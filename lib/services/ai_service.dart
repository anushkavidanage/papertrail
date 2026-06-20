/// Manages on-device AI model lifecycle for receipt search and spending insights.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_gemma_litertlm/flutter_gemma_litertlm.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/receipt.dart';

enum AiStatus { unavailable, optedOut, loading, ready, error }

class AIService extends ChangeNotifier {
  AIService._();
  static final AIService instance = AIService._();

  static const _optInKey = 'ai_opted_in';
  static const _modelUrl =
      'https://huggingface.co/litert-community/Qwen3-0.6B/resolve/main/Qwen3-0.6B.litertlm';
  static const _modelId = 'Qwen3-0.6B.litertlm';

  /// Maximum number of receipts included in a single model context window.
  static const maxReceiptsForContext = 50;

  AiStatus _status = AiStatus.unavailable;
  AiStatus get status => _status;

  String? _error;
  String? get error => _error;

  double _downloadProgress = 0.0;
  double get downloadProgress => _downloadProgress;

  InferenceModel? _model;
  InferenceChat? _insightChat;

  /// LiteRT-LM supports Android/iOS/macOS. Windows is excluded because
  /// background_downloader's Task.split() mismaps the absolute
  /// %LOCALAPPDATA%\flutter_gemma path on Windows, leaving the model file
  /// at an unexpected location so getActiveModel() always fails.
  static bool get _platformSupported {
    if (kIsWeb) return false;
    return Platform.isAndroid || Platform.isIOS || Platform.isMacOS;
  }

  /// Call once from [main] before [runApp]. No-ops on unsupported platforms
  /// or when the user has not opted in; does not download the model.
  Future<void> init() async {
    if (!_platformSupported) {
      _status = AiStatus.unavailable;
      notifyListeners();
      return;
    }
    try {
      await FlutterGemma.initialize(
        inferenceEngines: const [LiteRtLmEngine()],
      );
    } catch (_) {
      _status = AiStatus.unavailable;
      notifyListeners();
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_optInKey) != true) {
      _status = AiStatus.optedOut;
      notifyListeners();
      return;
    }
    await _loadModel();
  }

  /// Stores the opt-in preference and begins model download + load.
  Future<void> enableAI() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_optInKey, true);
    await _loadModel();
  }

  /// Uninstalls the model from device storage and resets to opt-out state.
  Future<void> disableAI() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_optInKey, false);
    _insightChat = null;
    _model = null;
    try {
      await FlutterGemma.uninstallModel(_modelId);
    } catch (_) {}
    _status = AiStatus.optedOut;
    _error = null;
    notifyListeners();
  }

  Future<void> _loadModel() async {
    _status = AiStatus.loading;
    _downloadProgress = 0.0;
    notifyListeners();
    try {
      if (!await FlutterGemma.isModelInstalled(_modelId)) {
        await FlutterGemma.installModel(
          modelType: ModelType.qwen3,
          fileType: ModelFileType.litertlm,
        )
            .fromNetwork(_modelUrl)
            .withProgress((p) {
              _downloadProgress = p / 100.0;
              notifyListeners();
            })
            .install();
      }
      _model = await FlutterGemma.getActiveModel(maxTokens: 2048);
      _status = AiStatus.ready;
      _error = null;
    } catch (e) {
      _status = AiStatus.error;
      _error = e.toString();
    }
    notifyListeners();
  }

  // Formats receipts as compact JSON lines for the model context.
  String _receiptContext(List<Receipt> receipts) {
    final sorted = [...receipts]
      ..sort((a, b) => b.purchaseDate.compareTo(a.purchaseDate));
    return sorted.take(maxReceiptsForContext).map((r) {
      final d = r.purchaseDate;
      final date =
          '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
      return jsonEncode({
        'id': r.id,
        'title': r.title,
        'amount': r.amount,
        'currency': r.currency,
        'date': date,
        if (r.vendor.isNotEmpty) 'vendor': r.vendor,
        if (r.categories.isNotEmpty) 'categories': r.categories,
        if (r.flags.isNotEmpty) 'flags': r.flags,
      });
    }).join('\n');
  }

  /// Natural-language receipt search. Returns matching receipts or [] on failure.
  Future<List<Receipt>> searchReceipts(
      String query, List<Receipt> receipts) async {
    if (_model == null) return [];
    try {
      final now = DateTime.now();
      final today =
          '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      final prompt = '''Today is $today. You are a receipt search assistant.
Return ONLY a JSON array of matching receipt IDs (the "id" field).
If no receipts match, return: []
Do not add any other text.

RECEIPTS:
${_receiptContext(receipts)}

USER QUERY: $query

MATCHING IDs:''';

      // Fresh one-shot chat; topK=1 for deterministic JSON output.
      final chat = await _model!.createChat(
        topK: 1,
        modelType: ModelType.qwen3,
      );
      await chat.addQuery(Message.text(text: prompt, isUser: true));

      final buf = StringBuffer();
      await for (final r in chat.generateChatResponseAsync()) {
        if (r is TextResponse) buf.write(r.token);
      }

      final raw = buf.toString().trim();
      final match = RegExp(r'\[.*?\]', dotAll: true).firstMatch(raw);
      if (match == null) return [];
      final ids =
          (jsonDecode(match.group(0)!) as List).cast<String>().toSet();
      return receipts.where((r) => ids.contains(r.id)).toList();
    } catch (_) {
      return [];
    }
  }

  /// Spending insights chat. Streams response tokens; maintains history across
  /// calls until [clearInsightHistory] is called.
  Stream<String> chatInsights(String query, List<Receipt> receipts) async* {
    if (_model == null) return;
    try {
      if (_insightChat == null) {
        final now = DateTime.now();
        final today =
            '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
        final n = receipts.length.clamp(0, maxReceiptsForContext);
        final sysInstruction =
            'Today is $today. You are a personal spending assistant. '
            'Answer questions conversationally and concisely. Use exact currency codes. '
            'The user\'s receipts (most recent $n):\n${_receiptContext(receipts)}';
        // openChat creates an independent session, unaffected by search queries.
        _insightChat = await _model!.openChat(
          systemInstruction: sysInstruction,
          temperature: 0.7,
          topK: 40,
          topP: 0.95,
          modelType: ModelType.qwen3,
        );
      }
      await _insightChat!.addQuery(Message.text(text: query, isUser: true));
      await for (final r in _insightChat!.generateChatResponseAsync()) {
        if (r is TextResponse) yield r.token;
      }
    } catch (_) {}
  }

  /// Clears the insights conversation history so the next query starts fresh.
  void clearInsightHistory() {
    _insightChat = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _insightChat = null;
    _model = null;
    super.dispose();
  }
}
