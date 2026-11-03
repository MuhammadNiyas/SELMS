// lib/screens/selms_login_screen.dart
//
// SELMS login screen — HR, IT, and Employee sign in from one screen.
// A single centred sign-in card under the system title, in the same
// black / light-blue palette as the HR admin screens (theme/selms_colors.dart).
//
// There is deliberately no "Register" action here. Accounts are provisioned
// by the seeded HR admin (scripts/seed_account.py) and, afterwards, by HR
// itself from inside the app (Employees -> Add employee).

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../theme/selms_colors.dart';
import 'dashboard_screen.dart';
import 'it_dashboard_screen.dart';
import 'employee_home_screen.dart';
import 'employee_set_password_screen.dart';

enum SelmsRole { hr, it, employee }

extension SelmsRoleX on SelmsRole {
  String get label => switch (this) {
        SelmsRole.hr => 'HR Staff',
        SelmsRole.it => 'IT Staff',
        SelmsRole.employee => 'Employee',
      };

  String get hint => switch (this) {
        SelmsRole.hr => 'Manage employees, onboarding & offboarding',
        SelmsRole.it => 'Equipment, QR tracking & provisioning',
        SelmsRole.employee => 'Checklist, documents & chat',
      };

  String get apiValue => switch (this) {
        SelmsRole.hr => 'hr',
        SelmsRole.it => 'it',
        SelmsRole.employee => 'employee',
      };

  IconData get icon => switch (this) {
        SelmsRole.hr => Icons.apartment_rounded,
        SelmsRole.it => Icons.build_rounded,
        SelmsRole.employee => Icons.person_rounded,
      };
}

class SelmsLoginScreen extends StatefulWidget {
  const SelmsLoginScreen({super.key, required this.apiBaseUrl});

  /// e.g. https://api.selms.my  or  http://localhost:5000
  final String apiBaseUrl;

  @override
  State<SelmsLoginScreen> createState() => _SelmsLoginScreenState();
}

class _SelmsLoginScreenState extends State<SelmsLoginScreen> {
  SelmsRole _role = SelmsRole.hr;
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _obscure = true;
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _emailCtrl.text.trim();
    final password = _passwordCtrl.text;

    if (email.isEmpty || password.isEmpty) {
      setState(() => _error = 'Enter your email and password to continue.');
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      final res = await http.post(
        Uri.parse('${widget.apiBaseUrl}/api/auth/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'role': _role.apiValue,
          'email': email,
          'password': password,
        }),
      );

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final token = data['token'] as String;
        // TODO: persist token (flutter_secure_storage / shared_preferences)
        if (!mounted) return;

        if (_role == SelmsRole.hr) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (_) => DashboardScreen(
                apiBaseUrl: widget.apiBaseUrl,
                hrToken: token,
              ),
            ),
          );
        } else if (_role == SelmsRole.it) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (_) => ItDashboardScreen(
                apiBaseUrl: widget.apiBaseUrl,
                itToken: token,
              ),
            ),
          );
        } else if (data['must_change_password'] == true) {
          // Still on HR's temporary password - make them choose their own first.
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (_) => EmployeeSetPasswordScreen(
                apiBaseUrl: widget.apiBaseUrl,
                employeeToken: token,
                temporaryPassword: password,
                fullName: data['full_name'] as String?,
              ),
            ),
          );
        } else {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (_) => EmployeeHomeScreen(
                apiBaseUrl: widget.apiBaseUrl,
                employeeToken: token,
              ),
            ),
          );
        }
      } else {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        setState(() => _error = data['message'] ?? 'Invalid email, password, or role.');
      }
    } catch (e) {
      setState(() => _error = 'Could not reach the server. Check your connection.');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SelmsColors.accentBg,
      body: SafeArea(
        child: Column(
          children: [
            // ---- title, centred at the top ----
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 56, 24, 0),
              child: const Text(
                'SMART EMPLOYEE LIFECYCLE MANAGEMENT SYSTEM',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 24,
                  height: 1.3,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                  color: SelmsColors.textPrimary,
                ),
              ),
            ),
            // ---- sign-in card, centred in the page ----
            Expanded(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.fromLTRB(28, 26, 28, 28),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.06),
                                blurRadius: 24,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          child: _signInForm(),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _signInForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Sign in',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: SelmsColors.textPrimary)),
        const SizedBox(height: 4),
        const Text('Choose your role, then enter your credentials.',
            style: TextStyle(fontSize: 12.5, color: SelmsColors.textSecondary)),
        const SizedBox(height: 20),
        Row(
          children: SelmsRole.values.map((r) {
            final active = r == _role;
            return Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: InkWell(
                  onTap: () => setState(() => _role = r),
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color: active ? SelmsColors.accentBg : Colors.white,
                      border: Border.all(
                        color: active ? SelmsColors.ink : SelmsColors.border,
                        width: active ? 1.4 : 1,
                      ),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Column(
                      children: [
                        Icon(r.icon,
                            size: 18, color: active ? SelmsColors.ink : SelmsColors.textMuted),
                        const SizedBox(height: 6),
                        Text(
                          r.label,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: active ? SelmsColors.ink : SelmsColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 22),
        const Text('Work email',
            style: TextStyle(
                fontSize: 12, fontWeight: FontWeight.w600, color: SelmsColors.textSecondary)),
        const SizedBox(height: 6),
        TextField(
          controller: _emailCtrl,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.next,
          decoration: _fieldDecoration('you@company.my'),
        ),
        const SizedBox(height: 16),
        const Text('Password',
            style: TextStyle(
                fontSize: 12, fontWeight: FontWeight.w600, color: SelmsColors.textSecondary)),
        const SizedBox(height: 6),
        TextField(
          controller: _passwordCtrl,
          obscureText: _obscure,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _submitting ? null : _submit(),
          decoration: _fieldDecoration('Enter your password').copyWith(
            suffixIcon: IconButton(
              icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                  size: 19, color: SelmsColors.textMuted),
              onPressed: () => setState(() => _obscure = !_obscure),
            ),
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: SelmsColors.roseBg,
              border: Border.all(color: SelmsColors.roseBorder),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(_error!, style: const TextStyle(fontSize: 12, color: SelmsColors.rose)),
          ),
        ],
        const SizedBox(height: 22),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _submitting ? null : _submit,
            style: ElevatedButton.styleFrom(
              backgroundColor: SelmsColors.ink,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 15),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              elevation: 0,
            ),
            child: _submitting
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : Text('Sign in as ${_role.label}',
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
          ),
        ),
      ],
    );
  }

  InputDecoration _fieldDecoration(String hintText) {
    return InputDecoration(
      hintText: hintText,
      hintStyle: const TextStyle(color: SelmsColors.textMuted, fontSize: 13.5),
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: SelmsColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: SelmsColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: SelmsColors.ink, width: 1.4),
      ),
    );
  }
}
