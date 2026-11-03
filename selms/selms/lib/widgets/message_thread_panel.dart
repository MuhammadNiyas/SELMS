// lib/widgets/message_thread_panel.dart
//
// One conversation thread — shared by the employee's Talk to HR/IT tabs
// and HR's/IT's inbox thread view. Polls on a timer since there's no
// push infrastructure; [mySenderRole] decides which bubbles align right.

import 'dart:async';
import 'package:flutter/material.dart';
import '../models/message.dart';
import '../theme/selms_colors.dart';

class MessageThreadPanel extends StatefulWidget {
  const MessageThreadPanel({
    super.key,
    required this.mySenderRole,
    required this.fetchMessages,
    required this.sendMessage,
    this.emptyHint = 'No messages yet — say hello.',
    this.onAccept,
  });

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

  Future<void> _send() async {
    final text = _inputCtrl.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await widget.sendMessage(text);
      _inputCtrl.clear();
      await _load();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _sending = false);
    }
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
                                Text(m.content,
                                    style: TextStyle(
                                        fontSize: 12.5,
                                        color: isSystem
                                            ? SelmsColors.statusOnboardingText
                                            : (isMine ? Colors.white : SelmsColors.textPrimary))),
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
        Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
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
