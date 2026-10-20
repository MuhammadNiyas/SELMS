// lib/screens/hr_shipments_screen.dart
//
// HR's view of the Pos Malaysia shipments IT creates: who a parcel is for,
// what's in it, its status, the Pos reference (with a Track button) and the
// QR. Read-only - IT owns the shipments, HR just follows them. It is the
// same page IT uses (ShipmentsPage) with readOnly switched on.

import 'package:flutter/material.dart';
import '../widgets/app_shell.dart';
import 'it_shipments_screen.dart';

class HrShipmentsScreen extends StatelessWidget {
  const HrShipmentsScreen({super.key, required this.apiBaseUrl, required this.hrToken});

  final String apiBaseUrl;
  final String hrToken;

  @override
  Widget build(BuildContext context) {
    return AppShell(
      apiBaseUrl: apiBaseUrl,
      hrToken: hrToken,
      activeRoute: SelmsRoute.shipments,
      child: ShipmentsPage(apiBaseUrl: apiBaseUrl, token: hrToken, readOnly: true),
    );
  }
}
