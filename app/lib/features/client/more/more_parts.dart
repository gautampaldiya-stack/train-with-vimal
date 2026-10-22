import 'package:flutter/material.dart';

import '../../../core/icons/app_icons.dart';
import '../../../core/theme/theme.dart';
import '../../../core/widgets/hover.dart';
import '../home/home_parts.dart';
import '../../../core/widgets/tooltip.dart';

/// Small pieces of the More board (`mo-*`, `fd-mi`, `fd-kv` classes), shared by the page and its sheets.

AppIconData moIcon(String key) => switch (key) {
      'form' => AppIcons.clipboard,
      'dumb' => AppIcons.dumbbell,
      'cal' => AppIcons.calendarAlt,
      'water' => AppIcons.water,
      'food' => AppIcons.food,
      'pill' => AppIcons.pill,
      'steps' => AppIcons.steps,
      'moon' => AppIcons.moon,
      'user' => AppIcons.user,
      'scale' => AppIcons.scale,
      'star' => AppIcons.star,
      'target' => AppIcons.target,
      'book' => AppIcons.library,
      _ => AppIcons.bell,
    };

ChTone moTone(String c) => switch (c) {
      'blue' => ChTone.blue,
      'green' => ChTone.green,
      'amber' => ChTone.amber,
      'purple' => ChTone.purple,
      _ => ChTone.gray,
    };

/// A notification's look by its event (board rows: form amber, session blue, best green, plan blue …).
(String, String) noticeLook(String event) => switch (event) {
      'checkin_reviewed' || 'checkin_reminder' || 'checkin_due' || 'form_request' => ('form', 'amber'),
      'session_booked' || 'session_moved' || 'session_cancelled' || 'session_reminder' => ('cal', 'blue'),
      'personal_best' || 'milestone' => ('star', 'green'),
      'plan_assigned' || 'plan_updated' || 'workout_reminder' => ('dumb', 'blue'),
      'water_reminder' => ('water', 'blue'),
      'supplement_reminder' => ('pill', 'purple'),
      'habit_reminder' => ('steps', 'green'),
      'meal_plan_assigned' || 'meal_plan_updated' || 'meal_reminder' => ('food', 'green'),
      'trainer_changed' || 'client_assigned' => ('user', 'gray'),
      'content_shared' => ('book', 'blue'),
      _ => ('bell', 'gray'),
    };

/// Where a notification's button goes, and its label ("Open check-ins").
(String, String)? noticeLink(String event, String route) {
  final r = route.startsWith('/') ? route : switch (noticeLook(event).$1) {
    'form' => '/checkins',
    'cal' || 'dumb' => '/train',
    'star' => '/progress',
    'water' || 'pill' || 'steps' => '/habits',
    'food' => '/food',
    'book' => '/library',
    _ => '',
  };
  if (r.isEmpty) return null;
  final label = switch (r.split('/').where((p) => p.isNotEmpty).firstOrNull ?? '') {
    'checkins' => 'Open check-ins',
    'train' || 'sessions' => 'Open training',
    'progress' => 'See progress',
    'habits' => 'Open habits',
    'food' => 'Open meal plan',
    'library' => 'Open library',
    _ => 'Open',
  };
  return (r.startsWith('/sessions') ? '/train' : r, label);
}

/// `ch-ic` in a chosen size (30 in coach rows, 32 in lists, 34 in menus).
class MoIc extends StatelessWidget {
  const MoIc(this.icon, {super.key, this.tone = ChTone.gray, this.size = 34, this.radius = 10});
  final AppIconData icon;
  final ChTone tone;
  final double size, radius;
  @override
  Widget build(BuildContext context) {
    final (bg, fg) = chTone(tone);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(radius)),
      child: AppIcon(icon, size: size <= 30 ? 15 : (size <= 32 ? 16 : 17), color: fg),
    );
  }
}

/// `mo-av`: the client's own initials (warm orange).
class MoAvatar extends StatelessWidget {
  const MoAvatar(this.initials, {super.key, this.size = 48});
  final String initials;
  final double size;
  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: const BoxDecoration(color: AppColors.moAvBg, shape: BoxShape.circle),
        child: Text(initials, style: AppText.s(size > 50 ? 18 : 16, W.w8, color: AppColors.moAvText)),
      );
}

/// `ch-sec sm`: "YOUR PLAN", "ACCOUNT".
Widget moSec(String t) => Padding(
      padding: const EdgeInsets.only(top: 4, left: 2),
      child: Text(t.toUpperCase(), style: AppText.s(12, W.w8, color: AppColors.muted, ls: 0.48)),
    );

/// `fl-mh mo-mh`: the small heading inside a web list card.
Widget moMh(String t) => Padding(
      padding: const EdgeInsets.fromLTRB(0, 10, 0, 2),
      child: Text(t.toUpperCase(), style: AppText.s(11, W.w7, color: AppColors.muted, ls: 0.55)),
    );

/// `fd-mi`: icon tile, bold title, grey line, optional pill, chevron.
class MoMenuRow extends StatelessWidget {
  const MoMenuRow({super.key, required this.icon, required this.title, required this.sub, this.pill, this.first = false, required this.onTap, this.pillTone = ChTone.blue});
  final AppIconData icon;
  final String title, sub; // empty sub = title only
  final String? pill;
  final ChTone pillTone;
  final bool first;
  final VoidCallback? onTap; // null = an info row (no chevron, no hover)
  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: title,
        child: Hover(
          onTap: onTap,
          builder: (_, h, _) => Container(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 2),
            decoration: BoxDecoration(border: first ? null : const Border(top: BorderSide(color: AppColors.line))),
            child: Row(spacing: 12, children: [
              MoIc(icon),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 1, children: [
                  Text(title, style: AppText.s(14, W.w7, color: h && onTap != null ? AppColors.accentText : AppColors.text)),
                  if (sub.isNotEmpty) CutText(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(12.5, W.w4, color: AppColors.muted)),
                ]),
              ),
              if (pill != null) MoPill(pill!, tone: pillTone),
              if (onTap != null) const AppIcon(AppIcons.chevronRight, size: 16, color: AppColors.muted),
            ]),
          ),
        ),
      );
}

/// `fd-pill`: "Due Sun", "3 new".
class MoPill extends StatelessWidget {
  const MoPill(this.label, {super.key, this.tone = ChTone.blue});
  final String label;
  final ChTone tone;
  @override
  Widget build(BuildContext context) {
    final (bg, fg) = switch (tone) {
      ChTone.amber => (AppColors.amberBg, AppColors.amberText),
      ChTone.green => (AppColors.okBg, AppColors.okText),
      ChTone.gray => (AppColors.sub, AppColors.text2),
      _ => (AppColors.infoBg, AppColors.infoText),
    };
    return Container(
      height: 22,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      margin: const EdgeInsets.only(left: 4),
      alignment: Alignment.center,
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(99)),
      child: Text(label, style: AppText.s(11.5, W.w7, color: fg)),
    );
  }
}

/// `mo-kvs` / `fd-kv`: label left, bold value right, a line between rows.
Widget moKvs(List<(String, String)> rows, {double size = 13, double pad = 9}) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (final (i, (l, v)) in rows.indexed)
        Container(
          padding: EdgeInsets.symmetric(vertical: pad),
          decoration: BoxDecoration(border: i == 0 ? null : const Border(top: BorderSide(color: AppColors.line))),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 12, children: [
            Text(l, style: AppText.s(size, W.w6, color: AppColors.muted)),
            Expanded(child: Text(v, textAlign: TextAlign.right, style: AppText.s(size, W.w7))),
          ]),
        ),
    ]);

/// `fd-cap`: grey note under a list.
Widget moCap(String t) => Text(t, style: AppText.s(12.5, W.w4, color: AppColors.muted, h: 1.45));

/// `mo-sw`: 38×22 switch.
class MoSwitch extends StatelessWidget {
  const MoSwitch(this.on, {super.key});
  final bool on;
  @override
  Widget build(BuildContext context) => AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 38,
        height: 22,
        decoration: BoxDecoration(color: on ? AppColors.accent : AppColors.moSwOff, borderRadius: BorderRadius.circular(99)),
        child: AnimatedAlign(
          duration: const Duration(milliseconds: 150),
          alignment: on ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            width: 16,
            height: 16,
            margin: const EdgeInsets.all(3),
            decoration: const BoxDecoration(color: AppColors.white, shape: BoxShape.circle, boxShadow: [BoxShadow(color: Color(0x33000000), blurRadius: 2, offset: Offset(0, 1))]),
          ),
        ),
      );
}

/// `mo-tr`: a switch row (icon optional), the whole row toggles.
class MoToggleRow extends StatelessWidget {
  const MoToggleRow({super.key, this.icon, this.tone = ChTone.gray, required this.title, required this.sub, required this.on, required this.onTap, this.first = false, this.line = true});
  final AppIconData? icon;
  final ChTone tone;
  final String title, sub;
  final bool on, first, line;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Semantics(
        toggled: on,
        label: title,
        child: Hover(
          onTap: onTap,
          builder: (_, h, _) => Container(
            padding: EdgeInsets.symmetric(vertical: line ? 9 : 0),
            decoration: BoxDecoration(border: first || !line ? null : const Border(top: BorderSide(color: AppColors.line))),
            child: Row(spacing: 10, children: [
              if (icon != null) MoIc(icon!, tone: tone, size: 30, radius: 9),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 1, children: [
                  Text(title, style: AppText.s(13.5, W.w7)),
                  Text(sub, style: AppText.s(12, W.w4, color: AppColors.muted)),
                ]),
              ),
              MoSwitch(on),
            ]),
          ),
        ),
      );
}

/// `mo-seg`: segmented choice (kg / lb).
class MoSeg extends StatelessWidget {
  const MoSeg({super.key, required this.options, required this.index, required this.onPick});
  final List<String> options;
  final int index;
  final ValueChanged<int> onPick;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(color: AppColors.sub, borderRadius: BorderRadius.circular(10)),
        child: Row(spacing: 3, children: [
          for (final (i, o) in options.indexed)
            Expanded(
              child: Semantics(
                selected: i == index,
                button: true,
                child: Hover(
                  onTap: () => onPick(i),
                  builder: (_, h, _) => Container(
                    height: 32,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: i == index ? AppColors.white : null,
                      borderRadius: BorderRadius.circular(8),
                      boxShadow: i == index ? const [BoxShadow(color: AppColors.shadowSoft, blurRadius: 2, offset: Offset(0, 1)), BoxShadow(color: AppColors.line, spreadRadius: 1)] : null,
                    ),
                    child: Text(o, style: AppText.s(13, W.w6, color: i == index || h ? AppColors.text : AppColors.text2)),
                  ),
                ),
              ),
            ),
        ]),
      );
}

/// `mo-fl` / `mo-sug`: round chips (black when on, or blue for `blue`).
class MoChips extends StatelessWidget {
  const MoChips({super.key, required this.items, required this.on, required this.onPick, this.blue = false, this.height = 30, this.scroll = false});
  final List<String> items;
  final String? on;
  final ValueChanged<String> onPick;
  final bool blue;
  final double height;

  /// One sideways-scrolling row (phone filters) instead of wrapping lines.
  final bool scroll;
  @override
  Widget build(BuildContext context) {
    final chips = [
        for (final t in items)
          Semantics(
            selected: t == on,
            button: true,
            child: Hover(
              onTap: () => onPick(t),
              builder: (_, h, _) {
                final sel = t == on;
                final (bg, bd, fg) = !sel
                    ? (h ? AppColors.outlineHover : AppColors.white, AppColors.line, AppColors.text2)
                    : blue
                        ? (AppColors.accentSoft, AppColors.accent, AppColors.accentText)
                        : (AppColors.text, AppColors.text, AppColors.white);
                return Container(
                  height: height,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(99), border: Border.all(color: bd)),
                  child: Center(widthFactor: 1, child: Text(t, style: AppText.s(12.5, W.w6, color: fg))),
                );
              },
            ),
          ),
      ];
    if (!scroll) return Wrap(spacing: 6, runSpacing: 6, children: chips);
    return SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(spacing: 6, children: chips));
  }
}

/// `mo-tabs` / `mo-wt`: the grey tab bar (Overview · Notifications · My activity, All · Unread).
/// As wide as its labels at every width by default (Gautam 2026-10-16).
class MoTabs extends StatelessWidget {
  const MoTabs({super.key, required this.labels, required this.index, required this.onPick, this.fit = true});
  final List<String> labels;
  final int index;
  final ValueChanged<int> onPick;
  final bool fit;
  @override
  Widget build(BuildContext context) {
    Widget tab(int i) => Semantics(
          selected: i == index,
          button: true,
          child: Hover(
            onTap: () => onPick(i),
            builder: (_, h, _) => Container(
              height: 32,
              padding: EdgeInsets.symmetric(horizontal: fit ? 16 : 6),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: i == index ? AppColors.white : null,
                borderRadius: BorderRadius.circular(6),
                boxShadow: i == index ? const [BoxShadow(color: AppColors.shadowSoft, blurRadius: 2, offset: Offset(0, 1)), BoxShadow(color: AppColors.line, spreadRadius: 1)] : null,
              ),
              child: Text(labels[i], maxLines: 1, style: AppText.s(13, W.w6, color: i == index || h ? AppColors.text : AppColors.text2)),
            ),
          ),
        );
    final track = Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: AppColors.sub, borderRadius: BorderRadius.circular(8)),
      child: Row(mainAxisSize: fit ? MainAxisSize.min : MainAxisSize.max, spacing: 4, children: [
        for (var i = 0; i < labels.length; i++) fit ? tab(i) : Expanded(child: tab(i)),
      ]),
    );
    return fit ? Align(alignment: Alignment.centerLeft, widthFactor: 1, child: track) : track;
  }
}

/// `mo-empty`: icon, bold line, grey line.
Widget moEmpty(String title, String sub, {AppIconData icon = AppIcons.bell}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 12),
      child: Column(spacing: 4, children: [
        MoIc(icon, size: 40, radius: 12),
        const SizedBox(height: 4),
        Text(title, style: AppText.s(14.5, W.w7)),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 280),
          child: Text(sub, textAlign: TextAlign.center, style: AppText.s(12.5, W.w4, color: AppColors.muted)),
        ),
      ]),
    );
