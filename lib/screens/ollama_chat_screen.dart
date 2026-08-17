/// Real-time chat with a locally running Ollama model.
///
/// Every request includes all the user's receipts as a JSON system prompt so
/// the model has full spending context. Thinking tokens (supported by Qwen3
/// via the Ollama `think` parameter) are displayed in a collapsible block
/// before the final answer.
///
/// Copyright (C) 2026, Anushka Vidanage
///
/// Licensed under the GNU General Public License, Version 3 (the "License");
///
/// License: https://opensource.org/license/gpl-3-0
//
// This program is free software: you can redistribute it and/or modify it under
// the terms of the GNU General Public License as published by the Free Software
// Foundation, either version 3 of the License, or (at your option) any later
// version.
//
// This program is distributed in the hope that it will be useful, but WITHOUT
// ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
// FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more
// details.
//
// You should have received a copy of the GNU General Public License along with
// this program.  If not, see <https://opensource.org/license/gpl-3-0>.
///
/// Authors: Anushka Vidanage

// Add the library directive as we have doc entries above. We publish the above
// meta doc lines in the docs.

library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

import 'package:markdown_tooltip/markdown_tooltip.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/receipt.dart';
import '../services/receipt_store.dart';

// ── Persistence keys ──────────────────────────────────────────────────────────

const _kBaseUrlKey = 'ollama_base_url';
const _kModelKey = 'ollama_model';
const _kDefaultUrl = 'http://localhost:11434';
const _kDefaultModel = 'qwen3.5:latest';

// ── Screen ────────────────────────────────────────────────────────────────────

class OllamaChatScreen extends StatefulWidget {
  const OllamaChatScreen({super.key});

  @override
  State<OllamaChatScreen> createState() => _OllamaChatScreenState();
}

class _OllamaChatScreenState extends State<OllamaChatScreen> {
  final _inputCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  final List<_Message> _messages = [];

  bool _isStreaming = false;
  String _baseUrl = _kDefaultUrl;
  String _model = _kDefaultModel;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  // ── Settings ────────────────────────────────────────────────────────────

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _baseUrl = prefs.getString(_kBaseUrlKey) ?? _kDefaultUrl;
        _model = prefs.getString(_kModelKey) ?? _kDefaultModel;
      });
    }
  }

  Future<void> _applySettings(String baseUrl, String model) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kBaseUrlKey, baseUrl);
    await prefs.setString(_kModelKey, model);
    setState(() {
      _baseUrl = baseUrl;
      _model = model;
    });
  }

  void _openSettings() {
    showDialog<void>(
      context: context,
      builder: (_) => _SettingsDialog(
        baseUrl: _baseUrl,
        model: _model,
        onSave: _applySettings,
      ),
    );
  }

  // ── Prompt construction ──────────────────────────────────────────────────

  String _systemPrompt(List<Receipt> receipts) {
    final now = DateTime.now();
    final today =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

    final sorted = [...receipts]
      ..sort((a, b) => b.purchaseDate.compareTo(a.purchaseDate));

    final rows = sorted.map((r) {
      final d = r.purchaseDate;
      final date =
          '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
      return {
        'id': r.id,
        'title': r.title,
        'amount': r.amount,
        'currency': r.currency,
        'date': date,
        if (r.vendor.isNotEmpty) 'vendor': r.vendor,
        if (r.categories.isNotEmpty) 'categories': r.categories,
        if (r.flags.isNotEmpty) 'flags': r.flags,
      };
    }).toList();

    return 'Today is $today. You are a personal spending assistant. '
        'Answer questions accurately and concisely based solely on the receipt '
        'data below. Use exact amounts and currency codes from the data.\n\n'
        'RECEIPTS (${rows.length} total):\n${jsonEncode(rows)}';
  }

  List<Map<String, String>> _buildHistory(
    String userInput,
    List<Receipt> receipts,
  ) {
    final msgs = <Map<String, String>>[
      {'role': 'system', 'content': _systemPrompt(receipts)},
    ];

    // Include prior turns so the model has conversation context.
    for (final m in _messages) {
      if (m.isUser) {
        msgs.add({'role': 'user', 'content': m.userText});
      } else if (m.responseText.isNotEmpty) {
        msgs.add({'role': 'assistant', 'content': m.responseText});
      }
    }

    msgs.add({'role': 'user', 'content': userInput});
    return msgs;
  }

  // ── Sending ──────────────────────────────────────────────────────────────

  Future<void> _send() async {
    final input = _inputCtrl.text.trim();
    if (input.isEmpty || _isStreaming) return;
    _inputCtrl.clear();

    final receipts = ReceiptStore.instance.receipts;
    final history = _buildHistory(input, receipts);

    setState(() {
      _messages.add(_Message.user(input));
      _messages.add(_Message.assistant());
      _isStreaming = true;
    });
    _scrollToBottom();

    HttpClient? client;
    try {
      client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
      final request = await client.postUrl(Uri.parse('$_baseUrl/api/chat'));
      request.headers.set('content-type', 'application/json');
      request.write(
        jsonEncode({
          'model': _model,
          'messages': history,
          'stream': true,
          'think': true,
        }),
      );
      final response = await request.close();

      if (response.statusCode != 200) {
        final body = await response.transform(utf8.decoder).join();
        _setError('HTTP ${response.statusCode}: $body');
        return;
      }

      await for (final line
          in response.transform(utf8.decoder).transform(const LineSplitter())) {
        if (line.isEmpty || !mounted) break;
        try {
          final json = jsonDecode(line) as Map<String, dynamic>;
          final msg = json['message'] as Map<String, dynamic>?;
          final thinking = msg?['thinking'] as String? ?? '';
          final content = msg?['content'] as String? ?? '';
          final done = json['done'] as bool? ?? false;

          setState(() {
            final last = _messages.last;
            if (thinking.isNotEmpty) {
              last.thinkingText += thinking;
              last.isThinking = true;
            }
            if (content.isNotEmpty) {
              last.isThinking = false;
              last.responseText += content;
            }
            if (done) {
              last.isStreaming = false;
              last.isThinking = false;
            }
          });
          _scrollToBottom();
        } catch (_) {}
      }
    } on SocketException catch (e) {
      _setError(
        'Cannot connect to Ollama at $_baseUrl.\n\n${e.message}\n\nMake sure Ollama is running.',
      );
    } on HttpException catch (e) {
      _setError('HTTP error: ${e.message}');
    } catch (e) {
      _setError(e.toString());
    } finally {
      client?.close();
      if (mounted) {
        setState(() {
          _isStreaming = false;
          if (_messages.isNotEmpty && !_messages.last.isUser) {
            final last = _messages.last;
            last.isStreaming = false;
            last.isThinking = false;
          }
        });
      }
    }
  }

  void _setError(String msg) {
    if (!mounted) return;
    setState(() {
      final last = _messages.last;
      last.responseText = msg;
      last.isStreaming = false;
      last.isThinking = false;
      _isStreaming = false;
    });
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
        );
      }
    });
  }

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        // ── Header ────────────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 4, 4),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_model, style: Theme.of(context).textTheme.titleSmall),
                    Text(
                      _baseUrl,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (_messages.isNotEmpty)
                MarkdownTooltip(
                  message: _isStreaming
                      ? '''

**Clear Conversation**

Unavailable while a reply is still streaming. Wait for it to finish.

'''
                      : '''

**Clear Conversation**

Discard the messages so far and start a fresh conversation.

''',
                  child: IconButton(
                    onPressed: _isStreaming
                        ? null
                        : () => setState(() => _messages.clear()),
                    icon: const Icon(Icons.delete_outline),
                  ),
                ),
              MarkdownTooltip(
                message: '''

**Ollama Settings**

Set the address of your Ollama server and choose which of its models to chat
with.

''',
                child: IconButton(
                  onPressed: _openSettings,
                  icon: const Icon(Icons.settings_outlined),
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1),

        // ── Message list ──────────────────────────────────────────────────
        Expanded(
          child: _messages.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.psychology_outlined,
                          size: 48,
                          color: scheme.onSurfaceVariant,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Chat with Ollama',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Ask anything about your receipts.\n'
                          'All receipt data is included in each request.',
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(color: scheme.onSurfaceVariant),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                )
              : ListView.builder(
                  controller: _scrollCtrl,
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                  itemCount: _messages.length,
                  itemBuilder: (_, i) => _MessageBubble(message: _messages[i]),
                ),
        ),

        // ── Input row ─────────────────────────────────────────────────────
        Padding(
          padding: EdgeInsets.only(
            left: 12,
            right: 12,
            top: 8,
            bottom: MediaQuery.of(context).viewInsets.bottom > 0
                ? MediaQuery.of(context).viewInsets.bottom + 12
                : 88,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: TextField(
                  controller: _inputCtrl,
                  decoration: const InputDecoration(
                    hintText: 'Ask about your receipts…',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  onSubmitted: (_) => _send(),
                  textInputAction: TextInputAction.send,
                  maxLines: 4,
                  minLines: 1,
                  enabled: !_isStreaming,
                ),
              ),
              const SizedBox(width: 8),
              _isStreaming
                  ? Padding(
                      padding: const EdgeInsets.all(12),
                      child: SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: scheme.primary,
                        ),
                      ),
                    )
                  : IconButton.filled(
                      onPressed: _send,
                      icon: const Icon(Icons.send),
                    ),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Message model ─────────────────────────────────────────────────────────────

class _Message {
  _Message.user(this.userText)
    : isUser = true,
      thinkingText = '',
      responseText = '',
      isThinking = false,
      isStreaming = false;

  _Message.assistant()
    : isUser = false,
      userText = '',
      thinkingText = '',
      responseText = '',
      isThinking = false,
      isStreaming = true;

  final bool isUser;
  final String userText;

  String thinkingText;
  String responseText;
  bool isThinking;
  bool isStreaming;
}

// ── Message bubble ────────────────────────────────────────────────────────────

class _MessageBubble extends StatefulWidget {
  const _MessageBubble({required this.message});
  final _Message message;

  @override
  State<_MessageBubble> createState() => _MessageBubbleState();
}

class _MessageBubbleState extends State<_MessageBubble> {
  // Auto-expanded while the model is thinking; user can collapse after.
  bool _showThinking = true;

  @override
  Widget build(BuildContext context) {
    final msg = widget.message;
    final scheme = Theme.of(context).colorScheme;

    // ── User bubble ───────────────────────────────────────────────────────
    if (msg.isUser) {
      return Align(
        alignment: Alignment.centerRight,
        child: Container(
          margin: const EdgeInsets.only(bottom: 12, left: 56),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: scheme.primaryContainer,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(16),
              topRight: Radius.circular(16),
              bottomLeft: Radius.circular(16),
              bottomRight: Radius.circular(4),
            ),
          ),
          child: Text(
            msg.userText,
            style: TextStyle(color: scheme.onPrimaryContainer),
          ),
        ),
      );
    }

    // ── Assistant bubble ──────────────────────────────────────────────────
    return Padding(
      padding: const EdgeInsets.only(bottom: 12, right: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Thinking block
          if (msg.thinkingText.isNotEmpty || msg.isThinking)
            _ThinkingBlock(
              text: msg.thinkingText,
              isActive: msg.isThinking,
              isExpanded: _showThinking,
              onToggle: () => setState(() => _showThinking = !_showThinking),
            ),

          // Response text
          if (msg.responseText.isNotEmpty) ...[
            if (msg.thinkingText.isNotEmpty) const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHigh,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(4),
                  topRight: Radius.circular(16),
                  bottomLeft: Radius.circular(16),
                  bottomRight: Radius.circular(16),
                ),
              ),
              child: Text(
                msg.responseText,
                style: TextStyle(color: scheme.onSurface),
              ),
            ),
          ] else if (msg.isStreaming && !msg.isThinking) ...[
            // Waiting for first response token after thinking completes.
            const SizedBox(height: 6),
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Thinking block ────────────────────────────────────────────────────────────

class _ThinkingBlock extends StatelessWidget {
  const _ThinkingBlock({
    required this.text,
    required this.isActive,
    required this.isExpanded,
    required this.onToggle,
  });

  final String text;
  final bool isActive;
  final bool isExpanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: scheme.outlineVariant.withAlpha(100),
          width: 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header — tap to expand/collapse (disabled while still thinking)
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: isActive ? null : onToggle,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    if (isActive) ...[
                      SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 1.5,
                          color: scheme.primary,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Thinking…',
                        style: TextStyle(
                          color: scheme.primary,
                          fontStyle: FontStyle.italic,
                          fontSize: 12.5,
                        ),
                      ),
                    ] else ...[
                      Icon(
                        Icons.psychology_outlined,
                        size: 15,
                        color: scheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        isExpanded ? 'Hide thinking' : 'Show thinking',
                        style: TextStyle(
                          color: scheme.onSurfaceVariant,
                          fontSize: 12.5,
                        ),
                      ),
                      const Spacer(),
                      Icon(
                        isExpanded ? Icons.expand_less : Icons.expand_more,
                        size: 16,
                        color: scheme.onSurfaceVariant,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),

          // Body — thinking text
          if ((isExpanded || isActive) && text.isNotEmpty)
            Container(
              constraints: const BoxConstraints(maxHeight: 260),
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: SingleChildScrollView(
                child: Text(
                  text,
                  style: TextStyle(
                    color: scheme.onSurfaceVariant,
                    fontSize: 11.5,
                    fontFamily: 'monospace',
                    height: 1.55,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ── Settings dialog ───────────────────────────────────────────────────────────

class _SettingsDialog extends StatefulWidget {
  const _SettingsDialog({
    required this.baseUrl,
    required this.model,
    required this.onSave,
  });

  final String baseUrl;
  final String model;
  final Future<void> Function(String baseUrl, String model) onSave;

  @override
  State<_SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<_SettingsDialog> {
  late final _urlCtrl = TextEditingController(text: widget.baseUrl);
  late final _modelCtrl = TextEditingController(text: widget.model);

  @override
  void dispose() {
    _urlCtrl.dispose();
    _modelCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Ollama Settings'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _urlCtrl,
            decoration: const InputDecoration(
              labelText: 'Base URL',
              hintText: 'http://localhost:11434',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            keyboardType: TextInputType.url,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _modelCtrl,
            decoration: const InputDecoration(
              labelText: 'Model',
              hintText: 'qwen3:latest',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Run `ollama list` to see available models.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            final url = _urlCtrl.text.trim();
            final model = _modelCtrl.text.trim();
            if (url.isNotEmpty && model.isNotEmpty) {
              widget.onSave(url, model);
              Navigator.pop(context);
            }
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}
