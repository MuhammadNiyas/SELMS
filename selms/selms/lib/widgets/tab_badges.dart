// lib/widgets/tab_badges.dart
//
// The red unread counts on the sidebar tabs - the same notifications as the
// bell, split by where they point (IT: Requests, Messages, Shipments; HR: Smart
// Schedule, Lifecycle Insights, Messages, Products, Shipments). Messages
// also counts unread employee messages ('chat'), which clear by reading the
// conversation. Opening a tab marks its own notifications read, so its count
// clears just like reading them in the bell.

import 'dart:async';
import 'package:flutter/material.dart';
import '../services/api_client.dart';
import '../theme/selms_colors.dart';

/// Which notification link types each tab collects ('chat' = unread
/// employee messages, not a bell item).
const itRequestsTypes = ['requests'];
const itMessagesTypes = ['chat'];
const itShipmentsTypes = ['shipments'];
const hrScheduleTypes = ['schedule'];
const hrLifecycleTypes = ['lifecycle', 'employee'];
const hrMessagesTypes = ['chat'];
const hrProductsTypes = ['products'];
const hrShipmentsTypes = ['shipments'];

/// Unread notifications per link type, shared by the bell and the sidebars.
final staffUnreadByType = ValueNotifier<Map<String, int>>(const {});

/// The bell's own total, kept in step with the tabs.
final staffUnreadTotal = ValueNotifier<int>(0);

/// Takes the counts from a GET /api/staff/notifications response.
void setStaffUnread(Map<String, dynamic> data) {
  final raw = (data['unread_by_type'] as Map?) ?? const {};
  staffUnreadByType.value = {for (final e in raw.entries) '${e.key}': (e.value as num).toInt()};
  staffUnreadTotal.value = (data['unread_count'] as num?)?.toInt() ?? 0;
}

/// Keeps the counts fresh while a shell is on screen.
class TabBadgePoller {
  TabBadgePoller(this.api, {this.openTypes = const []});

  final ApiClient api;

  /// The tab now open: its notifications are marked read first.
  final List<String> openTypes;
  Timer? _timer;

  Future<void> start() async {
    // Unread chat clears by reading the conversation, not by opening the tab.
    final types = openTypes.where((t) => t != 'chat').toList();
    if (types.isNotEmpty) {
      try {
        await api.markStaffNotificationTypesRead(types);
      } catch (_) {}
    }
    await refresh();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => refresh());
  }

  Future<void> refresh() async {
    try {
      setStaffUnread(await api.getStaffNotifications());
    } catch (_) {
      // Quiet - the badges keep their last known counts.
    }
  }

  void stop() => _timer?.cancel();
}

/// Red count pill for a sidebar tab; nothing when there is nothing unread.
class TabBadge extends StatelessWidget {
  const TabBadge({super.key, required this.types});

  final List<String> types;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Map<String, int>>(
      valueListenable: staffUnreadByType,
      builder: (_, counts, _) {
        final n = types.fold<int>(0, (sum, t) => sum + (counts[t] ?? 0));
        if (n == 0) return const SizedBox.shrink();
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
          constraints: const BoxConstraints(minWidth: 18),
          decoration: BoxDecoration(color: SelmsColors.rose, borderRadius: BorderRadius.circular(10)),
          child: Text(n > 99 ? '99+' : '$n',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.w700)),
        );
      },
    );
  }
}
