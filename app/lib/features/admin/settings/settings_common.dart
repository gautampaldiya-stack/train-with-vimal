import 'package:flutter/material.dart';

import '../../../core/icons/app_icons.dart';
import '../../../core/theme/theme.dart';
import '../../../core/widgets/card.dart';
import '../../../core/widgets/hover.dart';

/// Shared parts of Admin → Settings (boards `Settings` + `SettingsMobile`, D-53).

const stMonths = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/// Card padding: 18 on wide screens (`.hb-eb`), 14 on a phone.
double stPad(double cw) => cw < 600 ? 14 : 18;

/// `.card.hb-ed`: a card with the `.hb-eh` head, a body and an optional `.em-foot` footer.
class StEditCard extends StatelessWidget {
  const StEditCard({super.key, required this.cw, required this.icon, required this.tone, required this.title, required this.sub, required this.body, this.foot});
  final double cw;
  final AppIconData icon;
  final int tone; // `.hb-ic.t1…t4`
  final String title, sub;
  final Widget body;
  final Widget? foot;

  @override
  Widget build(BuildContext context) {
    final p = stPad(cw);
    final (bg, fg) = AppColors.hbTones[tone];
    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(
          padding: EdgeInsets.symmetric(horizontal: p, vertical: cw < 600 ? 14 : 16),
          decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.line))),
          child: Row(spacing: 12, children: [
            IconTile(icon, size: 44, radius: 11, iconSize: 22, bg: bg, fg: fg),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 2, children: [
                Text(title, style: AppText.h3),
                Text(sub, style: AppText.s(12.5, W.w6, color: AppColors.muted, h: 1.4)),
              ]),
            ),
          ]),
        ),
        Padding(padding: EdgeInsets.all(p), child: body),
        if (foot != null)
          Container(
            padding: EdgeInsets.symmetric(horizontal: p, vertical: 12),
            decoration: const BoxDecoration(
              color: AppColors.hbSaveBg,
              border: Border(top: BorderSide(color: AppColors.line)),
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(AppRadius.card)),
            ),
            child: foot,
          ),
      ]),
    );
  }
}

/// `.dr-fnote`: grey note in a card footer.
Widget stFootNote(String text) => Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(12.5, W.w6, color: AppColors.muted));

/// `.st-row`: words on the left, the control on the right; on a phone the control goes under the words.
class StRow extends StatelessWidget {
  const StRow({super.key, required this.title, required this.sub, required this.control, required this.phone, this.first = false, this.stretch = false});
  final String title, sub;
  final Widget control;
  final bool phone, first;

  /// Phone: the control takes the full width (selects), instead of its own width (tabs).
  final bool stretch;

  @override
  Widget build(BuildContext context) {
    final words = Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 2, children: [
      Text(title, style: AppText.s(13.5, W.w7)),
      Text(sub, style: AppText.s(12, W.w5, color: AppColors.muted, h: 1.4)),
    ]);
    return Container(
      padding: EdgeInsets.only(top: first ? 0 : 14),
      decoration: first ? null : const BoxDecoration(border: Border(top: BorderSide(color: AppColors.line))),
      child: phone
          ? Column(crossAxisAlignment: stretch ? CrossAxisAlignment.stretch : CrossAxisAlignment.start, spacing: 8, children: [words, control])
          : Row(spacing: 16, children: [Expanded(child: words), control]),
    );
  }
}

/// `.fm-au`: a link row with a small icon, title, sub line and a chevron.
class StLinkRow extends StatelessWidget {
  const StLinkRow({super.key, required this.icon, required this.title, required this.sub, required this.onTap});
  final AppIconData icon;
  final String title, sub;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Hover(
        onTap: onTap,
        builder: (_, h, _) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(borderRadius: AppRadius.all(8), border: Border.all(color: h ? AppColors.line2 : AppColors.line)),
          child: Row(spacing: 8, children: [
            AppIcon(icon, size: 15, color: AppColors.fmBolt),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 1, children: [
                Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(13, W.w6, color: h ? AppColors.accentText : AppColors.text)),
                Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(11.5, W.w6, color: AppColors.muted)),
              ]),
            ),
            const AppIcon(AppIcons.chevronRight, size: 15, color: AppColors.muted),
          ]),
        ),
      );
}

/// `.em-box`: a square tick box; `locked` = the dimmed box that cannot change (`.em-box.lk`).
class StBox extends StatelessWidget {
  const StBox({super.key, required this.on, this.locked = false});
  final bool on, locked;
  @override
  Widget build(BuildContext context) => Opacity(
        opacity: locked ? .5 : 1,
        child: Container(
          width: 20,
          height: 20,
          decoration: BoxDecoration(
            color: on ? AppColors.accent : AppColors.card,
            borderRadius: AppRadius.all(6),
            border: Border.all(color: on ? AppColors.accent : AppColors.line2, width: 1.5),
          ),
          child: on ? const Center(child: AppIcon(AppIcons.check, size: 13, color: AppColors.white)) : null,
        ),
      );
}

/// Parses "#2563EB" into a colour (null when it is not a 6-digit hex).
Color? stHex(String? v) {
  final s = (v ?? '').replaceAll('#', '').trim();
  if (!RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(s)) return null;
  return Color(int.parse('FF$s', radix: 16));
}

String stHexOf(Color c) => '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

/// Initials of the gym name for the logo box ("Train With Vimal" → "TV": first and last word).
String stInitials(String name) {
  final w = name.trim().split(RegExp(r'\s+')).where((x) => x.isNotEmpty).toList();
  if (w.isEmpty) return 'TV';
  if (w.length == 1) return w.first.substring(0, w.first.length.clamp(0, 2)).toUpperCase();
  return (w.first[0] + w.last[0]).toUpperCase();
}
