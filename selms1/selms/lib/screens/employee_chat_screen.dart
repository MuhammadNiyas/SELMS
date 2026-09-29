// lib/screens/employee_chat_screen.dart
//
// SmartBot tab (report fig 3.30) — AI only, via the shared ChatPanel.
// "Talk to HR" / "Talk to IT" (real messaging, no AI) were deliberately
// left out — no messaging backend exists yet, and this pass is Claude
// API only, per what was asked.

import 'package:flutter/material.dart';
import '../services/api_client.dart';
import '../widgets/chat_panel.dart';

class EmployeeChatScreen extends StatelessWidget {
  const EmployeeChatScreen({super.key, required this.api});

  final ApiClient api;

  @override
  Widget build(BuildContext context) {
    return ChatPanel(
      title: 'SmartBot',
      hint: "Hi! I'm your SmartBot assistant. How can I help you today?",
      suggestions: const ['Medical claim', 'Apply leave', 'Orientation', 'Equipment', 'VPN'],
      onSend: (message, history) => api.employeeChat(message, history),
    );
  }
}
