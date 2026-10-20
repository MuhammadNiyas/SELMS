// lib/widgets/flow_step_editors.dart
//
// The set-up dialogs for the two flow steps the employee takes part in:
//  * Documents - HR lists what the employee gets: a file to download only, or
//    a file to download and upload back.
//  * Survey - HR writes the questions (rating, yes / no, written answer).
// Shared by the onboarding and offboarding flow builders.

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../models/onboarding_flow_node.dart';
import '../services/api_client.dart';
import '../theme/selms_colors.dart';
import 'employee_avatar.dart';
import 'scheduling_dialog.dart' show PeoplePickerDialog;

String _newId() => DateTime.now().microsecondsSinceEpoch.toString();

const _attachExtensions = ['pdf', 'doc', 'docx', 'xls', 'xlsx', 'png', 'jpg', 'jpeg', 'txt'];

/// Builds the node for a Documents / Survey template, asking HR to fill it
/// in first. Null when HR backs out, so nothing half-empty reaches the flow.
Future<OnboardingFlowNode?> buildStepNode(
    BuildContext context, ApiClient api, FlowStepTemplate template, String id) async {
  final node = OnboardingFlowNode(id: id, type: 'action', icon: template.icon, label: template.label, step: template.step);
  final saved = await editStepNode(context, api, node);
  return saved ? node : null;
}

/// Opens the right editor for a Documents / Survey node and writes the
/// result back onto it. True when HR saved.
Future<bool> editStepNode(BuildContext context, ApiClient api, OnboardingFlowNode node) async {
  if (node.step == 'documents') {
    final docs = await showDialog<List<Map<String, dynamic>>>(
      context: context,
      builder: (_) => _DocumentsEditor(api: api, initial: node.docs),
    );
    if (docs == null) return false;
    node.docs = docs;
    node.label = 'Documents';
    node.sub = '${docs.length} document${docs.length == 1 ? '' : 's'}';
    return true;
  }
  if (node.step == 'email') {
    final cfg = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _EmailEditor(initial: node.email),
    );
    if (cfg == null) return false;
    node.email = cfg;
    // The step on the flow chart carries the subject the HR typed.
    node.label = 'Email: ${cfg['subject']}';
    node.sub = 'To ${_recipientsText(cfg)}';
    return true;
  }
  if (node.step == 'notification') {
    final cfg = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _NotificationEditor(api: api, initial: node.notify),
    );
    if (cfg == null) return false;
    node.notify = cfg;
    node.label = 'Send notification';
    node.sub = '"${cfg['title']}" to ${_recipientsText(cfg)}';
    return true;
  }
  if (node.step == 'survey') {
    final survey = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _SurveyEditor(initial: node.survey),
    );
    if (survey == null) return false;
    node.survey = survey;
    // "Survey: " keeps a survey's name from ever matching a built-in step.
    node.label = 'Survey: ${survey['title']}';
    final n = (survey['questions'] as List).length;
    node.sub = '$n question${n == 1 ? '' : 's'}';
    return true;
  }
  return false;
}

// ---------------------------------------------------------------------------

class _DocDraft {
  _DocDraft({String? id, String title = '', String instructions = '', this.action = 'download', this.fileId, this.filename})
      : id = id ?? _newId(),
        title = TextEditingController(text: title),
        instructions = TextEditingController(text: instructions);

  final String id;
  final TextEditingController title;
  final TextEditingController instructions;
  String action;
  String? fileId;
  String? filename;
  bool uploading = false;

  void dispose() {
    title.dispose();
    instructions.dispose();
  }
}

const _actionLabels = {
  'download': 'Download only',
  'upload': 'Download and upload back',
};

class _DocumentsEditor extends StatefulWidget {
  const _DocumentsEditor({required this.api, required this.initial});

  final ApiClient api;
  final List<Map<String, dynamic>> initial;

  @override
  State<_DocumentsEditor> createState() => _DocumentsEditorState();
}

class _DocumentsEditorState extends State<_DocumentsEditor> {
  late final List<_DocDraft> _drafts = widget.initial.isEmpty
      ? [_DocDraft()]
      : widget.initial
          .map((d) => _DocDraft(
                id: d['id'] as String?,
                title: d['title'] as String? ?? '',
                instructions: d['instructions'] as String? ?? '',
                action: d['action'] == 'upload' ? 'upload' : 'download', // older "acknowledge" = download
                fileId: d['file_id'] as String?,
                filename: d['filename'] as String?,
              ))
          .toList();
  String? _error;

  @override
  void dispose() {
    for (final d in _drafts) {
      d.dispose();
    }
    super.dispose();
  }

  Future<void> _attach(_DocDraft d) async {
    final file = await FilePicker.pickFile(type: FileType.custom, allowedExtensions: _attachExtensions);
    if (file == null || !mounted) return;
    setState(() {
      d.uploading = true;
      _error = null;
    });
    try {
      final bytes = await file.readAsBytes();
      final saved = await widget.api.uploadFlowFile(file.name, bytes);
      if (!mounted) return;
      setState(() {
        d.fileId = saved['file_id'] as String?;
        d.filename = saved['filename'] as String? ?? file.name;
        if (d.title.text.trim().isEmpty) {
          final dot = file.name.lastIndexOf('.');
          d.title.text = dot > 0 ? file.name.substring(0, dot) : file.name;
        }
      });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => d.uploading = false);
    }
  }

  void _save() {
    for (final d in _drafts) {
      if (d.title.text.trim().isEmpty) {
        setState(() => _error = 'Give every document a title.');
        return;
      }
      if (d.fileId == null) {
        setState(() => _error = '"${d.title.text.trim()}" needs a file for the employee to download.');
        return;
      }
    }
    Navigator.of(context).pop(_drafts
        .map((d) => {
              'id': d.id,
              'title': d.title.text.trim(),
              'action': d.action,
              'instructions': d.instructions.text.trim(),
              if (d.fileId != null) 'file_id': d.fileId,
              if (d.filename != null) 'filename': d.filename,
            })
        .toList());
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 680),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Documents for the employee',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: SelmsColors.textPrimary)),
              const SizedBox(height: 4),
              const Text(
                  'These appear in the employee\'s Documents tab when this step runs. Only HR and that employee can open them.',
                  style: TextStyle(fontSize: 11.5, color: SelmsColors.textMuted)),
              const SizedBox(height: 12),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(children: [for (final (i, d) in _drafts.indexed) _card(i, d)]),
                ),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(_error!, style: const TextStyle(fontSize: 12, color: SelmsColors.rose)),
                ),
              const SizedBox(height: 8),
              Row(
                children: [
                  TextButton.icon(
                    onPressed: () => setState(() => _drafts.add(_DocDraft())),
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('Add document', style: TextStyle(fontSize: 12.5)),
                  ),
                  const Spacer(),
                  TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
                  const SizedBox(width: 6),
                  ElevatedButton(
                    onPressed: _save,
                    style: ElevatedButton.styleFrom(backgroundColor: SelmsColors.ink, foregroundColor: Colors.white),
                    child: const Text('Save'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _card(int i, _DocDraft d) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: SelmsColors.fieldBg,
        border: Border.all(color: SelmsColors.border),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: d.title,
                  decoration: const InputDecoration(labelText: 'Document title', isDense: true),
                  style: const TextStyle(fontSize: 13),
                ),
              ),
              if (_drafts.length > 1)
                IconButton(
                  tooltip: 'Remove',
                  onPressed: () => setState(() => _drafts.removeAt(i).dispose()),
                  icon: const Icon(Icons.delete_outline, size: 18, color: SelmsColors.rose),
                ),
            ],
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            initialValue: d.action,
            isDense: true,
            decoration: const InputDecoration(labelText: 'What the employee does', isDense: true),
            items: [
              for (final e in _actionLabels.entries)
                DropdownMenuItem(value: e.key, child: Text(e.value, style: const TextStyle(fontSize: 13))),
            ],
            onChanged: (v) => setState(() => d.action = v ?? d.action),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: d.instructions,
            decoration: const InputDecoration(labelText: 'Instructions (optional)', isDense: true),
            style: const TextStyle(fontSize: 13),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              OutlinedButton.icon(
                onPressed: d.uploading ? null : () => _attach(d),
                icon: d.uploading
                    ? const SizedBox(width: 13, height: 13, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.attach_file, size: 15),
                label: Text(d.filename == null ? 'Attach file' : 'Replace file', style: const TextStyle(fontSize: 12)),
              ),
              const SizedBox(width: 10),
              if (d.filename != null)
                Expanded(
                  child: Text(d.filename!,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12, color: SelmsColors.textSecondary)),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _QuestionDraft {
  _QuestionDraft({String? id, String text = '', this.type = 'rating'})
      : id = id ?? _newId(),
        text = TextEditingController(text: text);

  final String id;
  final TextEditingController text;
  String type;
}

const _questionTypes = {
  'rating': 'Rating (1 to 5)',
  'yes_no': 'Yes / No',
  'text': 'Written answer',
};

class _SurveyEditor extends StatefulWidget {
  const _SurveyEditor({required this.initial});

  final Map<String, dynamic>? initial;

  @override
  State<_SurveyEditor> createState() => _SurveyEditorState();
}

class _SurveyEditorState extends State<_SurveyEditor> {
  late final TextEditingController _title = TextEditingController(text: widget.initial?['title'] as String? ?? '');
  late final List<_QuestionDraft> _questions = (() {
    final saved = (widget.initial?['questions'] as List?) ?? const [];
    if (saved.isEmpty) return [_QuestionDraft()];
    return saved
        .map((q) => _QuestionDraft(
              id: (q as Map)['id'] as String?,
              text: q['text'] as String? ?? '',
              type: q['type'] as String? ?? 'rating',
            ))
        .toList();
  })();
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    for (final q in _questions) {
      q.text.dispose();
    }
    super.dispose();
  }

  void _save() {
    if (_title.text.trim().isEmpty) {
      setState(() => _error = 'Give the survey a title.');
      return;
    }
    if (_questions.any((q) => q.text.text.trim().isEmpty)) {
      setState(() => _error = 'Every question needs some text.');
      return;
    }
    Navigator.of(context).pop({
      'title': _title.text.trim(),
      'questions': _questions.map((q) => {'id': q.id, 'text': q.text.text.trim(), 'type': q.type}).toList(),
    });
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 660),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Survey',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: SelmsColors.textPrimary)),
              const SizedBox(height: 4),
              const Text('The employee answers in their Documents tab. You see the answers in Lifecycle Insights.',
                  style: TextStyle(fontSize: 11.5, color: SelmsColors.textMuted)),
              const SizedBox(height: 12),
              TextField(
                controller: _title,
                decoration: const InputDecoration(labelText: 'Survey title', hintText: 'e.g. Week 1 check-in', isDense: true),
                style: const TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 12),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      for (final (i, q) in _questions.indexed)
                        Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: SelmsColors.fieldBg,
                            border: Border.all(color: SelmsColors.border),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: TextField(
                                      controller: q.text,
                                      decoration: InputDecoration(labelText: 'Question ${i + 1}', isDense: true),
                                      style: const TextStyle(fontSize: 13),
                                    ),
                                  ),
                                  if (_questions.length > 1)
                                    IconButton(
                                      tooltip: 'Remove',
                                      onPressed: () => setState(() => _questions.removeAt(i).text.dispose()),
                                      icon: const Icon(Icons.delete_outline, size: 18, color: SelmsColors.rose),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              DropdownButtonFormField<String>(
                                initialValue: q.type,
                                isDense: true,
                                decoration: const InputDecoration(labelText: 'Answer type', isDense: true),
                                items: [
                                  for (final e in _questionTypes.entries)
                                    DropdownMenuItem(value: e.key, child: Text(e.value, style: const TextStyle(fontSize: 13))),
                                ],
                                onChanged: (v) => setState(() => q.type = v ?? q.type),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(_error!, style: const TextStyle(fontSize: 12, color: SelmsColors.rose)),
                ),
              const SizedBox(height: 8),
              Row(
                children: [
                  TextButton.icon(
                    onPressed: () => setState(() => _questions.add(_QuestionDraft())),
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('Add question', style: TextStyle(fontSize: 12.5)),
                  ),
                  const Spacer(),
                  TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
                  const SizedBox(width: 6),
                  ElevatedButton(
                    onPressed: _save,
                    style: ElevatedButton.styleFrom(backgroundColor: SelmsColors.ink, foregroundColor: Colors.white),
                    child: const Text('Save'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Timing: only the steps where "when" matters most get a clock. Two choices:
// immediately, or on a specific date.

const _timedOnboarding = {'Send welcome email': 'reminder', 'Prepare IT equipment': 'do', 'Schedule orientation': 'meeting'};
const _timedOffboarding = {
  'Send offboarding email': 'reminder',
  'Retrieve IT equipment': 'do',
  'Schedule exit interview': 'meeting',
};

/// 'do' (SELMS waits for the day), 'meeting' (booked now, aimed at the day),
/// 'reminder' (HR sends it; reminded on the day) - or null when the step has no timing.
String? timingKind(OnboardingFlowNode node, String process) {
  if (node.step == 'documents' || node.step == 'survey' || node.step == 'notification' || node.step == 'email') return 'do';
  final fixed = (process == 'onboarding' ? _timedOnboarding : _timedOffboarding)[node.label];
  if (fixed != null) return fixed;
  // HR's own steps added with "+" (email, notification, meeting...): HR does them,
  // so a timing means "remind me on this day".
  if (node.type == 'action' && !node.locked) return 'reminder';
  return null;
}

bool supportsTiming(OnboardingFlowNode node, String process) => timingKind(node, process) != null;

String _dmy(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

/// 9:00 AM
String _hm12(TimeOfDay t) =>
    '${t.hourOfPeriod == 0 ? 12 : t.hourOfPeriod}:${t.minute.toString().padLeft(2, '0')} ${t.period == DayPeriod.am ? 'AM' : 'PM'}';

TimeOfDay? _parseTime(String? s) {
  final m = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(s ?? '');
  if (m == null) return null;
  return TimeOfDay(hour: int.parse(m.group(1)!), minute: int.parse(m.group(2)!));
}

/// The moment a step is timed for (date + time; midnight for older steps saved
/// without a time), or null when it runs immediately.
DateTime? whenDateTime(Map<String, dynamic>? when) {
  if ((when?['mode'] as String?) != 'on_date') return null;
  final d = DateTime.tryParse(when?['date'] as String? ?? '');
  if (d == null) return null;
  final t = _parseTime(when?['time'] as String?);
  return DateTime(d.year, d.month, d.day, t?.hour ?? 0, t?.minute ?? 0);
}

/// 21/10/2026, 9:00 AM
String whenAtText(Map<String, dynamic>? when) {
  final d = whenDateTime(when);
  if (d == null) return '';
  final t = _parseTime(when?['time'] as String?);
  return t == null ? _dmy(d) : '${_dmy(d)}, ${_hm12(t)}';
}

String whenSummary(Map<String, dynamic>? when, String process) {
  if ((when?['mode'] as String?) == 'on_date') {
    final text = whenAtText(when);
    return text.isEmpty ? 'On a date' : 'On $text';
  }
  return 'Immediately';
}

/// Opens the timing dialog. [employee] is whoever is picked at the top of the
/// page (null while editing the default template). Returns the new setting,
/// or null when cancelled.
Future<Map<String, dynamic>?> showWhenDialog(
  BuildContext context, {
  required OnboardingFlowNode node,
  required String process,
  required String apiBaseUrl,
  Map<String, dynamic>? employee,
  String? notAfter,
}) {
  return showDialog<Map<String, dynamic>>(
    context: context,
    builder: (_) => _WhenDialog(
      node: node,
      process: process,
      kind: timingKind(node, process) ?? 'do',
      apiBaseUrl: apiBaseUrl,
      employee: employee,
      notAfter: DateTime.tryParse(notAfter ?? ''),
    ),
  );
}

class _WhenDialog extends StatefulWidget {
  const _WhenDialog({
    required this.node,
    required this.process,
    required this.kind,
    required this.apiBaseUrl,
    required this.employee,
    this.notAfter,
  });

  final OnboardingFlowNode node;
  final String process;
  final String kind;
  final String apiBaseUrl;
  final Map<String, dynamic>? employee;
  /// Offboarding: the last working day - nothing can be timed after it.
  final DateTime? notAfter;

  @override
  State<_WhenDialog> createState() => _WhenDialogState();
}

class _WhenDialogState extends State<_WhenDialog> {
  late String _mode = (widget.node.when?['mode'] as String?) == 'on_date' ? 'on_date' : 'now';
  DateTime? _date;
  TimeOfDay _time = const TimeOfDay(hour: 9, minute: 0);
  String? _error;

  @override
  void initState() {
    super.initState();
    _date = DateTime.tryParse(widget.node.when?['date'] as String? ?? '');
    _time = _parseTime(widget.node.when?['time'] as String?) ?? _time;
  }

  String get _explain => switch (widget.kind) {
        'meeting' =>
          'Pick the day and time for the session (10 AM - 5 PM, Mon - Fri). If it clashes with another session you will be asked to pick another. Immediately = the first free slot from now.',
        'reminder' => 'HR is reminded at this day and time. You can still send it earlier.',
        _ => 'SELMS waits until this day and time, then does it (within a few minutes).',
      };

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final hire = DateTime.tryParse(widget.employee?['hire_date'] as String? ?? '');
    final first = DateTime(now.year - 1);
    final last = widget.notAfter ?? DateTime(now.year + 3);
    var initial = _date ?? hire ?? now;
    if (initial.isAfter(last)) initial = last;
    if (initial.isBefore(first)) initial = first;
    final picked = await showDatePicker(context: context, initialDate: initial, firstDate: first, lastDate: last);
    if (picked != null) {
      setState(() {
        _date = picked;
        _error = null;
      });
    }
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(context: context, initialTime: _time);
    if (picked != null) setState(() => _time = picked);
  }

  void _save() {
    if (_mode == 'now') return Navigator.of(context).pop({'mode': 'now'});
    final d = _date;
    if (d == null) return;
    final lastDay = widget.notAfter;
    if (lastDay != null && DateTime(d.year, d.month, d.day).isAfter(lastDay)) {
      setState(() => _error = "You can't choose this — it's after their last working day (${_dmy(lastDay)}).");
      return;
    }
    Navigator.of(context).pop({
      'mode': 'on_date',
      'date': '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}',
      'time': '${_time.hour.toString().padLeft(2, '0')}:${_time.minute.toString().padLeft(2, '0')}',
    });
  }

  /// Who this timing is for: photo, name, ID, department and hire date.
  Widget _employeeCard() {
    final e = widget.employee;
    if (e == null) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: SelmsColors.fieldBg, borderRadius: BorderRadius.circular(10)),
        child: const Text(
            'Default template - applies to every new employee. Pick an employee at the top of the page to time this step for one person and see their hire date.',
            style: TextStyle(fontSize: 11.5, color: SelmsColors.textSecondary, height: 1.4)),
      );
    }
    final hire = DateTime.tryParse(e['hire_date'] as String? ?? '');
    final dept = (e['department'] as String?) ?? '';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: SelmsColors.accentBg,
        border: Border.all(color: SelmsColors.ink),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          EmployeeAvatar(
            apiBaseUrl: widget.apiBaseUrl,
            name: e['full_name'] as String? ?? '',
            photoUrl: e['profile_image_url'] as String?,
            size: 40,
            background: Colors.white,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(e['full_name'] as String? ?? '',
                    style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: SelmsColors.textPrimary)),
                Text([e['employee_id'], if (dept.isNotEmpty) dept].join(' · '),
                    style: const TextStyle(fontSize: 11.5, color: SelmsColors.textSecondary)),
                const SizedBox(height: 2),
                Text('Hire date: ${hire == null ? 'not set' : _dmy(hire)}',
                    style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w500, color: SelmsColors.ink)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _option(String mode, String title, {Widget? extra, Widget? below}) {
    final selected = _mode == mode;
    return InkWell(
      onTap: () => setState(() => _mode = mode),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? SelmsColors.accentBg : Colors.white,
          border: Border.all(color: selected ? SelmsColors.ink : SelmsColors.border),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                    size: 17, color: selected ? SelmsColors.ink : SelmsColors.textMuted),
                const SizedBox(width: 10),
                Expanded(child: Text(title, style: const TextStyle(fontSize: 13))),
                if (selected && extra != null) extra,
              ],
            ),
            if (selected && below != null) Padding(padding: const EdgeInsets.only(left: 27, top: 8), child: below),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('When: ${widget.node.label}',
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: SelmsColors.textPrimary)),
              const SizedBox(height: 10),
              _employeeCard(),
              const SizedBox(height: 10),
              Text(_explain, style: const TextStyle(fontSize: 11.5, color: SelmsColors.textMuted, height: 1.4)),
              const SizedBox(height: 12),
              _option('now', 'Immediately',
                  extra: const Text('when it starts', style: TextStyle(fontSize: 11.5, color: SelmsColors.textMuted))),
              _option('on_date', 'On a specific date',
                  below: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      OutlinedButton(
                        onPressed: _pickDate,
                        style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
                        child: Text(_date == null ? 'Pick a date' : _dmy(_date!), style: const TextStyle(fontSize: 12)),
                      ),
                      OutlinedButton(
                        onPressed: _pickTime,
                        style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
                        child: Text(_hm12(_time), style: const TextStyle(fontSize: 12)),
                      ),
                    ],
                  )),
              if (widget.notAfter != null)
                Text('Must be on or before the last working day (${_dmy(widget.notAfter!)}).',
                    style: const TextStyle(fontSize: 11, color: SelmsColors.textMuted)),
              if (_error != null) ...[
                const SizedBox(height: 6),
                Text(_error!, style: const TextStyle(fontSize: 12, color: SelmsColors.rose)),
              ],
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
                  const SizedBox(width: 6),
                  ElevatedButton(
                    onPressed: (_mode == 'on_date' && _date == null) ? null : _save,
                    style: ElevatedButton.styleFrom(backgroundColor: SelmsColors.ink, foregroundColor: Colors.white),
                    child: const Text('Save'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Send notification: who gets the bell message, and what it says.

String _recipientsText(Map<String, dynamic> cfg) {
  final to = (cfg['to'] as Map?) ?? const {};
  final parts = <String>[
    if (to['employee'] == true) 'the employee',
    if (to['it'] == true) 'IT',
    if (to['hr'] == true) 'HR',
    for (final p in (cfg['people'] as List? ?? const [])) (p as Map)['name'] as String? ?? 'someone',
  ];
  return parts.isEmpty ? 'no one yet' : parts.join(', ');
}

class _NotificationEditor extends StatefulWidget {
  const _NotificationEditor({required this.api, required this.initial});

  final ApiClient api;
  final Map<String, dynamic>? initial;

  @override
  State<_NotificationEditor> createState() => _NotificationEditorState();
}

class _NotificationEditorState extends State<_NotificationEditor> {
  late final TextEditingController _title = TextEditingController(text: widget.initial?['title'] as String? ?? '');
  late final TextEditingController _message = TextEditingController(text: widget.initial?['message'] as String? ?? '');
  late bool _employee = ((widget.initial?['to'] as Map?)?['employee'] ?? true) == true;
  late bool _it = ((widget.initial?['to'] as Map?)?['it'] ?? false) == true;
  late bool _hr = ((widget.initial?['to'] as Map?)?['hr'] ?? false) == true;
  late final List<Map<String, dynamic>> _people = [
    for (final p in (widget.initial?['people'] as List? ?? const [])) Map<String, dynamic>.from(p as Map),
  ];
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    _message.dispose();
    super.dispose();
  }

  Future<void> _addPeople() async {
    final picked = await showDialog<List<Map<String, dynamic>>>(
      context: context,
      builder: (_) => PeoplePickerDialog(
        api: widget.api,
        apiBaseUrl: widget.api.baseUrl,
        selected: List.of(_people),
        title: 'Send to specific people',
      ),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _people
        ..clear()
        ..addAll([
          for (final p in picked) {'id': p['id'], 'name': p['name'], 'role': p['role']},
        ]);
    });
  }

  void _save() {
    if (_title.text.trim().isEmpty) {
      setState(() => _error = 'Give the notification a title.');
      return;
    }
    if (!_employee && !_it && !_hr && _people.isEmpty) {
      setState(() => _error = 'Choose who should get it.');
      return;
    }
    Navigator.of(context).pop({
      'title': _title.text.trim(),
      'message': _message.text.trim(),
      'to': {'employee': _employee, 'it': _it, 'hr': _hr},
      'people': _people,
    });
  }

  Widget _toChip(String label, bool value, ValueChanged<bool> onChanged) => FilterChip(
        label: Text(label, style: const TextStyle(fontSize: 12)),
        selected: value,
        onSelected: (v) => setState(() => onChanged(v)),
        backgroundColor: Colors.white,
        selectedColor: SelmsColors.accentBg,
        checkmarkColor: SelmsColors.ink,
        side: BorderSide(color: value ? SelmsColors.ink : SelmsColors.border),
      );

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480, maxHeight: 680),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Send notification',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: SelmsColors.textPrimary)),
              const SizedBox(height: 4),
              const Text('SELMS sends this to their bell by itself when the step comes up (or on its date).',
                  style: TextStyle(fontSize: 11.5, color: SelmsColors.textMuted)),
              const SizedBox(height: 12),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextField(
                        controller: _title,
                        decoration: const InputDecoration(labelText: 'Title', isDense: true),
                        style: const TextStyle(fontSize: 13),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _message,
                        maxLines: 4,
                        decoration: const InputDecoration(
                          labelText: 'Message',
                          isDense: true,
                          helperText: 'You can use {name}, {department}, {job_title}, {employee_id} and {hire_date}.',
                          helperMaxLines: 2,
                        ),
                        style: const TextStyle(fontSize: 13),
                      ),
                      const SizedBox(height: 14),
                      const Text('Send to',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: SelmsColors.textSecondary)),
                      const SizedBox(height: 6),
                      Wrap(spacing: 8, runSpacing: 6, children: [
                        _toChip('The employee', _employee, (v) => _employee = v),
                        _toChip('IT', _it, (v) => _it = v),
                        _toChip('HR', _hr, (v) => _hr = v),
                      ]),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          const Expanded(
                            child: Text('Specific people',
                                style: TextStyle(
                                    fontSize: 12, fontWeight: FontWeight.w600, color: SelmsColors.textSecondary)),
                          ),
                          TextButton.icon(
                            onPressed: _addPeople,
                            icon: const Icon(Icons.person_add_alt_1_outlined, size: 15),
                            label: Text(_people.isEmpty ? 'Pick people' : 'Change', style: const TextStyle(fontSize: 12)),
                          ),
                        ],
                      ),
                      if (_people.isEmpty)
                        const Text('No one picked. Optional: a buddy, a manager, anyone.',
                            style: TextStyle(fontSize: 11.5, color: SelmsColors.textMuted))
                      else
                        Wrap(spacing: 6, runSpacing: 6, children: [
                          for (final p in _people)
                            Chip(
                              label: Text(p['name'] as String? ?? '', style: const TextStyle(fontSize: 12)),
                              onDeleted: () => setState(() => _people.remove(p)),
                              visualDensity: VisualDensity.compact,
                              backgroundColor: SelmsColors.accentBg,
                              side: BorderSide.none,
                            ),
                        ]),
                      const SizedBox(height: 6),
                      const Text(
                          'HR and IT staff share one inbox per team, so picking a person from HR or IT reaches that team.',
                          style: TextStyle(fontSize: 10.5, color: SelmsColors.textMuted)),
                    ],
                  ),
                ),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(_error!, style: const TextStyle(fontSize: 12, color: SelmsColors.rose)),
                ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
                  const SizedBox(width: 6),
                  ElevatedButton(
                    onPressed: _save,
                    style: ElevatedButton.styleFrom(backgroundColor: SelmsColors.ink, foregroundColor: Colors.white),
                    child: const Text('Save'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Send email: starts blank. HR writes the subject (which also names the step on
// the flow chart), the message, and picks who gets it: the employee in the flow,
// the IT team or the HR team - nobody else. Save, and the flow sends it.

class _EmailEditor extends StatefulWidget {
  const _EmailEditor({required this.initial});

  final Map<String, dynamic>? initial;

  @override
  State<_EmailEditor> createState() => _EmailEditorState();
}

class _EmailEditorState extends State<_EmailEditor> {
  late final TextEditingController _subject = TextEditingController(text: widget.initial?['subject'] as String? ?? '');
  late final TextEditingController _message = TextEditingController(text: widget.initial?['message'] as String? ?? '');
  late bool _employee = ((widget.initial?['to'] as Map?)?['employee'] ?? false) == true;
  late bool _it = ((widget.initial?['to'] as Map?)?['it'] ?? false) == true;
  late bool _hr = ((widget.initial?['to'] as Map?)?['hr'] ?? false) == true;
  String? _error;

  @override
  void dispose() {
    _subject.dispose();
    _message.dispose();
    super.dispose();
  }

  void _save() {
    if (_subject.text.trim().isEmpty) {
      setState(() => _error = 'Write a subject. It also becomes the name of this step.');
      return;
    }
    if (_message.text.trim().isEmpty) {
      setState(() => _error = 'Write the message.');
      return;
    }
    if (!_employee && !_it && !_hr) {
      setState(() => _error = 'Choose who should get it.');
      return;
    }
    Navigator.of(context).pop({
      'subject': _subject.text.trim(),
      'message': _message.text.trim(),
      'to': {'employee': _employee, 'it': _it, 'hr': _hr},
    });
  }

  Widget _toChip(String label, bool value, ValueChanged<bool> onChanged) => FilterChip(
        label: Text(label, style: const TextStyle(fontSize: 12)),
        selected: value,
        onSelected: (v) => setState(() => onChanged(v)),
        backgroundColor: Colors.white,
        selectedColor: SelmsColors.accentBg,
        checkmarkColor: SelmsColors.ink,
        side: BorderSide(color: value ? SelmsColors.ink : SelmsColors.border),
      );

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 500, maxHeight: 640),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Send email',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: SelmsColors.textPrimary)),
              const SizedBox(height: 4),
              const Text('Save it and the flow sends it for you when this step comes up (or on its date).',
                  style: TextStyle(fontSize: 11.5, color: SelmsColors.textMuted)),
              const SizedBox(height: 12),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextField(
                        controller: _subject,
                        autofocus: widget.initial == null,
                        decoration: const InputDecoration(labelText: 'Subject', isDense: true),
                        style: const TextStyle(fontSize: 13),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _message,
                        maxLines: 8,
                        decoration: const InputDecoration(
                          labelText: 'Message',
                          alignLabelWithHint: true,
                          helperText: 'You can use {name}, {department}, {job_title}, {employee_id} and {hire_date}.',
                          helperMaxLines: 2,
                        ),
                        style: const TextStyle(fontSize: 13),
                      ),
                      const SizedBox(height: 14),
                      const Text('Send to',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: SelmsColors.textSecondary)),
                      const SizedBox(height: 6),
                      Wrap(spacing: 8, runSpacing: 6, children: [
                        _toChip('The employee', _employee, (v) => _employee = v),
                        _toChip('IT team', _it, (v) => _it = v),
                        _toChip('HR team', _hr, (v) => _hr = v),
                      ]),
                      const SizedBox(height: 6),
                      const Text(
                          'The employee is the person chosen at the top of the page. Only these three can be picked.',
                          style: TextStyle(fontSize: 10.5, color: SelmsColors.textMuted)),
                    ],
                  ),
                ),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(_error!, style: const TextStyle(fontSize: 12, color: SelmsColors.rose)),
                ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
                  const SizedBox(width: 6),
                  ElevatedButton(
                    onPressed: _save,
                    style: ElevatedButton.styleFrom(backgroundColor: SelmsColors.ink, foregroundColor: Colors.white),
                    child: const Text('Save'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
