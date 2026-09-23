// lib/screens/employee_view_screen.dart

import 'package:flutter/material.dart';
import '../models/employee.dart';
import '../models/employee_self_service.dart';
import '../services/api_client.dart';
import '../theme/selms_colors.dart';
import '../widgets/app_shell.dart';
import 'employee_edit_screen.dart';

const _departureTypes = ['Resignation', 'Termination', 'Retirement'];

class EmployeeViewScreen extends StatefulWidget {
  const EmployeeViewScreen({
    super.key,
    required this.apiBaseUrl,
    required this.hrToken,
    required this.employeeId,
  });

  final String apiBaseUrl;
  final String hrToken;
  final String employeeId;

  @override
  State<EmployeeViewScreen> createState() => _EmployeeViewScreenState();
}

class _EmployeeViewScreenState extends State<EmployeeViewScreen> {
  late final ApiClient _api = ApiClient(baseUrl: widget.apiBaseUrl, hrToken: widget.hrToken);
  Employee? _employee;
  OffboardingChecklist? _offboarding;
  bool _loading = true;
  String? _error;
  bool _resending = false;
  bool _initiatingOffboarding = false;
  String? _markingStep;

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
      final e = await _api.getEmployee(widget.employeeId);
      OffboardingChecklist offboarding;
      try {
        offboarding = await _api.getEmployeeOffboarding(widget.employeeId);
      } catch (_) {
        offboarding = OffboardingChecklist(started: false);
      }
      if (!mounted) return;
      setState(() {
        _employee = e;
        _offboarding = offboarding;
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

  Future<void> _initiateOffboarding() async {
    final departureTypeCtrl = ValueNotifier<String>(_departureTypes.first);
    final lastDayCtrl = TextEditingController();
    final notesCtrl = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: Colors.white,
          title: Text('Initiate offboarding — ${_employee!.fullName}', style: const TextStyle(fontSize: 15)),
          content: SizedBox(
            width: 360,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Departure type', style: TextStyle(fontSize: 11.5, color: SelmsColors.textMuted)),
                const SizedBox(height: 4),
                DropdownButtonFormField<String>(
                  initialValue: departureTypeCtrl.value,
                  items: _departureTypes
                      .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                      .toList(),
                  onChanged: (v) => setDialogState(() => departureTypeCtrl.value = v ?? departureTypeCtrl.value),
                  decoration: const InputDecoration(isDense: true, border: OutlineInputBorder()),
                ),
                const SizedBox(height: 14),
                const Text('Last working day', style: TextStyle(fontSize: 11.5, color: SelmsColors.textMuted)),
                const SizedBox(height: 4),
                TextField(
                  controller: lastDayCtrl,
                  readOnly: true,
                  decoration: const InputDecoration(
                    isDense: true,
                    hintText: 'yyyy-mm-dd',
                    border: OutlineInputBorder(),
                    suffixIcon: Icon(Icons.calendar_today_outlined, size: 16),
                  ),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: DateTime.now(),
                      firstDate: DateTime.now().subtract(const Duration(days: 365)),
                      lastDate: DateTime.now().add(const Duration(days: 365)),
                    );
                    if (picked != null) {
                      lastDayCtrl.text =
                          '${picked.year.toString().padLeft(4, '0')}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
                    }
                  },
                ),
                const SizedBox(height: 14),
                const Text('Notes (optional)', style: TextStyle(fontSize: 11.5, color: SelmsColors.textMuted)),
                const SizedBox(height: 4),
                TextField(
                  controller: notesCtrl,
                  maxLines: 2,
                  decoration: const InputDecoration(isDense: true, border: OutlineInputBorder()),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: lastDayCtrl.text.isEmpty ? null : () => Navigator.of(context).pop(true),
              style: ElevatedButton.styleFrom(backgroundColor: SelmsColors.rose, foregroundColor: Colors.white),
              child: const Text('Initiate offboarding'),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true) return;
    if (lastDayCtrl.text.isEmpty) return;

    setState(() => _initiatingOffboarding = true);
    try {
      await _api.initiateOffboarding(
        widget.employeeId,
        departureType: departureTypeCtrl.value,
        lastWorkingDay: lastDayCtrl.text,
        notes: notesCtrl.text.trim().isEmpty ? null : notesCtrl.text.trim(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Offboarding initiated.')));
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => _initiatingOffboarding = false);
    }
  }

  Future<void> _markOffboardingStep(String step) async {
    setState(() => _markingStep = step);
    try {
      await _api.offboardingMarkStep(widget.employeeId, step);
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => _markingStep = null);
    }
  }

  Future<void> _resendWelcomeEmail() async {
    setState(() => _resending = true);
    try {
      final message = await _api.resendWelcomeEmail(widget.employeeId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => _resending = false);
    }
  }

  Future<void> _confirmDelete() async {
    final confirmCtrl = TextEditingController();
    bool matches = false;

    final result = await showDialog<bool>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return Dialog(
              backgroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 380),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration:
                            const BoxDecoration(color: SelmsColors.roseBg, shape: BoxShape.circle),
                        alignment: Alignment.center,
                        child: const Icon(Icons.warning_amber_rounded,
                            color: SelmsColors.rose, size: 20),
                      ),
                      const SizedBox(height: 14),
                      Text('Delete ${_employee!.fullName}?',
                          style: const TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w600, color: SelmsColors.textPrimary)),
                      const SizedBox(height: 6),
                      const Text(
                        'This permanently removes the record — personal details, '
                        'employment history, and login access. This cannot be undone.',
                        style: TextStyle(fontSize: 12.5, color: SelmsColors.textSecondary, height: 1.5),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'If this employee has already started onboarding or has equipment '
                        'assigned, use Initiate offboarding instead — deleting won\'t revoke '
                        'equipment or IT access.',
                        style: TextStyle(fontSize: 12, color: SelmsColors.rose, height: 1.5),
                      ),
                      const SizedBox(height: 16),
                      Text('Type the employee ID to confirm',
                          style: const TextStyle(fontSize: 11.5, color: SelmsColors.textSecondary)),
                      const SizedBox(height: 6),
                      TextField(
                        controller: confirmCtrl,
                        onChanged: (v) =>
                            setDialogState(() => matches = v.trim() == widget.employeeId),
                        decoration: InputDecoration(
                          isDense: true,
                          hintText: widget.employeeId,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: const BorderSide(color: SelmsColors.border),
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () => Navigator.of(context).pop(false),
                              style: OutlinedButton.styleFrom(
                                side: const BorderSide(color: SelmsColors.border),
                                padding: const EdgeInsets.symmetric(vertical: 10),
                              ),
                              child: const Text('Cancel'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: matches ? () => Navigator.of(context).pop(true) : null,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: SelmsColors.rose,
                                foregroundColor: Colors.white,
                                elevation: 0,
                                padding: const EdgeInsets.symmetric(vertical: 10),
                              ),
                              child: const Text('Delete permanently'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );

    if (result == true) {
      try {
        await _api.deleteEmployee(widget.employeeId);
        if (!mounted) return;
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Employee deleted.')));
        Navigator.of(context).pop(true);
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppShell(
      apiBaseUrl: widget.apiBaseUrl,
      hrToken: widget.hrToken,
      activeRoute: SelmsRoute.employees,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
        child: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null || _employee == null) {
      return Center(
        child: Text(_error ?? 'Could not load this employee.',
            style: const TextStyle(color: SelmsColors.rose)),
      );
    }
    final e = _employee!;

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              InkWell(
                onTap: () => Navigator.of(context).pop(),
                child: const Text('Employees',
                    style: TextStyle(fontSize: 12.5, color: SelmsColors.textMuted)),
              ),
              const Icon(Icons.chevron_right, size: 14, color: SelmsColors.textMuted),
              Text(e.fullName,
                  style: const TextStyle(fontSize: 12.5, color: SelmsColors.textPrimary)),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 56,
                          height: 56,
                          clipBehavior: Clip.hardEdge,
                          decoration:
                              const BoxDecoration(color: SelmsColors.accentBg, shape: BoxShape.circle),
                          alignment: Alignment.center,
                          child: (e.profileImageUrl != null && e.profileImageUrl!.isNotEmpty)
                              ? Image.network('${widget.apiBaseUrl}${e.profileImageUrl}',
                                  fit: BoxFit.cover, width: 56, height: 56)
                              : Text(e.initials,
                                  style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                      color: SelmsColors.ink)),
                        ),
                        const SizedBox(width: 14),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(e.fullName,
                                style: const TextStyle(
                                    fontSize: 17, fontWeight: FontWeight.w600, color: SelmsColors.textPrimary)),
                            Text('${e.employeeId} · ${e.jobTitle ?? ''} · ${e.department ?? ''}',
                                style: const TextStyle(fontSize: 12.5, color: SelmsColors.textMuted)),
                          ],
                        ),
                      ],
                    ),
                    SizedBox(
                      width: 170,
                      child: Column(
                        children: [
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: () async {
                                final changed = await Navigator.of(context).push<bool>(
                                  MaterialPageRoute(
                                    builder: (_) => EmployeeEditScreen(
                                      apiBaseUrl: widget.apiBaseUrl,
                                      hrToken: widget.hrToken,
                                      employeeId: widget.employeeId,
                                    ),
                                  ),
                                );
                                if (changed == true) _load();
                              },
                              icon: const Icon(Icons.edit_outlined, size: 14),
                              label: const Text('Edit details', style: TextStyle(fontSize: 12.5)),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: SelmsColors.ink,
                                foregroundColor: Colors.white,
                                elevation: 0,
                                padding: const EdgeInsets.symmetric(vertical: 9),
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: _resending ? null : _resendWelcomeEmail,
                              icon: _resending
                                  ? const SizedBox(
                                      width: 12,
                                      height: 12,
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    )
                                  : const Icon(Icons.mail_outline, size: 14, color: SelmsColors.ink),
                              label: const Text('Resend welcome email',
                                  style: TextStyle(fontSize: 11.5, color: SelmsColors.ink)),
                              style: OutlinedButton.styleFrom(
                                side: const BorderSide(color: SelmsColors.border),
                                padding: const EdgeInsets.symmetric(vertical: 9),
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          if (_offboarding?.started != true)
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton.icon(
                                onPressed: _initiatingOffboarding ? null : _initiateOffboarding,
                                icon: _initiatingOffboarding
                                    ? const SizedBox(
                                        width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2))
                                    : const Icon(Icons.logout, size: 14, color: SelmsColors.rose),
                                label: const Text('Initiate offboarding',
                                    style: TextStyle(fontSize: 11.5, color: SelmsColors.rose)),
                                style: OutlinedButton.styleFrom(
                                  side: const BorderSide(color: SelmsColors.roseBorder),
                                  padding: const EdgeInsets.symmetric(vertical: 9),
                                ),
                              ),
                            ),
                          if (_offboarding?.started != true) const SizedBox(height: 8),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: _confirmDelete,
                              icon: const Icon(Icons.delete_outline, size: 14, color: SelmsColors.rose),
                              label: const Text('Delete',
                                  style: TextStyle(fontSize: 12.5, color: SelmsColors.rose)),
                              style: OutlinedButton.styleFrom(
                                side: const BorderSide(color: SelmsColors.roseBorder),
                                padding: const EdgeInsets.symmetric(vertical: 9),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const Divider(height: 40, color: SelmsColors.border),
                _sectionTitle('Personal details'),
                _grid([
                  _field('Gender', e.gender),
                  _field('Date of birth', e.dateOfBirth),
                  _field('Nationality', e.nationality),
                  _field('IC / passport no.', e.icPassportNo),
                  _field('Marital status', e.maritalStatus),
                  _field('Personal email', e.personalEmail),
                  _field('Mobile number', e.mobileNumber),
                  _field('Emergency contact name', e.emergencyContactName),
                  _field('Emergency contact no.', e.emergencyContactNumber),
                  _field('Emergency contact relationship', e.emergencyContactRelationship),
                ]),
                _fullWidthField(
                    'Address', '${e.addressLine ?? ''}, ${e.postcode ?? ''} ${e.state ?? ''}'),
                const SizedBox(height: 20),
                _sectionTitle('Employment details'),
                _grid([
                  _field('Employee ID', e.employeeId),
                  _field('Job title', e.jobTitle),
                  _field('Department', e.department),
                  _field('Line manager', e.lineManager),
                  _field('Hire date', e.hireDate),
                  _field('Confirmation date', e.confirmationDate),
                  _field('Employment status', e.employmentStatus),
                  _field('Work location type', e.workLocationType),
                  _field('Base salary', e.baseSalary != null ? 'RM ${e.baseSalary}' : null),
                  _field('Equipment', e.equipmentNeeded.join(', ')),
                  _statusField('Onboarding status', e.statusLabel),
                ]),
                if (e.remarks?.isNotEmpty == true) _fullWidthField('Remarks', e.remarks),
                const SizedBox(height: 20),
                _sectionTitle('Account details'),
                _grid([
                  _field('Work email', e.workEmail),
                  _field('Role', 'Employee'),
                ]),
                if (_offboarding?.started == true) ...[
                  const SizedBox(height: 20),
                  _sectionTitle('Offboarding progress'),
                  _offboardingProgress(_offboarding!),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _offboardingProgress(OffboardingChecklist o) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: SelmsColors.roseBg.withValues(alpha: 0.35),
        border: Border.all(color: SelmsColors.roseBorder),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${o.departureType} · Last day: ${o.lastWorkingDay ?? 'TBC'}',
              style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: SelmsColors.rose)),
          const SizedBox(height: 12),
          ...o.items.map((item) {
            final canMark =
                !item.done && (item.id == 'exit_interview' || item.id == 'access_revoked');
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(
                children: [
                  Icon(
                    item.done ? Icons.check_circle : Icons.radio_button_unchecked,
                    size: 16,
                    color: item.done ? SelmsColors.statusActiveText : SelmsColors.textMuted,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(item.label, style: const TextStyle(fontSize: 12.5)),
                  ),
                  if (canMark)
                    TextButton(
                      onPressed: _markingStep == (item.id == 'exit_interview'
                              ? 'exit_interview_scheduled'
                              : 'access_revoked')
                          ? null
                          : () => _markOffboardingStep(
                              item.id == 'exit_interview' ? 'exit_interview_scheduled' : 'access_revoked'),
                      child: Text(
                        _markingStep ==
                                (item.id == 'exit_interview' ? 'exit_interview_scheduled' : 'access_revoked')
                            ? 'Marking…'
                            : 'Mark done',
                        style: const TextStyle(fontSize: 11.5, color: SelmsColors.ink),
                      ),
                    ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _sectionTitle(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Text(text,
            style: const TextStyle(
                fontSize: 13, fontWeight: FontWeight.w600, color: SelmsColors.textPrimary)),
      );

  Widget _grid(List<Widget> fields, {double rowGap = 12, double colGap = 20}) {
    final rows = <Widget>[];
    for (var i = 0; i < fields.length; i += 2) {
      if (i > 0) rows.add(SizedBox(height: rowGap));
      final right = i + 1 < fields.length ? fields[i + 1] : const SizedBox();
      rows.add(Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: fields[i]),
          SizedBox(width: colGap),
          Expanded(child: right),
        ],
      ));
    }
    return Column(children: rows);
  }

  Widget _field(String label, String? value) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label.toUpperCase(),
              style: const TextStyle(fontSize: 10.5, color: SelmsColors.textMuted)),
          const SizedBox(height: 3),
          Text(value?.isNotEmpty == true ? value! : '—',
              style: const TextStyle(fontSize: 13, color: SelmsColors.textSecondary)),
        ],
      );

  Widget _fullWidthField(String label, String? value) => Padding(
        padding: const EdgeInsets.only(top: 4, bottom: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label.toUpperCase(),
                style: const TextStyle(fontSize: 10.5, color: SelmsColors.textMuted)),
            const SizedBox(height: 3),
            Text(value?.isNotEmpty == true ? value! : '—',
                style: const TextStyle(fontSize: 13, color: SelmsColors.textSecondary)),
          ],
        ),
      );

  Widget _statusField(String label, String value) {
    final isActive = value == 'Active';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label.toUpperCase(),
            style: const TextStyle(fontSize: 10.5, color: SelmsColors.textMuted)),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
          decoration: BoxDecoration(
            color: isActive ? SelmsColors.statusActiveBg : SelmsColors.statusOnboardingBg,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(value,
              style: TextStyle(
                  fontSize: 11.5,
                  color: isActive ? SelmsColors.statusActiveText : SelmsColors.statusOnboardingText)),
        ),
      ],
    );
  }
}
