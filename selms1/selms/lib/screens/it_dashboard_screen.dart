// lib/screens/it_dashboard_screen.dart
//
// IT's home, laid out like HR's dashboard but about IT's own work:
//  * KPI cards - equipment, what is with employees, new hires to prepare,
//    leavers to collect from;
//  * Work queue - every open request / return, most urgent first, with its
//    progress, the next thing to do and the deadline (start date / last
//    working day), read from the same live tasks as the request cards;
//  * Parcels - Pos shipments waiting on IT; Next 7 days - sessions;
//  * Equipment (status + stock by type), warranties ending soon, messages.
// On a normal screen it all fits at once, like HR's: the cards fill the
// height and a long list scrolls inside its own card, not the page.
// Everything comes from GET /api/it/dashboard in one call.
//
// Colours follow the HR dashboard: magnitude in one blue, identity in the
// validated categorical slots, status in the reserved status colours -
// always with an icon and a word, never colour alone.

import 'package:flutter/material.dart';
import '../services/api_client.dart';
import '../theme/selms_colors.dart';
import '../widgets/app_shell.dart' show TopBarActions;
import '../widgets/employee_avatar.dart';
import '../widgets/it_app_shell.dart';
import 'equipment_detail_screen.dart';
import 'it_messages_screen.dart';
import 'it_products_screen.dart';
import 'it_requests_screen.dart';
import 'it_schedule_screen.dart';
import 'it_shipments_screen.dart';

const _blue = Color(0xFF2A78D6);
const _track = Color(0xFFEEF1F5);
const _cat = [Color(0xFF1BAF7A), Color(0xFF2A78D6), Color(0xFFEB6834), Color(0xFFB4B2A9)];
const _good = Color(0xFF0CA30C);
const _warning = Color(0xFFFAB219);
const _critical = Color(0xFFD03B3B);

class ItDashboardScreen extends StatefulWidget {
  const ItDashboardScreen({super.key, required this.apiBaseUrl, required this.itToken});

  final String apiBaseUrl;
  final String itToken;

  @override
  State<ItDashboardScreen> createState() => _ItDashboardScreenState();
}

class _ItDashboardScreenState extends State<ItDashboardScreen> {
  late final ApiClient _api = ApiClient(baseUrl: widget.apiBaseUrl, hrToken: widget.itToken);
  late Future<Map<String, dynamic>> _future = _api.getItDashboard();
  String _filter = 'all'; // all | onboarding | offboarding

  Future<void> _refresh() async {
    setState(() => _future = _api.getItDashboard());
    await _future;
  }

  void _go(Widget screen) => Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => screen));
  void _openMessages() => _go(ItMessagesScreen(apiBaseUrl: widget.apiBaseUrl, itToken: widget.itToken));
  void _openRequests() => _go(ItRequestsScreen(apiBaseUrl: widget.apiBaseUrl, itToken: widget.itToken));
  void _openProducts() => _go(ItProductsScreen(apiBaseUrl: widget.apiBaseUrl, itToken: widget.itToken));
  void _openSchedule() => _go(ItScheduleScreen(apiBaseUrl: widget.apiBaseUrl, itToken: widget.itToken));
  void _openShipments({String? direction}) =>
      _go(ItShipmentsScreen(apiBaseUrl: widget.apiBaseUrl, itToken: widget.itToken, initialDirection: direction));
  void _openEquipment(String id) => Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => EquipmentDetailScreen(apiBaseUrl: widget.apiBaseUrl, itToken: widget.itToken, equipmentId: id),
    ),
  );

  static const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  static const _weekdays = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];

  String _todayLabel() {
    final d = DateTime.now();
    return '${_weekdays[d.weekday - 1]}, ${d.day} ${_months[d.month - 1]} ${d.year}';
  }

  String _greeting() {
    final h = DateTime.now().hour;
    return h < 12 ? 'Good morning' : (h < 18 ? 'Good afternoon' : 'Good evening');
  }

  String _dayText(String? iso) {
    final d = DateTime.tryParse(iso ?? '');
    return d == null ? '—' : '${d.day} ${_months[d.month - 1]} ${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    return ItAppShell(
      apiBaseUrl: widget.apiBaseUrl,
      itToken: widget.itToken,
      activeRoute: ItRoute.dashboard,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(28, 24, 28, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _greeting(),
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                          color: SelmsColors.textPrimary,
                        ),
                      ),
                      Text(_todayLabel(), style: const TextStyle(fontSize: 12.5, color: SelmsColors.textSecondary)),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Refresh',
                  onPressed: _refresh,
                  icon: const Icon(Icons.refresh, size: 20, color: SelmsColors.textSecondary),
                ),
                const SizedBox(width: 8),
                const TopBarActions(),
              ],
            ),
            const SizedBox(height: 18),
            Expanded(
              child: FutureBuilder<Map<String, dynamic>>(
                future: _future,
                builder: (context, snap) {
                  if (snap.connectionState != ConnectionState.done) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snap.hasError) {
                    return Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Could not load the dashboard.\n${snap.error}',
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: SelmsColors.rose, fontSize: 13),
                          ),
                          const SizedBox(height: 10),
                          OutlinedButton(onPressed: _refresh, child: const Text('Try again')),
                        ],
                      ),
                    );
                  }
                  return RefreshIndicator(onRefresh: _refresh, child: _body(snap.data!));
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _body(Map<String, dynamic> d) {
    final eq = (d['equipment'] as Map).cast<String, dynamic>();
    final queue = ((d['queue'] as List?) ?? const []).cast<Map<String, dynamic>>();
    final dueSoon = queue.where((q) => q['status'] != 'on_track').length;
    final newHires = queue.where((q) => q['process'] == 'onboarding').toList();
    final leavers = queue.where((q) => q['process'] == 'offboarding').toList();
    final toCollect = leavers.fold<int>(
      0,
      (sum, q) => sum + ((q['total_count'] as int? ?? 0) - (q['done_count'] as int? ?? 0)),
    );
    final parcels = (d['parcels'] as Map).cast<String, dynamic>();
    final sessions = ((d['upcoming_sessions'] as List?) ?? const []).cast<Map<String, dynamic>>();
    final warranties = ((d['warranties'] as List?) ?? const []).cast<Map<String, dynamic>>();
    final unread = d['unread_messages'] as int? ?? 0;

    Widget kpis(double width) {
      final cards = [
        _kpi(
          icon: Icons.inventory_2_outlined,
          label: 'Equipment',
          value: '${eq['total'] ?? 0}',
          sub: '${eq['available'] ?? 0} available in stock',
          onTap: _openProducts,
        ),
        _kpi(
          icon: Icons.laptop_mac_outlined,
          label: 'With employees',
          value: '${eq['assigned'] ?? 0}',
          sub: 'Held by ${eq['holders'] ?? 0} ${(eq['holders'] ?? 0) == 1 ? 'person' : 'people'}',
          onTap: _openProducts,
        ),
        _kpi(
          icon: Icons.person_add_alt_outlined,
          label: 'New hires to prepare',
          value: '${newHires.length}',
          sub: newHires.isEmpty
              ? 'Nothing to prepare'
              : '${newHires.where((q) => q['status'] != 'on_track').length} starting within 3 days',
          onTap: _openRequests,
        ),
        _kpi(
          icon: dueSoon > 0 ? Icons.error_outline : Icons.assignment_return_outlined,
          iconColor: dueSoon > 0 ? _critical : SelmsColors.ink,
          label: 'Equipment to collect',
          value: '$toCollect',
          sub: leavers.isEmpty ? 'No one is leaving' : 'From ${leavers.length} leaver${leavers.length == 1 ? '' : 's'}',
          onTap: _openRequests,
        ),
      ];
      final perRow = width > 900 ? 4 : 2;
      final w = (width - (perRow - 1) * 14) / perRow;
      return Wrap(
        spacing: 14,
        runSpacing: 14,
        children: [for (final k in cards) SizedBox(width: w, child: k)],
      );
    }

    return LayoutBuilder(
      builder: (context, c) {
        // Wide enough and tall enough: everything on one screen.
        if (c.maxWidth >= 900 && c.maxHeight >= 520) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 20),
            child: Column(
              children: [
                kpis(c.maxWidth),
                const SizedBox(height: 14),
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(flex: 5, child: _queueCard(queue, fill: true)),
                      const SizedBox(width: 14),
                      Expanded(
                        flex: 3,
                        child: Column(
                          children: [
                            _parcelsCard(parcels),
                            const SizedBox(height: 14),
                            Expanded(child: _sessionsCard(sessions, fill: true)),
                          ],
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        flex: 3,
                        child: Column(
                          children: [
                            _equipmentCard(eq),
                            const SizedBox(height: 14),
                            Expanded(child: _warrantyCard(warranties, unread, fill: true)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        }
        // Small window: the same cards, one under another.
        return ListView(
          padding: const EdgeInsets.only(bottom: 28),
          children: [
            kpis(c.maxWidth),
            const SizedBox(height: 14),
            _queueCard(queue),
            const SizedBox(height: 14),
            _parcelsCard(parcels),
            const SizedBox(height: 14),
            _sessionsCard(sessions),
            const SizedBox(height: 14),
            _equipmentCard(eq),
            const SizedBox(height: 14),
            _warrantyCard(warranties, unread),
          ],
        );
      },
    );
  }

  // ---------------------------------------------------------------- pieces

  /// fill: the card takes the height it is given and its content scrolls
  /// inside it (the one-screen layout); footer stays pinned at the bottom.
  Widget _card({
    required String title,
    String? subtitle,
    Widget? trailing,
    required Widget child,
    Widget? footer,
    bool fill = false,
  }) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: SelmsColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: fill ? MainAxisSize.max : MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: SelmsColors.textPrimary),
                    ),
                    if (subtitle != null)
                      Text(subtitle, style: const TextStyle(fontSize: 11.5, color: SelmsColors.textMuted)),
                  ],
                ),
              ),
              ?trailing,
            ],
          ),
          const SizedBox(height: 10),
          if (fill) Expanded(child: SingleChildScrollView(child: child)) else child,
          ?footer,
        ],
      ),
    );
  }

  Widget _link(String label, VoidCallback onTap) => TextButton(
    onPressed: onTap,
    style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 6), minimumSize: const Size(0, 30)),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: const TextStyle(fontSize: 12, color: SelmsColors.ink)),
        const SizedBox(width: 2),
        const Icon(Icons.arrow_forward, size: 14, color: SelmsColors.ink),
      ],
    ),
  );

  Widget _kpi({
    required IconData icon,
    required String label,
    required String value,
    required String sub,
    Color iconColor = SelmsColors.ink,
    VoidCallback? onTap,
  }) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: SelmsColors.border),
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(color: SelmsColors.accentBg, borderRadius: BorderRadius.circular(10)),
                child: Icon(icon, size: 21, color: iconColor),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: const TextStyle(fontSize: 12, color: SelmsColors.textSecondary)),
                    Text(
                      value,
                      style: const TextStyle(
                        fontSize: 22,
                        height: 1.15,
                        fontWeight: FontWeight.w700,
                        color: SelmsColors.textPrimary,
                      ),
                    ),
                    Text(
                      sub,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11.5, color: SelmsColors.textMuted),
                    ),
                  ],
                ),
              ),
              if (onTap != null) const Icon(Icons.chevron_right, size: 18, color: SelmsColors.textMuted),
            ],
          ),
        ),
      ),
    );
  }

  Widget _bar(double fraction, {double height = 6, Color color = _blue}) => ClipRRect(
    borderRadius: BorderRadius.circular(4),
    child: SizedBox(
      height: height,
      child: Stack(
        children: [
          Container(color: _track),
          FractionallySizedBox(
            widthFactor: fraction.clamp(0, 1).toDouble(),
            child: Container(
              decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(4)),
            ),
          ),
        ],
      ),
    ),
  );

  /// Deadline status - always an icon and a word, never colour alone.
  Widget _statusPill(String status) {
    final (color, icon, label) = switch (status) {
      'overdue' => (_critical, Icons.error, 'Overdue'),
      'due_soon' => (_warning, Icons.warning_rounded, 'Due soon'),
      _ => (_good, Icons.check_circle, 'On track'),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: SelmsColors.textPrimary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _processPill(String process) {
    final on = process == 'onboarding';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: on ? SelmsColors.statusOnboardingBg : SelmsColors.statusOffboardingBg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        on ? 'New hire' : 'Leaving',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w600,
          color: on ? SelmsColors.statusOnboardingText : SelmsColors.statusOffboardingText,
        ),
      ),
    );
  }

  static const _headStyle = TextStyle(
    fontSize: 10,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.6,
    color: SelmsColors.textMuted,
  );

  // ---- the work queue

  Widget _queueCard(List<Map<String, dynamic>> all, {bool fill = false}) {
    final rows = _filter == 'all' ? all : all.where((r) => r['process'] == _filter).toList();
    Widget chip(String key, String label, int count) {
      final active = _filter == key;
      return Padding(
        padding: const EdgeInsets.only(left: 6),
        child: ChoiceChip(
          label: Text(
            '$label · $count',
            style: TextStyle(fontSize: 11.5, color: active ? Colors.white : SelmsColors.textSecondary),
          ),
          selected: active,
          showCheckmark: false,
          selectedColor: SelmsColors.ink,
          backgroundColor: Colors.white,
          side: BorderSide(color: active ? SelmsColors.ink : SelmsColors.border),
          visualDensity: VisualDensity.compact,
          onSelected: (_) => setState(() => _filter = key),
        ),
      );
    }

    return _card(
      fill: fill,
      footer: Align(alignment: Alignment.centerRight, child: _link('Open requests', _openRequests)),
      title: 'Work queue',
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          chip('all', 'All', all.length),
          chip('onboarding', 'New hires', all.where((r) => r['process'] == 'onboarding').length),
          chip('offboarding', 'Leaving', all.where((r) => r['process'] == 'offboarding').length),
        ],
      ),
      child: Column(
        children: [
          if (rows.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 28),
              child: Column(
                children: [
                  Icon(Icons.check_circle_outline, size: 30, color: _good),
                  SizedBox(height: 8),
                  Text('Nothing waiting on IT.', style: TextStyle(fontSize: 12.5, color: SelmsColors.textMuted)),
                ],
              ),
            )
          else ...[
            const Padding(
              padding: EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  Expanded(flex: 5, child: Text('EMPLOYEE', style: _headStyle)),
                  Expanded(flex: 4, child: Text('EQUIPMENT', style: _headStyle)),
                  Expanded(flex: 5, child: Text('NEXT', style: _headStyle)),
                  SizedBox(width: 104, child: Text('DEADLINE', style: _headStyle)),
                ],
              ),
            ),
            const Divider(height: 1, color: SelmsColors.border),
            for (final r in rows) _queueRow(r),
          ],
        ],
      ),
    );
  }

  Widget _queueRow(Map<String, dynamic> r) {
    final process = r['process'] as String? ?? 'onboarding';
    final done = r['done_count'] as int? ?? 0;
    final total = r['total_count'] as int? ?? 0;
    final days = r['days_left'] as int?;
    final when = days == null
        ? 'No date set'
        : days < 0
        ? '${-days} day${days == -1 ? '' : 's'} late'
        : days == 0
        ? 'Today'
        : 'In $days day${days == 1 ? '' : 's'}';
    return InkWell(
      onTap: _openRequests,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: Color(0xFFF1F3F5))),
        ),
        child: Row(
          children: [
            Expanded(
              flex: 5,
              child: Row(
                children: [
                  EmployeeAvatar(
                    apiBaseUrl: widget.apiBaseUrl,
                    name: r['full_name'] as String? ?? '?',
                    photoUrl: r['profile_image_url'] as String?,
                    size: 32,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          r['full_name'] as String? ?? '',
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Flexible(child: _processPill(process)),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                r['work_location_type'] as String? ?? '',
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 11, color: SelmsColors.textMuted),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              flex: 4,
              child: Padding(
                padding: const EdgeInsets.only(right: 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      total == 0
                          ? (process == 'onboarding' ? 'Nothing requested' : 'Nothing on record')
                          : '$done of $total ${process == 'onboarding' ? 'assigned' : 'received'}',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: SelmsColors.textPrimary),
                    ),
                    const SizedBox(height: 5),
                    _bar(total == 0 ? 0 : done / total),
                  ],
                ),
              ),
            ),
            Expanded(
              flex: 5,
              child: Text(
                r['next_task'] as String? ?? '—',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, color: SelmsColors.textSecondary),
              ),
            ),
            SizedBox(
              width: 104,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _statusPill(r['status'] as String? ?? ''),
                  const SizedBox(height: 3),
                  Text(when, style: const TextStyle(fontSize: 10.5, color: SelmsColors.textMuted)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---- parcels

  Widget _parcelsCard(Map<String, dynamic> p) {
    Widget row(IconData icon, String label, int n, {String? direction}) => InkWell(
      onTap: () => _openShipments(direction: direction),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Icon(icon, size: 16, color: SelmsColors.textSecondary),
            const SizedBox(width: 10),
            Expanded(
              child: Text(label, style: const TextStyle(fontSize: 12, color: SelmsColors.textSecondary)),
            ),
            Text(
              '$n',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: n > 0 ? SelmsColors.textPrimary : SelmsColors.textMuted,
              ),
            ),
            const Icon(Icons.chevron_right, size: 16, color: SelmsColors.textMuted),
          ],
        ),
      ),
    );
    return _card(
      title: 'Parcels',
      trailing: _link('Shipments', () => _openShipments()),
      child: Column(
        children: [
          row(Icons.add_box_outlined, 'To create on Pos', p['to_create'] as int? ?? 0),
          row(Icons.outbox_outlined, 'Booked, not posted yet', p['to_post'] as int? ?? 0),
          row(Icons.local_shipping_outlined, 'On the way to new hires', p['on_the_way'] as int? ?? 0),
          const Divider(height: 10, color: SelmsColors.border),
          row(Icons.fact_check_outlined, 'Returns to review', p['returns_to_review'] as int? ?? 0, direction: 'return'),
          row(
            Icons.move_to_inbox_outlined,
            'Returns on the way',
            p['returns_on_the_way'] as int? ?? 0,
            direction: 'return',
          ),
        ],
      ),
    );
  }

  // ---- next 7 days

  Widget _sessionsCard(List<Map<String, dynamic>> sessions, {bool fill = false}) {
    String timeRange(String start, int minutes) {
      final p = start.split(':');
      if (p.length != 2) return start;
      String fmt(int t) {
        final h = t ~/ 60;
        final h12 = h % 12 == 0 ? 12 : h % 12;
        return '$h12:${(t % 60).toString().padLeft(2, '0')} ${h >= 12 ? 'PM' : 'AM'}';
      }

      final s = int.parse(p[0]) * 60 + int.parse(p[1]);
      return '${fmt(s)} – ${fmt(s + minutes)}';
    }

    return _card(
      fill: fill,
      title: 'Next 7 days',
      subtitle: sessions.isEmpty ? null : '${sessions.length} session${sessions.length == 1 ? '' : 's'} booked',
      trailing: _link('Schedule', _openSchedule),
      child: sessions.isEmpty
          ? const Padding(
              padding: EdgeInsets.symmetric(vertical: 10),
              child: Text('Nothing booked this week.', style: TextStyle(fontSize: 12.5, color: SelmsColors.textMuted)),
            )
          : Column(
              children: [
                for (final s in sessions)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        Builder(
                          builder: (_) {
                            final d = DateTime.tryParse(s['date'] as String? ?? '');
                            return Container(
                              width: 42,
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              decoration: BoxDecoration(
                                color: SelmsColors.accentBg,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Column(
                                children: [
                                  Text(
                                    d == null ? '' : _months[d.month - 1].toUpperCase(),
                                    style: const TextStyle(
                                      fontSize: 9,
                                      fontWeight: FontWeight.w700,
                                      color: SelmsColors.textSecondary,
                                    ),
                                  ),
                                  Text(
                                    d == null ? '?' : '${d.day}',
                                    style: const TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700,
                                      color: SelmsColors.ink,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                s['title'] as String? ?? 'Session',
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                              ),
                              Text(
                                [
                                  timeRange(
                                    s['start_time'] as String? ?? '',
                                    (s['duration_minutes'] as num?)?.toInt() ?? 30,
                                  ),
                                  if ((s['employee_name'] as String? ?? '').isNotEmpty) s['employee_name'] as String,
                                ].join(' · '),
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 11, color: SelmsColors.textMuted),
                              ),
                            ],
                          ),
                        ),
                        Icon(
                          (s['mode'] as String? ?? 'in_person') == 'in_person'
                              ? Icons.meeting_room_outlined
                              : Icons.videocam_outlined,
                          size: 16,
                          color: SelmsColors.textMuted,
                        ),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }

  // ---- equipment: status bar + stock by type, in one card

  Widget _equipmentCard(Map<String, dynamic> eq) {
    final entries = <(String, int, Color)>[
      ('Available', eq['available'] as int? ?? 0, _cat[0]),
      ('With employees', eq['assigned'] as int? ?? 0, _cat[1]),
      ('Under repair', eq['under_repair'] as int? ?? 0, _cat[2]),
      ('Lost', eq['lost'] as int? ?? 0, _cat[3]),
    ].where((e) => e.$2 > 0).toList();
    final total = entries.fold<int>(0, (a, e) => a + e.$2);
    final types =
        ((eq['by_type'] as Map?) ?? const {}).entries
            .map(
              (e) => (
                '${e.key}',
                ((e.value as Map)['total'] as num).toInt(),
                ((e.value as Map)['available'] as num).toInt(),
              ),
            )
            .toList()
          ..sort((a, b) => b.$2.compareTo(a.$2));
    final max = types.isEmpty ? 1 : types.first.$2;
    return _card(
      title: 'Equipment',
      trailing: _link('Products', _openProducts),
      child: total == 0
          ? const Text('No equipment yet.', style: TextStyle(fontSize: 12.5, color: SelmsColors.textMuted))
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 100% stacked bar, 2px gaps; the legend below gives the numbers
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: SizedBox(
                    height: 12,
                    child: Row(
                      children: [
                        for (final (i, e) in entries.indexed) ...[
                          if (i > 0) const SizedBox(width: 2),
                          Expanded(
                            flex: e.$2,
                            child: Tooltip(
                              message: '${e.$1}: ${e.$2} (${(e.$2 * 100 / total).round()}%)',
                              child: Container(color: e.$3),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 12,
                  runSpacing: 4,
                  children: [
                    for (final e in entries)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 9,
                            height: 9,
                            decoration: BoxDecoration(color: e.$3, borderRadius: BorderRadius.circular(3)),
                          ),
                          const SizedBox(width: 5),
                          Text(
                            '${e.$1} ${e.$2}',
                            style: const TextStyle(fontSize: 11.5, color: SelmsColors.textSecondary),
                          ),
                        ],
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                const Text('BY TYPE · FREE TO ASSIGN', style: _headStyle),
                const SizedBox(height: 4),
                for (final (name, n, free) in types)
                  Tooltip(
                    message: '$name: $n in total, $free available',
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 80,
                            child: Text(
                              name,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 11.5, color: SelmsColors.textSecondary),
                            ),
                          ),
                          Expanded(child: _bar(n / max, height: 8)),
                          SizedBox(
                            width: 54,
                            child: Text(
                              '$free free',
                              textAlign: TextAlign.right,
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                                color: free == 0 ? _critical : SelmsColors.textPrimary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
    );
  }

  // ---- warranties ending + messages

  Widget _warrantyCard(List<Map<String, dynamic>> items, int unread, {bool fill = false}) {
    return _card(
      fill: fill,
      footer: _messagesRow(unread),
      title: 'Warranty ending soon',
      subtitle: 'Within the next 90 days',
      child: Column(
        children: [
          if (items.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  Icon(Icons.verified_outlined, size: 18, color: _good),
                  SizedBox(width: 8),
                  Text(
                    'No warranty ends in the next 90 days.',
                    style: TextStyle(fontSize: 12.5, color: SelmsColors.textSecondary),
                  ),
                ],
              ),
            ),
          for (final w in items)
            InkWell(
              onTap: () => _openEquipment(w['equipment_id'] as String),
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      clipBehavior: Clip.antiAlias,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(7),
                        border: Border.all(color: SelmsColors.border),
                      ),
                      child: (w['photo_url'] as String? ?? '').isNotEmpty
                          ? Image.network(
                              '${widget.apiBaseUrl}${w['photo_url']}',
                              fit: BoxFit.cover,
                              errorBuilder: (_, _, _) =>
                                  const Icon(Icons.devices_other_outlined, size: 15, color: SelmsColors.textMuted),
                            )
                          : const Icon(Icons.devices_other_outlined, size: 15, color: SelmsColors.textMuted),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            w['name'] as String? ?? '',
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                          ),
                          Text(
                            [
                              if ((w['asset_tag'] as String? ?? '').isNotEmpty) w['asset_tag'] as String,
                              'Ends ${_dayText(w['warranty_expiry'] as String?)}',
                            ].join(' · '),
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 11, color: SelmsColors.textMuted),
                          ),
                        ],
                      ),
                    ),
                    if ((w['days_left'] as int? ?? 99) <= 30) _statusPill('due_soon'),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _messagesRow(int unread) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Divider(height: 14, color: SelmsColors.border),
        InkWell(
          onTap: _openMessages,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 7),
            child: Row(
              children: [
                const Icon(Icons.chat_bubble_outline, size: 17, color: SelmsColors.textSecondary),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Unread employee messages',
                    style: TextStyle(fontSize: 12, color: SelmsColors.textSecondary),
                  ),
                ),
                Text(
                  '$unread',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: SelmsColors.textPrimary),
                ),
                const Icon(Icons.chevron_right, size: 16, color: SelmsColors.textMuted),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
