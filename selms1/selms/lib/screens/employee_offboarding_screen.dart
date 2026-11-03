// lib/screens/employee_offboarding_screen.dart
//
// Only ever shown once HR has initiated offboarding for this employee
// (the shell decides whether this tab exists at all — see
// employee_home_screen.dart). Same read-only, system-derived timeline as
// the onboarding journey: nothing here is a self-reported checkbox.

import 'package:flutter/material.dart';
import '../models/employee_self_service.dart';
import '../services/api_client.dart';
import '../theme/selms_colors.dart';
import '../widgets/employee_ui.dart';
import 'employee_return_screen.dart';

class EmployeeOffboardingScreen extends StatefulWidget {
  const EmployeeOffboardingScreen({super.key, required this.api, this.onOpenDocuments});

  final ApiClient api;

  /// Jumps to the Documents tab (documents and surveys from HR live there).
  final VoidCallback? onOpenDocuments;

  @override
  State<EmployeeOffboardingScreen> createState() => _EmployeeOffboardingScreenState();
}

class _EmployeeOffboardingScreenState extends State<EmployeeOffboardingScreen> {
  late Future<OffboardingChecklist> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.api.getMyOffboarding();
  }

  Future<void> _refresh() async {
    setState(() { _future = widget.api.getMyOffboarding(); });
    await _future;
  }

  String _status(ChecklistItem item) =>
      item.done ? (item.doneAt != null ? 'Completed ${empDate(item.doneAt)}' : 'Completed') : 'Not done yet';

  void _openStep(ChecklistItem item, OffboardingChecklist o) {
    if (item.id == 'flow_documents' || item.id.startsWith('survey:')) {
      showEmpSheet(context, icon: Icons.description_outlined, title: item.label, subtitle: _status(item), children: [
        const EmpSheetText('Open the Documents tab to download, fill in and upload your documents, or answer the survey.',
            heading: 'What to do'),
        if (!item.done && widget.onOpenDocuments != null)
          EmpSheetButton(
            label: 'Open Documents',
            icon: Icons.description_outlined,
            onPressed: () {
              Navigator.of(context).pop();
              widget.onOpenDocuments!();
            },
          ),
      ]);
      return;
    }
    switch (item.id) {
      case 'exit_interview':
        final m = item.meeting;
        final url = m?['meeting_url'] as String? ?? '';
        final duration = (m?['duration_minutes'] as num?)?.toInt() ?? 30;
        showEmpSheet(
          context,
          icon: Icons.event_outlined,
          title: 'Exit interview',
          subtitle: m == null ? 'Not booked yet' : '${empDate(m['date'] as String?, weekday: true)} · ${m['start_time']}',
          children: [
            if (m == null)
              const EmpSheetText(
                  'Your exit interview is booked for you before your last working day. '
                  'The date, time and joining link will appear here once it is set.',
                  heading: 'Status')
            else ...[
              EmpMeetingTile(meeting: m, compact: true),
              const SizedBox(height: 14),
              if (url.isNotEmpty) ...[
                EmpSheetButton(label: 'Join the interview', icon: Icons.videocam_outlined, onPressed: () => empOpenUrl(url)),
                EmpCopyRow(label: 'Meeting link', value: url),
              ],
              if ((m['location'] as String? ?? '').isNotEmpty)
                EmpCopyRow(label: 'Location', value: m['location'] as String),
            ],
            EmpSheetText(
              'A private, $duration-minute conversation with HR about your time here — what went well, '
              'what could be better, and anything you would like to pass on. It helps the company improve; '
              'there are no wrong answers.',
              heading: 'What to expect',
            ),
          ],
        );
      case 'equipment_returned':
        showReturnEquipmentSheet(context, widget.api, subtitle: _status(item)).then((_) => _refresh());
      case 'access_revoked':
        showEmpSheet(context, icon: Icons.lock_outline, title: item.label, subtitle: _status(item), children: const [
          EmpSheetText(
              'On your last working day IT closes your company accounts (email and systems). '
              'Save anything personal before then, and hand over work files to your team.',
              heading: 'About this step'),
        ]);
      default:
        showEmpSheet(context, icon: Icons.assignment_outlined, title: item.label, subtitle: _status(item), children: [
          EmpSheetText(
            'HR has recorded your ${(o.departureType ?? 'departure').toLowerCase()}'
            '${o.lastWorkingDay != null ? ' with a last working day of ${empDate(o.lastWorkingDay, weekday: true)}' : ''}. '
            'Your remaining offboarding steps are listed on this page.',
            heading: 'About this step',
          ),
        ]);
    }
  }

  int? _daysLeft(String? lastDay) {
    final d = lastDay == null ? null : DateTime.tryParse(lastDay);
    if (d == null) return null;
    final now = DateTime.now();
    return DateTime(d.year, d.month, d.day).difference(DateTime(now.year, now.month, now.day)).inDays;
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _refresh,
      child: FutureBuilder<OffboardingChecklist>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) return const EmpLoading();
          if (snapshot.hasError) return EmpErrorState(message: '${snapshot.error}', onRetry: _refresh);

          final o = snapshot.data!;
          if (!o.started) {
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
              children: [
                EmpCard(
                  child: Column(
                    children: [
                      const EmpEmptyState(
                        icon: Icons.verified_user_outlined,
                        title: 'Nothing here right now',
                      ),
                      const Divider(height: 1, color: SelmsColors.border),
                      const SizedBox(height: 14),
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: Padding(
                          padding: EdgeInsets.only(bottom: 10),
                          child: Text('WHAT OFFBOARDING INCLUDES',
                              style: TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.7,
                                  color: SelmsColors.textMuted)),
                        ),
                      ),
                      ...const [
                        (Icons.event_outlined, 'Exit interview', 'A short conversation with HR'),
                        (Icons.devices_other_outlined, 'Return equipment', 'Hand company items back to IT'),
                        (Icons.lock_outline, 'Account closure', 'IT closes your access on your last day'),
                      ].map((s) => Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Row(
                              children: [
                                EmpIconBadge(s.$1, size: 32, bg: const Color(0xFFF1F5F9), fg: SelmsColors.textMuted),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(s.$2,
                                          style: const TextStyle(
                                              fontSize: 12.5, fontWeight: FontWeight.w600, color: SelmsColors.textSecondary)),
                                      Text(s.$3, style: const TextStyle(fontSize: 11.5, color: SelmsColors.textMuted)),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          )),
                    ],
                  ),
                ),
              ],
            );
          }
          final daysLeft = _daysLeft(o.lastWorkingDay);

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
            children: [
              EmpCard(
                color: EmpColors.leavingBg,
                child: Row(
                  children: [
                    EmpProgressRing(
                      percent: o.progressPercent,
                      size: 64,
                      color: EmpColors.leaving,
                      trackColor: Colors.white,
                      textColor: EmpColors.leaving,
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(o.departureType ?? 'Departure',
                              style: const TextStyle(
                                  fontSize: 15, fontWeight: FontWeight.w700, color: EmpColors.leaving)),
                          const SizedBox(height: 3),
                          Text(
                            o.lastWorkingDay == null
                                ? 'Last working day not yet confirmed.'
                                : 'Last working day: ${empDate(o.lastWorkingDay, weekday: true)}',
                            style: const TextStyle(fontSize: 12.5, color: SelmsColors.textSecondary),
                          ),
                          if (daysLeft != null && daysLeft >= 0) ...[
                            const SizedBox(height: 6),
                            EmpPill(
                              daysLeft == 0 ? 'Today' : '$daysLeft day${daysLeft == 1 ? '' : 's'} left',
                              bg: Colors.white,
                              fg: EmpColors.leaving,
                              icon: Icons.schedule,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const EmpSectionHeader('Steps'),
              EmpTimeline(
                items: o.items,
                hintFor: (_) => '',
                accent: EmpColors.leaving,
                extraFor: (item) => item.meeting != null ? EmpMeetingTile(meeting: item.meeting!) : null,
                onTap: (item) => _openStep(item, o),
              ),
            ],
          );
        },
      ),
    );
  }
}
