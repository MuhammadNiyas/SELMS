// lib/screens/employee_home_screen.dart
//
// The employee app's shell:
//  * a header - SELMS name, the notifications bell (a dropdown, not a
//    separate page) and the avatar menu (My profile, Log out);
//  * a top navigation bar - Home / Onboarding / Offboarding / Schedule /
//    Documents -
//    where each tab shows a red number when something new is waiting there.
//    Offboarding is always present but only has content once HR starts it;
//  * a floating chat bubble bottom-right, like HR's and IT's assistants,
//    holding everything chat-related (SmartBot, Talk to HR, Talk to IT),
//    with its own red number for new HR / IT replies.

import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../models/employee.dart';
import '../models/employee_self_service.dart';
import '../services/api_client.dart';
import '../theme/selms_colors.dart';
import '../widgets/employee_ui.dart';
import 'selms_login_screen.dart';
import 'employee_dashboard_screen.dart';
import 'employee_onboarding_screen.dart';
import 'employee_offboarding_screen.dart';
import 'employee_documents_screen.dart';
import 'employee_chat_screen.dart';
import 'employee_notifications_screen.dart';
import 'employee_profile_screen.dart';
import 'employee_schedule_screen.dart';

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

class _EmployeeHomeScreenState extends State<EmployeeHomeScreen> with SingleTickerProviderStateMixin {
  static const _tabKeys = ['home', 'onboarding', 'offboarding', 'schedule', 'documents'];

  late final ApiClient _api;
  late final TabController _tabController;
  Timer? _badgeTimer;

  Employee? _profile;
  int _unreadCount = 0;
  Map<String, int> _badges = const {};
  bool _loading = true;

  bool _chatOpen = false;
  bool _chatBuilt = false; // keep the chat alive once opened, so history survives closing it
  bool _alertsOpen = false;
  int _alertsOpenCount = 0; // a fresh dropdown (and fresh data) each time it opens
  int _homeReload = 0;

  @override
  void initState() {
    super.initState();
    _api = ApiClient(baseUrl: widget.apiBaseUrl, hrToken: widget.employeeToken);
    _tabController = TabController(length: _tabKeys.length, vsync: this)..addListener(_onTabChanged);
    _bootstrap();
    _badgeTimer = Timer.periodic(const Duration(seconds: 30), (_) => _refreshBadges());
  }

  Future<void> _bootstrap() async {
    try {
      final Employee profile;
      final EmployeeNotifications notifications;
      (profile, notifications) = await (_api.getMyProfile(), _api.getMyNotifications()).wait;
      if (!mounted) return;
      _profile = profile;
      _unreadCount = notifications.unreadCount;
      _badges = notifications.badges;
    } catch (_) {
      // The tabs show their own errors; the shell still opens.
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  void dispose() {
    _badgeTimer?.cancel();
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _refreshBadges() async {
    try {
      final n = await _api.getMyNotifications();
      if (!mounted) return;
      setState(() {
        _unreadCount = n.unreadCount;
        _badges = n.badges;
      });
    } catch (_) {
      // Non-critical - the numbers stay as they are until the next fetch.
    }
  }

  /// Opening a tab (or the chat) clears its red number from now on.
  Future<void> _markSeen(String section) async {
    try {
      await _api.markSectionSeen(section);
    } catch (_) {}
    await _refreshBadges();
  }

  void _onTabChanged() {
    if (_tabController.indexIsChanging) return;
    final key = _tabKeys[_tabController.index];
    if (key == 'home') {
      setState(() => _homeReload++);
    } else if (const {'onboarding', 'offboarding', 'documents'}.contains(key)) {
      _markSeen(key);
    }
  }

  Future<void> _refreshProfile() async {
    try {
      final profile = await _api.getMyProfile();
      if (!mounted) return;
      setState(() => _profile = profile);
    } catch (_) {}
  }

  void _goTo(String key) {
    final i = _tabKeys.indexOf(key);
    if (i >= 0) _tabController.animateTo(i);
  }

  void _navigate(EmpDestination d) {
    switch (d) {
      case EmpDestination.onboarding:
        _goTo('onboarding');
      case EmpDestination.offboarding:
        _goTo('offboarding');
      case EmpDestination.documents:
        _goTo('documents');
      case EmpDestination.profile:
        _openProfile();
    }
  }

  Future<void> _openProfile() async {
    setState(() {
      _alertsOpen = false;
      _chatOpen = false;
    });
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => Scaffold(
        backgroundColor: EmpColors.pageBg,
        appBar: AppBar(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.white,
          foregroundColor: SelmsColors.textPrimary,
          elevation: 0,
          title: const Text('My profile', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          bottom: const PreferredSize(
            preferredSize: Size.fromHeight(1),
            child: Divider(height: 1, color: SelmsColors.border),
          ),
        ),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: EmployeeProfileScreen(api: _api, onProfileChanged: _refreshProfile),
          ),
        ),
      ),
    ));
    if (mounted) setState(() => _homeReload++); // a new photo may finish "profile setup"
  }

  void _toggleAlerts() => setState(() {
        _alertsOpen = !_alertsOpen;
        if (_alertsOpen) {
          _alertsOpenCount++;
          _chatOpen = false;
        }
      });

  void _onAlertSelected(String? section) {
    setState(() => _alertsOpen = false);
    switch (section) {
      case 'onboarding' || 'offboarding':
        _goTo(section!);
      case 'messages':
        _setChat(true);
    }
  }

  void _setChat(bool open) {
    setState(() {
      _chatOpen = open;
      if (open) {
        _chatBuilt = true;
        _alertsOpen = false;
      }
    });
    if (open) _markSeen('messages');
  }

  void _logout() {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => SelmsLoginScreen(apiBaseUrl: widget.apiBaseUrl)),
      (route) => false,
    );
  }

  // ---------------------------------------------------------------- pieces

  Widget _countBadge(int count, Widget child) => Badge(
        isLabelVisible: count > 0,
        label: Text(count > 9 ? '9+' : '$count', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700)),
        backgroundColor: SelmsColors.rose,
        textColor: Colors.white,
        child: child,
      );

  Widget _avatar(double radius) {
    final p = _profile;
    final url = p?.profileImageUrl;
    final hasUrl = url != null && url.isNotEmpty;
    return CircleAvatar(
      radius: radius,
      backgroundColor: SelmsColors.accentBg,
      foregroundImage: hasUrl ? NetworkImage('${widget.apiBaseUrl}$url') : null,
      onForegroundImageError: hasUrl ? (_, _) {} : null,
      child: Text(p?.initials ?? '?',
          style: TextStyle(fontSize: radius * 0.7, fontWeight: FontWeight.w700, color: SelmsColors.ink)),
    );
  }

  Widget _header() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 10, 8, 6),
      child: Row(
        children: [
          const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('SELMS',
                  style: TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w800, letterSpacing: 0.8, color: SelmsColors.textPrimary)),
              Text('Employee portal', style: TextStyle(fontSize: 10.5, color: SelmsColors.textMuted)),
            ],
          ),
          const Spacer(),
          IconButton(
            tooltip: 'Notifications',
            onPressed: _toggleAlerts,
            isSelected: _alertsOpen,
            icon: _countBadge(
              _unreadCount,
              Icon(_alertsOpen ? Icons.notifications_rounded : Icons.notifications_none_rounded,
                  size: 24, color: _alertsOpen ? SelmsColors.ink : SelmsColors.textSecondary),
            ),
          ),
          PopupMenuButton<String>(
            tooltip: 'Account',
            offset: const Offset(0, 44),
            color: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            onSelected: (v) => v == 'logout' ? _logout() : _openProfile(),
            itemBuilder: (_) => [
              PopupMenuItem<String>(
                enabled: false,
                child: Row(
                  children: [
                    _avatar(18),
                    const SizedBox(width: 10),
                    Flexible(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(_profile?.fullName ?? 'Employee',
                              style: const TextStyle(
                                  fontSize: 13, fontWeight: FontWeight.w700, color: SelmsColors.textPrimary)),
                          Text(_profile?.workEmail ?? '',
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 11.5, color: SelmsColors.textMuted)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: 'profile',
                child: Row(children: [
                  Icon(Icons.person_outline, size: 18),
                  SizedBox(width: 10),
                  Text('My profile', style: TextStyle(fontSize: 13)),
                ]),
              ),
              const PopupMenuItem(
                value: 'logout',
                child: Row(children: [
                  Icon(Icons.logout, size: 18, color: SelmsColors.rose),
                  SizedBox(width: 10),
                  Text('Log out', style: TextStyle(fontSize: 13, color: SelmsColors.rose)),
                ]),
              ),
            ],
            child: Padding(padding: const EdgeInsets.all(6), child: _avatar(17)),
          ),
        ],
      ),
    );
  }

  /// Equal-width tabs, icon over label, each with its own red number.
  Widget _navBar() {
    Tab tab(IconData icon, String label, int count) => Tab(
          height: 50,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _countBadge(count, Icon(icon, size: 20)),
              const SizedBox(height: 3),
              Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
            ],
          ),
        );
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
      child: TabBar(
        controller: _tabController,
        dividerColor: Colors.transparent,
        indicatorSize: TabBarIndicatorSize.tab,
        indicator: BoxDecoration(color: SelmsColors.ink, borderRadius: BorderRadius.circular(12)),
        labelColor: Colors.white,
        unselectedLabelColor: SelmsColors.textSecondary,
        labelStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
        unselectedLabelStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
        labelPadding: const EdgeInsets.symmetric(horizontal: 2),
        splashBorderRadius: BorderRadius.circular(12),
        tabs: [
          tab(Icons.home_outlined, 'Home', 0),
          tab(Icons.route_outlined, 'Onboarding', _badges['onboarding'] ?? 0),
          tab(Icons.logout, 'Offboarding', _badges['offboarding'] ?? 0),
          tab(Icons.calendar_month_outlined, 'Schedule', 0),
          tab(Icons.description_outlined, 'Documents', _badges['documents'] ?? 0),
        ],
      ),
    );
  }

  Widget _chatButton() {
    final unread = _badges['messages'] ?? 0;
    return SizedBox(
      width: 62,
      height: 62,
      child: Stack(
        alignment: Alignment.bottomLeft,
        children: [
          Material(
            color: SelmsColors.ink,
            shape: const CircleBorder(),
            elevation: 6,
            shadowColor: Colors.black38,
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: () => _setChat(!_chatOpen),
              child: SizedBox(
                width: 56,
                height: 56,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  child: Icon(
                    _chatOpen ? Icons.close_rounded : Icons.chat_bubble_outline_rounded,
                    key: ValueKey(_chatOpen),
                    size: 24,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
          if (unread > 0 && !_chatOpen)
            Positioned(
              top: 0,
              right: 0,
              child: Container(
                constraints: const BoxConstraints(minWidth: 22),
                height: 22,
                padding: const EdgeInsets.symmetric(horizontal: 6),
                decoration: BoxDecoration(
                  color: SelmsColors.rose,
                  borderRadius: BorderRadius.circular(11),
                  border: Border.all(color: Colors.white, width: 2),
                ),
                alignment: Alignment.center,
                child: Text(unread > 9 ? '9+' : '$unread',
                    style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: Colors.white)),
              ),
            ),
        ],
      ),
    );
  }

  Widget _chatOverlay() {
    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            onTap: () => _setChat(false),
            child: Container(color: Colors.black.withValues(alpha: 0.25)),
          ),
        ),
        Positioned(
          left: 12,
          right: 12,
          top: 12,
          bottom: 84,
          child: Material(
            elevation: 16,
            borderRadius: BorderRadius.circular(16),
            clipBehavior: Clip.antiAlias,
            color: Colors.white,
            child: EmployeeChatPanel(api: _api, onClose: () => _setChat(false)),
          ),
        ),
      ],
    );
  }

  Widget _alertsOverlay(BoxConstraints c) {
    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            onTap: () => setState(() => _alertsOpen = false),
            child: Container(color: Colors.black.withValues(alpha: 0.08)),
          ),
        ),
        Positioned(
          top: 58,
          right: 8,
          width: math.min(370, c.maxWidth - 16),
          child: Material(
            elevation: 14,
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            clipBehavior: Clip.antiAlias,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: c.maxHeight * 0.7),
              child: EmployeeNotificationsPanel(
                key: ValueKey(_alertsOpenCount),
                api: _api,
                onClose: () => setState(() => _alertsOpen = false),
                onRead: _refreshBadges,
                onSelect: _onAlertSelected,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _page(String key) => switch (key) {
        'home' => EmployeeDashboardScreen(
            api: _api,
            profile: _profile,
            onNavigate: _navigate,
            onOpenAlerts: _toggleAlerts,
            reloadToken: _homeReload,
          ),
        'onboarding' => EmployeeOnboardingScreen(
            api: _api,
            fullName: _profile?.fullName,
            onOpenDocuments: () => _goTo('documents'),
            onOpenProfile: _openProfile,
          ),
        'offboarding' => EmployeeOffboardingScreen(api: _api, onOpenDocuments: () => _goTo('documents')),
        'schedule' => EmployeeScheduleScreen(api: _api),
        _ => EmployeeDocumentsScreen(api: _api),
      };

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: EmpColors.pageBg,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: EmpColors.pageBg,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: LayoutBuilder(
              builder: (context, c) => Stack(
                children: [
                  Column(
                    children: [
                      Container(
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          border: Border(bottom: BorderSide(color: SelmsColors.border)),
                        ),
                        child: Column(children: [_header(), _navBar()]),
                      ),
                      Expanded(
                        child: TabBarView(
                          controller: _tabController,
                          children: [for (final k in _tabKeys) _page(k)],
                        ),
                      ),
                    ],
                  ),
                  if (_chatBuilt) Positioned.fill(child: Offstage(offstage: !_chatOpen, child: _chatOverlay())),
                  Positioned(right: 14, bottom: 14, child: _chatButton()),
                  if (_alertsOpen) Positioned.fill(child: _alertsOverlay(c)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
