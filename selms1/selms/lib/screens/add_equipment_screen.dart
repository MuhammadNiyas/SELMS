// lib/screens/add_equipment_screen.dart

import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../services/api_client.dart';
import '../theme/selms_colors.dart';
import '../widgets/form_fields.dart';

class AddEquipmentScreen extends StatefulWidget {
  const AddEquipmentScreen({super.key, required this.apiBaseUrl, required this.itToken});

  final String apiBaseUrl;
  final String itToken;

  @override
  State<AddEquipmentScreen> createState() => _AddEquipmentScreenState();
}

class _AddEquipmentScreenState extends State<AddEquipmentScreen> {
  late final ApiClient _api = ApiClient(baseUrl: widget.apiBaseUrl, hrToken: widget.itToken);

  // Identification (specs merged in — no separate section)
  final _name = TextEditingController();
  final _brand = TextEditingController();
  final _model = TextEditingController();
  final _serialNumber = TextEditingController();
  final _assetTag = TextEditingController();
  final _ram = TextEditingController();
  final _storage = TextEditingController();
  final _colorMarks = TextEditingController();
  final _softwareLicenses = TextEditingController();

  // Condition & status
  String _condition = 'New';
  final _accessoriesIncluded = TextEditingController();

  // Purchase & warranty
  DateTime? _purchaseDate;
  final _purchasePrice = TextEditingController();
  final _vendor = TextEditingController();
  DateTime? _warrantyExpiry;

  // Notes & photo
  final _notes = TextEditingController();
  Uint8List? _photoBytes;

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
  final _newTypeCtrl = TextEditingController();

  bool _loadingTypes = true;
  bool _saving = false;
  String? _error;

  static const _conditions = ['New', 'Good', 'Damaged'];

  @override
  void initState() {
    super.initState();
    _loadTypes();
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

  Future<void> _loadTypes() async {
    try {
      final types = await _api.listEquipmentTypes();
      if (!mounted) return;
      setState(() {
        _types = types;
        _selectedType = types.isNotEmpty ? types.first : null;
        _loadingTypes = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _types = _typeIcons.keys.toList();
        _selectedType = _types.first;
        _loadingTypes = false;
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
      initialDate: now,
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
      final created = await _api.createEquipment(
        name: _name.text.trim(),
        type: _selectedType!,
        serialNumber: _serialNumber.text.trim(),
        brand: _brand.text.trim().isEmpty ? null : _brand.text.trim(),
        model: _model.text.trim().isEmpty ? null : _model.text.trim(),
        assetTag: _assetTag.text.trim().isEmpty ? null : _assetTag.text.trim(),
        ram: _ram.text.trim().isEmpty ? null : _ram.text.trim(),
        storage: _storage.text.trim().isEmpty ? null : _storage.text.trim(),
        colorMarks: _colorMarks.text.trim().isEmpty ? null : _colorMarks.text.trim(),
        softwareLicenses: _softwareLicenses.text.trim().isEmpty ? null : _softwareLicenses.text.trim(),
        condition: _condition,
        accessoriesIncluded: _accessoriesIncluded.text.trim().isEmpty ? null : _accessoriesIncluded.text.trim(),
        purchaseDate: _purchaseDate?.toIso8601String(),
        purchasePrice: num.tryParse(_purchasePrice.text.replaceAll(',', '').trim()),
        vendor: _vendor.text.trim().isEmpty ? null : _vendor.text.trim(),
        warrantyExpiry: _warrantyExpiry?.toIso8601String(),
        notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
      );

      if (_photoBytes != null) {
        try {
          await _api.uploadEquipmentPhoto(created.id, _photoBytes!);
        } catch (_) {
          // Best-effort — a failed photo upload shouldn't undo the record just created.
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
        title: const Text('Add equipment', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
      ),
      body: Center(
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
                    imageBytes: _photoBytes,
                    icon: _typeIcons[_selectedType] ?? Icons.inventory_2_outlined,
                    onChanged: (bytes) => setState(() => _photoBytes = bytes),
                  ),

                  _sectionHeader('Identification', 'What this item is and how to find it later.'),
                  _label('Equipment name'),
                  TextField(controller: _name, decoration: const InputDecoration(hintText: 'e.g. MacBook Pro 14"'), style: const TextStyle(fontSize: 13)),
                  const SizedBox(height: 14),

                  _label('Type'),
                  _loadingTypes
                      ? const Padding(
                          padding: EdgeInsets.symmetric(vertical: 12),
                          child: SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                        )
                      : SizedBox(
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
                      TextField(controller: _brand, decoration: const InputDecoration(hintText: 'Apple'), style: const TextStyle(fontSize: 13)),
                    ])),
                    const SizedBox(width: 12),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      _label('Model'),
                      TextField(controller: _model, decoration: const InputDecoration(hintText: 'A2779'), style: const TextStyle(fontSize: 13)),
                    ])),
                  ]),
                  const SizedBox(height: 14),

                  Row(children: [
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      _label('Serial number'),
                      TextField(controller: _serialNumber, decoration: const InputDecoration(hintText: 'SN-88213'), style: const TextStyle(fontSize: 13)),
                    ])),
                    const SizedBox(width: 12),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      _label('Asset tag'),
                      TextField(controller: _assetTag, decoration: const InputDecoration(hintText: 'IT-0142'), style: const TextStyle(fontSize: 13)),
                    ])),
                  ]),
                  const SizedBox(height: 14),

                  // RAM + Storage — right after Serial number/Asset tag, as requested
                  Row(children: [
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      _label('RAM', optional: true),
                      TextField(controller: _ram, decoration: const InputDecoration(hintText: 'e.g. 16GB'), style: const TextStyle(fontSize: 13)),
                    ])),
                    const SizedBox(width: 12),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      _label('Storage', optional: true),
                      TextField(controller: _storage, decoration: const InputDecoration(hintText: 'e.g. 512GB SSD'), style: const TextStyle(fontSize: 13)),
                    ])),
                  ]),
                  const SizedBox(height: 14),

                  Row(children: [
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      _label('Color / marks', optional: true),
                      TextField(controller: _colorMarks, decoration: const InputDecoration(hintText: 'e.g. Space grey'), style: const TextStyle(fontSize: 13)),
                    ])),
                    const SizedBox(width: 12),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      _label('Software / licenses', optional: true),
                      TextField(controller: _softwareLicenses, decoration: const InputDecoration(hintText: 'e.g. MS Office 365'), style: const TextStyle(fontSize: 13)),
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

                  _label('Status'),
                  SizedBox(
                    width: double.infinity,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 10),
                      decoration: BoxDecoration(
                          color: const Color(0xFFE1F5EE), borderRadius: BorderRadius.circular(8)),
                      child: const Text('Available', style: TextStyle(fontSize: 12.5, color: Color(0xFF085041))),
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.only(top: 4),
                    child: Text('New items default to Available', style: TextStyle(fontSize: 10, color: SelmsColors.textMuted)),
                  ),
                  const SizedBox(height: 14),

                  _label('Accessories included', optional: true),
                  TextField(controller: _accessoriesIncluded, decoration: const InputDecoration(hintText: 'e.g. Charger, sleeve case'), style: const TextStyle(fontSize: 13)),

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
                      // Same RM-prefixed, auto-comma-formatted field used for
                      // employee base salary — same treatment for consistency.
                      UnderlineCurrencyField(label: 'Purchase price', controller: _purchasePrice, optional: true),
                    ])),
                  ]),
                  const SizedBox(height: 14),

                  _label('Vendor / supplier', optional: true),
                  TextField(controller: _vendor, decoration: const InputDecoration(hintText: 'e.g. Machines Sdn Bhd'), style: const TextStyle(fontSize: 13)),
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
                  TextField(
                    controller: _notes,
                    maxLines: 3,
                    decoration: const InputDecoration(hintText: 'Anything worth flagging...'),
                    style: const TextStyle(fontSize: 13),
                  ),

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
                          : const Text('Add equipment', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
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
