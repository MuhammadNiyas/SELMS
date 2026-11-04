// lib/widgets/it_app_shell.dart
//
// The IT role's own sidebar shell — separate from HR's AppShell since the
// nav items (Dashboard/Products, not Dashboard/Employees/Onboarding) and
// the token they carry are role-specific. Visually identical treatment
// (dark sidebar, light-blue content area) so it still feels like one app.

import 'package:flutter/material.dart';
import '../services/api_client.dart';
import '../theme/selms_colors.dart';
import 'app_shell.dart' show SelmsSession;
import 'chat_panel.dart';
import 'tab_badges.dart';
import '../screens/selms_login_screen.dart';
import '../screens/it_dashboard_screen.dart';
import '../screens/it_products_screen.dart';
import '../screens/it_scan_screen.dart';
import '../screens/it_messages_screen.dart';
import '../screens/it_requests_screen.dart';
import '../screens/it_shipments_screen.dart';
import '../screens/it_schedule_screen.dart';

enum ItRoute { dashboard, products, scan, shipments, schedule, requests, messages }

class ItAppShell extends StatefulWidget {
  const ItAppShell({
    super.key,
    required this.apiBaseUrl,
    required this.itToken,
    required this.activeRoute,
    required this.child,
  });

  final String apiBaseUrl;
  final String itToken;
  final ItRoute activeRoute;
  final Widget child;

  @override
  State<ItAppShell> createState() => _ItAppShellState();
}

class _ItAppShellState extends State<ItAppShell> {
  bool _collapsed = false;
  bool _chatOpen = false;

  // Red counts on Messages / Shipments; opening one of them clears its own.
  late final TabBadgePoller _badges = TabBadgePoller(
    ApiClient(baseUrl: widget.apiBaseUrl, hrToken: widget.itToken),
    openTypes: switch (widget.activeRoute) {
      ItRoute.requests => itRequestsTypes,
      ItRoute.messages => itMessagesTypes,
      ItRoute.shipments => itShipmentsTypes,
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

  /// IT's assistant: finds and shares company documents (policies, forms).
  void _openChat() {
    if (_chatOpen) return;
    setState(() => _chatOpen = true);
    final api = ApiClient(baseUrl: widget.apiBaseUrl, hrToken: widget.itToken);
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
            title: 'SELMS IT Assistant',
            hint: "Hi! I'm your SELMS IT Assistant. Ask me about equipment, warranties, parcels or company documents.",
            suggestions: const ['which laptops are free?', 'warranties ending soon', 'IT policy'],
            onSend: api.itChat,
            documentUrl: api.documentDownloadUrl,
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
      token: widget.itToken,
      role: 'it',
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
                  child: _ItSidebar(
                    apiBaseUrl: widget.apiBaseUrl,
                    itToken: widget.itToken,
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
                  decoration: BoxDecoration(color: SelmsColors.ink, borderRadius: BorderRadius.circular(8)),
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

class _ItSidebar extends StatelessWidget {
  const _ItSidebar({
    required this.apiBaseUrl,
    required this.itToken,
    required this.activeRoute,
    required this.onCollapse,
  });

  final String apiBaseUrl;
  final String itToken;
  final ItRoute activeRoute;
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
          _ItNavItem(
            icon: Icons.dashboard_outlined,
            label: 'Dashboard',
            active: activeRoute == ItRoute.dashboard,
            onTap: () {
              if (activeRoute == ItRoute.dashboard) return;
              Navigator.of(context).pushReplacement(
                MaterialPageRoute(
                  builder: (_) => ItDashboardScreen(apiBaseUrl: apiBaseUrl, itToken: itToken),
                ),
              );
            },
          ),
          _ItNavItem(
            icon: Icons.inventory_2_outlined,
            label: 'Products',
            active: activeRoute == ItRoute.products,
            onTap: () {
              if (activeRoute == ItRoute.products) return;
              Navigator.of(context).pushReplacement(
                MaterialPageRoute(
                  builder: (_) => ItProductsScreen(apiBaseUrl: apiBaseUrl, itToken: itToken),
                ),
              );
            },
          ),
          _ItNavItem(
            icon: Icons.qr_code_scanner,
            label: 'Scan',
            active: activeRoute == ItRoute.scan,
            onTap: () {
              if (activeRoute == ItRoute.scan) return;
              Navigator.of(context).pushReplacement(
                MaterialPageRoute(
                  builder: (_) => ItScanScreen(apiBaseUrl: apiBaseUrl, itToken: itToken),
                ),
              );
            },
          ),
          _ItNavItem(
            icon: Icons.local_shipping_outlined,
            label: 'Shipments',
            badge: const TabBadge(types: itShipmentsTypes),
            active: activeRoute == ItRoute.shipments,
            onTap: () {
              if (activeRoute == ItRoute.shipments) return;
              Navigator.of(context).pushReplacement(
                MaterialPageRoute(
                  builder: (_) => ItShipmentsScreen(apiBaseUrl: apiBaseUrl, itToken: itToken),
                ),
              );
            },
          ),
          _ItNavItem(
            icon: Icons.calendar_month_outlined,
            label: 'Schedule',
            active: activeRoute == ItRoute.schedule,
            onTap: () {
              if (activeRoute == ItRoute.schedule) return;
              Navigator.of(context).pushReplacement(
                MaterialPageRoute(
                  builder: (_) => ItScheduleScreen(apiBaseUrl: apiBaseUrl, itToken: itToken),
                ),
              );
            },
          ),
          _ItNavItem(
            icon: Icons.assignment_outlined,
            label: 'Requests',
            badge: const TabBadge(types: itRequestsTypes),
            active: activeRoute == ItRoute.requests,
            onTap: () {
              if (activeRoute == ItRoute.requests) return;
              Navigator.of(context).pushReplacement(
                MaterialPageRoute(
                  builder: (_) => ItRequestsScreen(apiBaseUrl: apiBaseUrl, itToken: itToken),
                ),
              );
            },
          ),
          _ItNavItem(
            icon: Icons.chat_bubble_outline,
            label: 'Messages',
            badge: const TabBadge(types: itMessagesTypes),
            active: activeRoute == ItRoute.messages,
            onTap: () {
              if (activeRoute == ItRoute.messages) return;
              Navigator.of(context).pushReplacement(
                MaterialPageRoute(
                  builder: (_) => ItMessagesScreen(apiBaseUrl: apiBaseUrl, itToken: itToken),
                ),
              );
            },
          ),
          const Spacer(),
          _ItNavItem(
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

class _ItNavItem extends StatelessWidget {
  const _ItNavItem({required this.icon, required this.label, required this.active, required this.onTap, this.badge});

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
              child: Text(label,
                  style: TextStyle(
                    fontSize: 13.5,
                    color: active ? SelmsColors.ink : SelmsColors.sidebarInactive,
                    fontWeight: active ? FontWeight.w500 : FontWeight.w400,
                  )),
            ),
            ?badge,
          ],
        ),
      ),
    );
  }
}
