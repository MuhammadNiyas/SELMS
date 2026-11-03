// lib/screens/onboarding_stepper_screen.dart
//
// Click any step to see its detail. Green = done, amber = pending, gray =
// not started. "Email confirmed" flips automatically when the employee
// clicks the link in their inbox (GET /api/onboarding/confirm/<token> on
// the backend — no login required on their end). "IT equipment ready"
// is computed live from real equipment assignment records, not manual.
// "Orientation scheduled" stays manually markable as a fallback for when
// auto-booking (Start onboarding) found no free slot.

import 'package:flutter/material.dart';
import '../services/api_client.dart';
import '../theme/selms_colors.dart';
import '../widgets/app_shell.dart';

class OnboardingStepperScreen extends StatefulWidget {
  const OnboardingStepperScreen({
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
  State<OnboardingStepperScreen> createState() => _OnboardingStepperScreenState();
}

enum _StepState { done, pending, upcoming }

class _OnboardingStepperScreenState extends State<OnboardingStepperScreen> {
  late final ApiClient _api = ApiClient(baseUrl: widget.apiBaseUrl, hrToken: widget.hrToken);
  Map<String, dynamic>? _status;
  bool _loading = true;
  String? _error;
  int? _openIndex;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final s = await _api.onboardingStatus(widget.employeeId);
      if (!mounted) return;
      setState(() {
        _status = s;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _markStep(String step) async {
    try {
      await _api.markOnboardingStep(widget.employeeId, step);
      _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  List<_Step> get _steps {
    final s = _status ?? {};
    return [
      _Step(
        title: 'Registered',
        state: s['started'] == true ? _StepState.done : _StepState.upcoming,
        detail: s['started_at'] != null ? 'Onboarding started on ${s['started_at']}.' : 'Not started yet.',
      ),
      _Step(
        title: 'Welcome email sent',
        state: s['welcome_email_sent'] == true ? _StepState.done : _StepState.upcoming,
        detail: s['welcome_email_sent_at'] != null
            ? 'Sent on ${s['welcome_email_sent_at']}.'
            : 'Not sent yet.',
      ),
      _Step(
        title: 'Email confirmed',
        state: s['email_confirmed'] == true
            ? _StepState.done
            : (s['welcome_email_sent'] == true ? _StepState.pending : _StepState.upcoming),
        detail: s['email_confirmed'] == true
            ? 'Confirmed on ${s['email_confirmed_at']}.'
            : 'Not confirmed yet — waiting for ${widget.fullName} to click the link in the email.',
      ),
      _Step(
        title: 'IT equipment ready',
        state: s['it_equipment_ready'] == true ? _StepState.done : _StepState.pending,
        detail: s['it_equipment_ready'] == true
            ? 'Equipment assigned on ${s['it_equipment_ready_at']}.'
            : 'Waiting for IT to assign the requested equipment.',
      ),
      _Step(
        title: 'Orientation scheduled',
        state: s['orientation_scheduled'] == true ? _StepState.done : _StepState.pending,
        detail: s['orientation_scheduled'] == true
            ? 'Marked scheduled on ${s['orientation_scheduled_at']}.'
            : 'HR has not scheduled a session yet.',
        manualStep: 'orientation_scheduled',
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return AppShell(
      apiBaseUrl: widget.apiBaseUrl,
      hrToken: widget.hrToken,
      activeRoute: SelmsRoute.onboarding,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(child: Text(_error!, style: const TextStyle(color: SelmsColors.rose)))
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Onboarding',
                                  style: TextStyle(
                                      fontSize: 20, fontWeight: FontWeight.w600, color: SelmsColors.textPrimary)),
                              Text('${widget.fullName} — ${widget.employeeId} · click a step for details',
                                  style: const TextStyle(fontSize: 13, color: SelmsColors.textSecondary)),
                            ],
                          ),
                          const TopBarActions(),
                        ],
                      ),
                      const SizedBox(height: 18),
                      Container(
                        constraints: const BoxConstraints(maxWidth: 520),
                        padding: const EdgeInsets.all(22),
                        decoration:
                            BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            for (int i = 0; i < _steps.length; i++) _buildStepRow(i, i == _steps.length - 1),
                          ],
                        ),
                      ),
                    ],
                  ),
      ),
    );
  }

  Widget _buildStepRow(int i, bool isLast) {
    final step = _steps[i];
    final open = _openIndex == i;
    final colors = switch (step.state) {
      _StepState.done => (bg: SelmsColors.statusActiveBg, fg: SelmsColors.statusActiveText, icon: Icons.check),
      _StepState.pending => (bg: SelmsColors.statusOnboardingBg, fg: SelmsColors.statusOnboardingText, icon: Icons.schedule),
      _StepState.upcoming => (bg: const Color(0xFFF3F4F6), fg: SelmsColors.textMuted, icon: Icons.circle_outlined),
    };

    return Stack(
      children: [
        if (!isLast)
          Positioned(
            left: 9,
            top: 30,
            bottom: 0,
            child: Container(width: 2, color: SelmsColors.border),
          ),
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: InkWell(
            onTap: () => setState(() => _openIndex = open ? null : i),
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 20,
                    height: 20,
                    margin: const EdgeInsets.only(top: 1),
                    decoration: BoxDecoration(color: colors.bg, shape: BoxShape.circle),
                    child: Icon(colors.icon, size: 11, color: colors.fg),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(step.title,
                                style: const TextStyle(
                                    fontSize: 12.5, fontWeight: FontWeight.w500, color: SelmsColors.textPrimary)),
                            Icon(open ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                                size: 16, color: SelmsColors.textMuted),
                          ],
                        ),
                        if (open) ...[
                          const SizedBox(height: 6),
                          Text(step.detail,
                              style: const TextStyle(fontSize: 11.5, color: SelmsColors.textSecondary, height: 1.4)),
                          if (step.manualStep != null && step.state != _StepState.done) ...[
                            const SizedBox(height: 8),
                            OutlinedButton(
                              onPressed: () => _markStep(step.manualStep!),
                              style: OutlinedButton.styleFrom(
                                side: const BorderSide(color: SelmsColors.border),
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              ),
                              child: const Text('Mark as done', style: TextStyle(fontSize: 11.5)),
                            ),
                          ],
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _Step {
  _Step({required this.title, required this.state, required this.detail, this.manualStep});
  final String title;
  final _StepState state;
  final String detail;
  final String? manualStep;
}
