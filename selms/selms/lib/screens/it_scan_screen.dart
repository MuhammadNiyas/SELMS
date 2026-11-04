// lib/screens/it_scan_screen.dart
//
// Reads an equipment QR code (which just encodes that item's database ID),
// looks it up, and shows a bottom sheet with the item's details plus two
// actions — Assign / Retrieve — only one of which is ever actually
// clickable, based on the item's current status. Both actions route into
// screens that already exist (AssignEmployeeScreen, ReturnEquipmentDialog)
// — scanning is just a faster entry point into them, not new logic.

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../models/equipment.dart';
import '../services/api_client.dart';
import '../theme/selms_colors.dart';
import '../widgets/equipment_photo.dart';
import '../widgets/it_app_shell.dart';
import 'assign_employee_screen.dart';
import 'equipment_detail_screen.dart';

class ItScanScreen extends StatefulWidget {
  const ItScanScreen({super.key, required this.apiBaseUrl, required this.itToken});

  final String apiBaseUrl;
  final String itToken;

  @override
  State<ItScanScreen> createState() => _ItScanScreenState();
}

class _ItScanScreenState extends State<ItScanScreen> {
  late final ApiClient _api = ApiClient(baseUrl: widget.apiBaseUrl, hrToken: widget.itToken);
  final MobileScannerController _controller = MobileScannerController();

  bool _busy = false; // prevents multiple detections firing while one is being handled
  bool _torchOn = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_busy) return;
    final code = capture.barcodes.isNotEmpty ? capture.barcodes.first.rawValue : null;
    if (code == null || code.isEmpty) return;

    setState(() => _busy = true);
    await _controller.stop();

    try {
      final equipment = await _api.getEquipment(code);
      if (!mounted) return;
      await _showFoundSheet(equipment);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("That code doesn't match any equipment in SELMS.")),
      );
    }

    if (!mounted) return;
    setState(() => _busy = false);
    await _controller.start();
  }

  Future<void> _showFoundSheet(Equipment e) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (sheetContext) => _FoundEquipmentSheet(
        apiBaseUrl: widget.apiBaseUrl,
        equipment: e,
        onViewDetails: () {
          Navigator.of(sheetContext).pop();
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => EquipmentDetailScreen(
                apiBaseUrl: widget.apiBaseUrl,
                itToken: widget.itToken,
                equipmentId: e.id,
              ),
            ),
          );
        },
        onAssign: () {
          Navigator.of(sheetContext).pop();
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => AssignEmployeeScreen(
                apiBaseUrl: widget.apiBaseUrl,
                itToken: widget.itToken,
                equipmentItems: [e],
              ),
            ),
          );
        },
        onRetrieve: () {
          Navigator.of(sheetContext).pop();
          showDialog<void>(
            context: context,
            builder: (_) => ReturnEquipmentDialog(
              equipment: e,
              apiBaseUrl: widget.apiBaseUrl,
              onConfirm: (condition, notes) async {
                try {
                  await _api.returnEquipment(e.id, condition: condition, notes: notes);
                  if (!mounted) return;
                  Navigator.of(context).pop();
                  ScaffoldMessenger.of(context)
                      .showSnackBar(SnackBar(content: Text('${e.name} retrieved.')));
                } catch (err) {
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Could not retrieve item: $err'), backgroundColor: SelmsColors.rose));
                }
              },
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ItAppShell(
      apiBaseUrl: widget.apiBaseUrl,
      itToken: widget.itToken,
      activeRoute: ItRoute.scan,
      child: Stack(
        children: [
          MobileScanner(controller: _controller, onDetect: _onDetect),

          // Dim overlay with a viewfinder cut-out, matching the mockup.
          Positioned.fill(
            child: IgnorePointer(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.only(top: 60),
                      child: const Text('Scan equipment QR',
                          style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w500)),
                    ),
                    const SizedBox(height: 24),
                    _ViewfinderFrame(active: !_busy),
                    const SizedBox(height: 24),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 40),
                      child: Text(
                        _busy ? 'Looking up that item...' : 'Point your camera at the QR code on the equipment label',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          Positioned(
            bottom: 28,
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _RoundIconButton(
                  icon: _torchOn ? Icons.flash_on : Icons.flash_off,
                  onTap: () {
                    _controller.toggleTorch();
                    setState(() => _torchOn = !_torchOn);
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ViewfinderFrame extends StatelessWidget {
  const _ViewfinderFrame({required this.active});
  final bool active;

  @override
  Widget build(BuildContext context) {
    final color = active ? Colors.white : Colors.white38;
    return SizedBox(
      width: 220,
      height: 220,
      child: Stack(
        children: [
          _corner(top: 0, left: 0, color: color),
          _corner(top: 0, right: 0, color: color),
          _corner(bottom: 0, left: 0, color: color),
          _corner(bottom: 0, right: 0, color: color),
        ],
      ),
    );
  }

  Widget _corner({double? top, double? bottom, double? left, double? right, required Color color}) {
    return Positioned(
      top: top,
      bottom: bottom,
      left: left,
      right: right,
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          border: Border(
            top: top != null ? BorderSide(color: color, width: 3) : BorderSide.none,
            bottom: bottom != null ? BorderSide(color: color, width: 3) : BorderSide.none,
            left: left != null ? BorderSide(color: color, width: 3) : BorderSide.none,
            right: right != null ? BorderSide(color: color, width: 3) : BorderSide.none,
          ),
        ),
      ),
    );
  }
}

class _RoundIconButton extends StatelessWidget {
  const _RoundIconButton({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(22),
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.12), shape: BoxShape.circle),
        child: Icon(icon, size: 18, color: Colors.white),
      ),
    );
  }
}

/// The bottom sheet that appears after a successful scan — product details
/// first, then a choice between Assign and Retrieve, with only the
/// applicable one enabled.
class _FoundEquipmentSheet extends StatelessWidget {
  const _FoundEquipmentSheet({
    required this.apiBaseUrl,
    required this.equipment,
    required this.onViewDetails,
    required this.onAssign,
    required this.onRetrieve,
  });

  final String apiBaseUrl;
  final Equipment equipment;
  final VoidCallback onViewDetails;
  final VoidCallback onAssign;
  final VoidCallback onRetrieve;

  String _employeeInitials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length == 1) return parts[0].substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1)).toUpperCase();
  }

  IconData _typeIcon(String type) {
    switch (type) {
      case 'Laptop':
        return Icons.laptop_mac_outlined;
      case 'Phone':
        return Icons.smartphone_outlined;
      case 'Headphone':
        return Icons.headphones_outlined;
      case 'Monitor':
        return Icons.desktop_windows_outlined;
      case 'Mouse':
        return Icons.mouse_outlined;
      case 'Keyboard':
        return Icons.keyboard_outlined;
      default:
        return Icons.inventory_2_outlined;
    }
  }

  Color _statusBg(String status) => status == 'assigned' ? const Color(0xFFE6F1FB) : const Color(0xFFE1F5EE);
  Color _statusFg(String status) => status == 'assigned' ? const Color(0xFF0C447C) : const Color(0xFF085041);
  String _statusLabel(String status) => status[0].toUpperCase() + status.substring(1);

  @override
  Widget build(BuildContext context) {
    final isAvailable = equipment.status == 'available';
    final isAssigned = equipment.status == 'assigned';

    final productDetailsBlock = Row(
      children: [
        EquipmentPhoto(
          apiBaseUrl: apiBaseUrl,
          photoUrl: equipment.photoUrl,
          fallback: Icon(_typeIcon(equipment.type), size: 18, color: SelmsColors.ink),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(equipment.name,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: SelmsColors.textPrimary)),
              Text('${equipment.serialNumber} · ${equipment.type}',
                  style: const TextStyle(fontSize: 10, color: SelmsColors.textMuted)),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
          decoration: BoxDecoration(color: _statusBg(equipment.status), borderRadius: BorderRadius.circular(20)),
          child: Text(_statusLabel(equipment.status),
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w500, color: _statusFg(equipment.status))),
        ),
      ],
    );

    final employeeCard = (isAssigned && equipment.assignedToEmployeeName != null)
        ? Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: const Color(0xFFEAF3FB), borderRadius: BorderRadius.circular(10)),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: Colors.white,
                  child: Text(_employeeInitials(equipment.assignedToEmployeeName!),
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: SelmsColors.ink)),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(equipment.assignedToEmployeeName!,
                          style: const TextStyle(fontSize: 13.5, color: SelmsColors.textPrimary)),
                      Text(
                        [
                          if (equipment.assignedToEmployeeId != null) equipment.assignedToEmployeeId,
                          if (equipment.assignedToEmployeeDepartment != null) equipment.assignedToEmployeeDepartment,
                        ].join(' · '),
                        style: const TextStyle(fontSize: 11, color: SelmsColors.textMuted),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          )
        : null;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(color: SelmsColors.border, borderRadius: BorderRadius.circular(2)),
              ),
            ),

            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('PRODUCT DETAILS',
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.w500, color: SelmsColors.textMuted)),
                InkWell(
                  onTap: onViewDetails,
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('View full details',
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF0C447C))),
                      Icon(Icons.chevron_right, size: 14, color: Color(0xFF0C447C)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            productDetailsBlock,

            // Employee details go under the equipment details — this is
            // the "retrieve" case.
            if (employeeCard != null) ...[
              const SizedBox(height: 12),
              employeeCard,
            ] else ...[
              const SizedBox(height: 8),
              const Text('Not currently assigned to anyone.',
                  style: TextStyle(fontSize: 10.5, color: SelmsColors.textMuted)),
            ],
            const SizedBox(height: 16),
            const Divider(height: 1, color: SelmsColors.border),
            const SizedBox(height: 14),
            const Text('WHAT WOULD YOU LIKE TO DO?',
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.w500, color: SelmsColors.textMuted)),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _ActionButton(label: 'Assign', enabled: isAvailable, onTap: isAvailable ? onAssign : null),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _ActionButton(label: 'Retrieve', enabled: isAssigned, onTap: isAssigned ? onRetrieve : null),
                ),
              ],
            ),
            if (isAvailable)
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: Text("Retrieve is disabled — this item isn't assigned to anyone yet.",
                    textAlign: TextAlign.center, style: TextStyle(fontSize: 9.5, color: SelmsColors.textMuted)),
              )
            else if (isAssigned)
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: Text('Assign is disabled — retrieve it first before assigning to someone else.',
                    textAlign: TextAlign.center, style: TextStyle(fontSize: 9.5, color: SelmsColors.textMuted)),
              ),
          ],
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({required this.label, required this.enabled, required this.onTap});
  final String label;
  final bool enabled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 11),
        decoration: BoxDecoration(
          color: enabled ? SelmsColors.ink : const Color(0xFFF3F4F6),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 12,
            fontWeight: enabled ? FontWeight.w500 : FontWeight.w400,
            color: enabled ? Colors.white : const Color(0xFFB4B2A9),
          ),
        ),
      ),
    );
  }
}
