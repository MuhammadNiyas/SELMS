// lib/screens/onboarding_screen.dart
//
// The Onboarding tab IS the automation flow builder now — no separate
// "edit template" detour. The very first node in the chain is always
// "Choose employee" (locked — can't be deleted or renamed, only tapped to
// pick who this flow applies to). Until an employee is picked, everything
// below that node is the shared template. The moment HR picks someone,
// the rest of the chain swaps to that employee's own copy (auto-created
// from the template server-side the first time it's opened) — edits from
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
import 'onboarding_stepper_screen.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key, required this.apiBaseUrl, required this.hrToken});

  final String apiBaseUrl;
  final String hrToken;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  late final ApiClient _api = ApiClient(baseUrl: widget.apiBaseUrl, hrToken: widget.hrToken);

  List<Map<String, dynamic>> _candidates = [];
  List<Map<String, dynamic>> _activeOnboarding = [];
  bool _loadingActive = true;
  Map<String, dynamic>? _selectedEmployee; // null = editing the shared template

  List<OnboardingFlowNode> _nodes = [];
  bool _loading = true;
  bool _saving = false;
  bool _dirty = false;
  String? _error;
  String? _reorderingNodeId;

  // Where the picked employee is in their flow, by node id: each value is
  // {state: done|current|upcoming, kind: auto|it|hr, hint}.
  Map<String, Map<String, dynamic>> _runById = {};
  Timer? _runTimer;
  String? _completingStepId;

  @override
  void initState() {
    super.initState();
    _loadCandidatesThenFlow();
    _loadActiveOnboarding();
    // IT and employees move the flow along from their own screens, so keep
    // this view current.
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
      final steps = await _api.getOnboardingRun(emp['employee_id'] as String);
      if (!mounted || _selectedEmployee == null) return;
      setState(() => _runById = {for (final s in steps) s['id'] as String: s});
      // The history panel's progress moves with it.
      _loadActiveOnboarding();
    } catch (_) {
      // Non-fatal - the flow chart still shows, just without step states.
    }
  }

  Future<void> _completeStep(String stepId) async {
    final emp = _selectedEmployee;
    if (emp == null || _completingStepId != null) return;
    setState(() => _completingStepId = stepId);
    try {
      await _api.completeOnboardingStep(emp['employee_id'] as String, stepId);
      await _loadRun();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.toString()), backgroundColor: SelmsColors.rose));
    } finally {
      if (mounted) setState(() => _completingStepId = null);
    }
  }

  Future<void> _loadActiveOnboarding() async {
    try {
      final list = await _api.onboardingActiveList();
      if (!mounted) return;
      setState(() {
        _activeOnboarding = list;
        _loadingActive = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingActive = false);
    }
  }

  void _openStepperFor(Map<String, dynamic> employee) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => OnboardingStepperScreen(
          apiBaseUrl: widget.apiBaseUrl,
          hrToken: widget.hrToken,
          employeeId: employee['employee_id'] as String,
          fullName: employee['full_name'] as String,
        ),
      ),
    );
  }

  Future<void> _loadCandidatesThenFlow() async {
    try {
      final list = await _api.onboardingCandidates();
      if (!mounted) return;
      setState(() => _candidates = list);
    } catch (_) {
      // Candidate list is secondary — the flow itself still loads without it.
    }
    _loadActiveOnboarding(); // keep the overview list in sync too, no need to await
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
          ? await _api.getFlowTemplate()
          : await _api.getEmployeeFlow(_selectedEmployee!['employee_id'] as String);
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
        await _api.saveFlowTemplate(json);
      } else {
        await _api.saveEmployeeFlow(_selectedEmployee!['employee_id'] as String, json);
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
    setState(() => _selectedEmployee = picked.isEmpty ? null : picked);
    _loadFlow();
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
    final started = _selectedEmployee != null && _runById.isNotEmpty;
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => SchedulingDialog(
        apiBaseUrl: widget.apiBaseUrl,
        hrToken: widget.hrToken,
        sessionType: 'orientation',
        title: 'Orientation',
        employeeId: _selectedEmployee?['employee_id'] as String?,
        employeeName: _selectedEmployee?['full_name'] as String?,
        employeePhotoUrl: _selectedEmployee?['profile_image_url'] as String?,
        planNode: node,
        process: 'onboarding',
        employee: _selectedEmployee,
        planStarted: started,
        booked: _runById[node.id]?['booked'] as String?,
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
      final message = await _api.rebookFlowMeeting('onboarding', _selectedEmployee!['employee_id'] as String);
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
      process: 'onboarding',
      apiBaseUrl: widget.apiBaseUrl,
      employee: _selectedEmployee,
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

  bool _startingOnboarding = false;

  /// One-click automation: drafts the welcome email and auto-books
  /// orientation server-side (see /api/onboarding/<id>/auto-start), then
  /// opens the same review dialog HR would use manually — sending is
  /// still a separate, deliberate click.
  Future<void> _startOnboardingAuto() async {
    if (_selectedEmployee == null) return;
    final employeeId = _selectedEmployee!['employee_id'] as String;

    // Review first: every step in order. Nothing starts unless HR confirms.
    setState(() => _startingOnboarding = true);
    Map<String, dynamic> review;
    try {
      review = await _api.getStartReview('onboarding', employeeId);
    } catch (e) {
      if (mounted) {
        setState(() => _startingOnboarding = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString()), backgroundColor: SelmsColors.rose));
      }
      return;
    }
    if (!mounted) return;
    setState(() => _startingOnboarding = false);
    final confirmed = await showStartReview(context, review: review, apiBaseUrl: widget.apiBaseUrl);
    if (confirmed == null || !mounted) return;

    // The orientation format is planned with the pencil on that step.
    final mode = _plannedMeetingMode('Schedule orientation');

    setState(() => _startingOnboarding = true);
    try {
      // The reviewed email is saved first, so Start sends it straight away.
      if (confirmed.isNotEmpty) {
        await _api.saveOnboardingEmail(employeeId, confirmed['subject']!, confirmed['body']!);
      }
      final result = await _api.autoStartOnboarding(employeeId, mode: mode);
      if (!mounted) return;
      // The flow runs straight through, so the banner reports what ran and
      // the first step still waiting on a person.
      final orientation = result.orientation;
      final lines = <String>[
        'Onboarding started — the flow has run through its steps.',
        if (result.currentStep != null) 'Still to do: ${result.currentStep}.',
        if (result.emailSent) 'The saved onboarding email was sent.',
        if (result.itNotified) 'IT has been notified.',
        if (orientation != null) 'Orientation booked for ${orientation['date']} at ${orientation['start_time']}.',
        if (result.meetingWarning != null) result.meetingWarning!,
      ];

      if (result.subject.isNotEmpty) {
        await showDialog<void>(
          context: context,
          builder: (_) => _EmailStepDialog(
            apiBaseUrl: widget.apiBaseUrl,
            hrToken: widget.hrToken,
            employeeId: employeeId,
            title: 'Welcome email',
            initialSubject: result.subject,
            initialBody: result.body,
            banner: lines.join('\n'),
          ),
        );
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(lines.join(' '))));
      }
      if (mounted) {
        await _loadCandidatesThenFlow();
        await _loadRun();
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.toString()), backgroundColor: SelmsColors.rose));
    } finally {
      if (mounted) setState(() => _startingOnboarding = false);
    }
  }

  bool _cancellingOnboarding = false;

  /// Undoes an accidental "Start onboarding" click — confirms first,
  /// then shows whatever warnings the backend returns (e.g. the welcome
  /// email already went out and can't be recalled).
  Future<void> _cancelOnboardingFlow() async {
    if (_selectedEmployee == null) return;
    final employeeId = _selectedEmployee!['employee_id'] as String;
    final name = _selectedEmployee!['full_name'] as String;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        title: Text('Cancel onboarding for $name?', style: const TextStyle(fontSize: 15)),
        content: const Text(
          'This resets onboarding progress and removes any auto-booked orientation. '
          "If the welcome email was already sent or equipment already assigned, "
          "those real-world actions can't be undone — you'll see a warning after if so.",
          style: TextStyle(fontSize: 12.5, height: 1.4),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Keep it')),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: SelmsColors.rose, foregroundColor: Colors.white),
            child: const Text('Cancel onboarding'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _cancellingOnboarding = true);
    try {
      final result = await _api.cancelOnboarding(employeeId);
      if (!mounted) return;
      if (result.warnings.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Onboarding cancelled.')));
      } else {
        await showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            backgroundColor: Colors.white,
            title: const Text('Onboarding cancelled — with warnings', style: TextStyle(fontSize: 15)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: result.warnings
                  .map((w) => Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Text('•  $w', style: const TextStyle(fontSize: 12.5, height: 1.4)),
                      ))
                  .toList(),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Got it')),
            ],
          ),
        );
      }
      if (mounted) await _loadCandidatesThenFlow();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.toString()), backgroundColor: SelmsColors.rose));
    } finally {
      if (mounted) setState(() => _cancellingOnboarding = false);
    }
  }

  void _openEmailPopup(OnboardingFlowNode node) {
    if (_selectedEmployee == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Choose an employee at the top first — this step needs someone to send to.')),
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
    );
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
        // Only the locked step books the real orientation; a meeting added with "+"
        // is an extra and must never count as it.
        sessionType: node.locked ? 'orientation' : 'other',
        title: node.label,
        employeeId: _selectedEmployee!['employee_id'] as String,
        employeeName: _selectedEmployee!['full_name'] as String,
        employeePhotoUrl: _selectedEmployee!['profile_image_url'] as String?,
      ),
    ).then((booked) {
      if (booked == true && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Session scheduled.')));
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
      case 'ti-map-pin':
        return Icons.place_outlined;
      case 'ti-device-laptop':
        return Icons.laptop_mac_outlined;
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
                    child: const Icon(Icons.person_add_alt_1_outlined, size: 15, color: SelmsColors.ink),
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
    final canTick = isCurrent && run?['kind'] == 'hr' && node.label != 'Send welcome email';

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
                  if (supportsTiming(node, 'onboarding') && node.icon != 'ti-calendar')
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
                              Text(whenSummary(node.when, 'onboarding'),
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
      activeRoute: SelmsRoute.onboarding,
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
                      Text('Onboarding',
                          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: SelmsColors.textPrimary)),
                      Text('Pick an employee at the top to build or edit their onboarding flow.',
                          style: TextStyle(fontSize: 13, color: SelmsColors.textSecondary)),
                    ],
                  ),
                ),
                if (_selectedEmployee != null) ...[
                  if (_selectedEmployee!['onboarding_started'] != true) ...[
                    ElevatedButton.icon(
                      onPressed: _startingOnboarding ? null : _startOnboardingAuto,
                      icon: _startingOnboarding
                          ? const SizedBox(
                              width: 14, height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.auto_awesome, size: 14),
                      label: Text(_startingOnboarding ? 'Starting…' : 'Start onboarding',
                          style: const TextStyle(fontSize: 12)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: SelmsColors.ink,
                        foregroundColor: Colors.white,
                        elevation: 0,
                      ),
                    ),
                    const SizedBox(width: 10),
                  ],
                  if (_selectedEmployee!['onboarding_started'] == true) ...[
                    OutlinedButton.icon(
                      onPressed: _cancellingOnboarding ? null : _cancelOnboardingFlow,
                      icon: _cancellingOnboarding
                          ? const SizedBox(
                              width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.undo, size: 14, color: SelmsColors.rose),
                      label: Text(_cancellingOnboarding ? 'Cancelling…' : 'Cancel onboarding',
                          style: const TextStyle(fontSize: 11.5, color: SelmsColors.rose)),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: SelmsColors.roseBorder),
                      ),
                    ),
                    const SizedBox(width: 10),
                  ],
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
            // The flow chart keeps all the width it had; the history panel
            // sits beside it instead of above it, so it never shrinks the chart.
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: _buildBody()),
                  const SizedBox(width: 14),
                  _onboardingHistoryPanel(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Compact side panel: everyone who has been put through onboarding,
  /// newest first, with a small progress bar (a full bar + check = done).
  /// Tap a person to open their step-by-step checklist.
  Widget _onboardingHistoryPanel() {
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
                child: Text('Onboarding history',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: SelmsColors.textPrimary)),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(color: SelmsColors.accentBg, borderRadius: BorderRadius.circular(10)),
                child: Text('${_activeOnboarding.where((e) => e['completed'] != true).length}',
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: SelmsColors.ink)),
              ),
            ],
          ),
          const SizedBox(height: 2),
          const Text('Tap a person to open their checklist.',
              style: TextStyle(fontSize: 11, color: SelmsColors.textMuted)),
          const SizedBox(height: 8),
          const Divider(height: 1, color: SelmsColors.border),
          Expanded(
            child: _loadingActive
                ? const Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)))
                : _activeOnboarding.isEmpty
                    ? const Center(
                        child: Padding(
                          padding: EdgeInsets.all(12),
                          child: Text('No one has been onboarded yet.',
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 12, color: SelmsColors.textMuted)),
                        ),
                      )
                    : _historySections(_activeOnboarding),
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
    return InkWell(
      onTap: () => _openStepperFor(e),
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
                  Text('${e['employee_id'] ?? ''} · ${e['department'] ?? ''}',
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 10.5, color: SelmsColors.textMuted)),
                  if (e['completed'] == true && (e['completed_at'] as String?) != null)
                    Text('Completed ${(e['completed_at'] as String).substring(0, 10)}',
                        style: const TextStyle(fontSize: 10.5, color: Color(0xFF047857), fontWeight: FontWeight.w500)),
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

  Widget _buildBody() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(child: Text(_error!, style: const TextStyle(color: SelmsColors.rose, fontSize: 13)));
    }
    // The card fills the space up to the history panel (a small gap, like two
    // cards side by side) instead of floating centred in empty space; the
    // flow itself stays at its normal 520px width, centred inside the card.
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

  /// When set (from the one-click "Start Onboarding" automation), the
  /// dialog shows this draft immediately instead of fetching its own —
  /// avoids a second, different AI call right after the first.
  final String? initialSubject;
  final String? initialBody;

  /// Optional note shown above the draft, e.g. confirming the
  /// auto-booked orientation slot.
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
  bool _started = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.initialSubject != null && widget.initialBody != null) {
      _subjectCtrl.text = widget.initialSubject!;
      _bodyCtrl.text = widget.initialBody!;
      _started = true; // opened by the Start button
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
      final draft = await _api.draftOnboardingEmail(widget.employeeId, instruction: instruction);
      if (!mounted) return;
      setState(() {
        _subjectCtrl.text = (draft['subject'] as String?) ?? '';
        _bodyCtrl.text = (draft['body'] as String?) ?? '';
        _alreadySent = draft['sent'] == true;
        _started = draft['started'] == true;
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

  String _caption() {
    if (_alreadySent) return 'This email was already sent.';
    if (!_started) return 'Review and edit, then Save. It is sent when you click Start onboarding.';
    final at = whenDateTime(widget.when);
    if (at != null && at.isAfter(DateTime.now())) {
      return 'Review and edit, then Save. SELMS sends it on ${whenAtText(widget.when)}.';
    }
    return 'Review and edit, then Save. The flow sends it as soon as this step runs.';
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
      final message = await _api.saveOnboardingEmail(
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
              const SizedBox(height: 4),
              Text(_caption(), style: const TextStyle(fontSize: 11.5, color: SelmsColors.textMuted)),
              if (widget.banner != null) ...[
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: SelmsColors.statusActiveBg,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(widget.banner!,
                      style: const TextStyle(fontSize: 11.5, color: SelmsColors.statusActiveText)),
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
