// lib/widgets/employee_card.dart
//
// The employee card from the Employees page: photo, name, job title, ID,
// department, and email and call shortcuts. Also shown as a pop-up in Messages,
// where a team uses it with just its name and email (no [employeeId]).

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../theme/selms_colors.dart';
import 'employee_avatar.dart';

class EmployeeCard extends StatelessWidget {
  const EmployeeCard({
    super.key,
    required this.apiBaseUrl,
    required this.name,
    this.employeeId,
    this.photoUrl,
    this.jobTitle,
    this.department,
    this.workEmail,
    this.mobileNumber,
    this.onTap,
    this.initials,
  });

  final String apiBaseUrl;
  final String name;
  final String? employeeId;
  final String? initials;
  final String? photoUrl;
  final String? jobTitle;
  final String? department;
  final String? workEmail;
  final String? mobileNumber;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                EmployeeAvatar(apiBaseUrl: apiBaseUrl, name: name, photoUrl: photoUrl, size: 38, initials: initials),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 13.5, fontWeight: FontWeight.w500, color: SelmsColors.textPrimary)),
                      Text(jobTitle ?? '',
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 11.5, color: SelmsColors.textMuted)),
                    ],
                  ),
                ),
              ],
            ),
            if (employeeId != null) ...[
              const SizedBox(height: 8),
              Text('$employeeId · ${department ?? ''}',
                  style: const TextStyle(fontSize: 11.5, color: SelmsColors.textMuted)),
            ],
            const Spacer(),
            Row(
              children: [
                _iconButton(Icons.mail_outline, () {
                  if (workEmail != null) launchUrl(Uri.parse('mailto:$workEmail'));
                }),
                if (employeeId != null) ...[
                  const SizedBox(width: 8),
                  _iconButton(Icons.call_outlined, () {
                    if (mobileNumber != null) launchUrl(Uri.parse('tel:$mobileNumber'));
                  }),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _iconButton(IconData icon, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(13),
      child: Container(
        width: 26,
        height: 26,
        decoration: const BoxDecoration(color: Color(0xFFF3F4F6), shape: BoxShape.circle),
        child: Icon(icon, size: 13, color: const Color(0xFF6B7280)),
      ),
    );
  }
}
