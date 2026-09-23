// lib/models/employee_self_service.dart
//
// Models for the employee's own view of themselves: the onboarding
// checklist (GET /api/employee/me/checklist), the company documents they
// need to sign (GET /api/employee/me/documents), notifications, and — once
// HR has initiated it — the offboarding checklist.

class ChecklistItem {
  ChecklistItem({
    required this.id,
    required this.label,
    required this.done,
    this.doneAt,
  });

  final String id;
  final String label;
  final bool done;
  final String? doneAt; // ISO string, set only for system-driven steps

  factory ChecklistItem.fromJson(Map<String, dynamic> j) => ChecklistItem(
        id: j['id'] as String,
        label: j['label'] as String,
        done: j['done'] as bool? ?? false,
        doneAt: j['done_at'] as String?,
      );
}

class EmployeeChecklist {
  EmployeeChecklist({required this.items, required this.progressPercent});

  final List<ChecklistItem> items;
  final int progressPercent;

  factory EmployeeChecklist.fromJson(Map<String, dynamic> j) => EmployeeChecklist(
        items: (j['items'] as List)
            .map((e) => ChecklistItem.fromJson(e as Map<String, dynamic>))
            .toList(),
        progressPercent: j['progress_percent'] as int? ?? 0,
      );
}

class CompanyDocument {
  CompanyDocument({
    required this.id,
    required this.title,
    required this.description,
    required this.signed,
    this.signedAt,
  });

  final String id;
  final String title;
  final String description;
  final bool signed;
  final String? signedAt;

  factory CompanyDocument.fromJson(Map<String, dynamic> j) => CompanyDocument(
        id: j['id'] as String,
        title: j['title'] as String,
        description: j['description'] as String,
        signed: j['signed'] as bool? ?? false,
        signedAt: j['signed_at'] as String?,
      );
}

class NotificationItem {
  NotificationItem({
    required this.id,
    required this.title,
    required this.message,
    required this.at,
    required this.read,
  });

  final String id;
  final String title;
  final String message;
  final String at; // ISO string
  final bool read;

  factory NotificationItem.fromJson(Map<String, dynamic> j) => NotificationItem(
        id: j['id'] as String,
        title: j['title'] as String,
        message: j['message'] as String,
        at: j['at'] as String,
        read: j['read'] as bool? ?? false,
      );
}

class EmployeeNotifications {
  EmployeeNotifications({required this.items, required this.unreadCount});

  final List<NotificationItem> items;
  final int unreadCount;

  factory EmployeeNotifications.fromJson(Map<String, dynamic> j) => EmployeeNotifications(
        items: (j['notifications'] as List)
            .map((e) => NotificationItem.fromJson(e as Map<String, dynamic>))
            .toList(),
        unreadCount: j['unread_count'] as int? ?? 0,
      );
}

/// Mirrors EmployeeChecklist's shape but only meaningful once HR has
/// initiated offboarding for this employee — [started] is false and
/// everything else null/empty until then.
class OffboardingChecklist {
  OffboardingChecklist({
    required this.started,
    this.departureType,
    this.lastWorkingDay,
    this.items = const [],
    this.progressPercent = 0,
  });

  final bool started;
  final String? departureType;
  final String? lastWorkingDay;
  final List<ChecklistItem> items;
  final int progressPercent;

  factory OffboardingChecklist.fromJson(Map<String, dynamic> j) {
    if (j['started'] != true) return OffboardingChecklist(started: false);
    return OffboardingChecklist(
      started: true,
      departureType: j['departure_type'] as String?,
      lastWorkingDay: j['last_working_day'] as String?,
      items: (j['items'] as List)
          .map((e) => ChecklistItem.fromJson(e as Map<String, dynamic>))
          .toList(),
      progressPercent: j['progress_percent'] as int? ?? 0,
    );
  }
}
