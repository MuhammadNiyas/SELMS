// lib/theme/selms_colors.dart
//
// Single source of truth for the black-sidebar / light-blue HR admin
// palette, shared by the login screen and every screen inside AppShell.

import 'package:flutter/material.dart';

class SelmsColors {
  // Brand
  static const ink = Color(0xFF14161B); // sidebar / primary buttons
  static const accentBg = Color(0xFFEAF3FB); // light blue background + hover
  static const rose = Color(0xFFB91C1C);
  static const roseBg = Color(0xFFFEE2E2);
  static const roseBorder = Color(0xFFFCA5A5);

  // Neutrals
  static const cardWhite = Color(0xFFFFFFFF);
  static const fieldBg = Color(0xFFF9FAFB);
  static const border = Color(0xFFE5E7EB);
  static const textPrimary = Color(0xFF14161B);
  static const textSecondary = Color(0xFF374151);
  static const textMuted = Color(0xFF9CA3AF);
  static const sidebarInactive = Color(0xFFD1D5DB);
  static const sidebarIconInactive = Color(0xFF9CA3AF);

  // Status pills
  static const statusOnboardingBg = Color(0xFFFEF3C7);
  static const statusOnboardingText = Color(0xFF92400E);
  static const statusActiveBg = Color(0xFFD1FAE5);
  static const statusActiveText = Color(0xFF065F46);
  static const statusOffboardingBg = Color(0xFFFEE2E2);
  static const statusOffboardingText = Color(0xFF991B1B);
}
