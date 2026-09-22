// lib/screens/selms_login_screen.dart
//
// SELMS login screen — HR, IT, and Employee sign in from one screen.
// Restyled to match the black-sidebar / light-blue palette used across the
// HR admin screens (theme/selms_colors.dart).
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
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Signed in as ${_role.label} — screens not built yet.')),
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
      body: Row(
        children: [
          if (MediaQuery.of(context).size.width > 900)
            Expanded(
              flex: 5,
              child: Container(
                color: SelmsColors.ink,
                padding: const EdgeInsets.all(48),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: SelmsColors.accentBg,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          alignment: Alignment.center,
                          child: const Text('S',
                              style: TextStyle(
                                  color: SelmsColors.ink,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15)),
                        ),
                        const SizedBox(width: 10),
                        const Text('SELMS',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w600)),
                      ],
                    ),
                    const Spacer(),
                    const Text(
                      'One system.\nThree roles.\nNo manual handoffs.',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 28,
                        height: 1.25,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Onboarding and offboarding, coordinated automatically '
                      'between HR, IT and every new hire.',
                      style: TextStyle(color: Colors.white60, fontSize: 13.5, height: 1.5),
                    ),
                    const Spacer(),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const [
                        Icon(Icons.shield_outlined, color: Colors.white38, size: 16),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Accounts are provisioned by your HR administrator. '
                            'There is no public sign-up.',
                            style: TextStyle(color: Colors.white38, fontSize: 11.5, height: 1.4),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          Expanded(
            flex: 6,
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 400),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Sign in',
                          style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w700,
                              color: SelmsColors.textPrimary)),
                      const SizedBox(height: 4),
                      const Text('Choose your role, then enter your credentials.',
                          style: TextStyle(fontSize: 13, color: Colors.black54)),
                      const SizedBox(height: 24),
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
                                          size: 18,
                                          color: active ? SelmsColors.ink : SelmsColors.textMuted),
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
                      const SizedBox(height: 8),
                      Text(_role.hint,
                          style: const TextStyle(fontSize: 11.5, color: SelmsColors.textMuted)),
                      const SizedBox(height: 24),
                      const Text('Work email',
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: SelmsColors.textSecondary)),
                      const SizedBox(height: 6),
                      TextField(
                        controller: _emailCtrl,
                        keyboardType: TextInputType.emailAddress,
                        decoration: _fieldDecoration('you@company.my'),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Password',
                              style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: SelmsColors.textSecondary)),
                        ],
                      ),
                      const SizedBox(height: 6),
                      TextField(
                        controller: _passwordCtrl,
                        obscureText: _obscure,
                        decoration: _fieldDecoration('Enter your password').copyWith(
                          suffixIcon: IconButton(
                            icon: Icon(
                                _obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                                size: 19,
                                color: SelmsColors.textMuted),
                            onPressed: () => setState(() => _obscure = !_obscure),
                          ),
                        ),
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 14),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                          decoration: BoxDecoration(
                            color: SelmsColors.roseBg,
                            border: Border.all(color: SelmsColors.roseBorder),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(_error!,
                              style: const TextStyle(fontSize: 12, color: SelmsColors.rose)),
                        ),
                      ],
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _submitting ? null : _submit,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: SelmsColors.ink,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
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
                      const SizedBox(height: 20),
                      const Text(
                        "Don't have an account? Accounts aren't self-registered — "
                        "ask your HR administrator to add you.",
                        style: TextStyle(fontSize: 11.5, color: SelmsColors.textMuted, height: 1.4),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
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
