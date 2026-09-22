// lib/screens/assign_employee_screen.dart
//
// The page the Products table's "Assign N items to employee" button
// navigates to. Shows what's being handed over, then a searchable
// employee picker, then confirms via POST /api/equipment/assign.

import 'package:flutter/material.dart';
import '../models/equipment.dart';
import '../services/api_client.dart';
import '../theme/selms_colors.dart';

class AssignEmployeeScreen extends StatefulWidget {
  const AssignEmployeeScreen({
    super.key,
    required this.apiBaseUrl,
    required this.itToken,
    required this.equipmentItems,
  });

  final String apiBaseUrl;
  final String itToken;
  final List<Equipment> equipmentItems;

  @override
  State<AssignEmployeeScreen> createState() => _AssignEmployeeScreenState();
}

class _AssignEmployeeScreenState extends State<AssignEmployeeScreen> {
  late final ApiClient _api = ApiClient(baseUrl: widget.apiBaseUrl, hrToken: widget.itToken);
  final _searchCtrl = TextEditingController();

  List<Map<String, dynamic>> _results = [];
  Map<String, dynamic>? _selected;
  final _notesCtrl = TextEditingController();
  bool _loading = true;
  bool _confirming = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _search();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    setState(() => _loading = true);
    try {
      final results = await _api.lookupEmployees(query: _searchCtrl.text);
      if (!mounted) return;
      setState(() {
        _results = results;
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

  Future<void> _confirm() async {
    if (_selected == null) return;
    setState(() {
      _confirming = true;
      _error = null;
    });
    try {
      final message = await _api.assignEquipment(
        _selected!['employee_id'] as String,
        widget.equipmentItems.map((e) => e.id).toList(),
        notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _confirming = false;
        _error = e.toString();
      });
    }
  }

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length == 1) return parts[0].substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1)).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SelmsColors.accentBg,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: SelmsColors.textPrimary,
        title: const Text('Assign equipment', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.equipmentItems.length == 1 ? 'Assigning 1 item' : 'Assigning ${widget.equipmentItems.length} items',
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: SelmsColors.textPrimary),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: const Color(0xFFF9FAFB), borderRadius: BorderRadius.circular(10)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: widget.equipmentItems
                          .map((e) => Padding(
                                padding: const EdgeInsets.symmetric(vertical: 4),
                                child: Row(
                                  children: [
                                    const Icon(Icons.qr_code, size: 14, color: SelmsColors.textSecondary),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(e.name,
                                              style: const TextStyle(fontSize: 12.5, color: SelmsColors.textPrimary)),
                                          Text('${e.serialNumber} · ${e.type}',
                                              style: const TextStyle(fontSize: 10, color: SelmsColors.textMuted)),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ))
                          .toList(),
                    ),
                  ),
                  const SizedBox(height: 20),

                  const Text('Assign to',
                      style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w500, color: SelmsColors.textSecondary)),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _searchCtrl,
                    onChanged: (_) => _search(),
                    decoration: const InputDecoration(hintText: 'Search employees by name or ID...'),
                    style: const TextStyle(fontSize: 13),
                  ),
                  const SizedBox(height: 10),

                  if (_loading)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 20),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (_results.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Text('No employees found.', style: TextStyle(fontSize: 12.5, color: SelmsColors.textMuted)),
                    )
                  else
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 260),
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: _results.length,
                        itemBuilder: (context, i) {
                          final emp = _results[i];
                          final isSelected = _selected != null && _selected!['employee_id'] == emp['employee_id'];
                          return InkWell(
                            onTap: () => setState(() => _selected = emp),
                            borderRadius: BorderRadius.circular(8),
                            child: Container(
                              margin: const EdgeInsets.only(bottom: 4),
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                              decoration: BoxDecoration(
                                color: isSelected ? SelmsColors.accentBg : Colors.transparent,
                                border: Border.all(color: isSelected ? SelmsColors.ink : Colors.transparent),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                children: [
                                  CircleAvatar(
                                    radius: 14,
                                    backgroundColor: SelmsColors.accentBg,
                                    child: Text(_initials(emp['full_name'] as String? ?? '?'),
                                        style: const TextStyle(
                                            fontSize: 10, fontWeight: FontWeight.w600, color: SelmsColors.ink)),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(emp['full_name'] as String? ?? '',
                                            style: const TextStyle(fontSize: 12.5, color: SelmsColors.textPrimary)),
                                        Text('${emp['employee_id']} · ${emp['department'] ?? ''}',
                                            style: const TextStyle(fontSize: 10.5, color: SelmsColors.textMuted)),
                                      ],
                                    ),
                                  ),
                                  if (isSelected) const Icon(Icons.check_circle, size: 18, color: SelmsColors.ink),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),

                  const SizedBox(height: 16),
                  const Text('Notes',
                      style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w500, color: SelmsColors.textSecondary)),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _notesCtrl,
                    maxLines: 2,
                    decoration: const InputDecoration(hintText: 'e.g. Issued during onboarding, day 1'),
                    style: const TextStyle(fontSize: 13),
                  ),

                  if (_error != null) ...[
                    const SizedBox(height: 10),
                    Text(_error!, style: const TextStyle(color: SelmsColors.rose, fontSize: 12)),
                  ],
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.of(context).pop(false),
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: SelmsColors.border),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          child: const Text('Cancel', style: TextStyle(color: SelmsColors.textSecondary)),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: (_selected == null || _confirming) ? null : _confirm,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: SelmsColors.ink,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          child: _confirming
                              ? const SizedBox(
                                  width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                              : const Text('Confirm assign', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
