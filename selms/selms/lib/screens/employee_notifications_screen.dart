// lib/screens/employee_notifications_screen.dart
//
// The employee's notifications dropdown, opened from the bell in the header
// (not a separate page): every timestamped event on their own record plus
// stored notifications and AI reminders, newest first. Opening it counts as
// reading them - the bell's red number clears - while the ones that were new
// stay highlighted for this viewing. Tapping one goes where it belongs.

import 'package:flutter/material.dart';
import '../models/employee_self_service.dart';
import '../services/api_client.dart';
import '../theme/selms_colors.dart';
import '../widgets/employee_ui.dart';

class EmployeeNotificationsPanel extends StatefulWidget {
  const EmployeeNotificationsPanel({
    super.key,
    required this.api,
    required this.onClose,
    required this.onRead,
    required this.onSelect,
  });

  final ApiClient api;
  final VoidCallback onClose;

  /// Called once they've been marked read, so the shell refreshes its badges.
  final VoidCallback onRead;

  /// A notification was tapped: its section (onboarding / offboarding /
  /// messages, or null).
  final void Function(String? section) onSelect;

  @override
  State<EmployeeNotificationsPanel> createState() => _EmployeeNotificationsPanelState();
}

class _EmployeeNotificationsPanelState extends State<EmployeeNotificationsPanel> {
  late final Future<EmployeeNotifications> _future = _load();

  Future<EmployeeNotifications> _load() async {
    final data = await widget.api.getMyNotifications();
    if (data.unreadCount > 0) {
      try {
        await widget.api.markMyNotificationsRead();
        widget.onRead();
      } catch (_) {
        // Worst case the badge stays until the next successful attempt.
      }
    }
    return data;
  }

  (IconData, Color, Color) _style(NotificationItem n) {
    if (n.kind == 'reminder') return (Icons.alarm, EmpColors.warningBg, EmpColors.warning);
    if (n.kind == 'alert') return (Icons.error_outline, SelmsColors.roseBg, SelmsColors.rose);
    if (n.section == 'messages') return (Icons.chat_bubble_outline, SelmsColors.accentBg, SelmsColors.ink);
    if (n.section == 'offboarding') return (Icons.logout, EmpColors.leavingBg, EmpColors.leaving);
    final t = n.title.toLowerCase();
    if (t.contains('equipment')) return (Icons.laptop_mac_outlined, SelmsColors.accentBg, SelmsColors.ink);
    if (t.contains('interview') || t.contains('orientation')) {
      return (Icons.event_outlined, SelmsColors.accentBg, SelmsColors.ink);
    }
    if (t.contains('signed')) return (Icons.task_alt, EmpColors.successBg, EmpColors.success);
    return (Icons.notifications_none, SelmsColors.accentBg, SelmsColors.ink);
  }

  Widget _tile(NotificationItem n) {
    final (icon, bg, fg) = _style(n);
    return InkWell(
      onTap: () => widget.onSelect(n.section),
      child: Container(
        color: n.read ? Colors.white : const Color(0xFFF5F9FF),
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            EmpIconBadge(icon, size: 32, bg: bg, fg: fg),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(n.title, style: TextStyle(fontSize: 12.5, fontWeight: n.read ? FontWeight.w500 : FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(n.message,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11.5, color: SelmsColors.textSecondary, height: 1.35)),
                  const SizedBox(height: 3),
                  Text(empRelative(n.at), style: const TextStyle(fontSize: 10.5, color: SelmsColors.textMuted)),
                ],
              ),
            ),
            if (!n.read)
              Container(
                width: 8,
                height: 8,
                margin: const EdgeInsets.only(top: 4, left: 6),
                decoration: const BoxDecoration(color: SelmsColors.rose, shape: BoxShape.circle),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 6, 8),
          child: Row(
            children: [
              const Expanded(
                child: Text('Notifications', style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700)),
              ),
              IconButton(
                tooltip: 'Close',
                visualDensity: VisualDensity.compact,
                onPressed: widget.onClose,
                icon: const Icon(Icons.close, size: 18, color: SelmsColors.textMuted),
              ),
            ],
          ),
        ),
        const Divider(height: 1, color: SelmsColors.border),
        Flexible(
          child: FutureBuilder<EmployeeNotifications>(
            future: _future,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Padding(
                  padding: EdgeInsets.all(28),
                  child: Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))),
                );
              }
              if (snapshot.hasError) {
                return Padding(
                  padding: const EdgeInsets.all(20),
                  child: Text("Couldn't load notifications.\n${snapshot.error}",
                      style: const TextStyle(fontSize: 12, color: SelmsColors.rose)),
                );
              }
              final items = snapshot.data!.items;
              if (items.isEmpty) {
                return const EmpEmptyState(
                  icon: Icons.notifications_none,
                  title: "You're all caught up",
                );
              }
              return ListView.separated(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                itemCount: items.length,
                separatorBuilder: (_, _) => const Divider(height: 1, color: SelmsColors.border),
                itemBuilder: (_, i) => _tile(items[i]),
              );
            },
          ),
        ),
      ],
    );
  }
}
