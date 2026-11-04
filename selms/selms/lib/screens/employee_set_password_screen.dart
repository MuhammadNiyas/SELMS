// lib/screens/employee_set_password_screen.dart
//
// Shown right after an employee signs in with the temporary password HR
// emailed them (the login response says must_change_password). They choose
// their own password here before reaching the employee app; the temporary
// one stops working the moment the new one is saved.

import 'package:flutter/material.dart';
import '../services/api_client.dart';
import '../theme/selms_colors.dart';
import 'employee_home_screen.dart';
import 'selms_login_screen.dart';

class EmployeeSetPasswordScreen extends StatefulWidget {
  const EmployeeSetPasswordScreen({
    super.key,
    required this.apiBaseUrl,
    required this.employeeToken,
    required this.temporaryPassword,
    this.fullName,
  });

  final String apiBaseUrl;
  final String employeeToken;

  /// What they just signed in with - sent as the "current" password so they
  /// don't have to type HR's password a second time.
  final String temporaryPassword;
  final String? fullName;

  @override
  State<EmployeeSetPasswordScreen> createState() => _EmployeeSetPasswordScreenState();
}

class _EmployeeSetPasswordScreenState extends State<EmployeeSetPasswordScreen> {
  final _newCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _obscure = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _newCtrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _newCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  bool get _rightLength => _newCtrl.text.length >= 8 && _newCtrl.text.length <= 10;
  bool get _hasUppercase => RegExp(r'[A-Z]').hasMatch(_newCtrl.text);
  bool get _hasNumber => RegExp(r'\d').hasMatch(_newCtrl.text);
  bool get _hasSpecial => RegExp(r'[^A-Za-z0-9\s]').hasMatch(_newCtrl.text);

  Future<void> _save() async {
    if (!_rightLength || !_hasUppercase || !_hasNumber || !_hasSpecial) {
      setState(() => _error =
          'Your password needs 8 to 10 characters, with an uppercase letter, a number and a special character.');
      return;
    }
    if (_newCtrl.text != _confirmCtrl.text) {
      setState(() => _error = "The two passwords don't match.");
      return;
    }
    if (_newCtrl.text == widget.temporaryPassword) {
      setState(() => _error = 'Choose a password different from the temporary one HR sent you.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final api = ApiClient(baseUrl: widget.apiBaseUrl, hrToken: widget.employeeToken);
      await api.changeMyPassword(widget.temporaryPassword, _newCtrl.text);
      if (!mounted) return;
      Navigator.of(context).pushReplacement(MaterialPageRoute(
        builder: (_) => EmployeeHomeScreen(apiBaseUrl: widget.apiBaseUrl, employeeToken: widget.employeeToken),
      ));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = e.toString();
      });
    }
  }

  InputDecoration _field(String hint) => InputDecoration(
        hintText: hint,
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

  Widget _rule(bool ok, String text) => Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Row(
          children: [
            Icon(ok ? Icons.check_circle : Icons.radio_button_unchecked,
                size: 14, color: ok ? const Color(0xFF16A34A) : SelmsColors.textMuted),
            const SizedBox(width: 6),
            Expanded(
              child: Text(text,
                  style: TextStyle(fontSize: 11.5, color: ok ? SelmsColors.textSecondary : SelmsColors.textMuted)),
            ),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final firstName = (widget.fullName ?? '').split(RegExp(r'\s+')).first;
    return Scaffold(
      backgroundColor: SelmsColors.accentBg,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Container(
                padding: const EdgeInsets.fromLTRB(28, 26, 28, 24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 24, offset: const Offset(0, 8)),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(firstName.isEmpty ? 'Create your password' : 'Welcome, $firstName',
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    const Text(
                      'Create your own new password to continue.',
                      style: TextStyle(fontSize: 12.5, color: SelmsColors.textSecondary, height: 1.45),
                    ),
                    const SizedBox(height: 20),
                    const Text('New password',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: SelmsColors.textSecondary)),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _newCtrl,
                      obscureText: _obscure,
                      textInputAction: TextInputAction.next,
                      decoration: _field('8 to 10 characters').copyWith(
                        suffixIcon: IconButton(
                          icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                              size: 19, color: SelmsColors.textMuted),
                          onPressed: () => setState(() => _obscure = !_obscure),
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    _rule(_rightLength, '8 to 10 characters'),
                    _rule(_hasUppercase, 'At least one uppercase letter'),
                    _rule(_hasNumber, 'At least one number'),
                    _rule(_hasSpecial, 'At least one special character'),
                    const SizedBox(height: 14),
                    const Text('Confirm new password',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: SelmsColors.textSecondary)),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _confirmCtrl,
                      obscureText: _obscure,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _saving ? null : _save(),
                      decoration: _field('Type it again'),
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
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _saving ? null : _save,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: SelmsColors.ink,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 15),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          elevation: 0,
                        ),
                        child: _saving
                            ? const SizedBox(
                                height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Text('Save and continue', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Center(
                      child: TextButton(
                        onPressed: _saving
                            ? null
                            : () => Navigator.of(context).pushAndRemoveUntil(
                                  MaterialPageRoute(builder: (_) => SelmsLoginScreen(apiBaseUrl: widget.apiBaseUrl)),
                                  (route) => false,
                                ),
                        child: const Text('Back to sign in',
                            style: TextStyle(fontSize: 12.5, color: SelmsColors.textSecondary)),
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
  }
}
