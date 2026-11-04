// lib/widgets/message_thread_panel.dart
//
// One conversation thread — shared by the employee's Talk to HR/IT tabs
// and HR's/IT's inbox thread view. Polls on a timer since there's no
// push infrastructure; [mySenderRole] decides which bubbles align right.

import 'dart:async';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/message.dart';
import '../theme/selms_colors.dart';

const _fileExtensions = ['pdf', 'doc', 'docx', 'xls', 'xlsx', 'png', 'jpg', 'jpeg', 'txt'];
const _maxFileBytes = 10 * 1024 * 1024;

/// A file chosen in the chat, waiting to be sent.
typedef PickedChatFile = ({String name, List<int> bytes});

Future<PickedChatFile?> _pickWithSystemDialog() async {
  final file = await FilePicker.pickFile(type: FileType.custom, allowedExtensions: _fileExtensions);
  if (file == null) return null;
  return (name: file.name, bytes: await file.readAsBytes() as List<int>);
}

class MessageThreadPanel extends StatefulWidget {
  const MessageThreadPanel({
    super.key,
    required this.mySenderRole,
    required this.fetchMessages,
    required this.sendMessage,
    this.emptyHint = 'No messages yet — say hello.',
    this.onAccept,
    this.onSent,
    this.sendFile,
    this.fileUrl,
    this.pickFile = _pickWithSystemDialog,
  });

  /// Called after a message is sent, so an inbox beside this panel can update.
  final VoidCallback? onSent;

  /// Sends a file with optional text. Without it there is no paperclip.
  final Future<void> Function(String content, String filename, List<int> bytes)? sendFile;

  /// Where a message's file downloads from.
  final String Function(ChatMessage message)? fileUrl;

  /// How a file is chosen; tests replace the system dialog.
  final Future<PickedChatFile?> Function() pickFile;

  final String mySenderRole; // 'employee' | 'hr' | 'it'
  final Future<List<ChatMessage>> Function() fetchMessages;
  final Future<void> Function(String content) sendMessage;
  final String emptyHint;

  /// When set, system-authored messages (sender_role == 'system') show
  /// an "Accept" button that calls this. Only wired on IT's own Messages
  /// screen — leave null anywhere accepting wouldn't make sense (HR's
  /// inbox, the employee's own Talk to HR/IT tabs).
  final Future<void> Function(ChatMessage message)? onAccept;

  @override
  State<MessageThreadPanel> createState() => _MessageThreadPanelState();
}

class _MessageThreadPanelState extends State<MessageThreadPanel> {
  final _inputCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  List<ChatMessage> _messages = [];
  bool _loading = true;
  bool _sending = false;
  String? _error;
  String? _acceptingId;
  Timer? _pollTimer;
  PickedChatFile? _pickedFile;

  @override
  void initState() {
    super.initState();
    _load();
    _pollTimer = Timer.periodic(const Duration(seconds: 15), (_) => _load(silent: true));
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) setState(() => _loading = true);
    try {
      final list = await widget.fetchMessages();
      if (!mounted) return;
      setState(() {
        _messages = list;
        _loading = false;
        _error = null;
      });
      _scrollToBottom();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        if (!silent) _error = e.toString();
      });
    }
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

  Future<void> _accept(ChatMessage message) async {
    final onAccept = widget.onAccept;
    if (onAccept == null || _acceptingId != null) return;
    setState(() => _acceptingId = message.id);
    try {
      await onAccept(message);
      await _load();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _acceptingId = null);
    }
  }

  Future<void> _attach() async {
    final picked = await widget.pickFile();
    if (picked == null || !mounted) return;
    setState(() {
      if (picked.bytes.length > _maxFileBytes) {
        _error = 'That file is too large (10MB maximum).';
      } else {
        _pickedFile = picked;
        _error = null;
      }
    });
  }

  Future<void> _send() async {
    final text = _inputCtrl.text.trim();
    final file = _pickedFile;
    if ((text.isEmpty && file == null) || _sending) return;
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      if (file != null) {
        await widget.sendFile!(text, file.name, file.bytes);
      } else {
        await widget.sendMessage(text);
      }
      _inputCtrl.clear();
      if (mounted) setState(() => _pickedFile = null);
      await _load();
      widget.onSent?.call();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  String _sizeText(int? bytes) {
    if (bytes == null) return '';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).ceil()} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  Widget _fileRow(ChatMessage m, Color color) {
    final url = widget.fileUrl?.call(m);
    return InkWell(
      onTap: url == null ? null : () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.attach_file, size: 14, color: color),
            const SizedBox(width: 4),
            Flexible(
              child: Text(m.attachmentName!,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12.5, color: color, decoration: TextDecoration.underline, decorationColor: color)),
            ),
            const SizedBox(width: 6),
            Text(_sizeText(m.attachmentSize), style: TextStyle(fontSize: 10.5, color: color.withValues(alpha: 0.75))),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _messages.isEmpty
                  ? Center(
                      child: Text(widget.emptyHint,
                          style: const TextStyle(fontSize: 12.5, color: SelmsColors.textMuted)),
                    )
                  : ListView.builder(
                      controller: _scrollCtrl,
                      padding: const EdgeInsets.all(12),
                      itemCount: _messages.length,
                      itemBuilder: (context, i) {
                        final m = _messages[i];
                        final isMine = m.senderRole == widget.mySenderRole;
                        final isSystem = m.senderRole == 'system';
                        final showAccept = widget.onAccept != null && isSystem;
                        return Align(
                          alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            constraints: const BoxConstraints(maxWidth: 320),
                            decoration: BoxDecoration(
                              color: isSystem
                                  ? SelmsColors.statusOnboardingBg
                                  : (isMine ? SelmsColors.ink : SelmsColors.accentBg),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (!isMine)
                                  Text(m.senderName,
                                      style: const TextStyle(
                                          fontSize: 10.5, fontWeight: FontWeight.w600, color: SelmsColors.textMuted)),
                                if (m.content.isNotEmpty)
                                  Text(m.content,
                                      style: TextStyle(
                                          fontSize: 12.5,
                                          color: isSystem
                                              ? SelmsColors.statusOnboardingText
                                              : (isMine ? Colors.white : SelmsColors.textPrimary))),
                                if (m.attachmentName != null)
                                  _fileRow(m, isMine ? Colors.white : SelmsColors.textPrimary),
                                if (showAccept) ...[
                                  const SizedBox(height: 6),
                                  if (m.accepted)
                                    Text('Accepted by ${m.acceptedBy} ✓',
                                        style: const TextStyle(
                                            fontSize: 10.5,
                                            fontWeight: FontWeight.w600,
                                            color: SelmsColors.statusActiveText))
                                  else
                                    SizedBox(
                                      height: 26,
                                      child: ElevatedButton(
                                        onPressed: _acceptingId == m.id ? null : () => _accept(m),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: SelmsColors.ink,
                                          foregroundColor: Colors.white,
                                          padding: const EdgeInsets.symmetric(horizontal: 10),
                                          textStyle: const TextStyle(fontSize: 11),
                                        ),
                                        child: Text(_acceptingId == m.id ? 'Accepting…' : 'Accept'),
                                      ),
                                    ),
                                ],
                              ],
                            ),
                          ),
                        );
                      },
                    ),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(_error!, style: const TextStyle(fontSize: 11.5, color: SelmsColors.rose)),
          ),
        if (_pickedFile != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: Row(
              children: [
                const Icon(Icons.attach_file, size: 14, color: SelmsColors.textSecondary),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(_pickedFile!.name,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12, color: SelmsColors.textSecondary)),
                ),
                InkWell(
                  onTap: _sending ? null : () => setState(() => _pickedFile = null),
                  child: const Padding(
                    padding: EdgeInsets.all(2),
                    child: Icon(Icons.close, size: 15, color: SelmsColors.textSecondary),
                  ),
                ),
              ],
            ),
          ),
        Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              if (widget.sendFile != null) ...[
                InkWell(
                  onTap: _sending ? null : _attach,
                  borderRadius: BorderRadius.circular(16),
                  child: const Padding(
                    padding: EdgeInsets.all(6),
                    child: Icon(Icons.attach_file, size: 18, color: SelmsColors.textSecondary),
                  ),
                ),
                const SizedBox(width: 4),
              ],
              Expanded(
                child: TextField(
                  controller: _inputCtrl,
                  onSubmitted: (_) => _send(),
                  decoration: InputDecoration(
                    hintText: 'Type a message…',
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
                onPressed: _sending ? null : _send,
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
