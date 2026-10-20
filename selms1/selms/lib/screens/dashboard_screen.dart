// lib/screens/dashboard_screen.dart
//
// HR's home: the state of the whole employee lifecycle at a glance.
//  * KPI cards - headcount, onboarding, offboarding, what needs attention;
//  * Lifecycle progress - everyone currently onboarding or offboarding, with
//    their progress, the step they're on and an On track / At risk / Delayed
//    status (same rules as Lifecycle Insights, so the two always agree);
//  * Waiting on you - the flows whose current step is HR's;
//  * Next 7 days - upcoming sessions;
//  * Headcount by department, work arrangement, equipment and messages.
// Everything comes from GET /api/hr/dashboard in one call.
//
// Chart colours follow the data-viz rules: magnitude in one blue hue,
// identity (work arrangement) in the first three validated categorical
// slots, and status in the reserved status colours - always with an icon
// and a word, never colour alone.

import 'package:flutter/material.dart';
import '../services/api_client.dart';
import '../theme/selms_colors.dart';
import '../widgets/app_shell.dart';
import '../widgets/employee_avatar.dart';
import 'employee_view_screen.dart';
import 'hr_messages_screen.dart';
import 'it_products_screen.dart';
import 'lifecycle_insights_screen.dart';
import 'offboarding_screen.dart';
import 'onboarding_screen.dart';
import 'smart_schedule_screen.dart';

// Magnitude (bars, progress) - one hue.
const _blue = Color(0xFF2A78D6);
const _track = Color(0xFFEEF1F5);
// Identity - validated categorical slots 1-3 (light surface).
const _cat = [Color(0xFF2A78D6), Color(0xFFEB6834), Color(0xFF1BAF7A)];
const _catOther = Color(0xFFB4B2A9);
// Status - reserved, never used for anything else.
const _good = Color(0xFF0CA30C);
const _warning = Color(0xFFFAB219);
const _critical = Color(0xFFD03B3B);

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key, required this.apiBaseUrl, required this.hrToken});

  final String apiBaseUrl;
  final String hrToken;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  late final ApiClient _api = ApiClient(baseUrl: widget.apiBaseUrl, hrToken: widget.hrToken);
  late Future<Map<String, dynamic>> _future = _api.getHrDashboard();
  String _filter = 'all'; // all | onboarding | offboarding

  Future<void> _refresh() async {
    setState(() { _future = _api.getHrDashboard(); });
    await _future;
  }

  void _go(Widget screen) => Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => screen));
  void _openOnboarding() => _go(OnboardingScreen(apiBaseUrl: widget.apiBaseUrl, hrToken: widget.hrToken));
  void _openOffboarding() => _go(OffboardingScreen(apiBaseUrl: widget.apiBaseUrl, hrToken: widget.hrToken));
  void _openInsights() => _go(LifecycleInsightsScreen(apiBaseUrl: widget.apiBaseUrl, hrToken: widget.hrToken));
  void _openSchedule() => _go(SmartScheduleScreen(apiBaseUrl: widget.apiBaseUrl, hrToken: widget.hrToken));
  void _openMessages() => _go(HrMessagesScreen(apiBaseUrl: widget.apiBaseUrl, hrToken: widget.hrToken));
  void _openProducts() =>
      _go(ItProductsScreen(apiBaseUrl: widget.apiBaseUrl, itToken: widget.hrToken, viewOnly: true));
  void _openEmployee(String id) => Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => EmployeeViewScreen(apiBaseUrl: widget.apiBaseUrl, hrToken: widget.hrToken, employeeId: id)));

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

  @override
  Widget build(BuildContext context) {
    return AppShell(
      apiBaseUrl: widget.apiBaseUrl,
      hrToken: widget.hrToken,
      activeRoute: SelmsRoute.dashboard,
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
                      Text(_greeting(),
                          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: SelmsColors.textPrimary)),
                      Text(_todayLabel(),
                          style: const TextStyle(fontSize: 12.5, color: SelmsColors.textSecondary)),
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
                          Text('Could not load the dashboard.\n${snap.error}',
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: SelmsColors.rose, fontSize: 13)),
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
    final head = (d['headcount'] as Map).cast<String, dynamic>();
    final on = (d['onboarding'] as Map).cast<String, dynamic>();
    final off = (d['offboarding'] as Map).cast<String, dynamic>();
    final actions = ((d['actions'] as List?) ?? const []).cast<Map<String, dynamic>>();
    final attention = (on['at_risk'] as int) + (on['delayed'] as int) + (off['at_risk'] as int) + (off['delayed'] as int);

    return ListView(
      padding: const EdgeInsets.only(bottom: 28),
      children: [
        // ---- KPI row
        LayoutBuilder(builder: (context, c) {
          final cards = [
            _kpi(
              icon: Icons.groups_outlined,
              label: 'Employees',
              value: '${head['total']}',
              sub: (head['new_this_month'] as int) > 0
                  ? '+${head['new_this_month']} joined this month'
                  : 'No new joiners this month',
            ),
            _kpi(
              icon: Icons.route_outlined,
              label: 'Onboarding',
              value: '${on['total']}',
              sub: _statusLine(on),
              onTap: _openOnboarding,
            ),
            _kpi(
              icon: Icons.logout,
              label: 'Offboarding',
              value: '${off['total']}',
              sub: _statusLine(off),
              onTap: _openOffboarding,
            ),
            _kpi(
              icon: attention > 0 ? Icons.error_outline : Icons.check_circle_outline,
              iconColor: attention > 0 ? _critical : _good,
              label: 'Needs attention',
              value: '$attention',
              sub: actions.isEmpty ? 'Nothing waiting on HR' : '${actions.length} waiting on you',
              onTap: _openInsights,
            ),
          ];
          final perRow = c.maxWidth > 900 ? 4 : 2;
          final w = (c.maxWidth - (perRow - 1) * 14) / perRow;
          return Wrap(
            spacing: 14,
            runSpacing: 14,
            children: [for (final k in cards) SizedBox(width: w, child: k)],
          );
        }),
        const SizedBox(height: 16),
        // ---- progress tracker + side column
        LayoutBuilder(builder: (context, c) {
          final progress = _progressCard(d);
          final side = Column(children: [
            _actionsCard(actions),
            const SizedBox(height: 14),
            _sessionsCard(((d['upcoming_sessions'] as List?) ?? const []).cast<Map<String, dynamic>>()),
          ]);
          if (c.maxWidth < 900) return Column(children: [progress, const SizedBox(height: 14), side]);
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 3, child: progress),
              const SizedBox(width: 14),
              Expanded(flex: 2, child: side),
            ],
          );
        }),
        const SizedBox(height: 16),
        // ---- workforce
        LayoutBuilder(builder: (context, c) {
          final dept = _departmentCard((head['by_department'] as Map).cast<String, dynamic>());
          final work = _workCard((head['by_work_location'] as Map).cast<String, dynamic>());
          final ops = _opsCard(
            (d['equipment'] as Map).cast<String, dynamic>(),
            ((d['equipment_waiting'] as List?) ?? const []).cast<Map<String, dynamic>>(),
            d['unread_messages'] as int? ?? 0,
          );
          if (c.maxWidth < 900) {
            return Column(children: [dept, const SizedBox(height: 14), work, const SizedBox(height: 14), ops]);
          }
          return IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(flex: 3, child: dept),
                const SizedBox(width: 14),
                Expanded(flex: 2, child: work),
                const SizedBox(width: 14),
                Expanded(flex: 2, child: ops),
              ],
            ),
          );
        }),
      ],
    );
  }

  String _statusLine(Map<String, dynamic> s) {
    if ((s['total'] as int) == 0) return 'No one in progress';
    final parts = <String>[
      if ((s['on_track'] as int) > 0) '${s['on_track']} on track',
      if ((s['at_risk'] as int) > 0) '${s['at_risk']} at risk',
      if ((s['delayed'] as int) > 0) '${s['delayed']} delayed',
    ];
    return parts.isEmpty ? 'All completed' : parts.join(' · ');
  }

  // ---------------------------------------------------------------- pieces

  Widget _card({required String title, String? subtitle, Widget? trailing, required Widget child,
      EdgeInsets padding = const EdgeInsets.fromLTRB(18, 16, 18, 16)}) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: SelmsColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: SelmsColors.textPrimary)),
                    if (subtitle != null)
                      Text(subtitle, style: const TextStyle(fontSize: 11.5, color: SelmsColors.textMuted)),
                  ],
                ),
              ),
              ?trailing,
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  Widget _link(String label, VoidCallback onTap) => TextButton(
        onPressed: onTap,
        style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 6), minimumSize: const Size(0, 30)),
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
          padding: const EdgeInsets.all(18),
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
                    Text(value,
                        style: const TextStyle(
                            fontSize: 26, height: 1.15, fontWeight: FontWeight.w700, color: SelmsColors.textPrimary)),
                    Text(sub,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11.5, color: SelmsColors.textMuted)),
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

  /// Status always carries an icon and a word - never colour alone.
  Widget _statusPill(String status) {
    final (color, icon, label) = switch (status) {
      'delayed' => (_critical, Icons.error, 'Delayed'),
      'at_risk' => (_warning, Icons.warning_rounded, 'At risk'),
      'completed' => (_good, Icons.check_circle, 'Completed'),
      _ => (_good, Icons.check_circle, 'On track'),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 4),
          Flexible(
            child: Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: SelmsColors.textPrimary)),
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
      child: Text(on ? 'Onboarding' : 'Offboarding',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
              color: on ? SelmsColors.statusOnboardingText : SelmsColors.statusOffboardingText)),
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

  // ---- lifecycle progress (the tracker)

  Widget _progressCard(Map<String, dynamic> d) {
    final all = ((d['in_progress'] as List?) ?? const []).cast<Map<String, dynamic>>();
    final rows = _filter == 'all' ? all : all.where((r) => r['process'] == _filter).toList();
    Widget chip(String key, String label, int count) {
      final active = _filter == key;
      return Padding(
        padding: const EdgeInsets.only(left: 6),
        child: ChoiceChip(
          label: Text('$label · $count', style: TextStyle(fontSize: 11.5, color: active ? Colors.white : SelmsColors.textSecondary)),
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
      title: 'Lifecycle progress',
      subtitle: 'Everyone onboarding or offboarding right now — most urgent first',
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          chip('all', 'All', all.length),
          chip('onboarding', 'Onboarding', all.where((r) => r['process'] == 'onboarding').length),
          chip('offboarding', 'Offboarding', all.where((r) => r['process'] == 'offboarding').length),
        ],
      ),
      child: Column(
        children: [
          if (rows.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 28),
              child: Column(
                children: [
                  Icon(Icons.inbox_outlined, size: 30, color: SelmsColors.textMuted),
                  SizedBox(height: 8),
                  Text('No one is in progress here.', style: TextStyle(fontSize: 12.5, color: SelmsColors.textMuted)),
                  Text('Start onboarding or offboarding from their tabs and progress shows up here.',
                      style: TextStyle(fontSize: 11.5, color: SelmsColors.textMuted)),
                ],
              ),
            )
          else ...[
            // column headings
            const Padding(
              padding: EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  Expanded(flex: 5, child: Text('EMPLOYEE', style: _headStyle)),
                  Expanded(flex: 4, child: Text('PROGRESS', style: _headStyle)),
                  Expanded(flex: 5, child: Text('CURRENT STEP', style: _headStyle)),
                  SizedBox(width: 112, child: Text('STATUS', style: _headStyle)),
                ],
              ),
            ),
            const Divider(height: 1, color: SelmsColors.border),
            for (final r in rows) _progressRow(r),
          ],
          const SizedBox(height: 6),
          Align(alignment: Alignment.centerRight, child: _link('Open Lifecycle Insights', _openInsights)),
        ],
      ),
    );
  }

  static const _headStyle =
      TextStyle(fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.6, color: SelmsColors.textMuted);

  Widget _progressRow(Map<String, dynamic> r) {
    final pct = (r['progress_percent'] as num?)?.toInt() ?? 0;
    final process = r['process'] as String? ?? 'onboarding';
    final when = process == 'offboarding' && r['days_to_last_day'] != null
        ? ((r['days_to_last_day'] as int) >= 0 ? '${r['days_to_last_day']} days to last day' : 'Last day passed')
        : (r['days_elapsed'] != null ? 'Day ${(r['days_elapsed'] as int) + 1}' : '');
    return InkWell(
      onTap: () => _openEmployee(r['employee_id'] as String),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFF1F3F5)))),
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
                        Text(r['full_name'] as String? ?? '',
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Flexible(child: _processPill(process)),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(r['department'] as String? ?? '',
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 11, color: SelmsColors.textMuted)),
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
                child: Tooltip(
                  message: '$pct% of steps done',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text('$pct%',
                              style: const TextStyle(
                                  fontSize: 12, fontWeight: FontWeight.w600, color: SelmsColors.textPrimary)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(when,
                                textAlign: TextAlign.right,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 10.5, color: SelmsColors.textMuted)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 5),
                      _bar(pct / 100),
                    ],
                  ),
                ),
              ),
            ),
            Expanded(
              flex: 5,
              child: Tooltip(
                message: r['status_reason'] as String? ?? '',
                child: Text(r['current_step'] as String? ?? '—',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, color: SelmsColors.textSecondary)),
              ),
            ),
            SizedBox(width: 112, child: Align(alignment: Alignment.centerLeft, child: _statusPill(r['status'] as String? ?? ''))),
          ],
        ),
      ),
    );
  }

  // ---- waiting on HR

  Widget _actionsCard(List<Map<String, dynamic>> actions) {
    return _card(
      title: 'Waiting on you',
      subtitle: actions.isEmpty ? null : 'Steps only HR can move forward',
      child: actions.isEmpty
          ? const Padding(
              padding: EdgeInsets.symmetric(vertical: 10),
              child: Row(
                children: [
                  Icon(Icons.check_circle_outline, size: 18, color: _good),
                  SizedBox(width: 8),
                  Text("You're all caught up.", style: TextStyle(fontSize: 12.5, color: SelmsColors.textSecondary)),
                ],
              ),
            )
          : Column(
              children: [
                for (final a in actions)
                  InkWell(
                    onTap: a['process'] == 'onboarding' ? _openOnboarding : _openOffboarding,
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 7),
                      child: Row(
                        children: [
                          EmployeeAvatar(
                            apiBaseUrl: widget.apiBaseUrl,
                            name: a['full_name'] as String? ?? '?',
                            photoUrl: a['profile_image_url'] as String?,
                            size: 30,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(a['action'] as String? ?? '',
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
                                Text('${a['full_name']} · ${a['process'] == 'onboarding' ? 'Onboarding' : 'Offboarding'}',
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 11, color: SelmsColors.textMuted)),
                              ],
                            ),
                          ),
                          if (a['status'] == 'delayed' || a['status'] == 'at_risk') _statusPill(a['status'] as String),
                          const Icon(Icons.chevron_right, size: 18, color: SelmsColors.textMuted),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
    );
  }

  // ---- next 7 days

  Widget _sessionsCard(List<Map<String, dynamic>> sessions) {
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
                        Builder(builder: (_) {
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
                                Text(d == null ? '' : _months[d.month - 1].toUpperCase(),
                                    style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: SelmsColors.textSecondary)),
                                Text(d == null ? '?' : '${d.day}',
                                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: SelmsColors.ink)),
                              ],
                            ),
                          );
                        }),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(s['title'] as String? ?? 'Session',
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
                              Text(
                                [
                                  timeRange(s['start_time'] as String? ?? '', (s['duration_minutes'] as num?)?.toInt() ?? 30),
                                  if ((s['attendee_count'] as int? ?? 0) > 1)
                                    '${s['attendee_count']} people'
                                  else if ((s['employee_name'] as String? ?? '').isNotEmpty)
                                    s['employee_name'] as String,
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

  // ---- workforce charts

  Widget _departmentCard(Map<String, dynamic> byDept) {
    final rows = byDept.entries.map((e) => (e.key, (e.value as num).toInt())).toList()
      ..sort((a, b) => b.$2.compareTo(a.$2));
    final max = rows.isEmpty ? 1 : rows.first.$2;
    return _card(
      title: 'Headcount by department',
      child: rows.isEmpty
          ? const Text('No employees yet.', style: TextStyle(fontSize: 12.5, color: SelmsColors.textMuted))
          : Column(
              children: [
                for (final (name, n) in rows)
                  Tooltip(
                    message: '$name: $n employee${n == 1 ? '' : 's'}',
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 5),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 96,
                            child: Text(name,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 12, color: SelmsColors.textSecondary)),
                          ),
                          Expanded(child: _bar(n / max, height: 14)),
                          SizedBox(
                            width: 32,
                            child: Text('$n',
                                textAlign: TextAlign.right,
                                style: const TextStyle(
                                    fontSize: 12, fontWeight: FontWeight.w600, color: SelmsColors.textPrimary)),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
    );
  }

  Widget _workCard(Map<String, dynamic> byWork) {
    const order = ['Onsite', 'Remote'];
    final entries = <(String, int, Color)>[
      for (final (i, k) in order.indexed)
        if ((byWork[k] as num? ?? 0) > 0) (k, (byWork[k] as num).toInt(), _cat[i]),
      for (final k in byWork.keys.where((k) => !order.contains(k)))
        if ((byWork[k] as num? ?? 0) > 0) (k, (byWork[k] as num).toInt(), _catOther),
    ];
    final total = entries.fold<int>(0, (a, e) => a + e.$2);
    return _card(
      title: 'Work arrangement',
      child: total == 0
          ? const Text('No employees yet.', style: TextStyle(fontSize: 12.5, color: SelmsColors.textMuted))
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 100% stacked bar, 2px surface gaps between segments
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: SizedBox(
                    height: 16,
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
                const SizedBox(height: 14),
                // legend doubles as the direct labels (name, count, share)
                for (final e in entries)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(color: e.$3, borderRadius: BorderRadius.circular(3)),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(e.$1, style: const TextStyle(fontSize: 12, color: SelmsColors.textSecondary)),
                        ),
                        Text('${e.$2}',
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: SelmsColors.textPrimary)),
                        SizedBox(
                          width: 44,
                          child: Text('${(e.$2 * 100 / total).round()}%',
                              textAlign: TextAlign.right,
                              style: const TextStyle(fontSize: 11.5, color: SelmsColors.textMuted)),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }

  Widget _opsCard(Map<String, dynamic> eq, List<Map<String, dynamic>> waiting, int unread) {
    Widget stat(IconData icon, String label, String value, {VoidCallback? onTap}) => InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 7),
            child: Row(
              children: [
                Icon(icon, size: 17, color: SelmsColors.textSecondary),
                const SizedBox(width: 10),
                Expanded(child: Text(label, style: const TextStyle(fontSize: 12, color: SelmsColors.textSecondary))),
                Text(value,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: SelmsColors.textPrimary)),
                if (onTap != null) const Icon(Icons.chevron_right, size: 16, color: SelmsColors.textMuted),
              ],
            ),
          ),
        );
    return _card(
      title: 'Equipment',
      trailing: _link('Products', _openProducts),
      child: Column(
        children: [
          stat(Icons.laptop_mac_outlined, 'Assigned to employees', '${eq['assigned'] ?? 0}', onTap: _openProducts),
          stat(Icons.inventory_2_outlined, 'Available in stock', '${eq['available'] ?? 0}', onTap: _openProducts),
          stat(Icons.build_outlined, 'Under repair', '${eq['under_repair'] ?? 0}', onTap: _openProducts),
          const Divider(height: 14, color: SelmsColors.border),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              waiting.isEmpty ? 'No new hire is waiting for equipment' : 'New hires waiting for equipment',
              style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: SelmsColors.textSecondary),
            ),
          ),
          for (final w in waiting.take(4))
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                children: [
                  EmployeeAvatar(
                    apiBaseUrl: widget.apiBaseUrl,
                    name: w['full_name'] as String? ?? '?',
                    photoUrl: w['profile_image_url'] as String?,
                    size: 24,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(w['full_name'] as String? ?? '',
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12, color: SelmsColors.textPrimary)),
                  ),
                  Text('${w['assigned']} of ${w['needed']} ready',
                      style: const TextStyle(fontSize: 11, color: SelmsColors.textMuted)),
                ],
              ),
            ),
          const Divider(height: 18, color: SelmsColors.border),
          stat(Icons.chat_bubble_outline, 'Unread employee messages', '$unread', onTap: _openMessages),
        ],
      ),
    );
  }
}
