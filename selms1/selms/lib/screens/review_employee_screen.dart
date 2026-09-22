// lib/screens/review_employee_screen.dart
//
// This is the deliberate checkpoint before the onboarding chain fires
// (welcome email, IT equipment task, auto-scheduled orientation). Nothing
// external happens until "Create user" is pressed here. Laid out to match
// EmployeeViewScreen exactly, so what HR reviews here is what they'll see
// again afterwards.

import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../services/api_client.dart';
import '../theme/selms_colors.dart';
import '../widgets/app_shell.dart';

class ReviewEmployeeScreen extends StatefulWidget {
  const ReviewEmployeeScreen({
    super.key,
    required this.apiBaseUrl,
    required this.hrToken,
    required this.employeeData,
    this.profilePhotoBytes,
  });

  final String apiBaseUrl;
  final String hrToken;
  final Map<String, dynamic> employeeData;
  final Uint8List? profilePhotoBytes;

  @override
  State<ReviewEmployeeScreen> createState() => _ReviewEmployeeScreenState();
}

class _ReviewEmployeeScreenState extends State<ReviewEmployeeScreen> {
  bool _submitting = false;
  String? _error;

  String get _initials {
    final name = (widget.employeeData['full_name'] as String?)?.trim() ?? '';
    final parts = name.split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length == 1) return parts[0].substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1)).toUpperCase();
  }

  Future<void> _confirm() async {
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final api = ApiClient(baseUrl: widget.apiBaseUrl, hrToken: widget.hrToken);
      final id = await api.createEmployee(widget.employeeData);

      // Photo upload is best-effort and separate from account creation —
      // a failed upload here shouldn't undo the employee record that was
      // just created. HR can always add/replace the photo later from Edit.
      if (widget.profilePhotoBytes != null) {
        try {
          await api.uploadEmployeePhoto(id, widget.profilePhotoBytes!);
        } catch (_) {
          // Swallowed on purpose — see comment above.
        }
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Employee created — $id')));
      Navigator.of(context).pop(true);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.employeeData;
    final equipment = (d['equipment_needed'] as List).join(', ');
    final salary = d['base_salary'];

    return AppShell(
      apiBaseUrl: widget.apiBaseUrl,
      hrToken: widget.hrToken,
      activeRoute: SelmsRoute.employees,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Review employee details',
                      style: TextStyle(
                          fontSize: 20, fontWeight: FontWeight.w600, color: SelmsColors.textPrimary)),
                  const TopBarActions(),
                ],
              ),
              const SizedBox(height: 4),
              const Text(
                'Check everything below before creating this account — the same '
                'details will show up on their profile afterwards.',
                style: TextStyle(fontSize: 13, color: SelmsColors.textSecondary),
              ),
              const SizedBox(height: 18),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(24),
                decoration:
                    BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
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
                          child: widget.profilePhotoBytes != null
                              ? Image.memory(widget.profilePhotoBytes!,
                                  fit: BoxFit.cover, width: 56, height: 56)
                              : Text(_initials,
                                  style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                      color: SelmsColors.ink)),
                        ),
                        const SizedBox(width: 14),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('${d['full_name'] ?? ''}',
                                style: const TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.w600,
                                    color: SelmsColors.textPrimary)),
                            Text(
                                '(ID assigned on creation) · ${d['job_title'] ?? ''} · ${d['department'] ?? ''}',
                                style: const TextStyle(fontSize: 12.5, color: SelmsColors.textMuted)),
                          ],
                        ),
                      ],
                    ),
                    const Divider(height: 40, color: SelmsColors.border),
                    _sectionTitle('Personal details'),
                    _grid([
                      _field('Gender', d['gender']),
                      _field('Date of birth', d['date_of_birth']),
                      _field('Nationality', d['nationality']),
                      _field('IC / passport no.', d['ic_passport_no']),
                      _field('Marital status', d['marital_status']),
                      _field('Personal email', d['personal_email']),
                      _field('Mobile number', d['mobile_number']),
                      _field('Emergency contact name', d['emergency_contact_name']),
                      _field('Emergency contact no.', d['emergency_contact_number']),
                      _field('Emergency contact relationship', d['emergency_contact_relationship']),
                    ]),
                    _fullWidthField('Address',
                        '${d['address_line'] ?? ''}, ${d['postcode'] ?? ''} ${d['state'] ?? ''}'),
                    const SizedBox(height: 20),
                    _sectionTitle('Employment details'),
                    _grid([
                      _field('Job title', d['job_title']),
                      _field('Department', d['department']),
                      _field('Line manager', d['line_manager']),
                      _field('Hire date', d['hire_date']),
                      _field('Confirmation date', d['confirmation_date']),
                      _field('Employment status', d['employment_status']),
                      _field('Work location type', d['work_location_type']),
                      _field('Base salary', salary != null ? 'RM $salary' : null),
                      _field('Equipment', equipment),
                    ]),
                    if ((d['remarks'] as String?)?.isNotEmpty == true)
                      _fullWidthField('Remarks', d['remarks']),
                    const SizedBox(height: 20),
                    _sectionTitle('Account details'),
                    _grid([
                      _field('Work email', d['work_email']),
                      _field('Role', 'Employee'),
                    ]),
                    const SizedBox(height: 20),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: SelmsColors.accentBg,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.info_outline, size: 16, color: SelmsColors.ink),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Orientation will be auto-scheduled and a welcome email '
                              'will be sent once this account is created.',
                              style: TextStyle(fontSize: 12, color: SelmsColors.ink, height: 1.4),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 14),
                      Text(_error!, style: const TextStyle(fontSize: 12, color: SelmsColors.rose)),
                    ],
                    const SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        OutlinedButton(
                          onPressed: _submitting ? null : () => Navigator.of(context).pop(),
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: SelmsColors.border),
                            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                          ),
                          child:
                              const Text('Edit', style: TextStyle(color: SelmsColors.textSecondary)),
                        ),
                        const SizedBox(width: 10),
                        ElevatedButton(
                          onPressed: _submitting ? null : _confirm,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: SelmsColors.ink,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                          ),
                          child: _submitting
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                              : const Text('Create user',
                                  style: TextStyle(fontWeight: FontWeight.w500)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
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

  Widget _field(String label, dynamic value) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label.toUpperCase(),
              style: const TextStyle(fontSize: 10.5, color: SelmsColors.textMuted)),
          const SizedBox(height: 3),
          Text(
            (value == null || value.toString().isEmpty) ? '—' : value.toString(),
            style: const TextStyle(fontSize: 13, color: SelmsColors.textSecondary),
          ),
        ],
      );

  Widget _fullWidthField(String label, dynamic value) => Padding(
        padding: const EdgeInsets.only(top: 4, bottom: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label.toUpperCase(),
                style: const TextStyle(fontSize: 10.5, color: SelmsColors.textMuted)),
            const SizedBox(height: 3),
            Text(
              (value == null || value.toString().isEmpty) ? '—' : value.toString(),
              style: const TextStyle(fontSize: 13, color: SelmsColors.textSecondary),
            ),
          ],
        ),
      );
}
