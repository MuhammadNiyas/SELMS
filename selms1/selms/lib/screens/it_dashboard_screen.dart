// lib/screens/it_dashboard_screen.dart

import 'package:flutter/material.dart';
import '../models/equipment.dart';
import '../services/api_client.dart';
import '../theme/selms_colors.dart';
import '../widgets/app_shell.dart' show TopBarActions;
import '../widgets/it_app_shell.dart';

class ItDashboardScreen extends StatefulWidget {
  const ItDashboardScreen({super.key, required this.apiBaseUrl, required this.itToken});

  final String apiBaseUrl;
  final String itToken;

  @override
  State<ItDashboardScreen> createState() => _ItDashboardScreenState();
}

class _ItDashboardScreenState extends State<ItDashboardScreen> {
  late final ApiClient _api = ApiClient(baseUrl: widget.apiBaseUrl, hrToken: widget.itToken);

  EquipmentSummary? _summary;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final summary = await _api.equipmentSummary();
      if (!mounted) return;
      setState(() {
        _summary = summary;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return ItAppShell(
      apiBaseUrl: widget.apiBaseUrl,
      itToken: widget.itToken,
      activeRoute: ItRoute.dashboard,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                    constraints: const BoxConstraints(maxWidth: 340),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10)),
                    child: Row(
                      children: const [
                        Icon(Icons.search, size: 16, color: SelmsColors.textMuted),
                        SizedBox(width: 8),
                        Text('Search...', style: TextStyle(fontSize: 13, color: SelmsColors.textMuted)),
                      ],
                    ),
                  ),
                ),
                const TopBarActions(),
              ],
            ),
            const SizedBox(height: 20),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(child: Text(_error!, style: const TextStyle(color: SelmsColors.rose, fontSize: 13)));
    }
    final s = _summary!;
    return SingleChildScrollView(
      child: Container(
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Welcome',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: SelmsColors.textPrimary)),
            const Text('Here\'s your equipment overview today.',
                style: TextStyle(fontSize: 13.5, color: SelmsColors.textSecondary)),
            const SizedBox(height: 20),
            LayoutBuilder(
              builder: (context, constraints) {
                final crossAxisCount = constraints.maxWidth > 700 ? 4 : 2;
                return GridView.count(
                  crossAxisCount: crossAxisCount,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisSpacing: 14,
                  mainAxisSpacing: 14,
                  childAspectRatio: 1.6,
                  children: [
                    _kpiCard('Total equipment', s.total, Icons.inventory_2_outlined, SelmsColors.accentBg, SelmsColors.ink),
                    _kpiCard('Available', s.available, Icons.check_circle_outline, const Color(0xFFE1F5EE), const Color(0xFF085041)),
                    _kpiCard('Assigned', s.assigned, Icons.person_outline, const Color(0xFFE6F1FB), const Color(0xFF0C447C)),
                    _kpiCard('Returned', s.returned, Icons.replay_outlined, const Color(0xFFFAEEDA), const Color(0xFF854F0B)),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _kpiCard(String label, int value, IconData icon, Color bg, Color fg) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(border: Border.all(color: SelmsColors.border), borderRadius: BorderRadius.circular(10)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
            alignment: Alignment.center,
            child: Icon(icon, size: 16, color: fg),
          ),
          const SizedBox(height: 10),
          Text('$value', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: SelmsColors.textPrimary)),
          Text(label, style: const TextStyle(fontSize: 11.5, color: SelmsColors.textMuted)),
        ],
      ),
    );
  }
}
