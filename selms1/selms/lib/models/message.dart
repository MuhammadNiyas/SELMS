// lib/models/message.dart
//
// Plain human-to-human messages (Talk to HR / Talk to IT) — separate
// from the AI chatbot's ChatTurn, which never touches the database.

class ChatMessage {
  ChatMessage({
    required this.id,
    required this.employeeId,
    required this.employeeName,
    required this.targetRole,
    required this.senderRole,
    required this.senderName,
    required this.content,
    required this.createdAt,
  });

  final String id;
  final String employeeId;
  final String employeeName;
  final String targetRole; // 'hr' | 'it'
  final String senderRole; // 'employee' | 'hr' | 'it'
  final String senderName;
  final String content;
  final String createdAt; // ISO string

  factory ChatMessage.fromJson(Map<String, dynamic> j) => ChatMessage(
        id: j['id'] as String,
        employeeId: j['employee_id'] as String,
        employeeName: j['employee_name'] as String,
        targetRole: j['target_role'] as String,
        senderRole: j['sender_role'] as String,
        senderName: j['sender_name'] as String,
        content: j['content'] as String,
        createdAt: j['created_at'] as String,
      );
}

/// One row in HR's or IT's conversation inbox — one per employee who has
/// written in, not one per message.
class MessageConversation {
  MessageConversation({
    required this.employeeId,
    required this.employeeName,
    required this.lastMessage,
    required this.lastMessageAt,
    required this.lastSenderRole,
    required this.unreadCount,
  });

  final String employeeId;
  final String employeeName;
  final String lastMessage;
  final String lastMessageAt;
  final String lastSenderRole;
  final int unreadCount;

  factory MessageConversation.fromJson(Map<String, dynamic> j) => MessageConversation(
        employeeId: j['employee_id'] as String,
        employeeName: j['employee_name'] as String,
        lastMessage: j['last_message'] as String,
        lastMessageAt: j['last_message_at'] as String,
        lastSenderRole: j['last_sender_role'] as String,
        unreadCount: j['unread_count'] as int? ?? 0,
      );
}
