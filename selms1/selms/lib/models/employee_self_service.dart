// lib/models/employee_self_service.dart
//
// Models for the employee's own view of themselves: the onboarding
// checklist (GET /api/employee/me/checklist) and the company documents
// they need to sign (GET /api/employee/me/documents).

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
