// lib/screens/employee_onboarding_screen.dart
//
// The employee's onboarding journey (report fig 3.28), shown as a timeline.
// Every item's "done" state is derived server-side from real signals
// (welcome email sent, documents signed, orientation booked, equipment
// assigned, profile photo uploaded) — there's nothing here for the employee
// to tick by hand, since a self-reported checkbox wouldn't mean anything HR
// or IT could rely on. Tapping a step opens its details: the orientation
// link and what to expect, the parcel reference and Pos Malaysia tracking,
// or a shortcut to where the step gets done.

import 'package:flutter/material.dart';
import '../models/employee_self_service.dart';
import '../services/api_client.dart';
import '../theme/selms_colors.dart';
import '../widgets/employee_ui.dart';

/// Pos Malaysia's public tracking page (the backend sends the same link).
const _posTrackingUrl = 'https://tracking.pos.com.my/tracking';

class EmployeeOnboardingScreen extends StatefulWidget {
  const EmployeeOnboardingScreen({
    super.key,
    required this.api,
    required this.fullName,
    required this.onOpenDocuments,
    required this.onOpenProfile,
  });

  final ApiClient api;
  final String? fullName;
  final VoidCallback onOpenDocuments;
  final VoidCallback onOpenProfile;

  @override
  State<EmployeeOnboardingScreen> createState() => _EmployeeOnboardingScreenState();
}

class _EmployeeOnboardingScreenState extends State<EmployeeOnboardingScreen> {
  late Future<EmployeeChecklist> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.api.getMyChecklist();
  }

  Future<void> _refresh() async {
    setState(() { _future = widget.api.getMyChecklist(); });
    await _future;
  }

  String _hint(ChecklistItem item) => switch (item.id) {
        final id when id.startsWith('survey:') => 'A short survey from HR. Answer it in the Documents tab.',
        'documents_signed' => 'Complete the documents HR gave you, in the Documents tab.',
        'profile_setup' => 'Upload a profile photo in My profile.',
        _ => '',
      };

  Widget? _extra(ChecklistItem item) {
    if (item.meeting != null) return EmpMeetingTile(meeting: item.meeting!);
    if (item.shipment != null) return EmpShipmentTile(shipment: item.shipment!);
    return null;
  }

  // ---------------------------------------------------------------- step details

  void _openStep(ChecklistItem item) {
    if (item.id.startsWith('survey:')) {
      showEmpSheet(context, icon: Icons.fact_check_outlined, title: item.label, subtitle: _status(item), children: [
        const EmpSheetText('HR has a few short questions for you. Answer them in the Documents tab.', heading: 'What to do'),
        if (!item.done)
          EmpSheetButton(
            label: 'Open Documents',
            icon: Icons.description_outlined,
            onPressed: () {
              Navigator.of(context).pop();
              widget.onOpenDocuments();
            },
          ),
      ]);
      return;
    }
    switch (item.id) {
      case 'orientation':
        _orientationSheet(item);
      case 'it_equipment':
        _equipmentSheet(item);
      case 'documents_signed':
        showEmpSheet(context, icon: Icons.draw_outlined, title: item.label, subtitle: _status(item), children: [
          const EmpSheetText(
              'Open the Documents tab: download what HR sent, acknowledge it or upload your signed copy. '
              'HR is told as soon as you do.',
              heading: 'What to do'),
          if (!item.done)
            EmpSheetButton(
              label: 'Open Documents',
              icon: Icons.description_outlined,
              onPressed: () {
                Navigator.of(context).pop();
                widget.onOpenDocuments();
              },
            ),
        ]);
      case 'profile_setup':
        showEmpSheet(context, icon: Icons.account_circle_outlined, title: item.label, subtitle: _status(item), children: [
          const EmpSheetText('Add a profile photo so colleagues, HR and IT can recognise you.',
              heading: 'What to do'),
          EmpSheetButton(
            label: item.done ? 'View my profile' : 'Add a photo',
            icon: Icons.person_outline,
            onPressed: () {
              Navigator.of(context).pop();
              widget.onOpenProfile();
            },
          ),
        ]);
      default: // welcome email
        showEmpSheet(context, icon: Icons.mark_email_read_outlined, title: item.label, subtitle: _status(item), children: [
          EmpSheetText(
            item.done
                ? 'HR sent your welcome email to your personal inbox${item.doneAt != null ? ' on ${empDate(item.doneAt)}' : ''}. '
                    'It has your work email and a link to confirm you received it.'
                : 'HR will email your personal inbox when your onboarding starts. '
                    "Check your spam folder if you don't see it.",
            heading: 'About this step',
          ),
        ]);
    }
  }

  String _status(ChecklistItem item) =>
      item.done ? (item.doneAt != null ? 'Completed ${empDate(item.doneAt)}' : 'Completed') : 'Not done yet';

  void _orientationSheet(ChecklistItem item) {
    final m = item.meeting;
    final url = m?['meeting_url'] as String? ?? '';
    final duration = (m?['duration_minutes'] as num?)?.toInt() ?? 30;
    showEmpSheet(
      context,
      icon: Icons.event_outlined,
      title: 'Orientation session',
      subtitle: m == null ? 'Not booked yet' : '${empDate(m['date'] as String?, weekday: true)} · ${m['start_time']}',
      children: [
        if (m == null)
          const EmpSheetText(
              'HR books your orientation automatically as part of your onboarding. '
              'Once it is booked, the date, time and joining link will appear here.',
              heading: 'Status')
        else ...[
          EmpMeetingTile(meeting: m, compact: true),
          const SizedBox(height: 14),
          if (url.isNotEmpty) ...[
            EmpSheetButton(label: 'Join the session', icon: Icons.videocam_outlined, onPressed: () => empOpenUrl(url)),
            EmpCopyRow(label: 'Meeting link', value: url),
          ],
          if ((m['location'] as String? ?? '').isNotEmpty)
            EmpCopyRow(label: 'Location', value: m['location'] as String),
          EmpSheetText(
            'A $duration-minute welcome session with HR: an introduction to the company and your team, '
            'the tools and systems you will use, key policies, and what your first week looks like. '
            'Bring any questions you have.',
            heading: 'What to expect',
          ),
        ],
      ],
    );
  }

  void _equipmentSheet(ChecklistItem item) {
    final s = item.shipment;
    final ref = s?['pos_reference'] as String? ?? '';
    final trackingUrl = (s?['tracking_url'] as String?) ?? _posTrackingUrl;
    final statusLabel = switch (s?['status'] as String? ?? '') {
      'pending' => 'IT is preparing your parcel',
      'order_created' => 'Booked with Pos Malaysia — waiting to be sent',
      'dropped_off' => 'On its way with Pos Malaysia',
      'delivered' => 'Delivered',
      _ => '',
    };

    showEmpSheet(
      context,
      icon: Icons.laptop_mac_outlined,
      title: 'IT equipment',
      subtitle: _status(item),
      children: [
        if (s != null) ...[
          EmpShipmentTile(shipment: s),
          const SizedBox(height: 14),
          if (statusLabel.isNotEmpty) EmpSheetText(statusLabel, heading: 'Parcel status'),
          if (ref.isNotEmpty) ...[
            EmpCopyRow(label: 'Pos Malaysia reference', value: ref),
            EmpSheetButton(
              label: 'Track on Pos Malaysia',
              icon: Icons.local_shipping_outlined,
              onPressed: () => empOpenUrl(trackingUrl),
            ),
            const EmpSheetText('Copy the reference above and paste it on the Pos Malaysia tracking page.'),
          ] else
            const EmpSheetText('IT will add the Pos Malaysia reference once the parcel is booked — '
                'tracking will be available here then.'),
        ] else
          const EmpSheetText(
              'IT prepares the equipment you need for your role. You will be told when it is ready to collect.',
              heading: 'How you get it'),
        FutureBuilder<List<Map<String, dynamic>>>(
          future: widget.api.getMyEquipment(),
          builder: (context, snap) {
            final list = snap.data ?? const [];
            if (snap.connectionState != ConnectionState.done) {
              return const Padding(padding: EdgeInsets.all(8), child: LinearProgressIndicator(minHeight: 2));
            }
            if (list.isEmpty) {
              return const EmpSheetText('Nothing has been assigned to you yet.', heading: 'Assigned to you');
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const EmpSectionHeader('Assigned to you'),
                for (final e in list)
                  EmpEquipmentTile(
                    item: e,
                    baseUrl: widget.api.baseUrl,
                    trailing: const EmpPill('Yours', bg: EmpColors.successBg, fg: EmpColors.success, icon: Icons.check),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _refresh,
      child: FutureBuilder<EmployeeChecklist>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) return const EmpLoading();
          if (snapshot.hasError) return EmpErrorState(message: '${snapshot.error}', onRetry: _refresh);

          final checklist = snapshot.data!;
          final done = checklist.items.where((i) => i.done).length;
          final total = checklist.items.length;

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
            children: [
              EmpCard(
                child: Row(
                  children: [
                    EmpProgressRing(
                      percent: checklist.progressPercent,
                      size: 64,
                      color: SelmsColors.ink,
                      trackColor: SelmsColors.accentBg,
                      textColor: SelmsColors.ink,
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Your onboarding journey',
                              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                          const SizedBox(height: 3),
                          Text(
                            done == total
                                ? 'All $total steps complete — welcome aboard!'
                                : '$done of $total steps complete. Tap a step for details.',
                            style: const TextStyle(fontSize: 12.5, color: SelmsColors.textSecondary, height: 1.4),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const EmpSectionHeader('Steps'),
              EmpTimeline(items: checklist.items, hintFor: _hint, extraFor: _extra, onTap: _openStep),
            ],
          );
        },
      ),
    );
  }
}
