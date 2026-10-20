// lib/widgets/start_review_dialog.dart
//
// "Review before Start" for onboarding and offboarding: every step of the
// employee's flow, in order, with what it will do - the email (editable),
// documents, what IT is asked for, the meeting plan, the survey questions
// and HR's own "+" steps. Nothing runs here: Cancel closes it, Confirm
// starts the process. The steps come from the server, so any step added to
// the flow shows up automatically.

import 'package:flutter/material.dart';
import '../theme/selms_colors.dart';
import 'employee_avatar.dart';

/// Shows the review. Returns null when cancelled; on Confirm returns the
/// (possibly edited) email as {subject, body}, or an empty map when the
/// flow has no email step.
Future<Map<String, String>?> showStartReview(
  BuildContext context, {
  required Map<String, dynamic> review,
  required String apiBaseUrl,
}) {
  return showDialog<Map<String, String>>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _StartReviewDialog(review: review, apiBaseUrl: apiBaseUrl),
  );
}

class _StartReviewDialog extends StatefulWidget {
  const _StartReviewDialog({required this.review, required this.apiBaseUrl});

  final Map<String, dynamic> review;
  final String apiBaseUrl;

  @override
  State<_StartReviewDialog> createState() => _StartReviewDialogState();
}

class _StartReviewDialogState extends State<_StartReviewDialog> {
  late final Map<String, dynamic>? _email = (widget.review['email'] as Map?)?.cast<String, dynamic>();
  late final _subject = TextEditingController(text: _email?['subject'] as String? ?? '');
  late final _body = TextEditingController(text: _email?['body'] as String? ?? '');
  String? _error;

  @override
  void dispose() {
    _subject.dispose();
    _body.dispose();
    super.dispose();
  }

  bool get _offboarding => widget.review['process'] == 'offboarding';

  void _confirm() {
    if (_email != null && (_subject.text.trim().isEmpty || _body.text.trim().isEmpty)) {
      setState(() => _error = 'The email needs a subject and a message.');
      return;
    }
    Navigator.of(context).pop(_email == null ? <String, String>{} : {'subject': _subject.text.trim(), 'body': _body.text.trim()});
  }

  Widget _emailEditor() {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: SelmsColors.fieldBg, borderRadius: BorderRadius.circular(8)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_email!['saved'] == true ? 'Saved email - you can still change it here.' : 'Draft - change anything before confirming.',
              style: const TextStyle(fontSize: 11, color: SelmsColors.textMuted)),
          const SizedBox(height: 6),
          TextField(
            controller: _subject,
            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
            decoration: const InputDecoration(isDense: true, labelText: 'Subject', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _body,
            minLines: 5,
            maxLines: 12,
            style: const TextStyle(fontSize: 12.5, height: 1.4),
            decoration: const InputDecoration(isDense: true, labelText: 'Message', border: OutlineInputBorder()),
          ),
        ],
      ),
    );
  }

  Widget _step(int number, Map<String, dynamic> s) {
    final lines = ((s['lines'] as List?) ?? const []).cast<String>();
    final when = s['when'] as String?;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: SelmsColors.border),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 24,
            height: 24,
            alignment: Alignment.center,
            decoration: const BoxDecoration(color: SelmsColors.accentBg, shape: BoxShape.circle),
            child: Text('$number', style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: SelmsColors.ink)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(s['label'] as String? ?? '',
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: SelmsColors.textPrimary)),
                    ),
                    if (when != null)
                      Text(when, style: const TextStyle(fontSize: 11, color: SelmsColors.textSecondary)),
                  ],
                ),
                for (final line in lines)
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Text(line, style: const TextStyle(fontSize: 12, color: SelmsColors.textSecondary, height: 1.35)),
                  ),
                if (s['email'] == true && _email != null) _emailEditor(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final emp = (widget.review['employee'] as Map?)?.cast<String, dynamic>() ?? const {};
    final dep = (widget.review['departure'] as Map?)?.cast<String, dynamic>();
    final steps = ((widget.review['steps'] as List?) ?? const []).cast<Map<String, dynamic>>();
    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 600, maxHeight: MediaQuery.of(context).size.height * 0.9),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_offboarding ? 'Review before starting offboarding' : 'Review before starting onboarding',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: SelmsColors.textPrimary)),
              const SizedBox(height: 4),
              const Text('Nothing has started yet. Check each step below, then Confirm to start - or Cancel.',
                  style: TextStyle(fontSize: 11.5, color: SelmsColors.textMuted)),
              const SizedBox(height: 12),
              Row(
                children: [
                  EmployeeAvatar(
                    apiBaseUrl: widget.apiBaseUrl,
                    name: emp['full_name'] as String? ?? '',
                    photoUrl: emp['profile_image_url'] as String?,
                    size: 36,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(emp['full_name'] as String? ?? '',
                            style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: SelmsColors.textPrimary)),
                        Text(
                          dep != null
                              ? '${emp['employee_id']} · ${dep['departure_type'] ?? ''} · Last working day ${dep['last_working_day'] ?? ''}'
                              : '${emp['employee_id']} · ${emp['department'] ?? ''} · Hire date ${emp['hire_date'] ?? ''}',
                          style: const TextStyle(fontSize: 11.5, color: SelmsColors.textSecondary),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    children: [for (var i = 0; i < steps.length; i++) _step(i + 1, steps[i])],
                  ),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 6),
                Text(_error!, style: const TextStyle(fontSize: 12, color: SelmsColors.rose)),
              ],
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: _confirm,
                    style: ElevatedButton.styleFrom(backgroundColor: SelmsColors.ink, foregroundColor: Colors.white),
                    child: const Text('Confirm'),
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
