// lib/widgets/scheduling_dialog.dart
//
// Opened by tapping a "Schedule" step in either the onboarding or
// offboarding flow (matched by icon == 'ti-calendar'), or from the Smart
// Schedule calendar's own "+ Schedule Session" button. Suggests a
// conflict-free slot by checking existing bookings, shows what else is
// booked that day so the suggestion isn't a black box, and lets HR accept
// it or pick something else.

import 'package:flutter/material.dart';
import '../services/api_client.dart';
import '../theme/selms_colors.dart';

class SchedulingDialog extends StatefulWidget {
  const SchedulingDialog({
    super.key,
    required this.apiBaseUrl,
    required this.hrToken,
    required this.sessionType,
    required this.title,
    this.employeeId,
    this.employeeName,
    this.defaultLocation,
  });

  final String apiBaseUrl;
  final String hrToken;
  final String sessionType; // 'orientation' | 'it_handoff' | 'exit_interview' | 'other'
  final String title;
  final String? employeeId;
  final String? employeeName;
  final String? defaultLocation;

  @override
  State<SchedulingDialog> createState() => _SchedulingDialogState();
}

class _SchedulingDialogState extends State<SchedulingDialog> {
  late final ApiClient _api = ApiClient(baseUrl: widget.apiBaseUrl, hrToken: widget.hrToken);
  final _locationCtrl = TextEditingController();

  bool _loading = true;
  bool _confirming = false;
  String? _error;

  String? _date; // "YYYY-MM-DD"
  String? _startTime; // "HH:MM"
  List<Map<String, dynamic>> _dayBookings = [];

  @override
  void initState() {
    super.initState();
    _locationCtrl.text = widget.defaultLocation ?? '';
    _loadSuggestion();
  }

  @override
  void dispose() {
    _locationCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadSuggestion() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final suggestion = await _api.suggestBookingSlot();
      final date = suggestion['date'] as String;
      final dayStart = DateTime.parse(date);
      final dayBookings = await _api.listBookings(start: dayStart, end: dayStart);
      if (!mounted) return;
      setState(() {
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

    final dateStr =
        '${pickedDate.year.toString().padLeft(4, '0')}-${pickedDate.month.toString().padLeft(2, '0')}-${pickedDate.day.toString().padLeft(2, '0')}';
    final timeStr = '${pickedTime.hour.toString().padLeft(2, '0')}:${pickedTime.minute.toString().padLeft(2, '0')}';

    try {
      final dayBookings = await _api.listBookings(start: pickedDate, end: pickedDate);
      if (!mounted) return;
      setState(() {
        _date = dateStr;
        _startTime = timeStr;
        _dayBookings = dayBookings;
      });
    } catch (_) {
      // Non-fatal — the chosen slot still gets used, just without the busy-list refresh.
      setState(() {
        _date = dateStr;
        _startTime = timeStr;
      });
    }
  }

  Future<void> _confirm() async {
    if (_date == null || _startTime == null) return;
    setState(() {
      _confirming = true;
      _error = null;
    });
    try {
      await _api.createBooking(
        employeeId: widget.employeeId,
        employeeName: widget.employeeName,
        sessionType: widget.sessionType,
        title: widget.title,
        date: _date!,
        startTime: _startTime!,
        location: _locationCtrl.text.trim().isEmpty ? null : _locationCtrl.text.trim(),
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _confirming = false;
        _error = e.toString();
      });
    }
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
        constraints: const BoxConstraints(maxWidth: 380),
        child: Padding(
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
                        Text(widget.title,
                            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: SelmsColors.textPrimary)),
                        if (widget.employeeName != null)
                          Text('For ${widget.employeeName}',
                              style: const TextStyle(fontSize: 11, color: SelmsColors.textMuted)),
                      ],
                    ),
                  ),
                  InkWell(
                    onTap: () => Navigator.of(context).pop(false),
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
                const Text('Location', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w500, color: SelmsColors.textSecondary)),
                const SizedBox(height: 6),
                TextField(
                  controller: _locationCtrl,
                  decoration: const InputDecoration(hintText: 'e.g. HR Room 1'),
                  style: const TextStyle(fontSize: 13),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Text(_error!, style: const TextStyle(color: SelmsColors.rose, fontSize: 12)),
                ],
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _confirming ? null : _pickDifferentTime,
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
                        onPressed: _confirming ? null : _confirm,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: SelmsColors.ink,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 11),
                        ),
                        child: _confirming
                            ? const SizedBox(
                                width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Text('Confirm slot', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
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
