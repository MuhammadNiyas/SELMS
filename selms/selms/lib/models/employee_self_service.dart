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
    this.meeting,
    this.shipment,
  });

  final String id;
  final String label;
  final bool done;
  final String? doneAt; // ISO string, set only for system-driven steps
  /// Only on the orientation step: {date, start_time, duration_minutes,
  /// mode, location, meeting_url} of the booked session, or null.
  final Map<String, dynamic>? meeting;
  /// Only on the equipment step, for remote hires whose equipment is
  /// posted: {status, pos_reference}, or null.
  final Map<String, dynamic>? shipment;

  factory ChecklistItem.fromJson(Map<String, dynamic> j) => ChecklistItem(
        id: j['id'] as String,
        label: j['label'] as String,
        done: j['done'] as bool? ?? false,
        doneAt: j['done_at'] as String?,
        meeting: j['meeting'] as Map<String, dynamic>?,
        shipment: j['shipment'] as Map<String, dynamic>?,
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

class NotificationItem {
  NotificationItem({
    required this.id,
    required this.title,
    required this.message,
    required this.at,
    required this.read,
    this.kind = 'notification',
    this.section,
    this.confirmId,
    this.confirmedAt,
  });

  final String id;
  final String title;
  final String message;
  final String at; // ISO string
  final bool read;
  final String kind; // notification | reminder
  /// onboarding | offboarding | messages, or null - where tapping it goes.
  final String? section;

  /// Set when this one needs "I got it": the id to confirm it with.
  final String? confirmId;
  final String? confirmedAt;

  factory NotificationItem.fromJson(Map<String, dynamic> j) => NotificationItem(
        id: j['id'] as String,
        title: j['title'] as String,
        message: j['message'] as String,
        at: j['at'] as String,
        read: j['read'] as bool? ?? false,
        kind: j['kind'] as String? ?? 'notification',
        section: j['section'] as String?,
        confirmId: j['confirm_id'] as String?,
        confirmedAt: j['confirmed_at'] as String?,
      );
}

class EmployeeNotifications {
  EmployeeNotifications({required this.items, required this.unreadCount, this.badges = const {}});

  final List<NotificationItem> items;
  final int unreadCount;

  /// Red badge counts per section: onboarding, offboarding, documents, messages.
  final Map<String, int> badges;

  factory EmployeeNotifications.fromJson(Map<String, dynamic> j) => EmployeeNotifications(
        items: (j['notifications'] as List)
            .map((e) => NotificationItem.fromJson(e as Map<String, dynamic>))
            .toList(),
        unreadCount: j['unread_count'] as int? ?? 0,
        badges: ((j['badges'] as Map?) ?? const {})
            .map((k, v) => MapEntry(k as String, (v as num).toInt())),
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
    this.notes,
    this.items = const [],
    this.progressPercent = 0,
  });

  final bool started;
  final String? departureType;
  final String? lastWorkingDay;
  final String? notes;
  final List<ChecklistItem> items;
  final int progressPercent;

  factory OffboardingChecklist.fromJson(Map<String, dynamic> j) {
    // Before Start, HR may already have saved the departure details.
    if (j['started'] != true) {
      return OffboardingChecklist(
        started: false,
        departureType: j['departure_type'] as String?,
        lastWorkingDay: j['last_working_day'] as String?,
        notes: j['notes'] as String?,
      );
    }
    return OffboardingChecklist(
      started: true,
      departureType: j['departure_type'] as String?,
      lastWorkingDay: j['last_working_day'] as String?,
      notes: j['notes'] as String?,
      items: (j['items'] as List)
          .map((e) => ChecklistItem.fromJson(e as Map<String, dynamic>))
          .toList(),
      progressPercent: j['progress_percent'] as int? ?? 0,
    );
  }
}
