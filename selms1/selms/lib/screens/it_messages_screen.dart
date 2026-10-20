// lib/screens/it_messages_screen.dart
//
// IT's inbox — report fig 3.27 "Message Page", now actually functional
// (real conversations with real employees) instead of a static mockup.

import 'package:flutter/material.dart';
import '../models/message.dart';
import '../services/api_client.dart';
import '../widgets/employee_avatar.dart';
import '../theme/selms_colors.dart';
import '../widgets/it_app_shell.dart';
import '../widgets/message_thread_panel.dart';
import 'it_requests_view.dart';

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
  String _tab = 'requests'; // requests | conversations
  int _openRequests = 0;
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

  Widget _tabButton(String label, String value, {int badge = 0}) {
    final active = _tab == value;
    return InkWell(
      onTap: () => setState(() => _tab = value),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
        decoration: BoxDecoration(
          color: active ? SelmsColors.ink : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label,
                style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500,
                    color: active ? Colors.white : SelmsColors.textSecondary)),
            if (badge > 0) ...[
              const SizedBox(width: 7),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(color: SelmsColors.rose, borderRadius: BorderRadius.circular(10)),
                child: Text('$badge',
                    style: const TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.w700)),
              ),
            ],
          ],
        ),
      ),
    );
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
            Text(
                _tab == 'requests'
                    ? 'Equipment requests from HR — what to prepare, for whom, and how far along it is.'
                    : 'Conversations with employees who\'ve written in.',
                style: const TextStyle(fontSize: 13, color: SelmsColors.textSecondary)),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10)),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _tabButton('Requests', 'requests', badge: _openRequests),
                  _tabButton('Conversations', 'conversations'),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Expanded(
              child: _tab == 'requests'
                  ? ItRequestsView(
                      api: _api,
                      apiBaseUrl: widget.apiBaseUrl,
                      itToken: widget.itToken,
                      onOpenCount: (n) {
                        if (n != _openRequests && mounted) setState(() => _openRequests = n);
                      },
                    )
                  : _buildBody(),
            ),
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
                        EmployeeAvatar(
                          apiBaseUrl: widget.apiBaseUrl,
                          name: c.employeeName,
                          photoUrl: c.profileImageUrl,
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
                  ),
          ),
        ),
      ],
    );
  }
}
