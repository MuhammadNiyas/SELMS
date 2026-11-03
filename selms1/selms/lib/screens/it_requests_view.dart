// lib/screens/it_requests_view.dart
//
// IT's equipment requests, one card per onboarding HR has started, plus one
// return card per offboarding (what to collect back). Each card answers
// "what do I need to do for this person?" in one place: the person's
// details, every item with its photo and ID, and a task checklist.
//
// Nothing here is ticked off by hand and there is no "Accept" step: the
// tasks are read live from the equipment and shipment records, so a request
// is done the moment the work really is - everything assigned (and, for a
// remote hire, the Pos parcel posted), or everything back from a leaver.
// Until then SELMS reminds IT in the bell.

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/api_client.dart';
import '../theme/selms_colors.dart';
import '../widgets/employee_avatar.dart';
import 'it_products_screen.dart';
import 'it_shipments_screen.dart';

class ItRequestsView extends StatefulWidget {
  const ItRequestsView({
    super.key,
    required this.api,
    required this.apiBaseUrl,
    required this.itToken,
    this.onOpenCount,
  });

  final ApiClient api;
  final String apiBaseUrl;
  final String itToken;

  /// Reports how many requests still need work (for the tab badge).
  final void Function(int count)? onOpenCount;

  @override
  State<ItRequestsView> createState() => _ItRequestsViewState();
}

class _ItRequestsViewState extends State<ItRequestsView> {
  List<Map<String, dynamic>> _requests = [];
  List<Map<String, dynamic>> _returns = [];
  List<Map<String, dynamic>> _notices = [];
  bool _loading = true;
  String? _error;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _load();
    // Equipment gets assigned on other screens - keep the statuses fresh.
    _poll = Timer.periodic(
      const Duration(seconds: 20),
      (_) => _load(silent: true),
    );
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) setState(() => _loading = true);
    try {
      final data = await widget.api.getItRequests();
      final list = (data['requests'] as List).cast<Map<String, dynamic>>();
      if (!mounted) return;
      final returns = ((data['returns'] as List?) ?? []).cast<Map<String, dynamic>>();
      setState(() {
        _requests = list;
        _returns = returns;
        _notices = ((data['notices'] as List?) ?? []).cast<Map<String, dynamic>>();
        _loading = false;
        _error = null;
      });
      widget.onOpenCount?.call(
        list.where((r) => r['status'] == 'open' && r['fulfilled'] != true).length +
            returns.where((r) => r['fulfilled'] != true).length,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        if (!silent) _error = e.toString();
      });
    }
  }

  Future<void> _dismissNotice(Map<String, dynamic> n) async {
    try {
      await widget.api.deleteItNotice(n['id'] as String);
      if (!mounted) return;
      setState(() => _notices.removeWhere((x) => x['id'] == n['id']));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.toString()), backgroundColor: SelmsColors.rose));
    }
  }

  Widget _noticeCard(Map<String, dynamic> n) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
      decoration: BoxDecoration(
        color: SelmsColors.statusOnboardingBg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline, size: 18, color: SelmsColors.statusOnboardingText),
          const SizedBox(width: 10),
          Expanded(
            child: Text(n['content'] as String? ?? '',
                style: const TextStyle(fontSize: 12.5, color: SelmsColors.statusOnboardingText, height: 1.35)),
          ),
          TextButton.icon(
            onPressed: () => _dismissNotice(n),
            icon: const Icon(Icons.delete_outline, size: 15, color: SelmsColors.statusOnboardingText),
            label: const Text('Delete', style: TextStyle(fontSize: 12, color: SelmsColors.statusOnboardingText)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
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
    if (_requests.isEmpty && _returns.isEmpty && _notices.isEmpty) {
      return Container(
        width: double.infinity,
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
        child: const Center(
          child: Padding(
            padding: EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.inventory_2_outlined, size: 38, color: SelmsColors.textMuted),
                SizedBox(height: 12),
                Text('No equipment requests',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: SelmsColors.textPrimary)),
              ],
            ),
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.only(bottom: 24),
      itemCount: _notices.length + _requests.length + _returns.length,
      separatorBuilder: (_, _) => const SizedBox(height: 14),
      itemBuilder: (_, i) {
        // Short automatic notes first, each with a delete button.
        if (i < _notices.length) return _noticeCard(_notices[i]);
        final j = i - _notices.length;
        if (j < _requests.length) {
          final r = _requests[j];
          return _RequestCard(
            key: ValueKey(r['message_id']),
            request: r,
            apiBaseUrl: widget.apiBaseUrl,
            itToken: widget.itToken,
          );
        }
        final ret = _returns[j - _requests.length];
        return _ReturnCard(
          key: ValueKey('return-${ret['message_id']}'),
          data: ret,
          apiBaseUrl: widget.apiBaseUrl,
          itToken: widget.itToken,
          onChanged: () => _load(silent: true),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Pieces both cards use
// ---------------------------------------------------------------------------

Widget _heading(String t) => Text(
      t,
      style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, letterSpacing: 0.6, color: SelmsColors.textMuted),
    );

Widget _chip(String text, Color bg, Color fg) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Text(text, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: fg)),
    );

/// "ID: LAP-0012" - the asset tag, or the serial number when there is no tag.
String _idText(Map<String, dynamic> item) {
  final tag = (item['asset_tag'] as String?) ?? '';
  final serial = (item['serial_number'] as String?) ?? '';
  if (tag.isNotEmpty) return 'ID: $tag';
  if (serial.isNotEmpty) return 'S/N: $serial';
  return 'No ID on record';
}

/// The product's photo (a device icon when it has none).
class _AssetThumb extends StatelessWidget {
  const _AssetThumb({required this.apiBaseUrl, this.photoUrl, this.size = 44});

  final String apiBaseUrl;
  final String? photoUrl;
  final double size;

  @override
  Widget build(BuildContext context) {
    final icon = Icon(Icons.devices_other_outlined, size: size * 0.45, color: SelmsColors.textMuted);
    final url = photoUrl;
    return Container(
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: SelmsColors.border),
      ),
      alignment: Alignment.center,
      child: url != null && url.isNotEmpty
          ? Image.network(url.startsWith('http') ? url : '$apiBaseUrl$url',
              width: size, height: size, fit: BoxFit.cover, errorBuilder: (_, _, _) => icon)
          : icon,
    );
  }
}

/// Label / value row with an optional copy button.
class _Fact extends StatelessWidget {
  const _Fact(this.label, this.value, {this.copy = false});

  final String label;
  final String value;
  final bool copy;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(
            width: 108,
            child: Text(label, style: const TextStyle(fontSize: 11.5, color: SelmsColors.textMuted)),
          ),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 12.5, color: SelmsColors.textPrimary))),
          if (copy && value != '—')
            InkWell(
              onTap: () async {
                await Clipboard.setData(ClipboardData(text: value));
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('$label copied.'), duration: const Duration(seconds: 1)));
              },
              borderRadius: BorderRadius.circular(6),
              child: const Padding(
                padding: EdgeInsets.all(4),
                child: Icon(Icons.copy, size: 15, color: SelmsColors.textSecondary),
              ),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Onboarding: equipment to prepare for a new hire
// ---------------------------------------------------------------------------

class _RequestCard extends StatefulWidget {
  const _RequestCard({
    super.key,
    required this.request,
    required this.apiBaseUrl,
    required this.itToken,
  });

  final Map<String, dynamic> request;
  final String apiBaseUrl;
  final String itToken;

  @override
  State<_RequestCard> createState() => _RequestCardState();
}

class _RequestCardState extends State<_RequestCard> {
  bool _expanded = false; // collapsed shows just the summary row

  Map<String, dynamic> get _r => widget.request;
  Map<String, dynamic> get _emp => (_r['employee'] as Map).cast<String, dynamic>();
  Map<String, dynamic> get _account => (_r['account'] as Map).cast<String, dynamic>();
  List<Map<String, dynamic>> get _items => (_r['items'] as List).cast<Map<String, dynamic>>();
  List<Map<String, dynamic>> get _extra => ((_r['extra_assigned'] as List?) ?? []).cast<Map<String, dynamic>>();
  bool get _open => _r['status'] == 'open';
  bool get _fulfilled => _r['fulfilled'] == true;
  bool get _remote => _r['needs_shipping'] == true;

  void _goProducts() => Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => ItProductsScreen(apiBaseUrl: widget.apiBaseUrl, itToken: widget.itToken)),
      );

  void _goShipments() => Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => ItShipmentsScreen(apiBaseUrl: widget.apiBaseUrl, itToken: widget.itToken)),
      );

  /// Header chip for the Pos parcel of a remote hire.
  Widget _parcelChip() {
    final status = (_r['shipment'] as Map?)?['status'] as String?;
    return switch (status) {
      'dropped_off' || 'delivered' =>
        _chip(status == 'delivered' ? 'Parcel delivered' : 'Parcel posted', SelmsColors.statusActiveBg, SelmsColors.statusActiveText),
      'order_created' => _chip('Parcel booked, not posted', SelmsColors.statusOnboardingBg, SelmsColors.statusOnboardingText),
      _ => _chip('Parcel not created', const Color(0xFFFEE2E2), SelmsColors.statusOffboardingText),
    };
  }

  @override
  Widget build(BuildContext context) {
    final name = _emp['full_name'] as String? ?? '';
    final assigned = (_r['assigned_count'] as num).toInt();
    final needed = (_r['needed_count'] as num).toInt();

    return Opacity(
      opacity: _open ? 1 : 0.62,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: _fulfilled ? SelmsColors.statusActiveText.withValues(alpha: 0.35) : Colors.transparent,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ---- header (always visible; click to expand) ----
            InkWell(
              onTap: () => setState(() => _expanded = !_expanded),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 14),
                child: Row(
                  children: [
                    EmployeeAvatar(
                      apiBaseUrl: widget.apiBaseUrl,
                      name: name,
                      photoUrl: _emp['profile_image_url'] as String?,
                      size: 42,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(name,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        fontSize: 15, fontWeight: FontWeight.w600, color: SelmsColors.textPrimary)),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                    color: SelmsColors.statusOnboardingBg, borderRadius: BorderRadius.circular(10)),
                                child: const Text('New hire',
                                    style: TextStyle(
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.w600,
                                        color: SelmsColors.statusOnboardingText)),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${_emp['employee_id']}  ·  ${_emp['job_title'] ?? ''}  ·  ${_emp['department'] ?? ''}',
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12, color: SelmsColors.textMuted),
                          ),
                        ],
                      ),
                    ),
                    if (!_open)
                      _chip('Cancelled by HR', const Color(0xFFF3F4F6), SelmsColors.textSecondary)
                    else if (_fulfilled)
                      _chip('Done', SelmsColors.statusActiveBg, SelmsColors.statusActiveText)
                    else ...[
                      _chip('$assigned of $needed assigned',
                          assigned == needed ? SelmsColors.statusActiveBg : SelmsColors.statusOnboardingBg,
                          assigned == needed ? SelmsColors.statusActiveText : SelmsColors.statusOnboardingText),
                      if (_remote) ...[const SizedBox(width: 8), _parcelChip()],
                    ],
                    const SizedBox(width: 10),
                    Icon(_expanded ? Icons.expand_less : Icons.expand_more, size: 20, color: SelmsColors.textMuted),
                  ],
                ),
              ),
            ),
            if (_expanded) ...[
              const Divider(height: 1, color: SelmsColors.border),
              Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 5, child: _equipmentColumn(assigned, needed)),
                    const SizedBox(width: 28),
                    Expanded(flex: 5, child: _detailsColumn()),
                  ],
                ),
              ),
              if (_open && (assigned < needed || _remote)) ...[
                const Divider(height: 1, color: SelmsColors.border),
                Container(
                  color: SelmsColors.fieldBg,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  child: Row(
                    children: [
                      if (assigned < needed)
                        OutlinedButton.icon(
                          onPressed: _goProducts,
                          icon: const Icon(Icons.inventory_2_outlined, size: 15),
                          label: const Text('Assign equipment', style: TextStyle(fontSize: 12.5)),
                        ),
                      if (_remote) ...[
                        const SizedBox(width: 10),
                        OutlinedButton.icon(
                          onPressed: _goShipments,
                          icon: const Icon(Icons.local_shipping_outlined, size: 15),
                          label: Text(_r['shipment'] == null ? 'Ship via Pos' : 'View shipment',
                              style: const TextStyle(fontSize: 12.5)),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  // ---------- left: equipment + tasks ----------

  Widget _equipmentColumn(int assigned, int needed) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _heading('EQUIPMENT TO PREPARE'),
        const SizedBox(height: 10),
        if (_items.isEmpty)
          const Text('No equipment was requested for this hire.',
              style: TextStyle(fontSize: 12.5, color: SelmsColors.textMuted))
        else ...[
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: needed == 0 ? 1 : assigned / needed,
              minHeight: 5,
              backgroundColor: SelmsColors.border,
              valueColor: AlwaysStoppedAnimation(
                  assigned == needed ? SelmsColors.statusActiveText : const Color(0xFFF59E0B)),
            ),
          ),
          const SizedBox(height: 10),
          ..._items.map(_itemRow),
        ],
        if (_extra.isNotEmpty) ...[
          const SizedBox(height: 10),
          _heading('ALSO ASSIGNED'),
          const SizedBox(height: 6),
          ..._extra.map(_extraRow),
        ],
      ],
    );
  }

  Widget _itemRow(Map<String, dynamic> item) {
    final done = item['assigned'] == true;
    final asset = (item['asset'] as Map?)?.cast<String, dynamic>();
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: done ? SelmsColors.statusActiveBg.withValues(alpha: 0.5) : SelmsColors.fieldBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: SelmsColors.border),
      ),
      child: Row(
        children: [
          if (done)
            _AssetThumb(apiBaseUrl: widget.apiBaseUrl, photoUrl: asset?['photo_url'] as String?)
          else
            const SizedBox(
              width: 44,
              height: 44,
              child: Icon(Icons.radio_button_unchecked, size: 18, color: SelmsColors.textMuted),
            ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item['type'] as String? ?? '',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: SelmsColors.textPrimary)),
                if (done) ...[
                  Text(asset?['name'] as String? ?? '',
                      style: const TextStyle(fontSize: 11.5, color: SelmsColors.textSecondary)),
                  Text(_idText(asset ?? const {}), style: const TextStyle(fontSize: 11, color: SelmsColors.textMuted)),
                ] else
                  const Text('Not assigned yet', style: TextStyle(fontSize: 11.5, color: SelmsColors.textMuted)),
              ],
            ),
          ),
          if (done) const Icon(Icons.check_circle, size: 18, color: SelmsColors.statusActiveText),
        ],
      ),
    );
  }

  Widget _extraRow(Map<String, dynamic> a) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          _AssetThumb(apiBaseUrl: widget.apiBaseUrl, photoUrl: a['photo_url'] as String?, size: 32),
          const SizedBox(width: 10),
          Expanded(
            child: Text('${a['name'] ?? a['type'] ?? 'Item'}  ·  ${_idText(a)}',
                style: const TextStyle(fontSize: 12, color: SelmsColors.textSecondary)),
          ),
        ],
      ),
    );
  }

  // ---------- right: employee + account + delivery ----------

  Widget _detailsColumn() {
    final location = _emp['work_location_type'] as String? ?? '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _heading('EMPLOYEE'),
        const SizedBox(height: 6),
        _Fact('Start date', (_emp['hire_date'] as String?)?.isNotEmpty == true ? _emp['hire_date'] as String : 'TBC'),
        _Fact('Work location', location.isEmpty ? '—' : location),
        _Fact('Line manager',
            (_emp['line_manager'] as String?)?.isNotEmpty == true ? _emp['line_manager'] as String : '—'),
        _Fact('Personal email', _emp['personal_email'] as String? ?? '—', copy: true),
        _Fact('Phone', _emp['mobile_number'] as String? ?? '—', copy: true),
        const SizedBox(height: 14),
        _heading('MICROSOFT ACCOUNT'),
        const SizedBox(height: 6),
        if (!_open)
          const Text('Credentials are removed once a request is cancelled.',
              style: TextStyle(fontSize: 12, color: SelmsColors.textMuted))
        else ...[
          _Fact('Account email', _account['email'] as String? ?? '—', copy: true),
        ],
        const SizedBox(height: 14),
        _heading('DELIVERY'),
        const SizedBox(height: 6),
        if (!_remote)
          Row(
            children: [
              const Icon(Icons.business_outlined, size: 15, color: SelmsColors.textSecondary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  location.isEmpty
                      ? 'Collects equipment at the office.'
                      : '$location — collects equipment at the office. No posting needed.',
                  style: const TextStyle(fontSize: 12, color: SelmsColors.textSecondary),
                ),
              ),
            ],
          )
        else ...[
          Row(
            children: [
              const Icon(Icons.local_shipping_outlined, size: 15, color: SelmsColors.textSecondary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _r['shipment'] == null
                      ? '$location employee — equipment needs to be posted to:'
                      : 'Shipment ${_shipmentLabel((_r['shipment'] as Map)['status'] as String)} — posting to:',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: SelmsColors.textSecondary),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          _Fact('Address', _emp['address_line'] as String? ?? '—', copy: true),
          _Fact('Postcode', _emp['postcode'] as String? ?? '—', copy: true),
          _Fact('State', _emp['state'] as String? ?? '—', copy: true),
        ],
      ],
    );
  }

  String _shipmentLabel(String s) => switch (s) {
        'pending' => 'to prepare',
        'order_created' => 'booked with Pos',
        'dropped_off' => 'dropped at Pos',
        'delivered' => 'delivered',
        _ => s,
      };
}

// ---------------------------------------------------------------------------
// Offboarding: equipment to collect back from a leaver
// ---------------------------------------------------------------------------

/// Laid out like the onboarding card. An item counts as returned only once
/// IT has really received it (Products / Scan) - there is no tick box.
class _ReturnCard extends StatefulWidget {
  const _ReturnCard({
    super.key,
    required this.data,
    required this.apiBaseUrl,
    required this.itToken,
    this.onChanged,
  });

  final Map<String, dynamic> data;
  final String apiBaseUrl;
  final String itToken;

  /// Reloads the list after IT records something (e.g. an item as lost).
  final VoidCallback? onChanged;

  @override
  State<_ReturnCard> createState() => _ReturnCardState();
}

class _ReturnCardState extends State<_ReturnCard> {
  bool _expanded = false;
  bool _confirming = false;

  Map<String, dynamic> get _d => widget.data;
  Map<String, dynamic> get _emp => (_d['employee'] as Map).cast<String, dynamic>();
  List<Map<String, dynamic>> get _items => (_d['items'] as List).cast<Map<String, dynamic>>();
  Map<String, dynamic>? get _parcel => (_d['shipment'] as Map?)?.cast<String, dynamic>();
  bool get _fulfilled => _d['fulfilled'] == true;
  bool get _byPost => _d['by_post'] == true;

  /// Nothing on record for this leaver: IT confirms that, so it counts as done.
  Future<void> _confirmNothing() async {
    setState(() => _confirming = true);
    try {
      await ApiClient(baseUrl: widget.apiBaseUrl, hrToken: widget.itToken)
          .confirmNothingToCollect(_d['message_id'] as String);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Confirmed - nothing to collect.')));
      widget.onChanged?.call();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => _confirming = false);
    }
  }

  /// Closes an item off as lost (it won't come back), so offboarding can finish.
  Future<void> _markLost(Map<String, dynamic> it, Map<String, dynamic>? prep) async {
    final name = it['name'] ?? it['type'] ?? 'this item';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        title: Text('Mark $name as lost?', style: const TextStyle(fontSize: 15)),
        content: Text(
          'It is taken off ${_emp['full_name'] ?? 'the employee'} and recorded as Lost in Products. '
          '${(prep?['note'] as String? ?? '').isNotEmpty ? 'Their note: "${prep!['note']}"' : ''}',
          style: const TextStyle(fontSize: 12.5, height: 1.4),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: SelmsColors.rose, foregroundColor: Colors.white),
            child: const Text('Mark as lost'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await ApiClient(baseUrl: widget.apiBaseUrl, hrToken: widget.itToken).returnEquipment(
        it['equipment_id'] as String,
        condition: 'Lost',
        notes: (prep?['note'] as String? ?? '').isEmpty ? 'Marked lost by IT' : 'Employee: ${prep!['note']}',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$name recorded as lost.')));
      widget.onChanged?.call();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  /// "Employee: backed up · signed out · accessories included · Condition: Good · Note: ..."
  String _prepText(Map<String, dynamic> p) {
    final parts = <String>[
      if (p['condition'] != 'Lost') ...[
        p['backed_up'] == true ? 'backed up' : 'NOT backed up',
        p['signed_out'] == true ? 'signed out' : 'NOT signed out',
        p['accessories'] == true ? 'accessories included' : 'accessories missing',
      ],
      'Condition: ${p['condition'] ?? '-'}',
      if ((p['note'] as String? ?? '').isNotEmpty) 'Note: ${p['note']}',
    ];
    return 'Employee: ${parts.join(' · ')}';
  }

  Widget _badge(String text, Color bg, Color fg) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10)),
        child: Text(text, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: fg)),
      );

  @override
  Widget build(BuildContext context) {
    final name = _emp['full_name'] as String? ?? '';
    final returned = (_d['returned_count'] as num).toInt();
    final total = (_d['total_count'] as num).toInt();
    final lastDay = _d['last_working_day'] as String?;
    final fromEmployee = _parcel?['from_employee'] == true && !_fulfilled;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _fulfilled ? SelmsColors.statusActiveText.withValues(alpha: 0.35) : Colors.transparent,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 14),
              child: Row(
                children: [
                  EmployeeAvatar(
                    apiBaseUrl: widget.apiBaseUrl,
                    name: name,
                    photoUrl: _emp['profile_image_url'] as String?,
                    size: 42,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(name,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      fontSize: 15, fontWeight: FontWeight.w600, color: SelmsColors.textPrimary)),
                            ),
                            const SizedBox(width: 8),
                            _badge('Equipment return', const Color(0xFFFAECE7), const Color(0xFF993C1D)),
                            if (fromEmployee) ...[
                              const SizedBox(width: 6),
                              _badge('Parcel to review', SelmsColors.accentBg, SelmsColors.ink),
                            ] else if (!_fulfilled && _d['ready_at'] != null) ...[
                              const SizedBox(width: 6),
                              _badge('Ready to return', SelmsColors.statusActiveBg, SelmsColors.statusActiveText),
                            ],
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${_emp['employee_id'] ?? ''}  ·  ${_emp['job_title'] ?? ''}  ·  ${_emp['department'] ?? ''}',
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12, color: SelmsColors.textMuted),
                        ),
                      ],
                    ),
                  ),
                  if (_fulfilled)
                    _chip(total == 0 ? 'Nothing to collect' : 'Done', SelmsColors.statusActiveBg, SelmsColors.statusActiveText)
                  else
                    _chip(total == 0 ? 'To confirm' : '$returned of $total received', SelmsColors.statusOnboardingBg,
                        SelmsColors.statusOnboardingText),
                  const SizedBox(width: 10),
                  Icon(_expanded ? Icons.expand_less : Icons.expand_more, size: 20, color: SelmsColors.textMuted),
                ],
              ),
            ),
          ),
          if (_expanded) ...[
            const Divider(height: 1, color: SelmsColors.border),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 5, child: _equipmentColumn(returned, total)),
                  const SizedBox(width: 28),
                  Expanded(flex: 5, child: _detailsColumn(lastDay)),
                ],
              ),
            ),
            if (!_fulfilled && total > 0) ...[
              const Divider(height: 1, color: SelmsColors.border),
              Container(
                color: SelmsColors.fieldBg,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                child: Row(
                  children: [
                    OutlinedButton.icon(
                      onPressed: () => Navigator.of(context).pushReplacement(MaterialPageRoute(
                        builder: (_) => ItProductsScreen(apiBaseUrl: widget.apiBaseUrl, itToken: widget.itToken),
                      )),
                      icon: const Icon(Icons.inventory_2_outlined, size: 15),
                      label: const Text('Receive in Products', style: TextStyle(fontSize: 12.5)),
                    ),
                    if (_byPost) ...[
                      const SizedBox(width: 10),
                      OutlinedButton.icon(
                        onPressed: () => Navigator.of(context).pushReplacement(MaterialPageRoute(
                          builder: (_) => ItShipmentsScreen(
                              apiBaseUrl: widget.apiBaseUrl, itToken: widget.itToken, initialDirection: 'return'),
                        )),
                        icon: const Icon(Icons.local_shipping_outlined, size: 15),
                        label: Text(_parcel == null ? 'Return shipments' : 'Review the parcel',
                            style: const TextStyle(fontSize: 12.5)),
                      ),
                    ],
                    const Spacer(),
                    const Flexible(
                      child: Text(
                        'Done by itself once every item is received.',
                        textAlign: TextAlign.right,
                        style: TextStyle(fontSize: 11.5, color: SelmsColors.textMuted),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  // ---------- left: equipment + tasks ----------

  Widget _equipmentColumn(int returned, int total) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _heading('EQUIPMENT TO COLLECT'),
        const SizedBox(height: 10),
        if (_items.isEmpty && _fulfilled)
          Text('Confirmed by ${_d['nothing_to_collect_by'] ?? 'IT'}: no company equipment to collect.',
              style: const TextStyle(fontSize: 12.5, color: SelmsColors.textSecondary))
        else if (_items.isEmpty) ...[
          const Text(
              'No equipment is on record for this person. Check they really have nothing '
              '(laptop, phone, badge, accessories), then confirm - until then it is not counted as returned.',
              style: TextStyle(fontSize: 12.5, color: SelmsColors.textSecondary, height: 1.4)),
          const SizedBox(height: 10),
          ElevatedButton.icon(
            onPressed: _confirming ? null : _confirmNothing,
            icon: const Icon(Icons.check, size: 15),
            label: Text(_confirming ? 'Confirming…' : 'Confirm nothing to collect', style: const TextStyle(fontSize: 12)),
          ),
        ] else ...[
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: total == 0 ? 1 : returned / total,
              minHeight: 5,
              backgroundColor: SelmsColors.border,
              valueColor:
                  AlwaysStoppedAnimation(returned == total ? SelmsColors.statusActiveText : const Color(0xFFF59E0B)),
            ),
          ),
          const SizedBox(height: 10),
          ..._items.map(_itemRow),
        ],
      ],
    );
  }

  Widget _itemRow(Map<String, dynamic> it) {
    final done = it['returned'] == true;
    final prep = (it['prep'] as Map?)?.cast<String, dynamic>();
    final outcome = switch (it['outcome']) {
      'lost' => 'Recorded lost',
      'damaged' => 'Received · damaged',
      _ => 'Received',
    };
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: done ? SelmsColors.statusActiveBg.withValues(alpha: 0.5) : SelmsColors.fieldBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: SelmsColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _AssetThumb(apiBaseUrl: widget.apiBaseUrl, photoUrl: it['photo_url'] as String?),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${it['name'] ?? it['type'] ?? 'Item'}',
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: SelmsColors.textPrimary)),
                    Text('${it['type'] ?? ''}${it['type'] != null ? '  ·  ' : ''}${_idText(it)}',
                        style: const TextStyle(fontSize: 11, color: SelmsColors.textMuted)),
                  ],
                ),
              ),
              done
                  ? Text(outcome,
                      style: const TextStyle(
                          fontSize: 11, fontWeight: FontWeight.w600, color: SelmsColors.statusActiveText))
                  : const Text('With employee', style: TextStyle(fontSize: 11, color: SelmsColors.textMuted)),
            ],
          ),
          // What the employee said before handing it back.
          if (!done && prep != null)
            Padding(
              padding: const EdgeInsets.only(left: 54, top: 4),
              child: Text(_prepText(prep),
                  style: TextStyle(
                      fontSize: 11,
                      color: prep['condition'] == 'Good' ? SelmsColors.textSecondary : const Color(0xFF993C1D))),
            ),
          // Not coming back: IT can close it off as lost.
          if (!done)
            Padding(
              padding: const EdgeInsets.only(left: 54, top: 2),
              child: TextButton(
                onPressed: () => _markLost(it, prep),
                style: TextButton.styleFrom(
                    padding: EdgeInsets.zero, minimumSize: const Size(0, 0), visualDensity: VisualDensity.compact),
                child: Text(prep?['condition'] == 'Lost' ? 'Employee reported it lost — mark as lost' : 'Mark as lost',
                    style: const TextStyle(fontSize: 11, color: SelmsColors.rose)),
              ),
            ),
        ],
      ),
    );
  }

  // ---------- right: employee + how it comes back ----------

  Widget _detailsColumn(String? lastDay) {
    final location = _emp['work_location_type'] as String? ?? '';
    final ref = _parcel?['pos_reference'] as String? ?? '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _heading('EMPLOYEE'),
        const SizedBox(height: 6),
        _Fact('Last working day', (lastDay ?? '').isEmpty ? '—' : lastDay!),
        _Fact('Departure', (_d['departure_type'] as String? ?? '').isEmpty ? '—' : _d['departure_type'] as String),
        _Fact('Work location', location.isEmpty ? '—' : location),
        _Fact('Personal email', _emp['personal_email'] as String? ?? '—', copy: true),
        _Fact('Phone', _emp['mobile_number'] as String? ?? '—', copy: true),
        const SizedBox(height: 14),
        _heading('RETURN'),
        const SizedBox(height: 6),
        if (!_byPost)
          Row(
            children: [
              const Icon(Icons.business_outlined, size: 15, color: SelmsColors.textSecondary),
              const SizedBox(width: 8),
              Expanded(
                child: Text('Brings the items to ${_d['location'] ?? 'the IT department'}.',
                    style: const TextStyle(fontSize: 12, color: SelmsColors.textSecondary)),
              ),
            ],
          )
        else ...[
          Row(
            children: [
              const Icon(Icons.local_shipping_outlined, size: 15, color: SelmsColors.textSecondary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _parcel == null
                      ? 'Remote — the employee books the Pos parcel to the company and sends you the tracking number.'
                      : _parcel!['from_employee'] == true
                          ? 'Remote — the employee posted it and sent this tracking number to review:'
                          : 'Remote — returned by Pos Malaysia:',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: SelmsColors.textSecondary),
                ),
              ),
            ],
          ),
          if (ref.isNotEmpty) ...[
            const SizedBox(height: 4),
            _Fact('Tracking number', ref, copy: true),
            _Fact('Parcel status', switch (_parcel?['status']) {
              'delivered' => 'Received',
              'dropped_off' => 'On its way',
              'order_created' => 'Booked',
              _ => 'Pending',
            }),
          ],
        ],
      ],
    );
  }
}
