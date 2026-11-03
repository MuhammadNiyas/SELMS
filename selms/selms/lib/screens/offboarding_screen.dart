// lib/screens/offboarding_screen.dart
//
// The Offboarding tab IS the automation flow builder now — same pattern
// as Onboarding. The first node in the chain is always "Choose employee"
// (locked). Until an employee is picked, everything below that node is
// the shared offboarding template. The moment HR picks someone leaving,
// the rest of the chain swaps to that employee's own copy — edits from
// here on only affect that one employee.

import 'dart:async';
import 'package:flutter/material.dart';
import '../models/onboarding_flow_node.dart';
import '../services/api_client.dart';
import '../widgets/employee_avatar.dart';
import '../theme/selms_colors.dart';
import '../widgets/app_shell.dart';
import '../widgets/flow_step_editors.dart';
import '../widgets/scheduling_dialog.dart';
import '../widgets/start_review_dialog.dart';
import 'employee_view_screen.dart';

const _departureTypes = ['Resignation', 'Termination', 'Retirement'];

class OffboardingScreen extends StatefulWidget {
  const OffboardingScreen({super.key, required this.apiBaseUrl, required this.hrToken});

  final String apiBaseUrl;
  final String hrToken;

  @override
  State<OffboardingScreen> createState() => _OffboardingScreenState();
}

class _OffboardingScreenState extends State<OffboardingScreen> {
  late final ApiClient _api = ApiClient(baseUrl: widget.apiBaseUrl, hrToken: widget.hrToken);

  List<Map<String, dynamic>> _candidates = [];
  Map<String, dynamic>? _selectedEmployee; // null = editing the shared template

  List<OnboardingFlowNode> _nodes = [];
  bool _loading = true;
  bool _saving = false;
  bool _dirty = false;
  String? _error;
  String? _reorderingNodeId;

  // Everyone currently being offboarded (feeds the history panel).
  List<Map<String, dynamic>> _activeOffboarding = [];
  bool _loadingActive = true;
  // Whether the picked employee's offboarding has been started (null = unknown/none picked).
  bool? _selectedStarted;
  /// Departure details for the picked employee (saved before Start, or the ones it started with).
  Map<String, String?>? _departure;
  bool _starting = false;
  bool _cancelling = false;

  // Where the picked employee is in their flow, by node id: each value is
  // {state: done|current|upcoming, kind: auto|it|hr, hint}.
  Map<String, Map<String, dynamic>> _runById = {};
  Timer? _runTimer;
  String? _completingStepId;

  @override
  void initState() {
    super.initState();
    _loadCandidatesThenFlow();
    _loadActive();
    // IT returns equipment from their own screens, so keep this view current.
    _runTimer = Timer.periodic(const Duration(seconds: 15), (_) => _loadRun());
  }

  @override
  void dispose() {
    _runTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadRun() async {
    final emp = _selectedEmployee;
    if (emp == null) {
      if (_runById.isNotEmpty && mounted) setState(() => _runById = {});
      return;
    }
    try {
      final steps = await _api.getOffboardingRun(emp['employee_id'] as String);
      if (!mounted || _selectedEmployee == null) return;
      setState(() => _runById = {for (final s in steps) s['id'] as String: s});
      _loadActive(); // the history panel's progress moves with it
    } catch (_) {
      // Non-fatal - the flow chart still shows, just without step states.
    }
  }

  Future<void> _completeStep(String stepId) async {
    final emp = _selectedEmployee;
    if (emp == null || _completingStepId != null) return;
    setState(() => _completingStepId = stepId);
    try {
      await _api.completeOffboardingStep(emp['employee_id'] as String, stepId);
      await _loadRun();
      await _refreshSelectedStatus();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.toString()), backgroundColor: SelmsColors.rose));
    } finally {
      if (mounted) setState(() => _completingStepId = null);
    }
  }

  Future<void> _loadActive() async {
    try {
      final list = await _api.offboardingActiveList();
      if (!mounted) return;
      setState(() {
        _activeOffboarding = list;
        _loadingActive = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingActive = false);
    }
  }

  /// Looks up whether the picked employee's offboarding has started, to
  /// decide between the Start and Cancel buttons.
  Future<void> _refreshSelectedStatus() async {
    final emp = _selectedEmployee;
    if (emp == null) {
      if (mounted) {
        setState(() {
          _selectedStarted = null;
          _departure = null;
        });
      }
      return;
    }
    try {
      final status = await _api.getEmployeeOffboarding(emp['employee_id'] as String);
      if (!mounted || _selectedEmployee == null) return;
      setState(() {
        _selectedStarted = status.started;
        _departure = status.lastWorkingDay == null
            ? null
            : {'departure_type': status.departureType, 'last_working_day': status.lastWorkingDay, 'notes': status.notes};
      });
    } catch (_) {
      if (mounted) setState(() => _selectedStarted = null);
    }
  }

  void _openEmployee(Map<String, dynamic> e) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => EmployeeViewScreen(
        apiBaseUrl: widget.apiBaseUrl,
        hrToken: widget.hrToken,
        employeeId: e['employee_id'] as String,
      ),
    ));
  }

  /// Departure type, last working day and notes - prefilled with what was
  /// saved. Used by "Departure details" (before Start) and by "Start offboarding".
  Future<Map<String, String>?> _askDepartureDetails({required String title, required String action}) async {
    final saved = _departure;
    final typeValue = ValueNotifier<String>(
        _departureTypes.contains(saved?['departure_type']) ? saved!['departure_type']! : _departureTypes.first);
    final lastDayCtrl = TextEditingController(text: saved?['last_working_day'] ?? '');
    final notesCtrl = TextEditingController(text: saved?['notes'] ?? '');

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: Colors.white,
          title: Text(title, style: const TextStyle(fontSize: 15)),
          content: SizedBox(
            width: 360,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Departure type', style: TextStyle(fontSize: 11.5, color: SelmsColors.textMuted)),
                const SizedBox(height: 4),
                DropdownButtonFormField<String>(
                  initialValue: typeValue.value,
                  items: _departureTypes.map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
                  onChanged: (v) => setDialogState(() => typeValue.value = v ?? typeValue.value),
                  decoration: const InputDecoration(isDense: true, border: OutlineInputBorder()),
                ),
                const SizedBox(height: 14),
                const Text('Last working day', style: TextStyle(fontSize: 11.5, color: SelmsColors.textMuted)),
                const SizedBox(height: 4),
                TextField(
                  controller: lastDayCtrl,
                  readOnly: true,
                  decoration: const InputDecoration(
                    isDense: true,
                    hintText: 'yyyy-mm-dd',
                    border: OutlineInputBorder(),
                    suffixIcon: Icon(Icons.calendar_today_outlined, size: 16),
                  ),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: ctx,
                      initialDate: DateTime.now(),
                      firstDate: DateTime.now().subtract(const Duration(days: 365)),
                      lastDate: DateTime.now().add(const Duration(days: 365)),
                    );
                    if (picked != null) {
                      setDialogState(() => lastDayCtrl.text =
                          '${picked.year.toString().padLeft(4, '0')}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}');
                    }
                  },
                ),
                const SizedBox(height: 14),
                const Text('Notes (optional)', style: TextStyle(fontSize: 11.5, color: SelmsColors.textMuted)),
                const SizedBox(height: 4),
                TextField(
                  controller: notesCtrl,
                  maxLines: 2,
                  decoration: const InputDecoration(isDense: true, border: OutlineInputBorder()),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: lastDayCtrl.text.isEmpty ? null : () => Navigator.of(ctx).pop(true),
              style: ElevatedButton.styleFrom(backgroundColor: SelmsColors.ink, foregroundColor: Colors.white),
              child: Text(action),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true) return null;
    return {
      'departure_type': typeValue.value,
      'last_working_day': lastDayCtrl.text,
      'notes': notesCtrl.text.trim(),
    };
  }

  /// Saves the departure details before Start, so the exit interview can be
  /// planned on or before the last working day.
  Future<void> _editDepartureDetails() async {
    final emp = _selectedEmployee;
    if (emp == null) return;
    final details = await _askDepartureDetails(title: 'Departure details — ${emp['full_name']}', action: 'Save details');
    if (details == null || !mounted) return;
    try {
      await _api.saveOffboardingDetails(
        emp['employee_id'] as String,
        departureType: details['departure_type']!,
        lastWorkingDay: details['last_working_day']!,
        notes: details['notes'],
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Departure details saved.')));
      await _refreshSelectedStatus();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString()), backgroundColor: SelmsColors.rose));
      }
    }
  }

  /// Same details HR gives from the employee profile's "Initiate
  /// offboarding" - now available straight from this tab, prefilled with the
  /// departure details saved before.
  Future<void> _startOffboarding() async {
    final emp = _selectedEmployee;
    if (emp == null) return;
    final details = await _askDepartureDetails(title: 'Start offboarding — ${emp['full_name']}', action: 'Next: review');
    if (details == null || !mounted) return;
    final employeeId = emp['employee_id'] as String;

    // Review first: every step in order. Nothing starts unless HR confirms.
    setState(() => _starting = true);
    Map<String, dynamic> review;
    try {
      await _api.saveOffboardingDetails(
        employeeId,
        departureType: details['departure_type']!,
        lastWorkingDay: details['last_working_day']!,
        notes: details['notes'],
      );
      await _refreshSelectedStatus();
      review = await _api.getStartReview('offboarding', employeeId);
    } catch (e) {
      if (mounted) {
        setState(() => _starting = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString()), backgroundColor: SelmsColors.rose));
      }
      return;
    }
    if (!mounted) return;
    setState(() => _starting = false);
    final confirmed = await showStartReview(context, review: review, apiBaseUrl: widget.apiBaseUrl);
    if (confirmed == null || !mounted) return;

    setState(() => _starting = true);
    try {
      // The reviewed email is saved first, so Start sends it straight away.
      if (confirmed.isNotEmpty) {
        await _api.saveOffboardingEmail(employeeId, confirmed['subject']!, confirmed['body']!);
      }
      final result = await _api.initiateOffboarding(
        emp['employee_id'] as String,
        departureType: details['departure_type']!,
        lastWorkingDay: details['last_working_day']!,
        notes: details['notes']!.isEmpty ? null : details['notes'],
        // The exit interview format is planned with the pencil on that step.
        exitInterviewMode: _plannedMeetingMode('Schedule exit interview'),
      );
      if (!mounted) return;
      // The flow runs straight through, so the banner reports what ran and
      // the first step still waiting on a person.
      final lines = <String>[
        'Offboarding started — the flow has run through its steps.',
        if (result.currentStep != null) 'Still to do: ${result.currentStep}.',
        if (result.emailSent) 'The saved offboarding email was sent.',
        if (result.itNotified) 'IT has been notified.',
        if (result.exitInterview != null)
          'Exit interview booked for ${result.exitInterview!['date']} at ${result.exitInterview!['start_time']}.',
        if (result.meetingWarning != null) result.meetingWarning!,
      ];
      if (result.subject.isNotEmpty) {
        await showDialog<void>(
          context: context,
          builder: (_) => _EmailStepDialog(
            apiBaseUrl: widget.apiBaseUrl,
            hrToken: widget.hrToken,
            employeeId: emp['employee_id'] as String,
            title: 'Offboarding email',
            initialSubject: result.subject,
            initialBody: result.body,
            banner: lines.join('\n'),
          ),
        );
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(lines.join(' '))));
      }
      if (!mounted) return;
      await _refreshSelectedStatus();
      await _loadActive();
      await _loadRun();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.toString()), backgroundColor: SelmsColors.rose));
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  Future<void> _cancelOffboarding() async {
    final emp = _selectedEmployee;
    if (emp == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        title: Text('Cancel offboarding for ${emp['full_name']}?', style: const TextStyle(fontSize: 15)),
        content: const Text(
          'This resets their offboarding progress, removes the exit interview booking and '
          "IT's equipment return request (IT is told). If the offboarding email was already "
          "sent, that can't be recalled. They will disappear from the offboarding history.",
          style: TextStyle(fontSize: 12.5, height: 1.4),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Keep')),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: SelmsColors.rose, foregroundColor: Colors.white),
            child: const Text('Cancel offboarding'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _cancelling = true);
    try {
      final warnings = await _api.cancelOffboarding(emp['employee_id'] as String);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(warnings.isEmpty ? 'Offboarding cancelled.' : 'Offboarding cancelled. ${warnings.join(' ')}')));
      await _refreshSelectedStatus();
      await _loadActive();
      await _loadRun();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.toString()), backgroundColor: SelmsColors.rose));
    } finally {
      if (mounted) setState(() => _cancelling = false);
    }
  }

  Future<void> _loadCandidatesThenFlow() async {
    try {
      final list = await _api.lookupEmployees();
      if (!mounted) return;
      setState(() => _candidates = list);
    } catch (_) {
      // Candidate list is secondary — the flow itself still loads without it.
    }
    await _loadFlow();
  }

  Future<void> _loadFlow() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    _loadRun();
    try {
      final raw = _selectedEmployee == null
          ? await _api.getOffboardingFlowTemplate()
          : await _api.getOffboardingEmployeeFlow(_selectedEmployee!['employee_id'] as String);
      if (!mounted) return;
      setState(() {
        _nodes = raw.map(OnboardingFlowNode.fromJson).toList();
        _loading = false;
        _dirty = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final json = _nodes.map((n) => n.toJson()).toList();
      if (_selectedEmployee == null) {
        await _api.saveOffboardingFlowTemplate(json);
      } else {
        await _api.saveOffboardingEmployeeFlow(_selectedEmployee!['employee_id'] as String, json);
      }
      if (!mounted) return;
      setState(() {
        _saving = false;
        _dirty = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Flow saved.')));
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.toString()), backgroundColor: SelmsColors.rose));
    }
  }

  void _markDirty() => setState(() => _dirty = true);

  Future<void> _pickEmployee() async {
    final picked = await showDialog<Map<String, dynamic>?>(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420, maxHeight: 480),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Choose an employee',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: SelmsColors.textPrimary)),
                const SizedBox(height: 4),
                const Text('Edits below will apply only to this employee\'s copy of the flow.',
                    style: TextStyle(fontSize: 11.5, color: SelmsColors.textMuted)),
                const SizedBox(height: 10),
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ListTile(
                          leading: const Icon(Icons.layers_outlined, size: 18, color: SelmsColors.textSecondary),
                          title: const Text('Default template', style: TextStyle(fontSize: 13)),
                          subtitle: const Text('Applies to every new hire that hasn\'t been customized',
                              style: TextStyle(fontSize: 11)),
                          onTap: () => Navigator.of(context).pop(<String, dynamic>{}),
                        ),
                        const Divider(height: 20),
                        if (_candidates.isEmpty)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 16),
                            child: Text('No employees registered yet.',
                                style: TextStyle(fontSize: 12.5, color: SelmsColors.textMuted)),
                          )
                        else
                          ListView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: _candidates.length,
                            itemBuilder: (context, i) {
                              final c = _candidates[i];
                              return ListTile(
                                leading: EmployeeAvatar(
                                  apiBaseUrl: widget.apiBaseUrl,
                                  name: c['full_name'] as String,
                                  photoUrl: c['profile_image_url'] as String?,
                                  size: 40,
                                ),
                                title: Text(c['full_name'] as String, style: const TextStyle(fontSize: 13)),
                                subtitle: Text('${c['employee_id']} · ${c['department'] ?? ''}',
                                    style: const TextStyle(fontSize: 11.5)),
                                onTap: () => Navigator.of(context).pop(c),
                              );
                            },
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    // null means the dialog was dismissed without a choice — leave selection
    // untouched. An empty map means "Default template" was tapped explicitly.
    if (!mounted || picked == null) return;
    setState(() {
      _selectedEmployee = picked.isEmpty ? null : picked;
      _selectedStarted = null;
    });
    _loadFlow();
    _refreshSelectedStatus();
  }

  Future<void> _addStep(List<OnboardingFlowNode> list, int index, {required bool allowCondition}) async {
    final library =
        allowCondition ? flowStepLibrary : flowStepLibrary.where((t) => t.type != 'condition').toList();

    final picked = await showDialog<FlowStepTemplate>(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360, maxHeight: 420),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Choose a step',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: SelmsColors.textPrimary)),
                const SizedBox(height: 8),
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      children: library
                          .map((t) => ListTile(
                                leading: Icon(_iconFor(t.icon), size: 18, color: SelmsColors.textSecondary),
                                title: Text(t.label, style: const TextStyle(fontSize: 13)),
                                onTap: () => Navigator.of(context).pop(t),
                              ))
                          .toList(),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (picked == null) return;

    final newId = DateTime.now().microsecondsSinceEpoch.toString();
    if (picked.step != null) {
      // Documents / Survey: HR fills in the details before the step is added.
      final stepNode = await buildStepNode(context, _api, picked, newId);
      if (stepNode == null || !mounted) return;
      setState(() => list.insert(index, stepNode));
      _markDirty();
      await _save(); // one save, so the step can't be lost by forgetting a second button
      return;
    }
    final node = picked.type == 'condition'
        ? OnboardingFlowNode(
            id: newId,
            type: 'condition',
            label: 'Condition — choose a field',
            sub: 'Tap edit to configure',
            branchALabel: 'Path 1',
            branchBLabel: 'Path 2',
          )
        : OnboardingFlowNode(id: newId, type: 'action', icon: picked.icon, label: picked.label);

    setState(() => list.insert(index, node));
    _markDirty();
  }

  Future<void> _editStep(OnboardingFlowNode node) async {
    // Email and scheduling steps open their own window from the pencil.
    // (Steps with settings - Documents, Survey, Send email, Send notification - have their own editors below.)
    if (node.step == null && node.locked && node.icon == 'ti-mail') return _openEmailPopup(node);
    if (node.step == null && node.icon == 'ti-calendar') {
      // The orientation / exit interview step is planned here and booked at Start;
      // a meeting added with "+" is booked straight away in the scheduling window.
      return node.locked ? _openMeetingPlan(node) : _openSchedulingPopup(node);
    }
    if (node.step != null) {
      if (await editStepNode(context, _api, node) && mounted) {
        setState(() {});
        _markDirty();
        await _save();
      }
      return;
    }
    final labelCtrl = TextEditingController(text: node.label);
    final subCtrl = TextEditingController(text: node.sub ?? '');
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit step', style: TextStyle(fontSize: 15)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: labelCtrl,
              decoration: const InputDecoration(labelText: 'Title'),
              style: const TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: subCtrl,
              decoration: const InputDecoration(labelText: 'Subtitle (optional)'),
              style: const TextStyle(fontSize: 13),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: SelmsColors.ink, foregroundColor: Colors.white),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (result == true) {
      // An extra step can't take a locked step's name - SELMS would treat it as that step.
      final newLabel = labelCtrl.text.trim();
      if (_nodes.any((n) => n.locked && n.id != node.id && n.label.toLowerCase() == newLabel.toLowerCase())) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text('"$newLabel" is the name of a locked step. Please choose another name.')));
        }
        return;
      }
      setState(() {
        node.label = labelCtrl.text.trim().isEmpty ? node.label : labelCtrl.text.trim();
        node.sub = subCtrl.text.trim().isEmpty ? null : subCtrl.text.trim();
      });
      _markDirty();
    }
  }

  /// The format planned on the orientation / exit interview step; if none was
  /// picked with the pencil: Remote employees online, Onsite in person.
  String _plannedMeetingMode(String label) {
    final node = _nodes.where((n) => n.label == label).firstOrNull;
    final planned = node?.meeting?['mode'] as String?;
    if (planned == 'online' || planned == 'in_person') return planned!;
    return _selectedEmployee?['work_location_type'] == 'Remote' ? 'online' : 'in_person';
  }

  /// Pencil on the orientation / exit interview step: plan the time and format.
  /// Before Start it is only saved; after Start the booked meeting is moved.
  Future<void> _openMeetingPlan(OnboardingFlowNode node) async {
    if (_selectedEmployee == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Choose an employee at the top first — this step needs someone to schedule for.')),
      );
      return;
    }
    final lastDay = _departure?['last_working_day'];
    if (lastDay == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Set the last working day in Departure details first.')),
      );
      return;
    }
    final started = _selectedEmployee != null && _selectedStarted == true;
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => SchedulingDialog(
        apiBaseUrl: widget.apiBaseUrl,
        hrToken: widget.hrToken,
        showLinkField: false,
        sessionType: 'exit_interview',
        title: 'Exit Interview',
        employeeId: _selectedEmployee?['employee_id'] as String?,
        employeeName: _selectedEmployee?['full_name'] as String?,
        employeePhotoUrl: _selectedEmployee?['profile_image_url'] as String?,
        planNode: node,
        process: 'offboarding',
        employee: _selectedEmployee,
        planStarted: started,
        booked: _runById[node.id]?['booked'] as String?,
        notAfter: lastDay,
      ),
    );
    if (result == null || !mounted) return;
    setState(() {
      node.when = result['when'] as Map<String, dynamic>?;
      node.meeting = Map<String, dynamic>.from(result['meeting'] as Map);
    });
    _markDirty();
    await _save();
    if (!started || !mounted) return;
    try {
      final message = await _api.rebookFlowMeeting('offboarding', _selectedEmployee!['employee_id'] as String);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    }
    await _loadRun();
  }

  /// Opens the timing dialog for a step and saves the flow with the new "when".
  Future<void> _editTiming(OnboardingFlowNode node) async {
    final result = await showWhenDialog(
      context,
      node: node,
      process: 'offboarding',
      apiBaseUrl: widget.apiBaseUrl,
      employee: _selectedEmployee,
      // Everything in offboarding is done by the last working day.
      notAfter: _departure?['last_working_day'],
    );
    if (result == null || !mounted) return;
    setState(() => node.when = result['mode'] == 'now' ? null : result);
    _markDirty();
    await _save();
  }

  void _deleteStep(List<OnboardingFlowNode> list, OnboardingFlowNode node) {
    setState(() => list.remove(node));
    _markDirty();
  }

  /// "Complete" always closes the flow: it can't be moved, and nothing can be moved below it.
  bool _isFixedStep(OnboardingFlowNode n) => n.icon == 'ti-flag';

  void _toggleReorder(String nodeId) {
    final node = _nodes.where((n) => n.id == nodeId).firstOrNull;
    if (node != null && _isFixedStep(node)) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('This step always comes last.')));
      return;
    }
    setState(() => _reorderingNodeId = _reorderingNodeId == nodeId ? null : nodeId);
  }

  bool _canMove(List<OnboardingFlowNode> list, int from, int delta) {
    final to = from + delta;
    return from != -1 && to >= 0 && to < list.length && !_isFixedStep(list[to]) && !_isFixedStep(list[from]);
  }

  void _moveNode(List<OnboardingFlowNode> list, OnboardingFlowNode node, int delta) {
    final from = list.indexOf(node);
    final to = from + delta;
    if (!_canMove(list, from, delta)) return;
    setState(() {
      list.removeAt(from);
      list.insert(to, node);
    });
    _markDirty();
  }

  void _openEmailPopup(OnboardingFlowNode node) {
    if (_selectedEmployee == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Choose an employee at the top first — this step needs someone to send to.')),
      );
      return;
    }
    if (_selectedStarted != true) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Start offboarding first — the email is drafted from the departure details.')),
      );
      return;
    }
    showDialog<void>(
      context: context,
      builder: (_) => _EmailStepDialog(
        apiBaseUrl: widget.apiBaseUrl,
        hrToken: widget.hrToken,
        employeeId: _selectedEmployee!['employee_id'] as String,
        title: node.label,
        when: node.when,
      ),
    ).then((_) {
      if (mounted) {
        _loadRun();
        _loadActive();
      }
    });
  }

  void _openSchedulingPopup(OnboardingFlowNode node) {
    if (_selectedEmployee == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Choose an employee at the top first — this step needs someone to schedule for.')),
      );
      return;
    }
    showDialog<bool>(
      context: context,
      builder: (_) => SchedulingDialog(
        apiBaseUrl: widget.apiBaseUrl,
        hrToken: widget.hrToken,
        showLinkField: false,
        // Only the locked step books the real exit interview; a meeting added with "+"
        // is an extra and must never count as it.
        sessionType: node.locked ? 'exit_interview' : 'other',
        title: node.label,
        employeeId: _selectedEmployee!['employee_id'] as String,
        employeeName: _selectedEmployee!['full_name'] as String,
        employeePhotoUrl: _selectedEmployee!['profile_image_url'] as String?,
      ),
    ).then((booked) {
      if (booked == true && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Session scheduled.')));
        _loadRun();
        _loadActive();
      }
    });
  }

  IconData _iconFor(String? key) {
    switch (key) {
      case 'ti-mail':
        return Icons.mail_outline;
      case 'ti-bell':
        return Icons.notifications_none;
      case 'ti-checkbox':
        return Icons.check_box_outlined;
      case 'ti-calendar':
        return Icons.calendar_today_outlined;
      case 'ti-qrcode':
        return Icons.qr_code;
      case 'ti-message-circle':
        return Icons.chat_bubble_outline;
      case 'ti-git-branch':
        return Icons.call_split;
      case 'ti-flag':
        return Icons.flag_outlined;
      case 'ti-file-text':
        return Icons.description_outlined;
      case 'ti-clipboard-list':
        return Icons.fact_check_outlined;
      case 'ti-truck-delivery':
        return Icons.local_shipping_outlined;
      case 'ti-package':
        return Icons.inventory_2_outlined;
      default:
        return Icons.circle_outlined;
    }
  }

  // --- UI builders ---

  Widget _connector(VoidCallback onAdd) {
    return Column(
      children: [
        Container(width: 1, height: 12, color: SelmsColors.border),
        InkWell(
          onTap: onAdd,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: SelmsColors.border),
              color: Colors.white,
            ),
            child: const Icon(Icons.add, size: 13, color: SelmsColors.textSecondary),
          ),
        ),
        Container(width: 1, height: 12, color: SelmsColors.border),
      ],
    );
  }

  /// The permanent first node — tapping it opens the employee picker.
  /// Unlike other nodes it has no edit/delete icons, just this one purpose.
  Widget _employeePickerNode() {
    final hasSelection = _selectedEmployee != null;
    return InkWell(
      onTap: _pickEmployee,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: SelmsColors.accentBg,
          border: Border.all(color: SelmsColors.ink),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            hasSelection
                ? EmployeeAvatar(
                    apiBaseUrl: widget.apiBaseUrl,
                    name: _selectedEmployee!['full_name'] as String,
                    photoUrl: _selectedEmployee!['profile_image_url'] as String?,
                    size: 28,
                    background: Colors.white,
                  )
                : Container(
                    width: 28,
                    height: 28,
                    decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                    alignment: Alignment.center,
                    child: const Icon(Icons.logout, size: 15, color: SelmsColors.ink),
                  ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    hasSelection ? _selectedEmployee!['full_name'] as String : 'Choose employee',
                    style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500, color: SelmsColors.textPrimary),
                  ),
                  Text(
                    hasSelection
                        ? '${_selectedEmployee!['employee_id']} · editing this employee\'s own copy'
                        : 'Tap to pick who this flow applies to — editing the shared template',
                    style: const TextStyle(fontSize: 10, color: SelmsColors.textSecondary),
                  ),
                ],
              ),
            ),
            const Icon(Icons.unfold_more, size: 16, color: SelmsColors.textSecondary),
          ],
        ),
      ),
    );
  }

  Widget _nodeCard(OnboardingFlowNode node, List<OnboardingFlowNode> parentList) {
    final isCondition = node.type == 'condition';
    final isEmailStep = node.icon == 'ti-mail';
    final isScheduleStep = node.icon == 'ti-calendar';
    final isReordering = _reorderingNodeId == node.id;
    final index = parentList.indexOf(node);

    // Where this step is in the picked employee's run (null = no run yet).
    final run = _runById[node.id];
    final runState = run?['state'] as String?;
    final isDone = runState == 'done';
    final isCurrent = runState == 'current';
    // The End step looks like the "Choose employee" box: light blue with a dark outline.
    final isEnd = node.icon == 'ti-flag';
    final hint = run?['hint'] as String?;
    // Steps only a person can finish (HR's own custom steps) get a button.
    final canTick = isCurrent && run?['kind'] == 'hr' && node.label != 'Send offboarding email';

    return GestureDetector(
      onDoubleTap: () => _toggleReorder(node.id),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: isEnd
              ? SelmsColors.accentBg
              : isReordering
              ? SelmsColors.accentBg
              : isDone
                  ? SelmsColors.statusActiveBg.withValues(alpha: 0.45)
                  : isCurrent
                      ? SelmsColors.accentBg
                      : Colors.white,
          border: Border.all(
            color: isEnd || isReordering || isCurrent
                ? SelmsColors.ink
                : isDone
                    ? SelmsColors.statusActiveText.withValues(alpha: 0.35)
                    : SelmsColors.border,
            width: isCurrent && !isEnd ? 1.6 : 1,
          ),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: isEnd
                    ? Colors.white
                    : isDone
                        ? SelmsColors.statusActiveBg
                        : isCondition
                            ? const Color(0xFFF1EFE8)
                            : SelmsColors.accentBg,
                shape: isEnd ? BoxShape.circle : BoxShape.rectangle,
                borderRadius: isEnd ? null : BorderRadius.circular(7),
              ),
              alignment: Alignment.center,
              child: Icon(
                isDone ? Icons.check : (isCondition ? Icons.call_split : _iconFor(node.icon)),
                size: 15,
                color: isDone
                    ? SelmsColors.statusActiveText
                    : isCondition
                        ? const Color(0xFF444441)
                        : SelmsColors.ink,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(node.label,
                            style: const TextStyle(
                                fontSize: 12, fontWeight: FontWeight.w500, color: SelmsColors.textPrimary)),
                      ),
                    ],
                  ),
                  if (node.sub != null)
                    Text(node.sub!, style: const TextStyle(fontSize: 10, color: SelmsColors.textMuted)),
                  // Timing - only on the steps where "when" matters most.
                  // (Meeting steps - orientation / exit interview and "+" meetings - use the pencil, so no line here.)
                  if (supportsTiming(node, 'offboarding') && node.icon != 'ti-calendar')
                    Padding(
                      padding: const EdgeInsets.only(top: 5),
                      child: InkWell(
                        onTap: () => _editTiming(node),
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            border: Border.all(color: SelmsColors.border),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.schedule, size: 11, color: SelmsColors.textSecondary),
                              const SizedBox(width: 4),
                              Text(whenSummary(node.when, 'offboarding'),
                                  style: const TextStyle(fontSize: 10.5, color: SelmsColors.textSecondary)),
                            ],
                          ),
                        ),
                      ),
                    ),
                  // A booked meeting: the real date and time (and why, if it moved from the chosen time).
                  if (isDone && run?['booked'] != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Text(run!['booked'] as String,
                          style: const TextStyle(
                              fontSize: 10.5, fontWeight: FontWeight.w500, color: SelmsColors.statusActiveText)),
                    ),
                  if (isCurrent && hint != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Row(
                        children: [
                          const Icon(Icons.hourglass_top, size: 11, color: SelmsColors.ink),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text('Now: $hint',
                                style: const TextStyle(
                                    fontSize: 10.5, fontWeight: FontWeight.w500, color: SelmsColors.ink)),
                          ),
                        ],
                      ),
                    ),
                  if (canTick)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: SizedBox(
                        height: 26,
                        child: ElevatedButton(
                          onPressed: _completingStepId == node.id ? null : () => _completeStep(node.id),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF16A34A),
                            foregroundColor: Colors.white,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            textStyle: const TextStyle(fontSize: 11),
                          ),
                          child: Text(_completingStepId == node.id ? 'Saving…' : 'Mark done'),
                        ),
                      ),
                    ),
                  if (isReordering)
                    const Padding(
                      padding: EdgeInsets.only(top: 2),
                      child: Text('Double-tap again to stop moving',
                          style: TextStyle(fontSize: 9.5, color: SelmsColors.ink)),
                    ),
                ],
              ),
            ),
            if (isReordering) ...[
              InkWell(
                onTap: _canMove(parentList, index, -1) ? () => _moveNode(parentList, node, -1) : null,
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Icon(Icons.keyboard_arrow_up, size: 18,
                      color: _canMove(parentList, index, -1) ? SelmsColors.ink : SelmsColors.border),
                ),
              ),
              InkWell(
                onTap: _canMove(parentList, index, 1) ? () => _moveNode(parentList, node, 1) : null,
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Icon(Icons.keyboard_arrow_down, size: 18,
                      color: _canMove(parentList, index, 1) ? SelmsColors.ink : SelmsColors.border),
                ),
              ),
            ],
            if (node.locked) ...[
              // Locked steps with settings (Documents, Survey) can be edited but never removed.
              if (node.step != null || isEmailStep || isScheduleStep)
                InkWell(
                  onTap: () => _editStep(node),
                  child: const Padding(
                    padding: EdgeInsets.all(4),
                    child: Icon(Icons.edit_outlined, size: 15, color: SelmsColors.textSecondary),
                  ),
                ),
              const Padding(
                padding: EdgeInsets.all(4),
                child: Icon(Icons.lock_outline, size: 15, color: SelmsColors.textMuted),
              ),
            ] else ...[
              InkWell(
                onTap: () => _editStep(node),
                child: const Padding(
                  padding: EdgeInsets.all(4),
                  child: Icon(Icons.edit_outlined, size: 15, color: SelmsColors.textSecondary),
                ),
              ),
              InkWell(
                onTap: () => _deleteStep(parentList, node),
                child: const Padding(
                  padding: EdgeInsets.all(4),
                  child: Icon(Icons.close, size: 15, color: SelmsColors.rose),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }


  Widget _branchColumn(String label, Color bg, Color fg, List<OnboardingFlowNode> branch) {
    return Expanded(
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
            child: Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w500, color: fg)),
          ),
          const SizedBox(height: 8),
          _stepList(branch, allowCondition: false),
        ],
      ),
    );
  }

  Widget _stepList(List<OnboardingFlowNode> nodes, {required bool allowCondition}) {
    final children = <Widget>[
      _connector(() => _addStep(nodes, 0, allowCondition: allowCondition)),
    ];
    for (var i = 0; i < nodes.length; i++) {
      final node = nodes[i];
      children.add(_nodeCard(node, nodes));
      if (node.type == 'condition') {
        children.add(Column(
          children: [
            Container(width: 1, height: 12, color: SelmsColors.border),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _branchColumn(node.branchALabel ?? 'Path 1', SelmsColors.accentBg, SelmsColors.ink, node.branchA),
                const SizedBox(width: 14),
                _branchColumn(node.branchBLabel ?? 'Path 2', const Color(0xFFFAECE7), const Color(0xFF993C1D), node.branchB),
              ],
            ),
            Container(width: 1, height: 12, color: SelmsColors.border),
          ],
        ));
      }
      // The End step closes the flow, so there is no "+" after it.
      if (node.icon != 'ti-flag') {
        children.add(_connector(() => _addStep(nodes, i + 1, allowCondition: allowCondition)));
      }
    }
    return Column(children: children);
  }

  @override
  Widget build(BuildContext context) {
    return AppShell(
      apiBaseUrl: widget.apiBaseUrl,
      hrToken: widget.hrToken,
      activeRoute: SelmsRoute.offboarding,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Offboarding',
                          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: SelmsColors.textPrimary)),
                      Text('Pick a departing employee at the top, then start offboarding.',
                          style: TextStyle(fontSize: 13, color: SelmsColors.textSecondary)),
                    ],
                  ),
                ),
                if (_selectedEmployee != null && _selectedStarted == false) ...[
                  ElevatedButton.icon(
                    onPressed: _starting ? null : _startOffboarding,
                    icon: _starting
                        ? const SizedBox(
                            width: 14, height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.logout, size: 14),
                    label: Text(_starting ? 'Starting…' : 'Start offboarding', style: const TextStyle(fontSize: 12)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: SelmsColors.ink,
                      foregroundColor: Colors.white,
                      elevation: 0,
                    ),
                  ),
                  const SizedBox(width: 10),
                ],
                if (_selectedEmployee != null && _selectedStarted == true) ...[
                  OutlinedButton.icon(
                    onPressed: _cancelling ? null : _cancelOffboarding,
                    icon: _cancelling
                        ? const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.undo, size: 14, color: SelmsColors.rose),
                    label: Text(_cancelling ? 'Cancelling…' : 'Cancel offboarding',
                        style: const TextStyle(fontSize: 11.5, color: SelmsColors.rose)),
                    style: OutlinedButton.styleFrom(side: const BorderSide(color: SelmsColors.roseBorder)),
                  ),
                  const SizedBox(width: 10),
                ],
                OutlinedButton(
                  onPressed: (_dirty && !_saving) ? _save : null,
                  style: OutlinedButton.styleFrom(
                    backgroundColor: _dirty ? SelmsColors.ink : Colors.white,
                    foregroundColor: _dirty ? Colors.white : SelmsColors.textMuted,
                    side: BorderSide(color: _dirty ? SelmsColors.ink : SelmsColors.border),
                  ),
                  child: _saving
                      ? const SizedBox(
                          width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('Save changes', style: TextStyle(fontSize: 12.5)),
                ),
                const SizedBox(width: 12),
                const TopBarActions(),
              ],
            ),
            const SizedBox(height: 18),
            // Flow card keeps its width; the history sits beside it.
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: _buildBody()),
                  const SizedBox(width: 14),
                  _offboardingHistoryPanel(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Compact side panel: everyone offboarding has been started for, newest
  /// first, with their last working day and a small progress bar.
  Widget _offboardingHistoryPanel() {
    return Container(
      width: 270,
      margin: const EdgeInsets.only(bottom: 24),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text('Offboarding history',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: SelmsColors.textPrimary)),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(color: SelmsColors.accentBg, borderRadius: BorderRadius.circular(10)),
                child: Text('${_activeOffboarding.where((e) => e['completed'] != true).length}',
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: SelmsColors.ink)),
              ),
            ],
          ),
          const SizedBox(height: 2),
          const Text('Tap a person to open their profile.',
              style: TextStyle(fontSize: 11, color: SelmsColors.textMuted)),
          const SizedBox(height: 8),
          const Divider(height: 1, color: SelmsColors.border),
          Expanded(
            child: _loadingActive
                ? const Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)))
                : _activeOffboarding.isEmpty
                    ? const Center(
                        child: Padding(
                          padding: EdgeInsets.all(12),
                          child: Text('No one has been offboarded yet.',
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 12, color: SelmsColors.textMuted)),
                        ),
                      )
                    : _historySections(_activeOffboarding),
          ),
        ],
      ),
    );
  }

  /// "In progress" first, then "Completed" (with the date it finished).
  Widget _historySections(List<Map<String, dynamic>> all) {
    final inProgress = all.where((e) => e['completed'] != true).toList();
    final completed = all.where((e) => e['completed'] == true).toList();
    Widget header(String text, int n) => Padding(
          padding: const EdgeInsets.only(top: 10, bottom: 4),
          child: Text('$text  ·  $n',
              style: const TextStyle(
                  fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.6, color: SelmsColors.textMuted)),
        );
    final children = <Widget>[];
    void addRows(List<Map<String, dynamic>> rows) {
      for (var i = 0; i < rows.length; i++) {
        if (i > 0) children.add(const Divider(height: 1, color: SelmsColors.border));
        children.add(_historyRow(rows[i]));
      }
    }

    if (inProgress.isNotEmpty) {
      children.add(header('IN PROGRESS', inProgress.length));
      addRows(inProgress);
    }
    if (completed.isNotEmpty) {
      children.add(header('COMPLETED', completed.length));
      addRows(completed);
    }
    return ListView(padding: EdgeInsets.zero, children: children);
  }

  Widget _historyRow(Map<String, dynamic> e) {
    final progress = (e['progress_percent'] as num).toInt();
    final done = progress >= 100;
    final name = e['full_name'] as String? ?? '';
    final lastDay = e['last_working_day'] as String?;
    return InkWell(
      onTap: () => _openEmployee(e),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            EmployeeAvatar(
              apiBaseUrl: widget.apiBaseUrl,
              name: name,
              photoUrl: e['profile_image_url'] as String?,
              size: 30,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500)),
                  Text(
                      '${e['employee_id'] ?? ''} · ${e['department'] ?? ''}'
                      '${lastDay != null && lastDay.isNotEmpty ? ' · Last day $lastDay' : ''}',
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 10.5, color: SelmsColors.textMuted)),
                  if (e['completed'] == true && (e['completed_at'] as String?) != null)
                    Text('Completed ${(e['completed_at'] as String).substring(0, 10)}',
                        style: const TextStyle(fontSize: 10.5, color: Color(0xFF047857), fontWeight: FontWeight.w500)),
                  if ((e['login_status'] as String?)?.isNotEmpty == true)
                    Text('Login: ${e['login_status']}',
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 10.5, color: SelmsColors.textMuted)),
                  const SizedBox(height: 5),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: progress / 100,
                      minHeight: 4,
                      backgroundColor: SelmsColors.border,
                      valueColor: AlwaysStoppedAnimation(done ? const Color(0xFF10B981) : SelmsColors.ink),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            done
                ? const Icon(Icons.check_circle, size: 16, color: Color(0xFF10B981))
                : Text('$progress%', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }

  /// Before Start: the departure details (type, last working day, notes), so
  /// the exit interview is planned on or before the last working day.
  Widget _departureDetailsBox() {
    final d = _departure;
    final lastDay = DateTime.tryParse(d?['last_working_day'] ?? '');
    final notes = d?['notes'] ?? '';
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: lastDay == null ? SelmsColors.ink : SelmsColors.border),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Departure details',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: SelmsColors.textPrimary)),
                const SizedBox(height: 2),
                Text(
                  lastDay == null
                      ? 'Not set yet. Set the last working day first, so the exit interview is planned before it.'
                      : '${d!['departure_type'] ?? ''} · Last working day '
                          '${lastDay.day.toString().padLeft(2, '0')}/${lastDay.month.toString().padLeft(2, '0')}/${lastDay.year}'
                          '${notes.isEmpty ? '' : ' · $notes'}',
                  style: const TextStyle(fontSize: 11, color: SelmsColors.textSecondary),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton(
            onPressed: _editDepartureDetails,
            style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
            child: Text(lastDay == null ? 'Set details' : 'Edit', style: const TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(child: Text(_error!, style: const TextStyle(color: SelmsColors.rose, fontSize: 13)));
    }
    // Fills the space up to the history panel; the flow stays 520px wide,
    // centred inside the card (same arrangement as Onboarding).
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight - 24),
          child: Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 24),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Column(
                  children: [
                    _employeePickerNode(),
                    if (_selectedEmployee != null && _selectedStarted == false) _departureDetailsBox(),
                    _stepList(_nodes, allowCondition: true),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Popup opened by tapping a "Send email"-type step in the flow. The
/// dialog's title is the step's own label exactly as HR named it — this
/// isn't a generic "welcome email" screen, it's whatever that specific
/// workflow step was called.
class _EmailStepDialog extends StatefulWidget {
  const _EmailStepDialog({
    required this.apiBaseUrl,
    required this.hrToken,
    required this.employeeId,
    required this.title,
    this.initialSubject,
    this.initialBody,
    this.banner,
    this.when,
  });

  final String apiBaseUrl;
  final String hrToken;
  final String employeeId;
  final String title;

  /// When set (from the one-click "Start offboarding"), the dialog shows
  /// this draft immediately instead of fetching its own.
  final String? initialSubject;
  final String? initialBody;

  /// Optional note shown above the draft, e.g. what the flow has done so far.
  final String? banner;

  /// The step's timing, so the dialog can say when the saved email goes out.
  final Map<String, dynamic>? when;

  @override
  State<_EmailStepDialog> createState() => _EmailStepDialogState();
}

class _EmailStepDialogState extends State<_EmailStepDialog> {
  late final ApiClient _api = ApiClient(baseUrl: widget.apiBaseUrl, hrToken: widget.hrToken);
  final _subjectCtrl = TextEditingController();
  final _bodyCtrl = TextEditingController();
  final _instructionCtrl = TextEditingController();

  bool _loadingDraft = true;
  bool _regenerating = false;
  bool _sending = false;
  bool _alreadySent = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.initialSubject != null && widget.initialBody != null) {
      _subjectCtrl.text = widget.initialSubject!;
      _bodyCtrl.text = widget.initialBody!;
      _loadingDraft = false;
    } else {
      _loadDraft();
    }
  }

  @override
  void dispose() {
    _subjectCtrl.dispose();
    _bodyCtrl.dispose();
    _instructionCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadDraft({String instruction = ''}) async {
    setState(() {
      if (instruction.isEmpty) {
        _loadingDraft = true;
      } else {
        _regenerating = true;
      }
      _error = null;
    });
    try {
      final draft = await _api.draftOffboardingEmail(widget.employeeId, instruction: instruction);
      if (!mounted) return;
      setState(() {
        _subjectCtrl.text = (draft['subject'] as String?) ?? '';
        _bodyCtrl.text = (draft['body'] as String?) ?? '';
        _alreadySent = draft['sent'] == true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) {
        setState(() {
          _loadingDraft = false;
          _regenerating = false;
        });
      }
    }
  }

  Future<void> _save() async {
    if (_subjectCtrl.text.trim().isEmpty || _bodyCtrl.text.trim().isEmpty) {
      setState(() => _error = 'Subject and body are required.');
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final message = await _api.saveOffboardingEmail(
          widget.employeeId, _subjectCtrl.text.trim(), _bodyCtrl.text.trim());
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480, maxHeight: 560),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(widget.title,
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w600, color: SelmsColors.textPrimary)),
                  ),
                  InkWell(
                    onTap: () => Navigator.of(context).pop(),
                    child: const Icon(Icons.close, size: 18, color: SelmsColors.textSecondary),
                  ),
                ],
              ),
              if (_alreadySent) ...[
                const SizedBox(height: 4),
                const Text('This email was already sent.', style: TextStyle(fontSize: 11.5, color: SelmsColors.textMuted)),
              ],
              if (widget.banner != null) ...[
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: SelmsColors.accentBg,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(widget.banner!,
                      style: const TextStyle(fontSize: 11.5, height: 1.4, color: SelmsColors.textPrimary)),
                ),
              ],
              const SizedBox(height: 14),
              if (_loadingDraft)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 40),
                  child: Center(child: CircularProgressIndicator()),
                )
              else
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TextField(
                          controller: _subjectCtrl,
                          decoration: const InputDecoration(labelText: 'Subject'),
                          style: const TextStyle(fontSize: 13),
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: _bodyCtrl,
                          decoration: const InputDecoration(labelText: 'Body'),
                          style: const TextStyle(fontSize: 13),
                          maxLines: 10,
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _instructionCtrl,
                                decoration: const InputDecoration(
                                    labelText: 'Regenerate with instructions (optional)'),
                                style: const TextStyle(fontSize: 12.5),
                              ),
                            ),
                            const SizedBox(width: 8),
                            OutlinedButton(
                              onPressed: _regenerating ? null : () => _loadDraft(instruction: _instructionCtrl.text),
                              style: OutlinedButton.styleFrom(side: const BorderSide(color: SelmsColors.border)),
                              child: _regenerating
                                  ? const SizedBox(
                                      width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                                  : const Text('Regenerate', style: TextStyle(fontSize: 12)),
                            ),
                          ],
                        ),
                        if (_error != null) ...[
                          const SizedBox(height: 8),
                          Text(_error!, style: const TextStyle(color: SelmsColors.rose, fontSize: 12)),
                        ],
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: OutlinedButton.styleFrom(side: const BorderSide(color: SelmsColors.border)),
                    child: const Text('Cancel', style: TextStyle(color: SelmsColors.textSecondary)),
                  ),
                  const SizedBox(width: 10),
                  ElevatedButton(
                    onPressed: (_loadingDraft || _sending || _alreadySent) ? null : _save,
                    style: ElevatedButton.styleFrom(backgroundColor: SelmsColors.ink, foregroundColor: Colors.white),
                    child: _sending
                        ? const SizedBox(
                            width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Text('Save'),
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
