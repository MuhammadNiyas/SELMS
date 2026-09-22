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
    this.branchALabel,
    this.branchBLabel,
    List<OnboardingFlowNode>? branchA,
    List<OnboardingFlowNode>? branchB,
  })  : branchA = branchA ?? [],
        branchB = branchB ?? [];

  final String id;
  final String type; // 'action' | 'condition'
  String label;
  final String? icon;
  String? sub;
  /// The trigger step ("Employee details inserted") can't be deleted or moved.
  final bool locked;
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
  const FlowStepTemplate({required this.type, required this.icon, required this.label, this.sub});
  final String type; // 'action' | 'condition'
  final String icon;
  final String label;
  final String? sub;
}

const flowStepLibrary = [
  FlowStepTemplate(type: 'action', icon: 'ti-mail', label: 'Send email'),
  FlowStepTemplate(type: 'action', icon: 'ti-bell', label: 'Send notification'),
  FlowStepTemplate(type: 'action', icon: 'ti-checkbox', label: 'Assign task'),
  FlowStepTemplate(type: 'action', icon: 'ti-calendar', label: 'Schedule meeting'),
  FlowStepTemplate(type: 'action', icon: 'ti-qrcode', label: 'QR equipment check'),
  FlowStepTemplate(type: 'action', icon: 'ti-message-circle', label: 'AI chatbot message'),
  FlowStepTemplate(type: 'condition', icon: 'ti-git-branch', label: 'Condition (branch)'),
];
