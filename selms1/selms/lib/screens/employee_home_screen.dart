// lib/screens/employee_home_screen.dart
//
// Employee's own mobile-style home: a top tab bar (Onboarding / Documents /
// Profile — matches the report's fig 3.28 layout, minus Chat until there's
// a chatbot backend) over a shared header. Every tab reads real data from
// /api/employee/me/*, scoped to this session's own token.

import 'package:flutter/material.dart';
import '../services/api_client.dart';
import '../theme/selms_colors.dart';
import 'selms_login_screen.dart';
import 'employee_onboarding_screen.dart';
import 'employee_documents_screen.dart';
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
  late final TabController _tabController;

  String? _fullName;
  bool _loadingName = true;

  @override
  void initState() {
    super.initState();
    _api = ApiClient(baseUrl: widget.apiBaseUrl, hrToken: widget.employeeToken);
    _tabController = TabController(length: 3, vsync: this);
    _loadName();
  }

  Future<void> _loadName() async {
    try {
      final profile = await _api.getMyProfile();
      if (!mounted) return;
      setState(() {
        _fullName = profile.fullName;
        _loadingName = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingName = false);
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
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

  @override
  Widget build(BuildContext context) {
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
                          if (_loadingName)
                            const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          else
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
                        labelColor: SelmsColors.ink,
                        unselectedLabelColor: SelmsColors.textMuted,
                        indicatorColor: SelmsColors.ink,
                        labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                        unselectedLabelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w400),
                        tabs: const [
                          Tab(text: 'Onboarding'),
                          Tab(text: 'Documents'),
                          Tab(text: 'Profile'),
                        ],
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      EmployeeOnboardingScreen(api: _api, fullName: _fullName),
                      EmployeeDocumentsScreen(api: _api),
                      EmployeeProfileScreen(api: _api, onProfileChanged: _loadName),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
