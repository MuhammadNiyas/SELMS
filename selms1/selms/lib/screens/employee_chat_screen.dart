// lib/screens/employee_chat_screen.dart
//
// Chat tab (report fig 3.30): SmartBot (AI, via ChatPanel) plus Talk to
// HR / Talk to IT (plain human messaging, via MessageThreadPanel) as
// inner sub-tabs — matches the report's own 3-way split within one tab.

import 'package:flutter/material.dart';
import '../services/api_client.dart';
import '../theme/selms_colors.dart';
import '../widgets/chat_panel.dart';
import '../widgets/message_thread_panel.dart';

class EmployeeChatScreen extends StatefulWidget {
  const EmployeeChatScreen({super.key, required this.api});

  final ApiClient api;

  @override
  State<EmployeeChatScreen> createState() => _EmployeeChatScreenState();
}

class _EmployeeChatScreenState extends State<EmployeeChatScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController = TabController(length: 3, vsync: this);

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TabBar(
          controller: _tabController,
          labelColor: SelmsColors.ink,
          unselectedLabelColor: SelmsColors.textMuted,
          indicatorColor: SelmsColors.ink,
          labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          unselectedLabelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w400),
          tabs: const [
            Tab(text: 'SmartBot'),
            Tab(text: 'Talk to HR'),
            Tab(text: 'Talk to IT'),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              ChatPanel(
                title: 'SmartBot',
                hint: "Hi! I'm your SmartBot assistant. How can I help you today?",
                suggestions: const ['Medical claim', 'Apply leave', 'Orientation', 'Equipment', 'VPN'],
                onSend: (message, history) => widget.api.employeeChat(message, history),
              ),
              MessageThreadPanel(
                mySenderRole: 'employee',
                fetchMessages: () => widget.api.getMyMessages('hr'),
                sendMessage: (content) => widget.api.sendMyMessage('hr', content),
                emptyHint: 'No messages with HR yet — say hello.',
              ),
              MessageThreadPanel(
                mySenderRole: 'employee',
                fetchMessages: () => widget.api.getMyMessages('it'),
                sendMessage: (content) => widget.api.sendMyMessage('it', content),
                emptyHint: 'No messages with IT yet — say hello.',
              ),
            ],
          ),
        ),
      ],
    );
  }
}
