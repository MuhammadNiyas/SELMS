// lib/screens/employee_offboarding_screen.dart
//
// Only ever shown once HR has initiated offboarding for this employee
// (the shell decides whether this tab exists at all — see
// employee_home_screen.dart). Same read-only, system-derived pattern as
// the onboarding checklist: nothing here is a self-reported checkbox.

import 'package:flutter/material.dart';
import '../models/employee_self_service.dart';
import '../services/api_client.dart';
import '../theme/selms_colors.dart';

class EmployeeOffboardingScreen extends StatefulWidget {
  const EmployeeOffboardingScreen({super.key, required this.api});

  final ApiClient api;

  @override
  State<EmployeeOffboardingScreen> createState() => _EmployeeOffboardingScreenState();
}

class _EmployeeOffboardingScreenState extends State<EmployeeOffboardingScreen> {
  late Future<OffboardingChecklist> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.api.getMyOffboarding();
  }

  Future<void> _refresh() async {
    setState(() => _future = widget.api.getMyOffboarding());
    await _future;
  }

  String _hint(String id) => switch (id) {
        'departure_recorded' => 'Recorded by HR.',
        'exit_interview' => 'HR will schedule this and it will update here.',
        'equipment_returned' => 'Return all assigned equipment to IT.',
        'access_revoked' => 'IT will revoke your system access on your last day.',
        _ => '',
      };

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _refresh,
      child: FutureBuilder<OffboardingChecklist>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Text('Could not load your offboarding status.\n${snapshot.error}',
                    style: const TextStyle(color: SelmsColors.rose, fontSize: 13)),
              ],
            );
          }

          final o = snapshot.data!;
          if (!o.started) {
            return const Center(
              child: Text('Offboarding has not been started.',
                  style: TextStyle(fontSize: 13, color: SelmsColors.textMuted)),
            );
          }

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: SelmsColors.roseBg,
                  border: Border.all(color: SelmsColors.roseBorder),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(o.departureType ?? 'Departure',
                        style: const TextStyle(
                            color: SelmsColors.rose, fontSize: 16, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Text(
                      o.lastWorkingDay == null
                          ? 'Last working day not yet confirmed.'
                          : 'Last working day: ${o.lastWorkingDay}',
                      style: const TextStyle(color: SelmsColors.rose, fontSize: 12.5),
                    ),
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
                    Text('${o.progressPercent}%',
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
                    value: o.progressPercent / 100,
                    minHeight: 6,
                    backgroundColor: SelmsColors.border,
                    valueColor: const AlwaysStoppedAnimation(SelmsColors.rose),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              ...o.items.map((item) => Container(
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
                              Text(item.label,
                                  style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
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
