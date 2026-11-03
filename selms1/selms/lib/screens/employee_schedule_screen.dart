// lib/screens/employee_schedule_screen.dart
//
// The employee's Schedule tab - their own side of the Smart Schedule HR and
// IT use: the same weeks, the same sessions (orientation, IT handoff, exit
// interview...), laid out for a phone: a week strip to pick a day, that
// day's sessions, and what's coming up next. Read-only - HR and IT book
// sessions; tapping one shows its details with the Join link.

import 'package:flutter/material.dart';
import '../services/api_client.dart';
import '../theme/selms_colors.dart';
import '../widgets/employee_ui.dart';

class EmployeeScheduleScreen extends StatefulWidget {
  const EmployeeScheduleScreen({super.key, required this.api});

  final ApiClient api;

  @override
  State<EmployeeScheduleScreen> createState() => _EmployeeScheduleScreenState();
}

class _EmployeeScheduleScreenState extends State<EmployeeScheduleScreen> {
  late Future<List<Map<String, dynamic>>> _future = widget.api.getMyBookings();
  late DateTime _selected = _dateOnly(DateTime.now());

  static const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  static const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);
  static String _key(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  DateTime get _weekStart => _selected.subtract(Duration(days: _selected.weekday - 1));

  Future<void> _refresh() async {
    setState(() { _future = widget.api.getMyBookings(); });
    await _future;
  }

  void _shiftWeek(int weeks) => setState(() => _selected = _selected.add(Duration(days: 7 * weeks)));

  String _weekLabel() {
    final s = _weekStart;
    final e = s.add(const Duration(days: 6));
    if (s.month == e.month) return '${s.day} – ${e.day} ${_months[s.month - 1]} ${s.year}';
    return '${s.day} ${_months[s.month - 1]} – ${e.day} ${_months[e.month - 1]} ${e.year}';
  }

  (Color, Color, IconData) _typeStyle(String? type) => switch (type) {
        'orientation' => (const Color(0xFF085041), const Color(0xFFE1F5EE), Icons.waving_hand_outlined),
        'it_handoff' => (const Color(0xFF1D4ED8), const Color(0xFFE0ECFF), Icons.laptop_mac_outlined),
        'exit_interview' => (const Color(0xFF993C1D), const Color(0xFFFAECE7), Icons.logout),
        _ => (const Color(0xFF444441), const Color(0xFFF1EFE8), Icons.event_outlined),
      };

  String _about(String? type, int minutes) => switch (type) {
        'orientation' =>
          'A $minutes-minute welcome session with HR: an introduction to the company and your team, the tools '
              'you will use, key policies, and what your first week looks like.',
        'it_handoff' => 'IT hands over your equipment and helps you sign in to your accounts for the first time.',
        'exit_interview' =>
          'A private conversation with HR about your time here — what went well and what could be better.',
        _ => 'A session HR or IT booked with you.',
      };

  /// Everyone else attending (the backend leaves the employee out).
  List<String> _with(Map<String, dynamic> b) => ((b['with'] as List?) ?? const []).whereType<String>().toList();

  String _withShort(Map<String, dynamic> b) {
    final names = _with(b);
    if (names.isEmpty) return '';
    final first = names.first.split(RegExp(r'\s+')).first;
    return names.length == 1 ? 'with $first' : 'with $first +${names.length - 1}';
  }

  void _openSession(Map<String, dynamic> b) {
    final url = b['meeting_url'] as String? ?? '';
    final location = b['location'] as String? ?? '';
    final minutes = (b['duration_minutes'] as num?)?.toInt() ?? 30;
    final (_, _, icon) = _typeStyle(b['session_type'] as String?);
    showEmpSheet(
      context,
      icon: icon,
      title: b['title'] as String? ?? 'Session',
      subtitle: '${empDate(b['date'] as String?, weekday: true)} · ${empTimeRange(b['start_time'] as String? ?? '', minutes)}',
      children: [
        EmpMeetingTile(meeting: b, compact: true),
        const SizedBox(height: 14),
        if (url.isNotEmpty) ...[
          EmpSheetButton(label: 'Join the session', icon: Icons.videocam_outlined, onPressed: () => empOpenUrl(url)),
          EmpCopyRow(label: 'Meeting link', value: url),
        ],
        if (location.isNotEmpty) EmpCopyRow(label: 'Location', value: location),
        if (_with(b).isNotEmpty) EmpSheetText(_with(b).join(', '), heading: 'With'),
        EmpSheetText(_about(b['session_type'] as String?, minutes), heading: 'About this session'),
      ],
    );
  }

  Widget _sessionCard(Map<String, dynamic> b, {bool showDate = false}) {
    final (fg, bg, icon) = _typeStyle(b['session_type'] as String?);
    final minutes = (b['duration_minutes'] as num?)?.toInt() ?? 30;
    final mode = b['mode'] as String? ?? 'in_person';
    final modeLabel = mode == 'online' ? 'Online' : 'In person';
    final location = b['location'] as String? ?? '';
    final hasLink = (b['meeting_url'] as String? ?? '').isNotEmpty;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: EmpCard(
        onTap: () => _openSession(b),
        padding: EdgeInsets.zero,
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                width: 5,
                decoration: BoxDecoration(
                  color: fg,
                  borderRadius: const BorderRadius.horizontal(left: Radius.circular(14)),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 10, 12),
                  child: Row(
                    children: [
                      EmpIconBadge(icon, size: 36, bg: bg, fg: fg),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(b['title'] as String? ?? 'Session',
                                style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
                            const SizedBox(height: 2),
                            Text(
                              '${showDate ? '${empDate(b['date'] as String?, weekday: true)} · ' : ''}'
                              '${empTimeRange(b['start_time'] as String? ?? '', minutes)}',
                              style: const TextStyle(fontSize: 12, color: SelmsColors.textSecondary),
                            ),
                            const SizedBox(height: 2),
                            Text([modeLabel, if (location.isNotEmpty) location, if (_withShort(b).isNotEmpty) _withShort(b)].join(' · '),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 11.5, color: SelmsColors.textMuted)),
                          ],
                        ),
                      ),
                      if (hasLink) const Icon(Icons.videocam_outlined, size: 18, color: EmpColors.success),
                      const SizedBox(width: 2),
                      const Icon(Icons.chevron_right, size: 18, color: SelmsColors.textMuted),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _weekStrip(Map<String, int> countByDay) {
    final today = _dateOnly(DateTime.now());
    return EmpCard(
      padding: const EdgeInsets.fromLTRB(6, 6, 6, 10),
      child: Column(
        children: [
          Row(
            children: [
              IconButton(
                tooltip: 'Previous week',
                onPressed: () => _shiftWeek(-1),
                icon: const Icon(Icons.chevron_left, color: SelmsColors.textSecondary),
              ),
              Expanded(
                child: Text(_weekLabel(),
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
              ),
              IconButton(
                tooltip: 'Next week',
                onPressed: () => _shiftWeek(1),
                icon: const Icon(Icons.chevron_right, color: SelmsColors.textSecondary),
              ),
            ],
          ),
          Row(
            children: List.generate(7, (i) {
              final day = _weekStart.add(Duration(days: i));
              final isSelected = day == _selected;
              final isToday = day == today;
              final count = countByDay[_key(day)] ?? 0;
              return Expanded(
                child: InkWell(
                  onTap: () => setState(() => _selected = day),
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      color: isSelected ? SelmsColors.ink : Colors.transparent,
                      borderRadius: BorderRadius.circular(12),
                      border: isToday && !isSelected ? Border.all(color: SelmsColors.ink) : null,
                    ),
                    child: Column(
                      children: [
                        Text(_weekdays[i],
                            style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w600,
                                color: isSelected ? Colors.white70 : SelmsColors.textMuted)),
                        const SizedBox(height: 3),
                        Text('${day.day}',
                            style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: isSelected ? Colors.white : SelmsColors.textPrimary)),
                        const SizedBox(height: 4),
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: count == 0
                                ? Colors.transparent
                                : (isSelected ? Colors.white : SelmsColors.rose),
                            shape: BoxShape.circle,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
          ),
          if (_selected != today) ...[
            const SizedBox(height: 6),
            TextButton(
              onPressed: () => setState(() => _selected = today),
              style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
              child: const Text('Back to today', style: TextStyle(fontSize: 12, color: SelmsColors.ink)),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _refresh,
      child: FutureBuilder<List<Map<String, dynamic>>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) return const EmpLoading();
          if (snapshot.hasError) return EmpErrorState(message: '${snapshot.error}', onRetry: _refresh);

          final all = snapshot.data!;
          final countByDay = <String, int>{};
          for (final b in all) {
            final k = b['date'] as String? ?? '';
            countByDay[k] = (countByDay[k] ?? 0) + 1;
          }
          final dayKey = _key(_selected);
          final ofDay = all.where((b) => b['date'] == dayKey).toList();
          final todayKey = _key(DateTime.now());
          final upcoming = all.where((b) => (b['date'] as String? ?? '').compareTo(todayKey) >= 0 && b['date'] != dayKey).take(5).toList();

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
            children: [
              _weekStrip(countByDay),
              EmpSectionHeader(empDate(dayKey, weekday: true)),
              if (ofDay.isEmpty)
                const EmpCard(
                  child: Row(
                    children: [
                      Icon(Icons.event_available_outlined, size: 20, color: SelmsColors.textMuted),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text('No sessions on this day.',
                            style: TextStyle(fontSize: 12.5, color: SelmsColors.textMuted)),
                      ),
                    ],
                  ),
                )
              else
                ...ofDay.map(_sessionCard),
              if (upcoming.isNotEmpty) ...[
                const EmpSectionHeader('Coming up'),
                ...upcoming.map((b) => _sessionCard(b, showDate: true)),
              ] else if (all.isEmpty) ...[
                const SizedBox(height: 8),
                const EmpEmptyState(
                  icon: Icons.calendar_month_outlined,
                  title: 'Nothing scheduled yet',
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}
