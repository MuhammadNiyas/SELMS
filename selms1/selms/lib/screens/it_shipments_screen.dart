// lib/screens/it_shipments_screen.dart
//
// IT's view of equipment going out to / coming back from remote
// employees by Pos Malaysia. SELMS can't create the Pos order (e-Connote is
// a self-service website with no public API), so each shipment card gives IT
// everything to fill that form in without retyping - recipient details with
// copy buttons, the item list, a button that opens e-Connote - and then
// records the result: the Pos reference number and a screenshot of the QR
// code Pos hands back, plus the status through to delivery.
//
// Two views share one screen: "Onboarding" (equipment to a new hire) and
// "Offboarding" (equipment returned by a leaver).

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/api_client.dart';
import '../widgets/employee_avatar.dart';
import '../theme/selms_colors.dart';
import '../widgets/app_shell.dart' show TopBarActions;
import '../widgets/it_app_shell.dart';

/// IT's Shipments tab: the full, editable page inside IT's own sidebar shell.
class ItShipmentsScreen extends StatelessWidget {
  const ItShipmentsScreen({super.key, required this.apiBaseUrl, required this.itToken});

  final String apiBaseUrl;
  final String itToken;

  @override
  Widget build(BuildContext context) {
    return ItAppShell(
      apiBaseUrl: apiBaseUrl,
      itToken: itToken,
      activeRoute: ItRoute.shipments,
      child: ShipmentsPage(apiBaseUrl: apiBaseUrl, token: itToken),
    );
  }
}

/// The shipments page itself, shared by IT (editable) and HR (readOnly:
/// can see every parcel, its status and Pos reference, and track it, but
/// not change anything).
class ShipmentsPage extends StatefulWidget {
  const ShipmentsPage({super.key, required this.apiBaseUrl, required this.token, this.readOnly = false});

  final String apiBaseUrl;
  final String token;
  final bool readOnly;

  @override
  State<ShipmentsPage> createState() => _ShipmentsPageState();
}

class _ShipmentsPageState extends State<ShipmentsPage> {
  late final ApiClient _api = ApiClient(baseUrl: widget.apiBaseUrl, hrToken: widget.token);

  List<Map<String, dynamic>> _all = [];
  bool _loading = true;
  String? _error;
  String _direction = 'to_employee'; // to_employee | return
  String? _expandedId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final list = await _api.listShipments();
      if (!mounted) return;
      setState(() {
        _all = list;
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

  List<Map<String, dynamic>> get _inView => _all.where((s) => s['direction'] == _direction).toList();

  int _count(bool Function(String status) test) =>
      _inView.where((s) => test(s['status'] as String)).length;

  void _replace(Map<String, dynamic> updated) {
    setState(() {
      final i = _all.indexWhere((s) => s['_id'] == updated['_id']);
      if (i != -1) _all[i] = updated;
    });
  }

  Future<void> _newShipment() async {
    final created = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _NewShipmentDialog(api: _api, direction: _direction),
    );
    if (created == null || !mounted) return;
    await _load(silent: true);
    if (mounted) setState(() => _expandedId = created['_id'] as String);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Shipments',
                          style: TextStyle(
                              fontSize: 20, fontWeight: FontWeight.w600, color: SelmsColors.textPrimary)),
                      const SizedBox(height: 2),
                      Text(
                          widget.readOnly
                              ? 'Track equipment IT is posting to, and collecting from, remote employees.'
                              : 'Equipment posted to remote employees, and returned by leavers, via Pos Malaysia.',
                          style: const TextStyle(fontSize: 12.5, color: SelmsColors.textMuted)),
                    ],
                  ),
                ),
              ),
              OutlinedButton.icon(
                onPressed: _loading ? null : () => _load(),
                icon: const Icon(Icons.refresh, size: 15),
                label: const Text('Refresh', style: TextStyle(fontSize: 12)),
                style: OutlinedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: SelmsColors.textPrimary,
                  side: const BorderSide(color: SelmsColors.border),
                ),
              ),
              if (!widget.readOnly) ...[
                const SizedBox(width: 10),
                ElevatedButton.icon(
                  onPressed: _newShipment,
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('New shipment', style: TextStyle(fontSize: 12.5)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: SelmsColors.ink,
                    foregroundColor: Colors.white,
                    elevation: 0,
                  ),
                ),
              ],
              const SizedBox(width: 14),
              const TopBarActions(),
            ],
          ),
          const SizedBox(height: 18),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, style: const TextStyle(color: SelmsColors.rose, fontSize: 13)),
            const SizedBox(height: 10),
            OutlinedButton(onPressed: () => _load(), child: const Text('Try again')),
          ],
        ),
      );
    }

    final rows = _inView;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _summaryCard('To prepare', _count((s) => s == 'pending'), Icons.inventory_2_outlined,
                SelmsColors.statusOnboardingBg, SelmsColors.statusOnboardingText),
            const SizedBox(width: 12),
            _summaryCard('In transit', _count((s) => s == 'order_created' || s == 'dropped_off'),
                Icons.local_shipping_outlined, SelmsColors.accentBg, SelmsColors.ink),
            const SizedBox(width: 12),
            _summaryCard('Delivered', _count((s) => s == 'delivered'), Icons.check_circle_outline,
                SelmsColors.statusActiveBg, SelmsColors.statusActiveText),
          ],
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10)),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _segment('Onboarding · to employee', 'to_employee'),
              _segment('Offboarding · returns', 'return'),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: rows.isEmpty
              ? Container(
                  width: double.infinity,
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
                  child: _emptyState(),
                )
              : ListView.separated(
                  padding: const EdgeInsets.only(bottom: 24),
                  itemCount: rows.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (_, i) {
                    final s = rows[i];
                    final id = s['_id'] as String;
                    return _ShipmentCard(
                      key: ValueKey(id),
                      api: _api,
                      apiBaseUrl: widget.apiBaseUrl,
                      shipment: s,
                      readOnly: widget.readOnly,
                      expanded: _expandedId == id,
                      onToggle: () => setState(() => _expandedId = _expandedId == id ? null : id),
                      onChanged: _replace,
                      onDeleted: () {
                        setState(() {
                          _all.removeWhere((x) => x['_id'] == id);
                          if (_expandedId == id) _expandedId = null;
                        });
                      },
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _summaryCard(String label, int value, IconData icon, Color bg, Color fg) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10)),
              child: Icon(icon, size: 19, color: fg),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('$value',
                    style: const TextStyle(
                        fontSize: 22, fontWeight: FontWeight.w600, color: SelmsColors.textPrimary, height: 1.1)),
                const SizedBox(height: 2),
                Text(label, style: const TextStyle(fontSize: 11.5, color: SelmsColors.textMuted)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _segment(String label, String value) {
    final active = _direction == value;
    return InkWell(
      onTap: () => setState(() {
        _direction = value;
        _expandedId = null;
      }),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: active ? SelmsColors.ink : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w500,
                color: active ? Colors.white : SelmsColors.textSecondary)),
      ),
    );
  }

  Widget _emptyState() {
    final outgoing = _direction == 'to_employee';
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.local_shipping_outlined, size: 38, color: SelmsColors.textMuted),
            const SizedBox(height: 12),
            Text(outgoing ? 'No equipment shipments yet' : 'No equipment returns yet',
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: SelmsColors.textPrimary)),
            const SizedBox(height: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 380),
              child: Text(
                outgoing
                    ? 'After assigning equipment to a remote new hire, click "New shipment" to prepare their parcel.'
                    : 'When a remote employee leaves, click "New shipment" to arrange their equipment coming back.',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12.5, color: SelmsColors.textMuted, height: 1.4),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------

const _statusSteps = ['pending', 'order_created', 'dropped_off', 'delivered'];

String _statusLabel(String s) => switch (s) {
      'pending' => 'To prepare',
      'order_created' => 'Order created',
      'dropped_off' => 'Dropped at Pos',
      'delivered' => 'Delivered',
      'cancelled' => 'Cancelled',
      _ => s,
    };

Color _statusBg(String s) => switch (s) {
      'pending' => SelmsColors.statusOnboardingBg,
      'order_created' || 'dropped_off' => SelmsColors.accentBg,
      'delivered' => SelmsColors.statusActiveBg,
      _ => const Color(0xFFF3F4F6),
    };

Color _statusFg(String s) => switch (s) {
      'pending' => SelmsColors.statusOnboardingText,
      'order_created' || 'dropped_off' => SelmsColors.ink,
      'delivered' => SelmsColors.statusActiveText,
      _ => SelmsColors.textSecondary,
    };

/// One shipment: a summary row that expands into the working card.
class _ShipmentCard extends StatefulWidget {
  const _ShipmentCard({
    super.key,
    required this.api,
    required this.apiBaseUrl,
    required this.shipment,
    required this.readOnly,
    required this.expanded,
    required this.onToggle,
    required this.onChanged,
    required this.onDeleted,
  });

  final ApiClient api;
  final String apiBaseUrl;
  final Map<String, dynamic> shipment;
  final bool readOnly;
  final bool expanded;
  final VoidCallback onToggle;
  final void Function(Map<String, dynamic>) onChanged;
  final VoidCallback onDeleted;

  @override
  State<_ShipmentCard> createState() => _ShipmentCardState();
}

class _ShipmentCardState extends State<_ShipmentCard> {
  late final TextEditingController _refCtrl =
      TextEditingController(text: widget.shipment['pos_reference'] as String? ?? '');
  bool _busy = false;
  String? _error;

  Map<String, dynamic> get _s => widget.shipment;
  String get _id => _s['_id'] as String;
  String get _status => _s['status'] as String;
  bool get _isReturn => _s['direction'] == 'return';
  Map<String, dynamic> get _recipient => (_s['recipient'] as Map).cast<String, dynamic>();
  Map<String, dynamic> get _company => (_s['company'] as Map).cast<String, dynamic>();
  List<Map<String, dynamic>> get _items => ((_s['items'] as List?) ?? []).cast<Map<String, dynamic>>();

  @override
  void dispose() {
    _refCtrl.dispose();
    super.dispose();
  }

  Future<void> _run(Future<Map<String, dynamic>> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final updated = await action();
      if (!mounted) return;
      widget.onChanged(updated);
      setState(() => _busy = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _saveReference() =>
      _run(() => widget.api.updateShipment(_id, posReference: _refCtrl.text.trim()));

  Future<void> _setStatus(String status) => _run(() => widget.api.updateShipment(_id, status: status));

  Future<void> _pickQr() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 90);
    if (picked == null) return;
    await _run(() async {
      final bytes = await picked.readAsBytes();
      final name = picked.name.contains('.') ? picked.name : 'qr.png';
      final url = await widget.api.uploadShipmentQr(_id, bytes, name);
      return {..._s, 'qr_image_url': url};
    });
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this shipment?', style: TextStyle(fontSize: 16)),
        content: const Text('This removes the record from SELMS only. It does not cancel anything on the Pos site.',
            style: TextStyle(fontSize: 13)),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Keep')),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: SelmsColors.rose, foregroundColor: Colors.white),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await widget.api.deleteShipment(_id);
      if (mounted) widget.onDeleted();
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  Future<void> _copy(String label, String value) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$label copied.'), duration: const Duration(seconds: 1)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final name = _s['employee_name'] as String? ?? '';
    final itemsText = _items.isEmpty ? 'No items listed' : _items.map((i) => i['name']).join(', ');
    final ref = _s['pos_reference'] as String? ?? '';

    return Container(
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          InkWell(
            onTap: widget.onToggle,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              child: Row(
                children: [
                  EmployeeAvatar(
                    apiBaseUrl: widget.apiBaseUrl,
                    name: name,
                    photoUrl: (_s['recipient'] as Map?)?['profile_image_url'] as String?,
                    size: 36,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 3,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(name,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 13.5, fontWeight: FontWeight.w500, color: SelmsColors.textPrimary)),
                        Text('${_s['employee_id']} · ${_recipient['work_location_type'] ?? ''}',
                            style: const TextStyle(fontSize: 11.5, color: SelmsColors.textMuted)),
                      ],
                    ),
                  ),
                  Expanded(
                    flex: 4,
                    child: Text(itemsText,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12, color: SelmsColors.textSecondary)),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text(ref.isEmpty ? 'No reference yet' : ref,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 12,
                            color: ref.isEmpty ? SelmsColors.textMuted : SelmsColors.textPrimary,
                            fontWeight: ref.isEmpty ? FontWeight.w400 : FontWeight.w500)),
                  ),
                  _pill(_statusLabel(_status), _statusBg(_status), _statusFg(_status)),
                  const SizedBox(width: 10),
                  Icon(widget.expanded ? Icons.expand_less : Icons.expand_more,
                      size: 18, color: SelmsColors.textMuted),
                ],
              ),
            ),
          ),
          if (widget.expanded) ...[
            const Divider(height: 1, color: SelmsColors.border),
            Container(
              color: SelmsColors.fieldBg,
              padding: const EdgeInsets.all(18),
              child: _details(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _details() {
    final addressLine = [
      _recipient['address_line'],
      _recipient['postcode'],
      _recipient['state'],
    ].where((p) => p != null && '$p'.isNotEmpty).join(', ');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _progressSteps(),
        const SizedBox(height: 18),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // --- Who it's for (copy straight into the Pos form) ---
            Expanded(
              flex: 5,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _heading(_isReturn ? 'SEND TO (COMPANY)' : 'DELIVER TO'),
                  const SizedBox(height: 6),
                  if (_isReturn) ...[
                    _copyRow('Name', _company['name'] as String? ?? ''),
                    _copyRow('Phone', _company['phone'] as String? ?? ''),
                    _copyRow('Address', _company['address'] as String? ?? '',
                        emptyHint: 'Set COMPANY_ADDRESS in the backend .env'),
                    const SizedBox(height: 14),
                    _heading('FROM (EMPLOYEE)'),
                    const SizedBox(height: 6),
                  ],
                  _copyRow('Name', _recipient['name'] as String? ?? ''),
                  _copyRow('Phone', _recipient['phone'] as String? ?? ''),
                  _copyRow('Address', _recipient['address_line'] as String? ?? ''),
                  _copyRow('Postcode', _recipient['postcode'] as String? ?? ''),
                  _copyRow('State', _recipient['state'] as String? ?? ''),
                  if (addressLine.isNotEmpty)
                    TextButton.icon(
                      onPressed: () => _copy('Full address', addressLine),
                      icon: const Icon(Icons.copy_all, size: 14),
                      label: const Text('Copy full address', style: TextStyle(fontSize: 11.5)),
                    ),
                  const SizedBox(height: 10),
                  _heading('ITEMS IN THE PARCEL'),
                  const SizedBox(height: 6),
                  if (_items.isEmpty)
                    const Text('Nothing assigned yet — assign equipment first.',
                        style: TextStyle(fontSize: 12, color: SelmsColors.textMuted))
                  else
                    ..._items.map((i) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Row(
                            children: [
                              const Icon(Icons.inventory_2_outlined, size: 13, color: SelmsColors.textMuted),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  '${i['name']}${(i['asset_tag'] as String?)?.isNotEmpty == true ? '  ·  ${i['asset_tag']}' : ''}',
                                  style: const TextStyle(fontSize: 12.5, color: SelmsColors.textSecondary),
                                ),
                              ),
                            ],
                          ),
                        )),
                ],
              ),
            ),
            const SizedBox(width: 28),
            // --- The Pos order ---
            Expanded(
              flex: 5,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _heading('POS MALAYSIA ORDER'),
                  const SizedBox(height: 8),
                  if (!widget.readOnly) ...[
                    ElevatedButton.icon(
                      onPressed: () => launchUrl(Uri.parse(_s['pos_url'] as String),
                          mode: LaunchMode.externalApplication),
                      icon: const Icon(Icons.open_in_new, size: 14),
                      label: const Text('Open Pos e-Connote', style: TextStyle(fontSize: 12.5)),
                      style: ElevatedButton.styleFrom(
                          backgroundColor: SelmsColors.ink, foregroundColor: Colors.white, elevation: 0),
                    ),
                    const SizedBox(height: 4),
                    const Text('Create the order there, then save the reference and QR below.',
                        style: TextStyle(fontSize: 11, color: SelmsColors.textMuted)),
                    const SizedBox(height: 14),
                    const Text('Reference number',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: SelmsColors.textSecondary)),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _refCtrl,
                            onChanged: (_) => setState(() {}),
                            // Once the order is recorded, pressing Enter saves
                            // a corrected reference (there's no Save button).
                            onSubmitted: (_) {
                              if (_status != 'pending' && _refCtrl.text.trim().isNotEmpty) _saveReference();
                            },
                            style: const TextStyle(fontSize: 13),
                            decoration: const InputDecoration(isDense: true, hintText: 'e.g. the number Pos shows'),
                          ),
                        ),
                        const SizedBox(width: 6),
                        IconButton(
                          tooltip: 'Copy reference number',
                          onPressed: _refCtrl.text.trim().isEmpty
                              ? null
                              : () => _copy('Reference number', _refCtrl.text.trim()),
                          icon: const Icon(Icons.copy, size: 16),
                        ),
                      ],
                    ),
                  ] else
                    _copyRow('Reference', _s['pos_reference'] as String? ?? '', emptyHint: 'Not created yet'),
                  if ((_s['pos_reference'] as String? ?? '').isNotEmpty) ...[
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: _track,
                      icon: const Icon(Icons.travel_explore, size: 15),
                      label: const Text('Track on Pos', style: TextStyle(fontSize: 12.5)),
                    ),
                    const SizedBox(height: 4),
                    const Text('Copies the reference and opens Pos Malaysia tracking — paste it in if it isn\'t filled in.',
                        style: TextStyle(fontSize: 11, color: SelmsColors.textMuted)),
                  ],
                  if (!widget.readOnly || (_s['qr_image_url'] as String? ?? '').isNotEmpty) ...[
                    const SizedBox(height: 14),
                    const Text('QR code (screenshot from Pos)',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: SelmsColors.textSecondary)),
                    const SizedBox(height: 6),
                    _qrBlock(),
                  ],
                ],
              ),
            ),
          ],
        ),
        if (!widget.readOnly) ...[
          const SizedBox(height: 16),
          const Divider(height: 1, color: SelmsColors.border),
          const SizedBox(height: 10),
          Row(
            children: [
              ..._nextActions(),
              const Spacer(),
              if (_status != 'cancelled' && _status != 'delivered')
                TextButton(
                  onPressed: _busy ? null : () => _setStatus('cancelled'),
                  child: const Text('Cancel shipment', style: TextStyle(fontSize: 12, color: SelmsColors.textSecondary)),
                ),
              TextButton.icon(
                onPressed: _busy ? null : _delete,
                icon: const Icon(Icons.delete_outline, size: 15, color: SelmsColors.rose),
                label: const Text('Delete', style: TextStyle(fontSize: 12, color: SelmsColors.rose)),
              ),
            ],
          ),
        ],
        if (_error != null) ...[
          const SizedBox(height: 6),
          Text(_error!, style: const TextStyle(color: SelmsColors.rose, fontSize: 12)),
        ],
      ],
    );
  }

  /// The one or two sensible next clicks for the current status.
  List<Widget> _nextActions() {
    Widget go(String label, String status, {bool primary = true}) => Padding(
          padding: const EdgeInsets.only(right: 8),
          child: primary
              ? ElevatedButton(
                  onPressed: _busy ? null : () => _setStatus(status),
                  style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF16A34A), foregroundColor: Colors.white, elevation: 0),
                  child: Text(label, style: const TextStyle(fontSize: 12.5)),
                )
              : OutlinedButton(
                  onPressed: _busy ? null : () => _setStatus(status),
                  child: Text(label, style: const TextStyle(fontSize: 12.5)),
                ),
        );

    // "Create" records the order: it saves the reference and moves the
    // shipment on, but only once the reference is typed AND the QR
    // screenshot is uploaded.
    final readyToCreate =
        _refCtrl.text.trim().isNotEmpty && ((_s['qr_image_url'] as String?) ?? '').isNotEmpty;

    return switch (_status) {
      'pending' => [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ElevatedButton(
              onPressed: (_busy || !readyToCreate)
                  ? null
                  : () => _run(() => widget.api
                      .updateShipment(_id, posReference: _refCtrl.text.trim(), status: 'order_created')),
              style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF16A34A),
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: SelmsColors.border,
                  elevation: 0),
              child: const Text('Create', style: TextStyle(fontSize: 12.5)),
            ),
          ),
        ],
      'order_created' => [go('Mark dropped at Pos', 'dropped_off')],
      'dropped_off' => [go(_isReturn ? 'Mark received by company' : 'Mark delivered', 'delivered')],
      'cancelled' => [go('Reopen', 'pending', primary: false)],
      _ => [],
    };
  }

  /// Copies the Pos reference (so it can be pasted if the tracking page
  /// doesn't pre-fill it) and opens Pos Malaysia's tracking page.
  Future<void> _track() async {
    final ref = _s['pos_reference'] as String? ?? '';
    if (ref.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: ref));
    await launchUrl(Uri.parse(_s['tracking_url'] as String), mode: LaunchMode.externalApplication);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Reference $ref copied — paste it into the Pos tracking page.')),
    );
  }

  Widget _qrBlock() {
    final url = _s['qr_image_url'] as String?;
    if (url == null || url.isEmpty) {
      if (widget.readOnly) return const SizedBox.shrink();
      return OutlinedButton.icon(
        onPressed: _busy ? null : _pickQr,
        icon: const Icon(Icons.upload_outlined, size: 15),
        label: const Text('Upload QR screenshot', style: TextStyle(fontSize: 12)),
      );
    }
    final full = '${widget.apiBaseUrl}$url';
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        InkWell(
          onTap: () => showDialog<void>(
            context: context,
            builder: (_) => Dialog(
              backgroundColor: Colors.white,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 420, maxHeight: 520),
                      child: Image.network(full, fit: BoxFit.contain),
                    ),
                    const SizedBox(height: 8),
                    const Text('Show this at the Pos counter.',
                        style: TextStyle(fontSize: 12, color: SelmsColors.textMuted)),
                  ],
                ),
              ),
            ),
          ),
          child: Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: SelmsColors.border),
              borderRadius: BorderRadius.circular(8),
            ),
            clipBehavior: Clip.antiAlias,
            child: Image.network(full, fit: BoxFit.contain,
                errorBuilder: (_, _, _) => const Center(child: Icon(Icons.broken_image_outlined))),
          ),
        ),
        const SizedBox(width: 10),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Tap to enlarge', style: TextStyle(fontSize: 11, color: SelmsColors.textMuted)),
            if (!widget.readOnly)
              TextButton(
                onPressed: _busy ? null : _pickQr,
                child: const Text('Replace', style: TextStyle(fontSize: 12)),
              ),
          ],
        ),
      ],
    );
  }

  Widget _progressSteps() {
    if (_status == 'cancelled') {
      return Row(children: [
        const Icon(Icons.block, size: 15, color: SelmsColors.textMuted),
        const SizedBox(width: 8),
        const Text('This shipment was cancelled.', style: TextStyle(fontSize: 12.5, color: SelmsColors.textMuted)),
      ]);
    }
    final current = _statusSteps.indexOf(_status);
    return Row(
      children: [
        for (var i = 0; i < _statusSteps.length; i++) ...[
          Icon(i <= current ? Icons.check_circle : Icons.radio_button_unchecked,
              size: 17, color: i <= current ? SelmsColors.statusActiveText : SelmsColors.textMuted),
          const SizedBox(width: 6),
          Text(_statusLabel(_statusSteps[i]),
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: i == current ? FontWeight.w600 : FontWeight.w400,
                  color: i <= current ? SelmsColors.textPrimary : SelmsColors.textMuted)),
          if (i < _statusSteps.length - 1)
            Expanded(
              child: Container(
                height: 1.5,
                margin: const EdgeInsets.symmetric(horizontal: 10),
                color: i < current ? SelmsColors.statusActiveText : SelmsColors.border,
              ),
            ),
        ],
      ],
    );
  }

  Widget _heading(String t) => Text(t,
      style: const TextStyle(
          fontSize: 10.5, fontWeight: FontWeight.w600, letterSpacing: 0.6, color: SelmsColors.textMuted));

  Widget _pill(String text, Color bg, Color fg) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
        child: Text(text, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: fg)),
      );

  /// A label + value with a copy button, so IT can paste straight into
  /// the Pos form field by field.
  Widget _copyRow(String label, String value, {String emptyHint = 'Not on file'}) {
    final empty = value.trim().isEmpty;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(
            width: 70,
            child: Text(label, style: const TextStyle(fontSize: 11.5, color: SelmsColors.textMuted)),
          ),
          Expanded(
            child: Text(empty ? emptyHint : value,
                style: TextStyle(
                    fontSize: 12.5,
                    color: empty ? SelmsColors.textMuted : SelmsColors.textPrimary,
                    fontStyle: empty ? FontStyle.italic : FontStyle.normal)),
          ),
          if (!empty)
            InkWell(
              onTap: () => _copy(label, value),
              borderRadius: BorderRadius.circular(6),
              child: const Padding(
                padding: EdgeInsets.all(4),
                child: Icon(Icons.copy, size: 14, color: SelmsColors.textSecondary),
              ),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------

/// Pick which remote employee a new shipment is for.
class _NewShipmentDialog extends StatefulWidget {
  const _NewShipmentDialog({required this.api, required this.direction});

  final ApiClient api;
  final String direction;

  @override
  State<_NewShipmentDialog> createState() => _NewShipmentDialogState();
}

class _NewShipmentDialogState extends State<_NewShipmentDialog> {
  final _searchCtrl = TextEditingController();
  List<Map<String, dynamic>> _employees = [];
  bool _loading = true;
  String? _error;
  String? _creatingFor;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final data = await widget.api.shipmentEligibleEmployees(widget.direction);
      if (!mounted) return;
      setState(() {
        _employees = (data['employees'] as List).cast<Map<String, dynamic>>();
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

  Future<void> _create(Map<String, dynamic> e) async {
    final id = e['employee_id'] as String;
    setState(() {
      _creatingFor = id;
      _error = null;
    });
    try {
      final created = await widget.api.createShipment(id, widget.direction);
      if (!mounted) return;
      Navigator.of(context).pop(created);
    } catch (err) {
      if (!mounted) return;
      setState(() {
        _creatingFor = null;
        _error = err.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final outgoing = widget.direction == 'to_employee';
    final q = _searchCtrl.text.trim().toLowerCase();
    final visible = _employees.where((e) {
      if (q.isEmpty) return true;
      return (e['full_name'] as String).toLowerCase().contains(q) ||
          (e['employee_id'] as String).toLowerCase().contains(q);
    }).toList();

    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440, maxHeight: 520),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(outgoing ? 'New shipment to an employee' : 'New equipment return',
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                  ),
                  InkWell(
                    onTap: () => Navigator.of(context).pop(),
                    child: const Icon(Icons.close, size: 18, color: SelmsColors.textSecondary),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              const Text('Only remote employees are listed.',
                  style: TextStyle(fontSize: 11.5, color: SelmsColors.textMuted)),
              const SizedBox(height: 12),
              TextField(
                controller: _searchCtrl,
                onChanged: (_) => setState(() {}),
                style: const TextStyle(fontSize: 13),
                decoration: const InputDecoration(
                  isDense: true,
                  prefixIcon: Icon(Icons.search, size: 16),
                  hintText: 'Search name or ID',
                ),
              ),
              const SizedBox(height: 8),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(_error!, style: const TextStyle(color: SelmsColors.rose, fontSize: 12)),
                ),
              Flexible(
                child: _loading
                    ? const Padding(padding: EdgeInsets.all(30), child: Center(child: CircularProgressIndicator()))
                    : visible.isEmpty
                        ? const Padding(
                            padding: EdgeInsets.all(24),
                            child: Center(
                              child: Text('No remote employees found.',
                                  style: TextStyle(fontSize: 12.5, color: SelmsColors.textMuted)),
                            ),
                          )
                        : ListView.builder(
                            shrinkWrap: true,
                            itemCount: visible.length,
                            itemBuilder: (_, i) {
                              final e = visible[i];
                              final blocked = e['has_active_shipment'] == true;
                              final notes = <String>[
                                '${e['employee_id']}',
                                '${e['work_location_type']}',
                                if (outgoing && e['onboarding_started'] == true) 'Onboarding',
                                if (!outgoing && e['offboarding_started'] == true) 'Offboarding',
                                '${e['assigned_count']} assigned',
                                if (blocked) 'Shipment already open',
                              ];
                              return ListTile(
                                enabled: !blocked && _creatingFor == null,
                                dense: true,
                                leading: CircleAvatar(
                                  radius: 16,
                                  backgroundColor: SelmsColors.accentBg,
                                  child: Text((e['full_name'] as String).substring(0, 1).toUpperCase(),
                                      style: const TextStyle(
                                          fontSize: 12, fontWeight: FontWeight.w600, color: SelmsColors.ink)),
                                ),
                                title: Text(e['full_name'] as String, style: const TextStyle(fontSize: 13)),
                                subtitle: Text(notes.join(' · '), style: const TextStyle(fontSize: 11)),
                                trailing: _creatingFor == e['employee_id']
                                    ? const SizedBox(
                                        width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                                    : null,
                                onTap: () => _create(e),
                              );
                            },
                          ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
