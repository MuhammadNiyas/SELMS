// lib/widgets/equipment_photo.dart
//
// A product's photo in a small rounded square. Shows [fallback] when the
// product has no photo or the photo can't be loaded.

import 'package:flutter/material.dart';
import '../theme/selms_colors.dart';

class EquipmentPhoto extends StatelessWidget {
  const EquipmentPhoto({
    super.key,
    required this.apiBaseUrl,
    required this.photoUrl,
    required this.fallback,
    this.size = 40,
  });

  final String apiBaseUrl;
  final String? photoUrl;
  final Widget fallback;
  final double size;

  @override
  Widget build(BuildContext context) {
    final url = photoUrl;
    return Container(
      width: size,
      height: size,
      clipBehavior: Clip.hardEdge,
      decoration: BoxDecoration(color: SelmsColors.accentBg, borderRadius: BorderRadius.circular(8)),
      alignment: Alignment.center,
      child: (url != null && url.isNotEmpty)
          ? Image.network('$apiBaseUrl$url',
              fit: BoxFit.cover, width: size, height: size, errorBuilder: (_, _, _) => fallback)
          : fallback,
    );
  }
}
