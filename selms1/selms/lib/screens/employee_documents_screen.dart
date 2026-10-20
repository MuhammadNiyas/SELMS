// lib/screens/employee_documents_screen.dart
//
// The employee's Documents tab holds ONLY what HR has given them through
// their onboarding / offboarding flow:
//  * documents to download, to read and acknowledge, or to sign and upload back
//  * surveys to answer
// Nothing else is listed here - no standing company library.

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/api_client.dart';
import '../theme/selms_colors.dart';
import '../widgets/employee_ui.dart';

class EmployeeDocumentsScreen extends StatefulWidget {
  const EmployeeDocumentsScreen({super.key, required this.api});

  final ApiClient api;

  @override
  State<EmployeeDocumentsScreen> createState() => _EmployeeDocumentsScreenState();
}

class _EmployeeDocumentsScreenState extends State<EmployeeDocumentsScreen> {
  late Future<Map<String, dynamic>> _future = widget.api.getMyFlowItems();

  Future<void> _refresh() async {
    setState(() { _future = widget.api.getMyFlowItems(); });
    await _future;
  }

  // ---------- Documents and surveys HR gave this employee ----------

  String? _busyId;

  void _toast(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message), backgroundColor: error ? SelmsColors.rose : null));
  }

  Future<void> _acknowledgeFlowDoc(Map<String, dynamic> d) async {
    setState(() => _busyId = d['id'] as String);
    try {
      await widget.api.acknowledgeFlowDoc(d['id'] as String);
      _toast('${d['title']} acknowledged.');
      await _refresh();
    } catch (e) {
      _toast('$e', error: true);
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  Future<void> _uploadBack(Map<String, dynamic> d) async {
    final file = await FilePicker.pickFile(
        type: FileType.custom, allowedExtensions: const ['pdf', 'doc', 'docx', 'png', 'jpg', 'jpeg']);
    if (file == null || !mounted) return;
    setState(() => _busyId = d['id'] as String);
    try {
      await widget.api.uploadFlowDocReturn(d['id'] as String, file.name, await file.readAsBytes());
      _toast('Uploaded. HR will review it.');
      await _refresh();
    } catch (e) {
      _toast('$e', error: true);
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  Future<void> _answerSurvey(Map<String, dynamic> survey) async {
    final questions = (survey['questions'] as List).cast<Map<String, dynamic>>();
    final answers = <String, dynamic>{};
    final textCtrls = {for (final q in questions) q['id'] as String: TextEditingController()};
    String? error;
    final submitted = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) => AlertDialog(
          backgroundColor: Colors.white,
          title: Text(survey['title'] as String? ?? 'Survey', style: const TextStyle(fontSize: 15)),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final q in questions) ...[
                    Text(q['text'] as String? ?? '', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    if (q['type'] == 'rating')
                      Wrap(spacing: 6, children: [
                        for (var n = 1; n <= 5; n++)
                          ChoiceChip(
                            label: Text('$n'),
                            selected: answers[q['id']] == n,
                            onSelected: (_) => setDialog(() => answers[q['id'] as String] = n),
                          ),
                      ])
                    else if (q['type'] == 'yes_no')
                      Wrap(spacing: 6, children: [
                        for (final v in const ['yes', 'no'])
                          ChoiceChip(
                            label: Text(v == 'yes' ? 'Yes' : 'No'),
                            selected: answers[q['id']] == v,
                            onSelected: (_) => setDialog(() => answers[q['id'] as String] = v),
                          ),
                      ])
                    else
                      TextField(
                        controller: textCtrls[q['id']],
                        maxLines: 3,
                        decoration: const InputDecoration(hintText: 'Your answer (optional)', isDense: true),
                        style: const TextStyle(fontSize: 13),
                      ),
                    const SizedBox(height: 14),
                  ],
                  if (error != null) Text(error!, style: const TextStyle(fontSize: 12, color: SelmsColors.rose)),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Not now')),
            ElevatedButton(
              onPressed: () {
                for (final q in questions) {
                  if (q['type'] == 'text') {
                    answers[q['id'] as String] = textCtrls[q['id']]!.text.trim();
                  } else if (answers[q['id']] == null) {
                    setDialog(() => error = 'Please answer every question.');
                    return;
                  }
                }
                Navigator.of(ctx).pop(true);
              },
              style: ElevatedButton.styleFrom(backgroundColor: SelmsColors.ink, foregroundColor: Colors.white),
              child: const Text('Submit'),
            ),
          ],
        ),
      ),
    );
    for (final c in textCtrls.values) {
      c.dispose();
    }
    if (submitted != true || !mounted) return;
    setState(() => _busyId = survey['id'] as String);
    try {
      await widget.api.submitFlowSurvey(survey['id'] as String, answers);
      _toast('Thank you - your answers were sent.');
      await _refresh();
    } catch (e) {
      _toast('$e', error: true);
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  List<Widget> _flowSections(Map<String, dynamic> items) {
    final docs = (items['documents'] as List? ?? const []).cast<Map<String, dynamic>>();
    final surveys = (items['surveys'] as List? ?? const []).cast<Map<String, dynamic>>();
    if (docs.isEmpty && surveys.isEmpty) return const [];
    final open = docs.where((d) => const {'sent', 'rejected'}.contains(d['status']) && d['action'] != 'download').length +
        surveys.where((s) => s['status'] != 'submitted').length;
    return [
      EmpSectionHeader(
        'From HR',
        trailing: open == 0
            ? const EmpPill('All done', bg: EmpColors.successBg, fg: EmpColors.success, icon: Icons.check)
            : EmpPill('$open to do', bg: EmpColors.warningBg, fg: EmpColors.warning),
      ),
      for (final d in docs)
        Padding(padding: const EdgeInsets.only(bottom: 10), child: _flowDocCard(d)),
      for (final sv in surveys)
        Padding(padding: const EdgeInsets.only(bottom: 10), child: _surveyCard(sv)),
      const SizedBox(height: 6),
    ];
  }

  Widget _flowDocCard(Map<String, dynamic> d) {
    final id = d['id'] as String;
    final action = d['action'] as String? ?? 'download';
    final status = d['status'] as String? ?? 'sent';
    final busy = _busyId == id;
    final instructions = (d['instructions'] as String? ?? '').trim();
    final done = status == 'acknowledged' || status == 'approved';

    String line;
    Color lineColor = SelmsColors.textMuted;
    switch (status) {
      case 'acknowledged':
        line = 'Acknowledged ${empDate(d['acknowledged_at'] as String?)}';
      case 'approved':
        line = 'Approved by HR ${empDate(d['approved_at'] as String?)}';
      case 'returned':
        line = 'Waiting for HR to review - ${d['returned_filename'] ?? 'uploaded'}';
      case 'rejected':
        line = 'Please upload again: ${d['reject_reason'] ?? ''}';
        lineColor = SelmsColors.rose;
      default:
        line = switch (action) {
          'acknowledge' => 'Read, then acknowledge',
          'upload' => 'Download it, fill it in, then upload it back',
          _ => 'For you to download',
        };
    }

    final buttons = <Widget>[
      if (d['has_file'] == true)
        OutlinedButton.icon(
          onPressed: () => launchUrl(Uri.parse(widget.api.myFlowDocFileUrl(id)), mode: LaunchMode.externalApplication),
          icon: const Icon(Icons.download_outlined, size: 15),
          label: const Text('Download', style: TextStyle(fontSize: 12)),
        ),
      if (action == 'acknowledge' && status == 'sent')
        ElevatedButton(
          onPressed: busy ? null : () => _acknowledgeFlowDoc(d),
          style: ElevatedButton.styleFrom(backgroundColor: SelmsColors.ink, foregroundColor: Colors.white, elevation: 0),
          child: busy
              ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Text('I acknowledge', style: TextStyle(fontSize: 12)),
        ),
      if (action == 'upload' && const {'sent', 'rejected', 'returned'}.contains(status))
        ElevatedButton.icon(
          onPressed: busy ? null : () => _uploadBack(d),
          icon: busy
              ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.upload_file, size: 15),
          label: Text(status == 'returned' ? 'Replace file' : 'Upload it back', style: const TextStyle(fontSize: 12)),
          style: ElevatedButton.styleFrom(backgroundColor: SelmsColors.ink, foregroundColor: Colors.white, elevation: 0),
        ),
    ];

    return EmpCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              EmpIconBadge(
                done ? Icons.task_alt : (action == 'upload' ? Icons.upload_file : Icons.description_outlined),
                bg: done ? EmpColors.successBg : SelmsColors.accentBg,
                fg: done ? EmpColors.success : SelmsColors.ink,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(d['title'] as String? ?? 'Document',
                        style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
                    if (instructions.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(instructions, style: const TextStyle(fontSize: 12, color: SelmsColors.textSecondary, height: 1.35)),
                    ],
                    const SizedBox(height: 4),
                    Text(line, style: TextStyle(fontSize: 11.5, color: lineColor)),
                  ],
                ),
              ),
            ],
          ),
          if (buttons.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(spacing: 8, runSpacing: 8, children: buttons),
          ],
        ],
      ),
    );
  }

  Widget _surveyCard(Map<String, dynamic> sv) {
    final id = sv['id'] as String;
    final submitted = sv['status'] == 'submitted';
    final busy = _busyId == id;
    final count = (sv['questions'] as List? ?? const []).length;
    return EmpCard(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          EmpIconBadge(
            submitted ? Icons.task_alt : Icons.fact_check_outlined,
            bg: submitted ? EmpColors.successBg : SelmsColors.accentBg,
            fg: submitted ? EmpColors.success : SelmsColors.ink,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(sv['title'] as String? ?? 'Survey',
                    style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(
                  submitted
                      ? 'Answered ${empDate(sv['submitted_at'] as String?)}'
                      : 'Survey - $count question${count == 1 ? '' : 's'}',
                  style: const TextStyle(fontSize: 11.5, color: SelmsColors.textMuted),
                ),
              ],
            ),
          ),
          if (!submitted)
            ElevatedButton(
              onPressed: busy ? null : () => _answerSurvey(sv),
              style: ElevatedButton.styleFrom(backgroundColor: SelmsColors.ink, foregroundColor: Colors.white, elevation: 0),
              child: const Text('Answer', style: TextStyle(fontSize: 12)),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _refresh,
      child: FutureBuilder<Map<String, dynamic>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) return const EmpLoading();
          if (snapshot.hasError) return EmpErrorState(message: '${snapshot.error}', onRetry: _refresh);

          final sections = _flowSections(snapshot.data!);
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
            children: sections.isNotEmpty
                ? sections
                : const [
                    EmpCard(
                      child: EmpEmptyState(
                        icon: Icons.folder_open_outlined,
                        title: 'No documents yet',
                        message: 'Documents and surveys HR gives you during onboarding will appear here.',
                      ),
                    ),
                  ],
          );
        },
      ),
    );
  }
}
