// lib/screens/onboarding_email_review_screen.dart

import 'package:flutter/material.dart';
import '../services/api_client.dart';
import '../theme/selms_colors.dart';
import '../widgets/app_shell.dart';
import 'onboarding_stepper_screen.dart';

class OnboardingEmailReviewScreen extends StatefulWidget {
  const OnboardingEmailReviewScreen({
    super.key,
    required this.apiBaseUrl,
    required this.hrToken,
    required this.employeeId,
    required this.fullName,
  });

  final String apiBaseUrl;
  final String hrToken;
  final String employeeId;
  final String fullName;

  @override
  State<OnboardingEmailReviewScreen> createState() => _OnboardingEmailReviewScreenState();
}

class _OnboardingEmailReviewScreenState extends State<OnboardingEmailReviewScreen> {
  late final ApiClient _api = ApiClient(baseUrl: widget.apiBaseUrl, hrToken: widget.hrToken);
  final _subjectCtrl = TextEditingController();
  final _bodyCtrl = TextEditingController();
  final _instructionCtrl = TextEditingController();

  bool _loadingDraft = true;
  bool _regenerating = false;
  bool _sending = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadDraft();
  }

  @override
  void dispose() {
    _subjectCtrl.dispose();
    _bodyCtrl.dispose();
    _instructionCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadDraft({String instruction = ''}) async {
    setState(() {
      if (instruction.isEmpty) {
        _loadingDraft = true;
      } else {
        _regenerating = true;
      }
      _error = null;
    });
    try {
      final draft = await _api.draftOnboardingEmail(widget.employeeId, instruction: instruction);
      if (!mounted) return;
      setState(() {
        _subjectCtrl.text = draft['subject'] ?? '';
        _bodyCtrl.text = draft['body'] ?? '';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() {
        _loadingDraft = false;
        _regenerating = false;
      });
    }
  }

  void _showRegeneratePrompt() {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        title: const Text('Regenerate with AI', style: TextStyle(fontSize: 15)),
        content: TextField(
          controller: _instructionCtrl,
          decoration: const InputDecoration(
            hintText: 'Optional — e.g. "make it shorter" or "more casual"',
            hintStyle: TextStyle(fontSize: 12.5),
          ),
          style: const TextStyle(fontSize: 13),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              _loadDraft(instruction: _instructionCtrl.text.trim());
            },
            style: ElevatedButton.styleFrom(backgroundColor: SelmsColors.ink, foregroundColor: Colors.white),
            child: const Text('Regenerate'),
          ),
        ],
      ),
    );
  }

  Future<void> _send() async {
    if (_subjectCtrl.text.trim().isEmpty || _bodyCtrl.text.trim().isEmpty) {
      setState(() => _error = 'Subject and message cannot be empty.');
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await _api.sendOnboardingEmail(widget.employeeId, _subjectCtrl.text.trim(), _bodyCtrl.text.trim());
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => OnboardingStepperScreen(
            apiBaseUrl: widget.apiBaseUrl,
            hrToken: widget.hrToken,
            employeeId: widget.employeeId,
            fullName: widget.fullName,
          ),
        ),
      );
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppShell(
      apiBaseUrl: widget.apiBaseUrl,
      hrToken: widget.hrToken,
      activeRoute: SelmsRoute.onboarding,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text('Onboarding', style: TextStyle(fontSize: 12, color: SelmsColors.textMuted)),
                const Icon(Icons.chevron_right, size: 13, color: SelmsColors.textMuted),
                Text(widget.fullName, style: const TextStyle(fontSize: 12, color: SelmsColors.textMuted)),
                const Icon(Icons.chevron_right, size: 13, color: SelmsColors.textMuted),
                const Text('Review email', style: TextStyle(fontSize: 12, color: SelmsColors.textPrimary)),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                const Text('Review welcome email',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: SelmsColors.textPrimary)),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: SelmsColors.accentBg, borderRadius: BorderRadius.circular(10)),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.auto_awesome, size: 11, color: SelmsColors.ink),
                      SizedBox(width: 4),
                      Text('AI-drafted', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: SelmsColors.ink)),
                    ],
                  ),
                ),
              ],
            ),
            const Text('Nothing sends until you click Send below.',
                style: TextStyle(fontSize: 12.5, color: SelmsColors.textSecondary)),
            const SizedBox(height: 16),
            Expanded(
              child: _loadingDraft
                  ? const Center(child: CircularProgressIndicator())
                  : SingleChildScrollView(
                      child: Container(
                        constraints: const BoxConstraints(maxWidth: 560),
                        padding: const EdgeInsets.all(22),
                        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Subject',
                                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: SelmsColors.textSecondary)),
                            const SizedBox(height: 6),
                            TextField(
                              controller: _subjectCtrl,
                              style: const TextStyle(fontSize: 12.5),
                              decoration: InputDecoration(
                                isDense: true,
                                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                filled: true,
                                fillColor: SelmsColors.fieldBg,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: const BorderSide(color: SelmsColors.border),
                                ),
                              ),
                            ),
                            const SizedBox(height: 14),
                            const Text('Message',
                                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: SelmsColors.textSecondary)),
                            const SizedBox(height: 6),
                            Stack(
                              children: [
                                TextField(
                                  controller: _bodyCtrl,
                                  maxLines: 10,
                                  style: const TextStyle(fontSize: 12.5, height: 1.5),
                                  decoration: InputDecoration(
                                    contentPadding: const EdgeInsets.all(12),
                                    filled: true,
                                    fillColor: SelmsColors.fieldBg,
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(8),
                                      borderSide: const BorderSide(color: SelmsColors.border),
                                    ),
                                  ),
                                ),
                                if (_regenerating)
                                  Positioned.fill(
                                    child: Container(
                                      decoration: BoxDecoration(
                                        color: Colors.white.withOpacity(0.7),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
                                    ),
                                  ),
                              ],
                            ),
                            if (_error != null) ...[
                              const SizedBox(height: 12),
                              Text(_error!, style: const TextStyle(fontSize: 12, color: SelmsColors.rose)),
                            ],
                            const SizedBox(height: 18),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                InkWell(
                                  onTap: _regenerating ? null : _showRegeneratePrompt,
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: const [
                                      Icon(Icons.refresh, size: 14, color: SelmsColors.textSecondary),
                                      SizedBox(width: 5),
                                      Text('Regenerate with AI',
                                          style: TextStyle(fontSize: 12, color: SelmsColors.textSecondary)),
                                    ],
                                  ),
                                ),
                                Row(
                                  children: [
                                    OutlinedButton(
                                      onPressed: _sending ? null : () => Navigator.of(context).pop(),
                                      style: OutlinedButton.styleFrom(side: const BorderSide(color: SelmsColors.border)),
                                      child: const Text('Cancel', style: TextStyle(color: SelmsColors.textSecondary)),
                                    ),
                                    const SizedBox(width: 10),
                                    ElevatedButton(
                                      onPressed: _sending ? null : _send,
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: SelmsColors.ink,
                                        foregroundColor: Colors.white,
                                        elevation: 0,
                                      ),
                                      child: _sending
                                          ? const SizedBox(
                                              width: 14, height: 14,
                                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                          : const Text('Send email'),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
