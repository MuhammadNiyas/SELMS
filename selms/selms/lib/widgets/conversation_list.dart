// lib/widgets/conversation_list.dart
//
// The left side of HR's and IT's Messages pages: a search box, the other team,
// and every employee, so staff can open anyone and start messaging them. Also
// the bar above the open chat, and the employee card their photo opens.

import 'package:flutter/material.dart';
import '../models/message.dart';
import '../theme/selms_colors.dart';
import 'employee_avatar.dart';
import 'employee_card.dart';

/// Pop-up with the same card as the Employees page. [onOpenEmployee] makes the
/// card open the full employee page (HR only: it holds IC and salary). A team's
/// card shows its full name and email.
Future<void> showEmployeeCard(
  BuildContext context, {
  required String apiBaseUrl,
  required MessageConversation conversation,
  ValueChanged<String>? onOpenEmployee,
}) {
  final c = conversation;
  return showDialog<void>(
    context: context,
    builder: (ctx) => Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: SizedBox(
        width: 340,
        height: c.isTeam ? 118 : 142,
        child: c.isTeam
            ? EmployeeCard(
                apiBaseUrl: apiBaseUrl,
                name: c.teamTitle ?? c.employeeName,
                initials: c.avatarInitials,
                jobTitle: c.workEmail,
                workEmail: c.workEmail,
              )
            : EmployeeCard(
                apiBaseUrl: apiBaseUrl,
                name: c.employeeName,
                employeeId: c.employeeId,
                photoUrl: c.profileImageUrl,
                jobTitle: c.jobTitle,
                department: c.department,
                workEmail: c.workEmail,
                mobileNumber: c.mobileNumber,
                onTap: onOpenEmployee == null
                    ? null
                    : () {
                        Navigator.of(ctx).pop();
                        onOpenEmployee(c.employeeId);
                      },
              ),
      ),
    ),
  );
}

/// The bar above the open chat: who it is with. Clicking it opens their card.
class ConversationHeader extends StatelessWidget {
  const ConversationHeader({
    super.key,
    required this.apiBaseUrl,
    required this.conversation,
    this.onOpenEmployee,
  });

  final String apiBaseUrl;
  final MessageConversation conversation;
  final ValueChanged<String>? onOpenEmployee;

  @override
  Widget build(BuildContext context) {
    final c = conversation;
    final subtitle = c.isTeam ? '' : [c.employeeId, if ((c.department ?? '').isNotEmpty) c.department].join(' · ');
    final content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          EmployeeAvatar(
            apiBaseUrl: apiBaseUrl,
            name: c.employeeName,
            photoUrl: c.profileImageUrl,
            initials: c.avatarInitials,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(c.employeeName,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis),
                if (subtitle.isNotEmpty)
                  Text(subtitle,
                      style: const TextStyle(fontSize: 11, color: SelmsColors.textMuted),
                      overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
        ],
      ),
    );
    return InkWell(
      onTap: () => showEmployeeCard(context,
          apiBaseUrl: apiBaseUrl, conversation: c, onOpenEmployee: onOpenEmployee),
      child: content,
    );
  }
}

class ConversationList extends StatefulWidget {
  const ConversationList({
    super.key,
    required this.apiBaseUrl,
    required this.conversations,
    required this.selectedEmployeeId,
    required this.onSelect,
    this.onOpenEmployee,
  });

  final String apiBaseUrl;
  final List<MessageConversation> conversations;
  final String? selectedEmployeeId;
  final ValueChanged<String> onSelect;
  final ValueChanged<String>? onOpenEmployee;

  @override
  State<ConversationList> createState() => _ConversationListState();
}

class _ConversationListState extends State<ConversationList> {
  final _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  /// Every word typed must appear in the name, ID, department or job title.
  List<MessageConversation> get _matches {
    final words = _searchCtrl.text.toLowerCase().split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
    return widget.conversations.where((c) {
      final text = [c.employeeName, c.teamTitle ?? '', if (!c.isTeam) c.employeeId, c.department ?? '', c.jobTitle ?? '']
          .join(' ')
          .toLowerCase();
      return words.every(text.contains);
    }).toList();
  }

  Widget _searchBox() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8)),
      child: Row(
        children: [
          const Padding(
            padding: EdgeInsets.only(left: 2),
            child: Icon(Icons.search, size: 15, color: SelmsColors.textMuted),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: TextField(
              controller: _searchCtrl,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                border: InputBorder.none,
                isDense: true,
                hintText: 'Search employees...',
                hintStyle: TextStyle(fontSize: 12.5, color: SelmsColors.textMuted),
              ),
              style: const TextStyle(fontSize: 12.5),
            ),
          ),
        ],
      ),
    );
  }

  Widget _row(MessageConversation c) {
    final selected = c.employeeId == widget.selectedEmployeeId;
    final subtitle = c.lastMessage.isNotEmpty || c.isTeam
        ? c.lastMessage
        : [c.employeeId, if ((c.department ?? '').isNotEmpty) c.department].join(' · ');
    final avatar = EmployeeAvatar(
      apiBaseUrl: widget.apiBaseUrl,
      name: c.employeeName,
      photoUrl: c.profileImageUrl,
      initials: c.avatarInitials,
    );
    return InkWell(
      onTap: () => widget.onSelect(c.employeeId),
      child: Container(
        color: selected ? SelmsColors.accentBg : null,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            InkWell(
              customBorder: const CircleBorder(),
              onTap: () => showEmployeeCard(context,
                  apiBaseUrl: widget.apiBaseUrl, conversation: c, onOpenEmployee: widget.onOpenEmployee),
              child: avatar,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(c.employeeName,
                      style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                      overflow: TextOverflow.ellipsis),
                  if (subtitle.isNotEmpty)
                    Text(subtitle,
                        style: const TextStyle(fontSize: 11, color: SelmsColors.textMuted),
                        overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            if (c.unreadCount > 0)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: SelmsColors.rose, borderRadius: BorderRadius.circular(10)),
                child: Text('${c.unreadCount}',
                    style: const TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.w700)),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final matches = _matches;
    return Column(
      children: [
        _searchBox(),
        const SizedBox(height: 10),
        Expanded(
          child: Container(
            width: double.infinity,
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
            child: matches.isEmpty
                ? const Center(
                    child: Text('No employees found.', style: TextStyle(fontSize: 12.5, color: SelmsColors.textMuted)),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    itemCount: matches.length,
                    separatorBuilder: (_, _) => const Divider(height: 1, color: SelmsColors.border),
                    itemBuilder: (context, i) => _row(matches[i]),
                  ),
          ),
        ),
      ],
    );
  }
}
