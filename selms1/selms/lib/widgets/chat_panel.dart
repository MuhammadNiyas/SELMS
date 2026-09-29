// lib/widgets/chat_panel.dart
//
// Shared chat UI for both the HR Admin Assistant and the employee's
// SmartBot — same widget, different [title]/[hint]/[onSend] wiring.
// History lives only in this widget's state; nothing is persisted.

import 'package:flutter/material.dart';
import '../models/chat.dart';
import '../theme/selms_colors.dart';

class ChatPanel extends StatefulWidget {
  const ChatPanel({
    super.key,
    required this.title,
    required this.hint,
    required this.suggestions,
    required this.onSend,
  });

  final String title;
  final String hint;
  final List<String> suggestions;
  final Future<String> Function(String message, List<ChatTurn> history) onSend;

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
      setState(() => _turns.add(ChatTurn(role: 'assistant', content: reply)));
      _scrollToBottom();
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
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 8),
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
