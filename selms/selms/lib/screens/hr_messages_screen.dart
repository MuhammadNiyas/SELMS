// lib/screens/hr_messages_screen.dart
//
// HR's inbox — the IT team, then every employee, so HR can answer Talk to HR
// or start a conversation with anyone (report's fig 3.27 "Message Page" was
// drawn for IT only; this is HR's own equivalent).

import 'package:flutter/material.dart';
import '../models/message.dart';
import '../services/api_client.dart';
import '../theme/selms_colors.dart';
import '../widgets/app_shell.dart';
import '../widgets/conversation_list.dart';
import '../widgets/message_thread_panel.dart';
import 'employee_view_screen.dart';

class HrMessagesScreen extends StatefulWidget {
  const HrMessagesScreen({super.key, required this.apiBaseUrl, required this.hrToken});

  final String apiBaseUrl;
  final String hrToken;

  @override
  State<HrMessagesScreen> createState() => _HrMessagesScreenState();
}

class _HrMessagesScreenState extends State<HrMessagesScreen> {
  late final ApiClient _api = ApiClient(baseUrl: widget.apiBaseUrl, hrToken: widget.hrToken);
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
      final list = await _api.getHrConversations();
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

  /// The full employee page, same as clicking a card on the Employees page.
  Future<void> _openEmployee(String employeeId) async {
    await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => EmployeeViewScreen(
        apiBaseUrl: widget.apiBaseUrl,
        hrToken: widget.hrToken,
        employeeId: employeeId,
      ),
    ));
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return AppShell(
      apiBaseUrl: widget.apiBaseUrl,
      hrToken: widget.hrToken,
      activeRoute: SelmsRoute.messages,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Messages',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: SelmsColors.textPrimary)),
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
            onOpenEmployee: _openEmployee,
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
                      ConversationHeader(
                        apiBaseUrl: widget.apiBaseUrl,
                        conversation: selected,
                        onOpenEmployee: _openEmployee,
                      ),
                      const Divider(height: 1, color: SelmsColors.border),
                      Expanded(
                        child: MessageThreadPanel(
                          key: ValueKey(selected.employeeId),
                          mySenderRole: 'hr',
                          fetchMessages: () =>
                              selected.isTeam ? _api.getTeamChat() : _api.getHrThread(selected.employeeId),
                          sendMessage: (content) => selected.isTeam
                              ? _api.sendTeamMessage(content)
                              : _api.sendHrMessage(selected.employeeId, content),
                          sendFile: (content, name, bytes) => selected.isTeam
                              ? _api.sendTeamFile(content, name, bytes)
                              : _api.sendHrFile(selected.employeeId, content, name, bytes),
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
