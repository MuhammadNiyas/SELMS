// lib/screens/edit_equipment_screen.dart

import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../models/equipment.dart';
import '../services/api_client.dart';
import '../theme/selms_colors.dart';
import '../widgets/form_fields.dart';

class EditEquipmentScreen extends StatefulWidget {
  const EditEquipmentScreen({super.key, required this.apiBaseUrl, required this.itToken, required this.equipmentId});

  final String apiBaseUrl;
  final String itToken;
  final String equipmentId;

  @override
  State<EditEquipmentScreen> createState() => _EditEquipmentScreenState();
}

class _EditEquipmentScreenState extends State<EditEquipmentScreen> {
  late final ApiClient _api = ApiClient(baseUrl: widget.apiBaseUrl, hrToken: widget.itToken);

  final _name = TextEditingController();
  final _brand = TextEditingController();
  final _model = TextEditingController();
  final _serialNumber = TextEditingController();
  final _assetTag = TextEditingController();
  final _ram = TextEditingController();
  final _storage = TextEditingController();
  final _colorMarks = TextEditingController();
  final _softwareLicenses = TextEditingController();
  final _accessoriesIncluded = TextEditingController();
  final _purchasePrice = TextEditingController();
  final _vendor = TextEditingController();
  final _notes = TextEditingController();
  final _newTypeCtrl = TextEditingController();

  String _condition = 'New';
  String _status = 'available';
  DateTime? _purchaseDate;
  DateTime? _warrantyExpiry;
  Uint8List? _newPhotoBytes;
  String? _existingPhotoUrl;

  final Map<String, IconData> _typeIcons = {
    'Laptop': Icons.laptop_mac_outlined,
    'Phone': Icons.smartphone_outlined,
    'Headphone': Icons.headphones_outlined,
    'Monitor': Icons.desktop_windows_outlined,
    'Mouse': Icons.mouse_outlined,
    'Keyboard': Icons.keyboard_outlined,
  };
  List<String> _types = [];
  String? _selectedType;
  bool _showAddType = false;

  static const _conditions = ['New', 'Good', 'Damaged'];
  static const _statuses = ['available', 'assigned', 'returned', 'under_repair', 'retired', 'lost'];

  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in [
      _name, _brand, _model, _serialNumber, _assetTag, _ram, _storage, _colorMarks,
      _softwareLicenses, _accessoriesIncluded, _purchasePrice, _vendor, _notes, _newTypeCtrl,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final types = await _api.listEquipmentTypes();
      final e = await _api.getEquipment(widget.equipmentId);
      if (!mounted) return;
      setState(() {
        _types = types.contains(e.type) ? types : [...types, e.type];
        _selectedType = e.type;
        _name.text = e.name;
        _brand.text = e.brand ?? '';
        _model.text = e.model ?? '';
        _serialNumber.text = e.serialNumber;
        _assetTag.text = e.assetTag ?? '';
        _ram.text = e.ram ?? '';
        _storage.text = e.storage ?? '';
        _colorMarks.text = e.colorMarks ?? '';
        _softwareLicenses.text = e.softwareLicenses ?? '';
        _condition = _conditions.contains(e.condition) ? e.condition! : 'New';
        _status = _statuses.contains(e.status) ? e.status : 'available';
        _accessoriesIncluded.text = e.accessoriesIncluded ?? '';
        _purchasePrice.text = e.purchasePrice != null ? formatThousands(e.purchasePrice!.toStringAsFixed(0)) : '';
        _vendor.text = e.vendor ?? '';
        _notes.text = e.notes ?? '';
        _purchaseDate = e.purchaseDate != null ? DateTime.tryParse(e.purchaseDate!) : null;
        _warrantyExpiry = e.warrantyExpiry != null ? DateTime.tryParse(e.warrantyExpiry!) : null;
        _existingPhotoUrl = e.photoUrl != null ? '${widget.apiBaseUrl}${e.photoUrl}' : null;
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

  void _confirmNewType() {
    final value = _newTypeCtrl.text.trim();
    if (value.isEmpty) return;
    setState(() {
      if (!_types.contains(value)) _types.add(value);
      _selectedType = value;
      _newTypeCtrl.clear();
      _showAddType = false;
    });
  }

  Future<void> _pickDate({required bool isWarranty}) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: (isWarranty ? _warrantyExpiry : _purchaseDate) ?? now,
      firstDate: DateTime(now.year - 15),
      lastDate: DateTime(now.year + 15),
    );
    if (picked == null) return;
    setState(() {
      if (isWarranty) {
        _warrantyExpiry = picked;
      } else {
        _purchaseDate = picked;
      }
    });
  }

  String _formatDate(DateTime? d) =>
      d == null ? '' : '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  String _statusLabel(String s) => s == 'under_repair' ? 'Under repair' : s[0].toUpperCase() + s.substring(1);

  Future<void> _save() async {
    if (_name.text.trim().isEmpty || _selectedType == null || _serialNumber.text.trim().isEmpty) {
      setState(() => _error = 'Equipment name, type, and serial number are required.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await _api.updateEquipment(widget.equipmentId, {
        'name': _name.text.trim(),
        'type': _selectedType,
        'brand': _brand.text.trim(),
        'model': _model.text.trim(),
        'serial_number': _serialNumber.text.trim(),
        'asset_tag': _assetTag.text.trim(),
        'ram': _ram.text.trim(),
        'storage': _storage.text.trim(),
        'color_marks': _colorMarks.text.trim(),
        'software_licenses': _softwareLicenses.text.trim(),
        'condition': _condition,
        'status': _status,
        'accessories_included': _accessoriesIncluded.text.trim(),
        'purchase_date': _purchaseDate?.toIso8601String(),
        'purchase_price': num.tryParse(_purchasePrice.text.replaceAll(',', '').trim()),
        'vendor': _vendor.text.trim(),
        'warranty_expiry': _warrantyExpiry?.toIso8601String(),
        'notes': _notes.text.trim(),
      });

      if (_newPhotoBytes != null) {
        try {
          await _api.uploadEquipmentPhoto(widget.equipmentId, _newPhotoBytes!);
        } catch (_) {
          // Best-effort — a failed photo upload shouldn't undo the rest of the save.
        }
      }

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = e.toString();
      });
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
        title: const Text('Edit equipment', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 440),
                  child: Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SquarePhotoField(
                          imageBytes: _newPhotoBytes,
                          existingImageUrl: _existingPhotoUrl,
                          icon: _typeIcons[_selectedType] ?? Icons.inventory_2_outlined,
                          onChanged: (bytes) => setState(() => _newPhotoBytes = bytes),
                        ),

                        _sectionHeader('Identification', 'What this item is and how to find it later.'),
                        _label('Equipment name'),
                        TextField(controller: _name, style: const TextStyle(fontSize: 13)),
                        const SizedBox(height: 14),

                        _label('Type'),
                        SizedBox(
                          height: 64,
                          child: ListView(
                            scrollDirection: Axis.horizontal,
                            children: [..._types.map(_typeChip), _addTypeChip()],
                          ),
                        ),
                        if (_showAddType) ...[
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _newTypeCtrl,
                                  autofocus: true,
                                  decoration: const InputDecoration(hintText: 'New type name'),
                                  style: const TextStyle(fontSize: 12.5),
                                  onSubmitted: (_) => _confirmNewType(),
                                ),
                              ),
                              const SizedBox(width: 8),
                              InkWell(
                                onTap: _confirmNewType,
                                borderRadius: BorderRadius.circular(8),
                                child: Container(
                                  width: 36,
                                  height: 36,
                                  decoration: BoxDecoration(color: SelmsColors.ink, borderRadius: BorderRadius.circular(8)),
                                  child: const Icon(Icons.check, size: 16, color: Colors.white),
                                ),
                              ),
                            ],
                          ),
                        ],
                        const SizedBox(height: 14),

                        Row(children: [
                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            _label('Brand'),
                            TextField(controller: _brand, style: const TextStyle(fontSize: 13)),
                          ])),
                          const SizedBox(width: 12),
                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            _label('Model'),
                            TextField(controller: _model, style: const TextStyle(fontSize: 13)),
                          ])),
                        ]),
                        const SizedBox(height: 14),

                        Row(children: [
                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            _label('Serial number'),
                            TextField(controller: _serialNumber, style: const TextStyle(fontSize: 13)),
                          ])),
                          const SizedBox(width: 12),
                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            _label('Asset tag'),
                            TextField(controller: _assetTag, style: const TextStyle(fontSize: 13)),
                          ])),
                        ]),
                        const SizedBox(height: 14),

                        Row(children: [
                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            _label('RAM', optional: true),
                            TextField(controller: _ram, style: const TextStyle(fontSize: 13)),
                          ])),
                          const SizedBox(width: 12),
                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            _label('Storage', optional: true),
                            TextField(controller: _storage, style: const TextStyle(fontSize: 13)),
                          ])),
                        ]),
                        const SizedBox(height: 14),

                        Row(children: [
                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            _label('Color / marks', optional: true),
                            TextField(controller: _colorMarks, style: const TextStyle(fontSize: 13)),
                          ])),
                          const SizedBox(width: 12),
                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            _label('Software / licenses', optional: true),
                            TextField(controller: _softwareLicenses, style: const TextStyle(fontSize: 13)),
                          ])),
                        ]),

                        _sectionHeader('Condition & status', 'Physical state and what comes with it.'),
                        _label('Condition'),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: _conditions.map((c) {
                            final isSelected = c == _condition;
                            return InkWell(
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
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 14),

                        // Unlike Add (always "Available"), edit lets HR/IT
                        // actually change the status — this is the one place
                        // that should happen, once the item already exists.
                        _label('Status'),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: _statuses.map((s) {
                            final isSelected = s == _status;
                            return InkWell(
                              onTap: () => setState(() => _status = s),
                              borderRadius: BorderRadius.circular(20),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  color: isSelected ? SelmsColors.accentBg : Colors.white,
                                  border: Border.all(color: isSelected ? SelmsColors.ink : SelmsColors.border),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(_statusLabel(s),
                                    style: TextStyle(
                                        fontSize: 11.5,
                                        fontWeight: isSelected ? FontWeight.w500 : FontWeight.w400,
                                        color: isSelected ? SelmsColors.ink : SelmsColors.textSecondary)),
                              ),
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 14),

                        _label('Accessories included', optional: true),
                        TextField(controller: _accessoriesIncluded, style: const TextStyle(fontSize: 13)),

                        _sectionHeader('Purchase & warranty', 'For budgeting and repair coverage.'),
                        Row(children: [
                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            _label('Purchase date', optional: true),
                            InkWell(
                              onTap: () => _pickDate(isWarranty: false),
                              child: InputDecorator(
                                decoration: const InputDecoration(
                                  isDense: true,
                                  contentPadding: EdgeInsets.symmetric(vertical: 8),
                                ),
                                child: Text(_purchaseDate == null ? 'dd/mm/yyyy' : _formatDate(_purchaseDate),
                                    style: TextStyle(fontSize: 13, color: _purchaseDate == null ? SelmsColors.textMuted : SelmsColors.textPrimary)),
                              ),
                            ),
                          ])),
                          const SizedBox(width: 12),
                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            UnderlineCurrencyField(label: 'Purchase price', controller: _purchasePrice, optional: true),
                          ])),
                        ]),
                        const SizedBox(height: 14),

                        _label('Vendor / supplier', optional: true),
                        TextField(controller: _vendor, style: const TextStyle(fontSize: 13)),
                        const SizedBox(height: 14),

                        _label('Warranty expiry', optional: true),
                        InkWell(
                          onTap: () => _pickDate(isWarranty: true),
                          child: InputDecorator(
                            decoration: const InputDecoration(),
                            child: Text(_warrantyExpiry == null ? 'dd/mm/yyyy' : _formatDate(_warrantyExpiry),
                                style: TextStyle(fontSize: 13, color: _warrantyExpiry == null ? SelmsColors.textMuted : SelmsColors.textPrimary)),
                          ),
                        ),

                        _sectionHeader('Notes', ''),
                        TextField(controller: _notes, maxLines: 3, style: const TextStyle(fontSize: 13)),

                        if (_error != null) ...[
                          const SizedBox(height: 12),
                          Text(_error!, style: const TextStyle(color: SelmsColors.rose, fontSize: 12)),
                        ],
                        const SizedBox(height: 20),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: _saving ? null : _save,
                            style: ElevatedButton.styleFrom(backgroundColor: SelmsColors.ink, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 12)),
                            child: _saving
                                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                : const Text('Save changes', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
    );
  }

  Widget _sectionHeader(String title, String subtitle) {
    return Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Divider(height: 1, color: SelmsColors.border),
          const SizedBox(height: 16),
          Text(title, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: SelmsColors.textPrimary)),
          if (subtitle.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(subtitle, style: const TextStyle(fontSize: 10.5, color: SelmsColors.textMuted)),
            ),
        ],
      ),
    );
  }

  Widget _label(String text, {bool optional = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: RichText(
        text: TextSpan(
          text: text,
          style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w500, color: SelmsColors.textSecondary),
          children: optional
              ? const [TextSpan(text: '  (optional)', style: TextStyle(fontWeight: FontWeight.w400, color: SelmsColors.textMuted))]
              : null,
        ),
      ),
    );
  }

  Widget _typeChip(String type) {
    final isSelected = type == _selectedType;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: InkWell(
        onTap: () => setState(() => _selectedType = type),
        borderRadius: BorderRadius.circular(10),
        child: Container(
          width: 62,
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSelected ? SelmsColors.accentBg : Colors.white,
            border: Border.all(color: isSelected ? SelmsColors.ink : SelmsColors.border),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            children: [
              Icon(_typeIcons[type] ?? Icons.inventory_2_outlined, size: 17, color: isSelected ? SelmsColors.ink : SelmsColors.textSecondary),
              const SizedBox(height: 5),
              Text(type, textAlign: TextAlign.center, overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 9.5, fontWeight: isSelected ? FontWeight.w500 : FontWeight.w400, color: isSelected ? SelmsColors.ink : SelmsColors.textSecondary)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _addTypeChip() {
    return InkWell(
      onTap: () => setState(() => _showAddType = true),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: 62,
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(color: const Color(0xFFF9FAFB), border: Border.all(color: SelmsColors.border), borderRadius: BorderRadius.circular(10)),
        child: const Column(children: [
          Icon(Icons.add, size: 17, color: SelmsColors.textSecondary),
          SizedBox(height: 5),
          Text('Add new', style: TextStyle(fontSize: 9.5, color: SelmsColors.textSecondary)),
        ]),
      ),
    );
  }
}
