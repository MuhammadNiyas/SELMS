// lib/screens/lifecycle_insights_screen.dart
//
// The monitoring side of the lifecycle: where HR *watches* everyone who is
// currently onboarding or offboarding, instead of acting on one person at a
// time (that's the Onboarding / Offboarding tabs). One table covers both
// processes; each row expands to show its step-by-step timeline.
//
// The status pill (on track / at risk / delayed) is computed server-side by
// a single function (_lifecycle_status in selms_backend.py), so an ML model
// can replace those rules later without this screen changing.

import 'dart:async';
import 'package:flutter/material.dart';
import '../services/api_client.dart';
import '../theme/selms_colors.dart';
import '../widgets/app_shell.dart';
import '../widgets/flow_items_panel.dart';
import 'employee_view_screen.dart';
import 'onboarding_stepper_screen.dart';

class LifecycleInsightsScreen extends StatefulWidget {
  const LifecycleInsightsScreen({
    super.key,
    required this.apiBaseUrl,
    required this.hrToken,
    this.focusEmployeeId,
    this.focusProcess,
  });

  final String apiBaseUrl;
  final String hrToken;
  /// Opened from somewhere about one person (e.g. the Smart Schedule): the list
  /// is searched for them and their row is opened.
  final String? focusEmployeeId;
  final String? focusProcess; // 'onboarding' | 'offboarding'

  @override
  State<LifecycleInsightsScreen> createState() => _LifecycleInsightsScreenState();
}

class _LifecycleInsightsScreenState extends State<LifecycleInsightsScreen> {
  late final ApiClient _api = ApiClient(baseUrl: widget.apiBaseUrl, hrToken: widget.hrToken);
  final _searchCtrl = TextEditingController();
  Timer? _poll;

  Map<String, dynamic> _summary = {};
  List<Map<String, dynamic>> _records = [];
  bool _loading = true;
  String? _error;

  String _processFilter = 'all'; // all | onboarding | offboarding
  String? _statusFilter; // null = any status
  bool _showCompleted = false; // finished ones leave the list unless asked for
  String? _expandedKey;

  static const double _tableMinWidth = 1020;

  @override
  void initState() {
    super.initState();
    final focus = widget.focusEmployeeId;
    if (focus != null) {
      _searchCtrl.text = focus;
      if (widget.focusProcess != null) _expandedKey = '$focus:${widget.focusProcess}';
    }
    _load();
    // Quiet refresh so the page tracks employees acting on their own phones.
    _poll = Timer.periodic(const Duration(seconds: 30), (_) => _load(silent: true));
  }

  @override
  void dispose() {
    _poll?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final data = await _api.lifecycleOverview();
      if (!mounted) return;
      setState(() {
        _summary = (data['summary'] as Map).cast<String, dynamic>();
        _records = (data['records'] as List).cast<Map<String, dynamic>>();
        _loading = false;
        _error = null;
        // The focused person's process may already be finished: show completed ones then.
        if (!silent && _expandedKey != null &&
            _records.any((r) => _keyOf(r) == _expandedKey && r['status'] == 'completed')) {
          _showCompleted = true;
        }
      });
    } catch (e) {
      if (!mounted || silent) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  String _keyOf(Map<String, dynamic> r) => '${r['employee_id']}:${r['process']}';

  List<Map<String, dynamic>> get _filtered {
    final q = _searchCtrl.text.trim().toLowerCase();
    return _records.where((r) {
      if (_processFilter != 'all' && r['process'] != _processFilter) return false;
      if (_statusFilter != null && r['status'] != _statusFilter) return false;
      if (!_showCompleted && _statusFilter != 'completed' && r['status'] == 'completed') return false;
      if (q.isEmpty) return true;
      return (r['full_name'] as String? ?? '').toLowerCase().contains(q) ||
          (r['employee_id'] as String? ?? '').toLowerCase().contains(q) ||
          (r['department'] as String? ?? '').toLowerCase().contains(q);
    }).toList();
  }

  void _openDetail(Map<String, dynamic> r) {
    final id = r['employee_id'] as String;
    if (r['process'] == 'onboarding') {
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => OnboardingStepperScreen(
          apiBaseUrl: widget.apiBaseUrl,
          hrToken: widget.hrToken,
          employeeId: id,
          fullName: r['full_name'] as String,
        ),
      ));
    } else {
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => EmployeeViewScreen(
          apiBaseUrl: widget.apiBaseUrl,
          hrToken: widget.hrToken,
          employeeId: id,
        ),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppShell(
      apiBaseUrl: widget.apiBaseUrl,
      hrToken: widget.hrToken,
      activeRoute: SelmsRoute.insights,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(left: 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Lifecycle Insights',
                            style: TextStyle(
                                fontSize: 20, fontWeight: FontWeight.w600, color: SelmsColors.textPrimary)),
                        SizedBox(height: 2),
                        Text('Track everyone currently onboarding or offboarding, and spot who needs attention.',
                            style: TextStyle(fontSize: 12.5, color: SelmsColors.textMuted)),
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
                const SizedBox(width: 14),
                const TopBarActions(),
              ],
            ),
            const SizedBox(height: 18),
            Expanded(child: _buildBody()),
          ],
        ),
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

    final rows = _filtered;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _summaryCards(),
        const SizedBox(height: 14),
        _filterBar(),
        const SizedBox(height: 12),
        Expanded(
          child: Container(
            width: double.infinity,
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
            clipBehavior: Clip.antiAlias,
            child: _records.isEmpty
                ? _emptyState(
                    Icons.groups_outlined,
                    'No one is onboarding or offboarding right now',
                    'Start onboarding from the Onboarding tab, or initiate offboarding from an employee profile.',
                  )
                : rows.isEmpty
                    ? _emptyState(Icons.search_off, 'No matches', 'Try a different search or clear the filters.')
                    : _table(rows),
          ),
        ),
      ],
    );
  }

  // ---------- Summary cards ----------

  Widget _summaryCards() {
    int n(String k) => (_summary[k] as num?)?.toInt() ?? 0;
    return Row(
      children: [
        _summaryCard('Onboarding', n('onboarding_total'), Icons.login_outlined,
            SelmsColors.accentBg, SelmsColors.ink),
        const SizedBox(width: 12),
        _summaryCard('Offboarding', n('offboarding_total'), Icons.logout_outlined,
            SelmsColors.roseBg, SelmsColors.statusOffboardingText),
        const SizedBox(width: 12),
        _summaryCard('On track', n('on_track'), Icons.check_circle_outline,
            SelmsColors.statusActiveBg, SelmsColors.statusActiveText,
            status: 'on_track'),
        const SizedBox(width: 12),
        _summaryCard('At risk', n('at_risk'), Icons.warning_amber_rounded,
            SelmsColors.statusOnboardingBg, SelmsColors.statusOnboardingText,
            status: 'at_risk'),
        const SizedBox(width: 12),
        _summaryCard('Delayed', n('delayed'), Icons.schedule,
            SelmsColors.roseBg, SelmsColors.statusOffboardingText,
            status: 'delayed'),
      ],
    );
  }

  /// Cards that map to a status double as quick filters.
  Widget _summaryCard(String label, int value, IconData icon, Color bg, Color fg, {String? status}) {
    final selected = status != null && _statusFilter == status;
    return Expanded(
      child: InkWell(
        onTap: status == null
            ? null
            : () => setState(() => _statusFilter = selected ? null : status),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: selected ? fg : Colors.transparent, width: 1.5),
          ),
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
      ),
    );
  }

  // ---------- Filters ----------

  Widget _filterBar() {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10)),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _segment('All', 'all'),
              _segment('Onboarding', 'onboarding'),
              _segment('Offboarding', 'offboarding'),
            ],
          ),
        ),
        const SizedBox(width: 12),
        if (_statusFilter != null)
          InputChip(
            label: Text(_statusLabel(_statusFilter!), style: const TextStyle(fontSize: 11.5)),
            onDeleted: () => setState(() => _statusFilter = null),
            backgroundColor: Colors.white,
            side: const BorderSide(color: SelmsColors.border),
          ),
        const SizedBox(width: 12),
        FilterChip(
          label: Text('Show completed (${_records.where((r) => r['status'] == 'completed').length})',
              style: const TextStyle(fontSize: 11.5)),
          selected: _showCompleted,
          onSelected: (v) => setState(() => _showCompleted = v),
          backgroundColor: Colors.white,
          selectedColor: SelmsColors.accentBg,
          checkmarkColor: SelmsColors.ink,
          side: const BorderSide(color: SelmsColors.border),
        ),
        const Spacer(),
        Container(
          width: 280,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10)),
          child: Row(
            children: [
              const Icon(Icons.search, size: 16, color: SelmsColors.textMuted),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _searchCtrl,
                  onChanged: (_) => setState(() {}),
                  style: const TextStyle(fontSize: 13),
                  decoration: const InputDecoration(
                    hintText: 'Search name, ID or department',
                    hintStyle: TextStyle(fontSize: 12.5, color: SelmsColors.textMuted),
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(vertical: 11),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _segment(String label, String value) {
    final active = _processFilter == value;
    return InkWell(
      onTap: () => setState(() => _processFilter = value),
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

  // ---------- Table ----------

  Widget _table(List<Map<String, dynamic>> rows) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth < _tableMinWidth ? _tableMinWidth : constraints.maxWidth;
        return Scrollbar(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: width,
              height: constraints.maxHeight,
              child: Column(
                children: [
                  _tableHeader(),
                  const Divider(height: 1, color: SelmsColors.border),
                  Expanded(
                    child: ListView.separated(
                      itemCount: rows.length,
                      separatorBuilder: (_, _) => const Divider(height: 1, color: SelmsColors.border),
                      itemBuilder: (_, i) => _row(rows[i]),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // Column flex weights shared by the header and every row so they align.
  static const _cEmployee = 26;
  static const _cId = 11;
  static const _cDept = 14;
  static const _cProcess = 12;
  static const _cProgress = 17;
  static const _cStep = 18;
  static const _cTime = 11;
  static const _cStatus = 12;

  Widget _tableHeader() {
    Widget h(String t, int flex) => Expanded(
          flex: flex,
          child: Text(t.toUpperCase(),
              style: const TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.6,
                  color: SelmsColors.textMuted)),
        );
    return Container(
      color: SelmsColors.fieldBg,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      child: Row(
        children: [
          h('Employee', _cEmployee),
          h('Emp ID', _cId),
          h('Department', _cDept),
          h('Process', _cProcess),
          h('Progress', _cProgress),
          h('Current step', _cStep),
          h('Timeline', _cTime),
          h('Status', _cStatus),
          const SizedBox(width: 24),
        ],
      ),
    );
  }

  Widget _row(Map<String, dynamic> r) {
    final key = _keyOf(r);
    final expanded = _expandedKey == key;
    final progress = (r['progress_percent'] as num).toInt();
    final status = r['status'] as String;
    final name = r['full_name'] as String? ?? '';

    return Column(
      children: [
        InkWell(
          onTap: () => setState(() => _expandedKey = expanded ? null : key),
          child: Container(
            color: expanded ? SelmsColors.fieldBg : Colors.transparent,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            child: Row(
              children: [
                Expanded(
                  flex: _cEmployee,
                  child: Row(
                    children: [
                      _avatar(r, name),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(name,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontSize: 13, fontWeight: FontWeight.w500, color: SelmsColors.textPrimary)),
                            Text(r['job_title'] as String? ?? '',
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 11, color: SelmsColors.textMuted)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  flex: _cId,
                  child: Text(r['employee_id'] as String? ?? '',
                      style: const TextStyle(fontSize: 12, color: SelmsColors.textSecondary)),
                ),
                Expanded(
                  flex: _cDept,
                  child: Text(r['department'] as String? ?? '—',
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12, color: SelmsColors.textSecondary)),
                ),
                Expanded(flex: _cProcess, child: Align(alignment: Alignment.centerLeft, child: _processPill(r['process'] as String))),
                Expanded(
                  flex: _cProgress,
                  child: Padding(
                    padding: const EdgeInsets.only(right: 18),
                    child: Row(
                      children: [
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: LinearProgressIndicator(
                              value: progress / 100,
                              minHeight: 6,
                              backgroundColor: SelmsColors.border,
                              valueColor: AlwaysStoppedAnimation(_statusColor(status)),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          width: 32,
                          child: Text('$progress%',
                              textAlign: TextAlign.right,
                              style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600)),
                        ),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  flex: _cStep,
                  child: Text(r['current_step'] as String? ?? 'All steps done',
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12, color: SelmsColors.textSecondary)),
                ),
                Expanded(
                  flex: _cTime,
                  child: Text(_timeline(r),
                      style: TextStyle(
                          fontSize: 12,
                          color: r['status'] == 'delayed' ? SelmsColors.rose : SelmsColors.textSecondary,
                          fontWeight: r['status'] == 'delayed' ? FontWeight.w600 : FontWeight.w400)),
                ),
                Expanded(flex: _cStatus, child: Align(alignment: Alignment.centerLeft, child: _statusPill(status))),
                SizedBox(
                  width: 24,
                  child: Icon(expanded ? Icons.expand_less : Icons.expand_more,
                      size: 18, color: SelmsColors.textMuted),
                ),
              ],
            ),
          ),
        ),
        if (expanded) _detail(r),
      ],
    );
  }

  Widget _detail(Map<String, dynamic> r) {
    final steps = (r['steps'] as List).cast<Map<String, dynamic>>();
    final isOffboarding = r['process'] == 'offboarding';
    final status = r['status'] as String;

    return Container(
      width: double.infinity,
      color: SelmsColors.fieldBg,
      padding: const EdgeInsets.fromLTRB(66, 4, 24, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 5,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('STEP TIMELINE',
                    style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.6,
                        color: SelmsColors.textMuted)),
                const SizedBox(height: 8),
                ...steps.map(_stepTile),
              ],
            ),
          ),
          const SizedBox(width: 32),
          Expanded(
            flex: 4,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('SUMMARY',
                    style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.6,
                        color: SelmsColors.textMuted)),
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _statusBg(status),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(r['status_reason'] as String? ?? '',
                      style: TextStyle(fontSize: 12, color: _statusFg(status), height: 1.35)),
                ),
                const SizedBox(height: 12),
                _fact('Started', _fmtDate(r['started_at'] as String?)),
                if (r['completed_at'] != null) _fact('Completed', _fmtDate(r['completed_at'] as String?)),
                if (isOffboarding && r['login_status'] != null) _fact('SELMS login', r['login_status'] as String),
                if (isOffboarding) ...[
                  _fact('Departure type', r['departure_type'] as String? ?? '—'),
                  _fact('Last working day', r['last_working_day'] as String? ?? '—'),
                ],
                const SizedBox(height: 12),
                ElevatedButton.icon(
                  onPressed: () => _openDetail(r),
                  icon: const Icon(Icons.open_in_new, size: 14),
                  label: Text(isOffboarding ? 'Open employee profile' : 'Open checklist',
                      style: const TextStyle(fontSize: 12)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: SelmsColors.ink,
                    foregroundColor: Colors.white,
                    elevation: 0,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
          // What the employee was given by the flow (documents, surveys) and
          // what has come back - HR reviews it right here.
          if (((r['documents'] as List?) ?? const []).isNotEmpty || ((r['surveys'] as List?) ?? const []).isNotEmpty) ...[
            const SizedBox(height: 18),
            FlowItemsPanel(
              key: ValueKey('items-${r['employee_id']}-${r['process']}'),
              api: ApiClient(baseUrl: widget.apiBaseUrl, hrToken: widget.hrToken),
              employeeId: r['employee_id'] as String,
              process: r['process'] as String?,
              initialDocuments: ((r['documents'] as List?) ?? const []).cast<Map<String, dynamic>>(),
              initialSurveys: ((r['surveys'] as List?) ?? const []).cast<Map<String, dynamic>>(),
              onChanged: _load,
            ),
          ],
        ],
      ),
    );
  }

  Widget _stepTile(Map<String, dynamic> s) {
    final done = s['done'] == true;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Icon(done ? Icons.check_circle : Icons.radio_button_unchecked,
              size: 17, color: done ? SelmsColors.statusActiveText : SelmsColors.textMuted),
          const SizedBox(width: 10),
          Expanded(
            child: Text(s['label'] as String? ?? '',
                style: TextStyle(
                    fontSize: 12.5,
                    color: done ? SelmsColors.textPrimary : SelmsColors.textSecondary,
                    fontWeight: done ? FontWeight.w500 : FontWeight.w400)),
          ),
          Text(done ? _fmtDate(s['done_at'] as String?, fallback: 'Done') : 'Pending',
              style: const TextStyle(fontSize: 11.5, color: SelmsColors.textMuted)),
        ],
      ),
    );
  }

  Widget _fact(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            SizedBox(
              width: 120,
              child: Text(label, style: const TextStyle(fontSize: 11.5, color: SelmsColors.textMuted)),
            ),
            Expanded(
              child: Text(value,
                  style: const TextStyle(fontSize: 12, color: SelmsColors.textPrimary)),
            ),
          ],
        ),
      );

  // ---------- Small pieces ----------

  Widget _avatar(Map<String, dynamic> r, String name) {
    final url = r['profile_image_url'] as String?;
    final initials = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .take(2)
        .map((p) => p[0].toUpperCase())
        .join();
    final fallback = Text(initials,
        style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: SelmsColors.ink));
    return Container(
      width: 34,
      height: 34,
      clipBehavior: Clip.hardEdge,
      decoration: const BoxDecoration(color: SelmsColors.accentBg, shape: BoxShape.circle),
      alignment: Alignment.center,
      child: (url != null && url.isNotEmpty)
          ? Image.network('${widget.apiBaseUrl}$url',
              fit: BoxFit.cover, width: 34, height: 34, errorBuilder: (_, _, _) => fallback)
          : fallback,
    );
  }

  Widget _pill(String text, Color bg, Color fg) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
        child: Text(text, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: fg)),
      );

  Widget _processPill(String process) => process == 'onboarding'
      ? _pill('Onboarding', SelmsColors.accentBg, SelmsColors.ink)
      : _pill('Offboarding', SelmsColors.statusOffboardingBg, SelmsColors.statusOffboardingText);

  Widget _statusPill(String status) => _pill(_statusLabel(status), _statusBg(status), _statusFg(status));

  String _statusLabel(String s) => switch (s) {
        'on_track' => 'On track',
        'at_risk' => 'At risk',
        'delayed' => 'Delayed',
        'completed' => 'Completed',
        _ => s,
      };

  Color _statusBg(String s) => switch (s) {
        'on_track' => SelmsColors.statusActiveBg,
        'at_risk' => SelmsColors.statusOnboardingBg,
        'delayed' => SelmsColors.statusOffboardingBg,
        _ => SelmsColors.accentBg,
      };

  Color _statusFg(String s) => switch (s) {
        'on_track' => SelmsColors.statusActiveText,
        'at_risk' => SelmsColors.statusOnboardingText,
        'delayed' => SelmsColors.statusOffboardingText,
        _ => SelmsColors.ink,
      };

  Color _statusColor(String s) => switch (s) {
        'on_track' => const Color(0xFF10B981),
        'at_risk' => const Color(0xFFF59E0B),
        'delayed' => const Color(0xFFEF4444),
        _ => SelmsColors.ink,
      };

  /// "Day 4" while onboarding; "3d left" / "Overdue 2d" while offboarding.
  String _timeline(Map<String, dynamic> r) {
    if (r['process'] == 'onboarding') {
      final d = (r['days_elapsed'] as num?)?.toInt();
      return d == null ? '—' : 'Day ${d + 1}';
    }
    final left = (r['days_to_last_day'] as num?)?.toInt();
    if (left == null) return '—';
    if (left < 0) return 'Overdue ${-left}d';
    if (left == 0) return 'Last day today';
    return '${left}d left';
  }

  String _fmtDate(String? iso, {String fallback = '—'}) {
    final dt = iso == null ? null : DateTime.tryParse(iso)?.toLocal();
    if (dt == null) return fallback;
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    return '${dt.day} ${months[dt.month - 1]}, $hh:$mm';
  }

  Widget _emptyState(IconData icon, String title, String subtitle) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 38, color: SelmsColors.textMuted),
              const SizedBox(height: 12),
              Text(title,
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w600, color: SelmsColors.textPrimary)),
              const SizedBox(height: 6),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 380),
                child: Text(subtitle,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 12.5, color: SelmsColors.textMuted, height: 1.4)),
              ),
            ],
          ),
        ),
      );
}
