// lib/screens/add_employee_screen.dart
//
// Employee-only creation form. Submitting doesn't create the account
// directly — it opens ReviewEmployeeScreen first, which is the actual
// safety checkpoint before the onboarding chain (welcome email, IT task,
// auto-scheduled orientation) fires.

import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../services/api_client.dart';
import '../theme/selms_colors.dart';
import '../utils/employee_rules.dart';
import '../widgets/app_shell.dart';
import '../widgets/form_fields.dart';
import 'review_employee_screen.dart';

const _genders = ['Male', 'Female'];
const _maritalStatuses = ['Single', 'Married', 'Divorced', 'Widowed'];
const _departments = ['HR', 'IT', 'Marketing', 'Finance', 'Operations'];
const _employmentStatuses = ['Probation', 'Confirmed', 'Contract', 'Full-Time', 'Part-Time'];
const _workLocationTypes = ['Onsite', 'Remote'];

class AddEmployeeScreen extends StatefulWidget {
  const AddEmployeeScreen({super.key, required this.apiBaseUrl, required this.hrToken});

  final String apiBaseUrl;
  final String hrToken;

  @override
  State<AddEmployeeScreen> createState() => _AddEmployeeScreenState();
}

class _AddEmployeeScreenState extends State<AddEmployeeScreen> {
  // Personal
  final _name = TextEditingController();
  String? _gender;
  DateTime? _dob;
  final _nationality = TextEditingController();
  final _icPassport = TextEditingController();
  String? _maritalStatus;
  final _addressLine = TextEditingController();
  final _postcode = TextEditingController();
  String? _state;
  final _personalEmail = TextEditingController();
  final _mobile = TextEditingController();
  final _emergencyName = TextEditingController();
  final _emergencyPhone = TextEditingController();
  String? _emergencyRelationship;

  // Profile photo — the widget hands back already-cropped bytes.
  Uint8List? _profilePhotoBytes;

  // Employment
  final _employeeId = TextEditingController(text: '(auto-generated)');
  final _jobTitle = TextEditingController();
  String? _department;
  final _lineManager = TextEditingController();
  DateTime? _hireDate;
  DateTime? _confirmationDate;
  String? _employmentStatus;
  String? _workLocationType;
  final _baseSalary = TextEditingController();
  final Set<String> _equipment = {};
  // The equipment types IT has actually created - one choice per type.
  List<String> _equipmentOptions = [];
  bool _equipmentOptionsLoaded = false;
  final _remarks = TextEditingController();

  // Account
  final _workEmail = TextEditingController();
  final _tempPassword = TextEditingController();

  String? _error;

  @override
  void initState() {
    super.initState();
    _loadEquipmentOptions();
  }

  Future<void> _loadEquipmentOptions() async {
    try {
      final api = ApiClient(baseUrl: widget.apiBaseUrl, hrToken: widget.hrToken);
      final types = await api.listEquipmentTypes(onlyExisting: true);
      if (!mounted) return;
      setState(() {
        _equipmentOptions = types;
        _equipmentOptionsLoaded = true;
      });
    } catch (_) {
      if (mounted) setState(() => _equipmentOptionsLoaded = true);
    }
  }

  @override
  void dispose() {
    for (final c in [
      _name, _nationality, _icPassport, _addressLine, _postcode, _personalEmail, _mobile,
      _emergencyName, _emergencyPhone, _employeeId, _jobTitle, _lineManager,
      _baseSalary, _remarks, _workEmail, _tempPassword,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  void _generatePassword() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnpqrstuvwxyz23456789!@#';
    final rnd = DateTime.now().millisecondsSinceEpoch;
    var seed = rnd;
    String pick() {
      seed = (seed * 1103515245 + 12345) & 0x7fffffff;
      return chars[seed % chars.length];
    }
    _tempPassword.text = List.generate(10, (_) => pick()).join();
    setState(() {});
  }

  void _onPhotoChanged(Uint8List? bytes) {
    setState(() => _profilePhotoBytes = bytes);
  }

  String get _initials {
    final parts = _name.text.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length == 1) return parts[0].substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1)).toUpperCase();
  }

  String? _validate() {
    final required = <String>[
      _name.text, _nationality.text, _icPassport.text, _addressLine.text, _postcode.text,
      _personalEmail.text, _mobile.text, _emergencyName.text, _emergencyPhone.text,
      _jobTitle.text, _lineManager.text, _baseSalary.text, _workEmail.text, _tempPassword.text,
    ];
    if (required.any((v) => v.trim().isEmpty)) {
      return 'Please fill in every field before continuing.';
    }
    if (_gender == null || _dob == null || _maritalStatus == null || _state == null) {
      return 'Please fill in every field before continuing.';
    }
    if (_emergencyRelationship == null) {
      return 'Please fill in every field before continuing.';
    }
    if (_department == null || _hireDate == null) {
      return 'Please fill in every field before continuing.';
    }
    if (_employmentStatus == null || _workLocationType == null) {
      return 'Please fill in every field before continuing.';
    }
    if (_equipmentOptions.isNotEmpty && _equipment.isEmpty) {
      return 'Please fill in every field before continuing.';
    }
    return employeeDetailsProblem(
      fullName: _name.text,
      dateOfBirth: _dob,
      nationality: _nationality.text,
      icPassport: _icPassport.text,
      personalEmail: _personalEmail.text,
      workEmail: _workEmail.text,
      mobile: _mobile.text,
      emergencyPhone: _emergencyPhone.text,
      postcode: _postcode.text,
      address: _addressLine.text,
      jobTitle: _jobTitle.text,
      lineManager: _lineManager.text,
      emergencyName: _emergencyName.text,
      remarks: _remarks.text,
      baseSalary: num.tryParse(_baseSalary.text.replaceAll(',', '').trim()),
    );
  }

  void _goToReview() {
    final validationError = _validate();
    if (validationError != null) {
      setState(() => _error = validationError);
      return;
    }
    setState(() => _error = null);

    final body = <String, dynamic>{
      'full_name': _name.text.trim(),
      'gender': _gender,
      'date_of_birth': _dob?.toIso8601String(),
      'nationality': _nationality.text.trim(),
      'ic_passport_no': _icPassport.text.trim(),
      'marital_status': _maritalStatus,
      'address_line': _addressLine.text.trim(),
      'postcode': _postcode.text.trim(),
      'state': _state,
      'personal_email': _personalEmail.text.trim(),
      'mobile_number': _mobile.text.trim(),
      'emergency_contact_name': _emergencyName.text.trim(),
      'emergency_contact_number': _emergencyPhone.text.trim(),
      'emergency_contact_relationship': _emergencyRelationship,
      'job_title': _jobTitle.text.trim(),
      'department': _department,
      'line_manager': _lineManager.text.trim(),
      'hire_date': _hireDate?.toIso8601String(),
      'confirmation_date': _confirmationDate?.toIso8601String(),
      'employment_status': _employmentStatus,
      'work_location_type': _workLocationType,
      // Safe to parse directly now — _validate() already rejected anything
      // that isn't a plain number before we got here.
      'base_salary': num.parse(_baseSalary.text.replaceAll(',', '').trim()),
      'equipment_needed': _equipment.toList(),
      'remarks': _remarks.text.trim(),
      'work_email': _workEmail.text.trim(),
      'temp_password': _tempPassword.text,
    };

    Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ReviewEmployeeScreen(
          apiBaseUrl: widget.apiBaseUrl,
          hrToken: widget.hrToken,
          employeeData: body,
          profilePhotoBytes: _profilePhotoBytes,
        ),
      ),
    ).then((created) {
      if (created == true && mounted) Navigator.of(context).pop(true);
    });
  }

  @override
  Widget build(BuildContext context) {
    return AppShell(
      apiBaseUrl: widget.apiBaseUrl,
      hrToken: widget.hrToken,
      activeRoute: SelmsRoute.employees,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Text('Add new employee',
                        style: TextStyle(
                            fontSize: 20, fontWeight: FontWeight.w600, color: SelmsColors.textPrimary)),
                    Text('Fill in every field, then review before creating the account.',
                        style: TextStyle(fontSize: 13, color: SelmsColors.textSecondary)),
                  ],
                ),
                const TopBarActions(),
              ],
            ),
            const SizedBox(height: 18),
            Expanded(
              child: SingleChildScrollView(
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(28),
                  decoration:
                      BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SectionHeader(
                          title: 'Personal details', subtitle: 'Identity and contact information.'),
                      ProfilePhotoField(
                        imageBytes: _profilePhotoBytes,
                        fallbackInitials: _initials,
                        onChanged: _onPhotoChanged,
                      ),
                      const SizedBox(height: 20),
                      _fieldGrid([
                        LabeledField(label: 'Name', controller: _name, hint: 'e.g. Ahmad Rizwan'),
                        LabeledDropdown(
                            label: 'Gender',
                            value: _gender,
                            options: _genders,
                            onChanged: (v) => setState(() => _gender = v)),
                        LabeledDateField(
                            label: 'Date of birth',
                            value: _dob,
                            onPick: (d) => setState(() => _dob = d)),
                        LabeledField(
                            label: 'Nationality', controller: _nationality, hint: 'e.g. Malaysian'),
                        LabeledField(label: 'IC / passport no.', controller: _icPassport),
                        LabeledDropdown(
                            label: 'Marital status',
                            value: _maritalStatus,
                            options: _maritalStatuses,
                            onChanged: (v) => setState(() => _maritalStatus = v)),
                      ]),
                      const SizedBox(height: 14),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                              child:
                                  LabeledField(label: 'Personal email', controller: _personalEmail)),
                          const SizedBox(width: 16),
                          Expanded(
                              child: LabeledField(label: 'Mobile number', controller: _mobile)),
                        ],
                      ),
                      const SizedBox(height: 14),
                      LabeledField(label: 'Address', controller: _addressLine),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(child: LabeledField(label: 'Postcode', controller: _postcode)),
                          const SizedBox(width: 16),
                          Expanded(
                            child: LabeledDropdown(
                                label: 'State',
                                value: _state,
                                options: malaysianStates,
                                onChanged: (v) => setState(() => _state = v)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                              child: LabeledField(
                                  label: 'Emergency contact name', controller: _emergencyName)),
                          const SizedBox(width: 16),
                          Expanded(
                            child: LabeledDropdown(
                                label: 'Emergency contact relationship',
                                value: _emergencyRelationship,
                                options: const [
                                  'Spouse',
                                  'Parent',
                                  'Sibling',
                                  'Child',
                                  'Friend',
                                  'Other'
                                ],
                                onChanged: (v) => setState(() => _emergencyRelationship = v)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(
                              child: LabeledField(
                                  label: 'Emergency contact no.', controller: _emergencyPhone)),
                          const SizedBox(width: 16),
                          const Expanded(child: SizedBox()),
                        ],
                      ),
                      const Divider(height: 40, color: SelmsColors.border),
                      const SectionHeader(
                          title: 'Employment details',
                          subtitle: 'Role, pay, and equipment for this employee.'),
                      _fieldGrid([
                        LabeledField(label: 'Employee ID', controller: _employeeId),
                        LabeledField(label: 'Job title', controller: _jobTitle),
                        LabeledDropdown(
                            label: 'Department',
                            value: _department,
                            options: _departments,
                            onChanged: (v) => setState(() => _department = v)),
                        LabeledField(label: 'Line manager', controller: _lineManager),
                        LabeledDateField(
                            label: 'Hire date',
                            value: _hireDate,
                            onPick: (d) => setState(() => _hireDate = d)),
                        LabeledDateField(
                            label: 'Confirmation date',
                            value: _confirmationDate,
                            optional: true,
                            onPick: (d) => setState(() => _confirmationDate = d)),
                        LabeledDropdown(
                            label: 'Employment status',
                            value: _employmentStatus,
                            options: _employmentStatuses,
                            onChanged: (v) => setState(() => _employmentStatus = v)),
                        LabeledDropdown(
                            label: 'Work location type',
                            value: _workLocationType,
                            options: _workLocationTypes,
                            onChanged: (v) => setState(() => _workLocationType = v)),
                        LabeledCurrencyField(label: 'Base salary', controller: _baseSalary),
                      ]),
                      const SizedBox(height: 14),
                      _equipmentPicker(),
                      const SizedBox(height: 14),
                      LabeledField(
                          label: 'Remarks', controller: _remarks, maxLines: 3, optional: true),
                      const Divider(height: 40, color: SelmsColors.border),
                      const SectionHeader(
                          title: 'Account details', subtitle: 'Login credentials for this employee.'),
                      _fieldGrid([
                        LabeledField(label: 'Work email', controller: _workEmail),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Temporary password',
                                style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                    color: SelmsColors.textSecondary)),
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: _tempPassword,
                                    style: const TextStyle(fontSize: 12.5),
                                    decoration: selmsFieldDecoration(),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                OutlinedButton(
                                  onPressed: _generatePassword,
                                  style: OutlinedButton.styleFrom(
                                    side: const BorderSide(color: SelmsColors.ink),
                                    foregroundColor: SelmsColors.ink,
                                  ),
                                  child: const Text('Generate', style: TextStyle(fontSize: 12)),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ]),
                      if (_error != null) ...[
                        const SizedBox(height: 16),
                        Container(
                          width: double.infinity,
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
                      const SizedBox(height: 24),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          OutlinedButton(
                            onPressed: () => Navigator.of(context).pop(),
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: SelmsColors.border),
                              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                            ),
                            child: const Text('Cancel', style: TextStyle(color: SelmsColors.textSecondary)),
                          ),
                          const SizedBox(width: 10),
                          ElevatedButton(
                            onPressed: _goToReview,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: SelmsColors.ink,
                              foregroundColor: Colors.white,
                              elevation: 0,
                              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                            ),
                            child: const Text('Review and create',
                                style: TextStyle(fontWeight: FontWeight.w500)),
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

  Widget _equipmentPicker() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Equipment needed',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: SelmsColors.textSecondary)),
        const SizedBox(height: 8),
        if (_equipmentOptionsLoaded && _equipmentOptions.isEmpty)
          const Text('No equipment has been added by IT yet, so there is nothing to choose.',
              style: TextStyle(fontSize: 12, color: SelmsColors.textMuted)),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _equipmentOptions.map((item) {
            final selected = _equipment.contains(item);
            return FilterChip(
              label: Text(item, style: const TextStyle(fontSize: 12)),
              selected: selected,
              onSelected: (v) => setState(() => v ? _equipment.add(item) : _equipment.remove(item)),
              selectedColor: SelmsColors.accentBg,
              checkmarkColor: SelmsColors.ink,
              backgroundColor: Colors.white,
              side: BorderSide(color: selected ? SelmsColors.ink : SelmsColors.border),
            );
          }).toList(),
        ),
      ],
    );
  }

  /// Two-column layout that sizes each row to its content — unlike
  /// GridView.count with a fixed childAspectRatio, this can't leave dead
  /// space in a cell when the form is rendered wider than expected.
  Widget _fieldGrid(List<Widget> fields, {double rowGap = 14, double colGap = 16}) {
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
}
