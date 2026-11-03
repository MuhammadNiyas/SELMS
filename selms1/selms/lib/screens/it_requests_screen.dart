// lib/screens/it_requests_screen.dart
//
// IT's Requests tab: every new hire's equipment request and every leaver's
// equipment return, one card each (the cards themselves live in
// it_requests_view.dart). Used to be a tab inside Messages.

import 'package:flutter/material.dart';
import '../services/api_client.dart';
import '../theme/selms_colors.dart';
import '../widgets/app_shell.dart' show TopBarActions;
import '../widgets/it_app_shell.dart';
import 'it_requests_view.dart';

class ItRequestsScreen extends StatefulWidget {
  const ItRequestsScreen({super.key, required this.apiBaseUrl, required this.itToken});

  final String apiBaseUrl;
  final String itToken;

  @override
  State<ItRequestsScreen> createState() => _ItRequestsScreenState();
}

class _ItRequestsScreenState extends State<ItRequestsScreen> {
  late final ApiClient _api = ApiClient(baseUrl: widget.apiBaseUrl, hrToken: widget.itToken);

  @override
  Widget build(BuildContext context) {
    return ItAppShell(
      apiBaseUrl: widget.apiBaseUrl,
      itToken: widget.itToken,
      activeRoute: ItRoute.requests,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Expanded(
                  child: Text('Requests',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: SelmsColors.textPrimary)),
                ),
                TopBarActions(),
              ],
            ),
            const SizedBox(height: 14),
            Expanded(
              child: ItRequestsView(api: _api, apiBaseUrl: widget.apiBaseUrl, itToken: widget.itToken),
            ),
          ],
        ),
      ),
    );
  }
}
