// lib/screens/employee_notifications_screen.dart
//
// Alerts tab — every timestamped event on the employee's own record,
// newest first (report fig 3.19's idea, applied to the employee side).
// Marking read is a single "read everything up to now" action, not
// per-item, since there's no per-notification state to track otherwise.

import 'package:flutter/material.dart';
import '../models/employee_self_service.dart';
import '../services/api_client.dart';
import '../theme/selms_colors.dart';

class EmployeeNotificationsScreen extends StatefulWidget {
  const EmployeeNotificationsScreen({super.key, required this.api, required this.onRead});

  final ApiClient api;

  /// Called after a successful "mark all read" so the shell can refresh
  /// the unread badge on the tab itself.
  final VoidCallback onRead;

  @override
  State<EmployeeNotificationsScreen> createState() => _EmployeeNotificationsScreenState();
}

class _EmployeeNotificationsScreenState extends State<EmployeeNotificationsScreen> {
  late Future<EmployeeNotifications> _future;
  bool _marking = false;

  @override
  void initState() {
    super.initState();
    _future = widget.api.getMyNotifications();
  }

  Future<void> _refresh() async {
    setState(() => _future = widget.api.getMyNotifications());
    await _future;
  }

  Future<void> _markAllRead() async {
    setState(() => _marking = true);
    try {
      await widget.api.markMyNotificationsRead();
      widget.onRead();
      await _refresh();
    } catch (_) {
      // Silently ignore — worst case the badge stays until the next successful attempt.
    } finally {
      if (mounted) setState(() => _marking = false);
    }
  }

  String _relativeTime(String iso) {
    final at = DateTime.tryParse(iso);
    if (at == null) return '';
    final diff = DateTime.now().toUtc().difference(at.toUtc());
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _refresh,
      child: FutureBuilder<EmployeeNotifications>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Text('Could not load notifications.\n${snapshot.error}',
                    style: const TextStyle(color: SelmsColors.rose, fontSize: 13)),
              ],
            );
          }

          final data = snapshot.data!;
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text('Notifications', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                  ),
                  if (data.unreadCount > 0)
                    TextButton(
                      onPressed: _marking ? null : _markAllRead,
                      child: Text(_marking ? 'Marking…' : 'Mark all read',
                          style: const TextStyle(fontSize: 12, color: SelmsColors.ink)),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              if (data.items.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 40),
                  child: Center(
                    child: Text('Nothing here yet.',
                        style: TextStyle(fontSize: 13, color: SelmsColors.textMuted)),
                  ),
                )
              else
                ...data.items.map((n) => Container(
                      margin: const EdgeInsets.only(top: 10),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: n.read ? SelmsColors.cardWhite : SelmsColors.accentBg,
                        border: Border.all(color: SelmsColors.border),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            margin: const EdgeInsets.only(top: 4),
                            decoration: BoxDecoration(
                              color: n.read ? SelmsColors.border : SelmsColors.ink,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(n.title,
                                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                                const SizedBox(height: 2),
                                Text(n.message,
                                    style: const TextStyle(fontSize: 12, color: SelmsColors.textSecondary)),
                                const SizedBox(height: 4),
                                Text(_relativeTime(n.at),
                                    style: const TextStyle(fontSize: 10.5, color: SelmsColors.textMuted)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    )),
            ],
          );
        },
      ),
    );
  }
}
