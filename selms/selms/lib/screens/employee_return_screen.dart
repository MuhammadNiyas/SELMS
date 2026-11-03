// lib/screens/employee_return_screen.dart
//
// The employee's side of handing equipment back when they leave, shown in
// the pop-up of the Offboarding tab's "Equipment Returned" step: what to
// return, by when and where (or by post for remote staff); a short
// checklist per item (data backed up, signed out, accessories, the condition
// and a note); and "I'm ready to return" so IT knows. Remote staff instead book the Pos
// Malaysia parcel themselves (to the company address shown here) and send
// IT the tracking number to review. An item only shows as
// returned once IT has really received it (Products / Scan) - there is no
// "returned" tick here.

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../services/api_client.dart';
import '../theme/selms_colors.dart';
import '../widgets/employee_ui.dart';

const _posTrackingUrl = 'https://tracking.pos.com.my/tracking';

/// Opens the "Return your equipment" pop-up (same style as "Collect IT equipment").
Future<void> showReturnEquipmentSheet(BuildContext context, ApiClient api, {String? subtitle}) {
  return showEmpSheet(
    context,
    icon: Icons.devices_other_outlined,
    title: 'Return your equipment',
    subtitle: subtitle,
    children: [EmployeeReturnPanel(api: api)],
  );
}

class EmployeeReturnPanel extends StatefulWidget {
  const EmployeeReturnPanel({super.key, required this.api});

  final ApiClient api;

  @override
  State<EmployeeReturnPanel> createState() => _EmployeeReturnPanelState();
}

const _checks = [
  ('backed_up', 'Data backed up / personal files removed'),
  ('signed_out', 'Signed out of company accounts'),
  ('accessories', 'Charger and accessories included'),
];
const _conditions = ['Good', 'Damaged', 'Lost'];

class _EmployeeReturnPanelState extends State<EmployeeReturnPanel> {
  Map<String, dynamic>? _data;
  String? _error;
  bool _busy = false;

  /// What the employee is filling in, per equipment id (saved with "Save").
  final Map<String, Map<String, dynamic>> _draft = {};
  final Map<String, TextEditingController> _notes = {};
  final _tracking = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in _notes.values) {
      c.dispose();
    }
    _tracking.dispose();
    super.dispose();
  }

  void _take(Map<String, dynamic> data) {
    _data = data;
    for (final it in _items) {
      final id = it['equipment_id'] as String;
      final prep = Map<String, dynamic>.from((it['prep'] as Map?) ?? const {});
      _draft[id] = prep;
      (_notes[id] ??= TextEditingController()).text = prep['note'] as String? ?? '';
    }
  }

  Future<void> _load() async {
    try {
      final data = await widget.api.getMyReturns();
      if (!mounted) return;
      setState(() {
        _take(data);
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  List<Map<String, dynamic>> get _items => ((_data?['items'] as List?) ?? const []).cast<Map<String, dynamic>>();
  List<Map<String, dynamic>> get _outstanding => _items.where((i) => i['returned'] != true).toList();

  /// Every item still with the employee has its checklist done and saved.
  bool get _allSaved =>
      _outstanding.isNotEmpty &&
      _outstanding.every((i) => _complete(i['prep'] as Map<String, dynamic>?) && !_unsaved(i));

  bool _complete(Map<String, dynamic>? p) {
    if (p == null || !_conditions.contains(p['condition'])) return false;
    return p['condition'] == 'Lost' || _checks.every((c) => p[c.$1] == true);
  }

  /// The saved checklist differs from what is on screen.
  bool _unsaved(Map<String, dynamic> it) {
    final id = it['equipment_id'] as String;
    final saved = (it['prep'] as Map?) ?? const {};
    final d = _draft[id] ?? const {};
    return _checks.any((c) => (saved[c.$1] == true) != (d[c.$1] == true)) ||
        saved['condition'] != d['condition'] ||
        (saved['note'] as String? ?? '') != (_notes[id]?.text.trim() ?? '');
  }

  Future<void> _run(Future<Map<String, dynamic>> Function() call, String done) async {
    setState(() => _busy = true);
    try {
      final data = await call();
      if (!mounted) return;
      setState(() => _take(data));
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(done)));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _save(Map<String, dynamic> it) {
    final id = it['equipment_id'] as String;
    final d = _draft[id] ?? {};
    _run(
        () => widget.api.saveReturnPrep(id, {
              for (final c in _checks) c.$1: d[c.$1] == true,
              'condition': d['condition'],
              'note': _notes[id]?.text.trim() ?? '',
            }),
        'Saved.');
  }

  Widget _statusPill(Map<String, dynamic> it) {
    if (it['returned'] != true) return const EmpPill('With you', bg: EmpColors.warningBg, fg: EmpColors.warning);
    final when = empDate(it['returned_at'] as String?);
    return switch (it['outcome']) {
      'lost' => const EmpPill('Recorded lost', bg: Color(0xFFF1F5F9), fg: SelmsColors.textSecondary),
      'damaged' => EmpPill('Returned $when · damaged', bg: EmpColors.successBg, fg: EmpColors.success, icon: Icons.check),
      _ => EmpPill('Returned $when', bg: EmpColors.successBg, fg: EmpColors.success, icon: Icons.check),
    };
  }

  Widget _checklist(Map<String, dynamic> it) {
    final id = it['equipment_id'] as String;
    final d = _draft[id] ??= {};
    final lost = d['condition'] == 'Lost';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 10),
        const Divider(height: 1, color: SelmsColors.border),
        const SizedBox(height: 10),
        const Text('BEFORE YOU RETURN',
            style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, letterSpacing: 0.7, color: SelmsColors.textMuted)),
        const SizedBox(height: 4),
        if (!lost)
          for (final c in _checks)
            InkWell(
              onTap: () => setState(() => d[c.$1] = !(d[c.$1] == true)),
              child: Row(
                children: [
                  Checkbox(
                    value: d[c.$1] == true,
                    visualDensity: VisualDensity.compact,
                    onChanged: (v) => setState(() => d[c.$1] = v == true),
                  ),
                  Expanded(child: Text(c.$2, style: const TextStyle(fontSize: 12.5))),
                ],
              ),
            ),
        const SizedBox(height: 6),
        const Text('Condition', style: TextStyle(fontSize: 11.5, color: SelmsColors.textSecondary)),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          children: [
            for (final c in _conditions)
              ChoiceChip(
                label: Text(c, style: const TextStyle(fontSize: 12)),
                selected: d['condition'] == c,
                onSelected: (_) => setState(() => d['condition'] = c),
              ),
          ],
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _notes[id] ??= TextEditingController(),
          onChanged: (_) => setState(() {}),
          maxLines: 2,
          style: const TextStyle(fontSize: 12.5),
          decoration: InputDecoration(
            isDense: true,
            hintText: lost ? 'What happened? (optional)' : 'Anything IT should know? (optional)',
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: Text(
                _complete(it['prep'] as Map<String, dynamic>?) && !_unsaved(it)
                    ? 'Checklist saved.'
                    : lost
                        ? 'Reporting it lost - save to let IT know.'
                        : 'Tick all three and choose the condition, then Save.',
                style: const TextStyle(fontSize: 11, color: SelmsColors.textMuted),
              ),
            ),
            ElevatedButton(
              onPressed: _busy || !_complete(d) || !_unsaved(it) ? null : () => _save(it),
              style: ElevatedButton.styleFrom(backgroundColor: SelmsColors.ink, foregroundColor: Colors.white),
              child: const Text('Save'),
            ),
          ],
        ),
      ],
    );
  }

  /// The QR code screenshot Pos gave for the return parcel - IT sees it on the shipment.
  Future<void> _pickQr() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 90);
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    final name = picked.name.contains('.') ? picked.name : 'qr.png';
    await _run(() => widget.api.uploadMyReturnQr(bytes, name), 'QR code uploaded - IT can see it.');
  }

  Widget _qrUpload(Map<String, dynamic> data) {
    final url = data['qr_image_url'] as String?;
    if (url == null || url.isEmpty) {
      return EmpSheetButton(
        label: 'Upload the QR code from Pos',
        icon: Icons.qr_code_2,
        primary: false,
        onPressed: _busy ? () {} : _pickQr,
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Container(
            width: 110,
            height: 110,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: SelmsColors.border),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Image.network('${widget.api.baseUrl}$url',
                fit: BoxFit.contain,
                errorBuilder: (_, _, _) => const Center(child: Icon(Icons.broken_image_outlined))),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('QR code uploaded - IT can see it.',
                    style: TextStyle(fontSize: 12, color: SelmsColors.textSecondary)),
                TextButton(onPressed: _busy ? null : _pickQr, child: const Text('Replace')),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Remote staff: where to send the parcel, a link to book it on Pos
  /// Malaysia, then the tracking number - which goes to IT to review.
  Widget _byPost(Map<String, dynamic> data) {
    final s = (data['shipment'] as Map?)?.cast<String, dynamic>();
    final ref = s?['pos_reference'] as String? ?? '';
    final postedAt = data['posted_at'] as String?;
    final company = ((data['company'] as Map?) ?? const {}).cast<String, dynamic>();
    final rejected = (data['rejected'] as Map?)?.cast<String, dynamic>();
    final companyAddress = company['address'] as String? ?? '';
    final posUrl = data['pos_url'] as String? ?? 'https://send.pos.com.my/home/e-connote?lg=en';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const EmpSectionHeader('Return by post'),
        if (postedAt != null) ...[
          if (s != null) EmpShipmentTile(shipment: s),
          const SizedBox(height: 10),
          if (ref.isNotEmpty) ...[
            EmpCopyRow(label: 'Your tracking number', value: ref),
            EmpSheetButton(
              label: 'Track on Pos Malaysia',
              icon: Icons.local_shipping_outlined,
              onPressed: () => empOpenUrl(s?['tracking_url'] as String? ?? _posTrackingUrl),
            ),
          ],
          EmpSheetText('Sent to IT on ${empDate(postedAt)}. IT checks your parcel and ticks each item off when it arrives.'),
          _qrUpload(data),
        ] else ...[
          if (rejected != null)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: EmpColors.warningBg, borderRadius: BorderRadius.circular(10)),
              child: Text(
                "IT couldn't accept your last parcel details"
                '${(rejected['reason'] as String? ?? '').isNotEmpty ? ': ${rejected['reason']}' : ''}. '
                'Please check them and send the tracking number and QR code again.',
                style: const TextStyle(fontSize: 12.5, color: EmpColors.warning, height: 1.35),
              ),
            ),
          const EmpSheetText('You work remotely, so you post your equipment back with Pos Malaysia. '
              'Finish the checklist for each item above, pack them, then follow the steps below.'),
          const EmpSheetText('Send the parcel to this address.', heading: '1. Where it goes'),
          if (companyAddress.isEmpty)
            const EmpSheetText("IT hasn't added the company's return address yet - message IT before you post anything.")
          else ...[
            if ((company['name'] as String? ?? '').isNotEmpty) EmpCopyRow(label: 'Company', value: company['name'] as String),
            EmpCopyRow(label: 'Address', value: companyAddress),
            if ((company['phone'] as String? ?? '').isNotEmpty) EmpCopyRow(label: 'Phone', value: company['phone'] as String),
          ],
          const EmpSheetText('Book the parcel on Pos Malaysia (e-Connote). Use the address above as the receiver '
              'and your own details as the sender, then drop it at a Pos counter.', heading: '2. Book the parcel'),
          EmpSheetButton(
            label: 'Create the parcel on Pos Malaysia',
            icon: Icons.open_in_new,
            onPressed: () => empOpenUrl(posUrl),
          ),
          const EmpSheetText('Upload the QR code Pos gave you, type the tracking number and send it to IT. '
              'IT reviews it and receives each item when the parcel arrives.', heading: '3. Send it to IT'),
          _qrUpload(data),
          TextField(
            controller: _tracking,
            onChanged: (_) => setState(() {}),
            style: const TextStyle(fontSize: 13),
            decoration: const InputDecoration(
              isDense: true,
              border: OutlineInputBorder(),
              labelText: 'Pos Malaysia tracking number',
              hintText: 'e.g. EP123456789MY',
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _busy || !_allSaved || _tracking.text.trim().isEmpty
                  ? null
                  : () => _run(() => widget.api.markReturnPosted(_tracking.text.trim()),
                      "Sent to IT - they'll check your parcel."),
              style: ElevatedButton.styleFrom(
                backgroundColor: EmpColors.leaving,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 13),
              ),
              child: const Text('Send to IT'),
            ),
          ),
          const SizedBox(height: 6),
          Center(
            child: Text(
              !_allSaved ? 'Save the checklist for each item first.' : 'IT gets your tracking number to review.',
              style: const TextStyle(fontSize: 11.5, color: SelmsColors.textMuted),
            ),
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    if (_error != null) return EmpSheetText(_error!, heading: 'Could not load');
    if (data == null) return const Padding(padding: EdgeInsets.all(8), child: LinearProgressIndicator(minHeight: 2));
    if (data['started'] != true) return const EmpSheetText('Offboarding is not active for you.');

    final total = _items.length;
    final back = total - _outstanding.length;
    final readyAt = data['ready_at'] as String?;
    final byPost = data['by_post'] == true;
    final allSaved = _allSaved;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: EmpColors.leavingBg, borderRadius: BorderRadius.circular(12)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                data['last_working_day'] == null
                    ? 'Return your equipment'
                    : 'Return by ${empDate(data['last_working_day'] as String?, weekday: true)}',
                style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: EmpColors.leaving),
              ),
              const Text('Your last working day', style: TextStyle(fontSize: 11.5, color: SelmsColors.textSecondary)),
              const SizedBox(height: 8),
              Text(byPost ? 'Return by: Pos Malaysia (see below)' : 'Bring them to: ${data['location'] ?? 'the IT department'}',
                  style: const TextStyle(fontSize: 12.5, color: SelmsColors.textPrimary)),
              const SizedBox(height: 8),
              EmpPill(
                  total == 0
                      ? (data['nothing_to_collect_at'] != null ? 'Nothing to return' : 'IT is checking')
                      : '$back of $total returned',
                  bg: Colors.white,
                  fg: EmpColors.leaving),
            ],
          ),
        ),
        const EmpSectionHeader('Your items'),
        if (total == 0)
          EmpSheetText(data['nothing_to_collect_at'] != null
              ? 'IT has confirmed you have no company equipment to return.'
              : 'No company equipment is on record for you. IT will check and confirm - '
                  'if you do have anything (laptop, phone, badge, accessories), bring it to '
                  '${data['location'] ?? 'the IT department'} or message IT.')
        else
          for (final it in _items)
            EmpEquipmentTile(
              item: it,
              baseUrl: widget.api.baseUrl,
              trailing: _statusPill(it),
              child: it['returned'] == true ? null : _checklist(it),
            ),
        if (total > 0) ...[
          const SizedBox(height: 6),
          if (_outstanding.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: EmpColors.successBg, borderRadius: BorderRadius.circular(12)),
              child: const Text('Everything is back with IT — thank you!',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: EmpColors.success)),
            )
          else if (byPost)
            _byPost(data)
          else if (readyAt != null)
            EmpSheetText(
              "IT has been told you're ready (${empDate(readyAt)}). "
              'Bring your items to ${data['location'] ?? 'the IT department'}. '
              'Each one is ticked off when IT receives it.',
            )
          else ...[
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _busy || !allSaved ? null : () => _run(() => widget.api.markReadyToReturn(), "IT has been told you're ready."),
                style: ElevatedButton.styleFrom(
                  backgroundColor: EmpColors.leaving,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 13),
                ),
                child: const Text("I'm ready to return"),
              ),
            ),
            const SizedBox(height: 6),
            Center(
              child: Text(
                allSaved ? 'IT will be told you are ready.' : 'Save the checklist for each item first.',
                style: const TextStyle(fontSize: 11.5, color: SelmsColors.textMuted),
              ),
            ),
          ],
        ],
      ],
    );
  }
}
