// lib/screens/employee_dashboard_screen.dart
//
// The employee's Home tab: who they are, how far along they are, the ONE
// thing to do next (with a button straight to it), their next session, and
// recent activity. Everything is read from the same endpoints the other
// tabs use - nothing here is stored separately.

import 'package:flutter/material.dart';
import '../models/employee.dart';
import '../models/employee_self_service.dart';
import '../services/api_client.dart';
import '../theme/selms_colors.dart';
import '../widgets/employee_ui.dart';

/// Tabs the dashboard can send the employee to.
enum EmpDestination { onboarding, offboarding, documents, profile }

class EmployeeDashboardScreen extends StatefulWidget {
  const EmployeeDashboardScreen({
    super.key,
    required this.api,
    required this.profile,
    required this.onNavigate,
    required this.onOpenAlerts,
    this.reloadToken = 0,
  });

  final ApiClient api;
  final Employee? profile;
  final void Function(EmpDestination destination) onNavigate;
  final VoidCallback onOpenAlerts;

  /// Bumped by the shell whenever Home is shown again, so it re-reads.
  final int reloadToken;

  @override
  State<EmployeeDashboardScreen> createState() => _EmployeeDashboardScreenState();
}

class _HomeData {
  _HomeData(this.onboarding, this.offboarding, this.flowItems, this.notifications);

  final EmployeeChecklist onboarding;
  final OffboardingChecklist offboarding;
  final Map<String, dynamic> flowItems;
  final EmployeeNotifications notifications;
}

class _NextStep {
  _NextStep(this.icon, this.title, this.message, {this.actionLabel, this.destination, this.meeting, this.done = false});

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final EmpDestination? destination;
  final Map<String, dynamic>? meeting;
  final bool done;
}

class _EmployeeDashboardScreenState extends State<EmployeeDashboardScreen> {
  late Future<_HomeData> _future = _load();

  Future<_HomeData> _load() async {
    final api = widget.api;
    final (onboarding, offboarding, flowItems, notifications) = await (
      api.getMyChecklist(),
      api.getMyOffboarding(),
      api.getMyFlowItems(),
      api.getMyNotifications(),
    ).wait;
    return _HomeData(onboarding, offboarding, flowItems, notifications);
  }

  @override
  void didUpdateWidget(covariant EmployeeDashboardScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.reloadToken != widget.reloadToken) {
      setState(() { _future = _load(); });
    }
  }

  Future<void> _refresh() async {
    setState(() { _future = _load(); });
    await _future;
  }

  _NextStep _nextStep(_HomeData d) {
    if (d.offboarding.started) {
      final item = d.offboarding.items.where((i) => !i.done).firstOrNull;
      final lastDay = d.offboarding.lastWorkingDay;
      if (item == null) {
        return _NextStep(Icons.verified_outlined, 'Offboarding complete',
            'Everything is wrapped up. Thank you for your time with us.', done: true);
      }
      return switch (item.id) {
        'exit_interview' => _NextStep(Icons.event_outlined, 'Your exit interview',
            'It will be booked for you before your last working day and appear here.',
            destination: EmpDestination.offboarding, actionLabel: 'View offboarding'),
        'equipment_returned' => _NextStep(Icons.devices_other_outlined, 'Return your equipment',
            'Hand all company equipment back to IT${lastDay != null ? ' before $lastDay' : ''}.',
            destination: EmpDestination.profile, actionLabel: 'See my equipment'),
        'access_revoked' => _NextStep(Icons.lock_outline, 'Account closure',
            'IT will close your system access on your last working day.',
            destination: EmpDestination.offboarding, actionLabel: 'View offboarding'),
        _ => _NextStep(Icons.flag_outlined, item.label, 'In progress.',
            destination: EmpDestination.offboarding, actionLabel: 'View offboarding'),
      };
    }

    final item = d.onboarding.items.where((i) => !i.done).firstOrNull;
    if (item == null) {
      return _NextStep(Icons.celebration_outlined, "You're all set",
          'Everything on your onboarding list is done. Welcome aboard!', done: true);
    }
    // Documents / surveys from HR that still need the employee to act.
    final todo = ((d.flowItems['documents'] as List? ?? const []).cast<Map<String, dynamic>>().where((x) =>
                x['action'] != 'download' && const {'sent', 'rejected'}.contains(x['status'])).length) +
        ((d.flowItems['surveys'] as List? ?? const []).cast<Map<String, dynamic>>().where((x) => x['status'] != 'submitted').length);
    return switch (item.id) {
      'welcome_email' => _NextStep(Icons.mark_email_unread_outlined, 'Your onboarding starts soon',
          'HR will email your personal inbox when it begins.',
          destination: EmpDestination.onboarding, actionLabel: 'View onboarding'),
      'documents_signed' => _NextStep(Icons.draw_outlined, 'Your documents from HR',
          todo > 0
              ? '$todo item${todo == 1 ? '' : 's'} waiting for you in the Documents tab.'
              : 'HR is reviewing what you sent.',
          destination: EmpDestination.documents, actionLabel: 'Open documents'),
      'orientation' => _NextStep(Icons.event_outlined, 'Your orientation',
          item.meeting != null ? 'Your session is booked:' : 'HR will book your orientation session shortly.',
          meeting: item.meeting, destination: EmpDestination.onboarding, actionLabel: 'View onboarding'),
      'it_equipment' => _NextStep(Icons.laptop_mac_outlined, 'Your equipment',
          item.shipment != null
              ? 'Your equipment is being posted to you — track it on the Onboarding tab.'
              : 'IT is preparing your equipment. You will be notified when it is ready.',
          destination: EmpDestination.onboarding, actionLabel: 'View onboarding'),
      'profile_setup' => _NextStep(Icons.add_a_photo_outlined, 'Add a profile photo',
          'Help your colleagues recognise you — it only takes a moment.',
          destination: EmpDestination.profile, actionLabel: 'Add photo'),
      _ => _NextStep(Icons.flag_outlined, item.label, 'In progress.',
          destination: EmpDestination.onboarding, actionLabel: 'View onboarding'),
    };
  }

  /// The next session still ahead (orientation or exit interview).
  Map<String, dynamic>? _upcomingMeeting(_HomeData d) {
    final today = DateTime.now();
    final todayKey =
        '${today.year.toString().padLeft(4, '0')}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
    final meetings = [
      ...d.offboarding.items.map((i) => i.meeting),
      ...d.onboarding.items.map((i) => i.meeting),
    ].whereType<Map<String, dynamic>>().where((m) => (m['date'] as String? ?? '').compareTo(todayKey) >= 0);
    return meetings.firstOrNull;
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _refresh,
      child: FutureBuilder<_HomeData>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) return const EmpLoading();
          if (snapshot.hasError) return EmpErrorState(message: '${snapshot.error}', onRetry: _refresh);
          final d = snapshot.data!;
          final leaving = d.offboarding.started;
          final next = _nextStep(d);
          final upcoming = _upcomingMeeting(d);

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
            children: [
              _heroCard(d, leaving),
              const EmpSectionHeader('Next step'),
              _nextStepCard(next),
              if (upcoming != null && next.meeting == null) ...[
                EmpSectionHeader(leaving ? 'Upcoming session' : 'Upcoming'),
                EmpCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(upcoming['title'] as String? ?? 'Session',
                          style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 10),
                      EmpMeetingTile(meeting: upcoming, compact: true),
                    ],
                  ),
                ),
              ],
              EmpSectionHeader(
                'Recent activity',
                trailing: d.notifications.items.isEmpty
                    ? null
                    : TextButton(
                        onPressed: widget.onOpenAlerts,
                        style: TextButton.styleFrom(
                            padding: EdgeInsets.zero, minimumSize: const Size(0, 0), visualDensity: VisualDensity.compact),
                        child: const Text('View all', style: TextStyle(fontSize: 12, color: SelmsColors.ink)),
                      ),
              ),
              if (d.notifications.items.isEmpty)
                const EmpCard(
                  child: Text('No activity yet',
                      style: TextStyle(fontSize: 12.5, color: SelmsColors.textMuted)),
                )
              else
                EmpCard(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                  child: Column(
                    children: [
                      for (final (i, n) in d.notifications.items.take(4).indexed) ...[
                        if (i > 0) const Divider(height: 1, color: SelmsColors.border),
                        _activityRow(n),
                      ],
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _heroCard(_HomeData d, bool leaving) {
    final p = widget.profile;
    final firstName = (p?.fullName ?? '').split(RegExp(r'\s+')).first;
    final percent = leaving ? d.offboarding.progressPercent : d.onboarding.progressPercent;
    final role = [p?.jobTitle, p?.department].where((s) => s != null && s.isNotEmpty).join(' · ');
    final subtitle = leaving
        ? 'Offboarding · last working day ${d.offboarding.lastWorkingDay ?? 'TBC'}'
        : (percent >= 100 ? 'Onboarding complete' : 'Onboarding in progress');

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: leaving
              ? const [Color(0xFF4C0519), Color(0xFF881337)]
              : const [Color(0xFF14161B), Color(0xFF2B3A55)],
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(empDate(DateTime.now().toIso8601String(), weekday: true),
                    style: const TextStyle(fontSize: 11.5, color: Colors.white60)),
                const SizedBox(height: 4),
                Text(firstName.isEmpty ? empGreeting() : '${empGreeting()}, $firstName',
                    style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700, color: Colors.white)),
                if (role.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(role, style: const TextStyle(fontSize: 12, color: Colors.white70)),
                ],
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(subtitle,
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.white)),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          EmpProgressRing(percent: percent, size: 72),
        ],
      ),
    );
  }

  Widget _nextStepCard(_NextStep next) {
    return EmpCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              EmpIconBadge(next.icon,
                  bg: next.done ? EmpColors.successBg : SelmsColors.accentBg,
                  fg: next.done ? EmpColors.success : SelmsColors.ink),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(next.title, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 3),
                    Text(next.message,
                        style: const TextStyle(fontSize: 12.5, color: SelmsColors.textSecondary, height: 1.4)),
                  ],
                ),
              ),
            ],
          ),
          if (next.meeting != null) EmpMeetingTile(meeting: next.meeting!),
          if (next.actionLabel != null && next.destination != null) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => widget.onNavigate(next.destination!),
                style: ElevatedButton.styleFrom(
                  backgroundColor: SelmsColors.ink,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(next.actionLabel!, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                    const SizedBox(width: 6),
                    const Icon(Icons.arrow_forward, size: 16),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }


  Widget _activityRow(NotificationItem n) {
    final isReminder = n.kind == 'reminder';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          EmpIconBadge(
            isReminder ? Icons.alarm : Icons.notifications_none,
            size: 30,
            bg: isReminder ? EmpColors.warningBg : SelmsColors.accentBg,
            fg: isReminder ? EmpColors.warning : SelmsColors.ink,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(n.title,
                    style: TextStyle(fontSize: 12.5, fontWeight: n.read ? FontWeight.w500 : FontWeight.w700)),
                const SizedBox(height: 1),
                Text(n.message,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11.5, color: SelmsColors.textSecondary)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(empRelative(n.at), style: const TextStyle(fontSize: 10.5, color: SelmsColors.textMuted)),
        ],
      ),
    );
  }
}
