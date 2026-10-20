// lib/models/onboarding_flow_node.dart
//
// A node is either a plain action step, or a condition step that splits
// into two branches (each branch holding a flat list of action nodes —
// no nesting a condition inside a branch, to keep this simple).

class OnboardingFlowNode {
  OnboardingFlowNode({
    required this.id,
    required this.type,
    required this.label,
    this.icon,
    this.sub,
    this.locked = false,
    this.step,
    this.key,
    this.notify,
    this.email,
    this.when,
    this.meeting,
    List<Map<String, dynamic>>? docs,
    this.survey,
    this.branchALabel,
    this.branchBLabel,
    List<OnboardingFlowNode>? branchA,
    List<OnboardingFlowNode>? branchB,
  })  : docs = docs ?? [],
        branchA = branchA ?? [],
        branchB = branchB ?? [];

  final String id;
  final String type; // 'action' | 'condition'
  String label;
  final String? icon;
  String? sub;
  /// Locked steps (the default ones) can't be deleted.
  final bool locked;

  /// Set for the steps the employee takes part in: 'documents' or 'survey'.
  final String? step;

  /// When the step should happen: {mode: now | before | after | on_date, days, date}. Null = immediately.
  Map<String, dynamic>? when;

  /// Orientation / exit interview step: {mode: in_person | online}, planned before Start.
  Map<String, dynamic>? meeting;

  /// Marks the default steps the server keeps in every flow (e.g. 'default_documents').
  final String? key;

  /// Notification step: {title, message, to: {employee, it, hr}, people: [{id, name, role}]}.
  Map<String, dynamic>? notify;

  /// Email step: {subject, message, to: {employee, it, hr}}.
  Map<String, dynamic>? email;

  /// Documents step: [{id, title, action, instructions, file_id, filename}].
  List<Map<String, dynamic>> docs;

  /// Survey step: {title, questions: [{id, text, type}]}.
  Map<String, dynamic>? survey;
  String? branchALabel;
  String? branchBLabel;
  final List<OnboardingFlowNode> branchA;
  final List<OnboardingFlowNode> branchB;

  factory OnboardingFlowNode.fromJson(Map<String, dynamic> j) => OnboardingFlowNode(
        id: j['id'] as String,
        type: j['type'] as String,
        label: j['label'] as String,
        icon: j['icon'] as String?,
        sub: j['sub'] as String?,
        locked: j['locked'] as bool? ?? false,
        step: j['step'] as String?,
        key: j['key'] as String?,
        notify: j['notify'] == null ? null : Map<String, dynamic>.from(j['notify'] as Map),
        email: j['email'] == null ? null : Map<String, dynamic>.from(j['email'] as Map),
        when: j['when'] == null ? null : Map<String, dynamic>.from(j['when'] as Map),
        meeting: j['meeting'] == null ? null : Map<String, dynamic>.from(j['meeting'] as Map),
        docs: (j['docs'] as List?)?.map((e) => Map<String, dynamic>.from(e as Map)).toList(),
        survey: j['survey'] == null ? null : Map<String, dynamic>.from(j['survey'] as Map),
        branchALabel: j['branch_a_label'] as String?,
        branchBLabel: j['branch_b_label'] as String?,
        branchA: (j['branch_a'] as List?)
                ?.map((e) => OnboardingFlowNode.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [],
        branchB: (j['branch_b'] as List?)
                ?.map((e) => OnboardingFlowNode.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [],
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type,
        'label': label,
        if (icon != null) 'icon': icon,
        if (sub != null) 'sub': sub,
        if (locked) 'locked': locked,
        if (step != null) 'step': step,
        if (key != null) 'key': key,
        if (step == 'notification' && notify != null) 'notify': notify,
        if (step == 'email' && email != null) 'email': email,
        if (when != null) 'when': when,
        if (meeting != null) 'meeting': meeting,
        if (step == 'documents') 'docs': docs,
        if (step == 'survey' && survey != null) 'survey': survey,
        if (type == 'condition') ...{
          'branch_a_label': branchALabel,
          'branch_b_label': branchBLabel,
          'branch_a': branchA.map((n) => n.toJson()).toList(),
          'branch_b': branchB.map((n) => n.toJson()).toList(),
        },
      };
}

/// The library of step types offered behind every "+" button.
class FlowStepTemplate {
  const FlowStepTemplate({required this.type, required this.icon, required this.label, this.sub, this.step});
  final String type; // 'action' | 'condition'
  final String? step; // 'documents' | 'survey' - steps the employee takes part in
  final String icon;
  final String label;
  final String? sub;
}

const flowStepLibrary = [
  FlowStepTemplate(type: 'action', icon: 'ti-mail', label: 'Send email', step: 'email'),
  FlowStepTemplate(type: 'action', icon: 'ti-bell', label: 'Send notification', step: 'notification'),
  FlowStepTemplate(type: 'action', icon: 'ti-calendar', label: 'Schedule meeting'),
  FlowStepTemplate(type: 'action', icon: 'ti-file-text', label: 'Documents', step: 'documents'),
  FlowStepTemplate(type: 'action', icon: 'ti-clipboard-list', label: 'Survey', step: 'survey'),
  // "Condition (branch)" was removed: it was never wired into the flow engine.
];
