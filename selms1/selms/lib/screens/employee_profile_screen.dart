// lib/screens/employee_profile_screen.dart
//
// Read-only profile details (report fig 3.31) plus the one thing an
// employee can actually change themselves: their own profile photo,
// via the same crop/adjust flow HR uses (ProfilePhotoField).

import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../models/employee.dart';
import '../services/api_client.dart';
import '../theme/selms_colors.dart';
import '../widgets/form_fields.dart';

class EmployeeProfileScreen extends StatefulWidget {
  const EmployeeProfileScreen({super.key, required this.api, required this.onProfileChanged});

  final ApiClient api;

  /// Called after a successful photo upload so the shell's header
  /// initials/avatar (and the onboarding checklist's "profile setup"
  /// step) can pick up the change.
  final VoidCallback onProfileChanged;

  @override
  State<EmployeeProfileScreen> createState() => _EmployeeProfileScreenState();
}

class _EmployeeProfileScreenState extends State<EmployeeProfileScreen> {
  late Future<Employee> _future;
  Uint8List? _newPhotoBytes;
  bool _uploading = false;
  bool _savingContact = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _future = widget.api.getMyProfile();
  }

  Future<void> _refresh() async {
    setState(() => _future = widget.api.getMyProfile());
    await _future;
  }

  Future<void> _uploadPhoto() async {
    if (_newPhotoBytes == null) return;
    setState(() {
      _uploading = true;
      _error = null;
    });
    try {
      await widget.api.uploadMyPhoto(_newPhotoBytes!);
      _newPhotoBytes = null;
      widget.onProfileChanged();
      await _refresh();
    } catch (e) {
      setState(() => _error = 'Could not upload photo: $e');
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _editContactInfo(Employee employee) async {
    final emailCtrl = TextEditingController(text: employee.personalEmail ?? '');
    final phoneCtrl = TextEditingController(text: employee.mobileNumber ?? '');

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        title: const Text('Edit contact info', style: TextStyle(fontSize: 15)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Personal email', style: TextStyle(fontSize: 11.5, color: SelmsColors.textMuted)),
            const SizedBox(height: 4),
            TextField(
              controller: emailCtrl,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(isDense: true, border: OutlineInputBorder()),
            ),
            const SizedBox(height: 14),
            const Text('Phone', style: TextStyle(fontSize: 11.5, color: SelmsColors.textMuted)),
            const SizedBox(height: 4),
            TextField(
              controller: phoneCtrl,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(isDense: true, border: OutlineInputBorder()),
            ),
          ],
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
      await widget.api.updateMyContactInfo(
        personalEmail: emailCtrl.text.trim(),
        mobileNumber: phoneCtrl.text.trim(),
      );
      await _refresh();
    } catch (e) {
      setState(() => _error = 'Could not save contact info: $e');
    } finally {
      if (mounted) setState(() => _savingContact = false);
    }
  }

  Widget _field(String label, String? value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            flex: 4,
            child: Text(label, style: const TextStyle(fontSize: 12.5, color: SelmsColors.textMuted)),
          ),
          Expanded(
            flex: 6,
            child: Text(
              (value == null || value.isEmpty) ? '—' : value,
              style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _refresh,
      child: FutureBuilder<Employee>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Text('Could not load your profile.\n${snapshot.error}',
                    style: const TextStyle(color: SelmsColors.rose, fontSize: 13)),
              ],
            );
          }

          final employee = snapshot.data!;
          final photoUrl = employee.profileImageUrl == null
              ? null
              : '${widget.api.baseUrl}${employee.profileImageUrl}';
          final complete = photoUrl != null || _newPhotoBytes != null;

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
            children: [
              Center(
                child: Column(
                  children: [
                    ProfilePhotoField(
                      imageBytes: _newPhotoBytes,
                      existingImageUrl: photoUrl,
                      fallbackInitials: employee.initials,
                      onChanged: (bytes) => setState(() => _newPhotoBytes = bytes),
                    ),
                    const SizedBox(height: 10),
                    Text(employee.fullName,
                        style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text(
                      [employee.jobTitle, employee.department]
                          .where((s) => s != null && s.isNotEmpty)
                          .join(' · '),
                      style: const TextStyle(fontSize: 12, color: SelmsColors.textMuted),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              if (!complete)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  margin: const EdgeInsets.only(bottom: 14),
                  decoration: BoxDecoration(
                    color: SelmsColors.statusOnboardingBg,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    'Upload a photo to finish setting up your profile.',
                    style: TextStyle(fontSize: 12, color: SelmsColors.statusOnboardingText),
                  ),
                ),
              if (_error != null) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: SelmsColors.roseBg,
                    border: Border.all(color: SelmsColors.roseBorder),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(_error!, style: const TextStyle(fontSize: 12, color: SelmsColors.rose)),
                ),
              ],
              if (_newPhotoBytes != null) ...[
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _uploading ? null : _uploadPhoto,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: SelmsColors.ink,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: _uploading
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Text('Save new photo', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  ),
                ),
                const SizedBox(height: 14),
              ],
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                decoration: BoxDecoration(
                  color: SelmsColors.cardWhite,
                  border: Border.all(color: SelmsColors.border),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  children: [
                    _field('Full Name', employee.fullName),
                    const Divider(height: 1, color: SelmsColors.border),
                    _field('Employee ID', employee.employeeId),
                    const Divider(height: 1, color: SelmsColors.border),
                    _field('Department', employee.department),
                    const Divider(height: 1, color: SelmsColors.border),
                    _field('Job Role', employee.jobTitle),
                    const Divider(height: 1, color: SelmsColors.border),
                    _field('Work Type', employee.workLocationType),
                    const Divider(height: 1, color: SelmsColors.border),
                    _field('Start Date', employee.hireDate),
                    const Divider(height: 1, color: SelmsColors.border),
                    _field('Work Email', employee.workEmail),
                    const Divider(height: 1, color: SelmsColors.border),
                    _field('Personal Email', employee.personalEmail),
                    const Divider(height: 1, color: SelmsColors.border),
                    _field('Phone', employee.mobileNumber),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _savingContact ? null : () => _editContactInfo(employee),
                  icon: _savingContact
                      ? const SizedBox(
                          width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.edit_outlined, size: 14, color: SelmsColors.ink),
                  label: Text(_savingContact ? 'Saving…' : 'Edit contact info',
                      style: const TextStyle(fontSize: 12.5, color: SelmsColors.ink)),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: SelmsColors.border),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
