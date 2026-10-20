// lib/models/chat.dart
//
// One turn in a chatbot conversation (HR's Admin Assistant, IT's Assistant
// or the employee's SmartBot). Kept in-session only — sent back to the
// backend as history on every message, never persisted server-side.

/// A company document the bot looked up while answering; the chat shows it
/// as a Download button under the reply.
class ChatDocument {
  ChatDocument({required this.id, required this.title});

  final String id;
  final String title;

  factory ChatDocument.fromJson(Map<String, dynamic> json) =>
      ChatDocument(id: json['id'] as String, title: (json['title'] as String?) ?? 'Document');
}

/// What a chatbot endpoint returns: the answer text plus any documents it used.
class ChatReply {
  ChatReply({required this.text, this.documents = const []});

  final String text;
  final List<ChatDocument> documents;

  factory ChatReply.fromJson(Map<String, dynamic> json) => ChatReply(
        text: json['reply'] as String? ?? '',
        documents: ((json['documents'] as List?) ?? const [])
            .cast<Map<String, dynamic>>()
            .map(ChatDocument.fromJson)
            .toList(),
      );
}

class ChatTurn {
  ChatTurn({required this.role, required this.content, this.documents = const []});

  final String role; // 'user' | 'assistant'
  final String content;
  final List<ChatDocument> documents; // only on assistant turns; never sent back as history

  Map<String, String> toJson() => {'role': role, 'content': content};
}
