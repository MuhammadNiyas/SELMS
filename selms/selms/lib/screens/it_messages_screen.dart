// lib/screens/it_messages_screen.dart
//
// IT's inbox — report fig 3.27 "Message Page". The HR team, then every
// employee, so IT can answer Talk to IT or start a conversation with anyone.

import 'package:flutter/material.dart';
import '../models/message.dart';
import '../services/api_client.dart';
import '../theme/selms_colors.dart';
import '../widgets/conversation_list.dart';
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
        if (!list.any((c) => c.employeeId == _selectedEmployeeId)) _selectedEmployeeId = null;
        // Opens the latest employee conversation; the team chat stays unread until clicked.
        _selectedEmployeeId ??= list.where((c) => !c.isTeam).firstOrNull?.employeeId;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
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
            const SizedBox(height: 14),
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
    final selected = _conversations.where((c) => c.employeeId == _selectedEmployeeId).firstOrNull;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 280,
          child: ConversationList(
            apiBaseUrl: widget.apiBaseUrl,
            conversations: _conversations,
            selectedEmployeeId: _selectedEmployeeId,
            onSelect: (id) => setState(() => _selectedEmployeeId = id),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Container(
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
            child: selected == null
                ? const Center(
                    child: Text('Select a conversation', style: TextStyle(fontSize: 13, color: SelmsColors.textMuted)),
                  )
                : Column(
                    children: [
                      ConversationHeader(apiBaseUrl: widget.apiBaseUrl, conversation: selected),
                      const Divider(height: 1, color: SelmsColors.border),
                      Expanded(
                        child: MessageThreadPanel(
                          key: ValueKey(selected.employeeId),
                          mySenderRole: 'it',
                          fetchMessages: () =>
                              selected.isTeam ? _api.getTeamChat() : _api.getItThread(selected.employeeId),
                          sendMessage: (content) => selected.isTeam
                              ? _api.sendTeamMessage(content)
                              : _api.sendItMessage(selected.employeeId, content),
                          sendFile: (content, name, bytes) => selected.isTeam
                              ? _api.sendTeamFile(content, name, bytes)
                              : _api.sendItFile(selected.employeeId, content, name, bytes),
                          fileUrl: selected.isTeam ? _api.teamFileUrl : _api.messageFileUrl,
                          onSent: _load,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ],
    );
  }
}
