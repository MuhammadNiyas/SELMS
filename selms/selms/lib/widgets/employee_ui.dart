// lib/widgets/employee_ui.dart
//
// Small shared building blocks for the employee app, so every tab uses the
// same card, spacing, status colours and timeline - one consistent look
// instead of each screen styling its own boxes.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/employee_self_service.dart';
import '../theme/selms_colors.dart';

/// Employee-app accents on top of the shared SELMS palette.
class EmpColors {
  static const pageBg = Color(0xFFF3F6FA);
  static const success = Color(0xFF16A34A);
  static const successBg = Color(0xFFDCFCE7);
  static const warning = Color(0xFFB45309);
  static const warningBg = Color(0xFFFEF3C7);
  static const leaving = Color(0xFF9F1239); // offboarding accent
  static const leavingBg = Color(0xFFFFE4E6);
}

// ---------------------------------------------------------------- formatting

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

/// "12 Oct 2026" from an ISO date/datetime, or "—".
String empDate(String? iso, {bool weekday = false}) {
  final d = iso == null ? null : DateTime.tryParse(iso);
  if (d == null) return '—';
  final base = '${d.day} ${_months[d.month - 1]} ${d.year}';
  return weekday ? '${_weekdays[d.weekday - 1]}, $base' : base;
}

/// "10:00 – 10:30" for a start "HH:MM" and a length in minutes.
String empTimeRange(String start, int minutes) {
  final p = start.split(':');
  if (p.length != 2) return start;
  final total = int.parse(p[0]) * 60 + int.parse(p[1]) + minutes;
  final end = '${(total ~/ 60).toString().padLeft(2, '0')}:${(total % 60).toString().padLeft(2, '0')}';
  return '$start – $end';
}

String empRelative(String iso) {
  final at = DateTime.tryParse(iso);
  if (at == null) return '';
  final diff = DateTime.now().toUtc().difference(at.toUtc());
  if (diff.inMinutes < 1) return 'Just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
  if (diff.inHours < 24) return '${diff.inHours} h ago';
  if (diff.inDays == 1) return 'Yesterday';
  if (diff.inDays < 7) return '${diff.inDays} days ago';
  return empDate(iso);
}

String empGreeting() {
  final h = DateTime.now().hour;
  if (h < 12) return 'Good morning';
  if (h < 18) return 'Good afternoon';
  return 'Good evening';
}

// ---------------------------------------------------------------- building blocks

class EmpCard extends StatelessWidget {
  const EmpCard({super.key, required this.child, this.padding = const EdgeInsets.all(16), this.onTap, this.color});

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color ?? Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          width: double.infinity,
          padding: padding,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: SelmsColors.border),
          ),
          child: child,
        ),
      ),
    );
  }
}

class EmpSectionHeader extends StatelessWidget {
  const EmpSectionHeader(this.title, {super.key, this.trailing});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 18, 2, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(title.toUpperCase(),
                style: const TextStyle(
                    fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.8, color: SelmsColors.textMuted)),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

class EmpPill extends StatelessWidget {
  const EmpPill(this.text, {super.key, required this.bg, required this.fg, this.icon});

  final String text;
  final Color bg;
  final Color fg;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 12, color: fg), const SizedBox(width: 4)],
          Text(text, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: fg)),
        ],
      ),
    );
  }
}

class EmpProgressRing extends StatelessWidget {
  const EmpProgressRing({
    super.key,
    required this.percent,
    this.size = 64,
    this.color = Colors.white,
    this.trackColor = const Color(0x33FFFFFF),
    this.textColor = Colors.white,
  });

  final int percent;
  final double size;
  final Color color;
  final Color trackColor;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: size,
            height: size,
            child: CircularProgressIndicator(
              value: (percent.clamp(0, 100)) / 100,
              strokeWidth: size / 10,
              backgroundColor: trackColor,
              valueColor: AlwaysStoppedAnimation(color),
              strokeCap: StrokeCap.round,
            ),
          ),
          Text('$percent%',
              style: TextStyle(fontSize: size / 4.6, fontWeight: FontWeight.w700, color: textColor)),
        ],
      ),
    );
  }
}

class EmpIconBadge extends StatelessWidget {
  const EmpIconBadge(this.icon, {super.key, this.bg = SelmsColors.accentBg, this.fg = SelmsColors.ink, this.size = 38});

  final IconData icon;
  final Color bg;
  final Color fg;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(size * 0.28)),
      alignment: Alignment.center,
      child: Icon(icon, size: size * 0.5, color: fg),
    );
  }
}

class EmpEmptyState extends StatelessWidget {
  const EmpEmptyState({super.key, required this.icon, required this.title, this.message = ''});

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 24),
      child: Column(
        children: [
          EmpIconBadge(icon, size: 52, bg: Colors.white, fg: SelmsColors.textMuted),
          const SizedBox(height: 12),
          Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
          if (message.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(message,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12.5, color: SelmsColors.textMuted, height: 1.4)),
          ],
        ],
      ),
    );
  }
}

class EmpErrorState extends StatelessWidget {
  const EmpErrorState({super.key, required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const SizedBox(height: 40),
        const EmpIconBadge(Icons.cloud_off_outlined, size: 52, bg: SelmsColors.roseBg, fg: SelmsColors.rose),
        const SizedBox(height: 12),
        const Text("Couldn't load this right now",
            textAlign: TextAlign.center, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        Text(message,
            textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, color: SelmsColors.textMuted)),
        const SizedBox(height: 14),
        Center(
          child: OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh, size: 16),
            label: const Text('Try again'),
          ),
        ),
      ],
    );
  }
}

/// Grey placeholder blocks shown while a tab loads.
class EmpLoading extends StatelessWidget {
  const EmpLoading({super.key});

  @override
  Widget build(BuildContext context) {
    Widget block(double h) => Container(
          height: h,
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(color: const Color(0xFFE8EDF3), borderRadius: BorderRadius.circular(14)),
        );
    return ListView(
      padding: const EdgeInsets.all(16),
      physics: const NeverScrollableScrollPhysics(),
      children: [block(120), block(84), block(84), block(64)],
    );
  }
}

/// A bottom sheet with a step's full details - used when an employee taps
/// a step on their onboarding / offboarding journey.
Future<void> showEmpSheet(
  BuildContext context, {
  required IconData icon,
  required String title,
  String? subtitle,
  required List<Widget> children,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    constraints: const BoxConstraints(maxWidth: 480),
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (ctx) => SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.85),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(color: SelmsColors.border, borderRadius: BorderRadius.circular(2)),
                ),
              ),
              Row(
                children: [
                  EmpIconBadge(icon, size: 42),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                        if (subtitle != null)
                          Text(subtitle, style: const TextStyle(fontSize: 12, color: SelmsColors.textMuted)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              ...children,
            ],
          ),
        ),
      ),
    ),
  );
}

/// Paragraph text inside a details sheet.
class EmpSheetText extends StatelessWidget {
  const EmpSheetText(this.text, {super.key, this.heading});

  final String text;
  final String? heading;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (heading != null) ...[
            Text(heading!.toUpperCase(),
                style: const TextStyle(
                    fontSize: 10.5, fontWeight: FontWeight.w700, letterSpacing: 0.7, color: SelmsColors.textMuted)),
            const SizedBox(height: 4),
          ],
          Text(text, style: const TextStyle(fontSize: 13, color: SelmsColors.textSecondary, height: 1.45)),
        ],
      ),
    );
  }
}

/// A labelled value with a copy button (meeting link, parcel reference).
class EmpCopyRow extends StatelessWidget {
  const EmpCopyRow({super.key, required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        border: Border.all(color: SelmsColors.border),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(fontSize: 10.5, color: SelmsColors.textMuted)),
                const SizedBox(height: 2),
                SelectableText(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Copy',
            icon: const Icon(Icons.copy_rounded, size: 18, color: SelmsColors.ink),
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: value));
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$label copied.')));
            },
          ),
        ],
      ),
    );
  }
}

/// Full-width action button inside a details sheet.
class EmpSheetButton extends StatelessWidget {
  const EmpSheetButton({super.key, required this.label, required this.icon, required this.onPressed, this.primary = true});

  final String label;
  final IconData icon;
  final VoidCallback onPressed;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(10));
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: SizedBox(
        width: double.infinity,
        child: primary
            ? ElevatedButton.icon(
                onPressed: onPressed,
                icon: Icon(icon, size: 18),
                label: Text(label, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: SelmsColors.ink,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: shape,
                ),
              )
            : OutlinedButton.icon(
                onPressed: onPressed,
                icon: Icon(icon, size: 18, color: SelmsColors.ink),
                label: Text(label,
                    style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: SelmsColors.ink)),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: SelmsColors.border),
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: shape,
                ),
              ),
      ),
    );
  }
}

void empOpenUrl(String url) => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);

/// When and how a session happens (orientation / exit interview), with a
/// Join button when it has a link.
class EmpMeetingTile extends StatelessWidget {
  const EmpMeetingTile({super.key, required this.meeting, this.compact = false});

  final Map<String, dynamic> meeting;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final mode = meeting['mode'] as String? ?? 'in_person';
    final modeLabel = mode == 'online' ? 'Online' : 'In person';
    final url = meeting['meeting_url'] as String? ?? '';
    final location = meeting['location'] as String? ?? '';
    final start = meeting['start_time'] as String? ?? '';
    final duration = (meeting['duration_minutes'] as num?)?.toInt() ?? 30;

    return Container(
      width: double.infinity,
      margin: EdgeInsets.only(top: compact ? 0 : 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: SelmsColors.accentBg, borderRadius: BorderRadius.circular(10)),
      child: Row(
        children: [
          Container(
            width: 44,
            padding: const EdgeInsets.symmetric(vertical: 6),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8)),
            child: Builder(builder: (_) {
              final d = DateTime.tryParse(meeting['date'] as String? ?? '');
              return Column(
                children: [
                  Text(d == null ? '' : _months[d.month - 1].toUpperCase(),
                      style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700, color: SelmsColors.rose)),
                  Text(d == null ? '?' : '${d.day}',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: SelmsColors.ink)),
                ],
              );
            }),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${empDate(meeting['date'] as String?, weekday: true)} · ${empTimeRange(start, duration)}',
                    style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: SelmsColors.ink)),
                const SizedBox(height: 2),
                Text(location.isEmpty ? modeLabel : '$modeLabel · $location',
                    style: const TextStyle(fontSize: 11.5, color: SelmsColors.textSecondary)),
              ],
            ),
          ),
          if (url.isNotEmpty)
            ElevatedButton.icon(
              onPressed: () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
              icon: const Icon(Icons.videocam, size: 15),
              label: const Text('Join', style: TextStyle(fontSize: 12)),
              style: ElevatedButton.styleFrom(
                backgroundColor: EmpColors.success,
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(horizontal: 12),
              ),
            ),
        ],
      ),
    );
  }
}

/// Where a posted parcel has got to (remote hires).
/// One company item: its photo (or an icon), name, type · asset tag, an
/// optional status pill on the right and optional content underneath.
/// Used for "Collect IT equipment" and "Return your equipment".
class EmpEquipmentTile extends StatelessWidget {
  const EmpEquipmentTile({super.key, required this.item, required this.baseUrl, this.trailing, this.child});

  final Map<String, dynamic> item;
  final String baseUrl;
  final Widget? trailing;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final photo = item['photo_url'] as String?;
    final tag = item['asset_tag'] as String? ?? '';
    const placeholder = EmpIconBadge(Icons.devices_other_outlined, size: 48);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: SelmsColors.border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: photo != null && photo.isNotEmpty
                    ? Image.network('$baseUrl$photo',
                        width: 48, height: 48, fit: BoxFit.cover, errorBuilder: (_, _, _) => placeholder)
                    : placeholder,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item['name'] as String? ?? item['type'] as String? ?? 'Item',
                        style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: SelmsColors.textPrimary)),
                    Text([if (item['type'] != null) item['type'], if (tag.isNotEmpty) tag].join(' · '),
                        style: const TextStyle(fontSize: 11.5, color: SelmsColors.textSecondary)),
                  ],
                ),
              ),
              ?trailing,
            ],
          ),
          ?child,
        ],
      ),
    );
  }
}

class EmpShipmentTile extends StatelessWidget {
  const EmpShipmentTile({super.key, required this.shipment});

  final Map<String, dynamic> shipment;

  @override
  Widget build(BuildContext context) {
    final status = shipment['status'] as String? ?? '';
    const order = ['pending', 'order_created', 'dropped_off', 'delivered'];
    final reached = order.indexOf(status);
    final label = switch (status) {
      'pending' => 'IT is preparing your parcel',
      'order_created' => 'Booked with Pos Malaysia',
      'dropped_off' => 'On its way',
      'delivered' => 'Delivered',
      _ => 'Shipment update',
    };
    final ref = shipment['pos_reference'] as String? ?? '';
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: SelmsColors.accentBg, borderRadius: BorderRadius.circular(10)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.local_shipping_outlined, size: 16, color: SelmsColors.ink),
              const SizedBox(width: 8),
              Expanded(
                child: Text(label,
                    style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: SelmsColors.ink)),
              ),
              if (ref.isNotEmpty)
                Text('Ref $ref', style: const TextStyle(fontSize: 11, color: SelmsColors.textSecondary)),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: List.generate(order.length, (i) {
              return Expanded(
                child: Container(
                  height: 4,
                  margin: EdgeInsets.only(right: i == order.length - 1 ? 0 : 4),
                  decoration: BoxDecoration(
                    color: i <= reached ? SelmsColors.ink : Colors.white,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }
}

/// A vertical journey: done steps in green, the first open step
/// highlighted as "In progress", later steps greyed. [hintFor] explains
/// what finishes an open step; [extraFor] adds a meeting/parcel tile.
class EmpTimeline extends StatelessWidget {
  const EmpTimeline({
    super.key,
    required this.items,
    required this.hintFor,
    this.extraFor,
    this.accent = SelmsColors.ink,
    this.onTap,
  });

  final List<ChecklistItem> items;
  final String Function(ChecklistItem item) hintFor;
  final Widget? Function(ChecklistItem item)? extraFor;
  final Color accent;

  /// Opens a step's details (link, summary, tracking...). Null = not tappable.
  final void Function(ChecklistItem item)? onTap;

  @override
  Widget build(BuildContext context) {
    final currentIndex = items.indexWhere((i) => !i.done);
    return Column(
      children: List.generate(items.length, (i) {
        final item = items[i];
        final isCurrent = i == currentIndex;
        final isLast = i == items.length - 1;
        final extra = extraFor?.call(item);

        final dotColor = item.done ? EmpColors.success : (isCurrent ? accent : SelmsColors.border);
        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: 34,
                child: Column(
                  children: [
                    Container(
                      width: 26,
                      height: 26,
                      decoration: BoxDecoration(
                        color: item.done ? EmpColors.success : (isCurrent ? accent : Colors.white),
                        shape: BoxShape.circle,
                        border: Border.all(color: dotColor, width: 2),
                      ),
                      alignment: Alignment.center,
                      child: item.done
                          ? const Icon(Icons.check, size: 15, color: Colors.white)
                          : Text('${i + 1}',
                              style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w700,
                                  color: isCurrent ? Colors.white : SelmsColors.textMuted)),
                    ),
                    if (!isLast)
                      Expanded(
                        child: Container(
                          width: 2,
                          margin: const EdgeInsets.symmetric(vertical: 3),
                          color: item.done ? EmpColors.success.withValues(alpha: 0.5) : SelmsColors.border,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Padding(
                  padding: EdgeInsets.only(bottom: isLast ? 0 : 14),
                  child: Material(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    child: InkWell(
                    onTap: onTap == null ? null : () => onTap!(item),
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isCurrent ? accent.withValues(alpha: 0.55) : SelmsColors.border,
                        width: isCurrent ? 1.5 : 1,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(item.label,
                                  style: TextStyle(
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w600,
                                    color: item.done || isCurrent ? SelmsColors.textPrimary : SelmsColors.textSecondary,
                                  )),
                            ),
                            if (item.done)
                              const EmpPill('Done', bg: EmpColors.successBg, fg: EmpColors.success)
                            else if (isCurrent)
                              EmpPill('In progress', bg: accent.withValues(alpha: 0.1), fg: accent)
                            else
                              const EmpPill('Upcoming', bg: Color(0xFFF1F5F9), fg: SelmsColors.textMuted),
                            if (onTap != null) ...[
                              const SizedBox(width: 4),
                              const Icon(Icons.chevron_right, size: 18, color: SelmsColors.textMuted),
                            ],
                          ],
                        ),
                        if (item.done || hintFor(item).isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            item.done
                                ? (item.doneAt != null ? 'Completed ${empDate(item.doneAt)}' : 'Completed')
                                : hintFor(item),
                            style: const TextStyle(fontSize: 12, color: SelmsColors.textMuted, height: 1.35),
                          ),
                        ],
                        ?extra,
                      ],
                    ),
                  ),
                  ),
                  ),
                ),
              ),
            ],
          ),
        );
      }),
    );
  }
}
