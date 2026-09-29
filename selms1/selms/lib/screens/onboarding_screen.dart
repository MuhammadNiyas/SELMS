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

import 'package:flutter/material.dart';
import '../models/onboarding_flow_node.dart';
import '../services/api_client.dart';
import '../theme/selms_colors.dart';
import '../widgets/app_shell.dart';
import '../widgets/scheduling_dialog.dart';
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
  Map<String, dynamic>? _selectedEmployee; // null = editing the shared template

  List<OnboardingFlowNode> _nodes = [];
  bool _loading = true;
  bool _saving = false;
  bool _dirty = false;
  String? _error;
  String? _reorderingNodeId;

  @override
  void initState() {
    super.initState();
    _loadCandidatesThenFlow();
  }

  Future<void> _loadCandidatesThenFlow() async {
    try {
      final list = await _api.onboardingCandidates();
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
                                leading: CircleAvatar(
                                  backgroundColor: SelmsColors.accentBg,
                                  child: Text(_initials(c['full_name'] as String),
                                      style: const TextStyle(
                                          fontSize: 11, fontWeight: FontWeight.w600, color: SelmsColors.ink)),
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
      setState(() {
        node.label = labelCtrl.text.trim().isEmpty ? node.label : labelCtrl.text.trim();
        node.sub = subCtrl.text.trim().isEmpty ? null : subCtrl.text.trim();
      });
      _markDirty();
    }
  }

  void _deleteStep(List<OnboardingFlowNode> list, OnboardingFlowNode node) {
    setState(() => list.remove(node));
    _markDirty();
  }

  void _toggleReorder(String nodeId) {
    setState(() => _reorderingNodeId = _reorderingNodeId == nodeId ? null : nodeId);
  }

  void _moveNode(List<OnboardingFlowNode> list, OnboardingFlowNode node, int delta) {
    final from = list.indexOf(node);
    final to = from + delta;
    if (from == -1 || to < 0 || to >= list.length) return;
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

    setState(() => _startingOnboarding = true);
    try {
      final result = await _api.autoStartOnboarding(employeeId);
      if (!mounted) return;
      final orientation = result.orientation;
      final banner = orientation == null
          ? 'No free orientation slot found in the next 14 days — schedule manually.'
          : 'Orientation auto-booked for ${orientation['date']} at ${orientation['start_time']}.';

      await showDialog<void>(
        context: context,
        builder: (_) => _EmailStepDialog(
          apiBaseUrl: widget.apiBaseUrl,
          hrToken: widget.hrToken,
          employeeId: employeeId,
          title: 'Welcome email',
          initialSubject: result.subject,
          initialBody: result.body,
          banner: banner,
        ),
      );
      if (mounted) await _loadCandidatesThenFlow();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.toString()), backgroundColor: SelmsColors.rose));
    } finally {
      if (mounted) setState(() => _startingOnboarding = false);
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
        sessionType: 'orientation',
        title: node.label,
        employeeId: _selectedEmployee!['employee_id'] as String,
        employeeName: _selectedEmployee!['full_name'] as String,
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
      case 'ti-truck-delivery':
        return Icons.local_shipping_outlined;
      case 'ti-package':
        return Icons.inventory_2_outlined;
      default:
        return Icons.circle_outlined;
    }
  }

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length == 1) return parts[0].substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1)).toUpperCase();
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
            Container(
              width: 28,
              height: 28,
              decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
              alignment: Alignment.center,
              child: hasSelection
                  ? Text(_initials(_selectedEmployee!['full_name'] as String),
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: SelmsColors.ink))
                  : const Icon(Icons.person_add_alt_1_outlined, size: 15, color: SelmsColors.ink),
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

    return GestureDetector(
      onTap: isEmailStep
          ? () => _openEmailPopup(node)
          : isScheduleStep
              ? () => _openSchedulingPopup(node)
              : null,
      onDoubleTap: () => _toggleReorder(node.id),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: isReordering ? SelmsColors.accentBg : Colors.white,
          border: Border.all(color: isReordering ? SelmsColors.ink : SelmsColors.border),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: isCondition ? const Color(0xFFF1EFE8) : SelmsColors.accentBg,
                borderRadius: BorderRadius.circular(7),
              ),
              alignment: Alignment.center,
              child: Icon(
                isCondition ? Icons.call_split : _iconFor(node.icon),
                size: 15,
                color: isCondition ? const Color(0xFF444441) : SelmsColors.ink,
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
                      if (isEmailStep || isScheduleStep) ...[
                        const SizedBox(width: 6),
                        const Icon(Icons.open_in_new, size: 11, color: SelmsColors.textMuted),
                      ],
                    ],
                  ),
                  if (node.sub != null)
                    Text(node.sub!, style: const TextStyle(fontSize: 10, color: SelmsColors.textMuted)),
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
                onTap: index > 0 ? () => _moveNode(parentList, node, -1) : null,
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Icon(Icons.keyboard_arrow_up, size: 18,
                      color: index > 0 ? SelmsColors.ink : SelmsColors.border),
                ),
              ),
              InkWell(
                onTap: index < parentList.length - 1 ? () => _moveNode(parentList, node, 1) : null,
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Icon(Icons.keyboard_arrow_down, size: 18,
                      color: index < parentList.length - 1 ? SelmsColors.ink : SelmsColors.border),
                ),
              ),
            ],
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
      children.add(_connector(() => _addStep(nodes, i + 1, allowCondition: allowCondition)));
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
                  OutlinedButton(
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => OnboardingStepperScreen(
                            apiBaseUrl: widget.apiBaseUrl,
                            hrToken: widget.hrToken,
                            employeeId: _selectedEmployee!['employee_id'] as String,
                            fullName: _selectedEmployee!['full_name'] as String,
                          ),
                        ),
                      );
                    },
                    style: OutlinedButton.styleFrom(side: const BorderSide(color: SelmsColors.border)),
                    child: const Text('View checklist', style: TextStyle(fontSize: 12)),
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
            Expanded(child: _buildBody()),
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
    return SingleChildScrollView(
      child: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 520),
          margin: const EdgeInsets.only(bottom: 24),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
          child: Column(
            children: [
              _employeePickerNode(),
              _stepList(_nodes, allowCondition: true),
            ],
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
      final draft = await _api.draftOnboardingEmail(widget.employeeId, instruction: instruction);
      if (!mounted) return;
      setState(() {
        _subjectCtrl.text = draft['subject'] ?? '';
        _bodyCtrl.text = draft['body'] ?? '';
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

  Future<void> _send() async {
    if (_subjectCtrl.text.trim().isEmpty || _bodyCtrl.text.trim().isEmpty) {
      setState(() => _error = 'Subject and body are required.');
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final message = await _api.sendOnboardingEmail(
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
              const Text('AI-drafted — review before sending.',
                  style: TextStyle(fontSize: 11.5, color: SelmsColors.textMuted)),
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
                    onPressed: (_loadingDraft || _sending) ? null : _send,
                    style: ElevatedButton.styleFrom(backgroundColor: SelmsColors.ink, foregroundColor: Colors.white),
                    child: _sending
                        ? const SizedBox(
                            width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Text('Send'),
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
