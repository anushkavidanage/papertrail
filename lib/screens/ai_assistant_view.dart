/// AI assistant: natural-language receipt search + spending insights chat.
library;

import 'package:flutter/material.dart';

import '../models/receipt.dart';
import '../services/ai_service.dart';
import '../services/receipt_store.dart';
import '../widgets/receipt_card.dart';
import 'receipt_detail_screen.dart';

class AIAssistantView extends StatefulWidget {
  const AIAssistantView({super.key});

  @override
  State<AIAssistantView> createState() => _AIAssistantViewState();
}

class _AIAssistantViewState extends State<AIAssistantView> {
  // 0 = Search, 1 = Insights
  int _tab = 0;

  // --- Search state ---
  final _searchCtrl = TextEditingController();
  bool _searching = false;
  List<Receipt>? _searchResults;
  String _lastQuery = '';

  // --- Insights state ---
  final _chatCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  final List<_ChatMessage> _messages = [];
  bool _chatStreaming = false;

  @override
  void dispose() {
    _searchCtrl.dispose();
    _chatCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  // ── Search ───────────────────────────────────────────────────────────────

  Future<void> _runSearch() async {
    final q = _searchCtrl.text.trim();
    if (q.isEmpty) return;
    setState(() {
      _searching = true;
      _searchResults = null;
      _lastQuery = q;
    });
    final receipts = ReceiptStore.instance.receipts;
    final results = await AIService.instance.searchReceipts(q, receipts);
    if (mounted) {
      setState(() {
        _searching = false;
        _searchResults = results;
      });
    }
  }

  void _openReceipt(Receipt r) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ReceiptDetailScreen(receiptId: r.id)),
    );
  }

  // ── Chat ─────────────────────────────────────────────────────────────────

  Future<void> _sendMessage() async {
    final q = _chatCtrl.text.trim();
    if (q.isEmpty || _chatStreaming) return;
    _chatCtrl.clear();

    setState(() {
      _messages.add(_ChatMessage(text: q, isUser: true));
      _messages.add(_ChatMessage(text: '', isUser: false));
      _chatStreaming = true;
    });
    _scrollToBottom();

    final receipts = ReceiptStore.instance.receipts;
    await for (final token in AIService.instance.chatInsights(q, receipts)) {
      if (!mounted) break;
      setState(() {
        _messages.last = _ChatMessage(
          text: _messages.last.text + token,
          isUser: false,
        );
      });
      _scrollToBottom();
    }
    if (mounted) setState(() => _chatStreaming = false);
  }

  void _clearChat() {
    AIService.instance.clearInsightHistory();
    setState(() => _messages.clear());
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

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AIService.instance,
      builder: (context, _) {
        final status = AIService.instance.status;
        return Column(
          children: [
            // Status overlays replace the main content when not ready.
            if (status == AiStatus.unavailable)
              Expanded(child: _UnavailableCard())
            else if (status == AiStatus.optedOut)
              Expanded(child: _OptInCard())
            else if (status == AiStatus.loading)
              Expanded(child: _LoadingCard())
            else if (status == AiStatus.error)
              Expanded(child: _ErrorCard())
            else ...[
              // Ready — show tab selector + content.
              Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 16.0, vertical: 10.0),
                child: SegmentedButton<int>(
                  segments: const [
                    ButtonSegment(
                      value: 0,
                      label: Text('Search'),
                      icon: Icon(Icons.search),
                    ),
                    ButtonSegment(
                      value: 1,
                      label: Text('Insights'),
                      icon: Icon(Icons.chat_outlined),
                    ),
                  ],
                  selected: {_tab},
                  onSelectionChanged: (s) => setState(() => _tab = s.first),
                ),
              ),
              Expanded(
                child: _tab == 0 ? _buildSearch() : _buildChat(),
              ),
            ],
          ],
        );
      },
    );
  }

  // ── Search tab ────────────────────────────────────────────────────────────

  Widget _buildSearch() {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchCtrl,
                  decoration: const InputDecoration(
                    hintText: 'e.g. "electronics over \$200 last quarter"',
                    prefixIcon: Icon(Icons.auto_awesome_outlined),
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  onSubmitted: (_) => _runSearch(),
                  textInputAction: TextInputAction.search,
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _searching ? null : _runSearch,
                child: const Text('Search'),
              ),
            ],
          ),
        ),
        if (_searching) const LinearProgressIndicator(),
        if (_searchResults != null)
          Expanded(
            child: _searchResults!.isEmpty
                ? Center(
                    child: Text(
                      'No matching receipts found for "$_lastQuery".',
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                      textAlign: TextAlign.center,
                    ),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 4),
                        child: Text(
                          'Found ${_searchResults!.length} '
                          '${_searchResults!.length == 1 ? 'receipt' : 'receipts'} '
                          'matching "$_lastQuery" · AI-powered, on-device',
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: scheme.onSurfaceVariant,
                                  ),
                        ),
                      ),
                      Expanded(
                        child: ListView.builder(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          itemCount: _searchResults!.length,
                          itemBuilder: (_, i) {
                            final r = _searchResults![i];
                            return ReceiptCard(
                              receipt: r,
                              onTap: () => _openReceipt(r),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
          ),
      ],
    );
  }

  // ── Chat tab ──────────────────────────────────────────────────────────────

  Widget _buildChat() {
    return Column(
      children: [
        // Clear button (top right)
        if (_messages.isNotEmpty)
          Align(
            alignment: Alignment.centerRight,
            child: Padding(
              padding: const EdgeInsets.only(right: 12),
              child: TextButton.icon(
                onPressed: _clearChat,
                icon: const Icon(Icons.delete_outline, size: 16),
                label: const Text('Clear conversation'),
              ),
            ),
          ),

        // Message list
        Expanded(
          child: _messages.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'Ask anything about your spending.\n\n'
                      'e.g. "How much did I spend on groceries last month?"',
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant,
                          ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : ListView.builder(
                  controller: _scrollCtrl,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 8),
                  itemCount: _messages.length,
                  itemBuilder: (_, i) => _ChatBubble(msg: _messages[i]),
                ),
        ),

        // Input row
        Padding(
          padding: EdgeInsets.only(
            left: 12,
            right: 12,
            top: 8,
            bottom: MediaQuery.of(context).viewInsets.bottom + 12,
          ),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _chatCtrl,
                  decoration: const InputDecoration(
                    hintText: 'Ask about your spending…',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  onSubmitted: (_) => _sendMessage(),
                  textInputAction: TextInputAction.send,
                  maxLines: 3,
                  minLines: 1,
                ),
              ),
              const SizedBox(width: 8),
              _chatStreaming
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : IconButton.filled(
                      onPressed: _sendMessage,
                      icon: const Icon(Icons.send),
                    ),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Status cards ─────────────────────────────────────────────────────────────

class _OptInCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: scheme.outlineVariant),
          ),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.auto_awesome_outlined,
                  size: 48,
                  color: scheme.primary,
                ),
                const SizedBox(height: 16),
                Text(
                  'Enable AI Assistant',
                  style: Theme.of(context).textTheme.titleLarge,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  'Natural language search and spending insights — powered '
                  'by Qwen3, running 100% on your device. No receipt data '
                  'ever leaves your phone.\n\n'
                  'Requires a one-time download of approximately 586 MB.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: () => AIService.instance.enableAI(),
                  child: const Text('Enable AI features'),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () {},
                  child: const Text('Not now'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LoadingCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final progress = AIService.instance.downloadProgress;
    final pct = (progress * 100).round();
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: scheme.outlineVariant),
          ),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.downloading_outlined,
                    size: 48, color: scheme.primary),
                const SizedBox(height: 16),
                Text('Downloading AI model…',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(
                  '${progress > 0 ? '$pct%' : 'Starting…'} · ~586 MB · runs fully on-device',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                ),
                const SizedBox(height: 16),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: progress > 0 ? progress : null,
                    minHeight: 8,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: scheme.errorContainer),
          ),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.error_outline, size: 48, color: scheme.error),
                const SizedBox(height: 16),
                Text('Could not load AI model',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                if (AIService.instance.error != null)
                  Text(
                    AIService.instance.error!,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                    textAlign: TextAlign.center,
                  ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: () => AIService.instance.enableAI(),
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _UnavailableCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: scheme.outlineVariant),
          ),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.devices_other_outlined,
                    size: 48, color: scheme.onSurfaceVariant),
                const SizedBox(height: 16),
                Text(
                  'AI features not available on this platform',
                  style: Theme.of(context).textTheme.titleMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'On-device AI requires Android, iOS, macOS, or Windows.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Chat bubble ───────────────────────────────────────────────────────────────

class _ChatMessage {
  final String text;
  final bool isUser;
  const _ChatMessage({required this.text, required this.isUser});
}

class _ChatBubble extends StatelessWidget {
  const _ChatBubble({required this.msg});
  final _ChatMessage msg;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isUser = msg.isUser;
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.8,
        ),
        decoration: BoxDecoration(
          color: isUser ? scheme.primaryContainer : scheme.surfaceContainerHigh,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isUser ? 16 : 4),
            bottomRight: Radius.circular(isUser ? 4 : 16),
          ),
        ),
        child: msg.text.isEmpty
            ? SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: scheme.onSurfaceVariant,
                ),
              )
            : Text(
                msg.text,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: isUser
                          ? scheme.onPrimaryContainer
                          : scheme.onSurface,
                    ),
              ),
      ),
    );
  }
}
