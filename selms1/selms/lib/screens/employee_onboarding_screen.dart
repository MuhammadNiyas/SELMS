// lib/screens/employee_onboarding_screen.dart
//
// The employee's onboarding checklist (report fig 3.28). Every item's
// "done" state is derived server-side from real signals (welcome email
// sent, HR-marked orientation/equipment steps, all documents signed, a
// profile photo uploaded) — there's nothing here for the employee to
// tick by hand, since a self-reported checkbox wouldn't mean anything HR
// or IT could rely on. Incomplete items instead explain what finishes them.

import 'package:flutter/material.dart';
import '../models/employee_self_service.dart';
import '../services/api_client.dart';
import '../theme/selms_colors.dart';

class EmployeeOnboardingScreen extends StatefulWidget {
  const EmployeeOnboardingScreen({super.key, required this.api, required this.fullName});

  final ApiClient api;
  final String? fullName;

  @override
  State<EmployeeOnboardingScreen> createState() => _EmployeeOnboardingScreenState();
}

class _EmployeeOnboardingScreenState extends State<EmployeeOnboardingScreen> {
  late Future<EmployeeChecklist> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.api.getMyChecklist();
  }

  Future<void> _refresh() async {
    setState(() => _future = widget.api.getMyChecklist());
    await _future;
  }

  String _hint(String id) => switch (id) {
        'welcome_email' => 'Sent automatically once HR starts your onboarding.',
        'documents_signed' => 'Sign every document on the Documents tab.',
        'orientation' => 'HR will schedule this and it will update here.',
        'it_equipment' => 'Marked automatically once IT assigns your equipment.',
        'profile_setup' => 'Upload a profile photo on the Profile tab.',
        _ => '',
      };

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _refresh,
      child: FutureBuilder<EmployeeChecklist>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Text('Could not load your onboarding checklist.\n${snapshot.error}',
                    style: const TextStyle(color: SelmsColors.rose, fontSize: 13)),
              ],
            );
          }

          final checklist = snapshot.data!;
          final firstName = (widget.fullName ?? '').split(RegExp(r'\s+')).first;

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: SelmsColors.ink,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      firstName.isEmpty ? 'Welcome!' : 'Welcome, $firstName!',
                      style: const TextStyle(
                          color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 4),
                    const Text('Your onboarding progress is below.',
                        style: TextStyle(color: Colors.white70, fontSize: 12.5)),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: SelmsColors.cardWhite,
                  border: Border.all(color: SelmsColors.border),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    const Text('Overall Progress',
                        style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
                    const Spacer(),
                    Text('${checklist.progressPercent}%',
                        style: const TextStyle(
                            fontSize: 12.5, fontWeight: FontWeight.w700, color: SelmsColors.ink)),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: checklist.progressPercent / 100,
                    minHeight: 6,
                    backgroundColor: SelmsColors.border,
                    valueColor: const AlwaysStoppedAnimation(SelmsColors.ink),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              ...checklist.items.map((item) => Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: item.done ? SelmsColors.statusActiveBg.withValues(alpha: 0.4) : SelmsColors.cardWhite,
                      border: Border.all(color: SelmsColors.border),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          item.done ? Icons.check_circle : Icons.radio_button_unchecked,
                          size: 20,
                          color: item.done ? SelmsColors.statusActiveText : SelmsColors.textMuted,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item.label,
                                style: TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w600,
                                  color: SelmsColors.textPrimary,
                                  decoration: item.done ? TextDecoration.lineThrough : null,
                                  decorationColor: SelmsColors.textMuted,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                item.done ? 'Completed' : _hint(item.id),
                                style: const TextStyle(fontSize: 11.5, color: SelmsColors.textMuted),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  )),
            ],
          );
        },
      ),
    );
  }
}
