import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../app/services.dart';
import '../../../core/api/api_error.dart';
import '../../../core/icons/app_icons.dart';
import '../../../core/theme/theme.dart';
import '../../../core/widgets/badge.dart';
import '../../../core/widgets/button.dart';
import '../../../core/widgets/card.dart';
import '../../../core/widgets/hover.dart';
import '../../../core/widgets/input.dart';
import '../../../core/widgets/media.dart';
import '../../../core/widgets/overlays.dart';
import '../../../core/widgets/responsive.dart';
import '../../../core/widgets/tabs.dart';
import 'cp_common.dart';
import 'cp_model.dart';

// Content tab drawers (Assign content, Content preview, Change how long) and the drawer pieces the Content and
// Forms tabs share (`.dr-sec`, `.dr-opt`, `.dr-sw`, `.field`).

/// [cpHer]: "her" / "his" / "their" (possessive: "From her plans"). [cpHerObj]: "her" / "him" / "them"
/// (object: "Remind her to open it").
String cpHer(CpController c) => switch ('${c.detail['gender']}') { 'female' => 'her', 'male' => 'his', _ => 'their' };
String cpHerObj(CpController c) => switch ('${c.detail['gender']}') { 'female' => 'her', 'male' => 'him', _ => 'them' };
String cpShe(CpController c) => switch ('${c.detail['gender']}') { 'female' => 'she', 'male' => 'he', _ => 'they' };

AppIconData cpContentIcon(String kind) => switch (kind) {
      'video' => AppIcons.play,
      'image' => AppIcons.photo,
      'link' => AppIcons.link,
      _ => AppIcons.doc,
    };

Tone cpWhyTone(String why) => switch (why) { 'assigned' => Tone.warn, 'plan' => Tone.info, _ => Tone.neutral };

/// "2 d ago", "3 w ago", "5 h ago"; older than 5 weeks "12 Jan".
String cpShortAgo(Object? iso) {
  final t = cpParse(iso);
  if (t == null) return '';
  final d = DateTime.now().difference(t);
  if (d.inMinutes < 1) return 'just now';
  if (d.inHours < 1) return '${d.inMinutes} min ago';
  if (d.inDays < 1) return '${d.inHours} h ago';
  if (d.inDays < 7) return '${d.inDays} d ago';
  if (d.inDays < 35) return '${d.inDays ~/ 7} w ago';
  return cpDm(iso);
}

// ─────────────────────────────── Drawer pieces

/// `.dr-sec`: 16 above and below, a line under; `h4` + grey line, optional right side.
class DrSec extends StatelessWidget {
  const DrSec({super.key, required this.title, this.sub, this.trailing, required this.children, this.last = false, this.inlineSub = false});
  final String title;
  final String? sub;
  final Widget? trailing;
  final List<Widget> children;
  final bool last, inlineSub;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(border: last ? null : const Border(bottom: BorderSide(color: AppColors.line))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 10, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: inlineSub && !context.isPhone && sub != null
                  ? Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, spacing: 10, children: [
                      Text(title, style: AppText.s(13.5, W.w8)),
                      Flexible(child: Text(sub!, style: AppText.s(12.5, W.w5, color: AppColors.muted))),
                    ])
                  : Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 2, children: [
                      Text(title, style: AppText.s(13.5, W.w8)),
                      if (sub != null) Text(sub!, style: AppText.s(12.5, W.w5, color: AppColors.muted)),
                    ]),
            ),
            ?trailing,
          ]),
          ...children,
        ]),
      );
}

/// `.dr-opts.joined`: options in one box with lines between.
class DrOpts extends StatelessWidget {
  const DrOpts(this.children, {super.key});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (final (i, w) in children.indexed)
          Container(decoration: BoxDecoration(border: i == 0 ? null : const Border(top: BorderSide(color: AppColors.line))), child: w),
      ]);
}

/// A pick list in a drawer: [DrOpts] rows, about [rows] rows tall (6 by default); longer lists scroll inside
/// it with a scroll bar, and [footer] ("Show more") sits at the end of the scroll.
class DrScrollList extends StatefulWidget {
  const DrScrollList(this.children, {super.key, this.rows = 6, this.rowHeight = 55, this.footer});
  final List<Widget> children;
  final int rows;
  final double rowHeight;
  final Widget? footer;
  @override
  State<DrScrollList> createState() => _DrScrollListState();
}

class _DrScrollListState extends State<DrScrollList> {
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Container(
        constraints: BoxConstraints(maxHeight: widget.rows * widget.rowHeight),
        decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppColors.line), bottom: BorderSide(color: AppColors.line))),
        child: Scrollbar(
          controller: _scroll,
          thumbVisibility: widget.children.length > widget.rows,
          child: SingleChildScrollView(
            controller: _scroll,
            padding: EdgeInsets.only(right: widget.children.length > widget.rows ? 12 : 0),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              DrOpts(widget.children),
              if (widget.footer != null) Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: widget.footer),
            ]),
          ),
        ),
      );
}

/// `.dr-opt.sm`: radio or square check, optional thumb, title (+ badge), grey line, number on the right.
class DrOpt extends StatelessWidget {
  const DrOpt({super.key, required this.title, this.sub, this.badge, this.end, this.thumb, required this.on, this.multi = false, this.disabled = false, this.onTap});
  final String title;
  final String? sub, badge, end;
  final Widget? thumb;
  final bool on, multi, disabled;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => Opacity(
        opacity: disabled ? .55 : 1,
        child: Hover(
          onTap: disabled ? null : onTap,
          builder: (_, h, _) => Container(
            padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 0),
            color: h && !disabled ? AppColors.outlineHover : null,
            child: Row(spacing: 12, children: [
              multi ? AppCheckbox(value: on && !disabled, size: 18, onChanged: disabled ? null : (_) => onTap?.call()) : AppRadio(selected: on, onTap: onTap),
              ?thumb,
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 1, children: [
                  Wrap(spacing: 8, runSpacing: 2, crossAxisAlignment: WrapCrossAlignment.center, children: [
                    Text(title, style: AppText.s(13.5, W.w7)),
                    if (badge != null && badge!.isNotEmpty) AppBadge(badge!, plain: true),
                  ]),
                  if (sub != null && sub!.isNotEmpty) Text(sub!, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(12.5, W.w5, color: AppColors.muted)),
                ]),
              ),
              if (end != null) Text(end!, style: AppText.s(12, W.w5, color: AppColors.muted)),
            ]),
          ),
        ),
      );
}

/// `.dr-sw`: a switch, a bold line and a grey line.
class DrSwitch extends StatelessWidget {
  const DrSwitch({super.key, required this.title, required this.sub, required this.value, required this.onChanged});
  final String title, sub;
  final bool value;
  final ValueChanged<bool> onChanged;
  @override
  Widget build(BuildContext context) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => onChanged(!value),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 12, children: [
          Padding(padding: const EdgeInsets.only(top: 2), child: AppToggle(value: value, onChanged: onChanged)),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 1, children: [
              Text(title, style: AppText.s(13.5, W.w7)),
              Text(sub, style: AppText.s(12.5, W.w5, color: AppColors.muted)),
            ]),
          ),
        ]),
      );
}

/// `.field`: label over the control.
Widget drField(String label, Widget child, {String? error}) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 6, children: [
      Text(label, style: AppText.label),
      child,
      if (error != null) Text(error, style: AppText.s(12, W.w6, color: AppColors.badText)),
    ]);

/// A select-looking box that opens the date picker.
class DrDateBox extends StatelessWidget {
  const DrDateBox(this.value, {super.key, required this.onPick, this.first, this.placeholder = 'Pick a day'});
  final DateTime? value, first;
  final String placeholder;
  final ValueChanged<DateTime> onPick;
  @override
  Widget build(BuildContext context) => Hover(
        onTap: () async {
          final now = DateTime.now();
          final f = first ?? DateTime(now.year, now.month, now.day);
          final v = await showDatePicker(context: context, initialDate: value ?? f, firstDate: f, lastDate: DateTime(now.year + 2));
          if (v != null) onPick(v);
        },
        builder: (_, h, _) => Container(
          height: 36,
          padding: const EdgeInsets.fromLTRB(12, 0, 10, 0),
          decoration: BoxDecoration(color: AppColors.card, borderRadius: AppRadius.all(AppRadius.input), border: Border.all(color: h ? AppColors.lineHover : AppColors.line2)),
          child: Row(spacing: 8, children: [
            Expanded(
              child: Text(value == null ? placeholder : DateFormat('EEE, d MMM').format(value!),
                  style: AppText.s(13.5, W.w6, color: value == null ? AppColors.muted : AppColors.text)),
            ),
            const AppIcon(AppIcons.chevronDown, size: 16, color: AppColors.muted),
          ]),
        ),
      );
}

/// `.pk-th.media.sm`: a small tinted tile with the kind's icon.
Widget cpMediaThumb(String kind, int i, {double w = 44, double h = 32}) {
  final (a, b) = AppColors.mediaTiles[i % AppColors.mediaTiles.length];
  return Container(
    width: w,
    height: h,
    alignment: Alignment.center,
    decoration: BoxDecoration(borderRadius: AppRadius.all(7), gradient: LinearGradient(colors: [a, b], begin: Alignment.topLeft, end: Alignment.bottomRight)),
    child: AppIcon(cpContentIcon(kind), size: 15, color: AppColors.mediaFg),
  );
}

String _ymd(DateTime d) => DateFormat('yyyy-MM-dd').format(d);

// ─────────────────────────────── Assign content drawer

class _Assign extends ChangeNotifier {
  _Assign(this.c);
  final CpController c;
  String kind = 'all', q = '', how = 'always';
  List<Map> items = [];
  int? nextOffset;
  bool loading = true, busy = false, tell = true;
  Map? plan;
  DateTime? date;
  String? error, dateError;
  final picked = <String>{};
  Timer? _debounce;

  void set(VoidCallback f) {
    f();
    notifyListeners();
  }

  Future<void> load({bool more = false}) async {
    if (!more) set(() => loading = true);
    try {
      final r = await Services.api.get<Map>('clients/${c.id}/content/library/', query: {'kind': kind, 'q': q, 'offset': more ? nextOffset : 0});
      final rows = [for (final x in (r['results'] as List? ?? const [])) x as Map];
      items = more ? [...items, ...rows] : rows;
      nextOffset = (r['next_offset'] as num?)?.toInt();
      plan = r['plan'] as Map?;
      if (how == 'plan' && plan == null) how = 'always';
      error = null;
    } on ApiError catch (e) {
      error = e.message;
    }
    loading = false;
    notifyListeners();
  }

  void search(String v) {
    q = v.trim();
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), load);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }
}

/// Assign content to Riya: 1. Pick content (search, All · Videos · Guides, "Already has it"), 2. How long she
/// keeps it (Always · Until plan ends · Until a date), 3. Message (note + Tell Riya in the app). Returns how many
/// were assigned.
Future<int?> showAssignContentDrawer(BuildContext context, CpController c) {
  final s = _Assign(c)..load();
  final note = TextEditingController();
  final her = cpHer(c), she = cpShe(c);

  Future<void> save(BuildContext ctx) async {
    if (s.picked.isEmpty) return;
    if (s.how == 'date' && s.date == null) {
      s.set(() => s.dateError = 'Pick the last day.');
      return;
    }
    s.set(() => s.busy = true);
    try {
      final r = await Services.api.post<Map>('clients/${c.id}/content/', {
        'items': s.picked.toList(),
        'until': s.how,
        if (s.how == 'date') 'date': _ymd(s.date!),
        'note': note.text.trim(),
        'tell': s.tell,
      });
      if (ctx.mounted) Navigator.of(ctx).pop((r['added'] as num?)?.toInt() ?? s.picked.length);
    } on ApiError catch (e) {
      s.set(() {
        s.busy = false;
        s.dateError = e.field('date');
      });
      if (ctx.mounted && e.field('date') == null) showToast(ctx, 'Could not assign', sub: e.message);
    }
  }

  String summary() => '${s.picked.length} selected';

  return showAppDrawer<int>(
    context,
    title: 'Assign content to ${c.first}',
    sub: 'Videos, articles, PDFs and images from the library.',
    icon: AppIcons.content,
    builder: (ctx) => ListenableBuilder(
      listenable: s,
      builder: (ctx, _) {
        final planEnds = cpParse(s.plan?['ends']);
        final hint = switch (s.how) {
          'plan' => planEnds == null ? '' : 'Goes away on ${DateFormat('EEE, d MMM').format(planEnds)}',
          'date' => 'Pick the last day',
          _ => 'Stays in $her Library until you remove it',
        };
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          DrSec(
            title: '1. Pick content',
            sub: 'Pick one or more. ${c.first} sees them in the Library of $her app.',
            trailing: s.picked.isEmpty
                ? null
                : Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(color: AppColors.accentSoft, borderRadius: AppRadius.all(6)),
                    child: Text(summary(), style: AppText.s(12.5, W.w7, color: AppColors.accentText)),
                  ),
            children: [
              AppSearchField(placeholder: 'Search the library', icon: AppIcons.search, onChanged: s.search),
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final (k, l) in [('all', 'All'), ('video', 'Videos'), ('guide', 'Guides')])
                  FilterChipX(l, selected: s.kind == k, onTap: () {
                    s.kind = k;
                    s.load();
                  }),
              ]),
              if (s.loading)
                const CpLoading()
              else if (s.error != null)
                EmptyState('Could not load the library', sub: s.error, action: AppButton('Try again', onPressed: s.load))
              else if (s.items.isEmpty)
                EmptyState(s.q.isEmpty ? 'The library is empty' : 'Nothing matches “${s.q}”', sub: s.q.isEmpty ? 'Add videos and guides in the Content library first.' : 'Try another word.')
              else
                DrScrollList(footer: s.nextOffset != null ? Center(child: AppButton('Show more', size: BtnSize.sm, onPressed: () => s.load(more: true))) : null, [
                  for (final (i, x) in s.items.indexed)
                    DrOpt(
                      multi: true,
                      on: s.picked.contains('${x['id']}'),
                      disabled: x['has'] == true,
                      thumb: cpMediaThumb('${x['kind']}', i),
                      title: '${x['title']}',
                      badge: x['has'] == true ? 'Already has it' : null,
                      sub: x['has'] == true ? '${c.first} sees it now' : '${x['description'] ?? ''}',
                      end: '${x['kind_label']} · ${x['length']}',
                      onTap: () => s.set(() => s.picked.contains('${x['id']}') ? s.picked.remove('${x['id']}') : s.picked.add('${x['id']}')),
                    ),
                ]),
            ],
          ),
          DrSec(title: '2. How long $she ${she == 'they' ? 'keep' : 'keeps'} it', children: [
            Align(
              alignment: Alignment.centerLeft,
              child: SegmentedTabs<String>(
                height: 28,
                items: [const TabItem('always', 'Always'), if (s.plan != null) const TabItem('plan', 'Until plan ends'), const TabItem('date', 'Until a date')],
                value: s.how,
                onChanged: (v) => s.set(() {
                  s.how = v;
                  s.dateError = null;
                }),
              ),
            ),
            if (hint.isNotEmpty) Text(hint, style: AppText.s(12.5, W.w5, color: AppColors.muted)),
            if (s.how == 'date')
              drField('Last day', DrDateBox(s.date, onPick: (d) => s.set(() {
                    s.date = d;
                    s.dateError = null;
                  })), error: s.dateError),
          ]),
          DrSec(title: '3. Message', last: true, children: [
            drField('Note for ${c.first} (optional)', AppTextField(controller: note, maxLines: 4, minLines: 3, placeholder: 'Watch this before Tuesday’s leg day…')),
            DrSwitch(title: 'Tell ${c.first} in the app', sub: 'Push notice with your note', value: s.tell, onChanged: (v) => s.set(() => s.tell = v)),
          ]),
        ]);
      },
    ),
    footer: (ctx) => [
      if (!ctx.isPhone) Expanded(child: ListenableBuilder(listenable: s, builder: (_, _) => Text(summary(), style: AppText.s(12.5, W.w6, color: AppColors.muted)))),
      AppButton('Cancel', expand: ctx.isPhone, onPressed: () => Navigator.of(ctx).pop()),
      ListenableBuilder(
        listenable: s,
        builder: (_, _) => AppButton.primary(
          s.picked.isEmpty ? 'Assign' : 'Assign ${s.picked.length} ${s.picked.length == 1 ? 'item' : 'items'}',
          icon: AppIcons.check,
          expand: ctx.isPhone,
          loading: s.busy,
          onPressed: s.picked.isEmpty ? null : () => save(ctx),
        ),
      ),
    ],
  ).whenComplete(() => disposeLater([s, note]));
}

// ─────────────────────────────── Content preview drawer

/// "Exactly what Riya sees in her app": media, title, Opened / Watched / Reminder, why, shown until, added, and
/// what she reads. Returns 'remove' · 'library' · 'remind' for the footer buttons.
Future<String?> showContentPreview(BuildContext context, CpController c, Map r) {
  final her = cpHer(c), herObj = cpHerObj(c), she = cpShe(c);
  final kind = '${r['kind']}';
  final video = kind == 'video';
  final pic = '${r['image_url'] ?? ''}'.isNotEmpty
      ? '${r['image_url']}'
      : ('${r['cover_url'] ?? ''}'.isNotEmpty ? '${r['cover_url']}' : '${r['youtube_thumb'] ?? ''}');
  final p = (r['progress'] as num?)?.toInt() ?? 0;
  final dur = (r['duration'] as num?)?.toInt() ?? 0;
  String clock(int sec) => '${sec ~/ 60}:${(sec % 60).toString().padLeft(2, '0')}';
  final consumed = r['finished'] == true || p >= 95
      ? 'Full'
      : (video && dur > 0 ? '${clock((dur * p / 100).round())} of ${clock(dur)}' : '$p%');
  final kpis = [
    ('Opened', r['opened_at'] == null ? 'Not yet' : cpAgo(r['opened_at'])),
    (video ? 'Watched' : 'Read', r['opened_at'] == null ? (video ? '0:00' : '0%') : consumed),
    ('Reminder', r['reminded_at'] == null ? 'None' : 'Sent ${cpDm(r['reminded_at'])}'),
  ];
  final assigned = r['why'] == 'assigned';
  Widget qa(String k, String v) => Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.line))),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: Text(k, style: AppText.s(13, W.w5, color: AppColors.text2))),
          Expanded(child: Text(v, style: AppText.s(13, W.w6))),
        ]),
      );
  return showAppDrawer<String>(
    context,
    title: 'Content preview',
    sub: 'Exactly what ${c.first} sees in $her app',
    icon: AppIcons.content,
    builder: (ctx) => Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 14, children: [
        ClipRRect(
          borderRadius: AppRadius.all(AppRadius.card),
          child: SizedBox(
            height: 220,
            child: Stack(fit: StackFit.expand, children: [
              if (pic.isNotEmpty)
                NetImage(pic, fit: BoxFit.cover)
              else
                Container(
                  decoration: BoxDecoration(
                      gradient: LinearGradient(colors: [AppColors.mediaTiles[0].$1, AppColors.mediaTiles[0].$2], begin: Alignment.topLeft, end: Alignment.bottomRight)),
                  child: video ? null : Center(child: AppIcon(cpContentIcon(kind), size: 40, color: AppColors.mediaFg)),
                ),
              if (video)
                Center(
                  child: Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(color: AppColors.text.withValues(alpha: .72), shape: BoxShape.circle),
                    child: const Icon(Icons.play_arrow_rounded, color: AppColors.white, size: 30),
                  ),
                ),
              Positioned(
                right: 10,
                bottom: 10,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(color: AppColors.text.withValues(alpha: .72), borderRadius: AppRadius.all(5)),
                  child: Text('${r['length']}', style: AppText.s(12, W.w7, color: AppColors.white)),
                ),
              ),
            ]),
          ),
        ),
        Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 2, children: [
          Text('${r['title']}', style: AppText.s(16, W.w8)),
          Text('${r['kind_label']} · by ${r['added_by']}', style: AppText.cap),
        ]),
        Container(
          padding: const EdgeInsets.only(bottom: 10),
          decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.line))),
          child: IntrinsicHeight(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              for (final (i, (k, v)) in kpis.indexed)
                Expanded(
                  child: Container(
                    padding: EdgeInsets.only(left: i == 0 ? 0 : 12),
                    decoration: BoxDecoration(border: i == 0 ? null : const Border(left: BorderSide(color: AppColors.line))),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 2, children: [
                      Text(k, style: AppText.s(11.5, W.w6, color: AppColors.muted)),
                      Text(v, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(14, W.w8)),
                    ]),
                  ),
                ),
            ]),
          ),
        ),
        Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          qa('Why $she ${she == 'they' ? 'see' : 'sees'} it', '${r['why_label']}'),
          qa('Shown until', '${r['until_label']}'),
          qa('Added', cpDm(r['added_at'])),
          if ('${r['note'] ?? ''}'.isNotEmpty) qa('Your note', '${r['note']}'),
        ]),
        Text('WHAT ${c.first.toUpperCase()} READS', style: AppText.over),
        Text('${r['text'] ?? ''}'.isEmpty ? 'No description yet.' : '${r['text']}', style: AppText.s(13.5, W.w5, color: AppColors.text2, h: 1.6)),
      ]),
    ),
    footer: (ctx) => [
      if (ctx.isPhone)
        AppButton.primary('Remind $herObj', icon: AppIcons.bell, expand: true, onPressed: () => Navigator.of(ctx).pop('remind'))
      else
        AppButton(assigned ? 'Remove for ${c.first}' : 'Hide for ${c.first}', kind: BtnKind.text, icon: AppIcons.stop, onPressed: () => Navigator.of(ctx).pop('remove')),
      if (!ctx.isPhone) const Spacer(),
      AppButton('Open in library', icon: AppIcons.external, expand: ctx.isPhone, onPressed: () => Navigator.of(ctx).pop('library')),
      if (ctx.isPhone)
        AppButton(assigned ? 'Remove for ${c.first}' : 'Hide for ${c.first}', kind: BtnKind.danger, icon: AppIcons.stop, expand: true, onPressed: () => Navigator.of(ctx).pop('remove'))
      else
        AppButton.primary('Remind $herObj', icon: AppIcons.bell, onPressed: () => Navigator.of(ctx).pop('remind')),
    ],
  );
}

// ─────────────────────────────── Change how long

/// Always · Until plan ends · Until a date for one row. Returns the new "Shown until" label.
/// [plan] = the current program and its last day (`plan` of the list), for "Until plan ends".
Future<String?> showHowLongModal(BuildContext context, CpController c, Map r, Map? plan) {
  final she = cpShe(c), her = cpHer(c);
  final until = cpParse(r['until']);
  final s = ValueNotifier<(String, DateTime?, bool, String?)>((until != null ? 'date' : 'always', until, false, null));
  final planEnds = cpParse(plan?['ends']);
  return showAppModal<String>(
    context,
    title: 'How long $she ${she == 'they' ? 'keep' : 'keeps'} it',
    body: '${r['title']}',
    icon: AppIcons.clock,
    content: (ctx) => ValueListenableBuilder(
      valueListenable: s,
      builder: (_, v, _) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 10, children: [
        Align(
          alignment: Alignment.centerLeft,
          child: SegmentedTabs<String>(
            height: 28,
            items: [const TabItem('always', 'Always'), if (plan != null) const TabItem('plan', 'Until plan ends'), const TabItem('date', 'Until a date')],
            value: v.$1,
            onChanged: (x) => s.value = (x, v.$2, false, null),
          ),
        ),
        Text(
          switch (v.$1) {
            'plan' => planEnds == null ? '' : 'Goes away on ${DateFormat('EEE, d MMM').format(planEnds)}',
            'date' => 'Pick the last day',
            _ => 'Stays in $her Library until you remove it',
          },
          style: AppText.s(12.5, W.w5, color: AppColors.muted),
        ),
        if (v.$1 == 'date') drField('Last day', DrDateBox(v.$2, onPick: (d) => s.value = (v.$1, d, false, null)), error: v.$4),
      ]),
    ),
    actions: (ctx) => [
      AppButton('Cancel', expand: ctx.isPhone, onPressed: () => Navigator.of(ctx).pop()),
      ValueListenableBuilder(
        valueListenable: s,
        builder: (_, v, _) => AppButton.primary('Save', expand: ctx.isPhone, loading: v.$3, onPressed: () async {
          if (v.$1 == 'date' && v.$2 == null) {
            s.value = (v.$1, v.$2, false, 'Pick the last day.');
            return;
          }
          s.value = (v.$1, v.$2, true, null);
          try {
            final res = await Services.api.post<Map>('clients/${c.id}/content/${r['id']}/until/', {'until': v.$1, if (v.$1 == 'date') 'date': _ymd(v.$2!)});
            if (ctx.mounted) Navigator.of(ctx).pop('${res['until_label']}');
          } on ApiError catch (e) {
            s.value = (v.$1, v.$2, false, e.field('date') ?? e.field('until') ?? e.message);
          }
        }),
      ),
    ],
  ).whenComplete(() => disposeLater([s]));
}
