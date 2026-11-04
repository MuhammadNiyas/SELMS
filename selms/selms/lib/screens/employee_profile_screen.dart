// lib/screens/employee_profile_screen.dart
//
// The employee's own profile (report fig 3.31). Read-only work details, plus
// what an employee can change themselves: their profile photo (same
// crop/adjust flow HR uses, ProfilePhotoField), personal email and phone,
// and their own password. Also lists the equipment IT has assigned to them -
// the list they hand back when they leave.

import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../models/employee.dart';
import '../services/api_client.dart';
import '../theme/selms_colors.dart';
import '../widgets/employee_ui.dart';
import '../widgets/form_fields.dart';

class EmployeeProfileScreen extends StatefulWidget {
  const EmployeeProfileScreen({
    super.key,
    required this.api,
    required this.onProfileChanged,
  });

  final ApiClient api;

  /// Called after a photo or contact change so the shell's header avatar
  /// (and the onboarding "profile setup" step) can pick it up.
  final VoidCallback onProfileChanged;

  @override
  State<EmployeeProfileScreen> createState() => _EmployeeProfileScreenState();
}

class _EmployeeProfileScreenState extends State<EmployeeProfileScreen> {
  late Future<(Employee, List<Map<String, dynamic>>)> _future = _load();
  Uint8List? _newPhotoBytes;
  bool _uploading = false;
  bool _savingContact = false;

  Future<(Employee, List<Map<String, dynamic>>)> _load() async =>
      await (widget.api.getMyProfile(), widget.api.getMyEquipment()).wait;

  Future<void> _refresh() async {
    setState(() { _future = _load(); });
    await _future;
  }

  void _toast(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: error ? SelmsColors.rose : null),
    );
  }

  Future<void> _uploadPhoto() async {
    if (_newPhotoBytes == null) return;
    setState(() => _uploading = true);
    try {
      await widget.api.uploadMyPhoto(_newPhotoBytes!);
      _newPhotoBytes = null;
      widget.onProfileChanged();
      _toast('Profile photo updated.');
      await _refresh();
    } catch (e) {
      _toast('Could not upload photo: $e', error: true);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  /// Deletes the already-saved photo on the server so it's gone everywhere.
  Future<void> _removeSavedPhoto() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        title: const Text('Remove profile photo?', style: TextStyle(fontSize: 16)),
        content: const Text('Your photo will be deleted and your initials shown instead.',
            style: TextStyle(fontSize: 13)),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Keep')),
          ElevatedButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Remove')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await widget.api.removeMyPhoto();
      widget.onProfileChanged();
      await _refresh();
    } catch (e) {
      _toast('Could not remove photo: $e', error: true);
    }
  }

  InputDecoration _input(String label, {Widget? suffix}) => InputDecoration(
        labelText: label,
        isDense: true,
        suffixIcon: suffix,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      );

  Future<void> _editContactInfo(Employee employee) async {
    final phoneCtrl = TextEditingController(text: employee.mobileNumber ?? '');

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        title: const Text('Edit phone number', style: TextStyle(fontSize: 15)),
        content: SizedBox(
          width: 340,
          child: TextField(
            controller: phoneCtrl,
            autofocus: true,
            keyboardType: TextInputType.phone,
            decoration: _input('Phone'),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: SelmsColors.ink, foregroundColor: Colors.white),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (saved != true) return;

    setState(() => _savingContact = true);
    try {
      await widget.api.updateMyContactInfo(mobileNumber: phoneCtrl.text.trim());
      _toast('Phone number saved.');
      widget.onProfileChanged();
      await _refresh();
    } catch (e) {
      _toast('Could not save: $e', error: true);
    } finally {
      if (mounted) setState(() => _savingContact = false);
    }
  }

  Future<void> _changePassword() async {
    final changed = await showDialog<bool>(
      context: context,
      builder: (_) => _ChangePasswordDialog(api: widget.api),
    );
    if (changed == true) _toast('Password changed. Use it next time you sign in.');
  }

  Widget _row(IconData icon, String label, String? value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 11),
      child: Row(
        children: [
          Icon(icon, size: 17, color: SelmsColors.textMuted),
          const SizedBox(width: 12),
          Expanded(
            child: Text(label, style: const TextStyle(fontSize: 12.5, color: SelmsColors.textSecondary)),
          ),
          Flexible(
            child: Text(
              (value == null || value.isEmpty) ? '—' : value,
              textAlign: TextAlign.right,
              style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Widget _rows(List<Widget> rows) => EmpCard(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
        child: Column(
          children: [
            for (final (i, r) in rows.indexed) ...[
              if (i > 0) const Divider(height: 1, color: SelmsColors.border),
              r,
            ],
          ],
        ),
      );

  Widget _actionRow(IconData icon, String label, VoidCallback? onTap, {Color color = SelmsColors.textPrimary}) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 13),
        child: Row(
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 12),
            Expanded(child: Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: color))),
            Icon(Icons.chevron_right, size: 18, color: color.withValues(alpha: 0.5)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _refresh,
      child: FutureBuilder<(Employee, List<Map<String, dynamic>>)>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) return const EmpLoading();
          if (snapshot.hasError) return EmpErrorState(message: '${snapshot.error}', onRetry: _refresh);

          final (employee, equipment) = snapshot.data!;
          final photoUrl =
              employee.profileImageUrl == null ? null : '${widget.api.baseUrl}${employee.profileImageUrl}';
          final hasPhoto = photoUrl != null || _newPhotoBytes != null;

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
            children: [
              // ---- identity
              EmpCard(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 18),
                child: Column(
                  children: [
                    ProfilePhotoField(
                      compact: true,
                      imageBytes: _newPhotoBytes,
                      existingImageUrl: photoUrl,
                      fallbackInitials: employee.initials,
                      onChanged: (bytes) {
                        if (bytes != null || _newPhotoBytes != null) {
                          setState(() => _newPhotoBytes = bytes); // a new pick, or dropping an unsaved one
                        } else if (photoUrl != null) {
                          _removeSavedPhoto();
                        }
                      },
                    ),
                    const SizedBox(height: 10),
                    Text(employee.fullName, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text(
                      [employee.jobTitle, employee.department].where((s) => s != null && s.isNotEmpty).join(' · '),
                      style: const TextStyle(fontSize: 12.5, color: SelmsColors.textSecondary),
                    ),
                    const SizedBox(height: 8),
                    EmpPill(employee.employeeId, bg: SelmsColors.accentBg, fg: SelmsColors.ink, icon: Icons.badge_outlined),
                    if (!hasPhoto) ...[
                      const SizedBox(height: 12),
                      const Text('Add a photo to finish setting up your profile.',
                          style: TextStyle(fontSize: 12, color: EmpColors.warning)),
                    ],
                    if (_newPhotoBytes != null) ...[
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _uploading ? null : _uploadPhoto,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: SelmsColors.ink,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          child: _uploading
                              ? const SizedBox(
                                  width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                              : const Text('Save new photo', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              // ---- contact
              EmpSectionHeader(
                'Contact',
                trailing: TextButton.icon(
                  onPressed: _savingContact ? null : () => _editContactInfo(employee),
                  style: TextButton.styleFrom(
                      padding: EdgeInsets.zero, minimumSize: const Size(0, 0), visualDensity: VisualDensity.compact),
                  icon: const Icon(Icons.edit_outlined, size: 14, color: SelmsColors.ink),
                  label: Text(_savingContact ? 'Saving…' : 'Edit',
                      style: const TextStyle(fontSize: 12, color: SelmsColors.ink)),
                ),
              ),
              _rows([
                _row(Icons.alternate_email, 'Work email', employee.workEmail),
                _row(Icons.phone_outlined, 'Phone', employee.mobileNumber),
              ]),

              // ---- work
              const EmpSectionHeader('Work'),
              _rows([
                _row(Icons.apartment_outlined, 'Department', employee.department),
                _row(Icons.work_outline, 'Job role', employee.jobTitle),
                _row(Icons.supervisor_account_outlined, 'Line manager', employee.lineManager),
                _row(Icons.place_outlined, 'Work type', employee.workLocationType),
                _row(Icons.event_outlined, 'Start date', empDate(employee.hireDate)),
              ]),

              // ---- equipment
              EmpSectionHeader('My equipment',
                  trailing: Text('${equipment.length} item${equipment.length == 1 ? '' : 's'}',
                      style: const TextStyle(fontSize: 11, color: SelmsColors.textMuted))),
              if (equipment.isEmpty)
                const EmpCard(
                  child: Text('No equipment is assigned to you at the moment.',
                      style: TextStyle(fontSize: 12.5, color: SelmsColors.textMuted)),
                )
              else
                EmpCard(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                  child: Column(
                    children: [
                      for (final (i, e) in equipment.indexed) ...[
                        if (i > 0) const Divider(height: 1, color: SelmsColors.border),
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Row(
                            children: [
                              EmpIconBadge(
                                switch ((e['type'] as String? ?? '').toLowerCase()) {
                                  'laptop' => Icons.laptop_mac_outlined,
                                  'monitor' => Icons.desktop_windows_outlined,
                                  'phone' || 'mobile phone' => Icons.smartphone_outlined,
                                  _ => Icons.devices_other_outlined,
                                },
                                size: 34,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(e['name'] as String? ?? 'Equipment',
                                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                                    Text(
                                      [
                                        e['type'] as String? ?? '',
                                        (e['asset_tag'] as String? ?? '').isEmpty ? '' : 'Tag ${e['asset_tag']}',
                                        e['assigned_date'] == null ? '' : 'since ${empDate(e['assigned_date'] as String?)}',
                                      ].where((s) => s.isNotEmpty).join(' · '),
                                      style: const TextStyle(fontSize: 11.5, color: SelmsColors.textMuted),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),

              // ---- account
              const EmpSectionHeader('Account'),
              EmpCard(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 0),
                child: _actionRow(Icons.lock_outline, 'Change password', _changePassword),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ChangePasswordDialog extends StatefulWidget {
  const _ChangePasswordDialog({required this.api});

  final ApiClient api;

  @override
  State<_ChangePasswordDialog> createState() => _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends State<_ChangePasswordDialog> {
  final _current = TextEditingController();
  final _new = TextEditingController();
  final _confirm = TextEditingController();
  bool _show = false;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _current.dispose();
    _new.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final p = _new.text;
    if (p.length < 8 ||
        p.length > 10 ||
        !RegExp(r'[A-Z]').hasMatch(p) ||
        !RegExp(r'\d').hasMatch(p) ||
        !RegExp(r'[^A-Za-z0-9\s]').hasMatch(p)) {
      setState(() => _error =
          'The new password needs 8 to 10 characters, with an uppercase letter, a number and a special character.');
      return;
    }
    if (_new.text != _confirm.text) {
      setState(() => _error = "The new passwords don't match.");
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.api.changeMyPassword(_current.text, _new.text);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    InputDecoration deco(String label) => InputDecoration(
          labelText: label,
          isDense: true,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        );
    return AlertDialog(
      backgroundColor: Colors.white,
      title: const Text('Change password', style: TextStyle(fontSize: 15)),
      content: SizedBox(
        width: 340,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(controller: _current, obscureText: !_show, decoration: deco('Current password')),
            const SizedBox(height: 12),
            TextField(controller: _new, obscureText: !_show, decoration: deco('New password')),
            const SizedBox(height: 12),
            TextField(
              controller: _confirm,
              obscureText: !_show,
              decoration: deco('Confirm new password'),
              onSubmitted: (_) => _save(),
            ),
            const SizedBox(height: 4),
            CheckboxListTile(
              value: _show,
              onChanged: (v) => setState(() => _show = v ?? false),
              dense: true,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: const Text('Show passwords', style: TextStyle(fontSize: 12.5)),
            ),
            if (_error != null)
              Text(_error!, style: const TextStyle(fontSize: 12, color: SelmsColors.rose)),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: _saving ? null : () => Navigator.of(context).pop(false), child: const Text('Cancel')),
        ElevatedButton(
          onPressed: _saving ? null : _save,
          style: ElevatedButton.styleFrom(backgroundColor: SelmsColors.ink, foregroundColor: Colors.white),
          child: _saving
              ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Text('Update password'),
        ),
      ],
    );
  }
}
