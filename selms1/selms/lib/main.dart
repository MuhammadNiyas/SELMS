// lib/main.dart

import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'screens/selms_login_screen.dart';
import 'theme/selms_colors.dart';

/// localhost means "this device itself" on every platform — which is fine
/// for Chrome (same machine as the backend), but on an Android emulator
/// that resolves to the emulator's own internal environment, not your
/// actual computer. 10.0.2.2 is the emulator's special alias for "the
/// host machine's localhost". iOS simulators, unlike Android, can use
/// localhost directly since they share the host's network stack.
String _defaultApiBaseUrl() {
  // On web, reuse whatever host the page itself was loaded from, so the
  // same build works on the laptop (localhost) and on a phone that opened
  // it via the laptop's LAN IP (e.g. 192.168.1.20).
  if (kIsWeb) {
    final host = Uri.base.host;
    return 'http://${host.isEmpty ? 'localhost' : host}:5000';
  }
  if (Platform.isAndroid) return 'http://10.0.2.2:5000';
  return 'http://localhost:5000';
}

void main() {
  runApp(const SelmsApp());
}

class SelmsApp extends StatelessWidget {
  const SelmsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SELMS',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: SelmsColors.ink,
        useMaterial3: true,
        scaffoldBackgroundColor: SelmsColors.accentBg,
      ),
      // Change this if you deploy the backend somewhere other than
      // localhost, e.g. 'https://api.selms.my' — that overrides the
      // platform-specific default below for every platform at once.
      home: SelmsLoginScreen(apiBaseUrl: _defaultApiBaseUrl()),
    );
  }
}
