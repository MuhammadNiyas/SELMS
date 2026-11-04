// lib/screens/employee_forgot_password_screen.dart
//
// Forgot password for employees: email -> 6-digit code sent by email -> new
// password. The code and the 3-try limit are checked on the backend.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/api_client.dart';
import '../theme/selms_colors.dart';

class EmployeeForgotPasswordScreen extends StatefulWidget {
  const EmployeeForgotPasswordScreen({super.key, required this.apiBaseUrl, this.initialEmail = ''});

  final String apiBaseUrl;
  final String initialEmail;

  @override
  State<EmployeeForgotPasswordScreen> createState() => _EmployeeForgotPasswordScreenState();
}

enum _Step { email, code, password }

class _EmployeeForgotPasswordScreenState extends State<EmployeeForgotPasswordScreen> {
  late final ApiClient _api = ApiClient(baseUrl: widget.apiBaseUrl, hrToken: '');
  late final _emailCtrl = TextEditingController(text: widget.initialEmail);
  final _codeCtrl = TextEditingController();
  final _newCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();

  _Step _step = _Step.email;
  String _resetToken = '';
  String? _notice;
  String? _error;
  bool _busy = false;
  bool _obscure = true;

  @override
  void initState() {
    super.initState();
    _newCtrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _codeCtrl.dispose();
    _newCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  bool get _rightLength => _newCtrl.text.length >= 8 && _newCtrl.text.length <= 10;
  bool get _hasUppercase => RegExp(r'[A-Z]').hasMatch(_newCtrl.text);
  bool get _hasNumber => RegExp(r'\d').hasMatch(_newCtrl.text);
  bool get _hasSpecial => RegExp(r'[^A-Za-z0-9\s]').hasMatch(_newCtrl.text);

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _sendCode() async {
    final email = _emailCtrl.text.trim();
    if (email.isEmpty) {
      setState(() => _error = 'Enter your email.');
      return;
    }
    await _run(() async {
      final message = await _api.requestPasswordResetCode(email);
      if (!mounted) return;
      setState(() {
        _codeCtrl.clear();
        _notice = message;
        _step = _Step.code;
      });
    });
  }

  Future<void> _verifyCode() async {
    if (_codeCtrl.text.trim().length != 6) {
      setState(() => _error = 'Enter the 6-digit code.');
      return;
    }
    await _run(() async {
      final token = await _api.verifyPasswordResetCode(_emailCtrl.text.trim(), _codeCtrl.text.trim());
      if (!mounted) return;
      setState(() {
        _resetToken = token;
        _notice = null;
        _step = _Step.password;
      });
    });
  }

  Future<void> _savePassword() async {
    if (!_rightLength || !_hasUppercase || !_hasNumber || !_hasSpecial) {
      setState(() => _error =
          'Your password needs 8 to 10 characters, with an uppercase letter, a number and a special character.');
      return;
    }
    if (_newCtrl.text != _confirmCtrl.text) {
      setState(() => _error = "The two passwords don't match.");
      return;
    }
    await _run(() async {
      await _api.resetPasswordWithCode(_emailCtrl.text.trim(), _resetToken, _newCtrl.text);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Password changed. Sign in with your new password.')));
      Navigator.of(context).pop();
    });
  }

  InputDecoration _field(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: SelmsColors.textMuted, fontSize: 13.5),
        filled: true,
        fillColor: Colors.white,
        counterText: '',
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: SelmsColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: SelmsColors.border),
        ),
      );

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(text,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: SelmsColors.textSecondary)),
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

  Widget _primary(String label, VoidCallback onPressed) => SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: _busy ? null : onPressed,
          style: ElevatedButton.styleFrom(
            backgroundColor: SelmsColors.ink,
            foregroundColor: Colors.white,
            elevation: 0,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          child: Text(_busy ? 'Please wait…' : label),
        ),
      );

  List<Widget> _emailStep() => [
        _label('Email'),
        TextField(
          controller: _emailCtrl,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _busy ? null : _sendCode(),
          decoration: _field('you@company.my'),
        ),
        const SizedBox(height: 18),
        _primary('Send code', _sendCode),
      ];

  List<Widget> _codeStep() => [
        _label('6-digit code'),
        TextField(
          controller: _codeCtrl,
          keyboardType: TextInputType.number,
          textInputAction: TextInputAction.done,
          maxLength: 6,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          onSubmitted: (_) => _busy ? null : _verifyCode(),
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600, letterSpacing: 4),
          decoration: _field('000000'),
        ),
        const SizedBox(height: 18),
        _primary('Continue', _verifyCode),
        const SizedBox(height: 6),
        Center(
          child: TextButton(
            onPressed: _busy ? null : _sendCode,
            child: const Text('Send a new code', style: TextStyle(fontSize: 12.5, color: SelmsColors.ink)),
          ),
        ),
      ];

  List<Widget> _passwordStep() => [
        _label('New password'),
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
        _label('Confirm new password'),
        TextField(
          controller: _confirmCtrl,
          obscureText: _obscure,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _busy ? null : _savePassword(),
          decoration: _field('Type it again'),
        ),
        const SizedBox(height: 18),
        _primary('Save new password', _savePassword),
      ];

  @override
  Widget build(BuildContext context) {
    final title = switch (_step) {
      _Step.email => 'Forgot password',
      _Step.code => 'Enter the code',
      _Step.password => 'Create a new password',
    };
    return Scaffold(
      backgroundColor: SelmsColors.accentBg,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Container(
                padding: const EdgeInsets.fromLTRB(28, 26, 28, 18),
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
                    Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 16),
                    if (_notice != null) ...[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                        decoration: BoxDecoration(
                          color: SelmsColors.accentBg,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(_notice!, style: const TextStyle(fontSize: 12, color: SelmsColors.ink)),
                      ),
                      const SizedBox(height: 14),
                    ],
                    ...switch (_step) {
                      _Step.email => _emailStep(),
                      _Step.code => _codeStep(),
                      _Step.password => _passwordStep(),
                    },
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
                    const SizedBox(height: 6),
                    Center(
                      child: TextButton(
                        onPressed: _busy ? null : () => Navigator.of(context).pop(),
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
