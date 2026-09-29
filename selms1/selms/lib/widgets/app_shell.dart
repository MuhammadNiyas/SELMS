// lib/widgets/app_shell.dart
//
// The dark sidebar + light blue content shell shared by every HR screen.
// Pass a `child` for the page body; AppShell handles the sidebar (which can
// collapse for a full-width view), nav highlighting, and log out.

import 'package:flutter/material.dart';
import '../theme/selms_colors.dart';
import '../services/api_client.dart';
import '../screens/selms_login_screen.dart';
import '../screens/dashboard_screen.dart';
import '../screens/employee_directory_screen.dart';
import '../screens/onboarding_screen.dart';
import '../screens/offboarding_screen.dart';
import '../screens/smart_schedule_screen.dart';
import '../screens/hr_messages_screen.dart';
import 'chat_panel.dart';

enum SelmsRoute { dashboard, employees, onboarding, offboarding, smartSchedule, messages }

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

  void _openChat() {
    if (_chatOpen) return;
    setState(() => _chatOpen = true);
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
            suggestions: const ['overdue', 'offboarding', 'equipment', 'reminder'],
            onSend: (message, history) =>
                ApiClient(baseUrl: widget.apiBaseUrl, hrToken: widget.hrToken).hrChat(message, history),
          ),
        ),
      ),
    ).then((_) {
      if (mounted) setState(() => _chatOpen = false);
    });
  }

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
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: SelmsColors.accentBg,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  alignment: Alignment.center,
                  child: const Text('S',
                      style: TextStyle(
                          color: SelmsColors.ink, fontWeight: FontWeight.bold, fontSize: 14)),
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
            icon: Icons.calendar_month_outlined,
            label: 'Smart Schedule',
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
            icon: Icons.chat_bubble_outline,
            label: 'Messages',
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
  });

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
            Text(
              label,
              style: TextStyle(
                fontSize: 13.5,
                color: active ? SelmsColors.ink : SelmsColors.sidebarInactive,
                fontWeight: active ? FontWeight.w500 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Small top-right cluster (bell + avatar + "Admin") reused on every page.
class TopBarActions extends StatelessWidget {
  const TopBarActions({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
          alignment: Alignment.center,
          child: const Icon(Icons.notifications_none, size: 16, color: SelmsColors.ink),
        ),
        const SizedBox(width: 10),
        Container(
          width: 32,
          height: 32,
          decoration: const BoxDecoration(color: SelmsColors.ink, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        const Text('Admin',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: SelmsColors.ink)),
      ],
    );
  }
}
