// lib/widgets/employee_avatar.dart
//
// One round employee avatar for every list in SELMS (HR, IT and the
// employee app): their profile photo when they have one, their initials
// otherwise - and also the initials if the photo can't be loaded, so a
// missing file never shows as a broken image.

import 'package:flutter/material.dart';
import '../theme/selms_colors.dart';

class EmployeeAvatar extends StatelessWidget {
  const EmployeeAvatar({
    super.key,
    required this.apiBaseUrl,
    required this.name,
    this.photoUrl,
    this.size = 32,
    this.background = SelmsColors.accentBg,
  });

  final String apiBaseUrl;
  final String name;

  /// The stored path, e.g. /uploads/EMP-001-1791692874.png (or a full URL).
  final String? photoUrl;
  final double size;
  final Color background;

  static String initialsOf(String name) {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final initials = Text(
      initialsOf(name),
      style: TextStyle(fontSize: size * 0.36, fontWeight: FontWeight.w600, color: SelmsColors.ink),
    );
    final url = photoUrl;
    final hasPhoto = url != null && url.isNotEmpty;
    return Container(
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(color: background, shape: BoxShape.circle),
      alignment: Alignment.center,
      child: hasPhoto
          ? Image.network(
              url.startsWith('http') ? url : '$apiBaseUrl$url',
              width: size,
              height: size,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => initials,
            )
          : initials,
    );
  }
}
