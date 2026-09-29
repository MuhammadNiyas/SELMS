// lib/widgets/it_app_shell.dart
//
// The IT role's own sidebar shell — separate from HR's AppShell since the
// nav items (Dashboard/Products, not Dashboard/Employees/Onboarding) and
// the token they carry are role-specific. Visually identical treatment
// (dark sidebar, light-blue content area) so it still feels like one app.

import 'package:flutter/material.dart';
import '../theme/selms_colors.dart';
import '../screens/selms_login_screen.dart';
import '../screens/it_dashboard_screen.dart';
import '../screens/it_products_screen.dart';
import '../screens/it_scan_screen.dart';
import '../screens/it_messages_screen.dart';

enum ItRoute { dashboard, products, scan, messages }

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

  @override
  Widget build(BuildContext context) {
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
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(color: SelmsColors.accentBg, borderRadius: BorderRadius.circular(8)),
                  alignment: Alignment.center,
                  child: const Text('S',
                      style: TextStyle(color: SelmsColors.ink, fontWeight: FontWeight.bold, fontSize: 14)),
                ),
                const SizedBox(width: 10),
                const Text('SELMS',
                    style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600)),
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
            icon: Icons.chat_bubble_outline,
            label: 'Messages',
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
  const _ItNavItem({required this.icon, required this.label, required this.active, required this.onTap});

  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

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
            Text(label,
                style: TextStyle(
                  fontSize: 13.5,
                  color: active ? SelmsColors.ink : SelmsColors.sidebarInactive,
                  fontWeight: active ? FontWeight.w500 : FontWeight.w400,
                )),
          ],
        ),
      ),
    );
  }
}
