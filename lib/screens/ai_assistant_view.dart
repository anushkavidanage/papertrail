/// AI assistant: natural-language receipt search + spending insights chat.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_gemma/flutter_gemma.dart';

import '../models/ai_model_config.dart';
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
    if (mounted) {
      setState(() {
        _chatStreaming = false;
        if (_messages.isNotEmpty &&
            !_messages.last.isUser &&
            _messages.last.text.isEmpty) {
          _messages[_messages.length - 1] = const _ChatMessage(
            text: "Sorry, I couldn't generate a response. Please try again.",
            isUser: false,
          );
        }
      });
    }
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

  void _openSettings() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => const _AISettingsSheet(),
    );
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
            if (status == AiStatus.unavailable)
              Expanded(child: _UnavailableCard())
            else if (status == AiStatus.optedOut)
              Expanded(child: _OptInCard())
            else if (status == AiStatus.needsConfig)
              Expanded(child: _NeedsConfigCard(onConfigure: _openSettings))
            else if (status == AiStatus.loading)
              Expanded(child: _LoadingCard())
            else if (status == AiStatus.error)
              Expanded(child: _ErrorCard())
            else ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 4, 0),
                child: Row(
                  children: [
                    Expanded(
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
                        onSelectionChanged: (s) =>
                            setState(() => _tab = s.first),
                      ),
                    ),
                    IconButton(
                      onPressed: _openSettings,
                      icon: const Icon(Icons.settings_outlined),
                      tooltip: 'AI settings',
                    ),
                  ],
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
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
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
                          'matching "$_lastQuery" · AI-powered',
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

// ── Settings bottom sheet ─────────────────────────────────────────────────────

class _AISettingsSheet extends StatefulWidget {
  const _AISettingsSheet();

  @override
  State<_AISettingsSheet> createState() => _AISettingsSheetState();
}

class _AISettingsSheetState extends State<_AISettingsSheet>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  @override
  void initState() {
    super.initState();
    final initial = AIService.instance.backendType == BackendType.anthropic
        ? 1
        : 0;
    _tabs = TabController(length: 2, vsync: this, initialIndex: initial);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (_, controller) => Column(
        children: [
          // Handle bar
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: scheme.onSurfaceVariant.withAlpha(80),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Icon(Icons.auto_awesome_outlined, color: scheme.primary),
                const SizedBox(width: 8),
                Text('AI Settings',
                    style: Theme.of(context).textTheme.titleLarge),
              ],
            ),
          ),
          const SizedBox(height: 8),
          TabBar(
            controller: _tabs,
            tabs: const [
              Tab(icon: Icon(Icons.phone_android_outlined), text: 'Local Model'),
              Tab(icon: Icon(Icons.cloud_outlined), text: 'Anthropic Claude'),
            ],
          ),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: [
                _LocalModelTab(scrollController: controller),
                _AnthropicTab(scrollController: controller),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Local model tab ───────────────────────────────────────────────────────────

class _LocalModelTab extends StatefulWidget {
  const _LocalModelTab({required this.scrollController});
  final ScrollController scrollController;

  @override
  State<_LocalModelTab> createState() => _LocalModelTabState();
}

class _LocalModelTabState extends State<_LocalModelTab> {
  final _urlCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  bool _addingCustom = false;
  Map<String, bool> _installed = {};

  @override
  void initState() {
    super.initState();
    _checkInstalled();
  }

  @override
  void dispose() {
    _urlCtrl.dispose();
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _checkInstalled() async {
    final svc = AIService.instance;
    final results = <String, bool>{};
    for (final m in svc.allLocalModels) {
      results[m.id] = await svc.isModelInstalled(m.id);
    }
    if (mounted) setState(() => _installed = results);
  }

  Future<void> _selectModel(LocalModelConfig config) async {
    final nav = Navigator.of(context);
    await AIService.instance.switchLocalModel(config.id);
    if (mounted) {
      await _checkInstalled();
      nav.pop();
    }
  }

  Future<void> _deleteModel(LocalModelConfig config) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete model?'),
        content: Text(
            'Remove "${config.name}" (${config.sizeMb} MB) from this device?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed == true) {
      await AIService.instance.deleteLocalModel(config.id);
      if (config.isCustom) {
        await AIService.instance.removeCustomModel(config.id);
      }
      if (mounted) await _checkInstalled();
    }
  }

  Future<void> _addCustomModel() async {
    final url = _urlCtrl.text.trim();
    if (url.isEmpty) return;
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasAbsolutePath) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Invalid URL')),
      );
      return;
    }
    final filename = uri.pathSegments.lastWhere(
      (s) => s.endsWith('.litertlm'),
      orElse: () => '',
    );
    if (filename.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('URL must point to a .litertlm file')),
      );
      return;
    }
    final name =
        _nameCtrl.text.trim().isEmpty ? filename : _nameCtrl.text.trim();
    final config = LocalModelConfig(
      id: filename,
      name: name,
      description: 'Custom model',
      url: url,
      sizeMb: 0,
      modelType: ModelType.qwen3,
      fileType: ModelFileType.litertlm,
      isCustom: true,
    );
    await AIService.instance.addCustomModel(config);
    _urlCtrl.clear();
    _nameCtrl.clear();
    setState(() => _addingCustom = false);
    if (mounted) await _checkInstalled();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AIService.instance,
      builder: (context, _) {
        final svc = AIService.instance;
        final models = svc.allLocalModels;
        final activeId = svc.activeModelId;
        final isLocal = svc.backendType == BackendType.local;
        final scheme = Theme.of(context).colorScheme;

        return ListView(
          controller: widget.scrollController,
          padding: const EdgeInsets.all(16),
          children: [
            Text('Choose a model to run 100% on-device.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    )),
            const SizedBox(height: 12),
            ...models.map((m) {
              final isActive = isLocal && m.id == activeId;
              final isInstalled = _installed[m.id] ?? false;
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                color: isActive
                    ? scheme.primaryContainer.withAlpha(120)
                    : null,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 10),
                  child: Row(
                    children: [
                      // ignore: deprecated_member_use
                      Radio<String>(
                        value: m.id,
                        // ignore: deprecated_member_use
                        groupValue: isLocal ? activeId : null,
                        // ignore: deprecated_member_use
                        onChanged: (_) => _selectModel(m),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(m.name,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleSmall),
                                if (m.isCustom) ...[
                                  const SizedBox(width: 6),
                                  Chip(
                                    label: const Text('custom'),
                                    padding: EdgeInsets.zero,
                                    labelStyle: Theme.of(context)
                                        .textTheme
                                        .labelSmall,
                                    visualDensity: VisualDensity.compact,
                                  ),
                                ],
                              ],
                            ),
                            if (m.description.isNotEmpty)
                              Text(m.description,
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(
                                          color: scheme.onSurfaceVariant)),
                            if (m.sizeMb > 0)
                              Text('~${m.sizeMb} MB',
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(
                                          color: scheme.onSurfaceVariant)),
                          ],
                        ),
                      ),
                      if (isInstalled && !isActive)
                        IconButton(
                          icon: const Icon(Icons.delete_outline),
                          tooltip: 'Remove from device',
                          onPressed: () => _deleteModel(m),
                        ),
                      if (!isInstalled)
                        Text('Not downloaded',
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(color: scheme.onSurfaceVariant)),
                    ],
                  ),
                ),
              );
            }),
            const Divider(height: 24),
            // Custom model section
            if (!_addingCustom)
              OutlinedButton.icon(
                onPressed: () => setState(() => _addingCustom = true),
                icon: const Icon(Icons.add),
                label: const Text('Add custom model URL'),
              )
            else
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text('Add custom model',
                          style: Theme.of(context).textTheme.titleSmall),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _urlCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Model URL (.litertlm)',
                          hintText:
                              'https://huggingface.co/…/model.litertlm',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        keyboardType: TextInputType.url,
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _nameCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Display name (optional)',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: () =>
                                setState(() => _addingCustom = false),
                            child: const Text('Cancel'),
                          ),
                          const SizedBox(width: 8),
                          FilledButton(
                            onPressed: _addCustomModel,
                            child: const Text('Add'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

// ── Anthropic tab ─────────────────────────────────────────────────────────────

class _AnthropicTab extends StatefulWidget {
  const _AnthropicTab({required this.scrollController});
  final ScrollController scrollController;

  @override
  State<_AnthropicTab> createState() => _AnthropicTabState();
}

class _AnthropicTabState extends State<_AnthropicTab> {
  final _keyCtrl = TextEditingController();
  bool _obscure = true;
  String _selectedModel = AIService.instance.anthropicModel;
  bool _saving = false;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _loadKey();
  }

  @override
  void dispose() {
    _keyCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadKey() async {
    final key = await AIService.instance.readAnthropicKey();
    if (mounted) {
      setState(() {
        _keyCtrl.text = key;
        _loaded = true;
      });
    }
  }

  Future<void> _save() async {
    final nav = Navigator.of(context);
    setState(() => _saving = true);
    await AIService.instance.enableAnthropicBackend(
      apiKey: _keyCtrl.text.trim(),
      model: _selectedModel,
    );
    if (mounted) {
      setState(() => _saving = false);
      nav.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (!_loaded) {
      return const Center(child: CircularProgressIndicator());
    }
    return ListView(
      controller: widget.scrollController,
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'Use Claude via the Anthropic API. '
          'Your API key is stored securely on this device.',
          style: Theme.of(context)
              .textTheme
              .bodyMedium
              ?.copyWith(color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _keyCtrl,
          obscureText: _obscure,
          decoration: InputDecoration(
            labelText: 'Anthropic API key',
            hintText: 'sk-ant-…',
            border: const OutlineInputBorder(),
            prefixIcon: const Icon(Icons.key_outlined),
            suffixIcon: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: Icon(
                      _obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
                IconButton(
                  icon: const Icon(Icons.copy_outlined),
                  tooltip: 'Copy',
                  onPressed: () {
                    Clipboard.setData(
                        ClipboardData(text: _keyCtrl.text.trim()));
                    ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Copied')));
                  },
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        DropdownButtonFormField<String>(
          // ignore: deprecated_member_use
          value: _selectedModel,
          decoration: const InputDecoration(
            labelText: 'Model',
            border: OutlineInputBorder(),
          ),
          items: AIService.anthropicModels
              .map((pair) => DropdownMenuItem(
                    value: pair.$1,
                    child: Text(pair.$2),
                  ))
              .toList(),
          onChanged: (v) => setState(() => _selectedModel = v!),
        ),
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: _saving ? null : _save,
          icon: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.check),
          label: const Text('Save & use Anthropic Claude'),
        ),
        const SizedBox(height: 12),
        Text(
          'Requires an active Anthropic account. Receipts are sent to '
          'the Anthropic API to answer your questions.',
          style: Theme.of(context)
              .textTheme
              .bodySmall
              ?.copyWith(color: scheme.onSurfaceVariant),
          textAlign: TextAlign.center,
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
                Icon(Icons.auto_awesome_outlined,
                    size: 48, color: scheme.primary),
                const SizedBox(height: 16),
                Text('Enable AI Assistant',
                    style: Theme.of(context).textTheme.titleLarge,
                    textAlign: TextAlign.center),
                const SizedBox(height: 12),
                Text(
                  'Natural language search and spending insights.\n\n'
                  'Run 100% on-device with a local model, or connect your '
                  'Anthropic API key to use Claude.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: () =>
                      AIService.instance.enableLocalBackend(),
                  icon: const Icon(Icons.phone_android_outlined),
                  label: const Text('Use local model (free, private)'),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () => showModalBottomSheet(
                    context: context,
                    isScrollControlled: true,
                    useSafeArea: true,
                    shape: const RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.vertical(top: Radius.circular(20)),
                    ),
                    builder: (_) => const _AISettingsSheet(),
                  ),
                  icon: const Icon(Icons.cloud_outlined),
                  label: const Text('Configure Anthropic Claude'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NeedsConfigCard extends StatelessWidget {
  const _NeedsConfigCard({required this.onConfigure});
  final VoidCallback onConfigure;

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
                Icon(Icons.key_outlined, size: 48, color: scheme.primary),
                const SizedBox(height: 16),
                Text('API Key Required',
                    style: Theme.of(context).textTheme.titleLarge,
                    textAlign: TextAlign.center),
                const SizedBox(height: 12),
                Text(
                  'Enter your Anthropic API key to start using Claude.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: onConfigure,
                  icon: const Icon(Icons.settings_outlined),
                  label: const Text('Open AI Settings'),
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
                  '${progress > 0 ? '$pct%' : 'Starting…'} · runs fully on-device',
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
                  onPressed: () => AIService.instance.enableLocalBackend(),
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
          color: isUser
              ? scheme.primaryContainer
              : scheme.surfaceContainerHigh,
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
