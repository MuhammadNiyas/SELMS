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
    this.accepted = false,
    this.acceptedBy,
    this.acceptedAt,
    this.attachmentName,
    this.attachmentSize,
  });

  /// A file sent with the message. [content] can be empty when there is one.
  final String? attachmentName;
  final int? attachmentSize;

  final String id;
  final String employeeId;
  final String employeeName;
  final String targetRole; // 'hr' | 'it'
  final String senderRole; // 'employee' | 'hr' | 'it' | 'system'
  final String senderName;
  final String content;
  final String createdAt; // ISO string

  /// Only meaningful on sender_role == 'system' messages (e.g. the
  /// onboarding equipment notification) — IT explicitly acknowledging it.
  final bool accepted;
  final String? acceptedBy;
  final String? acceptedAt;

  factory ChatMessage.fromJson(Map<String, dynamic> j) => ChatMessage(
        id: j['id'] as String,
        employeeId: j['employee_id'] as String,
        employeeName: j['employee_name'] as String,
        targetRole: j['target_role'] as String,
        senderRole: j['sender_role'] as String,
        accepted: j['accepted'] as bool? ?? false,
        acceptedBy: j['accepted_by'] as String?,
        acceptedAt: j['accepted_at'] as String?,
        senderName: j['sender_name'] as String,
        content: j['content'] as String,
        createdAt: j['created_at'] as String,
        attachmentName: (j['attachment'] as Map?)?['filename'] as String?,
        attachmentSize: (j['attachment'] as Map?)?['size'] as int?,
      );
}

/// The id of the HR <-> IT team chat row in the inbox.
const teamChatId = 'team';

/// One row in HR's or IT's inbox — the other team, then one per employee (not
/// one per message). [lastMessage] is empty when there are no messages yet.
class MessageConversation {
  MessageConversation({
    required this.employeeId,
    required this.employeeName,
    required this.lastMessage,
    required this.lastMessageAt,
    required this.lastSenderRole,
    required this.unreadCount,
    this.profileImageUrl,
    this.department,
    this.jobTitle,
    this.workEmail,
    this.mobileNumber,
    this.isTeam = false,
    this.teamTitle,
  });

  final String employeeId;
  final String employeeName;
  final String? profileImageUrl;
  final String? department;
  final String? jobTitle;
  final String? workEmail;
  final String? mobileNumber;
  final bool isTeam;

  /// A team's full name, e.g. "Information Technology Team".
  final String? teamTitle;

  /// Letters for the photo circle: "IT" or "HR" for a team, otherwise from the name.
  String? get avatarInitials => isTeam ? employeeName.split(' ').first : null;
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
        profileImageUrl: j['profile_image_url'] as String?,
        department: j['department'] as String?,
        jobTitle: j['job_title'] as String?,
        workEmail: j['work_email'] as String?,
        mobileNumber: j['mobile_number'] as String?,
        isTeam: j['is_team'] == true,
        teamTitle: j['team_title'] as String?,
      );
}
