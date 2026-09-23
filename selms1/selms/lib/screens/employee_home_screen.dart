// lib/screens/employee_home_screen.dart
//
// Employee's own mobile-style home: a top tab bar over a shared header.
// Base tabs are Onboarding / Documents / Alerts / Profile (matches the
// report's fig 3.28 layout, minus Chat until there's a chatbot backend).
// An Offboarding tab is inserted only once HR has actually initiated
// offboarding for this employee — most employees never see it.

import 'package:flutter/material.dart';
import '../models/employee.dart';
import '../models/employee_self_service.dart';
import '../services/api_client.dart';
import '../theme/selms_colors.dart';
import 'selms_login_screen.dart';
import 'employee_onboarding_screen.dart';
import 'employee_offboarding_screen.dart';
import 'employee_documents_screen.dart';
import 'employee_notifications_screen.dart';
import 'employee_profile_screen.dart';

class EmployeeHomeScreen extends StatefulWidget {
  const EmployeeHomeScreen({
    super.key,
    required this.apiBaseUrl,
    required this.employeeToken,
  });

  final String apiBaseUrl;
  final String employeeToken;

  @override
  State<EmployeeHomeScreen> createState() => _EmployeeHomeScreenState();
}

class _EmployeeHomeScreenState extends State<EmployeeHomeScreen>
    with SingleTickerProviderStateMixin {
  late final ApiClient _api;
  TabController? _tabController;

  String? _fullName;
  bool _offboardingStarted = false;
  int _unreadCount = 0;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _api = ApiClient(baseUrl: widget.apiBaseUrl, hrToken: widget.employeeToken);
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    try {
      final Employee profile;
      final OffboardingChecklist offboarding;
      final EmployeeNotifications notifications;
      (profile, offboarding, notifications) = await (
        _api.getMyProfile(),
        _api.getMyOffboarding(),
        _api.getMyNotifications(),
      ).wait;
      if (!mounted) return;
      setState(() {
        _fullName = profile.fullName;
        _offboardingStarted = offboarding.started;
        _unreadCount = notifications.unreadCount;
        _tabController = TabController(length: _tabCount, vsync: this);
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _tabController = TabController(length: _tabCount, vsync: this);
        _loading = false;
      });
    }
  }

  int get _tabCount => _offboardingStarted ? 5 : 4;

  Future<void> _refreshUnreadCount() async {
    try {
      final notifications = await _api.getMyNotifications();
      if (!mounted) return;
      setState(() => _unreadCount = notifications.unreadCount);
    } catch (_) {
      // Non-critical — badge just stays as-is until the next successful fetch.
    }
  }

  Future<void> _refreshName() async {
    try {
      final profile = await _api.getMyProfile();
      if (!mounted) return;
      setState(() => _fullName = profile.fullName);
    } catch (_) {}
  }

  @override
  void dispose() {
    _tabController?.dispose();
    super.dispose();
  }

  String get _initials {
    final name = _fullName?.trim() ?? '';
    if (name.isEmpty) return '?';
    final parts = name.split(RegExp(r'\s+'));
    if (parts.length == 1) return parts[0].substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1)).toUpperCase();
  }

  void _logout() {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => SelmsLoginScreen(apiBaseUrl: widget.apiBaseUrl)),
      (route) => false,
    );
  }

  Widget _alertsTabLabel() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text('Alerts'),
        if (_unreadCount > 0) ...[
          const SizedBox(width: 5),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            decoration: BoxDecoration(color: SelmsColors.rose, borderRadius: BorderRadius.circular(8)),
            child: Text('$_unreadCount',
                style: const TextStyle(fontSize: 9.5, color: Colors.white, fontWeight: FontWeight.w700)),
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading || _tabController == null) {
      return const Scaffold(
        backgroundColor: SelmsColors.accentBg,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final tabs = <Tab>[
      const Tab(text: 'Onboarding'),
      if (_offboardingStarted) const Tab(text: 'Offboarding'),
      const Tab(text: 'Documents'),
      Tab(child: _alertsTabLabel()),
      const Tab(text: 'Profile'),
    ];

    final pages = <Widget>[
      EmployeeOnboardingScreen(api: _api, fullName: _fullName),
      if (_offboardingStarted) EmployeeOffboardingScreen(api: _api),
      EmployeeDocumentsScreen(api: _api),
      EmployeeNotificationsScreen(api: _api, onRead: _refreshUnreadCount),
      EmployeeProfileScreen(api: _api, onProfileChanged: _refreshName),
    ];

    return Scaffold(
      backgroundColor: SelmsColors.accentBg,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Column(
              children: [
                Container(
                  color: SelmsColors.cardWhite,
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 28,
                            height: 28,
                            decoration: BoxDecoration(
                              color: SelmsColors.ink,
                              borderRadius: BorderRadius.circular(7),
                            ),
                            alignment: Alignment.center,
                            child: const Text('S',
                                style: TextStyle(
                                    color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                          ),
                          const SizedBox(width: 8),
                          const Text('SELMS',
                              style: TextStyle(
                                  fontSize: 15, fontWeight: FontWeight.w600, color: SelmsColors.textPrimary)),
                          const Spacer(),
                          CircleAvatar(
                            radius: 15,
                            backgroundColor: SelmsColors.accentBg,
                            child: Text(_initials,
                                style: const TextStyle(
                                    fontSize: 11, fontWeight: FontWeight.w600, color: SelmsColors.ink)),
                          ),
                          IconButton(
                            icon: const Icon(Icons.logout, size: 19, color: SelmsColors.textMuted),
                            tooltip: 'Log out',
                            onPressed: _logout,
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      TabBar(
                        controller: _tabController,
                        isScrollable: tabs.length > 4,
                        labelColor: SelmsColors.ink,
                        unselectedLabelColor: SelmsColors.textMuted,
                        indicatorColor: SelmsColors.ink,
                        labelStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                        unselectedLabelStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w400),
                        tabs: tabs,
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: TabBarView(controller: _tabController, children: pages),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
