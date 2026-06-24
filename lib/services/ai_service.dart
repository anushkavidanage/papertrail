/// Manages AI backend lifecycle: on-device (flutter_gemma) and cloud (Anthropic).
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_gemma_litertlm/flutter_gemma_litertlm.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/ai_model_config.dart';
import '../models/receipt.dart';

// ── Enums ────────────────────────────────────────────────────────────────────

enum AiStatus {
  /// Platform not supported (no flutter_gemma binary available).
  unavailable,

  /// User has not selected any backend yet.
  optedOut,

  /// Cloud backend selected but API key is missing.
  needsConfig,

  /// Downloading or loading a local model.
  loading,

  /// Ready to handle queries.
  ready,

  /// Unrecoverable error (check [AIService.error]).
  error,
}

enum BackendType { local, anthropic }

// ── Service ──────────────────────────────────────────────────────────────────

class AIService extends ChangeNotifier {
  AIService._();
  static final AIService instance = AIService._();

  // ── Prefs / secure-storage keys ──────────────────────────────────────────

  static const _backendKey = 'ai_backend';
  static const _activeModelKey = 'ai_active_model_id';
  static const _anthropicModelKey = 'ai_anthropic_model';
  static const _customModelsKey = 'ai_custom_models';
  static const _anthropicApiKey = 'ai_anthropic_key';

  static const _defaultAnthropicModel = 'claude-haiku-4-5-20251001';
  static const _defaultLocalModelId = 'Qwen3-0.6B.litertlm';

  /// Maximum receipts included in a single model context window.
  static const maxReceiptsForContext = 50;

  // ── State ─────────────────────────────────────────────────────────────────

  AiStatus _status = AiStatus.unavailable;
  AiStatus get status => _status;

  String? _error;
  String? get error => _error;

  double _downloadProgress = 0.0;
  double get downloadProgress => _downloadProgress;

  BackendType _backendType = BackendType.local;
  BackendType get backendType => _backendType;

  String _activeModelId = _defaultLocalModelId;
  String get activeModelId => _activeModelId;

  String _anthropicModel = _defaultAnthropicModel;
  String get anthropicModel => _anthropicModel;

  /// Combined list: built-in models first, then user-added custom ones.
  List<LocalModelConfig> _customModels = [];
  List<LocalModelConfig> get allLocalModels =>
      [...kBuiltInLocalModels, ..._customModels];

  InferenceModel? _model;

  // ── Available Anthropic models ────────────────────────────────────────────

  static const anthropicModels = [
    ('claude-opus-4-8', 'Claude Opus 4.8 — most capable'),
    ('claude-sonnet-4-6', 'Claude Sonnet 4.6 — balanced'),
    ('claude-haiku-4-5-20251001', 'Claude Haiku 4.5 — fast & affordable'),
  ];

  // ── Platform support ──────────────────────────────────────────────────────

  static bool get _platformSupported {
    if (kIsWeb) return false;
    return Platform.isAndroid ||
        Platform.isIOS ||
        Platform.isMacOS ||
        Platform.isWindows;
  }

  String get _windowsModelPath {
    final base = Platform.environment['LOCALAPPDATA'] ??
        '${Platform.environment['USERPROFILE']}\\AppData\\Local';
    return '$base\\flutter_gemma\\$_activeModelId';
  }

  // ── Initialisation ────────────────────────────────────────────────────────

  /// Called once from [main] before [runApp].
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
    final backendStr = prefs.getString(_backendKey);

    if (backendStr == null) {
      _status = AiStatus.optedOut;
      notifyListeners();
      return;
    }

    _backendType = BackendType.values.firstWhere(
      (b) => b.name == backendStr,
      orElse: () => BackendType.local,
    );
    _activeModelId =
        prefs.getString(_activeModelKey) ?? _defaultLocalModelId;
    _anthropicModel =
        prefs.getString(_anthropicModelKey) ?? _defaultAnthropicModel;
    _loadCustomModels(prefs);

    await _activateBackend();
  }

  Future<void> _activateBackend() async {
    switch (_backendType) {
      case BackendType.local:
        await _loadLocalModel();
      case BackendType.anthropic:
        final key = await _readApiKey();
        if (key.isEmpty) {
          _status = AiStatus.needsConfig;
        } else {
          _status = AiStatus.ready;
          _error = null;
        }
        notifyListeners();
    }
  }

  // ── Enable / disable ──────────────────────────────────────────────────────

  /// Select local backend and download + load [modelId].
  Future<void> enableLocalBackend({String? modelId}) async {
    _model = null;
    _backendType = BackendType.local;
    _activeModelId = modelId ?? _activeModelId;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_backendKey, BackendType.local.name);
    await prefs.setString(_activeModelKey, _activeModelId);
    await _loadLocalModel();
  }

  /// Select Anthropic backend with the given [apiKey] and [model].
  Future<void> enableAnthropicBackend({
    required String apiKey,
    String? model,
  }) async {
    _model = null;
    _backendType = BackendType.anthropic;
    if (model != null) _anthropicModel = model;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_backendKey, BackendType.anthropic.name);
    await prefs.setString(_anthropicModelKey, _anthropicModel);
    await _saveApiKey(apiKey);
    _status = apiKey.isEmpty ? AiStatus.needsConfig : AiStatus.ready;
    _error = null;
    notifyListeners();
  }

  /// Change active Anthropic model without re-entering the key.
  Future<void> setAnthropicModel(String model) async {
    _anthropicModel = model;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_anthropicModelKey, model);
    notifyListeners();
  }

  /// Switch to a different local model (downloads if needed).
  Future<void> switchLocalModel(String modelId) async {
    if (_activeModelId == modelId &&
        _backendType == BackendType.local &&
        _status == AiStatus.ready) {
      return;
    }
    _model = null;
    _activeModelId = modelId;
    _backendType = BackendType.local;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_backendKey, BackendType.local.name);
    await prefs.setString(_activeModelKey, modelId);
    await _loadLocalModel();
  }

  /// Completely opt out: forget the selected backend.
  Future<void> disableAI() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_backendKey);
    _model = null;
    if (_backendType == BackendType.local) {
      try {
        await FlutterGemma.uninstallModel(_activeModelId);
      } catch (_) {}
      if (Platform.isWindows) {
        try {
          await File(_windowsModelPath).delete();
        } catch (_) {}
      }
    }
    _status = AiStatus.optedOut;
    _error = null;
    notifyListeners();
  }

  // ── Custom model management ───────────────────────────────────────────────

  Future<void> addCustomModel(LocalModelConfig config) async {
    _customModels = [..._customModels, config];
    await _persistCustomModels();
    notifyListeners();
  }

  Future<void> removeCustomModel(String modelId) async {
    _customModels = _customModels.where((m) => m.id != modelId).toList();
    await _persistCustomModels();
    notifyListeners();
  }

  /// Delete an installed local model from device storage.
  Future<void> deleteLocalModel(String modelId) async {
    try {
      await FlutterGemma.uninstallModel(modelId);
    } catch (_) {}
    if (Platform.isWindows) {
      try {
        final base = Platform.environment['LOCALAPPDATA'] ??
            '${Platform.environment['USERPROFILE']}\\AppData\\Local';
        await File('$base\\flutter_gemma\\$modelId').delete();
      } catch (_) {}
    }
    if (_activeModelId == modelId && _status == AiStatus.ready) {
      _model = null;
      _status = AiStatus.optedOut;
      notifyListeners();
    }
  }

  Future<bool> isModelInstalled(String modelId) async {
    try {
      return await FlutterGemma.isModelInstalled(modelId);
    } catch (_) {
      return false;
    }
  }

  // ── Local model download / load ───────────────────────────────────────────

  Future<void> _loadLocalModel() async {
    _status = AiStatus.loading;
    _downloadProgress = 0.0;
    notifyListeners();
    try {
      if (!await FlutterGemma.isModelInstalled(_activeModelId)) {
        if (Platform.isWindows) {
          await _installModelWindows();
        } else {
          final config = _getModelConfig(_activeModelId);
          await FlutterGemma.installModel(
            modelType: config.modelType,
            fileType: config.fileType,
          )
              .fromNetwork(config.url)
              .withProgress((p) {
                _downloadProgress = p / 100.0;
                notifyListeners();
              })
              .install();
        }
      }
      _model = await FlutterGemma.getActiveModel(maxTokens: 8192);
      _status = AiStatus.ready;
      _error = null;
    } catch (e) {
      _status = AiStatus.error;
      _error = e.toString();
    }
    notifyListeners();
  }

  Future<void> _installModelWindows() async {
    final config = _getModelConfig(_activeModelId);
    final path = _windowsModelPath;
    await File(path).parent.create(recursive: true);
    await _streamDownload(config.url, path);
    await FlutterGemma.installModel(
      modelType: config.modelType,
      fileType: config.fileType,
    )
        .fromFile(path)
        .install();
  }

  Future<void> _streamDownload(String url, String destPath) async {
    final client = HttpClient();
    try {
      final request = await client.getUrl(Uri.parse(url));
      final response = await request.close();
      final total = response.contentLength;
      var received = 0;
      final sink = File(destPath).openWrite();
      try {
        await for (final chunk in response) {
          sink.add(chunk);
          received += chunk.length;
          if (total > 0) {
            _downloadProgress = received / total;
            notifyListeners();
          }
        }
      } finally {
        await sink.close();
      }
    } finally {
      client.close();
    }
  }

  LocalModelConfig _getModelConfig(String modelId) {
    return allLocalModels.firstWhere(
      (m) => m.id == modelId,
      orElse: () => throw Exception(
          'No config found for model "$modelId". Add it via addCustomModel().'),
    );
  }

  // ── Receipt context helpers ───────────────────────────────────────────────

  String _receiptContext(List<Receipt> receipts) {
    final sorted = [...receipts]
      ..sort((a, b) => b.purchaseDate.compareTo(a.purchaseDate));
    return sorted.take(maxReceiptsForContext).map((r) {
      final d = r.purchaseDate;
      final date = _isoDate(d);
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

  // ── Public AI API ─────────────────────────────────────────────────────────

  Future<List<Receipt>> searchReceipts(
      String query, List<Receipt> receipts) async {
    if (_status != AiStatus.ready) return [];
    return switch (_backendType) {
      BackendType.local => _localSearch(query, receipts),
      BackendType.anthropic => _anthropicSearch(query, receipts),
    };
  }

  Stream<String> chatInsights(String query, List<Receipt> receipts) {
    if (_status != AiStatus.ready) return const Stream.empty();
    return switch (_backendType) {
      BackendType.local => _localChatInsights(query, receipts),
      BackendType.anthropic => _anthropicChatInsights(query, receipts),
    };
  }

  void clearInsightHistory() => notifyListeners();

  // ── Local backend — search ────────────────────────────────────────────────

  Future<List<Receipt>> _localSearch(
      String query, List<Receipt> receipts) async {
    if (_model == null) return [];
    try {
      final today = _isoDate(DateTime.now());
      final prompt = 'Today is $today.\n\n'
          'RECEIPTS:\n${_receiptContext(receipts)}\n\n'
          'USER QUERY: $query\n\n'
          'Return the matching receipt IDs as a JSON array. /no_think\n\n'
          'Answer (JSON array only):';

      final chat = await _model!.openChat(
        systemInstruction: 'You are a receipt search assistant. '
            'Given receipts and a user query, return ONLY a JSON array of '
            'matching receipt ID strings. If nothing matches, return []. '
            'Output JSON only.',
        topK: 1,
        temperature: 0.1,
        topP: 1.0,
        modelType: ModelType.qwen3,
      );
      await chat.addQuery(Message.text(text: prompt, isUser: true));

      final buf = StringBuffer();
      var prefix = '';
      var streaming = false;
      await for (final r in chat.generateChatResponseAsync()) {
        if (r is! TextResponse) continue;
        if (_isEos(r.token)) break;
        final token = r.token;
        if (!streaming) {
          prefix += token;
          final endIdx = prefix.indexOf('</think>');
          if (endIdx != -1) {
            streaming = true;
            buf.write(
                prefix.substring(endIdx + '</think>'.length).trimLeft());
            prefix = '';
          } else if (prefix.length >= 7 && !prefix.startsWith('<think>')) {
            streaming = true;
            buf.write(prefix);
            prefix = '';
          }
        } else {
          buf.write(token);
          if (buf.toString().contains(']')) break;
        }
      }
      if (prefix.isNotEmpty && !prefix.startsWith('<think>')) {
        buf.write(prefix);
      }

      final raw = _cleanModelOutput(buf.toString());
      final match = RegExp(r'\[[\s\S]*?\]').firstMatch(raw);
      if (match == null) return [];
      final ids =
          (jsonDecode(match.group(0)!) as List).cast<String>().toSet();
      return receipts.where((r) => ids.contains(r.id)).toList();
    } catch (_) {
      return [];
    }
  }

  // ── Local backend — insights (hybrid pipeline) ────────────────────────────

  Stream<String> _localChatInsights(
      String query, List<Receipt> receipts) async* {
    if (_model == null) return;
    try {
      final now = DateTime.now();
      final today = _isoDate(now);

      final filter = await _parseQueryIntent(query, receipts, now);

      final String dataContext;
      if (filter != null && filter.hasFilters) {
        final matched = _applyFilter(receipts, filter);
        dataContext = _buildResultContext(matched);
      } else {
        final n = receipts.length.clamp(0, maxReceiptsForContext);
        dataContext =
            'The user\'s receipts (most recent $n):\n${_receiptContext(receipts)}';
      }

      final chat = await _model!.openChat(
        systemInstruction: 'Today is $today. You are a personal spending '
            'assistant. Answer concisely and conversationally. '
            'Use exact currency codes.',
        temperature: 0.7,
        topK: 40,
        topP: 0.95,
        modelType: ModelType.qwen3,
      );

      final prompt = filter != null && filter.hasFilters
          ? 'User asked: "$query"\n\n'
              'Pre-computed data (do NOT recalculate these numbers):\n'
              '$dataContext\n\n'
              'Answer in 1-3 sentences. /no_think'
          : '$dataContext\n\nUser question: $query /no_think';

      await chat.addQuery(Message.text(text: prompt, isUser: true));

      var prefix = '';
      var streaming = false;
      await for (final r in chat.generateChatResponseAsync()) {
        if (r is! TextResponse) continue;
        if (_isEos(r.token)) break;
        final token = r.token;
        if (!streaming) {
          prefix += token;
          final endIdx = prefix.indexOf('</think>');
          if (endIdx != -1) {
            streaming = true;
            final after =
                prefix.substring(endIdx + '</think>'.length).trimLeft();
            prefix = '';
            if (after.isNotEmpty) yield after;
          } else if (prefix.length >= 7 && !prefix.startsWith('<think>')) {
            streaming = true;
            if (prefix.isNotEmpty) yield prefix;
            prefix = '';
          }
        } else {
          yield token;
        }
      }
      if (prefix.isNotEmpty && !prefix.startsWith('<think>')) {
        yield prefix;
      }
    } catch (_) {}
  }

  // ── Local backend — intent parsing ────────────────────────────────────────

  Future<_QueryFilter?> _parseQueryIntent(
    String query,
    List<Receipt> receipts,
    DateTime now,
  ) async {
    if (_model == null) return null;
    try {
      final today = _isoDate(now);
      final firstOfMonth =
          '${now.year}-${now.month.toString().padLeft(2, '0')}-01';
      final prevMonthStart = _isoDate(DateTime(now.year, now.month - 1, 1));
      final prevMonthEnd = _isoDate(DateTime(now.year, now.month, 0));
      final firstOfYear = '${now.year}-01-01';
      final minus7 = _isoDate(now.subtract(const Duration(days: 7)));
      final minus30 = _isoDate(now.subtract(const Duration(days: 30)));
      final minus90 = _isoDate(now.subtract(const Duration(days: 90)));

      final knownCats = receipts.expand((r) => r.categories).toSet().toList()
        ..sort();
      final catsHint = knownCats.isEmpty
          ? ''
          : '\nKnown categories: ${knownCats.join(', ')}';

      final prompt =
          'Today is $today. Extract a filter from the user\'s receipt question.\n'
          'Output ONLY a valid JSON object — no other text. /no_think\n\n'
          'Fields:\n'
          '  "dateFrom": "YYYY-MM-DD" or null\n'
          '  "dateTo":   "YYYY-MM-DD" or null\n'
          '  "categories": [] (category names, case-insensitive)\n'
          '  "keywords":   [] (words to match in title or vendor)\n'
          '  "operation":  "sum" | "count" | "list" | "average"\n\n'
          'Date shortcuts:\n'
          '  this month  → dateFrom="$firstOfMonth", dateTo="$today"\n'
          '  last month  → dateFrom="$prevMonthStart", dateTo="$prevMonthEnd"\n'
          '  this year   → dateFrom="$firstOfYear", dateTo="$today"\n'
          '  last week   → dateFrom="$minus7", dateTo="$today"\n'
          '  last 30d    → dateFrom="$minus30", dateTo="$today"\n'
          '  last 90d    → dateFrom="$minus90", dateTo="$today"'
          '$catsHint\n\n'
          'USER QUESTION: $query';

      final chat = await _model!.openChat(
        systemInstruction:
            'You extract structured JSON filters from questions about receipts.',
        topK: 1,
        temperature: 0.1,
        modelType: ModelType.qwen3,
      );
      await chat.addQuery(Message.text(text: prompt, isUser: true));

      final buf = StringBuffer();
      var pfx = '';
      var stm = false;
      await for (final r in chat.generateChatResponseAsync()) {
        if (r is! TextResponse) continue;
        if (_isEos(r.token)) break;
        final t = r.token;
        if (!stm) {
          pfx += t;
          final endIdx = pfx.indexOf('</think>');
          if (endIdx != -1) {
            stm = true;
            buf.write(pfx.substring(endIdx + '</think>'.length).trimLeft());
            pfx = '';
          } else if (pfx.length >= 7 && !pfx.startsWith('<think>')) {
            stm = true;
            buf.write(pfx);
            pfx = '';
          }
        } else {
          buf.write(t);
          if (buf.toString().contains('}')) break;
        }
      }
      if (pfx.isNotEmpty && !pfx.startsWith('<think>')) buf.write(pfx);

      final raw = _cleanModelOutput(buf.toString());
      final match = RegExp(r'\{[\s\S]*?\}').firstMatch(raw);
      if (match == null) return null;

      final json = jsonDecode(match.group(0)!) as Map<String, dynamic>;
      return _QueryFilter(
        dateFrom: _parseDate(json['dateFrom']),
        dateTo: _parseDate(json['dateTo']),
        categories: _toStringList(json['categories']),
        keywords: _toStringList(json['keywords']),
        operation: (json['operation'] as String?) ?? 'sum',
      );
    } catch (_) {
      return null;
    }
  }

  // ── Local backend — filter / aggregate ───────────────────────────────────

  List<Receipt> _applyFilter(List<Receipt> all, _QueryFilter filter) {
    return all.where((r) {
      if (filter.dateFrom != null &&
          r.purchaseDate.isBefore(filter.dateFrom!)) {
        return false;
      }
      if (filter.dateTo != null) {
        final end = DateTime(filter.dateTo!.year, filter.dateTo!.month,
            filter.dateTo!.day, 23, 59, 59);
        if (r.purchaseDate.isAfter(end)) return false;
      }
      if (filter.categories.isEmpty && filter.keywords.isEmpty) return true;
      final rCats = r.categories.map((c) => c.toLowerCase()).toSet();
      if (filter.categories.any((c) => rCats.contains(c.toLowerCase()))) {
        return true;
      }
      if (filter.keywords.isNotEmpty) {
        final text = '${r.title} ${r.vendor}'.toLowerCase();
        if (filter.keywords.any((k) => text.contains(k.toLowerCase()))) {
          return true;
        }
      }
      return false;
    }).toList();
  }

  String _buildResultContext(List<Receipt> matched) {
    if (matched.isEmpty) return 'No receipts matched the filter.';
    final totals = <String, double>{};
    for (final r in matched) {
      totals[r.currency] = (totals[r.currency] ?? 0.0) + r.amount;
    }
    final sb = StringBuffer();
    sb.writeln('Matched receipts: ${matched.length}');
    sb.writeln('Total: ${totals.entries.map((e) => '${e.key} ${e.value.toStringAsFixed(2)}').join(', ')}');
    for (final r in matched.take(10)) {
      final vendor = r.vendor.isNotEmpty ? ' (${r.vendor})' : '';
      sb.writeln(
          '  ${_isoDate(r.purchaseDate)}  ${r.currency} ${r.amount.toStringAsFixed(2)}  "${r.title}"$vendor');
    }
    if (matched.length > 10) {
      sb.writeln('  … and ${matched.length - 10} more');
    }
    return sb.toString().trim();
  }

  // ── Anthropic backend — search ────────────────────────────────────────────

  Future<List<Receipt>> _anthropicSearch(
      String query, List<Receipt> receipts) async {
    try {
      final key = await _readApiKey();
      if (key.isEmpty) return [];

      final today = _isoDate(DateTime.now());
      final userMsg =
          'Today is $today.\n\nRECEIPTS:\n${_receiptContext(receipts)}\n\n'
          'USER QUERY: $query\n\nReturn matching receipt IDs as a JSON array.';

      final body = jsonEncode({
        'model': _anthropicModel,
        'max_tokens': 512,
        'system': 'You are a receipt search assistant. Return ONLY a JSON '
            'array of matching receipt ID strings. If nothing matches, '
            'return []. Output JSON only.',
        'messages': [
          {'role': 'user', 'content': userMsg}
        ],
      });

      final client = HttpClient();
      try {
        final request = await client
            .postUrl(Uri.parse('https://api.anthropic.com/v1/messages'));
        request.headers.set('x-api-key', key);
        request.headers.set('anthropic-version', '2023-06-01');
        request.headers.set('content-type', 'application/json');
        request.write(body);
        final response = await request.close();

        final responseBody =
            await response.transform(utf8.decoder).join();
        final json = jsonDecode(responseBody) as Map<String, dynamic>;

        if (response.statusCode != 200) {
          return [];
        }

        final content = (json['content'] as List).first as Map<String, dynamic>;
        final text = content['text'] as String? ?? '';
        final match = RegExp(r'\[[\s\S]*?\]').firstMatch(text);
        if (match == null) return [];
        final ids =
            (jsonDecode(match.group(0)!) as List).cast<String>().toSet();
        return receipts.where((r) => ids.contains(r.id)).toList();
      } finally {
        client.close();
      }
    } catch (_) {
      return [];
    }
  }

  // ── Anthropic backend — insights ──────────────────────────────────────────

  Stream<String> _anthropicChatInsights(
      String query, List<Receipt> receipts) async* {
    try {
      final key = await _readApiKey();
      if (key.isEmpty) return;

      final now = DateTime.now();
      final today = _isoDate(now);
      final n = receipts.length.clamp(0, maxReceiptsForContext);
      final context = _receiptContext(receipts.take(n).toList());

      final userMsg = 'My receipts (most recent $n):\n$context\n\n$query';

      final body = jsonEncode({
        'model': _anthropicModel,
        'max_tokens': 1024,
        'stream': true,
        'system': 'Today is $today. You are a personal spending assistant. '
            'Answer concisely and conversationally. Use exact currency codes.',
        'messages': [
          {'role': 'user', 'content': userMsg}
        ],
      });

      final client = HttpClient();
      try {
        final request = await client
            .postUrl(Uri.parse('https://api.anthropic.com/v1/messages'));
        request.headers.set('x-api-key', key);
        request.headers.set('anthropic-version', '2023-06-01');
        request.headers.set('content-type', 'application/json');
        request.write(body);
        final response = await request.close();

        if (response.statusCode != 200) {
          final errorBody = await response.transform(utf8.decoder).join();
          try {
            final err = jsonDecode(errorBody) as Map<String, dynamic>;
            yield 'Error: ${(err['error'] as Map?)?['message'] ?? errorBody}';
          } catch (_) {
            yield 'Error: HTTP ${response.statusCode}';
          }
          return;
        }

        // Parse Server-Sent Events.
        await for (final line in response
            .transform(utf8.decoder)
            .transform(const LineSplitter())) {
          if (!line.startsWith('data: ')) continue;
          final data = line.substring(6);
          try {
            final json = jsonDecode(data) as Map<String, dynamic>;
            final type = json['type'] as String?;
            if (type == 'content_block_delta') {
              final delta = json['delta'] as Map<String, dynamic>?;
              if (delta?['type'] == 'text_delta') {
                final text = delta!['text'] as String? ?? '';
                if (text.isNotEmpty) yield text;
              }
            } else if (type == 'message_stop') {
              break;
            }
          } catch (_) {}
        }
      } finally {
        client.close();
      }
    } catch (_) {}
  }

  // ── API key secure storage ────────────────────────────────────────────────

  static const _secureStorage = FlutterSecureStorage();

  Future<String> _readApiKey() async {
    try {
      return await _secureStorage.read(key: _anthropicApiKey) ?? '';
    } catch (_) {
      return '';
    }
  }

  Future<void> _saveApiKey(String key) async {
    try {
      if (key.isEmpty) {
        await _secureStorage.delete(key: _anthropicApiKey);
      } else {
        await _secureStorage.write(key: _anthropicApiKey, value: key);
      }
    } catch (_) {}
  }

  /// Reads the stored Anthropic key (for pre-populating the settings field).
  Future<String> readAnthropicKey() => _readApiKey();

  // ── Custom model persistence ──────────────────────────────────────────────

  void _loadCustomModels(SharedPreferences prefs) {
    final raw = prefs.getString(_customModelsKey);
    if (raw == null) return;
    try {
      final list = jsonDecode(raw) as List;
      _customModels = list
          .map((e) => LocalModelConfig.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {}
  }

  Future<void> _persistCustomModels() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _customModelsKey,
      jsonEncode(_customModels.map((m) => m.toJson()).toList()),
    );
  }

  // ── Utilities ─────────────────────────────────────────────────────────────

  static String _isoDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static DateTime? _parseDate(Object? v) =>
      v == null ? null : DateTime.tryParse(v.toString());

  static List<String> _toStringList(Object? v) =>
      (v as List?)?.map((e) => e.toString()).toList() ?? [];

  static bool _isEos(String token) =>
      token.contains('<|endoftext|>') || token.contains('<|im_end|>');

  static String _cleanModelOutput(String raw) {
    var t = raw;
    t = t.replaceAll(RegExp(r'<think>[\s\S]*?</think>'), '');
    t = t.replaceAll(RegExp(r'<think>[\s\S]*$'), '');
    t = t.replaceAll('</think>', '');
    t = t.replaceAll('<|endoftext|>', '');
    t = t.replaceAll('<|im_end|>', '');
    t = t.replaceAll('<|im_start|>', '');
    return t.trim();
  }

  @override
  void dispose() {
    _model = null;
    super.dispose();
  }
}

// ── Query filter value type ───────────────────────────────────────────────────

class _QueryFilter {
  const _QueryFilter({
    this.dateFrom,
    this.dateTo,
    this.categories = const [],
    this.keywords = const [],
    this.operation = 'sum',
  });

  final DateTime? dateFrom;
  final DateTime? dateTo;
  final List<String> categories;
  final List<String> keywords;
  final String operation;

  bool get hasFilters =>
      dateFrom != null ||
      dateTo != null ||
      categories.isNotEmpty ||
      keywords.isNotEmpty;
}
