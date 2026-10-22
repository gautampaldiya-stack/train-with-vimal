import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/api/api_error.dart';
import '../../../core/icons/app_icons.dart';
import '../../../core/theme/theme.dart';
import '../../../core/widgets/badge.dart';
import '../../../core/widgets/button.dart';
import '../../../core/widgets/hover.dart';
import '../../../core/widgets/input.dart';
import '../../../core/widgets/overlays.dart';
import '../../../core/widgets/responsive.dart';
import '../../../core/widgets/select.dart';
import 'cal_model.dart';
import '../../../core/widgets/tooltip.dart';

// Calendar overlays from the boards: the session panel (`.modal.cal-det`, phone: bottom sheet), Cancel this session?,
// the New session / Move session drawer and My working hours.

// ─────────────────────────────── Small board pieces

/// `.cal-kind`: kind-tinted chip with a square dot.
class CalKindChip extends StatelessWidget {
  const CalKindChip(this.kind, {super.key});
  final CalKind kind;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: kind.bg, borderRadius: AppRadius.all(AppRadius.badge)),
        child: Row(mainAxisSize: MainAxisSize.min, spacing: 6, children: [
          Container(width: 8, height: 8, decoration: BoxDecoration(color: kind.dot, borderRadius: AppRadius.all(2))),
          Text(kind.label, style: AppText.s(12, W.w7, color: kind.fg)),
        ]),
      );
}

/// `.tabs.sm`: grey track (padding 3), 28 high tabs, 12.5/600; the picked one white with a soft shadow.
class CalTabs<T> extends StatelessWidget {
  const CalTabs({super.key, required this.items, required this.value, required this.onChanged});
  final List<(T, String)> items;
  final T value;
  final ValueChanged<T> onChanged;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(color: AppColors.sub, borderRadius: AppRadius.all(AppRadius.btn)),
        child: Row(mainAxisSize: MainAxisSize.min, spacing: 2, children: [
          for (final (v, label) in items)
            Hover(
              onTap: v == value ? null : () => onChanged(v),
              builder: (_, h, _) => Container(
                height: 28,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: v == value ? AppColors.white : null,
                  borderRadius: AppRadius.all(AppRadius.tab),
                  boxShadow: v == value ? AppShadows.tab : null,
                ),
                child: Text(label, style: AppText.s(12.5, W.w6, color: v == value || h ? AppColors.text : AppColors.text2)),
              ),
            ),
        ]),
      );
}

/// `.field`: label (with a red * when required), the control, a grey hint.
Widget _field(String? label, Widget child, {String? hint, String? error, bool req = false}) =>
    Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 6, children: [
      if (label != null)
        Text.rich(TextSpan(text: label, style: AppText.label, children: [
          if (req) TextSpan(text: '*', style: AppText.s(12.5, W.w7, color: AppColors.badText)),
        ])),
      child,
      if (error != null)
        Text(error, style: AppText.s(12, W.w6, color: AppColors.badText))
      else if (hint != null)
        Text(hint, style: AppText.s(12, W.w5, color: AppColors.muted)),
    ]);

/// `.dr-sec`: 18 above and below, a line under, h4 title.
class _Sec extends StatelessWidget {
  const _Sec(this.title, this.children, {this.sub, this.last = false});
  final String title;
  final String? sub;
  final List<Widget> children;
  final bool last;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(vertical: 18),
        decoration: BoxDecoration(border: last ? null : const Border(bottom: BorderSide(color: AppColors.line))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 12, children: [
          Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 2, children: [
            Text(title, style: AppText.s(13.5, W.w8)),
            if (sub != null) Text(sub!, style: AppText.s(12.5, W.w5, color: AppColors.muted, h: 1.35)),
          ]),
          ...children,
        ]),
      );
}

/// `.dr-sw`: switch, bold line, grey line.
class _Switch extends StatelessWidget {
  const _Switch({required this.title, required this.sub, required this.value, required this.onChanged});
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

/// `.select.sm`: 32 high select (working hours from / to).
class _SmSelect extends StatelessWidget {
  const _SmSelect(this.value, {required this.entries, this.width = 112});
  final String value;
  final List<MenuEntry> entries;
  final double? width;
  @override
  Widget build(BuildContext context) => Builder(
        builder: (b) => Hover(
          onTap: () => showAppMenu(b, entries, width: 160, alignRight: false),
          builder: (_, h, _) => Container(
            width: width,
            height: 32,
            padding: EdgeInsets.fromLTRB(context.isPhone ? 8 : 12, 0, context.isPhone ? 6 : 10, 0),
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: AppRadius.all(AppRadius.input),
              border: Border.all(color: h ? AppColors.lineHover : AppColors.line2),
            ),
            child: Row(spacing: 6, children: [
              Expanded(child: CutText(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(13, W.w6))),
              const AppIcon(AppIcons.chevronDown, size: 16, color: AppColors.muted),
            ]),
          ),
        ),
      );
}

Tone calStatusTone(String status) => switch (status) { 'done' => Tone.ok, 'missed' => Tone.bad, _ => Tone.info };
String calStatusLabel(String status) => switch (status) { 'done' => 'Done', 'missed' => 'Missed', _ => 'Booked' };

// ─────────────────────────────── Session panel

/// Opens a session. Returns what the trainer picked: `profile` · `move` · `cancel` · `toggle`.
Future<String?> showSessionPanel(BuildContext context, CalSession s) {
  final phone = context.isPhone;
  Widget head(BuildContext ctx) => Padding(
        padding: phone ? const EdgeInsets.fromLTRB(4, 6, 0, 0) : const EdgeInsets.fromLTRB(20, 14, 16, 0),
        child: Row(spacing: 8, children: [
          CalKindChip(s.kind),
          AppBadge(calStatusLabel(s.status), tone: calStatusTone(s.status), plain: true),
          const Spacer(),
          AppIconButton(AppIcons.close, tooltip: 'Close', ghost: true, small: true, onPressed: () => Navigator.of(ctx).pop()),
        ]),
      );
  Widget kv(String k, String v, {String? extra}) => Container(
        padding: const EdgeInsets.fromLTRB(0, 10, 0, 10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 3, children: [
          Text(k, style: AppText.s(12.5, W.w5, color: AppColors.muted)),
          Text(v, style: AppText.s(14, W.w7)),
          if (extra != null && extra.isNotEmpty) SelectableText(extra, style: AppText.s(12.5, W.w6, color: AppColors.accentText)),
        ]),
      );
  Widget body(BuildContext ctx) => Padding(
        padding: phone ? const EdgeInsets.fromLTRB(4, 6, 4, 4) : const EdgeInsets.fromLTRB(20, 6, 20, 0),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(child: CutText(s.client, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppText.s(phone ? 18 : 20, W.w8, ls: -0.4))),
            Hover(
              onTap: () => Navigator.of(ctx).pop('profile'),
              builder: (_, h, _) => Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                child: Row(mainAxisSize: MainAxisSize.min, spacing: 6, children: [
                  Text('Open profile', style: AppText.s(13, W.w7, color: h ? AppColors.linkHover : AppColors.accentText)),
                  AppIcon(AppIcons.next, size: 14, color: h ? AppColors.linkHover : AppColors.accentText),
                ]),
              ),
            ),
          ]),
          Padding(padding: const EdgeInsets.only(top: 2), child: Text(s.when, style: AppText.s(13.5, W.w6, color: AppColors.text2))),
          const SizedBox(height: 10),
          Table(
            columnWidths: const {0: FlexColumnWidth(), 1: FixedColumnWidth(20), 2: FlexColumnWidth()},
            children: [
              TableRow(children: [
                Container(decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.line))), child: kv('Plan', s.plan.isEmpty ? 'No plan yet' : s.plan)),
                const SizedBox(),
                Container(decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.line))), child: kv('Length', '${s.minutes}  min')),
              ]),
              TableRow(children: [
                kv(s.isCall ? 'Where' : 'Place', s.where, extra: s.isCall ? s.callLink : null),
                const SizedBox(),
                kv('Booked by', s.bookedBy.isEmpty ? '—' : s.bookedBy),
              ]),
            ],
          ),
          if (s.note.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(top: 12),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(color: AppColors.sub, borderRadius: AppRadius.all(AppRadius.item)),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 8, children: [
                const Padding(padding: EdgeInsets.only(top: 1), child: AppIcon(AppIcons.doc, size: 16, color: AppColors.muted)),
                Expanded(child: Text(s.note, style: AppText.s(13, W.w5, color: AppColors.text2, h: 1.45))),
              ]),
            ),
        ]),
      );
  Widget doneBtn(BuildContext ctx, {bool expand = false}) => s.done
      ? AppButton('Mark as not done', expand: expand, onPressed: () => Navigator.of(ctx).pop('toggle'))
      : AppButton.primary('Mark as done', icon: AppIcons.check, expand: expand, onPressed: () => Navigator.of(ctx).pop('toggle'));
  Widget cancelBtn(BuildContext ctx) => Hover(
        onTap: () => Navigator.of(ctx).pop('cancel'),
        builder: (_, h, _) => Container(
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(color: h ? AppColors.badBg : null, borderRadius: AppRadius.all(AppRadius.btn)),
          child: Row(mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center, spacing: 6, children: [
            const AppIcon(AppIcons.trash, size: 16, color: AppColors.badText),
            Text('Cancel session', style: AppText.button.copyWith(color: AppColors.badText)),
          ]),
        ),
      );

  if (phone) {
    return showAppSheet<String>(
      context,
      builder: (ctx) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        head(ctx),
        body(ctx),
      ]),
      footer: (ctx) => [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(spacing: 8, children: [
            Expanded(child: AppButton('Reschedule', icon: AppIcons.move, expand: true, onPressed: () => Navigator.of(ctx).pop('move'))),
            Expanded(child: doneBtn(ctx, expand: true)),
          ]),
        ),
        Center(child: cancelBtn(ctx)),
      ],
    );
  }
  return showGeneralDialog<String>(
    context: context,
    barrierDismissible: true,
    barrierLabel: s.client,
    barrierColor: AppColors.scrimModal,
    transitionDuration: const Duration(milliseconds: 140),
    transitionBuilder: (_, a, _, child) => FadeTransition(opacity: a, child: ScaleTransition(scale: Tween(begin: .98, end: 1.0).animate(a), child: child)),
    pageBuilder: (ctx, _, _) => Center(
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: 540,
          margin: const EdgeInsets.all(24),
          decoration: BoxDecoration(color: AppColors.card, borderRadius: AppRadius.all(AppRadius.modal), boxShadow: AppShadows.modal),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            head(ctx),
            Flexible(child: SingleChildScrollView(child: body(ctx))),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 18),
              child: Row(spacing: 8, children: [
                cancelBtn(ctx),
                const Spacer(),
                AppButton('Reschedule', icon: AppIcons.move, onPressed: () => Navigator.of(ctx).pop('move')),
                doneBtn(ctx),
              ]),
            ),
          ]),
        ),
      ),
    ),
  );
}

/// "Cancel this session?" with the Tell the client switch. Returns null (Keep it) or whether to tell the client.
Future<bool?> confirmCancelSession(BuildContext context, CalSession s) {
  var tell = true;
  return showAppModal<bool>(
    context,
    title: 'Cancel this session?',
    body: '${s.client}, ${s.when}. It is removed from the calendar.',
    icon: AppIcons.trash,
    danger: true,
    content: (ctx) => StatefulBuilder(
      builder: (ctx, set) => _Switch(
        title: 'Tell the client',
        sub: 'Push notice and WhatsApp with the time that was cancelled',
        value: tell,
        onChanged: (v) => set(() => tell = v),
      ),
    ),
    actions: (ctx) => [
      AppButton('Keep it', expand: ctx.isPhone, onPressed: () => Navigator.of(ctx).pop()),
      AppButton('Cancel session', kind: BtnKind.danger, expand: ctx.isPhone, onPressed: () => Navigator.of(ctx).pop(tell)),
    ],
  );
}

// ─────────────────────────────── New session / Move session drawer

class _Form extends ChangeNotifier {
  _Form(this.c, this.move) {
    final now = DateTime.now(), today = calDay(now);
    if (move != null) {
      final m = move!;
      client = m.clientId;
      clientName = m.client;
      kind = m.kind;
      week = calMonday(m.start);
      day = m.start.weekday - 1;
      hour = m.start.hour.clamp(calH0, calH1 - 1);
      minute = m.start.minute;
      len.text = '${m.minutes}';
      call = m.isCall;
      place.text = m.place.isEmpty ? c.defaultPlace : m.place;
      link.text = m.callLink;
      note.text = m.note;
    } else {
      // The calendar's picked day when it is still ahead, else tomorrow; 8 am.
      var d = c.dateOf(c.day);
      if (!d.isAfter(today)) d = today.add(const Duration(days: 1));
      week = calMonday(d);
      day = d.weekday - 1;
      place.text = c.defaultPlace;
      len.text = '${kind.minutes}';
    }
  }
  final CalendarController c;
  final CalSession? move;
  String? client, clientName;
  CalKind kind = CalKind.session;
  late DateTime week;
  late int day;
  int hour = 8, minute = 0;
  bool call = false, tell = true, busy = false;
  final len = TextEditingController(), place = TextEditingController(), link = TextEditingController(), note = TextEditingController();
  CalCheck? check;
  Map<String, String> errors = {};
  Timer? _t;
  int _ticket = 0;

  DateTime get date => week.add(Duration(days: day));
  DateTime get start => DateTime(date.year, date.month, date.day, hour, minute);
  int get minutes => int.tryParse(len.text) ?? 0;
  int get from => hour * 60 + minute;
  bool get clash => check?.state == 'clash';

  void set(VoidCallback f, {bool recheck = false}) {
    f();
    errors = {};
    notifyListeners();
    if (recheck) runCheck();
  }

  void pickKind(CalKind k) => set(() {
        kind = k;
        len.text = '${k.minutes}';
        call = k.onCall;
      }, recheck: true);

  void runCheck() {
    _t?.cancel();
    _t = Timer(const Duration(milliseconds: 250), () async {
      final m = minutes;
      if (m < 5 || m > 240) {
        check = null;
        notifyListeners();
        return;
      }
      final t = ++_ticket;
      try {
        final r = await c.check(start, m, exclude: move?.id);
        if (t != _ticket) return;
        check = r;
      } on ApiError {
        if (t != _ticket) return;
        check = null;
      }
      notifyListeners();
    });
  }

  /// "You already have Riya Sharma at 7 – 8 am" / "Outside your working hours (6:30 am – 8 pm)".
  String? get warning {
    if (start.isBefore(DateTime.now()) && (move == null || start != move!.start)) return 'This time has passed';
    final k = check;
    if (k == null) return null;
    if (k.state == 'clash' && k.clashFrom != null && k.clashTo != null) {
      final a = k.clashFrom!, b = k.clashTo!;
      return 'You already have ${k.withName} at ${calRange(calMinutes(a), b.difference(a).inMinutes)}';
    }
    if (k.state == 'outside') {
      final h = k.hours;
      if (h == null) return 'Outside your working hours';
      return 'Outside your working hours (${calRange(h.$1, h.$2 - h.$1)})';
    }
    if (k.state == 'day_off') return 'Outside your working hours (day off)';
    return null;
  }

  bool validate() {
    final e = <String, String>{};
    if (client == null) e['client'] = 'Pick a client.';
    final m = int.tryParse(len.text);
    if (m == null || m < 5 || m > 240) e['minutes'] = 'Enter 5 to 240 minutes.';
    final l = link.text.trim();
    if (call && l.isNotEmpty && !_linkOk(l)) e['call_link'] = 'Enter a call link (meet.google.com/…) or a 10 digit number.';
    if (start.isBefore(DateTime.now().subtract(const Duration(minutes: 5))) && (move == null || start != move!.start)) {
      e['start'] = 'Pick a time from now on.';
    }
    errors = e;
    notifyListeners();
    return e.isEmpty;
  }

  static bool _linkOk(String v) {
    final digits = v.replaceAll(RegExp(r'\D'), '');
    if (RegExp(r'^\+?[0-9 ]{10,15}$').hasMatch(v) && digits.length >= 10) return true;
    return RegExp(r'^(https?://)?[\w-]+(\.[\w-]+)+(/\S*)?$', caseSensitive: false).hasMatch(v);
  }

  @override
  void dispose() {
    _t?.cancel();
    for (final x in [len, place, link, note]) {
      x.dispose();
    }
    super.dispose();
  }
}

/// New session (no [move]) or Move session. Returns the saved session and, for a move, the one before it (Undo).
Future<(CalSession, CalSession?)?> showSessionForm(BuildContext context, CalendarController c, {CalSession? move}) {
  final f = _Form(c, move);
  final clients = c.myClients();
  f.runCheck();
  final phone = context.isPhone;
  final today = calDay(DateTime.now());

  Future<void> save(BuildContext ctx) async {
    if (f.clash || f.busy || !f.validate()) return;
    f.set(() => f.busy = true);
    try {
      final r = await c.save(
        id: move?.id,
        client: f.client!,
        kind: f.kind,
        start: f.start,
        minutes: f.minutes,
        call: f.call,
        place: f.place.text.trim(),
        link: f.link.text.trim(),
        note: f.note.text.trim(),
        tell: f.tell,
      );
      if (ctx.mounted) Navigator.of(ctx).pop((r, move));
    } on ApiError catch (e) {
      f.busy = false;
      f.errors = {for (final x in e.fields.entries) x.key: x.value.first};
      if (f.errors.isEmpty) f.errors = {'start': e.message};
      f.runCheck();
      f.set(() {});
    }
  }

  Widget body(BuildContext ctx) => ListenableBuilder(
        listenable: f,
        builder: (ctx, _) {
          final hint = f.minutes >= 5 && f.minutes <= 240 ? calRange(f.from, f.minutes) : null;
          final startsField = _field(
            'Starts',
            Row(spacing: 8, children: [
              SizedBox(
                width: 100,
                child: AppSelect(calFmt(f.hour * 60), entries: [
                  for (var h = calH0; h < calH1; h++) MenuEntry(calFmt(h * 60), selected: h == f.hour, onTap: () => f.set(() => f.hour = h, recheck: true)),
                ]),
              ),
              // Flexible + scaleDown: the :00 … :45 strip shrinks a little in a narrow drawer instead of overflowing.
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Container(
                height: 36,
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(color: AppColors.sub, borderRadius: AppRadius.all(AppRadius.input)),
                child: Row(mainAxisSize: MainAxisSize.min, spacing: 2, children: [
                  for (final m in const [0, 15, 30, 45])
                    Hover(
                      onTap: () => f.set(() => f.minute = m, recheck: true),
                      builder: (_, h, _) => Container(
                        padding: const EdgeInsets.symmetric(horizontal: 9),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: m == f.minute ? AppColors.card : null,
                          borderRadius: AppRadius.all(6),
                          boxShadow: m == f.minute ? AppShadows.tab : null,
                        ),
                        child: Text(':${m.toString().padLeft(2, '0')}',
                            style: AppText.s(12.5, W.w6, color: m == f.minute || h ? AppColors.text : AppColors.muted)),
                      ),
                    ),
                ]),
              ),
                ),
              ),
            ]),
            error: f.errors['start'],
          );
          final lengthField = _field(
            'Length',
            AppTextField(
              controller: f.len,
              keyboard: TextInputType.number,
              formatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(3)],
              suffix: Text('min', style: AppText.s(14, W.w5, color: AppColors.muted)),
              onChanged: (_) => f.set(() {}, recheck: true),
              error: f.errors['minutes'],
            ),
            hint: f.errors['minutes'] == null ? hint : null,
          );
          final warn = f.warning;
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            _Sec('Who', [
              FutureBuilder<List<CalClient>>(
                future: clients,
                builder: (ctx, snap) {
                  final list = snap.data ?? const <CalClient>[];
                  if (f.client == null && list.isNotEmpty && move == null) {
                    f.client = list.first.id;
                    f.clientName = list.first.name;
                  }
                  final label = f.clientName ?? (snap.hasError ? 'Could not load your clients' : (snap.hasData ? 'No clients yet' : 'Loading…'));
                  return _field(
                    'Client',
                    AppSelect(label, entries: [
                      for (final p in list)
                        MenuEntry(p.name, end: p.goal, selected: p.id == f.client, onTap: () => f.set(() {
                              f.client = p.id;
                              f.clientName = p.name;
                            })),
                    ]),
                    req: true,
                    hint: 'Only clients given to you',
                    error: f.errors['client'],
                  );
                },
              ),
            ]),
            _Sec('Type', [
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final k in CalKind.values)
                  Hover(
                    onTap: () => f.pickKind(k),
                    builder: (_, h, _) => Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppColors.card,
                        borderRadius: AppRadius.all(AppRadius.chip),
                        border: Border.all(color: k == f.kind ? AppColors.accent : (h ? AppColors.lineHover : AppColors.line2)),
                        boxShadow: k == f.kind ? const [BoxShadow(color: AppColors.accentSoft, spreadRadius: 2)] : null,
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, spacing: 6, children: [
                        Container(width: 8, height: 8, decoration: BoxDecoration(color: k.dot, borderRadius: AppRadius.all(2))),
                        Text(k.label, style: AppText.s(12.5, W.w6)),
                        Padding(padding: const EdgeInsets.only(left: 2), child: Text('${k.minutes} min', style: AppText.s(11.5, W.w6, color: AppColors.muted))),
                      ]),
                    ),
                  ),
              ]),
            ]),
            _Sec('When', [
              Row(spacing: phone ? 3 : 6, children: [
                SizedBox(
                  width: phone ? 28 : 30,
                  child: AppIconButton(AppIcons.prev, tooltip: 'Week before', small: true, onPressed: () => f.set(() => f.week = f.week.subtract(const Duration(days: 7)), recheck: true)),
                ),
                for (var i = 0; i < 7; i++)
                  Expanded(
                    child: Builder(builder: (_) {
                      final d = f.week.add(Duration(days: i)), on = i == f.day, past = d.isBefore(today);
                      return Opacity(
                        opacity: past && !on ? .45 : 1,
                        child: Hover(
                          onTap: past ? null : () => f.set(() => f.day = i, recheck: true),
                          builder: (_, h, _) => Container(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            decoration: BoxDecoration(
                              color: on ? AppColors.accent : AppColors.card,
                              borderRadius: AppRadius.all(AppRadius.item),
                              border: Border.all(color: on ? AppColors.accent : (h ? AppColors.lineHover : AppColors.line)),
                            ),
                            child: Column(spacing: 1, children: [
                              Text(calWd[i], style: AppText.s(11, W.w6, color: on ? AppColors.white.withValues(alpha: .8) : AppColors.muted)),
                              Text('${d.day}', style: AppText.s(15, W.w7, color: on ? AppColors.white : AppColors.text)),
                            ]),
                          ),
                        ),
                      );
                    }),
                  ),
                SizedBox(
                  width: phone ? 28 : 30,
                  child: AppIconButton(AppIcons.next, tooltip: 'Week after', small: true, onPressed: () => f.set(() => f.week = f.week.add(const Duration(days: 7)), recheck: true)),
                ),
              ]),
              if (phone) ...[startsField, lengthField]
              else
                Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 12, children: [
                  Expanded(flex: 3, child: startsField),
                  Expanded(flex: 2, child: lengthField),
                ]),
              if (warn != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(color: AppColors.warnBg, borderRadius: AppRadius.all(AppRadius.item)),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 10, children: [
                    const AppIcon(AppIcons.alert, size: 16, color: AppColors.warnText),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 2, children: [
                        Text(warn, style: AppText.s(13, W.w7, color: AppColors.warnText)),
                        Text('Pick another time.', style: AppText.s(12.5, W.w5, color: AppColors.text2)),
                      ]),
                    ),
                  ]),
                )
              else if (f.check?.state == 'free')
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(color: AppColors.okBg, borderRadius: AppRadius.all(AppRadius.item)),
                  child: Row(spacing: 10, children: [
                    const AppIcon(AppIcons.check, size: 16, color: AppColors.okText),
                    Expanded(child: Text('You are free at this time', style: AppText.s(13, W.w6, color: AppColors.okText))),
                  ]),
                ),
            ]),
            _Sec('Where', [
              Align(
                alignment: Alignment.centerLeft,
                child: CalTabs<bool>(items: const [(false, 'In person'), (true, 'Call')], value: f.call, onChanged: (v) => f.set(() => f.call = v)),
              ),
              if (!f.call)
                _field('Place', AppTextField(controller: f.place, placeholder: 'Gym floor', formatters: [LengthLimitingTextInputFormatter(120)]), hint: 'Where they meet')
              else
                _field(
                  'Call link or number',
                  AppTextField(
                    controller: f.link,
                    placeholder: 'meet.google.com/abc-defg-hij',
                    keyboard: TextInputType.url,
                    formatters: [LengthLimitingTextInputFormatter(200)],
                    onChanged: (_) => f.set(() {}),
                  ),
                  hint: 'Optional',
                  error: f.errors['call_link'],
                ),
            ]),
            _Sec('Note', last: true, [
              _field(
                null,
                AppTextField(
                  controller: f.note,
                  placeholder: 'e.g. Check the left shoulder first',
                  maxLines: 4,
                  minLines: 4,
                  formatters: [LengthLimitingTextInputFormatter(300)],
                ),
                hint: 'Optional. Only you and Vimal see it.',
              ),
              _Switch(
                title: 'Tell the client',
                sub: 'Push notice and WhatsApp with the time and place',
                value: f.tell,
                onChanged: (v) => f.set(() => f.tell = v),
              ),
            ]),
          ]);
        },
      );

  String foot() => '${calDayLabel(f.date)} · ${f.minutes >= 5 ? calRange(f.from, f.minutes) : calFmt(f.from)}';
  Widget saveBtn(BuildContext ctx, {bool expand = false}) => ListenableBuilder(
        listenable: f,
        builder: (_, _) => AppButton.primary(move == null ? 'Create session' : 'Move session',
            icon: AppIcons.check, expand: expand, loading: f.busy, onPressed: f.clash ? null : () => save(ctx)),
      );
  final noteText = ListenableBuilder(
    listenable: f,
    builder: (_, _) => CutText(foot(), maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(12.5, W.w6, color: AppColors.muted)),
  );

  return showAppDrawer<(CalSession, CalSession?)>(
    context,
    title: move == null ? 'New session' : 'Move session',
    sub: move == null ? 'Book one of your clients' : '${move.client} · now ${move.when}',
    icon: AppIcons.calStat,
    builder: body,
    footer: (ctx) => phone
        ? [
            noteText,
            Row(spacing: 8, children: [
              Expanded(child: AppButton('Cancel', expand: true, onPressed: () => Navigator.of(ctx).pop())),
              Expanded(child: saveBtn(ctx, expand: true)),
            ]),
          ]
        : [
            Expanded(child: noteText),
            AppButton('Cancel', onPressed: () => Navigator.of(ctx).pop()),
            saveBtn(ctx),
          ],
  ).whenComplete(() => disposeLater([f]));
}

// ─────────────────────────────── My working hours

/// Every weekday on / off with from – to. Returns true when saved.
Future<bool> showWorkingHours(BuildContext context, CalendarController c) async {
  final days = [for (final d in (c.hours.isEmpty ? [for (var i = 0; i < 7; i++) CalAvDay(i, i < 6, 390, 1200)] : c.hours)) d.copy()];
  final state = ValueNotifier(0);
  var busy = false;
  String? error;
  final times = [for (var m = 5 * 60; m <= 23 * 60 + 30; m += 30) m];

  Future<void> save(BuildContext ctx) async {
    final bad = days.where((d) => d.open && d.to <= d.from).toList();
    if (bad.isNotEmpty) {
      error = '${calWdLong[bad.first.weekday]}: the end must be after the start.';
      state.value++;
      return;
    }
    busy = true;
    error = null;
    state.value++;
    try {
      await c.saveHours(days);
      if (ctx.mounted) Navigator.of(ctx).pop(true);
    } on ApiError catch (e) {
      busy = false;
      error = e.fields.values.expand((v) => v).firstOrNull ?? e.message;
      state.value++;
    }
  }

  final r = await showAppDrawer<bool>(
    context,
    title: 'My working hours',
    sub: 'Vimal sees them when he books for you',
    icon: AppIcons.clockAlt,
    builder: (ctx) => ValueListenableBuilder(
      valueListenable: state,
      builder: (ctx, _, _) {
        final phone = ctx.isPhone;
        final n = days.where((d) => d.open).length;
        return _Sec('Working hours, week after week', sub: '$n working ${n == 1 ? 'day' : 'days'}. The calendar shades the rest, and a session outside them shows a warning.', last: true, [
          Column(children: [
            for (final d in days)
              Container(
                constraints: const BoxConstraints(minHeight: 50),
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(border: d.weekday == 0 ? null : const Border(top: BorderSide(color: AppColors.line))),
                child: Row(spacing: phone ? 8 : 12, children: [
                  SizedBox(
                    width: phone ? 84 : 96,
                    child: Text(calWdLong[d.weekday], style: AppText.s(13.5, W.w6, color: d.open ? AppColors.text : AppColors.muted)),
                  ),
                  AppToggle(
                    value: d.open,
                    onChanged: (v) {
                      d.open = v;
                      if (v && d.to <= d.from) {
                        d.from = 420;
                        d.to = 1260;
                      }
                      state.value++;
                    },
                  ),
                  const Spacer(),
                  if (d.open) ...[
                    _SmSelect(calFmt(d.from), width: phone ? 92 : 112, entries: [
                      for (final m in times)
                        MenuEntry(calFmt(m), selected: m == d.from, onTap: () {
                          d.from = m;
                          state.value++;
                        }),
                    ]),
                    Text('to', style: AppText.s(12.5, W.w5, color: AppColors.muted)),
                    _SmSelect(calFmt(d.to), width: phone ? 92 : 112, entries: [
                      for (final m in times)
                        MenuEntry(calFmt(m), selected: m == d.to, onTap: () {
                          d.to = m;
                          state.value++;
                        }),
                    ]),
                  ] else
                    Text('Day off', style: AppText.s(13, W.w5, color: AppColors.muted)),
                ]),
              ),
          ]),
          if (error != null) Text(error!, style: AppText.s(12.5, W.w6, color: AppColors.badText)),
        ]);
      },
    ),
    footer: (ctx) {
      final note = CutText('Booked sessions stay as they are', maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(12.5, W.w6, color: AppColors.muted));
      final saveBtn = ValueListenableBuilder(
        valueListenable: state,
        builder: (_, _, _) => AppButton.primary('Save availability', icon: AppIcons.check, expand: ctx.isPhone, loading: busy, onPressed: () => save(ctx)),
      );
      return ctx.isPhone
          ? [
              note,
              Row(spacing: 8, children: [
                Expanded(child: AppButton('Cancel', expand: true, onPressed: () => Navigator.of(ctx).pop())),
                Expanded(child: saveBtn),
              ]),
            ]
          : [Expanded(child: note), AppButton('Cancel', onPressed: () => Navigator.of(ctx).pop()), saveBtn];
    },
  );
  disposeLater([state]);
  return r == true;
}
