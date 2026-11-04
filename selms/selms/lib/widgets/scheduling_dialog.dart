// lib/widgets/scheduling_dialog.dart
//
// Opened by tapping a "Schedule" step in either the onboarding or
// offboarding flow (matched by icon == 'ti-calendar'), or from the Smart
// Schedule calendar's own "+ Schedule Session" button. Suggests a
// conflict-free slot by checking existing bookings, shows what else is
// booked that day so the suggestion isn't a black box, and lets HR accept
// it or pick something else. HR names the session and chooses who attends -
// any number of employees and HR / IT staff, who all get the invite.
// Sessions run within the working hours HR sets on Smart Schedule.

import 'dart:async';
import 'package:flutter/material.dart';
import '../services/api_client.dart';
import '../theme/selms_colors.dart';
import 'employee_avatar.dart';
import 'flow_step_editors.dart';
import '../models/onboarding_flow_node.dart';

const _sessionMinutes = 30;

class SchedulingDialog extends StatefulWidget {
  const SchedulingDialog({
    super.key,
    required this.apiBaseUrl,
    required this.hrToken,
    required this.sessionType,
    required this.title,
    this.employeeId,
    this.employeeName,
    this.employeePhotoUrl,
    this.defaultLocation,
    this.planNode,
    this.process = 'onboarding',
    this.employee,
    this.planStarted = false,
    this.booked,
    this.notAfter,
    this.showLinkField = true,
  });

  final String apiBaseUrl;
  final String hrToken;
  final String sessionType; // 'orientation' | 'it_handoff' | 'exit_interview' | 'other'
  final String title;
  final String? employeeId;
  final String? employeeName;
  final String? employeePhotoUrl;
  final String? defaultLocation;

  /// Plan mode - the pencil on the orientation / exit interview step. Nothing
  /// is booked here: "Pick different time" opens the When window (Immediately
  /// or a date + time) and Save pops {when, meeting: {mode, title, location,
  /// meeting_url, attendees, attendee_ids}}. SELMS books it at Start.
  final OnboardingFlowNode? planNode;
  final String process;
  final Map<String, dynamic>? employee; // for the When window
  final bool planStarted; // already booked: Save moves the meeting
  final String? booked; // "Booked for 25 Oct 2026, 2:00 PM"
  /// Exit interview: nothing after the employee's last working day (YYYY-MM-DD).
  final String? notAfter;

  /// false from the onboarding / offboarding flows: online meetings always get
  /// the Google Meet link SELMS creates, so there is no link box to fill in.
  final bool showLinkField;

  @override
  State<SchedulingDialog> createState() => _SchedulingDialogState();
}

class _SchedulingDialogState extends State<SchedulingDialog> {
  late final ApiClient _api = ApiClient(baseUrl: widget.apiBaseUrl, hrToken: widget.hrToken);
  late final _titleCtrl = TextEditingController(text: widget.title);

  final _locationCtrl = TextEditingController();
  final _linkCtrl = TextEditingController();

  /// Who's attending: {id, name, role, profile_image_url}. The employee the
  /// dialog was opened for (onboarding / offboarding step) is fixed.
  late final List<Map<String, dynamic>> _people = [
    if (widget.employeeId != null)
      {
        'id': widget.employeeId,
        'name': widget.employeeName ?? widget.employeeId,
        'role': 'employee',
        'profile_image_url': widget.employeePhotoUrl,
        'locked': true,
      },
  ];
  String _mode = 'in_person'; // in_person | online
  bool _googleConnected = false;
  bool _hasDefaultLink = false;

  bool _loading = true;
  bool _confirming = false;
  String? _error;

  String? _date; // "YYYY-MM-DD"
  String? _startTime; // "HH:MM"
  List<Map<String, dynamic>> _dayBookings = [];

  bool get _planMode => widget.planNode != null;

  // The working day sessions can be booked in (minutes), set by HR.
  int _dayStart = 10 * 60;
  int _dayEnd = 17 * 60;
  // The working days, 0 = Monday ... 6 = Sunday, including those between.
  int _firstDay = 0;
  int _lastDay = 4;

  String get _daysText {
    const names = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
    return _firstDay == _lastDay ? names[_firstDay] : '${names[_firstDay]} to ${names[_lastDay]}';
  }

  String _clock(int minutes) {
    final h = (minutes ~/ 60) % 24;
    final h12 = h % 12 == 0 ? 12 : h % 12;
    return '$h12:${(minutes % 60).toString().padLeft(2, '0')} ${h >= 12 ? 'PM' : 'AM'}';
  }

  Future<void> _loadWorkingHours() async {
    try {
      final hours = await _api.getWorkingHours();
      if (!mounted) return;
      setState(() {
        _dayStart = hours['start_minutes'] as int;
        _dayEnd = hours['end_minutes'] as int;
        _firstDay = hours['first_day'] as int;
        _lastDay = hours['last_day'] as int;
      });
    } catch (_) {
      // Non-fatal: the backend still checks the hours when booking.
    }
  }

  @override
  void initState() {
    super.initState();
    _loadWorkingHours();
    _locationCtrl.text = widget.defaultLocation ?? '';
    _titleCtrl.addListener(() => setState(() {}));
    if (_planMode) {
      // Reopen with what was saved before (name, people, place, format, link).
      final plan = widget.planNode!.meeting ?? const {};
      // Not picked yet: Remote employees meet online, Onsite in person.
      _mode = plan['mode'] == 'online' || plan['mode'] == 'in_person'
          ? plan['mode'] as String
          : (widget.employee?['work_location_type'] == 'Remote' ? 'online' : 'in_person');
      if ((plan['title'] as String?)?.isNotEmpty == true) _titleCtrl.text = plan['title'] as String;
      if ((plan['location'] as String?)?.isNotEmpty == true) _locationCtrl.text = plan['location'] as String;
      _linkCtrl.text = widget.showLinkField ? (plan['meeting_url'] as String? ?? '') : '';
      for (final a in (plan['attendees'] as List? ?? const [])) {
        final person = Map<String, dynamic>.from(a as Map);
        if (!_people.any((p) => p['id'] == person['id'])) _people.add(person);
      }
      _openPlan();
    } else {
      _loadSuggestion();
    }
    _loadGoogleStatus();
  }

  /// Plan mode: the saved time if it is still free, otherwise the suggested slot.
  Future<void> _openPlan() async {
    final saved = widget.planNode!.when;
    final day = DateTime.tryParse(saved?['date'] as String? ?? '');
    final time = saved?['time'] as String?;
    if (saved?['mode'] == 'on_date' && day != null && time != null) {
      final now = DateTime.now();
      final at = DateTime(day.year, day.month, day.day, int.parse(time.split(':')[0]), int.parse(time.split(':')[1]));
      if (at.isAfter(now) && await _trySlot(day, time) && mounted) {
        setState(() => _loading = false);
        return;
      }
    }
    await _loadSuggestion();
  }

  /// Plan mode: "Pick different time" opens the When window (Immediately /
  /// a specific date + time). Immediately = the suggested slot from now.
  Future<void> _pickPlanTime() async {
    final node = widget.planNode!;
    final copy = OnboardingFlowNode(
      id: node.id,
      type: node.type,
      label: node.label,
      icon: node.icon,
      locked: node.locked,
      when: _date == null ? null : {'mode': 'on_date', 'date': _date, 'time': _startTime},
    );
    final result = await showWhenDialog(
      context,
      node: copy,
      process: widget.process,
      apiBaseUrl: widget.apiBaseUrl,
      employee: widget.employee,
      notAfter: widget.notAfter,
    );
    if (result == null || !mounted) return;
    if (result['mode'] == 'now') return _loadSuggestion();
    final day = DateTime.tryParse(result['date'] as String? ?? '');
    if (day != null) await _trySlot(day, result['time'] as String? ?? '10:00');
  }

  void _savePlan() {
    if (_titleCtrl.text.trim().isEmpty) {
      setState(() => _error = 'Give the session a name.');
      return;
    }
    if (_date == null || _startTime == null) return;
    final others = _people.where((p) => p['locked'] != true).toList();
    Navigator.of(context).pop(<String, dynamic>{
      'when': {'mode': 'on_date', 'date': _date, 'time': _startTime},
      'meeting': {
        'mode': _mode,
        'title': _titleCtrl.text.trim(),
        'location': _locationCtrl.text.trim(),
        'meeting_url': _mode == 'online' ? _linkCtrl.text.trim() : '',
        'attendees': others,
        'attendee_ids': [for (final p in others) p['id']],
      },
    });
  }

  /// This employee's own orientation / exit interview (after Start) is the one
  /// being moved, so it never counts as a clash.
  bool _isOwnBooking(Map<String, dynamic> b) =>
      _planMode && b['employee_id'] == widget.employeeId && b['session_type'] == widget.sessionType;

  /// Uses [day] at [hhmm] if it is a working day, within the working hours and clashes
  /// with nothing; otherwise says why and keeps the current slot. True if used.
  Future<bool> _trySlot(DateTime day, String hhmm) async {
    final parts = hhmm.split(':');
    final startMinutes = int.parse(parts[0]) * 60 + int.parse(parts[1]);
    await _loadWorkingHours();
    if (!mounted) return false;
    if (day.weekday - 1 < _firstDay || day.weekday - 1 > _lastDay) {
      setState(() => _error = 'Sessions run $_daysText - pick another day.');
      return false;
    }
    if (startMinutes < _dayStart || startMinutes + _sessionMinutes > _dayEnd) {
      setState(() => _error = 'Sessions run between ${_clock(_dayStart)} and ${_clock(_dayEnd)} — '
          'pick a start time from ${_clock(_dayStart)} to ${_clock(_dayEnd - _sessionMinutes)}.');
      return false;
    }
    final dateStr =
        '${day.year.toString().padLeft(4, '0')}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
    final lastDay = widget.notAfter;
    if (lastDay != null && dateStr.compareTo(lastDay) > 0) {
      setState(() => _error = "You can't choose this — it's after their last working day (${_formatDate(lastDay)}).");
      return false;
    }
    try {
      final dayBookings = (await _api.listBookings(start: day, end: day)).where((b) => !_isOwnBooking(b)).toList();
      if (!mounted) return false;
      // Never on top of another session: say which one and keep the previous slot.
      final pickedEnd = startMinutes + _sessionMinutes;
      for (final b in dayBookings) {
        final bParts = (b['start_time'] as String).split(':');
        final bStart = int.parse(bParts[0]) * 60 + int.parse(bParts[1]);
        final bEnd = bStart + (b['duration_minutes'] as int? ?? _sessionMinutes);
        if (startMinutes < bEnd && bStart < pickedEnd) {
          final who = (b['employee_name'] as String?)?.isNotEmpty == true ? ' - ${b['employee_name']}' : '';
          setState(() => _error = "You can't choose this time: it clashes with ${b['title']}$who "
              '(${_formatTimeRange(b['start_time'] as String, durationMinutes: bEnd - bStart)}). Pick another time.');
          return false;
        }
      }
      setState(() {
        _error = null;
        _date = dateStr;
        _startTime = hhmm;
        _dayBookings = dayBookings;
      });
      return true;
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
      return false;
    }
  }

  /// Only decides which hint to show under the link field - failing to load
  /// it just means the generic hint is shown.
  Future<void> _loadGoogleStatus() async {
    try {
      final status = await _api.googleStatus();
      if (!mounted) return;
      setState(() {
        _googleConnected = status['connected'] == true;
        _hasDefaultLink = status['default_meeting_url'] == true;
      });
    } catch (_) {}
  }

  Future<void> _loadSuggestion() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final suggestion = await _api.suggestBookingSlot(notAfter: widget.notAfter);
      final date = suggestion['date'] as String;
      final dayStart = DateTime.parse(date);
      final dayBookings =
          (await _api.listBookings(start: dayStart, end: dayStart)).where((b) => !_isOwnBooking(b)).toList();
      if (!mounted) return;
      setState(() {
        _error = null;
        _date = date;
        _startTime = suggestion['start_time'] as String;
        _dayBookings = dayBookings;
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

  Future<void> _pickDifferentTime() async {
    if (_date == null) return;
    final currentDate = DateTime.parse(_date!);
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: currentDate,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 90)),
    );
    if (pickedDate == null || !mounted) return;

    final currentTimeParts = (_startTime ?? '09:00').split(':');
    final pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: int.parse(currentTimeParts[0]), minute: int.parse(currentTimeParts[1])),
    );
    if (pickedTime == null) return;

    await _trySlot(pickedDate,
        '${pickedTime.hour.toString().padLeft(2, '0')}:${pickedTime.minute.toString().padLeft(2, '0')}');
  }

  Future<void> _addPeople() async {
    final picked = await showDialog<List<Map<String, dynamic>>>(
      context: context,
      builder: (_) => PeoplePickerDialog(
        api: _api,
        apiBaseUrl: widget.apiBaseUrl,
        selected: List.of(_people),
      ),
    );
    if (picked == null || !mounted) return;
    setState(() {
      final locked = _people.where((p) => p['locked'] == true).toList();
      _people
        ..clear()
        ..addAll(locked)
        ..addAll(picked.where((p) => !locked.any((l) => l['id'] == p['id'])));
    });
  }

  Future<void> _confirm() async {
    if (_date == null || _startTime == null) return;
    if (_titleCtrl.text.trim().isEmpty) {
      setState(() => _error = 'Give the session a name.');
      return;
    }
    setState(() {
      _confirming = true;
      _error = null;
    });
    try {
      final created = await _api.createBooking(
        employeeId: widget.employeeId,
        employeeName: widget.employeeName,
        sessionType: widget.sessionType,
        title: _titleCtrl.text.trim(),
        date: _date!,
        startTime: _startTime!,
        location: _locationCtrl.text.trim().isEmpty ? null : _locationCtrl.text.trim(),
        mode: _mode,
        meetingUrl: _mode == 'in_person' ? null : _linkCtrl.text.trim(),
        attendeeIds: [for (final p in _people) p['id'] as String],
      );
      if (!mounted) return;
      final warning = created['meeting_warning'] as String?;
      if (warning != null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(warning)));
      }
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _confirming = false;
        _error = e.toString();
      });
    }
  }

  Widget _modeChip(String label, String value, IconData icon) {
    final active = _mode == value;
    return Expanded(
      child: InkWell(
        onTap: _confirming ? null : () => setState(() => _mode = value),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(
            color: active ? SelmsColors.ink : Colors.white,
            border: Border.all(color: active ? SelmsColors.ink : SelmsColors.border),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 14, color: active ? Colors.white : SelmsColors.textSecondary),
              const SizedBox(width: 5),
              Flexible(
                child: Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w500,
                        color: active ? Colors.white : SelmsColors.textSecondary)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatDate(String iso) {
    final d = DateTime.parse(iso);
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return '${weekdays[d.weekday - 1]}, ${d.day} ${months[d.month - 1]}';
  }

  String _formatTimeRange(String start, {int durationMinutes = 30}) {
    final parts = start.split(':');
    final startMinutes = int.parse(parts[0]) * 60 + int.parse(parts[1]);
    final endMinutes = startMinutes + durationMinutes;
    String fmt(int total) {
      final h = total ~/ 60;
      final m = total % 60;
      final period = h >= 12 ? 'PM' : 'AM';
      final h12 = h % 12 == 0 ? 12 : h % 12;
      return '$h12:${m.toString().padLeft(2, '0')} $period';
    }
    return '${fmt(startMinutes)} – ${fmt(endMinutes)}';
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_titleCtrl.text.trim().isEmpty ? 'New session' : _titleCtrl.text.trim(),
                            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: SelmsColors.textPrimary)),
                        Text('Sessions run ${_clock(_dayStart)} – ${_clock(_dayEnd)}',
                            style: const TextStyle(fontSize: 11, color: SelmsColors.textMuted)),
                      ],
                    ),
                  ),
                  InkWell(
                    onTap: () => Navigator.of(context).pop(_planMode ? null : false),
                    child: const Icon(Icons.close, size: 18, color: SelmsColors.textSecondary),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              if (_loading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 30),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_error != null && _date == null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  child: Text(_error!, style: const TextStyle(color: SelmsColors.rose, fontSize: 12.5)),
                )
              else ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: SelmsColors.accentBg,
                    border: Border.all(color: SelmsColors.ink),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: const [
                          Icon(Icons.auto_awesome, size: 13, color: SelmsColors.ink),
                          SizedBox(width: 6),
                          Text('SUGGESTED SLOT',
                              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: SelmsColors.ink)),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text('${_formatDate(_date!)} · ${_formatTimeRange(_startTime!)}',
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: SelmsColors.textPrimary)),
                      const SizedBox(height: 2),
                      Text(
                        _dayBookings.isEmpty
                            ? 'No conflicts found this day.'
                            : '${_dayBookings.length} other session${_dayBookings.length == 1 ? '' : 's'} that day — no overlap.',
                        style: const TextStyle(fontSize: 10.5, color: SelmsColors.textSecondary),
                      ),
                      if (_planMode) ...[
                        const SizedBox(height: 6),
                        Text(
                          widget.planStarted
                              ? 'Save moves the booked meeting to this slot.'
                              : 'Nothing is booked yet - SELMS books this slot when you press Start.',
                          style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w500, color: SelmsColors.ink),
                        ),
                        if (widget.booked != null)
                          Text('Now: ${widget.booked}',
                              style: const TextStyle(fontSize: 10.5, color: SelmsColors.statusActiveText)),
                      ],
                    ],
                  ),
                ),
                if (_dayBookings.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  const Text('Also booked this day',
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.w500, color: SelmsColors.textMuted)),
                  const SizedBox(height: 6),
                  ..._dayBookings.map((b) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Text(
                          '${_formatTimeRange(b['start_time'] as String, durationMinutes: b['duration_minutes'] as int? ?? 30)} — ${b['title']}',
                          style: const TextStyle(fontSize: 11, color: SelmsColors.textSecondary),
                        ),
                      )),
                ],
                const SizedBox(height: 14),
                const Text('Session name',
                    style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w500, color: SelmsColors.textSecondary)),
                const SizedBox(height: 6),
                TextField(
                  controller: _titleCtrl,
                  decoration: const InputDecoration(hintText: 'e.g. Team introduction, Payroll briefing'),
                  style: const TextStyle(fontSize: 13),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: Text("Who's attending${_people.isEmpty ? '' : ' (${_people.length})'}",
                          style: const TextStyle(
                              fontSize: 10.5, fontWeight: FontWeight.w500, color: SelmsColors.textSecondary)),
                    ),
                    TextButton.icon(
                      onPressed: _confirming ? null : _addPeople,
                      style: TextButton.styleFrom(
                          padding: EdgeInsets.zero, minimumSize: const Size(0, 0), visualDensity: VisualDensity.compact),
                      icon: const Icon(Icons.person_add_alt_1_outlined, size: 15, color: SelmsColors.ink),
                      label: const Text('Add people', style: TextStyle(fontSize: 11.5, color: SelmsColors.ink)),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                if (_people.isEmpty)
                  const Text('No one added yet — add employees, HR or IT staff. They all get the invite.',
                      style: TextStyle(fontSize: 11, color: SelmsColors.textMuted))
                else
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: _people
                        .map((p) => Container(
                              padding: const EdgeInsets.fromLTRB(4, 4, 8, 4),
                              decoration: BoxDecoration(
                                color: SelmsColors.accentBg,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  EmployeeAvatar(
                                    apiBaseUrl: widget.apiBaseUrl,
                                    name: p['name'] as String? ?? '?',
                                    photoUrl: p['profile_image_url'] as String?,
                                    size: 22,
                                    background: Colors.white,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(p['name'] as String? ?? '',
                                      style: const TextStyle(fontSize: 11.5, color: SelmsColors.textPrimary)),
                                  if (p['role'] == 'hr' || p['role'] == 'it')
                                    Text(' · ${(p['role'] as String).toUpperCase()}',
                                        style: const TextStyle(fontSize: 10.5, color: SelmsColors.textMuted)),
                                  if (p['locked'] != true) ...[
                                    const SizedBox(width: 4),
                                    InkWell(
                                      onTap: _confirming ? null : () => setState(() => _people.remove(p)),
                                      child: const Icon(Icons.close, size: 14, color: SelmsColors.textSecondary),
                                    ),
                                  ],
                                ],
                              ),
                            ))
                        .toList(),
                  ),
                const SizedBox(height: 14),
                const Text('Location', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w500, color: SelmsColors.textSecondary)),
                const SizedBox(height: 6),
                TextField(
                  controller: _locationCtrl,
                  decoration: const InputDecoration(hintText: 'e.g. HR Room 1'),
                  style: const TextStyle(fontSize: 13),
                ),
                const SizedBox(height: 12),
                const Text('Format', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w500, color: SelmsColors.textSecondary)),
                const SizedBox(height: 6),
                Row(
                  children: [
                    _modeChip('In person', 'in_person', Icons.meeting_room_outlined),
                    const SizedBox(width: 6),
                    _modeChip('Online', 'online', Icons.videocam_outlined),
                  ],
                ),
                if (_mode != 'in_person' && widget.showLinkField) ...[
                  const SizedBox(height: 12),
                  const Text('Meeting link',
                      style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w500, color: SelmsColors.textSecondary)),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _linkCtrl,
                    decoration: const InputDecoration(hintText: 'https://meet.google.com/…  (optional)'),
                    style: const TextStyle(fontSize: 13),
                  ),
                  if (!_googleConnected) ...[
                    const SizedBox(height: 4),
                    Text(
                      _hasDefaultLink
                          ? 'Leave empty to use the default company meeting link.'
                          : 'Paste a Meet/Teams link, or connect Google on the Smart Schedule page to auto-create one.',
                      style: const TextStyle(fontSize: 10.5, color: SelmsColors.textMuted),
                    ),
                  ],
                ],
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Text(_error!, style: const TextStyle(color: SelmsColors.rose, fontSize: 12)),
                ],
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _confirming ? null : (_planMode ? _pickPlanTime : _pickDifferentTime),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: SelmsColors.border),
                          padding: const EdgeInsets.symmetric(vertical: 11),
                        ),
                        child: const Text('Pick different time',
                            style: TextStyle(fontSize: 12, color: SelmsColors.textSecondary)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _confirming ? null : (_planMode ? _savePlan : _confirm),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: SelmsColors.ink,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 11),
                        ),
                        child: _confirming
                            ? const SizedBox(
                                width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : Text(_planMode ? 'Save' : 'Confirm slot',
                                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}


/// Search employees, HR and IT staff and tick everyone who should attend.
/// Pops the full selection (or null if cancelled).
class PeoplePickerDialog extends StatefulWidget {
  const PeoplePickerDialog({
    super.key,
    required this.api,
    required this.apiBaseUrl,
    required this.selected,
    this.title = "Who's attending",
  });

  final String title;

  final ApiClient api;
  final String apiBaseUrl;
  final List<Map<String, dynamic>> selected;

  @override
  State<PeoplePickerDialog> createState() => PeoplePickerDialogState();
}

class PeoplePickerDialogState extends State<PeoplePickerDialog> {
  final _searchCtrl = TextEditingController();
  late final Map<String, Map<String, dynamic>> _chosen = {for (final p in widget.selected) p['id'] as String: p};
  List<Map<String, dynamic>> _results = [];
  bool _loading = true;
  String? _error;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _search('');
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _search(String q) async {
    setState(() => _loading = true);
    try {
      final list = await widget.api.lookupPeople(query: q);
      if (!mounted) return;
      setState(() {
        _results = list;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  String _roleLabel(Map<String, dynamic> p) => switch (p['role']) {
        'hr' => 'HR staff',
        'it' => 'IT staff',
        _ => [p['id'], p['department']].where((v) => v != null && '$v'.isNotEmpty).join(' · '),
      };

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420, maxHeight: 560),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("${widget.title}${_chosen.isEmpty ? '' : ' · ${_chosen.length} selected'}",
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: SelmsColors.textPrimary)),
              const SizedBox(height: 10),
              TextField(
                controller: _searchCtrl,
                autofocus: true,
                onChanged: (v) {
                  _debounce?.cancel();
                  _debounce = Timer(const Duration(milliseconds: 300), () => _search(v));
                },
                style: const TextStyle(fontSize: 13),
                decoration: const InputDecoration(
                  isDense: true,
                  prefixIcon: Icon(Icons.search, size: 18),
                  hintText: 'Search by name, ID or email',
                ),
              ),
              const SizedBox(height: 8),
              Flexible(
                child: _loading
                    ? const Padding(
                        padding: EdgeInsets.all(24),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    : _error != null
                        ? Text(_error!, style: const TextStyle(color: SelmsColors.rose, fontSize: 12))
                        : _results.isEmpty
                            ? const Padding(
                                padding: EdgeInsets.all(16),
                                child: Text('No one matches that search.',
                                    style: TextStyle(fontSize: 12.5, color: SelmsColors.textMuted)),
                              )
                            : ListView.builder(
                                shrinkWrap: true,
                                itemCount: _results.length,
                                itemBuilder: (_, i) {
                                  final p = _results[i];
                                  final id = p['id'] as String;
                                  final locked = _chosen[id]?['locked'] == true;
                                  return CheckboxListTile(
                                    value: _chosen.containsKey(id),
                                    onChanged: locked
                                        ? null
                                        : (v) => setState(() => v == true ? _chosen[id] = p : _chosen.remove(id)),
                                    dense: true,
                                    controlAffinity: ListTileControlAffinity.trailing,
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                                    secondary: EmployeeAvatar(
                                      apiBaseUrl: widget.apiBaseUrl,
                                      name: p['name'] as String? ?? '?',
                                      photoUrl: p['profile_image_url'] as String?,
                                      size: 32,
                                    ),
                                    title: Text(p['name'] as String? ?? '', style: const TextStyle(fontSize: 13)),
                                    subtitle: Text(_roleLabel(p), style: const TextStyle(fontSize: 11)),
                                  );
                                },
                              ),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(_chosen.values.toList()),
                    style: ElevatedButton.styleFrom(backgroundColor: SelmsColors.ink, foregroundColor: Colors.white),
                    child: Text(_chosen.isEmpty ? 'Done' : 'Add ${_chosen.length}'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
