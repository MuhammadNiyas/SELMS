// lib/screens/it_products_screen.dart
//
// Assign flow: the "Assign to employee" button below the table has three
// states — (1) default, no checkboxes; (2) clicked once, checkboxes appear
// on every Available row, label unchanged; (3) once 1+ items are ticked,
// they show as removable chips inside the search bar and the button label
// updates live with the count. Clicking it in state 3 navigates to
// AssignEmployeeScreen with those items pre-loaded.

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/equipment.dart';
import '../services/api_client.dart';
import '../theme/selms_colors.dart';
import '../widgets/app_shell.dart' show AppShell, SelmsRoute, TopBarActions;
import '../widgets/employee_avatar.dart';
import '../widgets/it_app_shell.dart';
import 'add_equipment_screen.dart';
import 'assign_employee_screen.dart';
import 'equipment_detail_screen.dart';

const _equipmentStatuses = ['available', 'assigned', 'returned', 'under_repair', 'retired', 'lost'];
const _equipmentConditions = ['New', 'Good', 'Damaged'];

class ItProductsScreen extends StatefulWidget {
  const ItProductsScreen({super.key, required this.apiBaseUrl, required this.itToken, this.viewOnly = false});

  final String apiBaseUrl;

  /// The signed-in user's token - IT's, or HR's when [viewOnly] is true.
  final String itToken;

  /// HR's view of the same list: inside HR's shell, search and filters only -
  /// no adding, assigning or exporting, and items open a read-only summary.
  final bool viewOnly;

  @override
  State<ItProductsScreen> createState() => _ItProductsScreenState();
}

class _ItProductsScreenState extends State<ItProductsScreen> {
  late final ApiClient _api = ApiClient(baseUrl: widget.apiBaseUrl, hrToken: widget.itToken);
  final _searchCtrl = TextEditingController();

  List<String> _types = [];
  String? _type;
  String? _status;
  String? _condition;

  List<Equipment> _items = [];
  bool _loading = true;
  String? _error;

  bool _selecting = false;
  final Set<String> _selectedIds = {};

  final _filterButtonKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _loadTypesThenItems();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  int get _activeFilterCount => [_type, _status, _condition].where((v) => v != null).length;

  Future<void> _loadTypesThenItems() async {
    try {
      final types = await _api.listEquipmentTypes();
      if (!mounted) return;
      setState(() => _types = types);
    } catch (_) {
      // Non-fatal — the filter dropdown just won't have options if this fails.
    }
    await _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await _api.listEquipment(
        query: _searchCtrl.text,
        type: _type,
        status: _status,
        condition: _condition,
      );
      if (!mounted) return;
      setState(() {
        _items = items;
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

  Future<void> _exportExcel() async {
    final params = <String, String>{'token': widget.itToken};
    if (_searchCtrl.text.trim().isNotEmpty) params['q'] = _searchCtrl.text.trim();
    if (_type != null) params['type'] = _type!;
    if (_status != null) params['status'] = _status!;
    if (_condition != null) params['condition'] = _condition!;

    final uri = Uri.parse('${widget.apiBaseUrl}/api/equipment/export').replace(queryParameters: params);
    final ok = await launchUrl(uri, mode: LaunchMode.platformDefault);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Could not start the export download.')));
    }
  }

  void _openFilterPanel() async {
    final renderBox = _filterButtonKey.currentContext!.findRenderObject() as RenderBox;
    final offset = renderBox.localToGlobal(Offset.zero);
    final size = renderBox.size;

    String? type = _type;
    String? status = _status;
    String? condition = _condition;

    await showMenu<void>(
      context: context,
      position: RelativeRect.fromLTRB(
        offset.dx,
        offset.dy + size.height + 6,
        offset.dx + 260,
        offset.dy + size.height + 6,
      ),
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      items: [
        PopupMenuItem<void>(
          enabled: false,
          padding: EdgeInsets.zero,
          child: StatefulBuilder(
            builder: (context, setMenuState) {
              return Container(
                width: 230,
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _filterDropdown('Type', type, _types, (v) => setMenuState(() => type = v)),
                    const SizedBox(height: 12),
                    _filterDropdown(
                        'Status', status, _equipmentStatuses, (v) => setMenuState(() => status = v),
                        display: _statusLabel),
                    const SizedBox(height: 12),
                    _filterDropdown('Condition', condition, _equipmentConditions,
                        (v) => setMenuState(() => condition = v)),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => setMenuState(() {
                              type = null;
                              status = null;
                              condition = null;
                            }),
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: SelmsColors.border),
                              padding: const EdgeInsets.symmetric(vertical: 8),
                            ),
                            child: const Text('Clear', style: TextStyle(fontSize: 12)),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () {
                              setState(() {
                                _type = type;
                                _status = status;
                                _condition = condition;
                              });
                              Navigator.of(context).pop();
                              _load();
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: SelmsColors.ink,
                              foregroundColor: Colors.white,
                              elevation: 0,
                              padding: const EdgeInsets.symmetric(vertical: 8),
                            ),
                            child: const Text('Apply', style: TextStyle(fontSize: 12)),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  String _statusLabel(String s) => s == 'under_repair' ? 'Under repair' : s[0].toUpperCase() + s.substring(1);

  Widget _filterDropdown(String label, String? value, List<String> options, ValueChanged<String?> onChanged,
      {String Function(String)? display}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label.toUpperCase(),
            style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w500, color: Colors.black45)),
        const SizedBox(height: 6),
        DropdownButtonFormField<String>(
          initialValue: value,
          isExpanded: true,
          hint: Text('All ${label.toLowerCase()}s', style: const TextStyle(fontSize: 12.5)),
          items: options
              .map((o) => DropdownMenuItem(
                  value: o, child: Text(display != null ? display(o) : o, style: const TextStyle(fontSize: 12.5))))
              .toList(),
          onChanged: onChanged,
          decoration: InputDecoration(
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: SelmsColors.border),
            ),
          ),
        ),
      ],
    );
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

  void _startSelecting() => setState(() => _selecting = true);

  void _cancelSelecting() => setState(() {
        _selecting = false;
        _selectedIds.clear();
      });

  void _toggleSelected(String id) => setState(() {
        if (_selectedIds.contains(id)) {
          _selectedIds.remove(id);
        } else {
          _selectedIds.add(id);
        }
      });

  Future<void> _goToAssign() async {
    final selectedItems = _items.where((e) => _selectedIds.contains(e.id)).toList();
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => AssignEmployeeScreen(
          apiBaseUrl: widget.apiBaseUrl,
          itToken: widget.itToken,
          equipmentItems: selectedItems,
        ),
      ),
    );
    if (!mounted) return;
    setState(() {
      _selecting = false;
      _selectedIds.clear();
    });
    if (result == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    final content = _buildContent();
    if (widget.viewOnly) {
      return AppShell(
        apiBaseUrl: widget.apiBaseUrl,
        hrToken: widget.itToken,
        activeRoute: SelmsRoute.products,
        child: content,
      );
    }
    return ItAppShell(
      apiBaseUrl: widget.apiBaseUrl,
      itToken: widget.itToken,
      activeRoute: ItRoute.products,
      child: content,
    );
  }

  Widget _buildContent() {
    final selectedItems = _items.where((e) => _selectedIds.contains(e.id)).toList();
    return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Products',
                          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: SelmsColors.textPrimary)),
                      Text('${_items.length} equipment items${widget.viewOnly ? ' · view only' : ''}',
                          style: const TextStyle(fontSize: 12, color: SelmsColors.textMuted)),
                    ],
                  ),
                ),
                const TopBarActions(),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    constraints: const BoxConstraints(maxWidth: 420),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8)),
                    child: Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        const Padding(
                          padding: EdgeInsets.only(left: 2),
                          child: Icon(Icons.search, size: 15, color: SelmsColors.textMuted),
                        ),
                        ...selectedItems.map((e) => Chip(
                              label: Text(e.name, style: const TextStyle(fontSize: 11.5)),
                              backgroundColor: SelmsColors.accentBg,
                              deleteIcon: const Icon(Icons.close, size: 13),
                              onDeleted: () => _toggleSelected(e.id),
                              visualDensity: VisualDensity.compact,
                              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              padding: const EdgeInsets.symmetric(horizontal: 2),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6), side: BorderSide.none),
                            )),
                        SizedBox(
                          width: selectedItems.isEmpty ? 200 : 140,
                          child: TextField(
                            controller: _searchCtrl,
                            onChanged: (_) => _load(),
                            decoration: InputDecoration(
                              border: InputBorder.none,
                              isDense: true,
                              hintText: selectedItems.isEmpty ? 'Search equipment...' : 'Search or tick more...',
                              hintStyle: const TextStyle(fontSize: 12.5, color: SelmsColors.textMuted),
                            ),
                            style: const TextStyle(fontSize: 12.5),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                InkWell(
                  key: _filterButtonKey,
                  onTap: _openFilterPanel,
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.all(9),
                    decoration: BoxDecoration(color: SelmsColors.ink, borderRadius: BorderRadius.circular(8)),
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        const Icon(Icons.filter_list, size: 15, color: Colors.white),
                        if (_activeFilterCount > 0)
                          Positioned(
                            right: -6,
                            top: -6,
                            child: Container(
                              padding: const EdgeInsets.all(3),
                              decoration: const BoxDecoration(color: SelmsColors.rose, shape: BoxShape.circle),
                              child: Text('$_activeFilterCount',
                                  style: const TextStyle(fontSize: 8, color: Colors.white, fontWeight: FontWeight.w600)),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const Spacer(),
                OutlinedButton.icon(
                  onPressed: _exportExcel,
                  icon: const Icon(Icons.table_chart_outlined, size: 16, color: Colors.white),
                  label: const Text('Export Excel'),
                  style: OutlinedButton.styleFrom(
                    backgroundColor: const Color(0xFF16A34A),
                    foregroundColor: Colors.white,
                  ),
                ),
                if (!widget.viewOnly) ...[
                const SizedBox(width: 10),
                ElevatedButton.icon(
                  onPressed: () {
                    Navigator.of(context)
                        .push(MaterialPageRoute(
                          builder: (_) => AddEquipmentScreen(apiBaseUrl: widget.apiBaseUrl, itToken: widget.itToken),
                        ))
                        .then((_) => _loadTypesThenItems());
                  },
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Add equipment', style: TextStyle(fontSize: 12.5)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: SelmsColors.ink,
                    foregroundColor: Colors.white,
                    elevation: 0,
                  ),
                ),
                ],
              ],
            ),
            const SizedBox(height: 16),
            Expanded(child: _buildBody()),
            if (!widget.viewOnly) ...[
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (_selecting) ...[
                  TextButton(
                    onPressed: _cancelSelecting,
                    child: const Text('Cancel', style: TextStyle(fontSize: 12, color: SelmsColors.textSecondary)),
                  ),
                  const SizedBox(width: 8),
                ],
                ElevatedButton.icon(
                  onPressed: (_selecting && _selectedIds.isEmpty) ? null : (_selecting ? _goToAssign : _startSelecting),
                  icon: const Icon(Icons.person_add_alt_1_outlined, size: 15),
                  label: Text(
                    _selecting && _selectedIds.isNotEmpty
                        ? 'Assign ${_selectedIds.length} item${_selectedIds.length == 1 ? '' : 's'} to employee'
                        : 'Assign to employee',
                    style: const TextStyle(fontSize: 12.5),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: SelmsColors.ink,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: SelmsColors.ink.withValues(alpha: 0.5),
                    disabledForegroundColor: Colors.white70,
                    elevation: 0,
                  ),
                ),
              ],
            ),
            ],
          ],
        ),
    );
  }

  Widget _buildBody() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(child: Text(_error!, style: const TextStyle(color: SelmsColors.rose, fontSize: 13)));
    }
    if (_items.isEmpty) {
      return const Center(
          child: Text('No equipment found.', style: TextStyle(fontSize: 13, color: SelmsColors.textMuted)));
    }
    return Container(
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            child: Row(
              children: [
                if (_selecting) const SizedBox(width: 28),
                const Expanded(flex: 2, child: Text('NAME', style: TextStyle(fontSize: 10.5, color: SelmsColors.textMuted, fontWeight: FontWeight.w500))),
                const Expanded(child: Text('TYPE', style: TextStyle(fontSize: 10.5, color: SelmsColors.textMuted, fontWeight: FontWeight.w500))),
                const Expanded(child: Text('SERIAL NO.', style: TextStyle(fontSize: 10.5, color: SelmsColors.textMuted, fontWeight: FontWeight.w500))),
                const Expanded(child: Text('STATUS', style: TextStyle(fontSize: 10.5, color: SelmsColors.textMuted, fontWeight: FontWeight.w500))),
                const Expanded(flex: 2, child: SizedBox()),
              ],
            ),
          ),
          const Divider(height: 1, color: SelmsColors.border),
          Expanded(
            child: ListView.separated(
              itemCount: _items.length,
              separatorBuilder: (_, __) => const Divider(height: 1, color: SelmsColors.border),
              itemBuilder: (context, i) {
                final e = _items[i];
                final isSelectable = e.status == 'available';
                final isChecked = _selectedIds.contains(e.id);

                return Container(
                  color: isChecked ? SelmsColors.accentBg : Colors.transparent,
                  child: Row(
                    children: [
                      if (_selecting)
                        SizedBox(
                          width: 28,
                          child: isSelectable
                              ? Checkbox(
                                  value: isChecked,
                                  onChanged: (_) => _toggleSelected(e.id),
                                  activeColor: SelmsColors.ink,
                                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                )
                              : const Icon(Icons.block, size: 14, color: SelmsColors.border),
                        ),
                      Expanded(
                        child: InkWell(
                          onTap: () {
                            Navigator.of(context)
                                .push(MaterialPageRoute(
                                  builder: (_) => EquipmentDetailScreen(
                                    apiBaseUrl: widget.apiBaseUrl,
                                    itToken: widget.itToken,
                                    equipmentId: e.id,
                                    viewOnly: widget.viewOnly,
                                  ),
                                ))
                                .then((_) => _load());
                          },
                          child: Padding(
                            padding: EdgeInsets.only(left: _selecting ? 0 : 20, right: 20, top: 12, bottom: 12),
                            child: Row(
                              children: [
                                Expanded(
                                  flex: 2,
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 32,
                                        height: 32,
                                        clipBehavior: Clip.hardEdge,
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFF9FAFB),
                                          borderRadius: BorderRadius.circular(7),
                                          border: Border.all(color: SelmsColors.border),
                                        ),
                                        alignment: Alignment.center,
                                        child: (e.photoUrl != null && e.photoUrl!.isNotEmpty)
                                            ? Image.network('${widget.apiBaseUrl}${e.photoUrl}',
                                                fit: BoxFit.cover,
                                                width: 32,
                                                height: 32,
                                                errorBuilder: (_, _, _) => const Icon(Icons.inventory_2_outlined,
                                                    size: 14, color: SelmsColors.textMuted))
                                            : const Icon(Icons.inventory_2_outlined, size: 14, color: SelmsColors.textMuted),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Text(e.name,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(fontSize: 12.5, color: SelmsColors.textPrimary)),
                                      ),
                                    ],
                                  ),
                                ),
                                Expanded(child: Text(e.type, style: const TextStyle(fontSize: 12, color: SelmsColors.textSecondary))),
                                Expanded(child: Text(e.serialNumber, style: const TextStyle(fontSize: 12, color: SelmsColors.textMuted))),
                                Expanded(
                                  child: Align(
                                    alignment: Alignment.centerLeft,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                                      decoration: BoxDecoration(color: _statusBg(e.status), borderRadius: BorderRadius.circular(20)),
                                      child: Text(
                                        _statusLabel(e.status),
                                        style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w500, color: _statusFg(e.status)),
                                      ),
                                    ),
                                  ),
                                ),
                                Expanded(
                                  flex: 2,
                                  child: e.assignedToEmployeeName == null
                                      ? const SizedBox()
                                      : Row(
                                          children: [
                                            EmployeeAvatar(
                                              apiBaseUrl: widget.apiBaseUrl,
                                              name: e.assignedToEmployeeName!,
                                              photoUrl: e.assignedToEmployeePhotoUrl,
                                              size: 24,
                                            ),
                                            const SizedBox(width: 8),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Text(e.assignedToEmployeeName!,
                                                      overflow: TextOverflow.ellipsis,
                                                      style: const TextStyle(fontSize: 11.5, color: SelmsColors.textPrimary)),
                                                  if (e.assignedToEmployeeId != null)
                                                    Text(e.assignedToEmployeeId!,
                                                        style: const TextStyle(fontSize: 9.5, color: SelmsColors.textMuted)),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
