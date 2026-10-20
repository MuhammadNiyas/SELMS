// lib/screens/smart_schedule_screen.dart
//
// A weekly calendar grid showing every booking made via the Assign/Retrieve
// scheduling popups (orientation, exit interview, IT handoff) plus any
// manually added sessions. Real week navigation, today highlighted, and
// blocks sized/positioned by their actual duration — not just fixed-height
// placeholders.

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/api_client.dart';
import '../theme/selms_colors.dart';
import '../widgets/app_shell.dart';
import '../widgets/it_app_shell.dart';
import '../widgets/scheduling_dialog.dart';
import 'lifecycle_insights_screen.dart';
import 'it_messages_screen.dart';
import 'it_shipments_screen.dart';

class SmartScheduleScreen extends StatefulWidget {
  const SmartScheduleScreen({super.key, required this.apiBaseUrl, required this.hrToken, this.forIt = false});

  final String apiBaseUrl;
  /// The signed-in user's token - HR's, or IT's when [forIt] is true.
  final String hrToken;
  /// Same calendar inside IT's shell: no Google connect chip (that stays
  /// with HR) and only the session types IT actually runs.
  final bool forIt;

  @override
  State<SmartScheduleScreen> createState() => _SmartScheduleScreenState();
}

class _SmartScheduleScreenState extends State<SmartScheduleScreen> {
  late final ApiClient _api = ApiClient(baseUrl: widget.apiBaseUrl, hrToken: widget.hrToken);

  // Sessions run 10:00 AM - 5:00 PM (same as the booking rules).
  static const int _dayStartHour = 10;
  static const int _dayEndHour = 17;
  // Pixels per hour - recomputed from the space available so the 10 AM - 5 PM
  // grid fills the card instead of leaving a long empty area under it.
  double _hourHeight = 56;
  static const double _minHourHeight = 48;

  late DateTime _weekMonday;
  List<Map<String, dynamic>> _bookings = [];
  // Flow steps timed for a date this week (emails, documents, surveys...) - HR only.
  List<Map<String, dynamic>> _sends = [];
  bool _loading = true;
  String? _error;

  Map<String, dynamic>? _google; // {configured, connected, default_meeting_url}
  Timer? _googlePoll;

  @override
  void dispose() {
    _googlePoll?.cancel();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _loadGoogleStatus();
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
      var sends = <Map<String, dynamic>>[];
      try {
        // Monday to Sunday: weekend items are shown in Friday's cell. HR sees what
        // the flows send; IT sees its own tasks (equipment to assign / retrieve, parcels).
        final sunday = _weekMonday.add(const Duration(days: 6));
        sends = widget.forIt
            ? await _api.listItTasks(start: _weekMonday, end: sunday)
            : await _api.listScheduledSends(start: _weekMonday, end: sunday);
      } catch (_) {
        // Non-fatal: the meetings still show without the row.
      }
      if (!mounted) return;
      setState(() {
        _bookings = bookings;
        _sends = sends;
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

  Future<void> _loadGoogleStatus() async {
    try {
      final status = await _api.googleStatus();
      if (!mounted) return;
      setState(() => _google = status);
    } catch (_) {
      // Non-fatal: the calendar works fine without the Google chip.
    }
  }

  /// Opens Google's consent page in a new tab, then checks every few
  /// seconds (for up to 2 minutes) until HR has finished approving it.
  Future<void> _connectGoogle() async {
    try {
      final url = await _api.googleAuthUrl();
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Finish signing in to Google in the new tab, then come back here.')),
      );
      _googlePoll?.cancel();
      var checks = 0;
      _googlePoll = Timer.periodic(const Duration(seconds: 3), (t) async {
        checks++;
        await _loadGoogleStatus();
        if (_google?['connected'] == true || checks >= 40) {
          t.cancel();
          if (mounted && _google?['connected'] == true) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Google connected.')));
          }
        }
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  Future<void> _disconnectGoogle() async {
    try {
      await _api.googleDisconnect();
      await _loadGoogleStatus();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  Widget _googleChip({bool compact = false}) {
    final g = _google;
    if (widget.forIt || g == null || g['configured'] != true) return const SizedBox.shrink();
    final connected = g['connected'] == true;
    return Padding(
      padding: const EdgeInsets.only(right: 12),
      child: InkWell(
        onTap: connected ? _disconnectGoogle : _connectGoogle,
        borderRadius: BorderRadius.circular(20),
        child: Tooltip(
          message: connected
              ? 'Google Meet links are created automatically. Click to disconnect.'
              : 'Connect Google to auto-create Meet links',
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: connected ? SelmsColors.statusActiveBg : Colors.white,
              border: Border.all(
                  color: connected ? SelmsColors.statusActiveText.withValues(alpha: 0.3) : SelmsColors.border),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(connected ? Icons.check_circle : Icons.link,
                    size: 14, color: connected ? SelmsColors.statusActiveText : SelmsColors.textSecondary),
                if (!compact) const SizedBox(width: 6),
                if (!compact)
                Text(connected ? 'Google Meet connected' : 'Connect Google Meet',
                    style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w500,
                        color: connected ? SelmsColors.statusActiveText : SelmsColors.textSecondary)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openBookingDetails(Map<String, dynamic> booking) async {
    final changed = await showDialog<bool>(
      context: context,
      builder: (_) => _BookingDetailsDialog(api: _api, booking: booking),
    );
    if (changed == true) _load();
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

  /// Straight to the session form: name, people, format.
  Future<void> _openNewSessionFlow() async {
    final booked = await showDialog<bool>(
      context: context,
      builder: (_) => SchedulingDialog(
        apiBaseUrl: widget.apiBaseUrl,
        hrToken: widget.hrToken,
        sessionType: 'other',
        title: '',
      ),
    );
    if (booked == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    final content = _buildContent();
    if (widget.forIt) {
      return ItAppShell(
        apiBaseUrl: widget.apiBaseUrl,
        itToken: widget.hrToken,
        activeRoute: ItRoute.schedule,
        child: content,
      );
    }
    return AppShell(
      apiBaseUrl: widget.apiBaseUrl,
      hrToken: widget.hrToken,
      activeRoute: SelmsRoute.smartSchedule,
      child: content,
    );
  }

  Widget _buildContent() {
    return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Title row
            const Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Smart Schedule',
                          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: SelmsColors.textPrimary)),
                      Text('Working hours 10:00 AM – 5:00 PM · Monday to Friday',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12.5, color: SelmsColors.textSecondary)),
                    ],
                  ),
                ),
                TopBarActions(),
              ],
            ),
            const SizedBox(height: 14),
            // Toolbar: week navigation on the left, actions on the right
            Row(
              children: [
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
                const SizedBox(width: 14),
                Expanded(
                  child: Text(_formatRange(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: SelmsColors.textPrimary)),
                ),
                const SizedBox(width: 12),
                LayoutBuilder(builder: (context, _) {
                  // Narrow window: the chip shrinks to its icon (the tooltip still says it all).
                  final compact = MediaQuery.sizeOf(context).width < 1200;
                  return _googleChip(compact: compact);
                }),
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
              ],
            ),
            const SizedBox(height: 14),
            Expanded(child: _buildBody()),
          ],
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
          if (_sends.isNotEmpty) ...[
            const Divider(height: 1, color: SelmsColors.border),
            _sendsStrip(days),
          ],
          const Divider(height: 1, color: SelmsColors.border),
          Expanded(
            child: LayoutBuilder(builder: (context, c) {
              const bottomPad = 14.0; // room for the "5 PM" label under the last line
              _hourHeight = ((c.maxHeight - bottomPad) / hours.length).clamp(_minHourHeight, 140).toDouble();
              final gridHeight = hours.length * _hourHeight;
              return SingleChildScrollView(
                child: SizedBox(
                  height: gridHeight + bottomPad,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // time labels on every hour line, 10 AM down to 5 PM
                      SizedBox(
                        width: 64,
                        height: gridHeight + bottomPad,
                        child: Stack(
                          children: [
                            for (var i = 0; i <= hours.length; i++)
                              Positioned(
                                top: i == 0 ? 2 : i * _hourHeight - 6,
                                right: 8,
                                child: Text(_formatHour(_dayStartHour + i),
                                    style: const TextStyle(fontSize: 10, color: SelmsColors.textMuted)),
                              ),
                          ],
                        ),
                      ),
                      ...List.generate(5, (i) => Expanded(child: _dayColumn(days[i]))),
                    ],
                  ),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }

  // ---- Sends: what the flows send each day, in a row above the meeting grid ----
  //
  // Each day is a plain list of two-line items (time and person, then the
  // step). The row has a fixed height; a busy day scrolls inside its own box.
  // Clicking an item opens that employee in Lifecycle Insights.

  static const double _sendItemHeight = 38;
  static const int _sendRowsVisible = 4;

  /// This day's sends; Friday also gets Saturday's and Sunday's (the grid has no weekend).
  List<Map<String, dynamic>> _sendsFor(DateTime day) {
    final keys = {_dateKey(day)};
    if (day.weekday == DateTime.friday) {
      keys.addAll([_dateKey(day.add(const Duration(days: 1))), _dateKey(day.add(const Duration(days: 2)))]);
    }
    return _sends.where((s) => keys.contains(s['date'])).toList();
  }

  String _time12(String hhmm) {
    final p = hhmm.split(':');
    final h = int.parse(p[0]);
    return '${h % 12 == 0 ? 12 : h % 12}:${p[1]} ${h >= 12 ? 'PM' : 'AM'}';
  }

  /// "10:05 AM · Ali" (weekend items in Friday's box get "Sat " / "Sun " in front).
  String _sendWhenWho(Map<String, dynamic> s) {
    final d = DateTime.parse(s['date'] as String);
    final day = d.weekday == DateTime.saturday ? 'Sat ' : (d.weekday == DateTime.sunday ? 'Sun ' : '');
    final time = s['time'] as String?;
    return '$day${time == null ? 'Start of day' : _time12(time)} · ${s['employee_name']}';
  }

  String _sendWhat(Map<String, dynamic> s) => '${s['kind'] == 'reminder' ? 'Reminder: ' : ''}${s['label']}';

  String _sendTooltip(Map<String, dynamic> s) {
    final process = s['process'] == 'onboarding' ? 'Onboarding' : 'Offboarding';
    if (s['hint'] != null) {
      return '$process - ${s['employee_name']} (${s['employee_id']})\n${s['label']}\n'
          '${s['done'] == true ? 'Done.' : s['hint']}\nClick to open.';
    }
    final what = s['done'] == true
        ? 'Done.'
        : s['kind'] == 'reminder'
            ? 'HR is reminded to do this.'
            : 'SELMS does this by itself.';
    final timing = s['timing'] == 'now' ? 'Set to Immediately' : 'Set for a specific date';
    return '$process - ${s['employee_name']} (${s['employee_id']})\n${_sendWhat(s)}\n$timing. $what\nClick to open in Lifecycle Insights.';
  }

  void _openInInsights(Map<String, dynamic> s) {
    if (widget.forIt) {
      // IT: parcels open Shipments, equipment tasks open Requests.
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => s['kind'] == 'shipment'
            ? ItShipmentsScreen(apiBaseUrl: widget.apiBaseUrl, itToken: widget.hrToken)
            : ItMessagesScreen(apiBaseUrl: widget.apiBaseUrl, itToken: widget.hrToken),
      ));
      return;
    }
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => LifecycleInsightsScreen(
        apiBaseUrl: widget.apiBaseUrl,
        hrToken: widget.hrToken,
        focusEmployeeId: s['employee_id'] as String?,
        focusProcess: s['process'] as String?,
      ),
    ));
  }

  /// Filled like a meeting block: green for onboarding, orange for offboarding.
  Widget _sendItem(Map<String, dynamic> s) {
    final done = s['done'] == true;
    final type = s['process'] == 'offboarding' ? 'exit_interview' : 'orientation';
    final fg = _sessionFg(type);
    return Tooltip(
      message: _sendTooltip(s),
      waitDuration: const Duration(milliseconds: 400),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: () => _openInInsights(s),
          child: Container(
            height: _sendItemHeight - 4,
            margin: const EdgeInsets.only(bottom: 4),
            padding: const EdgeInsets.symmetric(horizontal: 6),
            decoration: BoxDecoration(
              color: _sessionBg(type),
              border: Border.all(color: fg.withValues(alpha: 0.3)),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${done ? '\u2713 ' : ''}${_sendWhat(s)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: fg)),
                Text(_sendWhenWho(s),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 9, color: fg)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _sendsStrip(List<DateTime> days) {
    final perDay = [for (final d in days) _sendsFor(d)];
    final most = perDay.fold<int>(0, (m, l) => l.length > m ? l.length : m);
    final rows = most.clamp(1, _sendRowsVisible);
    return SizedBox(
      height: rows * _sendItemHeight + 10,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 64,
            child: Padding(
              padding: const EdgeInsets.only(top: 8, right: 8),
              child: Text(widget.forIt ? 'IT tasks' : 'Sends',
                  textAlign: TextAlign.right, style: const TextStyle(fontSize: 10, color: SelmsColors.textMuted)),
            ),
          ),
          for (var i = 0; i < days.length; i++)
            Expanded(
              child: Container(
                decoration: const BoxDecoration(border: Border(left: BorderSide(color: SelmsColors.border, width: 0.5))),
                padding: const EdgeInsets.fromLTRB(4, 5, 4, 0),
                child: perDay[i].isEmpty
                    ? const SizedBox.shrink()
                    : Scrollbar(
                        thumbVisibility: perDay[i].length > _sendRowsVisible,
                        child: ListView(
                          padding: EdgeInsets.only(right: perDay[i].length > _sendRowsVisible ? 8 : 0),
                          children: [for (final s in perDay[i]) _sendItem(s)],
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
                decoration: const BoxDecoration(border: Border(top: BorderSide(color: Color(0xFFE9ECEF)))),
                child: Column(
                  children: [
                    SizedBox(height: _hourHeight / 2 - 1),
                    Container(height: 1, color: const Color(0xFFF6F7F9)), // half-hour guide
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(height: 1, color: const Color(0xFFE9ECEF)), // 5 PM
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

    final blockHeight = height - 4 < 20 ? 20.0 : height - 4;
    final employeeName = b['employee_name'] as String?;
    final attendeeCount = (b['attendees'] as List?)?.length ?? 0;
    // More than one person: show how many; otherwise who it's with.
    final titleText = attendeeCount > 1
        ? '${b['title']} — $attendeeCount people'
        : '${b['title']}${employeeName != null && employeeName.isNotEmpty ? ' — $employeeName' : ''}';
    final location = b['location'] as String?;
    final detailText = '${b['start_time']}${location != null && location.isNotEmpty ? ' · $location' : ''}';
    // Two lines of text need ~36px; short sessions (e.g. a 20-30 min slot
    // at this hour height) get one combined line so nothing overflows.
    final compact = blockHeight < 36;

    // A small camera marks sessions that have an online part.
    final online = (b['mode'] as String? ?? 'in_person') != 'in_person' ||
        ((b['meeting_url'] as String?)?.isNotEmpty ?? false);
    final fg = _sessionFg(type);
    final cameraIcon = online
        ? Padding(padding: const EdgeInsets.only(right: 4), child: Icon(Icons.videocam, size: 11, color: fg))
        : const SizedBox.shrink();

    return Positioned(
      top: top + 2,
      left: 3,
      right: 3,
      height: blockHeight,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: () => _openBookingDetails(b),
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: 6, vertical: compact ? 2 : 4),
            decoration: BoxDecoration(
              color: _sessionBg(type),
              border: Border.all(color: fg.withValues(alpha: 0.3)),
              borderRadius: BorderRadius.circular(6),
            ),
            clipBehavior: Clip.hardEdge,
            child: compact
                ? Row(
                    children: [
                      cameraIcon,
                      Expanded(
                        child: Text(
                          '$titleText · $detailText',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: fg),
                        ),
                      ),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          cameraIcon,
                          Expanded(
                            child: Text(
                              titleText,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: fg),
                            ),
                          ),
                        ],
                      ),
                      Text(
                        detailText,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 9, color: fg),
                      ),
                    ],
                  ),
          ),
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

/// Opened by tapping a block on the calendar: everything about one session
/// plus Join / Copy link / edit link / cancel. Pops `true` if anything
/// changed so the calendar reloads.
class _BookingDetailsDialog extends StatefulWidget {
  const _BookingDetailsDialog({required this.api, required this.booking});

  final ApiClient api;
  final Map<String, dynamic> booking;

  @override
  State<_BookingDetailsDialog> createState() => _BookingDetailsDialogState();
}

class _BookingDetailsDialogState extends State<_BookingDetailsDialog> {
  late final TextEditingController _linkCtrl =
      TextEditingController(text: widget.booking['meeting_url'] as String? ?? '');
  bool _editing = false;
  bool _busy = false;
  String? _error;

  Map<String, dynamic> get _b => widget.booking;
  String get _bookingId => _b['_id'] as String;
  String get _mode => _b['mode'] as String? ?? 'in_person';
  String get _url => _linkCtrl.text.trim();

  @override
  void dispose() {
    _linkCtrl.dispose();
    super.dispose();
  }

  String _modeLabel() => switch (_mode) {
        'online' => 'Online',
        _ => 'In person',
      };

  String _timeRange() {
    final parts = (_b['start_time'] as String).split(':');
    final start = int.parse(parts[0]) * 60 + int.parse(parts[1]);
    final end = start + ((_b['duration_minutes'] as num?)?.toInt() ?? 30);
    String fmt(int t) {
      final h = t ~/ 60;
      final h12 = h % 12 == 0 ? 12 : h % 12;
      return '$h12:${(t % 60).toString().padLeft(2, '0')} ${h >= 12 ? 'PM' : 'AM'}';
    }

    return '${fmt(start)} – ${fmt(end)}';
  }

  String _dateLabel() {
    final d = DateTime.parse(_b['date'] as String);
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return '${weekdays[d.weekday - 1]}, ${d.day} ${months[d.month - 1]} ${d.year}';
  }

  Future<void> _saveLink() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.api.updateBooking(_bookingId, meetingUrl: _url);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _cancelSession() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel this session?', style: TextStyle(fontSize: 16)),
        content: const Text(
            'It will be removed from the calendar, and the Google invite (if any) will be cancelled for everyone.',
            style: TextStyle(fontSize: 13)),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Keep')),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: SelmsColors.rose, foregroundColor: Colors.white),
            child: const Text('Cancel session'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.api.deleteBooking(_bookingId);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.toString();
      });
    }
  }

  Widget _row(IconData icon, String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Icon(icon, size: 15, color: SelmsColors.textMuted),
            const SizedBox(width: 10),
            Expanded(child: Text(text, style: const TextStyle(fontSize: 12.5, color: SelmsColors.textSecondary))),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final employee = _b['employee_name'] as String? ?? '';
    final attendees = ((_b['attendees'] as List?) ?? const []).cast<Map<String, dynamic>>();
    final location = _b['location'] as String? ?? '';
    final hasLink = _url.isNotEmpty;

    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(_b['title'] as String? ?? 'Session',
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w600, color: SelmsColors.textPrimary)),
                  ),
                  InkWell(
                    onTap: () => Navigator.of(context).pop(false),
                    child: const Icon(Icons.close, size: 18, color: SelmsColors.textSecondary),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              if (attendees.isEmpty && employee.isNotEmpty) _row(Icons.person_outline, employee),
              if (attendees.isNotEmpty)
                _row(
                  attendees.length > 1 ? Icons.groups_outlined : Icons.person_outline,
                  attendees
                      .map((a) => a['role'] == 'employee' ? a['name'] : '${a['name']} (${(a['role'] as String).toUpperCase()})')
                      .join(', '),
                ),
              _row(Icons.event_outlined, _dateLabel()),
              _row(Icons.schedule, _timeRange()),
              _row(_mode == 'in_person' ? Icons.meeting_room_outlined : Icons.videocam_outlined, _modeLabel()),
              if (location.isNotEmpty) _row(Icons.place_outlined, location),
              if (_mode != 'in_person') ...[
                const SizedBox(height: 10),
                const Text('MEETING LINK',
                    style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.6,
                        color: SelmsColors.textMuted)),
                const SizedBox(height: 6),
                if (_editing)
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _linkCtrl,
                          autofocus: true,
                          style: const TextStyle(fontSize: 13),
                          decoration: const InputDecoration(isDense: true, hintText: 'https://meet.google.com/…'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: _busy ? null : _saveLink,
                        style: ElevatedButton.styleFrom(backgroundColor: SelmsColors.ink, foregroundColor: Colors.white),
                        child: const Text('Save', style: TextStyle(fontSize: 12)),
                      ),
                    ],
                  )
                else if (hasLink) ...[
                  SelectableText(_url, style: const TextStyle(fontSize: 12.5, color: Color(0xFF1D4ED8))),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      ElevatedButton.icon(
                        onPressed: () => launchUrl(Uri.parse(_url), mode: LaunchMode.externalApplication),
                        icon: const Icon(Icons.videocam, size: 15),
                        label: const Text('Join', style: TextStyle(fontSize: 12.5)),
                        style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF16A34A), foregroundColor: Colors.white, elevation: 0),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton.icon(
                        onPressed: () async {
                          await Clipboard.setData(ClipboardData(text: _url));
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context)
                              .showSnackBar(const SnackBar(content: Text('Link copied.')));
                        },
                        icon: const Icon(Icons.copy, size: 14),
                        label: const Text('Copy link', style: TextStyle(fontSize: 12.5)),
                      ),
                      const SizedBox(width: 4),
                      TextButton(
                        onPressed: () => setState(() => _editing = true),
                        child: const Text('Edit', style: TextStyle(fontSize: 12)),
                      ),
                    ],
                  ),
                ] else
                  Row(
                    children: [
                      const Expanded(
                        child: Text('No link yet.', style: TextStyle(fontSize: 12.5, color: SelmsColors.textMuted)),
                      ),
                      OutlinedButton(
                        onPressed: () => setState(() => _editing = true),
                        child: const Text('Add link', style: TextStyle(fontSize: 12)),
                      ),
                    ],
                  ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!, style: const TextStyle(color: SelmsColors.rose, fontSize: 12)),
              ],
              const SizedBox(height: 16),
              const Divider(height: 1, color: SelmsColors.border),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: _busy ? null : _cancelSession,
                  icon: const Icon(Icons.delete_outline, size: 16, color: SelmsColors.rose),
                  label: const Text('Cancel session', style: TextStyle(fontSize: 12.5, color: SelmsColors.rose)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
