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

  /// LiteRT-LM has no Linux binary as of flutter_gemma_litertlm 1.0.x.
  static bool get _platformSupported {
    if (kIsWeb) return false;
    return Platform.isAndroid ||
        Platform.isIOS ||
        Platform.isMacOS ||
        Platform.isWindows;
  }

  /// Where flutter_gemma stores models on Windows.
  String get _windowsModelPath {
    final base = Platform.environment['LOCALAPPDATA'] ??
        '${Platform.environment['USERPROFILE']}\\AppData\\Local';
    return '$base\\flutter_gemma\\$_modelId';
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
    _model = null;
    try {
      await FlutterGemma.uninstallModel(_modelId);
    } catch (_) {}
    // On Windows the model was registered via .fromFile() so uninstallModel
    // removes the metadata but not the file itself — delete it manually.
    if (Platform.isWindows) {
      try {
        await File(_windowsModelPath).delete();
      } catch (_) {}
    }
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
        if (Platform.isWindows) {
          // background_downloader mismaps absolute Windows paths; download
          // the model ourselves directly to the expected directory instead.
          await _installModelWindows();
        } else {
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
    final modelPath = _windowsModelPath;
    await File(modelPath).parent.create(recursive: true);
    await _streamDownload(_modelUrl, modelPath);
    await FlutterGemma.installModel(
      modelType: ModelType.qwen3,
      fileType: ModelFileType.litertlm,
    )
        .fromFile(modelPath)
        .install();
  }

  /// Stream-downloads [url] to [destPath] and updates [_downloadProgress].
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
      final today = _isoDate(now);
      final prompt = 'Today is $today.\n\n'
          'RECEIPTS:\n${_receiptContext(receipts)}\n\n'
          'USER QUERY: $query\n\n'
          'Return the matching receipt IDs as a JSON array. /no_think\n\n'
          'Answer (JSON array only):';

      // Use openChat for proper system-instruction separation and temperature
      // control. createChat (shared session, no topP) lets thinking blocks run
      // indefinitely and never terminates the stream reliably.
      final chat = await _model!.openChat(
        systemInstruction:
            'You are a receipt search assistant. '
            'Given a list of receipts and a user query, return ONLY a JSON '
            'array of matching receipt ID strings. '
            'If nothing matches, return []. Output JSON only, no other text.',
        topK: 1,
        temperature: 0.1,
        topP: 1.0,
        modelType: ModelType.qwen3,
      );
      await chat.addQuery(Message.text(text: prompt, isUser: true));

      // Collect response with thinking-block suppression (same pattern as
      // chatInsights) and early exit once the JSON array is complete.
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
          // Stop as soon as the JSON array is closed.
          if (buf.toString().contains(']')) break;
        }
      }
      // Flush any prefix that EOS fired before the 7-char threshold was hit.
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

  /// Hybrid spending-insights pipeline.
  ///
  /// Step 1 — model parses the query into a structured [_QueryFilter] (JSON).
  /// Step 2 — Dart filters and aggregates receipts accurately.
  /// Step 3 — model formats the pre-computed numbers into a natural reply.
  ///
  /// Falls back to passing full receipt context when intent parsing returns no
  /// meaningful filter (open-ended questions, comparison queries, etc.).
  Stream<String> chatInsights(String query, List<Receipt> receipts) async* {
    if (_model == null) return;
    try {
      final now = DateTime.now();
      final today = _isoDate(now);

      // ── Stage 1: parse intent ──────────────────────────────────────────────
      final filter = await _parseQueryIntent(query, receipts, now);

      // ── Stage 2: compute answer data in Dart ──────────────────────────────
      final String dataContext;
      if (filter != null && filter.hasFilters) {
        final matched = _applyFilter(receipts, filter);
        dataContext = _buildResultContext(matched);
      } else {
        // Open-ended query – give the model the raw receipt list.
        final n = receipts.length.clamp(0, maxReceiptsForContext);
        dataContext =
            'The user\'s receipts (most recent $n):\n${_receiptContext(receipts)}';
      }

      // ── Stage 3: generate the natural-language answer ─────────────────────
      final sysInstruction =
          'Today is $today. You are a personal spending assistant. '
          'Answer concisely and conversationally. Use exact currency codes.';
      final chat = await _model!.openChat(
        systemInstruction: sysInstruction,
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
          : '$dataContext\n\n'
            'User question: $query /no_think';

      await chat.addQuery(Message.text(text: prompt, isUser: true));

      // Stream with Qwen3 thinking-block suppression.
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
      // Flush any prefix that EOS fired before the 7-char threshold was hit.
      if (prefix.isNotEmpty && !prefix.startsWith('<think>')) {
        yield prefix;
      }
    } catch (_) {}
  }

  // ── Intent parsing ──────────────────────────────────────────────────────────

  /// Asks the model to extract a [_QueryFilter] from [query]. Returns null when
  /// the JSON output cannot be parsed or has no usable constraints.
  Future<_QueryFilter?> _parseQueryIntent(
    String query,
    List<Receipt> receipts,
    DateTime now,
  ) async {
    if (_model == null) return null;
    try {
      final today = _isoDate(now);

      // Pre-compute all common date ranges so the model only has to pattern-match.
      final firstOfMonth =
          '${now.year}-${now.month.toString().padLeft(2, '0')}-01';
      final prevMonthStart =
          _isoDate(DateTime(now.year, now.month - 1, 1));
      final prevMonthEnd =
          _isoDate(DateTime(now.year, now.month, 0)); // day 0 = last of prev
      final firstOfYear = '${now.year}-01-01';
      final minus7 = _isoDate(now.subtract(const Duration(days: 7)));
      final minus30 = _isoDate(now.subtract(const Duration(days: 30)));
      final minus90 = _isoDate(now.subtract(const Duration(days: 90)));

      // Include the known category names so the model can match user vocabulary.
      final knownCats = receipts
          .expand((r) => r.categories)
          .toSet()
          .toList()
        ..sort();
      final catsHint = knownCats.isEmpty
          ? ''
          : '\nKnown categories in this user\'s data: ${knownCats.join(', ')}';

      final prompt =
          'Today is $today. Extract a filter from the user\'s receipt question.\n'
          'Output ONLY a valid JSON object — no other text. /no_think\n\n'
          'JSON fields:\n'
          '  "dateFrom": "YYYY-MM-DD" or null\n'
          '  "dateTo":   "YYYY-MM-DD" or null\n'
          '  "categories": [] (category names to match, case-insensitive)\n'
          '  "keywords":   [] (words to search in receipt title or vendor)\n'
          '  "operation":  "sum" | "count" | "list" | "average"\n\n'
          'Date shortcuts (use these exact values):\n'
          '  "this month"      → dateFrom="$firstOfMonth", dateTo="$today"\n'
          '  "last month"      → dateFrom="$prevMonthStart", dateTo="$prevMonthEnd"\n'
          '  "this year"       → dateFrom="$firstOfYear", dateTo="$today"\n'
          '  "last week"       → dateFrom="$minus7", dateTo="$today"\n'
          '  "last 30 days"    → dateFrom="$minus30", dateTo="$today"\n'
          '  "last quarter"    → dateFrom="$minus90", dateTo="$today"'
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
          // Stop as soon as the JSON object is closed.
          if (buf.toString().contains('}')) break;
        }
      }
      // Flush any prefix that EOS fired before the 7-char threshold was hit.
      if (pfx.isNotEmpty && !pfx.startsWith('<think>')) {
        buf.write(pfx);
      }

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

  // ── Dart-side filtering and aggregation ────────────────────────────────────

  List<Receipt> _applyFilter(List<Receipt> all, _QueryFilter filter) {
    return all.where((r) {
      // Date range (inclusive on both ends, covers the full day).
      if (filter.dateFrom != null && r.purchaseDate.isBefore(filter.dateFrom!)) {
        return false;
      }
      if (filter.dateTo != null) {
        final endOfDay = DateTime(filter.dateTo!.year, filter.dateTo!.month,
            filter.dateTo!.day, 23, 59, 59);
        if (r.purchaseDate.isAfter(endOfDay)) return false;
      }

      // If no category/keyword constraint, date-only filter passes all.
      if (filter.categories.isEmpty && filter.keywords.isEmpty) return true;

      // Category match (case-insensitive).
      final rCats = r.categories.map((c) => c.toLowerCase()).toSet();
      if (filter.categories.any((c) => rCats.contains(c.toLowerCase()))) {
        return true;
      }

      // Keyword match in title + vendor.
      if (filter.keywords.isNotEmpty) {
        final text = '${r.title} ${r.vendor}'.toLowerCase();
        if (filter.keywords.any((k) => text.contains(k.toLowerCase()))) {
          return true;
        }
      }

      return false;
    }).toList();
  }

  /// Builds a plain-text summary of [matched] receipts for the model to narrate.
  String _buildResultContext(List<Receipt> matched) {
    if (matched.isEmpty) return 'No receipts matched the filter.';

    // Totals per currency (exact Dart arithmetic).
    final totals = <String, double>{};
    for (final r in matched) {
      totals[r.currency] = (totals[r.currency] ?? 0.0) + r.amount;
    }

    final sb = StringBuffer();
    sb.writeln('Matched receipts: ${matched.length}');
    sb.writeln(
      'Total: ${totals.entries.map((e) => '${e.key} ${e.value.toStringAsFixed(2)}').join(', ')}',
    );

    // List up to 10 individual receipts for the model to reference.
    final preview = matched.take(10).toList();
    for (final r in preview) {
      final d = r.purchaseDate;
      final date = _isoDate(d);
      final vendor = r.vendor.isNotEmpty ? ' (${r.vendor})' : '';
      sb.writeln(
          '  $date  ${r.currency} ${r.amount.toStringAsFixed(2)}  "${r.title}"$vendor');
    }
    if (matched.length > 10) {
      sb.writeln('  … and ${matched.length - 10} more receipts');
    }

    return sb.toString().trim();
  }

  // ── Utilities ───────────────────────────────────────────────────────────────

  static String _isoDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static DateTime? _parseDate(Object? v) =>
      v == null ? null : DateTime.tryParse(v.toString());

  static List<String> _toStringList(Object? v) =>
      (v as List?)?.map((e) => e.toString()).toList() ?? [];

  /// True when [token] is an end-of-sequence or structural special token that
  /// should stop streaming (Qwen3 / LiteRT-LM variants).
  static bool _isEos(String token) =>
      token.contains('<|endoftext|>') || token.contains('<|im_end|>');

  /// Strips Qwen3 thinking blocks and special tokens from a complete response.
  static String _cleanModelOutput(String raw) {
    var t = raw;
    // Remove complete <think>…</think> blocks.
    t = t.replaceAll(RegExp(r'<think>[\s\S]*?</think>'), '');
    // Remove unclosed <think> that runs to the end of the string.
    t = t.replaceAll(RegExp(r'<think>[\s\S]*$'), '');
    // Remove any stray closing tag.
    t = t.replaceAll('</think>', '');
    // Remove EOS / structural tokens.
    t = t.replaceAll('<|endoftext|>', '');
    t = t.replaceAll('<|im_end|>', '');
    t = t.replaceAll('<|im_start|>', '');
    return t.trim();
  }

  /// Signals the view to clear the displayed chat messages.
  void clearInsightHistory() {
    notifyListeners();
  }

  @override
  void dispose() {
    _model = null;
    super.dispose();
  }
}

// ── Value type for a parsed query filter ────────────────────────────────────

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

  /// True when the filter carries at least one meaningful constraint.
  bool get hasFilters =>
      dateFrom != null ||
      dateTo != null ||
      categories.isNotEmpty ||
      keywords.isNotEmpty;
}
