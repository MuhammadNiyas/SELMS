// lib/screens/equipment_detail_screen.dart

import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../models/equipment.dart';
import '../services/api_client.dart';
import '../theme/selms_colors.dart';
import '../widgets/form_fields.dart' show SquarePhotoViewDialog;
import 'edit_equipment_screen.dart';

class EquipmentDetailScreen extends StatefulWidget {
  const EquipmentDetailScreen({
    super.key,
    required this.apiBaseUrl,
    required this.itToken,
    required this.equipmentId,
    this.viewOnly = false,
  });

  final String apiBaseUrl;
  final String itToken;
  final String equipmentId;

  /// HR opens the same page as IT, but without Edit and Retrieve.
  final bool viewOnly;

  @override
  State<EquipmentDetailScreen> createState() => _EquipmentDetailScreenState();
}

class _EquipmentDetailScreenState extends State<EquipmentDetailScreen> {
  late final ApiClient _api = ApiClient(baseUrl: widget.apiBaseUrl, hrToken: widget.itToken);

  Equipment? _equipment;
  bool _loading = true;
  String? _error;
  bool _printing = false;

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
      final e = await _api.getEquipment(widget.equipmentId);
      if (!mounted) return;
      setState(() {
        _equipment = e;
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

  Color _statusBg(String status) {
    switch (status) {
      case 'assigned':
        return const Color(0xFFE6F1FB);
      case 'under_repair':
        return const Color(0xFFFAEEDA);
      case 'retired':
      case 'lost':
        return const Color(0xFFFAECE7);
      case 'returned':
        return const Color(0xFFF1EFE8);
      default:
        return const Color(0xFFE1F5EE);
    }
  }

  Color _statusFg(String status) {
    switch (status) {
      case 'assigned':
        return const Color(0xFF0C447C);
      case 'under_repair':
        return const Color(0xFF854F0B);
      case 'retired':
      case 'lost':
        return const Color(0xFF993C1D);
      case 'returned':
        return const Color(0xFF444441);
      default:
        return const Color(0xFF085041);
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'under_repair':
        return 'Under repair';
      default:
        return status[0].toUpperCase() + status.substring(1);
    }
  }

  void _viewPhoto(BuildContext context, String url) {
    showDialog<void>(
      context: context,
      builder: (_) => SquarePhotoViewDialog(networkImageUrl: '${widget.apiBaseUrl}$url'),
    );
  }

  void _showReturnDialog(Equipment e) {
    showDialog<void>(
      context: context,
      builder: (_) => ReturnEquipmentDialog(
        equipment: e,
        onConfirm: (condition, notes) async {
          try {
            await _api.returnEquipment(e.id, condition: condition, notes: notes);
            if (!mounted) return;
            Navigator.of(context).pop();
            _load();
          } catch (err) {
            if (!mounted) return;
            ScaffoldMessenger.of(context)
                .showSnackBar(SnackBar(content: Text('Could not return item: $err'), backgroundColor: SelmsColors.rose));
          }
        },
      ),
    );
  }

  /// Renders the same QR (its own database ID) to a PNG, builds a small
  /// printable label PDF with it, and opens the platform's print dialog —
  /// on web this is the browser's native print/save-as-PDF prompt.
  Future<void> _printLabel(Equipment e) async {
    setState(() => _printing = true);
    try {
      final qrPainter = QrPainter(
        data: e.id,
        version: QrVersions.auto,
        gapless: true,
      );
      final qrImageData = await qrPainter.toImageData(400);
      final qrBytes = qrImageData!.buffer.asUint8List();
      final qrImage = pw.MemoryImage(qrBytes);

      final doc = pw.Document();
      doc.addPage(
        pw.Page(
          pageFormat: const PdfPageFormat(226.77, 226.77), // ~80mm square label
          margin: const pw.EdgeInsets.all(16),
          build: (context) => pw.Column(
            mainAxisAlignment: pw.MainAxisAlignment.center,
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              pw.Image(qrImage, width: 140, height: 140),
              pw.SizedBox(height: 10),
              pw.Text(e.name,
                  textAlign: pw.TextAlign.center,
                  style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
              if (e.assetTag != null && e.assetTag!.isNotEmpty) ...[
                pw.SizedBox(height: 3),
                pw.Text('Asset tag: ${e.assetTag}',
                    textAlign: pw.TextAlign.center, style: const pw.TextStyle(fontSize: 9)),
              ],
            ],
          ),
        ),
      );

      await Printing.layoutPdf(onLayout: (_) async => doc.save());
    } catch (err) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Could not print label: $err'), backgroundColor: SelmsColors.rose));
    } finally {
      if (mounted) setState(() => _printing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SelmsColors.accentBg,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: SelmsColors.textPrimary,
        title: const Text('Equipment details', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(child: Text(_error!, style: const TextStyle(color: SelmsColors.rose, fontSize: 13)));
    }
    final e = _equipment!;
    final hasPhoto = e.photoUrl != null && e.photoUrl!.isNotEmpty;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // QR + name card
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(color: SelmsColors.ink, borderRadius: BorderRadius.circular(12)),
                child: Column(
                  children: [
                    Container(
                      width: 140,
                      height: 140,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10)),
                      // The QR just encodes the item's own database ID — that's
                      // all a scan needs to look this exact record back up.
                      child: QrImageView(data: e.id, backgroundColor: Colors.white),
                    ),
                    const SizedBox(height: 14),
                    Text(e.name, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600), textAlign: TextAlign.center),
                    if (e.assetTag != null && e.assetTag!.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: Text('Asset tag: ${e.assetTag}', style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 11.5)),
                      ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        InkWell(
                          onTap: _printing ? null : () => _printLabel(e),
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8)),
                            child: Row(mainAxisSize: MainAxisSize.min, children: [
                              if (_printing)
                                const SizedBox(
                                    width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                              else
                                const Icon(Icons.print_outlined, size: 14, color: SelmsColors.ink),
                              const SizedBox(width: 6),
                              const Text('Print label',
                                  style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w500, color: SelmsColors.ink)),
                            ]),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),

              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 10),
                      decoration: BoxDecoration(color: _statusBg(e.status), borderRadius: BorderRadius.circular(8)),
                      child: Text(_statusLabel(e.status),
                          style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500, color: _statusFg(e.status))),
                    ),
                  ),
                  if (!widget.viewOnly) ...[
                    const SizedBox(width: 10),
                    InkWell(
                      onTap: () {
                        Navigator.of(context)
                            .push(MaterialPageRoute(
                              builder: (_) => EditEquipmentScreen(
                                apiBaseUrl: widget.apiBaseUrl,
                                itToken: widget.itToken,
                                equipmentId: widget.equipmentId,
                              ),
                            ))
                            .then((_) => _load());
                      },
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8)),
                        child: const Icon(Icons.edit_outlined, size: 16, color: SelmsColors.textSecondary),
                      ),
                    ),
                  ],
                ],
              ),

              if (e.status == 'assigned' && e.assignedToEmployeeName != null) ...[
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          CircleAvatar(
                            radius: 18,
                            backgroundColor: SelmsColors.accentBg,
                            child: Text(_employeeInitials(e.assignedToEmployeeName!),
                                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: SelmsColors.ink)),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(e.assignedToEmployeeName!,
                                    style: const TextStyle(fontSize: 13.5, color: SelmsColors.textPrimary)),
                                Text(
                                  [
                                    if (e.assignedToEmployeeId != null) e.assignedToEmployeeId,
                                    if (e.assignedToEmployeeDepartment != null) e.assignedToEmployeeDepartment,
                                  ].join(' · '),
                                  style: const TextStyle(fontSize: 11, color: SelmsColors.textMuted),
                                ),
                              ],
                            ),
                          ),
                          if (!widget.viewOnly)
                            InkWell(
                              onTap: () => _showReturnDialog(e),
                              child: const Text('Retrieve',
                                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: SelmsColors.ink)),
                            ),
                        ],
                      ),
                      const Divider(height: 20, color: SelmsColors.border),
                      _assignField('Assigned on', _formatAssignedDate(e.assignedDate)),
                      if (e.assignmentNotes != null && e.assignmentNotes!.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        _assignField('Notes', e.assignmentNotes!),
                      ],
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 14),

              // Photo — its own separate container, placed under the
              // Available status row rather than sharing the dark QR card.
              if (hasPhoto) ...[
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
                  child: Center(
                    child: InkWell(
                      onTap: () => _viewPhoto(context, e.photoUrl!),
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        width: 96,
                        height: 96,
                        clipBehavior: Clip.hardEdge,
                        decoration: BoxDecoration(
                          color: const Color(0xFFF9FAFB),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: SelmsColors.border),
                        ),
                        child: Image.network('${widget.apiBaseUrl}${e.photoUrl}', fit: BoxFit.cover, width: 96, height: 96),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
              ],

              _sectionCard('Identification', [
                _field('Type', e.type),
                if (e.brand != null && e.brand!.isNotEmpty) _field('Brand', e.brand!),
                if (e.model != null && e.model!.isNotEmpty) _field('Model', e.model!),
                _field('Serial number', e.serialNumber),
                if (e.assetTag != null && e.assetTag!.isNotEmpty) _field('Asset tag', e.assetTag!),
                if (e.ram != null && e.ram!.isNotEmpty) _field('RAM', e.ram!),
                if (e.storage != null && e.storage!.isNotEmpty) _field('Storage', e.storage!),
                if (e.colorMarks != null && e.colorMarks!.isNotEmpty) _field('Color / marks', e.colorMarks!),
                if (e.softwareLicenses != null && e.softwareLicenses!.isNotEmpty) _field('Software / licenses', e.softwareLicenses!),
              ]),

              _sectionCard('Condition & status', [
                if (e.condition != null) _field('Condition', e.condition!),
                _field('Status', _statusLabel(e.status)),
                if (e.accessoriesIncluded != null && e.accessoriesIncluded!.isNotEmpty)
                  _field('Accessories included', e.accessoriesIncluded!),
              ]),

              if ((e.purchaseDate != null) || (e.purchasePrice != null) || (e.vendor != null) || (e.warrantyExpiry != null))
                _sectionCard('Purchase & warranty', [
                  if (e.purchaseDate != null) _field('Purchase date', e.purchaseDate!.split('T').first),
                  if (e.purchasePrice != null) _field('Purchase price', 'RM ${e.purchasePrice}'),
                  if (e.vendor != null && e.vendor!.isNotEmpty) _field('Vendor', e.vendor!),
                  if (e.warrantyExpiry != null) _field('Warranty expiry', e.warrantyExpiry!.split('T').first),
                ]),

              if (e.notes != null && e.notes!.isNotEmpty)
                _sectionCard('Notes', [
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Text(e.notes!, style: const TextStyle(fontSize: 12, color: SelmsColors.textPrimary, height: 1.5)),
                  ),
                ]),
            ],
          ),
        ),
      ),
    );
  }

  String _employeeInitials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length == 1) return parts[0].substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1)).toUpperCase();
  }

  String _formatAssignedDate(String? iso) {
    if (iso == null) return '—';
    final d = DateTime.tryParse(iso);
    if (d == null) return '—';
    return '${d.day.toString().padLeft(2, '0')} ${_monthName(d.month)} ${d.year}';
  }

  String _monthName(int m) => const [
        'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
      ][m - 1];

  Widget _assignField(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 9, color: SelmsColors.textMuted)),
        const SizedBox(height: 2),
        Text(value, style: const TextStyle(fontSize: 11.5, color: SelmsColors.textPrimary)),
      ],
    );
  }

  Widget _sectionCard(String title, List<Widget> children) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: SelmsColors.textPrimary)),
            const SizedBox(height: 10),
            ...children,
          ],
        ),
      ),
    );
  }

  /// Fixed-width label column, everything left-aligned — this is what
  /// keeps every row lining up straight down the card, instead of values
  /// hugging the right edge at different lengths.
  Widget _field(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(label, style: const TextStyle(fontSize: 11, color: SelmsColors.textMuted)),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(fontSize: 12.5, color: SelmsColors.textPrimary)),
          ),
        ],
      ),
    );
  }
}

/// The lightweight "Return equipment" popup — asks for condition on
/// return, which decides whether the item goes back to Available or
/// routes to Under repair (see the /return backend route).
class ReturnEquipmentDialog extends StatefulWidget {
  const ReturnEquipmentDialog({required this.equipment, required this.onConfirm});

  final Equipment equipment;
  final Future<void> Function(String? condition, String? notes) onConfirm;

  @override
  State<ReturnEquipmentDialog> createState() => ReturnEquipmentDialogState();
}

class ReturnEquipmentDialogState extends State<ReturnEquipmentDialog> {
  String _condition = 'Good';
  final _notesCtrl = TextEditingController();
  bool _confirming = false;

  String _employeeInitials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length == 1) return parts[0].substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1)).toUpperCase();
  }

  @override
  void dispose() {
    _notesCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.equipment;
    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Return equipment',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: SelmsColors.textPrimary)),
              const SizedBox(height: 6),
              const Text('Mark this item as returned or unassign?',
                  style: TextStyle(fontSize: 12, color: SelmsColors.textSecondary, height: 1.4)),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: const Color(0xFFF9FAFB), borderRadius: BorderRadius.circular(10)),
                child: Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(color: SelmsColors.accentBg, borderRadius: BorderRadius.circular(8)),
                      alignment: Alignment.center,
                      child: const Icon(Icons.inventory_2_outlined, size: 17, color: SelmsColors.ink),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(e.name, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500, color: SelmsColors.textPrimary)),
                          Text('${e.serialNumber} · ${e.type}',
                              style: const TextStyle(fontSize: 10, color: SelmsColors.textMuted)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              if (e.assignedToEmployeeName != null) ...[
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: const Color(0xFFEAF3FB), borderRadius: BorderRadius.circular(10)),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 16,
                        backgroundColor: Colors.white,
                        child: Text(_employeeInitials(e.assignedToEmployeeName!),
                            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: SelmsColors.ink)),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(e.assignedToEmployeeName!,
                                style: const TextStyle(fontSize: 12.5, color: SelmsColors.textPrimary)),
                            Text(
                              [
                                if (e.assignedToEmployeeId != null) e.assignedToEmployeeId,
                                if (e.assignedToEmployeeDepartment != null) e.assignedToEmployeeDepartment,
                              ].join(' · '),
                              style: const TextStyle(fontSize: 10, color: SelmsColors.textMuted),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 18),
              const Text('Condition on return',
                  style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w500, color: SelmsColors.textSecondary)),
              const SizedBox(height: 8),
              Row(
                children: ['Good', 'Damaged', 'Lost'].map((c) {
                  final isSelected = c == _condition;
                  return Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: InkWell(
                      onTap: () => setState(() => _condition = c),
                      borderRadius: BorderRadius.circular(20),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: isSelected ? SelmsColors.accentBg : Colors.white,
                          border: Border.all(color: isSelected ? SelmsColors.ink : SelmsColors.border),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(c,
                            style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: isSelected ? FontWeight.w500 : FontWeight.w400,
                                color: isSelected ? SelmsColors.ink : SelmsColors.textSecondary)),
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 18),
              const Text('Notes',
                  style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w500, color: SelmsColors.textSecondary)),
              const SizedBox(height: 8),
              TextField(
                controller: _notesCtrl,
                maxLines: 2,
                decoration: const InputDecoration(hintText: 'e.g. Returned with minor scratches on lid'),
                style: const TextStyle(fontSize: 12.5),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: SelmsColors.border),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                      ),
                      child: const Text('Cancel', style: TextStyle(color: SelmsColors.textSecondary, fontSize: 12.5)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _confirming
                          ? null
                          : () async {
                              setState(() => _confirming = true);
                              await widget.onConfirm(
                                  _condition, _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim());
                            },
                      style: ElevatedButton.styleFrom(backgroundColor: SelmsColors.ink, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 10)),
                      child: _confirming
                          ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Text('Confirm return', style: TextStyle(fontSize: 12.5)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
