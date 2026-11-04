// lib/widgets/app_shell.dart
//
// The dark sidebar + light blue content shell shared by every HR screen.
// Pass a `child` for the page body; AppShell handles the sidebar (which can
// collapse for a full-width view), nav highlighting, and log out.

import 'dart:async';
import 'package:flutter/material.dart';
import '../theme/selms_colors.dart';
import '../services/api_client.dart';
import '../screens/selms_login_screen.dart';
import '../screens/dashboard_screen.dart';
import '../screens/employee_directory_screen.dart';
import '../screens/onboarding_screen.dart';
import '../screens/offboarding_screen.dart';
import '../screens/lifecycle_insights_screen.dart';
import '../screens/hr_shipments_screen.dart';
import '../screens/smart_schedule_screen.dart';
import '../screens/hr_messages_screen.dart';
import '../screens/employee_view_screen.dart';
import '../screens/it_requests_screen.dart';
import '../screens/it_products_screen.dart';
import '../screens/it_shipments_screen.dart';
import 'chat_panel.dart';
import 'tab_badges.dart';

enum SelmsRoute { dashboard, employees, onboarding, offboarding, insights, shipments, products, smartSchedule, messages }

class AppShell extends StatefulWidget {
  const AppShell({
    super.key,
    required this.apiBaseUrl,
    required this.hrToken,
    required this.activeRoute,
    required this.child,
  });

  final String apiBaseUrl;
  final String hrToken;
  final SelmsRoute activeRoute;
  final Widget child;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  bool _collapsed = false;
  bool _chatOpen = false;

  // Red counts on the tabs; opening one clears its own.
  late final TabBadgePoller _badges = TabBadgePoller(
    ApiClient(baseUrl: widget.apiBaseUrl, hrToken: widget.hrToken),
    openTypes: switch (widget.activeRoute) {
      SelmsRoute.smartSchedule => hrScheduleTypes,
      SelmsRoute.insights => hrLifecycleTypes,
      SelmsRoute.products => hrProductsTypes,
      SelmsRoute.shipments => hrShipmentsTypes,
      _ => const <String>[],
    },
  );

  @override
  void initState() {
    super.initState();
    _badges.start();
  }

  @override
  void dispose() {
    _badges.stop();
    super.dispose();
  }

  void _openChat() {
    if (_chatOpen) return;
    setState(() => _chatOpen = true);
    final api = ApiClient(baseUrl: widget.apiBaseUrl, hrToken: widget.hrToken);
    showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (_) => Dialog(
        alignment: Alignment.bottomRight,
        insetPadding: const EdgeInsets.only(right: 24, bottom: 24),
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        child: SizedBox(
          width: 340,
          height: 460,
          child: ChatPanel(
            title: 'SELMS Admin Assistant',
            hint: "Hi! I'm your SELMS Admin Assistant. How can I help you today?",
            suggestions: const ['overdue', 'offboarding', 'equipment', 'what documents do we have?'],
            onSend: api.hrChat,
            documentUrl: api.documentDownloadUrl,
            onUpload: (name, bytes, title) => api.uploadDocument(name, bytes, title: title),
            onDeleteDocument: api.deleteDocument,
          ),
        ),
      ),
    ).then((_) {
      if (mounted) setState(() => _chatOpen = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    return SelmsSession(
      apiBaseUrl: widget.apiBaseUrl,
      token: widget.hrToken,
      role: 'hr',
      child: _buildShell(context),
    );
  }

  Widget _buildShell(BuildContext context) {
    return Scaffold(
      backgroundColor: SelmsColors.accentBg,
      body: Stack(
        children: [
          Row(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeInOut,
                width: _collapsed ? 0 : 220,
                clipBehavior: Clip.hardEdge,
                decoration: const BoxDecoration(),
                child: OverflowBox(
                  minWidth: 220,
                  maxWidth: 220,
                  alignment: Alignment.centerLeft,
                  child: _Sidebar(
                    apiBaseUrl: widget.apiBaseUrl,
                    hrToken: widget.hrToken,
                    activeRoute: widget.activeRoute,
                    onCollapse: () => setState(() => _collapsed = true),
                  ),
                ),
              ),
              Expanded(child: widget.child),
            ],
          ),
          if (_collapsed)
            Positioned(
              top: 20,
              left: 12,
              child: InkWell(
                onTap: () => setState(() => _collapsed = false),
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: SelmsColors.ink,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.chevron_right, size: 18, color: Colors.white),
                ),
              ),
            ),
          Positioned(
            bottom: 24,
            right: 24,
            child: InkWell(
              onTap: _openChat,
              borderRadius: BorderRadius.circular(28),
              child: Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: SelmsColors.ink,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 10, offset: const Offset(0, 3)),
                  ],
                ),
                child: const Icon(Icons.smart_toy_outlined, size: 22, color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({
    required this.apiBaseUrl,
    required this.hrToken,
    required this.activeRoute,
    required this.onCollapse,
  });

  final String apiBaseUrl;
  final String hrToken;
  final SelmsRoute activeRoute;
  final VoidCallback onCollapse;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 220,
      color: SelmsColors.ink,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 6, bottom: 24),
            child: Row(
              children: [
                const Text('SELMS',
                    style: TextStyle(
                        color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700, letterSpacing: 0.8)),
                const Spacer(),
                InkWell(
                  onTap: onCollapse,
                  borderRadius: BorderRadius.circular(6),
                  child: const Padding(
                    padding: EdgeInsets.all(4),
                    child: Icon(Icons.chevron_left, size: 18, color: Colors.white54),
                  ),
                ),
              ],
            ),
          ),
          _NavItem(
            icon: Icons.dashboard_outlined,
            label: 'Dashboard',
            active: activeRoute == SelmsRoute.dashboard,
            onTap: () {
              if (activeRoute == SelmsRoute.dashboard) return;
              Navigator.of(context).pushReplacement(
                MaterialPageRoute(
                  builder: (_) => DashboardScreen(apiBaseUrl: apiBaseUrl, hrToken: hrToken),
                ),
              );
            },
          ),
          _NavItem(
            icon: Icons.people_outline,
            label: 'Employees',
            active: activeRoute == SelmsRoute.employees,
            onTap: () {
              if (activeRoute == SelmsRoute.employees) return;
              Navigator.of(context).pushReplacement(
                MaterialPageRoute(
                  builder: (_) => EmployeeDirectoryScreen(apiBaseUrl: apiBaseUrl, hrToken: hrToken),
                ),
              );
            },
          ),
          _NavItem(
            icon: Icons.auto_awesome_outlined,
            label: 'Onboarding',
            active: activeRoute == SelmsRoute.onboarding,
            onTap: () {
              if (activeRoute == SelmsRoute.onboarding) return;
              Navigator.of(context).pushReplacement(
                MaterialPageRoute(
                  builder: (_) => OnboardingScreen(apiBaseUrl: apiBaseUrl, hrToken: hrToken),
                ),
              );
            },
          ),
          _NavItem(
            icon: Icons.logout_outlined,
            label: 'Offboarding',
            active: activeRoute == SelmsRoute.offboarding,
            onTap: () {
              if (activeRoute == SelmsRoute.offboarding) return;
              Navigator.of(context).pushReplacement(
                MaterialPageRoute(
                  builder: (_) => OffboardingScreen(apiBaseUrl: apiBaseUrl, hrToken: hrToken),
                ),
              );
            },
          ),
          _NavItem(
            icon: Icons.insights_outlined,
            label: 'Lifecycle Insights',
            badge: const TabBadge(types: hrLifecycleTypes),
            active: activeRoute == SelmsRoute.insights,
            onTap: () {
              if (activeRoute == SelmsRoute.insights) return;
              Navigator.of(context).pushReplacement(
                MaterialPageRoute(
                  builder: (_) => LifecycleInsightsScreen(apiBaseUrl: apiBaseUrl, hrToken: hrToken),
                ),
              );
            },
          ),
          _NavItem(
            icon: Icons.calendar_month_outlined,
            label: 'Smart Schedule',
            badge: const TabBadge(types: hrScheduleTypes),
            active: activeRoute == SelmsRoute.smartSchedule,
            onTap: () {
              if (activeRoute == SelmsRoute.smartSchedule) return;
              Navigator.of(context).pushReplacement(
                MaterialPageRoute(
                  builder: (_) => SmartScheduleScreen(apiBaseUrl: apiBaseUrl, hrToken: hrToken),
                ),
              );
            },
          ),
          _NavItem(
            icon: Icons.local_shipping_outlined,
            label: 'Shipments',
            badge: const TabBadge(types: hrShipmentsTypes),
            active: activeRoute == SelmsRoute.shipments,
            onTap: () {
              if (activeRoute == SelmsRoute.shipments) return;
              Navigator.of(context).pushReplacement(
                MaterialPageRoute(
                  builder: (_) => HrShipmentsScreen(apiBaseUrl: apiBaseUrl, hrToken: hrToken),
                ),
              );
            },
          ),
          _NavItem(
            icon: Icons.inventory_2_outlined,
            label: 'Products',
            badge: const TabBadge(types: hrProductsTypes),
            active: activeRoute == SelmsRoute.products,
            onTap: () {
              if (activeRoute == SelmsRoute.products) return;
              Navigator.of(context).pushReplacement(
                MaterialPageRoute(
                  // IT's product list, view only for HR.
                  builder: (_) => ItProductsScreen(apiBaseUrl: apiBaseUrl, itToken: hrToken, viewOnly: true),
                ),
              );
            },
          ),
          _NavItem(
            icon: Icons.chat_bubble_outline,
            label: 'Messages',
            badge: const TabBadge(types: hrMessagesTypes),
            active: activeRoute == SelmsRoute.messages,
            onTap: () {
              if (activeRoute == SelmsRoute.messages) return;
              Navigator.of(context).pushReplacement(
                MaterialPageRoute(
                  builder: (_) => HrMessagesScreen(apiBaseUrl: apiBaseUrl, hrToken: hrToken),
                ),
              );
            },
          ),
          const Spacer(),
          _NavItem(
            icon: Icons.logout,
            label: 'Log out',
            active: false,
            onTap: () {
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => SelmsLoginScreen(apiBaseUrl: apiBaseUrl)),
                (route) => false,
              );
            },
          ),
        ],
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
    this.badge,
  });

  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  /// Red unread count, at the end of the row.
  final Widget? badge;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: active ? SelmsColors.accentBg : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: active ? SelmsColors.ink : SelmsColors.sidebarIconInactive),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13.5,
                  color: active ? SelmsColors.ink : SelmsColors.sidebarInactive,
                  fontWeight: active ? FontWeight.w500 : FontWeight.w400,
                ),
              ),
            ),
            ?badge,
          ],
        ),
      ),
    );
  }
}

/// Gives widgets inside a shell (HR or IT) the API address, token and role,
/// so shared pieces like the top bar's bell can call the backend without
/// every screen having to pass them down.
class SelmsSession extends InheritedWidget {
  const SelmsSession({
    super.key,
    required this.apiBaseUrl,
    required this.token,
    required this.role,
    required super.child,
  });

  final String apiBaseUrl;
  final String token;
  final String role; // 'hr' | 'it'

  static SelmsSession? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SelmsSession>();

  @override
  bool updateShouldNotify(SelmsSession old) =>
      apiBaseUrl != old.apiBaseUrl || token != old.token || role != old.role;
}

/// Small top-right cluster (bell + avatar + "HR Staff" or "IT Staff") reused on every page.
class TopBarActions extends StatelessWidget {
  const TopBarActions({super.key});

  @override
  Widget build(BuildContext context) {
    final staffLabel = SelmsSession.maybeOf(context)?.role == 'it' ? 'IT Staff' : 'HR Staff';
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const NotificationBell(),
        const SizedBox(width: 10),
        Container(
          width: 32,
          height: 32,
          decoration: const BoxDecoration(color: SelmsColors.ink, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Text(staffLabel,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: SelmsColors.ink)),
      ],
    );
  }
}

/// The bell: unread count badge, and a list of notifications (FYI),
/// reminders (please do this) and alerts (something is stuck) for the
/// signed-in HR or IT user. Polls quietly so new items appear on their own.
class NotificationBell extends StatefulWidget {
  const NotificationBell({super.key});

  @override
  State<NotificationBell> createState() => _NotificationBellState();
}

class _NotificationBellState extends State<NotificationBell> {
  List<Map<String, dynamic>> _items = [];
  int _unread = 0;
  Timer? _poll;
  ApiClient? _api;
  String _role = 'hr';
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final session = SelmsSession.maybeOf(context);
    if (session == null || _started) return;
    _started = true;
    _role = session.role;
    _api = ApiClient(baseUrl: session.apiBaseUrl, hrToken: session.token);
    _load();
    _poll = Timer.periodic(const Duration(seconds: 30), (_) => _load());
    // A tab opened (and cleared its notifications) - follow it straight away.
    staffUnreadTotal.addListener(_followTotal);
  }

  void _followTotal() {
    if (mounted && staffUnreadTotal.value != _unread) setState(() => _unread = staffUnreadTotal.value);
  }

  @override
  void dispose() {
    _poll?.cancel();
    staffUnreadTotal.removeListener(_followTotal);
    super.dispose();
  }

  Future<void> _load() async {
    final api = _api;
    if (api == null) return;
    try {
      final data = await api.getStaffNotifications();
      if (!mounted) return;
      setStaffUnread(data);
      setState(() {
        _items = (data['notifications'] as List).cast<Map<String, dynamic>>();
        _unread = (data['unread_count'] as num?)?.toInt() ?? 0;
      });
    } catch (_) {
      // Quiet - the bell just keeps its last known state.
    }
  }

  IconData _iconFor(String kind) => switch (kind) {
        'reminder' => Icons.alarm,
        'alert' => Icons.warning_amber_rounded,
        _ => Icons.notifications_none,
      };

  Color _colorFor(String kind) => switch (kind) {
        'reminder' => const Color(0xFFB45309),
        'alert' => SelmsColors.rose,
        _ => const Color(0xFF1D4ED8),
      };

  String _ago(String iso) {
    final at = DateTime.tryParse(iso);
    if (at == null) return '';
    final d = DateTime.now().toUtc().difference(at.toUtc());
    if (d.inMinutes < 1) return 'just now';
    if (d.inMinutes < 60) return '${d.inMinutes}m ago';
    if (d.inHours < 24) return '${d.inHours}h ago';
    return '${d.inDays}d ago';
  }

  /// "4 Nov, 2:30 PM"
  String _whenConfirmed(String iso) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final d = DateTime.parse(iso).toLocal();
    final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
    return '${d.day} ${months[d.month - 1]}, $h:${d.minute.toString().padLeft(2, '0')} ${d.hour >= 12 ? 'PM' : 'AM'}';
  }

  /// The "I got it" button, or who confirmed it and when.
  Widget _confirmation(Map<String, dynamic> n, VoidCallback refreshList) {
    final at = n['confirmed_at'] as String?;
    if (at != null) {
      final who = n['confirmed_by'] as String?;
      return Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Text('✓ Confirmed${who == null ? '' : ' by $who'}, ${_whenConfirmed(at)}',
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF16A34A))),
      );
    }
    return Align(
      alignment: Alignment.centerRight,
      child: Padding(
        padding: const EdgeInsets.only(top: 6),
        child: ElevatedButton(
          onPressed: () async {
            try {
              await _api?.confirmStaffNotification(n['id'] as String);
            } catch (_) {}
            await _load();
            refreshList();
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: SelmsColors.ink,
            foregroundColor: Colors.white,
            elevation: 0,
            visualDensity: VisualDensity.compact,
            textStyle: const TextStyle(fontSize: 12),
          ),
          child: const Text('I got it'),
        ),
      ),
    );
  }

  Future<void> _open(Map<String, dynamic> n) async {
    final api = _api;
    if (api != null && n['read'] != true) {
      try {
        await api.markStaffNotificationRead(n['id'] as String);
      } catch (_) {}
      await _load();
    }
    if (!mounted) return;
    final link = (n['link'] as Map?)?.cast<String, dynamic>() ?? {};
    final session = SelmsSession.maybeOf(context);
    if (session == null) return;
    Navigator.of(context).pop(); // close the list
    if (link['type'] == 'employee' && _role == 'hr' && link['employee_id'] != null) {
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => EmployeeViewScreen(
          apiBaseUrl: session.apiBaseUrl,
          hrToken: session.token,
          employeeId: link['employee_id'] as String,
        ),
      ));
    } else if (link['type'] == 'lifecycle' && _role == 'hr') {
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => LifecycleInsightsScreen(apiBaseUrl: session.apiBaseUrl, hrToken: session.token),
      ));
    } else if (link['type'] == 'schedule' && _role == 'hr') {
      Navigator.of(context).pushReplacement(MaterialPageRoute(
        builder: (_) => SmartScheduleScreen(apiBaseUrl: session.apiBaseUrl, hrToken: session.token),
      ));
    } else if (link['type'] == 'products' && _role == 'hr') {
      Navigator.of(context).pushReplacement(MaterialPageRoute(
        builder: (_) => ItProductsScreen(apiBaseUrl: session.apiBaseUrl, itToken: session.token, viewOnly: true),
      ));
    } else if (link['type'] == 'shipments' && _role == 'hr') {
      Navigator.of(context).pushReplacement(MaterialPageRoute(
        builder: (_) => HrShipmentsScreen(apiBaseUrl: session.apiBaseUrl, hrToken: session.token),
      ));
    } else if (link['type'] == 'requests' && _role == 'it') {
      Navigator.of(context).pushReplacement(MaterialPageRoute(
        builder: (_) => ItRequestsScreen(apiBaseUrl: session.apiBaseUrl, itToken: session.token),
      ));
    } else if (link['type'] == 'shipments' && _role == 'it') {
      Navigator.of(context).pushReplacement(MaterialPageRoute(
        builder: (_) => ItShipmentsScreen(
          apiBaseUrl: session.apiBaseUrl,
          itToken: session.token,
          initialDirection: link['direction'] as String?,
        ),
      ));
    }
  }

  Future<void> _showList() async {
    await _load();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierColor: Colors.transparent,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => Align(
          alignment: Alignment.topRight,
          child: Padding(
            padding: const EdgeInsets.only(top: 62, right: 24),
            child: Material(
              color: Colors.white,
              elevation: 8,
              borderRadius: BorderRadius.circular(14),
              clipBehavior: Clip.antiAlias,
              child: SizedBox(
                width: 380,
                height: 480,
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 14, 8, 10),
                      child: Row(
                        children: [
                          const Expanded(
                            child: Text('Notifications',
                                style: TextStyle(
                                    fontSize: 14, fontWeight: FontWeight.w600, color: SelmsColors.textPrimary)),
                          ),
                          if (_unread > 0)
                            TextButton(
                              onPressed: () async {
                                try {
                                  await _api?.markAllStaffNotificationsRead();
                                } catch (_) {}
                                await _load();
                                setDialogState(() {});
                              },
                              child: const Text('Mark all read', style: TextStyle(fontSize: 12)),
                            ),
                        ],
                      ),
                    ),
                    const Divider(height: 1, color: SelmsColors.border),
                    Expanded(
                      child: _items.isEmpty
                          ? const Center(
                              child: Text("You're all caught up.",
                                  style: TextStyle(fontSize: 12.5, color: SelmsColors.textMuted)),
                            )
                          : ListView.separated(
                              itemCount: _items.length,
                              separatorBuilder: (_, _) => const Divider(height: 1, color: SelmsColors.border),
                              itemBuilder: (_, i) {
                                final n = _items[i];
                                final unread = n['read'] != true;
                                final kind = n['kind'] as String? ?? 'notification';
                                return InkWell(
                                  onTap: () => _open(n),
                                  child: Container(
                                    color: unread ? SelmsColors.accentBg.withValues(alpha: 0.5) : null,
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                    child: Row(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Container(
                                          width: 30,
                                          height: 30,
                                          decoration: BoxDecoration(
                                            color: _colorFor(kind).withValues(alpha: 0.12),
                                            shape: BoxShape.circle,
                                          ),
                                          child: Icon(_iconFor(kind), size: 16, color: _colorFor(kind)),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(n['title'] as String? ?? '',
                                                  style: TextStyle(
                                                      fontSize: 12.5,
                                                      fontWeight: unread ? FontWeight.w600 : FontWeight.w500,
                                                      color: SelmsColors.textPrimary)),
                                              const SizedBox(height: 2),
                                              Text(n['message'] as String? ?? '',
                                                  style: const TextStyle(
                                                      fontSize: 11.5, height: 1.35, color: SelmsColors.textSecondary)),
                                              const SizedBox(height: 4),
                                              Text(_ago(n['at'] as String? ?? ''),
                                                  style: const TextStyle(fontSize: 10.5, color: SelmsColors.textMuted)),
                                              if (n['needs_confirm'] == true)
                                                _confirmation(n, () => setDialogState(() {})),
                                            ],
                                          ),
                                        ),
                                        if (unread)
                                          Container(
                                            margin: const EdgeInsets.only(top: 4, left: 6),
                                            width: 8,
                                            height: 8,
                                            decoration:
                                                const BoxDecoration(color: SelmsColors.rose, shape: BoxShape.circle),
                                          ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: _api == null ? null : _showList,
      borderRadius: BorderRadius.circular(16),
      child: SizedBox(
        width: 36,
        height: 36,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
              alignment: Alignment.center,
              child: const Icon(Icons.notifications_none, size: 16, color: SelmsColors.ink),
            ),
            if (_unread > 0)
              Positioned(
                top: 0,
                right: 0,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  constraints: const BoxConstraints(minWidth: 16),
                  decoration: BoxDecoration(color: SelmsColors.rose, borderRadius: BorderRadius.circular(10)),
                  child: Text(_unread > 99 ? '99+' : '$_unread',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 9.5, color: Colors.white, fontWeight: FontWeight.w700)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
