// lib/screens/it_messages_screen.dart
//
// IT's inbox — report fig 3.27 "Message Page", now actually functional
// (real conversations with real employees) instead of a static mockup.

import 'package:flutter/material.dart';
import '../models/message.dart';
import '../services/api_client.dart';
import '../theme/selms_colors.dart';
import '../widgets/it_app_shell.dart';
import '../widgets/message_thread_panel.dart';

class ItMessagesScreen extends StatefulWidget {
  const ItMessagesScreen({super.key, required this.apiBaseUrl, required this.itToken});

  final String apiBaseUrl;
  final String itToken;

  @override
  State<ItMessagesScreen> createState() => _ItMessagesScreenState();
}

class _ItMessagesScreenState extends State<ItMessagesScreen> {
  late final ApiClient _api = ApiClient(baseUrl: widget.apiBaseUrl, hrToken: widget.itToken);
  List<MessageConversation> _conversations = [];
  String? _selectedEmployeeId;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final list = await _api.getItConversations();
      if (!mounted) return;
      setState(() {
        _conversations = list;
        _loading = false;
        _selectedEmployeeId ??= list.isNotEmpty ? list.first.employeeId : null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length == 1) return parts[0].substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1)).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    return ItAppShell(
      apiBaseUrl: widget.apiBaseUrl,
      itToken: widget.itToken,
      activeRoute: ItRoute.messages,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Messages',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: SelmsColors.textPrimary)),
            const Text('Conversations with employees who\'ve written in.',
                style: TextStyle(fontSize: 13, color: SelmsColors.textSecondary)),
            const SizedBox(height: 18),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(child: Text(_error!, style: const TextStyle(color: SelmsColors.rose, fontSize: 13)));
    }
    if (_conversations.isEmpty) {
      return const Center(
        child: Text('No conversations yet.', style: TextStyle(fontSize: 13, color: SelmsColors.textMuted)),
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 280,
          child: Container(
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 6),
              itemCount: _conversations.length,
              separatorBuilder: (_, __) => const Divider(height: 1, color: SelmsColors.border),
              itemBuilder: (context, i) {
                final c = _conversations[i];
                final selected = c.employeeId == _selectedEmployeeId;
                return InkWell(
                  onTap: () => setState(() => _selectedEmployeeId = c.employeeId),
                  child: Container(
                    color: selected ? SelmsColors.accentBg : null,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 16,
                          backgroundColor: SelmsColors.ink,
                          child: Text(_initials(c.employeeName),
                              style: const TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.w600)),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(c.employeeName,
                                  style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                                  overflow: TextOverflow.ellipsis),
                              Text(c.lastMessage,
                                  style: const TextStyle(fontSize: 11, color: SelmsColors.textMuted),
                                  overflow: TextOverflow.ellipsis),
                            ],
                          ),
                        ),
                        if (c.unreadCount > 0)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration:
                                BoxDecoration(color: SelmsColors.rose, borderRadius: BorderRadius.circular(10)),
                            child: Text('${c.unreadCount}',
                                style: const TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.w700)),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Container(
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
            child: _selectedEmployeeId == null
                ? const Center(
                    child: Text('Select a conversation', style: TextStyle(fontSize: 13, color: SelmsColors.textMuted)),
                  )
                : MessageThreadPanel(
                    key: ValueKey(_selectedEmployeeId),
                    mySenderRole: 'it',
                    fetchMessages: () => _api.getItThread(_selectedEmployeeId!),
                    sendMessage: (content) => _api.sendItMessage(_selectedEmployeeId!, content),
                    onAccept: (message) => _api.acceptMessage(message.id),
                  ),
          ),
        ),
      ],
    );
  }
}
