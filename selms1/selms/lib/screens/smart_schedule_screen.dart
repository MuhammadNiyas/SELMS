// lib/screens/smart_schedule_screen.dart
//
// A weekly calendar grid showing every booking made via the Assign/Retrieve
// scheduling popups (orientation, exit interview, IT handoff) plus any
// manually added sessions. Real week navigation, today highlighted, and
// blocks sized/positioned by their actual duration — not just fixed-height
// placeholders.

import 'package:flutter/material.dart';
import '../services/api_client.dart';
import '../theme/selms_colors.dart';
import '../widgets/app_shell.dart';
import '../widgets/scheduling_dialog.dart';

class SmartScheduleScreen extends StatefulWidget {
  const SmartScheduleScreen({super.key, required this.apiBaseUrl, required this.hrToken});

  final String apiBaseUrl;
  final String hrToken;

  @override
  State<SmartScheduleScreen> createState() => _SmartScheduleScreenState();
}

class _SmartScheduleScreenState extends State<SmartScheduleScreen> {
  late final ApiClient _api = ApiClient(baseUrl: widget.apiBaseUrl, hrToken: widget.hrToken);

  static const int _dayStartHour = 8;
  static const int _dayEndHour = 18;
  static const double _hourHeight = 56;

  late DateTime _weekMonday;
  List<Map<String, dynamic>> _bookings = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _weekMonday = now.subtract(Duration(days: now.weekday - 1));
    _weekMonday = DateTime(_weekMonday.year, _weekMonday.month, _weekMonday.day);
    _load();
  }

  DateTime get _weekFriday => _weekMonday.add(const Duration(days: 4));

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final bookings = await _api.listBookings(start: _weekMonday, end: _weekFriday);
      if (!mounted) return;
      setState(() {
        _bookings = bookings;
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

  void _shiftWeek(int days) {
    setState(() => _weekMonday = _weekMonday.add(Duration(days: days)));
    _load();
  }

  void _goToThisWeek() {
    final now = DateTime.now();
    var monday = now.subtract(Duration(days: now.weekday - 1));
    monday = DateTime(monday.year, monday.month, monday.day);
    setState(() => _weekMonday = monday);
    _load();
  }

  bool _isToday(DateTime d) {
    final now = DateTime.now();
    return d.year == now.year && d.month == now.month && d.day == now.day;
  }

  String _dateKey(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Color _sessionBg(String type) {
    switch (type) {
      case 'exit_interview':
        return const Color(0xFFFAECE7);
      case 'other':
        return const Color(0xFFF1EFE8);
      default:
        return const Color(0xFFE1F5EE);
    }
  }

  Color _sessionFg(String type) {
    switch (type) {
      case 'exit_interview':
        return const Color(0xFF993C1D);
      case 'other':
        return const Color(0xFF444441);
      default:
        return const Color(0xFF085041);
    }
  }

  Future<void> _openNewSessionFlow() async {
    final choice = await showDialog<Map<String, String>>(
      context: context,
      builder: (_) => const _NewSessionTypeDialog(),
    );
    if (choice == null || !mounted) return;

    final booked = await showDialog<bool>(
      context: context,
      builder: (_) => SchedulingDialog(
        apiBaseUrl: widget.apiBaseUrl,
        hrToken: widget.hrToken,
        sessionType: choice['session_type']!,
        title: choice['title']!,
      ),
    );
    if (booked == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    return AppShell(
      apiBaseUrl: widget.apiBaseUrl,
      hrToken: widget.hrToken,
      activeRoute: SelmsRoute.smartSchedule,
      child: Padding(
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
                      const Text('Smart Schedule',
                          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: SelmsColors.textPrimary)),
                      Text('Weekly calendar — ${_formatRange()}',
                          style: const TextStyle(fontSize: 12.5, color: SelmsColors.textSecondary)),
                    ],
                  ),
                ),
                InkWell(
                  onTap: () => _shiftWeek(-7),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8)),
                    child: const Icon(Icons.chevron_left, size: 18, color: SelmsColors.textSecondary),
                  ),
                ),
                const SizedBox(width: 8),
                InkWell(
                  onTap: _goToThisWeek,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8)),
                    child: const Text('Today', style: TextStyle(fontSize: 12, color: SelmsColors.textSecondary)),
                  ),
                ),
                const SizedBox(width: 8),
                InkWell(
                  onTap: () => _shiftWeek(7),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8)),
                    child: const Icon(Icons.chevron_right, size: 18, color: SelmsColors.textSecondary),
                  ),
                ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  onPressed: _openNewSessionFlow,
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Schedule Session', style: TextStyle(fontSize: 12.5)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF16A34A),
                    foregroundColor: Colors.white,
                    elevation: 0,
                  ),
                ),
                const SizedBox(width: 12),
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

  String _formatRange() {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final start = _weekMonday;
    final end = _weekFriday;
    if (start.month == end.month) {
      return '${start.day}–${end.day} ${months[start.month - 1]} ${start.year}';
    }
    return '${start.day} ${months[start.month - 1]} – ${end.day} ${months[end.month - 1]} ${end.year}';
  }

  Widget _buildBody() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(child: Text(_error!, style: const TextStyle(color: SelmsColors.rose, fontSize: 13)));
    }

    final days = List.generate(5, (i) => _weekMonday.add(Duration(days: i)));
    const dayLabels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri'];
    final hours = List.generate(_dayEndHour - _dayStartHour, (i) => _dayStartHour + i);

    return Container(
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
      clipBehavior: Clip.hardEdge,
      child: Column(
        children: [
          Row(
            children: [
              const SizedBox(width: 64),
              ...List.generate(5, (i) {
                final isToday = _isToday(days[i]);
                return Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: isToday ? SelmsColors.accentBg : const Color(0xFFF9FAFB),
                      border: const Border(left: BorderSide(color: SelmsColors.border, width: 0.5)),
                    ),
                    child: Column(
                      children: [
                        Text(dayLabels[i],
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: isToday ? SelmsColors.ink : SelmsColors.textPrimary)),
                        Text('${days[i].day} ${_monthAbbrev(days[i].month)}',
                            style: const TextStyle(fontSize: 10, color: SelmsColors.textMuted)),
                      ],
                    ),
                  ),
                );
              }),
            ],
          ),
          const Divider(height: 1, color: SelmsColors.border),
          Expanded(
            child: SingleChildScrollView(
              child: SizedBox(
                height: hours.length * _hourHeight,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 64,
                      child: Column(
                        children: hours
                            .map((h) => SizedBox(
                                  height: _hourHeight,
                                  child: Padding(
                                    padding: const EdgeInsets.only(top: 4, right: 8),
                                    child: Align(
                                      alignment: Alignment.topRight,
                                      child: Text(_formatHour(h),
                                          style: const TextStyle(fontSize: 10, color: SelmsColors.textMuted)),
                                    ),
                                  ),
                                ))
                            .toList(),
                      ),
                    ),
                    ...List.generate(5, (i) => Expanded(child: _dayColumn(days[i]))),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _dayColumn(DateTime day) {
    final isToday = _isToday(day);
    final dayBookings = _bookings.where((b) => b['date'] == _dateKey(day)).toList();
    final hourCount = _dayEndHour - _dayStartHour;

    return Container(
      height: hourCount * _hourHeight,
      decoration: BoxDecoration(
        color: isToday ? const Color(0xFFF7FAFD) : Colors.white,
        border: const Border(left: BorderSide(color: SelmsColors.border, width: 0.5)),
      ),
      child: Stack(
        children: [
          Column(
            children: List.generate(
              hourCount,
              (_) => Container(
                height: _hourHeight,
                decoration: const BoxDecoration(border: Border(top: BorderSide(color: Color(0xFFF3F4F6)))),
              ),
            ),
          ),
          ...dayBookings.map((b) => _bookingBlock(b)),
        ],
      ),
    );
  }

  Widget _bookingBlock(Map<String, dynamic> b) {
    final startParts = (b['start_time'] as String).split(':');
    final startMinutes = int.parse(startParts[0]) * 60 + int.parse(startParts[1]);
    final dayStartMinutes = _dayStartHour * 60;
    final top = ((startMinutes - dayStartMinutes) / 60) * _hourHeight;
    final durationMinutes = b['duration_minutes'] as int? ?? 30;
    final height = (durationMinutes / 60) * _hourHeight;
    final type = b['session_type'] as String? ?? 'other';

    if (top < 0 || startMinutes >= _dayEndHour * 60) return const SizedBox.shrink();

    return Positioned(
      top: top + 2,
      left: 3,
      right: 3,
      height: height - 4 < 20 ? 20 : height - 4,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        decoration: BoxDecoration(
          color: _sessionBg(type),
          border: Border.all(color: _sessionFg(type).withValues(alpha: 0.3)),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${b['title']}${b['employee_name'] != null && (b['employee_name'] as String).isNotEmpty ? ' — ${b['employee_name']}' : ''}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: _sessionFg(type)),
            ),
            Text(
              '${b['start_time']}${b['location'] != null && (b['location'] as String).isNotEmpty ? ' · ${b['location']}' : ''}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 9, color: _sessionFg(type)),
            ),
          ],
        ),
      ),
    );
  }

  String _formatHour(int h) {
    final period = h >= 12 ? 'PM' : 'AM';
    final h12 = h % 12 == 0 ? 12 : h % 12;
    return '$h12:00 $period';
  }

  String _monthAbbrev(int m) =>
      const ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'][m - 1];
}

/// Small first step for the "+ Schedule Session" button — pick a session
/// type (and its default title) before the SchedulingDialog opens.
class _NewSessionTypeDialog extends StatelessWidget {
  const _NewSessionTypeDialog();

  static const _types = [
    {'session_type': 'orientation', 'title': 'Orientation'},
    {'session_type': 'it_handoff', 'title': 'IT Handoff'},
    {'session_type': 'exit_interview', 'title': 'Exit Interview'},
    {'session_type': 'other', 'title': 'Other Session'},
  ];

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('New session',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: SelmsColors.textPrimary)),
            const SizedBox(height: 4),
            const Text('What kind of session is this?',
                style: TextStyle(fontSize: 11.5, color: SelmsColors.textMuted)),
            const SizedBox(height: 12),
            ..._types.map((t) => ListTile(
                  leading: const Icon(Icons.event_outlined, size: 18, color: SelmsColors.textSecondary),
                  title: Text(t['title']!, style: const TextStyle(fontSize: 13)),
                  onTap: () => Navigator.of(context).pop(t),
                )),
          ],
        ),
      ),
    );
  }
}
