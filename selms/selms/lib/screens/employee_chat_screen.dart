// lib/screens/employee_chat_screen.dart
//
// Everything chat-related for the employee, in one panel that opens from
// the floating chat bubble (bottom-right, like HR's and IT's assistants):
// SmartBot (AI, via ChatPanel - can also hand out company documents) plus
// Talk to HR / Talk to IT (plain human messaging, via MessageThreadPanel).

import 'package:flutter/material.dart';
import '../services/api_client.dart';
import '../theme/selms_colors.dart';
import '../widgets/chat_panel.dart';
import '../widgets/message_thread_panel.dart';

class EmployeeChatPanel extends StatefulWidget {
  const EmployeeChatPanel({super.key, required this.api, required this.onClose});

  final ApiClient api;
  final VoidCallback onClose;

  @override
  State<EmployeeChatPanel> createState() => _EmployeeChatPanelState();
}

class _EmployeeChatPanelState extends State<EmployeeChatPanel> with SingleTickerProviderStateMixin {
  late final TabController _tabController = TabController(length: 3, vsync: this);

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Widget _tab(IconData icon, String label) => Tab(
        height: 34,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15),
            const SizedBox(width: 6),
            Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis)),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Title bar
        Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 8, 12),
          decoration: const BoxDecoration(
            color: SelmsColors.ink,
            borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                alignment: Alignment.center,
                child: const Icon(Icons.forum_outlined, size: 18, color: Colors.white),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Help & messages',
                        style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: Colors.white)),
                    Text('SmartBot answers instantly · HR and IT reply here',
                        style: TextStyle(fontSize: 11, color: Colors.white70)),
                  ],
                ),
              ),
              IconButton(
                onPressed: widget.onClose,
                tooltip: 'Close',
                icon: const Icon(Icons.close, size: 20, color: Colors.white70),
              ),
            ],
          ),
        ),
        // Switcher
        Container(
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
          child: Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(color: const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(10)),
            child: TabBar(
              controller: _tabController,
              indicator: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 4)],
              ),
              indicatorSize: TabBarIndicatorSize.tab,
              labelPadding: const EdgeInsets.symmetric(horizontal: 4),
              dividerColor: Colors.transparent,
              labelColor: SelmsColors.ink,
              unselectedLabelColor: SelmsColors.textMuted,
              labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              unselectedLabelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
              tabs: [
                _tab(Icons.smart_toy_outlined, 'SmartBot'),
                _tab(Icons.badge_outlined, 'HR'),
                _tab(Icons.computer_outlined, 'IT'),
              ],
            ),
          ),
        ),
        const Divider(height: 1, color: SelmsColors.border),
        Expanded(
          child: Container(
            color: Colors.white,
            child: TabBarView(
              controller: _tabController,
              children: [
                ChatPanel(
                  title: 'SmartBot',
                  hint: "Hi! I'm SmartBot. Ask me about your onboarding, company policies or documents.",
                  suggestions: const ['What should I do next?', 'Apply leave', 'Medical claim', 'Company documents'],
                  onSend: widget.api.employeeChat,
                  documentUrl: widget.api.documentDownloadUrl,
                  showHeader: false,
                ),
                MessageThreadPanel(
                  mySenderRole: 'employee',
                  fetchMessages: () => widget.api.getMyMessages('hr'),
                  sendMessage: (content) => widget.api.sendMyMessage('hr', content),
                  sendFile: (content, name, bytes) => widget.api.sendMyFile('hr', content, name, bytes),
                  fileUrl: widget.api.messageFileUrl,
                  emptyHint: 'No messages with HR yet — say hello.',
                ),
                MessageThreadPanel(
                  mySenderRole: 'employee',
                  fetchMessages: () => widget.api.getMyMessages('it'),
                  sendMessage: (content) => widget.api.sendMyMessage('it', content),
                  sendFile: (content, name, bytes) => widget.api.sendMyFile('it', content, name, bytes),
                  fileUrl: widget.api.messageFileUrl,
                  emptyHint: 'No messages with IT yet — say hello.',
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
