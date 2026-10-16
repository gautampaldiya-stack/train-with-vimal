import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api/api_error.dart';
import '../../../core/icons/app_icons.dart';
import '../../../core/theme/theme.dart';
import '../../../core/widgets/avatar.dart';
import '../../../core/widgets/button.dart';
import '../../../core/widgets/card.dart';
import '../../../core/widgets/hover.dart';
import '../../../core/widgets/input.dart';
import '../../../core/widgets/overlays.dart';
import '../../../core/widgets/responsive.dart';
import '../../../core/widgets/tabs.dart';
import '../../../core/widgets/tooltip.dart';
import 'dashboard_model.dart';

// ─────────────────────────────── Bell dropdown (`.td-notes`)

/// 340 wide under the bell (phone: full width, 16 from the edges, under the hero's top row).
Future<void> showNotesDropdown(BuildContext anchor, TrainerHomeController c, {required void Function(TdNotice) onOpen}) {
  final box = anchor.findRenderObject() as RenderBox;
  final overlay = Overlay.of(anchor, rootOverlay: true).context.findRenderObject() as RenderBox;
  final at = box.localToGlobal(Offset.zero, ancestor: overlay);
  final size = overlay.size;
  final phone = anchor.isPhone;
  const width = 340.0;
  return showGeneralDialog(
    context: anchor,
    barrierDismissible: true,
    barrierLabel: 'Notifications',
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 90),
    transitionBuilder: (_, a, _, child) => FadeTransition(opacity: a, child: child),
    pageBuilder: (ctx, _, _) => Stack(children: [
      Positioned(
        left: phone ? 16 : (at.dx + box.size.width - width).clamp(8, size.width - width - 8),
        right: phone ? 16 : null,
        width: phone ? null : width,
        top: at.dy + box.size.height + 6,
        child: Material(
          color: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.all(6),
            constraints: BoxConstraints(maxHeight: size.height - at.dy - box.size.height - (phone ? 120 : 24)),
            decoration: BoxDecoration(color: AppColors.card, borderRadius: AppRadius.all(AppRadius.menu), border: Border.all(color: AppColors.line), boxShadow: AppShadows.menu),
            child: ListenableBuilder(
              listenable: c,
              builder: (ctx, _) {
                final list = c.data?.notices ?? const <TdNotice>[];
                return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
                    child: Row(children: [
                      Expanded(child: Text('Notifications', style: AppText.s(14, W.w7))),
                      if ((c.data?.unread ?? 0) > 0)
                        Hover(
                          onTap: () => c.readAll().catchError((_) {}),
                          builder: (_, h, _) => SizedBox(
                            height: 26,
                            child: Center(
                              child: Text('Mark all read',
                                  style: AppText.s(12.5, W.w7, color: AppColors.accentText).copyWith(decoration: h ? TextDecoration.underline : null)),
                            ),
                          ),
                        ),
                    ]),
                  ),
                  if (list.isEmpty) Padding(padding: const EdgeInsets.fromLTRB(8, 4, 8, 10), child: Text('Nothing new yet.', style: AppText.cap)),
                  Flexible(
                    child: SingleChildScrollView(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 2, children: [
                        for (final n in list)
                          Hover(
                            onTap: () {
                              Navigator.of(ctx).pop();
                              onOpen(n);
                            },
                            builder: (_, h, _) => Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: h ? AppColors.sub : (n.read ? null : AppColors.tdNoteNew),
                                borderRadius: AppRadius.all(AppRadius.item),
                              ),
                              child: Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 10, children: [
                                AppAvatar(n.initials, size: 24, colors: AppColors.avatarCode(n.color), initials: n.initials),
                                Expanded(
                                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 2, children: [
                                    Text(n.title, style: AppText.s(13, W.w6, h: 1.35)),
                                    Text(n.when, style: AppText.s(12, W.w5, color: AppColors.muted)),
                                  ]),
                                ),
                              ]),
                            ),
                          ),
                      ]),
                    ),
                  ),
                ]);
              },
            ),
          ),
        ),
      ),
    ]),
  );
}

// ─────────────────────────────── Review drawer

class ReviewResult {
  const ReviewResult(this.replied);
  final bool replied;
}

const _quick = ['Great week, keep going!', 'Let’s talk at your next session.', 'I’ve updated your plan.'];

/// `First’s weekly check-in`: 4 numbers, the week's answers with last week, what they wrote, photos, reply.
Future<ReviewResult?> showReviewDrawer(BuildContext context, TrainerHomeController c, TdCheckin r) {
  final reply = TextEditingController();
  final busy = ValueNotifier(false);
  final first = r.client.first;
  final weight = r.line.startsWith('Weight') ? ' · ${r.line.split(' · ').first}' : '';
  final detail = c.checkin(r.id);

  Future<void> done(BuildContext ctx) async {
    busy.value = true;
    try {
      final text = reply.text.trim();
      await c.review(r, text);
      if (ctx.mounted) Navigator.of(ctx).pop(ReviewResult(text.isNotEmpty));
    } on ApiError catch (e) {
      busy.value = false;
      if (ctx.mounted) showToast(ctx, e.message);
    }
  }

  void profile(BuildContext ctx) {
    Navigator.of(ctx).pop();
    context.go('/clients/${r.client.id}');
  }

  Widget mainBtn(BuildContext ctx, {bool expand = false}) => ListenableBuilder(
        listenable: Listenable.merge([reply, busy]),
        builder: (_, _) => AppButton.primary(reply.text.trim().isEmpty ? 'Mark reviewed' : 'Send and mark reviewed',
            icon: AppIcons.check, loading: busy.value, expand: expand, onPressed: () => done(ctx)),
      );

  final phone = context.isPhone;
  return showAppDrawer<ReviewResult>(
    context,
    title: '$first’s ${r.kind.toLowerCase()}',
    sub: 'Sent ${r.age} ago$weight',
    icon: AppIcons.clipboard,
    builder: (ctx) => FutureBuilder<Map>(
      future: detail,
      builder: (ctx, snap) {
        if (snap.hasError) {
          return EmptyState('Could not open this check-in', sub: snap.error is ApiError ? (snap.error as ApiError).message : null);
        }
        if (!snap.hasData) {
          return const Padding(
            padding: EdgeInsets.all(40),
            child: Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.2, color: AppColors.accent))),
          );
        }
        final d = snap.data!;
        final rv = (d['review'] as Map?) ?? const {};
        final kpis = [for (final k in (rv['kpis'] as List? ?? const [])) ('${(k as Map)['label']}', '${k['value']}')];
        final rows = [for (final q in (rv['rows'] as List? ?? const [])) ('${(q as Map)['label']}', '${q['value']}', '${q['last'] ?? ''}')];
        final note = '${rv['note'] ?? ''}';
        final photos = [for (final p in (d['photos'] as List? ?? const [])) p as Map];
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _Sec(children: [
            if (kpis.isNotEmpty) _Kpis(kpis),
            if (rows.isNotEmpty)
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                for (final (i, (k, v, m)) in rows.indexed)
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 9),
                    decoration: BoxDecoration(border: i == 0 ? null : const Border(top: BorderSide(color: AppColors.line))),
                    child: Row(spacing: 12, children: [
                      SizedBox(width: 72, child: Text(k, style: AppText.s(13, W.w6, color: AppColors.muted))),
                      Expanded(child: Text(v, style: AppText.s(13, W.w6))),
                      if (m.isNotEmpty) Text(m, style: AppText.s(12, W.w4, color: AppColors.muted)),
                    ]),
                  ),
              ]),
          ]),
          if (note.isNotEmpty)
            _Sec(children: [
              Container(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                decoration: BoxDecoration(color: AppColors.caWebBg, borderRadius: AppRadius.all(AppRadius.card), border: Border.all(color: AppColors.line)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 2, children: [
                  Text('$first wrote', style: AppText.s(12, W.w7, color: AppColors.muted)),
                  Text(note, style: AppText.s(13, W.w4, color: AppColors.text2, h: 1.5)),
                ]),
              ),
            ]),
          _Sec(children: [
            _SecHead('Photos', trailing: Text(photos.isEmpty ? 'No photos this time' : '${photos.length} new', style: AppText.cap)),
            if (photos.isNotEmpty)
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final p in photos)
                  ClipRRect(
                    borderRadius: AppRadius.all(10),
                    child: Container(
                      width: 92,
                      height: 112,
                      color: AppColors.sub,
                      child: Stack(fit: StackFit.expand, children: [
                        Image.network('${p['image']}', fit: BoxFit.cover, errorBuilder: (_, _, _) => const Center(child: AppIcon(AppIcons.photo, size: 22, color: AppColors.muted))),
                        Positioned(
                          left: 6,
                          bottom: 6,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(color: AppColors.pxPoseBg, borderRadius: AppRadius.all(6)),
                            child: Text('${p['label']}', style: AppText.s(11.5, W.w6)),
                          ),
                        ),
                      ]),
                    ),
                  ),
              ]),
          ]),
          _Sec(last: true, children: [
            const _SecHead('Reply',
                trailing: AppTooltip(
                  message: 'The client gets your reply in the app with their check-in. You can edit their plan from their profile.',
                  child: AppIcon(AppIcons.infoAlt, size: 16, color: AppColors.muted),
                )),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(borderRadius: AppRadius.all(AppRadius.card), border: Border.all(color: AppColors.line)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 8, children: [
                TextField(
                  controller: reply,
                  minLines: 3,
                  maxLines: 6,
                  maxLength: 2000,
                  style: AppText.s(13.5, W.w5),
                  decoration: InputDecoration(
                    isDense: true,
                    counterText: '',
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
                    hintText: 'Write a short reply for $first…',
                    hintStyle: AppText.s(13.5, W.w5, color: AppColors.muted),
                  ),
                ),
                Wrap(spacing: 6, runSpacing: 6, children: [
                  for (final q in _quick)
                    _Chip(q, onTap: () {
                      reply.text = q;
                      reply.selection = TextSelection.collapsed(offset: q.length);
                    }),
                ]),
              ]),
            ),
          ]),
        ]);
      },
    ),
    footer: (ctx) => phone
        ? [
            Row(spacing: 8, children: [
              Expanded(child: AppButton('Open profile', icon: AppIcons.eye, expand: true, onPressed: () => profile(ctx))),
              Expanded(child: mainBtn(ctx, expand: true)),
            ]),
          ]
        : [
            AppButton('Open profile', icon: AppIcons.eye, onPressed: () => profile(ctx)),
            const Spacer(),
            AppButton('Close', onPressed: () => Navigator.of(ctx).pop()),
            mainBtn(ctx),
          ],
  ).whenComplete(() {
    reply.dispose();
    busy.dispose();
  });
}

/// `.dr-sec`: 16 top and bottom, line under it.
class _Sec extends StatelessWidget {
  const _Sec({required this.children, this.last = false});
  final List<Widget> children;
  final bool last;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(border: last ? null : const Border(bottom: BorderSide(color: AppColors.line))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 10, children: children),
      );
}

class _SecHead extends StatelessWidget {
  const _SecHead(this.title, {this.trailing});
  final String title;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) => SizedBox(
        height: 30,
        child: Row(children: [Expanded(child: Text(title, style: AppText.s(13.5, W.w8))), ?trailing]),
      );
}

/// `.dr-kpis` in the drawer: 4 cells with a line between, a line under (2 × 2 on a phone).
class _Kpis extends StatelessWidget {
  const _Kpis(this.items);
  final List<(String, String)> items;
  @override
  Widget build(BuildContext context) {
    Widget cell((String, String) k, int i, {bool divide = true}) => Container(
          padding: EdgeInsets.fromLTRB(i == 0 || !divide ? 0 : 12, 2, 12, 2),
          decoration: BoxDecoration(border: divide && i > 0 ? const Border(left: BorderSide(color: AppColors.line)) : null),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 2, children: [
            Text(k.$1, style: AppText.s(11.5, W.w6, color: AppColors.muted), maxLines: 1, overflow: TextOverflow.ellipsis),
            Text(k.$2, style: AppText.s(14, W.w8), maxLines: 1, overflow: TextOverflow.ellipsis),
          ]),
        );
    final phone = context.isPhone;
    return Container(
      padding: const EdgeInsets.only(bottom: 10),
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.line))),
      child: phone
          ? Column(spacing: 10, children: [
              for (var r = 0; r < items.length; r += 2)
                IntrinsicHeight(
                  child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    for (var i = r; i < r + 2; i++) Expanded(child: i < items.length ? cell(items[i], i - r) : const SizedBox()),
                  ]),
                ),
            ])
          : IntrinsicHeight(
              child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [for (final (i, k) in items.indexed) Expanded(child: cell(k, i))]),
            ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip(this.label, {required this.onTap});
  final String label;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Hover(
        onTap: onTap,
        builder: (_, h, _) => Container(
          height: 28,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: h ? AppColors.outlineHover : AppColors.white,
            borderRadius: AppRadius.all(AppRadius.chip),
            border: Border.all(color: AppColors.line2),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [Text(label, style: AppText.s(12.5, W.w6, color: AppColors.text2))]),
        ),
      );
}

// ─────────────────────────────── New session modal

class NewSession {
  const NewSession(this.id, this.client, this.when);
  final String id, client, when;
}

const _lens = [30, 45, 60, 90];
const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
const _days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

String _two(int n) => n.toString().padLeft(2, '0');

/// "New session · Shows in your calendar and the client’s app.": client, day + time, length, where, note.
Future<NewSession?> showNewSessionModal(BuildContext context, TrainerHomeController c) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  // Next free half hour from now; after 21:30 it moves to tomorrow 07:00.
  var first = now.add(Duration(minutes: 30 - now.minute % 30));
  var dayIx = 0;
  if (first.hour > 21 || first.day != now.day) {
    dayIx = 1;
    first = DateTime(now.year, now.month, now.day + 1, 7);
  }
  final s = _NsState(day: dayIx, time: '${_two(first.hour)}:${_two(first.minute)}');
  final clients = c.myClients();
  final note = TextEditingController();

  String dayLabel(int i) {
    final d = today.add(Duration(days: i));
    final name = i == 0 ? 'Today' : (i == 1 ? 'Tomorrow' : _days[d.weekday - 1]);
    return '$name, ${d.day} ${_months[d.month - 1]}';
  }

  final times = [for (var m = 6 * 60; m <= 21 * 60 + 30; m += 15) '${_two(m ~/ 60)}:${_two(m % 60)}'];

  Future<void> add(BuildContext ctx) async {
    final who = s.client;
    if (who == null) {
      s.error = 'Pick a client.';
      s.changed();
      return;
    }
    s.busy = true;
    s.changed();
    final d = today.add(Duration(days: s.day));
    final start = DateTime(d.year, d.month, d.day, int.parse(s.time.split(':')[0]), int.parse(s.time.split(':')[1]));
    try {
      final id = await c.addSession(client: who.id, start: start, minutes: _lens[s.len], call: s.where == 1, note: note.text.trim());
      final when = '${s.day == 0 ? 'today' : (s.day == 1 ? 'tomorrow' : dayLabel(s.day))} ${s.time}';
      if (ctx.mounted) Navigator.of(ctx).pop(NewSession(id, who.name, when));
    } on ApiError catch (e) {
      s.busy = false;
      s.error = e.fields.values.expand((v) => v).firstOrNull ?? e.message;
      s.changed();
    }
  }

  Widget field(String label, Widget child) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 6, children: [
        Text(label, style: AppText.label),
        child,
      ]);

  return showAppModal<NewSession>(
    context,
    title: 'New session',
    body: 'Shows in your calendar and the client’s app.',
    icon: AppIcons.calendarAlt,
    width: 480,
    content: (ctx) => ListenableBuilder(
      listenable: s,
      builder: (ctx, _) => FutureBuilder<List<TdPerson>>(
        future: clients,
        builder: (ctx, snap) {
          final list = snap.data ?? const <TdPerson>[];
          if (s.client == null && list.isNotEmpty) s.client = list.first;
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 12, children: [
            field(
              'Client',
              _Select(
                s.client?.name ?? (snap.hasError ? 'Could not load your clients' : 'Loading…'),
                entries: [for (final p in list) MenuEntry(p.name, selected: p.id == s.client?.id, onTap: () => s.set(() => s.client = p))],
              ),
            ),
            Row(spacing: 12, children: [
              Expanded(
                child: field('Day', _Select(dayLabel(s.day), entries: [for (var i = 0; i < 14; i++) MenuEntry(dayLabel(i), selected: i == s.day, onTap: () => s.set(() => s.day = i))])),
              ),
              Expanded(
                child: field('Time', _Select(s.time, entries: [for (final t in times) MenuEntry(t, selected: t == s.time, onTap: () => s.set(() => s.time = t))])),
              ),
            ]),
            field(
              'Length',
              Align(
                alignment: Alignment.centerLeft,
                child: SegmentedTabs<int>(
                  height: 28,
                  items: [for (final (i, m) in _lens.indexed) TabItem(i, '$m min')],
                  value: s.len,
                  onChanged: (v) => s.set(() => s.len = v),
                ),
              ),
            ),
            field(
              'Where',
              Align(
                alignment: Alignment.centerLeft,
                child: SegmentedTabs<int>(
                  height: 28,
                  items: const [TabItem(0, 'Gym floor'), TabItem(1, 'Video call')],
                  value: s.where,
                  onChanged: (v) => s.set(() => s.where = v),
                ),
              ),
            ),
            AppTextField(label: 'Note for the client', placeholder: 'Bring your lifting belt', controller: note),
            if (s.error != null) Text(s.error!, style: AppText.s(12.5, W.w6, color: AppColors.badText)),
          ]);
        },
      ),
    ),
    actions: (ctx) => [
      AppButton('Cancel', expand: ctx.isPhone, onPressed: () => Navigator.of(ctx).pop()),
      ListenableBuilder(
        listenable: s,
        builder: (_, _) => AppButton.primary('Add session', expand: ctx.isPhone, loading: s.busy, onPressed: () => add(ctx)),
      ),
    ],
  ).whenComplete(() {
    note.dispose();
    s.dispose();
  });
}

class _NsState extends ChangeNotifier {
  _NsState({required this.day, required this.time});
  TdPerson? client;
  int day, len = 2, where = 0;
  String time;
  String? error;
  bool busy = false;
  void set(VoidCallback f) {
    f();
    error = null;
    notifyListeners();
  }

  void changed() => notifyListeners();
}

/// `.select`: 36 high, line2 border, value 13.5/600 and a chevron; opens a menu with a tick on the picked item.
class _Select extends StatelessWidget {
  const _Select(this.value, {required this.entries});
  final String value;
  final List<MenuEntry> entries;
  @override
  Widget build(BuildContext context) => Builder(
        builder: (b) => Hover(
          onTap: entries.isEmpty ? null : () => showAppMenu(b, entries, width: (b.findRenderObject() as RenderBox).size.width, alignRight: false),
          builder: (_, h, _) => Container(
            height: 36,
            padding: const EdgeInsets.fromLTRB(12, 0, 10, 0),
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: AppRadius.all(AppRadius.input),
              border: Border.all(color: h ? AppColors.lineHover : AppColors.line2),
            ),
            child: Row(spacing: 8, children: [
              Expanded(child: Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(13.5, W.w6))),
              const AppIcon(AppIcons.chevronDown, size: 16, color: AppColors.muted),
            ]),
          ),
        ),
      );
}
