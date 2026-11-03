// lib/widgets/flow_items_panel.dart
//
// HR's view of the documents and surveys given to one employee by their
// onboarding / offboarding flow: what was sent, what came back, and the
// buttons to view, approve, send back or remind. Used in the Lifecycle
// Insights row and on the employee's profile. Shows nothing when the
// employee has been given nothing.

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/api_client.dart';
import '../theme/selms_colors.dart';

class FlowItemsPanel extends StatefulWidget {
  const FlowItemsPanel({
    super.key,
    required this.api,
    required this.employeeId,
    this.process,
    this.initialDocuments,
    this.initialSurveys,
    this.onChanged,
  });

  final ApiClient api;
  final String employeeId;

  /// 'onboarding' or 'offboarding' to show only that flow's items; null = all.
  final String? process;
  final List<Map<String, dynamic>>? initialDocuments;
  final List<Map<String, dynamic>>? initialSurveys;

  /// Called after HR approves / sends back / reminds, so the page around it
  /// can refresh its own status line.
  final VoidCallback? onChanged;

  @override
  State<FlowItemsPanel> createState() => _FlowItemsPanelState();
}

class _FlowItemsPanelState extends State<FlowItemsPanel> {
  List<Map<String, dynamic>> _docs = [];
  List<Map<String, dynamic>> _surveys = [];
  bool _loaded = false;
  String? _busyId;
  final _openSurveys = <String>{};

  @override
  void initState() {
    super.initState();
    if (widget.initialDocuments != null || widget.initialSurveys != null) {
      _docs = widget.initialDocuments ?? [];
      _surveys = widget.initialSurveys ?? [];
      _loaded = true;
    } else {
      _reload();
    }
  }

  Future<void> _reload({bool notify = false}) async {
    try {
      final data = await widget.api.getEmployeeFlowItems(widget.employeeId);
      if (!mounted) return;
      bool keep(Map<String, dynamic> x) => widget.process == null || x['process'] == widget.process;
      setState(() {
        _docs = (data['documents'] as List).cast<Map<String, dynamic>>().where(keep).toList();
        _surveys = (data['surveys'] as List).cast<Map<String, dynamic>>().where(keep).toList();
        _loaded = true;
      });
    } catch (_) {
      if (mounted) setState(() => _loaded = true);
    }
    if (notify) widget.onChanged?.call();
  }

  void _toast(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message), backgroundColor: error ? SelmsColors.rose : null));
  }

  Future<void> _run(String id, Future<void> Function() action, String done) async {
    setState(() => _busyId = id);
    try {
      await action();
      _toast(done);
      await _reload(notify: true);
    } catch (e) {
      _toast('$e', error: true);
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  Future<void> _sendBack(Map<String, dynamic> d) async {
    final ctrl = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        title: Text('Reject "${d['title']}"', style: const TextStyle(fontSize: 15)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLines: 2,
          decoration: const InputDecoration(labelText: 'What should they fix?', hintText: 'e.g. The photo is blurry'),
          style: const TextStyle(fontSize: 13),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(ctrl.text.trim()),
            style: ElevatedButton.styleFrom(backgroundColor: SelmsColors.rose, foregroundColor: Colors.white),
            child: const Text('Reject'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (reason == null || reason.isEmpty || !mounted) return;
    await _run(d['id'] as String, () => widget.api.rejectFlowDoc(d['id'] as String, reason), 'Sent back for a new upload.');
  }

  void _open(String url) => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);

  (String, Color, Color) _docChip(Map<String, dynamic> d) {
    switch (d['status']) {
      case 'approved':
        return ('Approved', SelmsColors.statusActiveBg, SelmsColors.statusActiveText);
      case 'acknowledged':
        return ('Acknowledged', SelmsColors.statusActiveBg, SelmsColors.statusActiveText);
      case 'returned':
        return ('Uploaded - review', const Color(0xFFFAEEDA), const Color(0xFF854F0B));
      case 'rejected':
        return ('Rejected', const Color(0xFFFAECE7), const Color(0xFF993C1D));
      default:
        return (d['action'] == 'download' ? 'Sent' : 'Waiting for employee', const Color(0xFFF1EFE8), const Color(0xFF444441));
    }
  }

  Widget _chip((String, Color, Color) c) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: c.$2, borderRadius: BorderRadius.circular(20)),
        child: Text(c.$1, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w500, color: c.$3)),
      );

  Widget _heading(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(text,
            style: const TextStyle(
                fontSize: 10.5, fontWeight: FontWeight.w600, letterSpacing: 0.6, color: SelmsColors.textMuted)),
      );

  Widget _smallButton(String label, VoidCallback? onTap, {bool danger = false, bool primary = false}) => SizedBox(
        height: 28,
        child: primary
            ? ElevatedButton(
                onPressed: onTap,
                style: ElevatedButton.styleFrom(
                    backgroundColor: SelmsColors.ink,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    textStyle: const TextStyle(fontSize: 11.5)),
                child: Text(label),
              )
            : OutlinedButton(
                onPressed: onTap,
                style: OutlinedButton.styleFrom(
                    foregroundColor: danger ? SelmsColors.rose : SelmsColors.ink,
                    side: BorderSide(color: danger ? SelmsColors.roseBorder : SelmsColors.border),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    textStyle: const TextStyle(fontSize: 11.5)),
                child: Text(label),
              ),
      );

  /// One half of a document row: a small caption, the file name, and a button.
  Widget _filePane(String caption, String? name, String emptyText, String buttonLabel, VoidCallback? onTap) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: SelmsColors.fieldBg, borderRadius: BorderRadius.circular(8)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(caption,
              style: const TextStyle(
                  fontSize: 10, fontWeight: FontWeight.w600, letterSpacing: 0.5, color: SelmsColors.textMuted)),
          const SizedBox(height: 4),
          Text(name ?? emptyText,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 12, color: name == null ? SelmsColors.textMuted : SelmsColors.textPrimary)),
          const SizedBox(height: 8),
          if (name != null && onTap != null) _smallButton(buttonLabel, onTap),
        ],
      ),
    );
  }

  Widget _docRow(Map<String, dynamic> d) {
    final id = d['id'] as String;
    final status = d['status'] as String? ?? 'sent';
    final needsUpload = d['action'] == 'upload';
    final busy = _busyId == id;
    final returnedName = d['returned_filename'] as String?;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          color: Colors.white, border: Border.all(color: SelmsColors.border), borderRadius: BorderRadius.circular(8)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.description_outlined, size: 16, color: SelmsColors.textSecondary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(d['title'] as String? ?? 'Document',
                    style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: SelmsColors.textPrimary)),
              ),
              _chip(_docChip(d)),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Left: the file HR gave the employee.
              Expanded(
                child: _filePane(
                  'ORIGINAL FILE',
                  d['has_file'] == true ? (d['filename'] as String? ?? 'File') : null,
                  'No file attached',
                  'Open original',
                  () => _open(widget.api.hrFlowDocFileUrl(id)),
                ),
              ),
              if (needsUpload) ...[
                const SizedBox(width: 10),
                // Right: what the employee uploaded back.
                Expanded(
                  child: _filePane(
                    "EMPLOYEE'S UPLOAD",
                    returnedName?.isNotEmpty == true ? returnedName : null,
                    status == 'rejected' ? 'Waiting for a new upload' : 'Not uploaded yet',
                    'View upload',
                    () => _open(widget.api.hrFlowDocReturnedUrl(id)),
                  ),
                ),
              ],
            ],
          ),
          if (status == 'rejected' && (d['reject_reason'] as String?)?.isNotEmpty == true)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text('Rejected: ${d['reject_reason']}',
                  style: const TextStyle(fontSize: 11.5, color: SelmsColors.rose)),
            ),
          // Under both: HR's decision on the upload.
          if (status == 'returned') ...[
            const SizedBox(height: 10),
            Wrap(spacing: 8, runSpacing: 6, children: [
              _smallButton(busy ? 'Saving...' : 'Approve',
                  busy ? null : () => _run(id, () => widget.api.approveFlowDoc(id), 'Approved.'),
                  primary: true),
              _smallButton('Reject', busy ? null : () => _sendBack(d), danger: true),
            ]),
          ] else if (needsUpload && (status == 'sent' || status == 'rejected')) ...[
            const SizedBox(height: 10),
            _smallButton('Remind', busy ? null : () => _run(id, () => widget.api.remindFlowDoc(id), 'Reminder sent.')),
          ],
        ],
      ),
    );
  }

  String _answerText(Map<String, dynamic> q, dynamic a) {
    if (a == null || (a is String && a.isEmpty)) return '—';
    return switch (q['type']) {
      'rating' => '$a / 5',
      'yes_no' => a == 'yes' ? 'Yes' : 'No',
      _ => '$a',
    };
  }

  Widget _surveyRow(Map<String, dynamic> sv) {
    final id = sv['id'] as String;
    final submitted = sv['status'] == 'submitted';
    final open = _openSurveys.contains(id);
    final questions = (sv['questions'] as List? ?? const []).cast<Map<String, dynamic>>();
    final answers = (sv['answers'] as Map? ?? const {}).cast<String, dynamic>();
    final busy = _busyId == id;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
          color: Colors.white, border: Border.all(color: SelmsColors.border), borderRadius: BorderRadius.circular(8)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.fact_check_outlined, size: 16, color: SelmsColors.textSecondary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(sv['title'] as String? ?? 'Survey',
                    style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: SelmsColors.textPrimary)),
              ),
              _chip(submitted
                  ? ('Answered', SelmsColors.statusActiveBg, SelmsColors.statusActiveText)
                  : ('Waiting for employee', const Color(0xFFF1EFE8), const Color(0xFF444441))),
            ],
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.only(left: 24),
            child: Wrap(spacing: 8, runSpacing: 6, children: [
              if (submitted)
                _smallButton(open ? 'Hide answers' : 'View answers',
                    () => setState(() => open ? _openSurveys.remove(id) : _openSurveys.add(id))),
              if (!submitted)
                _smallButton(busy ? 'Sending...' : 'Remind',
                    busy ? null : () => _run(id, () => widget.api.remindFlowSurvey(id), 'Reminder sent.')),
            ]),
          ),
          if (submitted && open)
            Padding(
              padding: const EdgeInsets.only(left: 24, top: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final q in questions)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(q['text'] as String? ?? '',
                              style: const TextStyle(fontSize: 11.5, color: SelmsColors.textMuted)),
                          const SizedBox(height: 2),
                          Text(_answerText(q, answers[q['id']]),
                              style: const TextStyle(fontSize: 12.5, color: SelmsColors.textPrimary)),
                        ],
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded || (_docs.isEmpty && _surveys.isEmpty)) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_docs.isNotEmpty) ...[
          _heading('DOCUMENTS'),
          for (final d in _docs) _docRow(d),
        ],
        if (_surveys.isNotEmpty) ...[
          if (_docs.isNotEmpty) const SizedBox(height: 8),
          _heading('SURVEYS'),
          for (final sv in _surveys) _surveyRow(sv),
        ],
      ],
    );
  }
}
