// lib/models/chat.dart
//
// One turn in a chatbot conversation (HR's Admin Assistant or the
// employee's SmartBot). Kept in-session only — sent back to the backend
// as history on every message, never persisted server-side.

class ChatTurn {
  ChatTurn({required this.role, required this.content});

  final String role; // 'user' | 'assistant'
  final String content;

  Map<String, String> toJson() => {'role': role, 'content': content};
}
