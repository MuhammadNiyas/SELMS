// lib/widgets/chat_panel.dart
//
// Shared chat UI for the HR Admin Assistant, IT's Assistant and the
// employee's SmartBot — same widget, different [title]/[hint]/[onSend]
// wiring. History lives only in this widget's state; nothing is persisted.
//
// Documents: when a reply used company documents, they appear as Download
// buttons under it ([documentUrl]). HR's chat also gets a paperclip
// ([onUpload]) and a delete icon on each document ([onDeleteDocument]).

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/chat.dart';
import '../theme/selms_colors.dart';

class ChatPanel extends StatefulWidget {
  const ChatPanel({
    super.key,
    required this.title,
    required this.hint,
    required this.suggestions,
    required this.onSend,
    this.documentUrl,
    this.onUpload,
    this.onDeleteDocument,
    this.showHeader = true,
  });

  /// False when the panel sits inside a container that has its own title
  /// bar and close button (the employee's chat bubble).
  final bool showHeader;

  final String title;
  final String hint;
  final List<String> suggestions;
  final Future<ChatReply> Function(String message, List<ChatTurn> history) onSend;

  /// Download address for a document id. Null hides the Download buttons.
  final String Function(String documentId)? documentUrl;

  /// Shows the paperclip (HR only). Receives the picked file and its title.
  final Future<ChatReply> Function(String filename, List<int> bytes, String title)? onUpload;

  /// Shows a delete icon on each document button (HR only).
  final Future<void> Function(String documentId)? onDeleteDocument;

  @override
  State<ChatPanel> createState() => _ChatPanelState();
}

class _ChatPanelState extends State<ChatPanel> {
  final _messageCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  final List<ChatTurn> _turns = [];
  bool _sending = false;
  String? _error;

  @override
  void dispose() {
    _messageCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollCtrl.hasClients) return;
      _scrollCtrl.animateTo(
        _scrollCtrl.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _send([String? text]) async {
    final message = (text ?? _messageCtrl.text).trim();
    if (message.isEmpty || _sending) return;

    final history = List<ChatTurn>.from(_turns);
    setState(() {
      _turns.add(ChatTurn(role: 'user', content: message));
      _messageCtrl.clear();
      _sending = true;
      _error = null;
    });
    _scrollToBottom();

    try {
      final reply = await widget.onSend(message, history);
      if (!mounted) return;
      setState(() => _turns.add(ChatTurn(role: 'assistant', content: reply.text, documents: reply.documents)));
      _scrollToBottom();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  static const _allowedExtensions = ['pdf', 'docx', 'txt', 'md'];

  /// Paperclip: pick a file, confirm its title, upload it, and show the
  /// saved-plus-summary reply as the assistant's next message.
  Future<void> _attach() async {
    if (_sending || widget.onUpload == null) return;
    final file = await FilePicker.pickFile(type: FileType.custom, allowedExtensions: _allowedExtensions);
    if (file == null || !mounted) return;

    final dot = file.name.lastIndexOf('.');
    final titleCtrl = TextEditingController(text: dot > 0 ? file.name.substring(0, dot) : file.name);
    final title = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add document', style: TextStyle(fontSize: 15)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(file.name, style: const TextStyle(fontSize: 12, color: SelmsColors.textMuted)),
            const SizedBox(height: 10),
            TextField(
              controller: titleCtrl,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Document title', isDense: true),
              style: const TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 8),
            const Text('Everyone in SELMS (HR, IT and employees) will be able to download this.',
                style: TextStyle(fontSize: 11.5, color: SelmsColors.textSecondary)),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(titleCtrl.text.trim()),
            style: ElevatedButton.styleFrom(backgroundColor: SelmsColors.ink, foregroundColor: Colors.white),
            child: const Text('Upload'),
          ),
        ],
      ),
    );
    titleCtrl.dispose();
    if (title == null || !mounted) return;

    setState(() {
      _turns.add(ChatTurn(role: 'user', content: 'Attached: ${file.name}'));
      _sending = true;
      _error = null;
    });
    _scrollToBottom();
    try {
      final bytes = await file.readAsBytes();
      final reply = await widget.onUpload!(file.name, bytes, title);
      if (!mounted) return;
      setState(() => _turns.add(ChatTurn(role: 'assistant', content: reply.text, documents: reply.documents)));
      _scrollToBottom();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _deleteDocument(ChatDocument doc) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this document?', style: TextStyle(fontSize: 15)),
        content: Text('"${doc.title}" will be removed for HR, IT and employees. This can\'t be undone.',
            style: const TextStyle(fontSize: 13)),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Keep')),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: SelmsColors.rose, foregroundColor: Colors.white),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await widget.onDeleteDocument!(doc.id);
      if (!mounted) return;
      setState(() {
        for (var i = 0; i < _turns.length; i++) {
          final t = _turns[i];
          if (t.documents.any((d) => d.id == doc.id)) {
            _turns[i] = ChatTurn(
              role: t.role,
              content: t.content,
              documents: t.documents.where((d) => d.id != doc.id).toList(),
            );
          }
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Document deleted.')));
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    }
  }

  Widget _documentChips(ChatTurn turn) {
    final urlFor = widget.documentUrl;
    if (urlFor == null || turn.documents.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 280),
        child: Wrap(
          spacing: 6,
          runSpacing: 6,
          children: turn.documents.map((d) {
            return Container(
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: SelmsColors.border),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  InkWell(
                    onTap: () => launchUrl(Uri.parse(urlFor(d.id)), mode: LaunchMode.externalApplication),
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.download_outlined, size: 14, color: SelmsColors.ink),
                          const SizedBox(width: 5),
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 170),
                            child: Text(d.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 11.5, color: SelmsColors.ink)),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (widget.onDeleteDocument != null)
                    InkWell(
                      onTap: () => _deleteDocument(d),
                      borderRadius: BorderRadius.circular(8),
                      child: const Padding(
                        padding: EdgeInsets.fromLTRB(2, 6, 8, 6),
                        child: Icon(Icons.delete_outline, size: 14, color: SelmsColors.rose),
                      ),
                    ),
                ],
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        if (widget.showHeader)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: SelmsColors.border)),
          ),
          child: Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(color: SelmsColors.ink, borderRadius: BorderRadius.circular(8)),
                alignment: Alignment.center,
                child: const Icon(Icons.smart_toy_outlined, size: 15, color: Colors.white),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(widget.title,
                    style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
              ),
              InkWell(
                onTap: () => Navigator.of(context).maybePop(),
                child: const Padding(
                  padding: EdgeInsets.all(4),
                  child: Icon(Icons.close, size: 18, color: SelmsColors.textMuted),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: _turns.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(widget.hint, style: const TextStyle(fontSize: 12.5, color: SelmsColors.textSecondary)),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: widget.suggestions
                            .map((s) => InkWell(
                                  onTap: () => _send(s),
                                  borderRadius: BorderRadius.circular(20),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: SelmsColors.accentBg,
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: Text(s, style: const TextStyle(fontSize: 11.5, color: SelmsColors.ink)),
                                  ),
                                ))
                            .toList(),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  controller: _scrollCtrl,
                  padding: const EdgeInsets.all(12),
                  itemCount: _turns.length,
                  itemBuilder: (context, i) {
                    final turn = _turns[i];
                    final isUser = turn.role == 'user';
                    return Align(
                      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
                      child: Column(
                        crossAxisAlignment: isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                        children: [
                          Container(
                            margin: EdgeInsets.only(bottom: turn.documents.isEmpty ? 8 : 6),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            constraints: const BoxConstraints(maxWidth: 280),
                            decoration: BoxDecoration(
                              color: isUser ? SelmsColors.ink : SelmsColors.accentBg,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              turn.content,
                              style: TextStyle(
                                fontSize: 12.5,
                                color: isUser ? Colors.white : SelmsColors.textPrimary,
                              ),
                            ),
                          ),
                          _documentChips(turn),
                        ],
                      ),
                    );
                  },
                ),
        ),
        if (_sending)
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(_error!, style: const TextStyle(fontSize: 11.5, color: SelmsColors.rose)),
          ),
        Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              if (widget.onUpload != null)
                Tooltip(
                  message: 'Attach a document (PDF, DOCX, TXT)',
                  child: IconButton(
                    onPressed: _sending ? null : _attach,
                    icon: const Icon(Icons.attach_file, size: 20, color: SelmsColors.textSecondary),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              Expanded(
                child: TextField(
                  controller: _messageCtrl,
                  onSubmitted: (_) => _send(),
                  decoration: InputDecoration(
                    hintText: 'Ask me anything…',
                    hintStyle: const TextStyle(fontSize: 12.5),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: SelmsColors.border),
                    ),
                  ),
                  style: const TextStyle(fontSize: 12.5),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: _sending ? null : () => _send(),
                style: ElevatedButton.styleFrom(
                  backgroundColor: SelmsColors.ink,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                ),
                child: const Text('Send', style: TextStyle(fontSize: 12.5)),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
