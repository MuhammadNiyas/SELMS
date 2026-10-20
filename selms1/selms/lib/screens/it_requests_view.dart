// lib/screens/it_requests_view.dart
//
// IT's equipment requests, one card per onboarding HR has started (plus a
// simpler "return" card per offboarding: what to collect back). Each
// card answers "what do I need to do for this person?" in one place:
// the hire's details, the exact equipment they were approved for with a
// live assigned / not-assigned status per item, and the account details
// needed to create their Microsoft account.
//
// There is no "done" button. A request completes only when every item is
// really assigned in the equipment records - the status here is read live
// from them, so it can't be claimed without doing the work. "Accept" just
// tells HR that IT has seen the request and is on it.

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/api_client.dart';
import '../theme/selms_colors.dart';
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
                style: const TextStyle(
                    fontSize: 12.5, color: SelmsColors.statusOnboardingText, height: 1.35)),
          ),
          TextButton.icon(
            onPressed: () => _dismissNotice(n),
            icon: const Icon(Icons.delete_outline, size: 15, color: SelmsColors.statusOnboardingText),
            label: const Text('Delete',
                style: TextStyle(fontSize: 12, color: SelmsColors.statusOnboardingText)),
          ),
        ],
      ),
    );
  }

  Future<void> _accept(Map<String, dynamic> r) async {
    try {
      await widget.api.acceptMessage(r['message_id'] as String);
      await _load(silent: true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString()),
          backgroundColor: SelmsColors.rose,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _error!,
              style: const TextStyle(color: SelmsColors.rose, fontSize: 13),
            ),
            const SizedBox(height: 10),
            OutlinedButton(
              onPressed: () => _load(),
              child: const Text('Try again'),
            ),
          ],
        ),
      );
    }
    if (_requests.isEmpty && _returns.isEmpty && _notices.isEmpty) {
      return Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Center(
          child: Padding(
            padding: EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.inventory_2_outlined,
                  size: 38,
                  color: SelmsColors.textMuted,
                ),
                SizedBox(height: 12),
                Text(
                  'No equipment requests',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: SelmsColors.textPrimary,
                  ),
                ),
                SizedBox(height: 6),
                Text(
                  'When HR starts onboarding someone, their equipment request appears here — '
                  'and when someone is offboarded, the equipment to collect back.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12.5,
                    color: SelmsColors.textMuted,
                  ),
                ),
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
            onAccept: () => _accept(r),
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

class _RequestCard extends StatefulWidget {
  const _RequestCard({
    super.key,
    required this.request,
    required this.apiBaseUrl,
    required this.itToken,
    required this.onAccept,
  });

  final Map<String, dynamic> request;
  final String apiBaseUrl;
  final String itToken;
  final Future<void> Function() onAccept;

  @override
  State<_RequestCard> createState() => _RequestCardState();
}

class _RequestCardState extends State<_RequestCard> {
  bool _showPassword = false;
  bool _accepting = false;
  bool _expanded = false; // collapsed shows just the summary row

  Map<String, dynamic> get _r => widget.request;
  Map<String, dynamic> get _emp =>
      (_r['employee'] as Map).cast<String, dynamic>();
  Map<String, dynamic> get _account =>
      (_r['account'] as Map).cast<String, dynamic>();
  List<Map<String, dynamic>> get _items =>
      (_r['items'] as List).cast<Map<String, dynamic>>();
  List<Map<String, dynamic>> get _extra =>
      ((_r['extra_assigned'] as List?) ?? []).cast<Map<String, dynamic>>();
  bool get _open => _r['status'] == 'open';
  bool get _fulfilled => _r['fulfilled'] == true;
  bool get _accepted => _r['accepted'] == true;

  Future<void> _copy(String label, String value) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$label copied.'),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  void _goProducts() => Navigator.of(context).pushReplacement(
    MaterialPageRoute(
      builder: (_) => ItProductsScreen(
        apiBaseUrl: widget.apiBaseUrl,
        itToken: widget.itToken,
      ),
    ),
  );

  void _goShipments() => Navigator.of(context).pushReplacement(
    MaterialPageRoute(
      builder: (_) => ItShipmentsScreen(
        apiBaseUrl: widget.apiBaseUrl,
        itToken: widget.itToken,
      ),
    ),
  );

  String _initials(String name) {
    final parts = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
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
            color: _fulfilled
                ? SelmsColors.statusActiveText.withValues(alpha: 0.35)
                : Colors.transparent,
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
                    Container(
                      width: 42,
                      height: 42,
                      clipBehavior: Clip.hardEdge,
                      decoration: const BoxDecoration(
                        color: SelmsColors.accentBg,
                        shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child:
                          (_emp['profile_image_url'] as String?)?.isNotEmpty ==
                              true
                          ? Image.network(
                              '${widget.apiBaseUrl}${_emp['profile_image_url']}',
                              fit: BoxFit.cover,
                              width: 42,
                              height: 42,
                              errorBuilder: (_, _, _) =>
                                  Text(_initials(name), style: _initialsStyle),
                            )
                          : Text(_initials(name), style: _initialsStyle),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: SelmsColors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${_emp['employee_id']}  ·  ${_emp['job_title'] ?? ''}  ·  ${_emp['department'] ?? ''}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: SelmsColors.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (!_open)
                      _chip(
                        'Cancelled by HR',
                        const Color(0xFFF3F4F6),
                        SelmsColors.textSecondary,
                      )
                    else ...[
                      if (_fulfilled)
                        _chip(
                          'All equipment assigned',
                          SelmsColors.statusActiveBg,
                          SelmsColors.statusActiveText,
                        )
                      else
                        _chip(
                          '$assigned of $needed assigned',
                          SelmsColors.statusOnboardingBg,
                          SelmsColors.statusOnboardingText,
                        ),
                      const SizedBox(width: 8),
                      _accepted
                          ? _chip(
                              'Accepted by ${_r['accepted_by']}',
                              SelmsColors.accentBg,
                              SelmsColors.ink,
                            )
                          : _chip(
                              'Awaiting acceptance',
                              const Color(0xFFFEE2E2),
                              SelmsColors.statusOffboardingText,
                            ),
                    ],
                    const SizedBox(width: 10),
                    Icon(
                      _expanded ? Icons.expand_less : Icons.expand_more,
                      size: 20,
                      color: SelmsColors.textMuted,
                    ),
                  ],
                ),
              ),
            ),
            if (_expanded) ...[
              const Divider(height: 1, color: SelmsColors.border),
              // ---- body ----
              Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 5,
                      child: _equipmentColumn(assigned, needed),
                    ),
                    const SizedBox(width: 28),
                    Expanded(flex: 5, child: _detailsColumn()),
                  ],
                ),
              ),
              // ---- actions ----
              if (_open) ...[
                const Divider(height: 1, color: SelmsColors.border),
                Container(
                  color: SelmsColors.fieldBg,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                  child: Row(
                    children: [
                      if (!_accepted)
                        ElevatedButton.icon(
                          onPressed: _accepting
                              ? null
                              : () async {
                                  setState(() => _accepting = true);
                                  await widget.onAccept();
                                  if (mounted)
                                    setState(() => _accepting = false);
                                },
                          icon: const Icon(Icons.check, size: 15),
                          label: Text(
                            _accepting ? 'Accepting…' : 'Accept request',
                            style: const TextStyle(fontSize: 12.5),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: SelmsColors.ink,
                            foregroundColor: Colors.white,
                            elevation: 0,
                          ),
                        ),
                      if (!_accepted) const SizedBox(width: 10),
                      if (!_fulfilled)
                        OutlinedButton.icon(
                          onPressed: _goProducts,
                          icon: const Icon(
                            Icons.inventory_2_outlined,
                            size: 15,
                          ),
                          label: const Text(
                            'Assign equipment',
                            style: TextStyle(fontSize: 12.5),
                          ),
                        ),
                      if (_r['needs_shipping'] == true) ...[
                        const SizedBox(width: 10),
                        OutlinedButton.icon(
                          onPressed: _goShipments,
                          icon: const Icon(
                            Icons.local_shipping_outlined,
                            size: 15,
                          ),
                          label: Text(
                            _r['shipment'] == null
                                ? 'Ship via Pos'
                                : 'View shipment',
                            style: const TextStyle(fontSize: 12.5),
                          ),
                        ),
                      ],
                      const Spacer(),
                      Flexible(
                        child: Text(
                          _fulfilled
                              ? 'Complete — IT has assigned everything requested.'
                              : 'Nothing is assigned for you. Items tick off as you assign them from Products.',
                          textAlign: TextAlign.right,
                          style: const TextStyle(
                            fontSize: 11.5,
                            color: SelmsColors.textMuted,
                          ),
                        ),
                      ),
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

  static const _initialsStyle = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w600,
    color: SelmsColors.ink,
  );

  // ---------- left: equipment ----------

  Widget _equipmentColumn(int assigned, int needed) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _heading('EQUIPMENT TO PREPARE'),
        const SizedBox(height: 10),
        if (_items.isEmpty)
          const Text(
            'No equipment was requested for this hire.',
            style: TextStyle(fontSize: 12.5, color: SelmsColors.textMuted),
          )
        else ...[
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: needed == 0 ? 1 : assigned / needed,
              minHeight: 5,
              backgroundColor: SelmsColors.border,
              valueColor: AlwaysStoppedAnimation(
                _fulfilled
                    ? SelmsColors.statusActiveText
                    : const Color(0xFFF59E0B),
              ),
            ),
          ),
          const SizedBox(height: 10),
          ..._items.map(_itemRow),
        ],
        if (_extra.isNotEmpty) ...[
          const SizedBox(height: 10),
          _heading('ALSO ASSIGNED'),
          const SizedBox(height: 6),
          ..._extra.map(
            (a) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Text(
                '${a['name']}${(a['asset_tag'] as String?)?.isNotEmpty == true ? '  ·  ${a['asset_tag']}' : ''}',
                style: const TextStyle(
                  fontSize: 12,
                  color: SelmsColors.textSecondary,
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _itemRow(Map<String, dynamic> item) {
    final done = item['assigned'] == true;
    final asset = (item['asset'] as Map?)?.cast<String, dynamic>();
    final tag = (asset?['asset_tag'] as String?) ?? '';
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: done
            ? SelmsColors.statusActiveBg.withValues(alpha: 0.5)
            : SelmsColors.fieldBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: SelmsColors.border),
      ),
      child: Row(
        children: [
          Icon(
            done ? Icons.check_circle : Icons.radio_button_unchecked,
            size: 18,
            color: done ? SelmsColors.statusActiveText : SelmsColors.textMuted,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item['type'] as String? ?? '',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: SelmsColors.textPrimary,
                  ),
                ),
                Text(
                  done
                      ? '${asset?['name'] ?? ''}${tag.isNotEmpty ? '  ·  $tag' : ''}'
                      : 'Not assigned yet',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: done
                        ? SelmsColors.textSecondary
                        : SelmsColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---------- right: employee + account ----------

  Widget _detailsColumn() {
    final location = _emp['work_location_type'] as String? ?? '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _heading('EMPLOYEE'),
        const SizedBox(height: 6),
        _fact(
          'Start date',
          (_emp['hire_date'] as String?)?.isNotEmpty == true
              ? _emp['hire_date'] as String
              : 'TBC',
        ),
        _fact('Work location', location.isEmpty ? '—' : location),
        _fact(
          'Line manager',
          (_emp['line_manager'] as String?)?.isNotEmpty == true
              ? _emp['line_manager'] as String
              : '—',
        ),
        _fact(
          'Personal email',
          _emp['personal_email'] as String? ?? '—',
          copy: true,
        ),
        _fact('Phone', _emp['mobile_number'] as String? ?? '—', copy: true),
        const SizedBox(height: 14),
        _heading('MICROSOFT ACCOUNT'),
        const SizedBox(height: 6),
        if (!_open)
          const Text(
            'Credentials are removed once a request is cancelled.',
            style: TextStyle(fontSize: 12, color: SelmsColors.textMuted),
          )
        else ...[
          _fact(
            'Account email',
            _account['email'] as String? ?? '—',
            copy: true,
          ),
          _passwordRow(),
          const SizedBox(height: 4),
          const Text(
            'One-time password for creating the account. Ask the employee to change it at first sign-in.',
            style: TextStyle(
              fontSize: 11,
              color: SelmsColors.textMuted,
              height: 1.35,
            ),
          ),
        ],
        const SizedBox(height: 14),
        _heading('DELIVERY'),
        const SizedBox(height: 6),
        if (_r['needs_shipping'] != true)
          Row(
            children: [
              const Icon(
                Icons.business_outlined,
                size: 15,
                color: SelmsColors.textSecondary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  location.isEmpty
                      ? 'Collects equipment at the office.'
                      : '$location — collects equipment at the office. No posting needed.',
                  style: const TextStyle(
                    fontSize: 12,
                    color: SelmsColors.textSecondary,
                  ),
                ),
              ),
            ],
          )
        else ...[
          Row(
            children: [
              const Icon(
                Icons.local_shipping_outlined,
                size: 15,
                color: SelmsColors.textSecondary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _r['shipment'] == null
                      ? '$location employee — equipment needs to be posted to:'
                      : 'Shipment ${_shipmentLabel((_r['shipment'] as Map)['status'] as String)} — posting to:',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: SelmsColors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          _fact('Address', _emp['address_line'] as String? ?? '—', copy: true),
          _fact('Postcode', _emp['postcode'] as String? ?? '—', copy: true),
          _fact('State', _emp['state'] as String? ?? '—', copy: true),
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

  Widget _passwordRow() {
    final pw = _account['initial_password'] as String?;
    if (pw == null || pw.isEmpty) {
      return _fact('Initial password', 'Not available');
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          const SizedBox(
            width: 108,
            child: Text(
              'Initial password',
              style: TextStyle(fontSize: 11.5, color: SelmsColors.textMuted),
            ),
          ),
          Expanded(
            child: SelectableText(
              _showPassword ? pw : '•' * pw.length,
              style: const TextStyle(
                fontSize: 12.5,
                color: SelmsColors.textPrimary,
                letterSpacing: 0.5,
              ),
            ),
          ),
          _iconBtn(
            _showPassword
                ? Icons.visibility_off_outlined
                : Icons.visibility_outlined,
            () => setState(() => _showPassword = !_showPassword),
          ),
          _iconBtn(Icons.copy, () => _copy('Password', pw)),
        ],
      ),
    );
  }

  Widget _fact(String label, String value, {bool copy = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(
            width: 108,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 11.5,
                color: SelmsColors.textMuted,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 12.5,
                color: SelmsColors.textPrimary,
              ),
            ),
          ),
          if (copy && value != '—')
            _iconBtn(Icons.copy, () => _copy(label, value)),
        ],
      ),
    );
  }

  Widget _iconBtn(IconData icon, VoidCallback onTap) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(6),
    child: Padding(
      padding: const EdgeInsets.all(4),
      child: Icon(icon, size: 15, color: SelmsColors.textSecondary),
    ),
  );

  Widget _heading(String t) => Text(
    t,
    style: const TextStyle(
      fontSize: 10.5,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.6,
      color: SelmsColors.textMuted,
    ),
  );

  Widget _chip(String text, Color bg, Color fg) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color: bg,
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      text,
      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: fg),
    ),
  );
}


/// What to collect back from someone being offboarded. Read live from the
/// equipment records: an item counts as returned only once IT has really
/// retrieved it (via the Products / Scan screens) - there is no tick box.
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
  /// Reloads the list after IT records an item (e.g. as lost).
  final VoidCallback? onChanged;

  @override
  State<_ReturnCard> createState() => _ReturnCardState();
}

class _ReturnCardState extends State<_ReturnCard> {
  late bool _expanded = widget.data['fulfilled'] != true;

  Map<String, dynamic> get _d => widget.data;
  Map<String, dynamic> get _emp => (_d['employee'] as Map).cast<String, dynamic>();
  List<Map<String, dynamic>> get _items => (_d['items'] as List).cast<Map<String, dynamic>>();
  bool get _fulfilled => _d['fulfilled'] == true;

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

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final name = _emp['full_name'] as String? ?? '';
    final returned = (_d['returned_count'] as num).toInt();
    final total = (_d['total_count'] as num).toInt();
    final lastDay = _d['last_working_day'] as String?;
    final photo = _emp['profile_image_url'] as String?;

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
                  Container(
                    width: 42,
                    height: 42,
                    clipBehavior: Clip.hardEdge,
                    decoration: const BoxDecoration(color: SelmsColors.accentBg, shape: BoxShape.circle),
                    alignment: Alignment.center,
                    child: (photo != null && photo.isNotEmpty)
                        ? Image.network('${widget.apiBaseUrl}$photo',
                            fit: BoxFit.cover,
                            width: 42,
                            height: 42,
                            errorBuilder: (_, _, _) => Text(_initials(name),
                                style: const TextStyle(
                                    fontSize: 13, fontWeight: FontWeight.w600, color: SelmsColors.ink)))
                        : Text(_initials(name),
                            style: const TextStyle(
                                fontSize: 13, fontWeight: FontWeight.w600, color: SelmsColors.ink)),
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
                                      fontSize: 14.5, fontWeight: FontWeight.w600, color: SelmsColors.textPrimary)),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFAECE7),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Text('Equipment return',
                                  style: TextStyle(
                                      fontSize: 10.5, fontWeight: FontWeight.w600, color: Color(0xFF993C1D))),
                            ),
                            if (!_fulfilled && _d['posted_at'] != null) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: SelmsColors.accentBg,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Text('Posted by employee',
                                    style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: SelmsColors.ink)),
                              ),
                            ],
                            if (!_fulfilled && _d['ready_at'] != null) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: SelmsColors.statusActiveBg,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Text('Ready to return',
                                    style: TextStyle(
                                        fontSize: 10.5, fontWeight: FontWeight.w600, color: SelmsColors.statusActiveText)),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${_emp['employee_id'] ?? ''} · ${_emp['department'] ?? ''}'
                          '${lastDay != null && lastDay.isNotEmpty ? ' · Last working day $lastDay' : ''}',
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 11.5, color: SelmsColors.textMuted),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: _fulfilled ? SelmsColors.statusActiveBg : SelmsColors.accentBg,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      _fulfilled ? 'All returned' : '$returned of $total returned',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: _fulfilled ? SelmsColors.statusActiveText : SelmsColors.ink,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(_expanded ? Icons.expand_less : Icons.expand_more, size: 20, color: SelmsColors.textMuted),
                ],
              ),
            ),
          ),
          if (_expanded) ...[
            const Divider(height: 1, color: SelmsColors.border),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_items.isEmpty)
                    const Text('No equipment is assigned to this person — nothing to collect.',
                        style: TextStyle(fontSize: 12.5, color: SelmsColors.textSecondary))
                  else
                    ..._items.map((it) {
                      final done = it['returned'] == true;
                      final tag = (it['asset_tag'] as String?) ?? '';
                      final prep = (it['prep'] as Map?)?.cast<String, dynamic>();
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                          children: [
                            Icon(done ? Icons.check_circle : Icons.hourglass_top,
                                size: 16,
                                color: done ? SelmsColors.statusActiveText : SelmsColors.textMuted),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                '${it['name'] ?? it['type'] ?? 'Item'}'
                                '${it['type'] != null && it['name'] != null ? ' · ${it['type']}' : ''}'
                                '${tag.isNotEmpty ? ' · $tag' : ''}',
                                style: TextStyle(
                                  fontSize: 12.5,
                                  color: done ? SelmsColors.textMuted : SelmsColors.textPrimary,
                                  decoration: done ? TextDecoration.lineThrough : null,
                                ),
                              ),
                            ),
                          ],
                        ),
                            // Not coming back: IT can close it off as lost.
                            if (!done)
                              Padding(
                                padding: const EdgeInsets.only(left: 26, top: 2),
                                child: TextButton(
                                  onPressed: () => _markLost(it, prep),
                                  style: TextButton.styleFrom(
                                      padding: EdgeInsets.zero,
                                      minimumSize: const Size(0, 0),
                                      visualDensity: VisualDensity.compact),
                                  child: Text(prep?['condition'] == 'Lost' ? 'Employee reported it lost — mark as lost' : 'Mark as lost',
                                      style: const TextStyle(fontSize: 11, color: SelmsColors.rose)),
                                ),
                              ),
                            // What the employee said before handing it back.
                            if (!done && prep != null)
                              Padding(
                                padding: const EdgeInsets.only(left: 26, top: 2),
                                child: Text(_prepText(prep),
                                    style: TextStyle(
                                        fontSize: 11,
                                        color: prep['condition'] == 'Good'
                                            ? SelmsColors.textSecondary
                                            : const Color(0xFF993C1D))),
                              ),
                          ],
                        ),
                      );
                    }),
                  const SizedBox(height: 10),
                  const Text(
                    'Retrieve each item from Products (or scan its QR). It is marked returned here '
                    'automatically; the exit interview is booked once everything is back.',
                    style: TextStyle(fontSize: 11.5, color: SelmsColors.textMuted, height: 1.4),
                  ),
                  if (!_fulfilled) ...[
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: () => Navigator.of(context).pushReplacement(
                        MaterialPageRoute(
                          builder: (_) => ItProductsScreen(
                            apiBaseUrl: widget.apiBaseUrl,
                            itToken: widget.itToken,
                          ),
                        ),
                      ),
                      icon: const Icon(Icons.inventory_2_outlined, size: 15),
                      label: const Text('Open Products', style: TextStyle(fontSize: 12)),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
