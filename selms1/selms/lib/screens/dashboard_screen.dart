// lib/screens/dashboard_screen.dart

import 'package:flutter/material.dart';
import '../theme/selms_colors.dart';
import '../widgets/app_shell.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key, required this.apiBaseUrl, required this.hrToken});

  final String apiBaseUrl;
  final String hrToken;

  @override
  Widget build(BuildContext context) {
    return AppShell(
      apiBaseUrl: apiBaseUrl,
      hrToken: hrToken,
      activeRoute: SelmsRoute.dashboard,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Container(
                    constraints: const BoxConstraints(maxWidth: 340),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: const [
                        Icon(Icons.search, size: 16, color: SelmsColors.textMuted),
                        SizedBox(width: 8),
                        Text('Search...',
                            style: TextStyle(fontSize: 13, color: SelmsColors.textMuted)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                const TopBarActions(),
              ],
            ),
            const SizedBox(height: 24),
            Expanded(
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(28),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Welcome, admin',
                        style: TextStyle(
                            fontSize: 22, fontWeight: FontWeight.w600, color: SelmsColors.textPrimary)),
                    const SizedBox(height: 4),
                    const Text("Here's what's happening today.",
                        style: TextStyle(fontSize: 13.5, color: SelmsColors.textSecondary)),
                    const SizedBox(height: 20),
                    Expanded(
                      child: Container(
                        width: double.infinity,
                        decoration: BoxDecoration(
                          border: Border.all(color: SelmsColors.border, width: 1.5),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Center(
                          child: Text(
                            'Charts and summary cards added here later',
                            style: TextStyle(fontSize: 12.5, color: SelmsColors.textMuted),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
