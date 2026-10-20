// lib/screens/employee_edit_screen.dart

import 'dart:typed_data';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/employee.dart';
import '../services/api_client.dart';
import '../theme/selms_colors.dart';
import '../widgets/app_shell.dart';
import '../widgets/form_fields.dart';

const _genders = ['Male', 'Female'];
const _maritalStatuses = ['Single', 'Married', 'Divorced', 'Widowed'];
const _departments = ['HR', 'IT', 'Marketing', 'Finance', 'Operations'];
const _employmentStatuses = ['Probation', 'Confirmed', 'Contract', 'Full-Time', 'Part-Time'];
const _workLocationTypes = ['Onsite', 'Remote'];

class EmployeeEditScreen extends StatefulWidget {
  const EmployeeEditScreen({
    super.key,
    required this.apiBaseUrl,
    required this.hrToken,
    required this.employeeId,
  });

  final String apiBaseUrl;
  final String hrToken;
  final String employeeId;

  @override
  State<EmployeeEditScreen> createState() => _EmployeeEditScreenState();
}

class _EmployeeEditScreenState extends State<EmployeeEditScreen> {
  late final ApiClient _api = ApiClient(baseUrl: widget.apiBaseUrl, hrToken: widget.hrToken);

  bool _loading = true;
  String? _loadError;
  String? _saveError;
  bool _saving = false;

  final _name = TextEditingController();
  String? _gender;
  DateTime? _dob;
  final _nationality = TextEditingController();
  final _icPassport = TextEditingController();
  String? _maritalStatus;
  final _personalEmail = TextEditingController();
  final _mobile = TextEditingController();
  final _addressLine = TextEditingController();
  final _postcode = TextEditingController();
  String? _state;
  final _emergencyName = TextEditingController();
  final _emergencyPhone = TextEditingController();
  String? _emergencyRelationship;

  // Profile photo — null bytes with a non-null URL means "unchanged, keep
  // the one already on the server"; null bytes + null URL means no photo.
  Uint8List? _profilePhotoBytes;
  String? _existingProfileImageUrl;

  final _jobTitle = TextEditingController();
  String? _department;
  final _lineManager = TextEditingController();
  DateTime? _hireDate;
  String? _employmentStatus;
  String? _workLocationType;
  final _baseSalary = TextEditingController();
  List<String> _equipment = [];
  List<String> _equipmentOptions = []; // types IT has created equipment for

  final _workEmail = TextEditingController();
  final _passwordCtrl = TextEditingController();
  String? _passwordState; // 'temporary' | 'own' | 'unknown'
  String _originalPassword = ''; // what the field showed on load

  String get _initials {
    final parts = _name.text.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length == 1) return parts[0].substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1)).toUpperCase();
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in [
      _name, _nationality, _icPassport, _personalEmail, _mobile, _addressLine, _postcode,
      _emergencyName, _emergencyPhone, _jobTitle, _lineManager, _baseSalary, _workEmail,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final e = await _api.getEmployee(widget.employeeId);
      try {
        _equipmentOptions = await _api.listEquipmentTypes(onlyExisting: true);
      } catch (_) {}
      _name.text = e.fullName;
      _gender = e.gender;
      _dob = e.dateOfBirth != null ? DateTime.tryParse(e.dateOfBirth!) : null;
      _nationality.text = e.nationality ?? '';
      _icPassport.text = e.icPassportNo ?? '';
      _maritalStatus = e.maritalStatus;
      _personalEmail.text = e.personalEmail ?? '';
      _mobile.text = e.mobileNumber ?? '';
      _addressLine.text = e.addressLine ?? '';
      _postcode.text = e.postcode ?? '';
      _state = e.state;
      _emergencyName.text = e.emergencyContactName ?? '';
      _emergencyPhone.text = e.emergencyContactNumber ?? '';
      _emergencyRelationship = e.emergencyContactRelationship;
      _existingProfileImageUrl = e.profileImageUrl;
      _jobTitle.text = e.jobTitle ?? '';
      _department = e.department;
      _lineManager.text = e.lineManager ?? '';
      _hireDate = e.hireDate != null ? DateTime.tryParse(e.hireDate!) : null;
      _employmentStatus = e.employmentStatus;
      _workLocationType = e.workLocationType;
      _baseSalary.text = e.baseSalary != null ? formatThousands(e.baseSalary!.toStringAsFixed(0)) : '';
      _equipment = List.of(e.equipmentNeeded);
      _passwordState = e.passwordState;
      _originalPassword = e.temporaryPassword ?? '';
      _passwordCtrl.text = _originalPassword;
      _workEmail.text = e.workEmail ?? '';
      if (mounted) setState(() => _loading = false);
    } catch (err) {
      if (mounted) {
        setState(() {
          _loadError = err.toString();
          _loading = false;
        });
      }
    }
  }

  /// 12 characters, no look-alikes (0/O, 1/l/I), with a symbol and a digit.
  String _randomPassword() {
    const upper = 'ABCDEFGHJKLMNPQRSTUVWXYZ', lower = 'abcdefghijkmnpqrstuvwxyz';
    const digits = '23456789', symbols = '!@#\$%&*?';
    final rnd = math.Random.secure();
    String pick(String set) => set[rnd.nextInt(set.length)];
    final chars = [pick(upper), pick(lower), pick(digits), pick(symbols)];
    final all = upper + lower + digits + symbols;
    while (chars.length < 12) {
      chars.add(pick(all));
    }
    chars.shuffle(rnd);
    return chars.join();
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _saveError = null;
    });
    try {
      final temporaryPassword = await _api.updateEmployee(widget.employeeId, {
        'full_name': _name.text.trim(),
        'gender': _gender,
        'date_of_birth': _dob?.toIso8601String(),
        'nationality': _nationality.text.trim(),
        'ic_passport_no': _icPassport.text.trim(),
        'marital_status': _maritalStatus,
        'personal_email': _personalEmail.text.trim(),
        'mobile_number': _mobile.text.trim(),
        'address_line': _addressLine.text.trim(),
        'postcode': _postcode.text.trim(),
        'state': _state,
        'emergency_contact_name': _emergencyName.text.trim(),
        'emergency_contact_number': _emergencyPhone.text.trim(),
        'emergency_contact_relationship': _emergencyRelationship,
        'job_title': _jobTitle.text.trim(),
        'department': _department,
        'line_manager': _lineManager.text.trim(),
        'hire_date': _hireDate?.toIso8601String(),
        'employment_status': _employmentStatus,
        'work_location_type': _workLocationType,
        'base_salary': num.tryParse(_baseSalary.text.replaceAll(',', '').trim()) ??
            _baseSalary.text.trim(),
        'equipment_needed': _equipment,
        'work_email': _workEmail.text.trim(),
        if (_passwordCtrl.text.trim().isNotEmpty && _passwordCtrl.text.trim() != _originalPassword)
          'new_password': _passwordCtrl.text.trim(),
      });

      // Photo upload is separate (multipart) and best-effort — a failed
      // upload here shouldn't block the rest of the changes from saving.
      String? photoError;
      if (_profilePhotoBytes != null) {
        try {
          await _api.uploadEmployeePhoto(widget.employeeId, _profilePhotoBytes!);
        } catch (e) {
          // Still doesn't block the other changes, but say so instead of
          // silently reporting "Changes saved" with the old photo.
          photoError = e.toString();
        }
      }

      if (!mounted) return;
      // A reset produces a new temporary password - show it once so HR can
      // pass it on (it also goes in the welcome email when onboarding starts).
      if (temporaryPassword != null) {
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: Colors.white,
            title: const Text('Password updated', style: TextStyle(fontSize: 15)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Temporary password:', style: TextStyle(fontSize: 12.5, color: SelmsColors.textSecondary)),
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: SelmsColors.accentBg,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: SelectableText(temporaryPassword,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, fontFamily: 'monospace')),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Give this to the employee. If their onboarding has started, they must create their own '
                  'password the next time they sign in. It is also included if the welcome email is resent.',
                  style: TextStyle(fontSize: 12, color: SelmsColors.textMuted, height: 1.4),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: temporaryPassword));
                  if (ctx.mounted) Navigator.of(ctx).pop();
                },
                child: const Text('Copy & close'),
              ),
            ],
          ),
        );
        if (!mounted) return;
      }
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(photoError == null
            ? 'Changes saved.'
            : 'Changes saved, but the photo could not be uploaded: $photoError'),
      ));
      Navigator.of(context).pop(true);
    } catch (e) {
      setState(() => _saveError = e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Called by the photo field: new bytes = a freshly picked photo; null =
  /// the Remove button. Removing a photo that's already saved deletes it on
  /// the server straight away (after confirming) so it's gone everywhere.
  Future<void> _onPhotoChanged(Uint8List? bytes) async {
    if (bytes != null) {
      setState(() => _profilePhotoBytes = bytes);
      return;
    }
    // Discarding a photo that was picked but not saved yet.
    if (_profilePhotoBytes != null) {
      setState(() => _profilePhotoBytes = null);
      return;
    }
    if (_existingProfileImageUrl == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove profile photo?', style: TextStyle(fontSize: 16)),
        content: const Text(
            'The photo is deleted and will disappear everywhere in SELMS. Their initials are shown instead.',
            style: TextStyle(fontSize: 13)),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Keep')),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: SelmsColors.rose, foregroundColor: Colors.white),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await _api.removeEmployeePhoto(widget.employeeId);
      if (!mounted) return;
      setState(() => _existingProfileImageUrl = null);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Photo removed.')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.toString()), backgroundColor: SelmsColors.rose));
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
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _loadError != null
                ? Center(child: Text(_loadError!, style: const TextStyle(color: SelmsColors.rose)))
                : _buildForm(),
      ),
    );
  }

  Widget _buildForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text('Employees', style: TextStyle(fontSize: 12, color: SelmsColors.textMuted)),
            const Icon(Icons.chevron_right, size: 13, color: SelmsColors.textMuted),
            Text(_name.text, style: const TextStyle(fontSize: 12, color: SelmsColors.textMuted)),
            const Icon(Icons.chevron_right, size: 13, color: SelmsColors.textMuted),
            const Text('Edit', style: TextStyle(fontSize: 12, color: SelmsColors.textPrimary)),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Edit employee',
                    style: TextStyle(
                        fontSize: 20, fontWeight: FontWeight.w600, color: SelmsColors.textPrimary)),
                Text('Updating ${_name.text} — ${widget.employeeId}',
                    style: const TextStyle(fontSize: 13, color: SelmsColors.textSecondary)),
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
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SectionHeader(
                      title: 'Personal details', subtitle: 'Identity and contact information.'),
                  ProfilePhotoField(
                    imageBytes: _profilePhotoBytes,
                    existingImageUrl: _existingProfileImageUrl != null
                        ? '${widget.apiBaseUrl}$_existingProfileImageUrl'
                        : null,
                    fallbackInitials: _initials,
                    onChanged: _onPhotoChanged,
                  ),
                  const SizedBox(height: 20),
                  _grid([
                    LabeledField(label: 'Name', controller: _name),
                    LabeledDropdown(
                        label: 'Gender',
                        value: _gender,
                        options: _genders,
                        onChanged: (v) => setState(() => _gender = v)),
                    LabeledDateField(
                        label: 'Date of birth', value: _dob, onPick: (d) => setState(() => _dob = d)),
                    LabeledField(label: 'Nationality', controller: _nationality),
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
                          child: LabeledField(label: 'Personal email', controller: _personalEmail)),
                      const SizedBox(width: 16),
                      Expanded(child: LabeledField(label: 'Mobile number', controller: _mobile)),
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
                            options: const ['Spouse', 'Parent', 'Sibling', 'Child', 'Friend', 'Other'],
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
                  _grid([
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
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Equipment assigned',
                          style: TextStyle(
                              fontSize: 12, fontWeight: FontWeight.w500, color: SelmsColors.textSecondary)),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          ..._equipment.map((item) => Chip(
                                label: Text(item, style: const TextStyle(fontSize: 12, color: Colors.white)),
                                backgroundColor: SelmsColors.ink,
                                deleteIcon: const Icon(Icons.close, size: 14, color: Colors.white70),
                                onDeleted: () => setState(() => _equipment.remove(item)),
                              )),
                          for (final item in _equipmentOptions)
                            if (!_equipment.contains(item))
                              ActionChip(
                                label: Text('+ $item', style: const TextStyle(fontSize: 12)),
                                backgroundColor: Colors.white,
                                side: const BorderSide(color: SelmsColors.border),
                                onPressed: () => setState(() => _equipment.add(item)),
                              ),
                        ],
                      ),
                    ],
                  ),
                  const Divider(height: 40, color: SelmsColors.border),
                  const SectionHeader(
                      title: 'Account details', subtitle: 'Login credentials for this employee.'),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: LabeledField(label: 'Work email', controller: _workEmail)),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            LabeledField(
                              label: 'Password',
                              controller: _passwordCtrl,
                              hint: 'Type a new password',
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    switch (_passwordState) {
                                      'temporary' => 'Temporary password, included in the welcome email. Edit it if you need to.',
                                      'own' => 'They created their own password, so it can\'t be shown. Type one to replace it.',
                                      _ => 'No password is stored to show. Type one to set a new password.',
                                    },
                                    style: const TextStyle(fontSize: 10.5, color: SelmsColors.textMuted),
                                  ),
                                ),
                                InkWell(
                                  onTap: () => setState(() => _passwordCtrl.text = _randomPassword()),
                                  child: const Padding(
                                    padding: EdgeInsets.only(left: 8),
                                    child: Text('Generate',
                                        style: TextStyle(
                                            fontSize: 11, fontWeight: FontWeight.w600, color: SelmsColors.ink)),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  if (_saveError != null) ...[
                    const SizedBox(height: 16),
                    Text(_saveError!, style: const TextStyle(fontSize: 12, color: SelmsColors.rose)),
                  ],
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      OutlinedButton(
                        onPressed: _saving ? null : () => Navigator.of(context).pop(),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: SelmsColors.border),
                          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                        ),
                        child: const Text('Cancel', style: TextStyle(color: SelmsColors.textSecondary)),
                      ),
                      const SizedBox(width: 10),
                      ElevatedButton(
                        onPressed: _saving ? null : _save,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: SelmsColors.ink,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                        ),
                        child: _saving
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Text('Save changes', style: TextStyle(fontWeight: FontWeight.w500)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// Two-column layout that sizes each row to its content — see the
  /// matching comment in add_employee_screen.dart for why this replaced
  /// GridView.count (fixed aspect ratio left dead space on wide screens).
  Widget _grid(List<Widget> fields, {double rowGap = 14, double colGap = 16}) {
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
