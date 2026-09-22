// lib/widgets/form_fields.dart

import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import '../theme/selms_colors.dart';

/// Shared list so Add/Edit/Review all offer the same options.
const malaysianStates = [
  'Johor', 'Kedah', 'Kelantan', 'Melaka', 'Negeri Sembilan', 'Pahang',
  'Perak', 'Perlis', 'Pulau Pinang', 'Sabah', 'Sarawak', 'Selangor',
  'Terengganu', 'W.P. Kuala Lumpur', 'W.P. Labuan', 'W.P. Putrajaya',
];

InputDecoration selmsFieldDecoration({String? hint}) {
  return InputDecoration(
    isDense: true,
    hintText: hint,
    hintStyle: const TextStyle(fontSize: 12.5, color: SelmsColors.textMuted),
    filled: true,
    fillColor: SelmsColors.fieldBg,
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: const BorderSide(color: SelmsColors.border),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: const BorderSide(color: SelmsColors.border),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: const BorderSide(color: SelmsColors.ink, width: 1.4),
    ),
  );
}

class LabeledField extends StatelessWidget {
  const LabeledField({
    super.key,
    required this.label,
    required this.controller,
    this.hint,
    this.keyboardType,
    this.maxLines = 1,
    this.optional = false,
  });

  final String label;
  final TextEditingController controller;
  final String? hint;
  final TextInputType? keyboardType;
  final int maxLines;
  final bool optional;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _FieldLabel(label: label, optional: optional),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          keyboardType: keyboardType,
          maxLines: maxLines,
          style: const TextStyle(fontSize: 12.5, color: SelmsColors.textPrimary),
          decoration: selmsFieldDecoration(hint: hint),
        ),
      ],
    );
  }
}

/// Digits-only input that displays as "RM 2,000" — the RM prefix is fixed
/// and bold, commas are inserted automatically as the person types. The
/// controller's .text stays comma-formatted; strip commas before parsing.
class LabeledCurrencyField extends StatelessWidget {
  const LabeledCurrencyField({
    super.key,
    required this.label,
    required this.controller,
    this.optional = false,
  });

  final String label;
  final TextEditingController controller;
  final bool optional;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _FieldLabel(label: label, optional: optional),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          inputFormatters: [_ThousandsSeparatorFormatter()],
          style: const TextStyle(fontSize: 12.5, color: SelmsColors.textPrimary),
          decoration: selmsFieldDecoration().copyWith(
            prefixText: 'RM ',
            prefixStyle: const TextStyle(
                fontSize: 12.5, fontWeight: FontWeight.w700, color: SelmsColors.textPrimary),
          ),
        ),
      ],
    );
  }
}

/// Formats a plain numeric string as "2,000" — used both by the live
/// input formatter below and to pre-fill LabeledCurrencyField with an
/// already-formatted value (e.g. when Edit employee loads existing data).
String formatThousands(String digitsOnly) {
  final clean = digitsOnly.replaceAll(RegExp(r'[^0-9]'), '');
  if (clean.isEmpty) return '';
  final buffer = StringBuffer();
  for (var i = 0; i < clean.length; i++) {
    final posFromEnd = clean.length - i;
    buffer.write(clean[i]);
    if (posFromEnd > 1 && posFromEnd % 3 == 1) buffer.write(',');
  }
  return buffer.toString();
}

class _ThousandsSeparatorFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final formatted = formatThousands(newValue.text);
    if (formatted.isEmpty) return const TextEditingValue(text: '');
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

/// Same RM-prefix, auto-comma-formatting behavior as LabeledCurrencyField,
/// but rendered as a plain underlined line instead of a filled box —
/// "RM" shows before the person ever types anything, and typing "1000"
/// becomes "RM 1,000" live, same as before, just a lighter visual treatment.
class UnderlineCurrencyField extends StatelessWidget {
  const UnderlineCurrencyField({
    super.key,
    required this.label,
    required this.controller,
    this.optional = false,
  });

  final String label;
  final TextEditingController controller;
  final bool optional;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _FieldLabel(label: label, optional: optional),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          inputFormatters: [_ThousandsSeparatorFormatter()],
          style: const TextStyle(fontSize: 13, color: SelmsColors.textPrimary),
          decoration: InputDecoration(
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(vertical: 8),
            prefixText: 'RM ',
            prefixStyle: const TextStyle(
                fontSize: 13, fontWeight: FontWeight.w700, color: SelmsColors.textPrimary),
            border: const UnderlineInputBorder(borderSide: BorderSide(color: SelmsColors.textSecondary)),
            enabledBorder: const UnderlineInputBorder(borderSide: BorderSide(color: SelmsColors.textSecondary)),
            focusedBorder: const UnderlineInputBorder(borderSide: BorderSide(color: SelmsColors.ink, width: 1.5)),
          ),
        ),
      ],
    );
  }
}

class LabeledDropdown extends StatelessWidget {
  const LabeledDropdown({
    super.key,
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
    this.optional = false,
  });

  final String label;
  final String? value;
  final List<String> options;
  final ValueChanged<String?> onChanged;
  final bool optional;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _FieldLabel(label: label, optional: optional),
        const SizedBox(height: 6),
        DropdownButtonFormField<String>(
          initialValue: value,
          isExpanded: true,
          hint: const Text('Select', style: TextStyle(fontSize: 12.5, color: SelmsColors.textMuted)),
          style: const TextStyle(fontSize: 12.5, color: SelmsColors.textPrimary),
          items: options.map((o) => DropdownMenuItem(value: o, child: Text(o))).toList(),
          onChanged: onChanged,
          decoration: selmsFieldDecoration(),
        ),
      ],
    );
  }
}

class LabeledDateField extends StatelessWidget {
  const LabeledDateField({
    super.key,
    required this.label,
    required this.value,
    required this.onPick,
    this.optional = false,
  });

  final String label;
  final DateTime? value;
  final ValueChanged<DateTime> onPick;
  final bool optional;

  String _fmt(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _FieldLabel(label: label, optional: optional),
        const SizedBox(height: 6),
        InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () async {
            final now = DateTime.now();
            final picked = await showDatePicker(
              context: context,
              initialDate: value ?? now,
              firstDate: DateTime(1950),
              lastDate: DateTime(now.year + 1),
            );
            if (picked != null) onPick(picked);
          },
          child: InputDecorator(
            decoration: selmsFieldDecoration(),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  value == null ? 'dd/mm/yyyy' : _fmt(value!),
                  style: TextStyle(
                    fontSize: 12.5,
                    color: value == null ? SelmsColors.textMuted : SelmsColors.textPrimary,
                  ),
                ),
                const Icon(Icons.calendar_today_outlined, size: 14, color: SelmsColors.textMuted),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel({required this.label, required this.optional});
  final String label;
  final bool optional;

  @override
  Widget build(BuildContext context) {
    return RichText(
      text: TextSpan(
        text: label,
        style: const TextStyle(
            fontSize: 12, fontWeight: FontWeight.w500, color: SelmsColors.textSecondary),
        children: optional
            ? const [
                TextSpan(
                  text: '  (optional)',
                  style: TextStyle(fontWeight: FontWeight.w400, color: SelmsColors.textMuted),
                ),
              ]
            : [],
      ),
    );
  }
}

/// Circular photo preview that, when tapped, lets HR pick a photo and then
/// drag/zoom it inside a circular crop so what they see is what gets saved.
class ProfilePhotoField extends StatelessWidget {
  const ProfilePhotoField({
    super.key,
    required this.imageBytes,
    required this.fallbackInitials,
    required this.onChanged,
    this.existingImageUrl,
  });

  /// Bytes of a newly-picked photo. Takes priority over [existingImageUrl].
  final Uint8List? imageBytes;

  /// Full URL of the photo already saved on the server (Edit employee only).
  /// Shown until the person picks a replacement.
  final String? existingImageUrl;

  /// Shown inside the circle when there's neither new bytes nor an existing photo.
  final String fallbackInitials;

  /// Called with the cropped image bytes, or null when removed.
  final ValueChanged<Uint8List?> onChanged;

  bool get _hasPhoto => imageBytes != null || (existingImageUrl != null && existingImageUrl!.isNotEmpty);

  Future<void> _pickAndAdjust(BuildContext context) async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 90);
    if (picked == null) return;
    final rawBytes = await picked.readAsBytes();
    if (!context.mounted) return;
    final adjusted = await showDialog<Uint8List>(
      context: context,
      builder: (_) => PhotoAdjustDialog(imageBytes: rawBytes),
    );
    if (adjusted != null) onChanged(adjusted);
  }

  /// Tapping the circle views the current photo if one's set, otherwise
  /// it's the same as pressing "Upload photo" — no separate icon needed.
  void _onCircleTap(BuildContext context) {
    if (imageBytes != null) {
      showDialog<void>(context: context, builder: (_) => PhotoViewDialog(imageBytes: imageBytes!));
    } else if (existingImageUrl != null && existingImageUrl!.isNotEmpty) {
      showDialog<void>(
          context: context, builder: (_) => PhotoViewDialog(networkImageUrl: existingImageUrl));
    } else {
      _pickAndAdjust(context);
    }
  }

  Widget _circleContent() {
    if (imageBytes != null) {
      return Image.memory(imageBytes!, fit: BoxFit.cover, width: 64, height: 64);
    }
    if (existingImageUrl != null && existingImageUrl!.isNotEmpty) {
      return Image.network(existingImageUrl!, fit: BoxFit.cover, width: 64, height: 64);
    }
    return Text(
      fallbackInitials.isEmpty ? '?' : fallbackInitials,
      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: SelmsColors.ink),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        InkWell(
          onTap: () => _onCircleTap(context),
          borderRadius: BorderRadius.circular(32),
          child: Container(
            width: 64,
            height: 64,
            clipBehavior: Clip.hardEdge,
            decoration: BoxDecoration(
              color: SelmsColors.accentBg,
              shape: BoxShape.circle,
              border: !_hasPhoto ? Border.all(color: SelmsColors.border) : null,
            ),
            alignment: Alignment.center,
            child: _circleContent(),
          ),
        ),
        const SizedBox(width: 16),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            RichText(
              text: TextSpan(
                text: 'Profile photo',
                style: const TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w500, color: SelmsColors.textSecondary),
                children: const [
                  TextSpan(
                    text: '  (optional)',
                    style: TextStyle(fontWeight: FontWeight.w400, color: SelmsColors.textMuted),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed: () => _pickAndAdjust(context),
                  icon: const Icon(Icons.upload_outlined, size: 14, color: SelmsColors.ink),
                  label: Text(_hasPhoto ? 'Replace photo' : 'Upload photo',
                      style: const TextStyle(fontSize: 11.5, color: SelmsColors.ink)),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: SelmsColors.border),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                ),
                if (_hasPhoto) ...[
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: () => onChanged(null),
                    child: const Text('Remove',
                        style: TextStyle(fontSize: 11.5, color: SelmsColors.rose)),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 4),
            Text(_hasPhoto ? 'JPG or PNG, up to 5MB. Tap the circle to view.' : 'JPG or PNG, up to 5MB.',
                style: const TextStyle(fontSize: 10, color: SelmsColors.textMuted)),
          ],
        ),
      ],
    );
  }
}

/// Read-only preview of the currently saved photo, shown the way it'll
/// actually appear as an avatar. Opened by tapping the circle. Pass either
/// [imageBytes] (a newly-picked photo) or [networkImageUrl] (one already
/// saved on the server), not both.
class PhotoViewDialog extends StatelessWidget {
  const PhotoViewDialog({super.key, this.imageBytes, this.networkImageUrl});

  final Uint8List? imageBytes;
  final String? networkImageUrl;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Profile photo',
                style: TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w600, color: SelmsColors.textPrimary)),
            const SizedBox(height: 16),
            ClipOval(
              child: imageBytes != null
                  ? Image.memory(imageBytes!, fit: BoxFit.cover, width: 180, height: 180)
                  : Image.network(networkImageUrl!, fit: BoxFit.cover, width: 180, height: 180),
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () => Navigator.of(context).pop(),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: SelmsColors.border),
                  padding: const EdgeInsets.symmetric(vertical: 11),
                ),
                child: const Text('Close', style: TextStyle(color: SelmsColors.textSecondary)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Same tap-to-pick, crop, and view behavior as ProfilePhotoField, but
/// displayed as a rounded square rather than a circle — a laptop or
/// monitor doesn't read naturally as a round avatar the way a face does.
/// Reuses PhotoAdjustDialog as-is: it already captures a square PNG
/// internally, only ProfilePhotoField's own preview was clipping it into
/// a circle on display.
class SquarePhotoField extends StatelessWidget {
  const SquarePhotoField({
    super.key,
    required this.imageBytes,
    required this.onChanged,
    this.existingImageUrl,
    this.icon = Icons.inventory_2_outlined,
  });

  final Uint8List? imageBytes;
  final String? existingImageUrl;
  final ValueChanged<Uint8List?> onChanged;
  final IconData icon;

  bool get _hasPhoto => imageBytes != null || (existingImageUrl != null && existingImageUrl!.isNotEmpty);

  Future<void> _pickAndAdjust(BuildContext context) async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 90);
    if (picked == null) return;
    final rawBytes = await picked.readAsBytes();
    if (!context.mounted) return;
    final adjusted = await showDialog<Uint8List>(
      context: context,
      builder: (_) => PhotoAdjustDialog(imageBytes: rawBytes),
    );
    if (adjusted != null) onChanged(adjusted);
  }

  void _onBoxTap(BuildContext context) {
    if (imageBytes != null) {
      showDialog<void>(context: context, builder: (_) => SquarePhotoViewDialog(imageBytes: imageBytes!));
    } else if (existingImageUrl != null && existingImageUrl!.isNotEmpty) {
      showDialog<void>(
          context: context, builder: (_) => SquarePhotoViewDialog(networkImageUrl: existingImageUrl));
    } else {
      _pickAndAdjust(context);
    }
  }

  Widget _boxContent() {
    if (imageBytes != null) {
      return Image.memory(imageBytes!, fit: BoxFit.cover, width: 64, height: 64);
    }
    if (existingImageUrl != null && existingImageUrl!.isNotEmpty) {
      return Image.network(existingImageUrl!, fit: BoxFit.cover, width: 64, height: 64);
    }
    return Icon(icon, size: 24, color: SelmsColors.textMuted);
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        InkWell(
          onTap: () => _onBoxTap(context),
          borderRadius: BorderRadius.circular(10),
          child: Container(
            width: 64,
            height: 64,
            clipBehavior: Clip.hardEdge,
            decoration: BoxDecoration(
              color: const Color(0xFFF9FAFB),
              borderRadius: BorderRadius.circular(10),
              border: !_hasPhoto
                  ? Border.all(color: SelmsColors.border, style: BorderStyle.solid)
                  : Border.all(color: SelmsColors.border),
            ),
            alignment: Alignment.center,
            child: _boxContent(),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              RichText(
                text: const TextSpan(
                  text: 'Equipment photo',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: SelmsColors.textSecondary),
                  children: [
                    TextSpan(
                        text: '  (optional)',
                        style: TextStyle(fontWeight: FontWeight.w400, color: SelmsColors.textMuted)),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _hasPhoto ? 'Tap the box to view or replace' : 'QR code is generated automatically once saved',
                style: const TextStyle(fontSize: 9, color: SelmsColors.textMuted),
              ),
              if (_hasPhoto) ...[
                const SizedBox(height: 4),
                Row(
                  children: [
                    InkWell(
                      onTap: () => _pickAndAdjust(context),
                      child: const Text('Replace',
                          style: TextStyle(fontSize: 10.5, color: SelmsColors.ink, fontWeight: FontWeight.w500)),
                    ),
                    const SizedBox(width: 12),
                    InkWell(
                      onTap: () => onChanged(null),
                      child: const Text('Remove', style: TextStyle(fontSize: 10.5, color: SelmsColors.rose)),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// Read-only preview of a photo shown in a square, the same idea as
/// PhotoViewDialog but without forcing it into a circle.
class SquarePhotoViewDialog extends StatelessWidget {
  const SquarePhotoViewDialog({super.key, this.imageBytes, this.networkImageUrl});

  final Uint8List? imageBytes;
  final String? networkImageUrl;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Equipment photo',
                style: TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w600, color: SelmsColors.textPrimary)),
            const SizedBox(height: 16),
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: imageBytes != null
                  ? Image.memory(imageBytes!, fit: BoxFit.cover, width: 220, height: 220)
                  : Image.network(networkImageUrl!, fit: BoxFit.cover, width: 220, height: 220),
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () => Navigator.of(context).pop(),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: SelmsColors.border),
                  padding: const EdgeInsets.symmetric(vertical: 11),
                ),
                child: const Text('Close', style: TextStyle(color: SelmsColors.textSecondary)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Square crop dialog. Opens showing the whole picked photo — nothing is
/// cropped until the person actually zooms or drags. Renders the visible
/// square straight to PNG bytes on confirm; the avatar circles elsewhere
/// in the app clip that square into a circle when they display it.
class PhotoAdjustDialog extends StatefulWidget {
  const PhotoAdjustDialog({super.key, required this.imageBytes});

  /// The raw, un-cropped bytes straight from the image picker.
  final Uint8List imageBytes;

  @override
  State<PhotoAdjustDialog> createState() => _PhotoAdjustDialogState();
}

class _PhotoAdjustDialogState extends State<PhotoAdjustDialog> {
  static const double _canvasSize = 240;

  final GlobalKey _boundaryKey = GlobalKey();
  Offset _offset = Offset.zero;
  double _scale = 1.0;
  Offset _dragStartOffset = Offset.zero;
  Offset _dragStartFocal = Offset.zero;
  double _scaleStart = 1.0;
  bool _rendering = false;

  void _onScaleStart(ScaleStartDetails d) {
    _dragStartOffset = _offset;
    _dragStartFocal = d.focalPoint;
    _scaleStart = _scale;
  }

  void _onScaleUpdate(ScaleUpdateDetails d) {
    setState(() {
      _offset = _dragStartOffset + (d.focalPoint - _dragStartFocal);
      // 1.0 = the whole photo fits inside the square, untouched. Zooming
      // in past that is the only thing that actually crops anything.
      _scale = (_scaleStart * d.scale).clamp(1.0, 4.0);
    });
  }

  Future<void> _confirm() async {
    setState(() => _rendering = true);
    try {
      // A short delay lets the final frame (post drag/zoom) actually paint
      // before we capture it — toImage() otherwise sometimes grabs a stale
      // frame on the very last gesture update.
      await Future.delayed(const Duration(milliseconds: 16));
      final boundary =
          _boundaryKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 3);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      final bytes = byteData!.buffer.asUint8List();
      if (mounted) Navigator.of(context).pop(bytes);
    } finally {
      if (mounted) setState(() => _rendering = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const Text('Adjust photo',
                style: TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w600, color: SelmsColors.textPrimary)),
            const SizedBox(height: 4),
            const Text('Drag to reposition, pinch or use the slider to zoom.',
                style: TextStyle(fontSize: 11.5, color: SelmsColors.textMuted),
                textAlign: TextAlign.center),
            const SizedBox(height: 18),
            // Square crop area — the final saved photo is square, and gets
            // clipped into a circle wherever the app displays it as an avatar.
            GestureDetector(
              onScaleStart: _onScaleStart,
              onScaleUpdate: _onScaleUpdate,
              child: RepaintBoundary(
                key: _boundaryKey,
                child: ClipRect(
                  child: Container(
                    width: _canvasSize,
                    height: _canvasSize,
                    color: SelmsColors.fieldBg,
                    child: Center(
                      child: Transform.translate(
                        offset: _offset,
                        child: Transform.scale(
                          scale: _scale,
                          // BoxFit.contain — the whole photo is visible at
                          // scale 1.0, nothing pre-cropped before editing.
                          child: Image.memory(
                            widget.imageBytes,
                            fit: BoxFit.contain,
                            width: _canvasSize,
                            height: _canvasSize,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                const Icon(Icons.zoom_out, size: 16, color: SelmsColors.textMuted),
                Expanded(
                  child: Slider(
                    value: _scale,
                    min: 1.0,
                    max: 4.0,
                    activeColor: SelmsColors.ink,
                    onChanged: (v) => setState(() => _scale = v),
                  ),
                ),
                const Icon(Icons.zoom_in, size: 16, color: SelmsColors.textMuted),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                OutlinedButton(
                  onPressed: _rendering ? null : () => Navigator.of(context).pop(),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: SelmsColors.border),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
                  ),
                  child: const Text('Cancel', style: TextStyle(color: SelmsColors.textSecondary)),
                ),
                const SizedBox(width: 10),
                ElevatedButton(
                  onPressed: _rendering ? null : _confirm,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: SelmsColors.ink,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
                  ),
                  child: _rendering
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('Use photo', style: TextStyle(fontWeight: FontWeight.w500)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class SectionHeader extends StatelessWidget {
  const SectionHeader({super.key, required this.title, required this.subtitle});
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: const TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w600, color: SelmsColors.textPrimary)),
          const SizedBox(height: 2),
          Text(subtitle, style: const TextStyle(fontSize: 12, color: SelmsColors.textMuted)),
        ],
      ),
    );
  }
}
