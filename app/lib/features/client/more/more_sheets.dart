import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/services.dart';
import '../../../core/api/api_error.dart';
import '../../../core/icons/app_icons.dart';
import '../../../core/theme/theme.dart';
import '../../../core/widgets/client.dart';
import '../../../core/widgets/hover.dart';
import '../../../core/widgets/overlays.dart';
import '../../auth/sheets.dart' show showTermsSheet;
import '../home/home_model.dart' show clock, dayShort;
import '../home/home_parts.dart';
import '../progress/progress_sheets.dart' show pxFooter;
import 'more_model.dart';
import 'more_parts.dart';

/// Sheets of the More board. On wide screens [showAppSheet] makes them centred cards.

String moDate(DateTime d) => DateFormat('d MMM y').format(d);

/// "1 Sep – 23 Nov 2026".
String moRange(DateTime a, DateTime b) =>
    a.year == b.year ? '${DateFormat('d MMM').format(a)} – ${DateFormat('d MMM y').format(b)}' : '${moDate(a)} – ${moDate(b)}';

/// "+919820111234" → "+91 98201 11234".
String moPhone(String p) {
  if (p.isEmpty) return '—';
  final m = RegExp(r'^\+91(\d{5})(\d{5})$').firstMatch(p);
  return m == null ? p : '+91 ${m[1]} ${m[2]}';
}

/// "Every Sunday, 6:00 pm".
/// "Every day · sent today" / "Every day · reminder at 9:00 pm".
String moDailyLine(MoData d) => d.dailySent ? 'Every day · sent today' : 'Every day · reminder at ${d.dailyReminder}';

String moCheckinWhen(MoData d) => 'Every Sunday, ${minClock(hmsToMin(d.checkinTime))}';

void moFailed(BuildContext context, [Object? e]) => showToast(context, 'Could not save',
    sub: e is ApiError && e.offline ? 'You are offline. Try again when you are back online.' : (e is ApiError ? e.message : 'Try again'),
    kind: ToastKind.err);

/// A PNG of the page under the sheet, as a data URL (Report a problem → Attach a screenshot).
Future<String?> moCapture(GlobalKey key) async {
  try {
    final b = key.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (b == null) return null;
    final img = await b.toImage(pixelRatio: 1);
    final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
    if (bytes == null) return null;
    return 'data:image/png;base64,${base64Encode(bytes.buffer.asUint8List())}';
  } catch (_) {
    return null;
  }
}

Widget _lbl(String t) => Text(t, style: AppText.s(12, W.w7, color: AppColors.text2));

// ─────────────────────────────── My trainer → Details

Future<void> showCoachSheet(BuildContext context, MoreController c) {
  final d = c.data!;
  final p = d.program, s = d.session, m = d.meal;
  final days = [for (final i in (p?['training_days'] as List? ?? const [])) DateFormat('EEE').format(DateTime(2024, 1, 1 + (i as int)))];
  DateTime? start = s == null ? null : DateTime.parse('${s['start']}').toLocal();
  String sessionLine() {
    if (s == null || start == null) return 'No session booked';
    final today = DateUtils.dateOnly(DateTime.now());
    final day = DateUtils.isSameDay(start, today) ? 'Today' : dayShort(start);
    final where = s['is_call'] == true ? 'Call' : ('${s['place']}'.isEmpty ? 'At the gym' : '${s['place']}');
    return '$day, ${clock(start)} · $where · ${s['minutes']} min';
  }

  final rows = [
    ('Next session', sessionLine()),
    if (days.isNotEmpty) ('Training days', days.join(', ')),
    ('Daily check-in', moDailyLine(d)),
    ('Weekly check-in', moCheckinWhen(d)),
    ('Next check-in', '${dayShort(d.nextCheckin)} · week ${d.checkinWeek}'),
    ('Check-in reply', '${d.checkin['reply'] ?? ''}'),
    if (p != null) ('Program', '${p['name']} · week ${p['week']} of ${p['weeks']}'),
    if (m != null) ('Meal plan', '${NumberFormat.decimalPattern('en_IN').format(m['kcal'])} kcal · ${m['diet']}'),
    if (p != null) ('Plan ends', dayShort(DateTime.parse('${p['end']}'))),
  ];
  return showAppSheet(
    context,
    title: d.coachName,
    sub: 'Your trainer${p == null ? '' : ' · ${p['name']}'}',
    footerStretch: true,
    builder: (_) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 10, children: [
      moKvs(rows, pad: 8),
      moCap('Questions about your plan? Add them to your weekly check-in or ask ${d.coachFirst} at your next session.'),
    ]),
    footer: pxFooter((ctx) => [
      CaButton('Add to calendar', kind: CaBtnKind.out, icon: AppIcons.calendarAlt, onPressed: () async {
        Navigator.of(ctx).pop();
        if (s == null || start == null) {
          showToast(context, 'No session booked yet', sub: '${d.coachFirst} books your sessions', kind: ToastKind.info);
          return;
        }
        final end = DateTime.parse('${s['end']}').toUtc();
        String f(DateTime t) => DateFormat("yyyyMMdd'T'HHmmss'Z'").format(t.toUtc());
        final uri = Uri.https('calendar.google.com', '/calendar/render', {
          'action': 'TEMPLATE',
          'text': 'Session with ${d.coachFirst}',
          'dates': '${f(start)}/${f(end)}',
          'details': 'Train With Vimal',
          'location': '${s['place']}',
        });
        await launchUrl(uri, mode: LaunchMode.externalApplication).catchError((_) => false);
        if (context.mounted) {
          showToast(context, 'Session added to your calendar', sub: '${dayShort(start)} · ${clock(start)} · reminder 1 h before', kind: ToastKind.ok);
        }
      }),
    ]),
  );
}

// ─────────────────────────────── Edit profile

Future<void> showEditProfileSheet(BuildContext context, MoreController c) {
  final d = c.data!;
  final local = d.phone.startsWith('+91') ? moPhone(d.phone).substring(4) : d.phone;
  final name = TextEditingController(text: d.name), email = TextEditingController(text: d.email);
  final phone = TextEditingController(text: local), city = TextEditingController(text: d.city);
  String cmText(double? v) => v == null ? '' : (v == v.roundToDouble() ? '${v.toInt()}' : '$v');
  final height = TextEditingController(text: cmText(d.heightCm));
  final dob = ValueNotifier<DateTime?>(d.dob);
  final errors = ValueNotifier<Map<String, String>>({});
  final busy = ValueNotifier(false);
  final listen = Listenable.merge([dob, errors, busy]);

  String norm(String p) => p.replaceAll(RegExp(r'[^0-9+]'), '');
  Future<void> save(BuildContext ctx) async {
    final ch = <String, dynamic>{};
    if (name.text.trim() != d.name) ch['full_name'] = name.text.trim();
    if (email.text.trim().toLowerCase() != d.email.toLowerCase()) ch['email'] = email.text.trim();
    final ph = norm(phone.text);
    if (ph.isNotEmpty && (ph.startsWith('+') ? ph : '+91$ph') != d.phone) ch['phone'] = ph.startsWith('+') ? ph : '+91$ph';
    if (city.text.trim() != d.city) ch['city'] = city.text.trim();
    final hText = height.text.trim().replaceAll(',', '.');
    final h = hText.isEmpty ? null : double.tryParse(hText);
    if (hText.isNotEmpty && (h == null || h < 100 || h > 250)) {
      errors.value = {'height': 'Enter your height in cm, between 100 and 250'};
      return;
    }
    if (h != d.heightCm) ch['height_cm'] = h;
    if (dob.value != d.dob) ch['date_of_birth'] = dob.value == null ? null : DateFormat('yyyy-MM-dd').format(dob.value!);
    if (ch.isEmpty) {
      Navigator.of(ctx).pop();
      showToast(context, 'Nothing changed', sub: 'Your profile is the same', kind: ToastKind.info);
      return;
    }
    final before = <String, dynamic>{
      if (ch.containsKey('full_name')) 'full_name': d.name,
      if (ch.containsKey('phone')) 'phone': d.phone,
      if (ch.containsKey('city')) 'city': d.city,
      if (ch.containsKey('height_cm')) 'height_cm': d.heightCm,
      if (ch.containsKey('date_of_birth')) 'date_of_birth': d.dob == null ? null : DateFormat('yyyy-MM-dd').format(d.dob!),
    };
    busy.value = true;
    try {
      await c.saveProfile(ch);
    } on ApiError catch (e) {
      busy.value = false;
      const keys = {'full_name': 'name', 'email': 'email', 'phone': 'phone', 'city': 'city', 'date_of_birth': 'dob', 'height_cm': 'height'};
      final f = {for (final MapEntry(:key, :value) in e.fields.entries) keys[key] ?? key: value.first};
      if (f.isEmpty) {
        if (context.mounted) moFailed(context, e);
      }
      errors.value = f;
      return;
    }
    if (ctx.mounted) Navigator.of(ctx).pop();
    if (!context.mounted) return;
    final newEmail = ch['email'] as String?;
    Future<void> undo() async {
      try {
        if (newEmail != null) await c.cancelEmail();
        if (before.isNotEmpty) await c.saveProfile(before);
      } catch (e) {
        if (context.mounted) moFailed(context, e);
      }
    }

    if (newEmail != null) {
      showToast(context, 'Verify your new email', sub: 'We sent a link to $newEmail', kind: ToastKind.info, action: 'Undo', onAction: undo);
    } else {
      showToast(context, 'Profile saved', sub: c.data?.name ?? '', kind: ToastKind.ok, action: 'Undo', onAction: undo);
    }
  }

  return showAppSheet(
    context,
    title: 'Edit profile',
    sub: '${d.coachFirst} sees this name, number and email',
    listen: listen,
    footerStretch: true,
    builder: (ctx) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 12, children: [
      CaField(label: 'Full name', controller: name, error: errors.value['name'], autofill: const [AutofillHints.name]),
      CaField(label: 'Email', controller: email, error: errors.value['email'], keyboard: TextInputType.emailAddress),
      CaField(label: 'Mobile', controller: phone, leading: '+91', error: errors.value['phone'], keyboard: TextInputType.phone),
      CaField(label: 'City', controller: city, error: errors.value['city']),
      CaField(
        label: 'Height',
        controller: height,
        hint: 'e.g. 162',
        error: errors.value['height'],
        keyboard: const TextInputType.numberWithOptions(decimal: true),
        trailing: Padding(padding: const EdgeInsets.only(right: 12), child: Text('cm', style: AppText.s(13.5, W.w6, color: AppColors.muted))),
      ),
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 5, children: [
        Text('Date of birth', style: AppText.s(12.5, W.w7, color: AppColors.text2)),
        Hover(
          onTap: () async {
            final now = DateTime.now();
            final v = await showDatePicker(
              context: ctx,
              initialDate: dob.value ?? DateTime(now.year - 25),
              firstDate: DateTime(now.year - 100),
              lastDate: DateTime(now.year - 10, now.month, now.day),
            );
            if (v != null) dob.value = v;
          },
          builder: (_, h, _) => Container(
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            alignment: Alignment.centerLeft,
            decoration: BoxDecoration(color: AppColors.white, borderRadius: BorderRadius.circular(10), border: Border.all(color: h ? AppColors.accent : AppColors.line2)),
            child: Text(dob.value == null ? 'Pick a date' : moDate(dob.value!),
                style: AppText.s(14.5, dob.value == null ? W.w5 : W.w6, color: dob.value == null ? AppColors.muted : AppColors.text)),
          ),
        ),
        if (errors.value['dob'] != null) Text(errors.value['dob']!, style: AppText.s(12.5, W.w6, color: AppColors.badText)),
      ]),
      moCap('A new email is used only after you open the verification link we send to it.'),
    ]),
    footer: pxFooter((ctx) => [
      CaButton('Cancel', kind: CaBtnKind.out, onPressed: () => Navigator.of(ctx).pop()),
      CaButton('Save', loading: busy.value, onPressed: () => save(ctx)),
    ]),
  );
}

// ─────────────────────────────── Notification (from the list)

Future<void> showNoticeSheet(BuildContext context, MoreController c, MoNotice n, String when) {
  final (ic, tone) = noticeLook(n.event);
  final link = noticeLink(n.event, n.route);
  return showAppSheet(
    context,
    title: n.title,
    sub: when,
    footerStretch: true,
    builder: (_) => Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 12, children: [
      MoIc(moIcon(ic), tone: moTone(tone)),
      Expanded(child: Text(n.body.isEmpty ? n.title : n.body, style: AppText.s(14, W.w4, h: 1.5))),
    ]),
    footer: (ctx) => [
      Row(spacing: 8, children: [
        Expanded(
          child: CaButton('Mark as unread', kind: CaBtnKind.out, icon: AppIcons.bell, onPressed: () {
            Navigator.of(ctx).pop();
            c.markUnread(n);
            showToast(context, 'Marked as unread', sub: n.title, kind: ToastKind.info);
          }),
        ),
        Expanded(
          child: _DangerOutline('Delete', icon: AppIcons.trash, onTap: () {
            Navigator.of(ctx).pop();
            c.removeNotice(n);
            var undone = false;
            showToast(context, 'Notification deleted', sub: n.title, kind: ToastKind.del, action: 'Undo', onAction: () {
              undone = true;
              c.restoreNotice(n);
            });
            Future.delayed(const Duration(seconds: 7), () {
              if (!undone) c.deleteNotice(n);
            });
          }),
        ),
      ]),
      if (link != null)
        CaButton(link.$2, trailingIcon: AppIcons.chevronRight, onPressed: () {
          Navigator.of(ctx).pop();
          context.go(link.$1);
        }),
    ],
  );
}

/// `ca-btn out sm mo-del`: outline button with red text.
class _DangerOutline extends StatelessWidget {
  const _DangerOutline(this.label, {required this.icon, required this.onTap, this.small = false});
  final String label;
  final AppIconData icon;
  final VoidCallback onTap;
  final bool small;
  @override
  Widget build(BuildContext context) {
    final web = CaWeb.of(context);
    return Semantics(
      button: true,
      label: label,
      child: Hover(
        onTap: onTap,
        builder: (_, h, _) => Container(
          height: small ? 34 : (web ? 40 : 44),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(color: h ? AppColors.badBg : AppColors.white, borderRadius: BorderRadius.circular(small ? 10 : 12), border: Border.all(color: AppColors.line)),
          child: Row(mainAxisSize: small ? MainAxisSize.min : MainAxisSize.max, mainAxisAlignment: MainAxisAlignment.center, spacing: 6, children: [
            AppIcon(icon, size: 15, color: AppColors.badText),
            Text(label, style: AppText.s(small ? 13 : 14, W.w7, color: AppColors.badText)),
          ]),
        ),
      ),
    );
  }
}

// ─────────────────────────────── Notification settings

Future<void> showReminderSheet(BuildContext context, MoreController c) {
  final coach = c.data?.coachFirst ?? 'Your coach';
  void flip(String key, String title, String sub) {
    final r = c.data!.reminders;
    final was = r[key] == true;
    c.setReminders({key: !was});
    showToast(context, '$title ${was ? 'off' : 'on'}', sub: was ? 'You will not get these' : sub, kind: was ? ToastKind.info : ToastKind.ok, action: 'Undo', onAction: () => c.setReminders({key: was}));
  }

  return showAppSheet(
    context,
    title: 'Notification settings',
    sub: 'Choose what you want to be reminded about',
    listen: c,
    footerStretch: true,
    builder: (_) {
      final r = c.data!.reminders;
      final qOn = r['quiet_on'] == true;
      final from = hmsToMin('${r['quiet_from'] ?? '22:00:00'}'), to = hmsToMin('${r['quiet_to'] ?? '07:00:00'}');
      Widget time(String l, String key, int v) => Container(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
            decoration: BoxDecoration(color: AppColors.white, borderRadius: BorderRadius.circular(10), border: Border.all(color: AppColors.line)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 4, children: [
              Text(l, style: AppText.s(12, W.w7, color: AppColors.text2)),
              Row(children: [
                _RoundStep(AppIcons.minus, 'Earlier', () => c.setReminders({key: minToHms((v + 1410) % 1440)})),
                Expanded(child: Text(minClock(v), textAlign: TextAlign.center, style: AppText.s(15, W.w8))),
                _RoundStep(AppIcons.plus, 'Later', () => c.setReminders({key: minToHms((v + 30) % 1440)})),
              ]),
            ]),
          );
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 10, children: [
        Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (final (i, (key, icon, tone, title, sub)) in moReminderKeys.indexed)
            MoToggleRow(
              first: i == 0,
              icon: moIcon(icon),
              tone: moTone(tone),
              title: title,
              sub: sub.replaceAll('{coach}', coach),
              on: r[key] == true,
              onTap: () => flip(key, title, sub.replaceAll('{coach}', coach)),
            ),
        ]),
        Container(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
          decoration: BoxDecoration(color: AppColors.caWebBg, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.line)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 8, children: [
            MoToggleRow(
              line: false,
              icon: AppIcons.moon,
              tone: ChTone.purple,
              title: 'Quiet hours',
              sub: qOn ? '${minClock(from)} – ${minClock(to)} · reminders wait' : 'Off · reminders at any time',
              on: qOn,
              onTap: () => c.setReminders({'quiet_on': !qOn}),
            ),
            if (qOn)
              Row(spacing: 8, children: [
                Expanded(child: time('From', 'quiet_from', from)),
                Expanded(child: time('To', 'quiet_to', to)),
              ]),
          ]),
        ),
        moCap('Your choices are saved as you change them. Reminders on your phone arrive in the Train With Vimal app.'),
      ]);
    },
    footer: pxFooter((ctx) => [
      CaButton('Reset to recommended', kind: CaBtnKind.out, onPressed: () {
        final before = Map<String, dynamic>.of(c.data!.reminders);
        c.resetReminders();
        showToast(context, 'Settings reset', sub: 'Recommended reminders are on', kind: ToastKind.ok, action: 'Undo', onAction: () => c.setReminders(before));
      }),
      CaButton('Done', onPressed: () => Navigator.of(ctx).pop()),
    ], flex: const [3, 2]),
  );
}

class _RoundStep extends StatelessWidget {
  const _RoundStep(this.icon, this.label, this.onTap);
  final AppIconData icon;
  final String label;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: label,
        child: Hover(
          onTap: onTap,
          builder: (_, h, _) => Container(
            width: 30,
            height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: h ? AppColors.outlineHover : AppColors.white, shape: BoxShape.circle, border: Border.all(color: AppColors.line)),
            child: AppIcon(icon, size: 14, color: AppColors.text2),
          ),
        ),
      );
}

// ─────────────────────────────── Units & preferences

Future<void> showUnitsSheet(BuildContext context, MoreController c) {
  final me = Services.session.me!;
  final was = {'unit_weight': me.unitWeight, 'unit_length': me.unitLength, 'unit_water': me.unitWater, 'week_start': me.weekStart, 'theme': me.theme};
  final draft = ValueNotifier(Map<String, String>.of(was));
  const groups = [
    ('Weight', 'unit_weight', [('kg', 'kg'), ('lb', 'lb')]),
    ('Height and measurements', 'unit_length', [('cm', 'cm'), ('in', 'in')]),
    ('Water', 'unit_water', [('l', 'litres'), ('oz', 'fl oz')]),
    ('Week starts on', 'week_start', [('mon', 'Monday'), ('sun', 'Sunday')]),
    ('Theme', 'theme', [('light', 'Light'), ('dark', 'Dark'), ('system', 'Like my phone')]),
  ];
  final d = c.data!;
  final kg = (d.goal?['now_kg'] as num?)?.toDouble();
  final water = (d.meal?['water_ml'] as num?)?.toInt() ?? 3000;
  return showAppSheet(
    context,
    title: 'Units & preferences',
    sub: 'How numbers and weeks show in the app',
    listen: draft,
    footerStretch: true,
    builder: (_) {
      final v = draft.value;
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 12, children: [
        for (final (label, key, opts) in groups)
          Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 6, children: [
            _lbl(label),
            MoSeg(
              options: [for (final o in opts) o.$2],
              index: opts.indexWhere((o) => o.$1 == v[key]).clamp(0, opts.length - 1),
              onPick: (i) => draft.value = {...v, key: opts[i].$1},
            ),
          ]),
        Container(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
          decoration: BoxDecoration(color: AppColors.caWebBg, borderRadius: BorderRadius.circular(10), border: Border.all(color: AppColors.line)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Padding(padding: const EdgeInsets.only(top: 6), child: Text('PREVIEW', style: AppText.s(11, W.w7, color: AppColors.muted, ls: 0.55))),
            moKvs([
              if (kg != null) ('Your weight', moKg(kg, v['unit_weight']!)),
              ('Your height', moHeight(d.heightCm, v['unit_length']!)),
              ('Water goal', moWater(water, v['unit_water']!)),
            ], pad: 8),
          ]),
        ),
        moCap('${d.coachFirst} still sees your numbers in the units he uses.'),
      ]);
    },
    footer: pxFooter((ctx) => [
      CaButton('Cancel', kind: CaBtnKind.out, onPressed: () => Navigator.of(ctx).pop()),
      CaButton('Save', onPressed: () {
        final v = draft.value;
        Navigator.of(ctx).pop();
        final ch = {for (final k in v.keys) if (v[k] != was[k]) k: v[k]};
        if (ch.isEmpty) {
          showToast(context, 'Nothing changed', kind: ToastKind.info);
          return;
        }
        c.setPrefs(ch);
        final bits = [
          if (kg != null) moKg(kg, v['unit_weight']!),
          moHeight(d.heightCm, v['unit_length']!),
          'week starts ${v['week_start'] == 'sun' ? 'Sunday' : 'Monday'}',
        ];
        showToast(context, 'Preferences saved', sub: bits.join(' · '), kind: ToastKind.ok, action: 'Undo',
            onAction: () => c.setPrefs({for (final k in ch.keys) k: was[k]}));
      }),
    ]),
  );
}

// ─────────────────────────────── Privacy & data, Delete account

Future<void> showPrivacySheet(BuildContext context, MoreController c) {
  final d = c.data!;
  final dl = ValueNotifier('idle'); // idle | prep | sent
  return showAppSheet(
    context,
    title: 'Privacy & data',
    sub: 'Your data belongs to you',
    listen: Listenable.merge([dl, Services.session]),
    builder: (ctx) {
      final me = Services.session.me!;
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 12, children: [
        Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 4, children: [
          Text('WHO CAN SEE YOUR DATA', style: AppText.s(11, W.w7, color: AppColors.muted, ls: 0.55)),
          moKvs([('${d.coachFirst}, your coach', me.sharePhotos ? 'All your logs and photos' : 'All your logs, no new photos'), ('Gym admin', 'Profile and plan dates')], pad: 8),
        ]),
        Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          MoToggleRow(
            first: true,
            title: 'Share progress photos with ${d.coachFirst}',
            sub: 'Turn off to keep new photos only with you',
            on: me.sharePhotos,
            onTap: () {
              final was = me.sharePhotos;
              c.setPrefs({'share_photos': !was});
              showToast(context, was ? 'Photos are private now' : '${d.coachFirst} can see your photos',
                  sub: was ? 'New photos stay with you' : 'Check-in photos go to ${d.coachFirst}', kind: ToastKind.info, action: 'Undo',
                  onAction: () => c.setPrefs({'share_photos': was}));
            },
          ),
          MoToggleRow(
            title: 'Help improve the app',
            sub: 'Send anonymous usage data, never your logs',
            on: me.usageData,
            onTap: () => c.setPrefs({'usage_data': !me.usageData}),
          ),
        ]),
        _box(
          title: 'Download my data',
          text: 'A ZIP with your profile, workouts, food logs, check-ins and photos. We email the link to ${d.email.isEmpty ? 'your email' : d.email}.',
          action: Opacity(
            opacity: dl.value == 'prep' ? .5 : 1,
            child: chSm(dl.value == 'prep' ? 'Preparing your file…' : (dl.value == 'sent' ? 'Sent · send again' : 'Download my data'), () async {
              if (dl.value == 'prep') return;
              dl.value = 'prep';
              showToast(context, 'Preparing your data', sub: 'This takes a few seconds', kind: ToastKind.info);
              try {
                final to = await c.exportData();
                dl.value = 'sent';
                if (context.mounted) showToast(context, 'Your data is on its way', sub: 'Download link sent to $to', kind: ToastKind.ok);
              } catch (e) {
                dl.value = 'idle';
                if (context.mounted) moFailed(context, e);
              }
            }, icon: AppIcons.downloadAlt),
          ),
        ),
        _box(
          bad: true,
          title: 'Delete my account',
          text: 'Erases everything you logged. You get 14 days to change your mind.',
          action: _DangerOutline('Delete account', small: true, icon: AppIcons.trash, onTap: () {
            Navigator.of(ctx).pop();
            showDeleteSheet(context, c);
          }),
        ),
      ]);
    },
  );
}

Widget _box({required String title, required String text, required Widget action, bool bad = false}) => Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: bad ? AppColors.moBadBox : AppColors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: bad ? AppColors.moBadLine : AppColors.line)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 4, children: [
        Text(title, style: AppText.s(14, W.w7)),
        Padding(padding: const EdgeInsets.only(bottom: 4), child: Text(text, style: AppText.s(12.5, W.w4, color: AppColors.muted, h: 1.4))),
        action,
      ]),
    );

Future<void> showDeleteSheet(BuildContext context, MoreController c) {
  final day = DateTime.now().add(const Duration(days: 14));
  final ok = ValueNotifier(false);
  final typed = TextEditingController();
  final busy = ValueNotifier(false);
  final coach = c.data?.coachFirst ?? 'Your coach';
  return showAppSheet(
    context,
    title: 'Delete your account?',
    sub: 'This is permanent after 14 days',
    listen: Listenable.merge([ok, typed, busy]),
    footerStretch: true,
    builder: (_) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 10, children: [
      for (final p in ['Your workouts, food logs, check-ins and photos are erased', '$coach can no longer see your progress or plan', 'Log in within 14 days to cancel'])
        Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 10, children: [
          Container(
            width: 20,
            height: 20,
            alignment: Alignment.center,
            decoration: const BoxDecoration(color: AppColors.badBg, shape: BoxShape.circle),
            child: const AppIcon(AppIcons.close, size: 11, color: AppColors.badText, stroke: 2.8),
          ),
          Expanded(child: Text(p, style: AppText.s(13.5, W.w4, h: 1.4))),
        ]),
      Container(height: 1, color: AppColors.line),
      CaCheckRow(on: ok.value, onTap: () => ok.value = !ok.value, title: 'I understand', sub: 'My logs, check-ins and photos are erased on ${dayShort(day)}.'),
      CaField(label: 'Type DELETE to confirm', controller: typed, hint: 'Tap to type'),
    ]),
    footer: pxFooter((ctx) {
      final ready = ok.value && typed.text.trim().toUpperCase() == 'DELETE';
      return [
        CaButton('Keep my account', kind: CaBtnKind.out, onPressed: () => Navigator.of(ctx).pop()),
        Opacity(
          opacity: ready ? 1 : .45,
          child: _DangerSolid('Delete my account', loading: busy.value, onTap: () async {
            if (!ready || busy.value) return;
            busy.value = true;
            try {
              await c.requestDelete();
            } catch (e) {
              busy.value = false;
              if (context.mounted) moFailed(context, e);
              return;
            }
            if (ctx.mounted) Navigator.of(ctx).pop();
            if (context.mounted) {
              showToast(context, 'Account deletion on ${dayShort(day)}', sub: 'Log in before then to cancel', kind: ToastKind.warn, action: 'Undo', onAction: () => c.cancelDelete());
            }
          }),
        ),
      ];
    }),
  );
}

class _DangerSolid extends StatelessWidget {
  const _DangerSolid(this.label, {required this.onTap, this.loading = false});
  final String label;
  final VoidCallback onTap;
  final bool loading;
  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: label,
        child: Hover(
          onTap: onTap,
          builder: (_, h, _) => Container(
            height: CaWeb.of(context) ? 40 : 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: h ? AppColors.badText : AppColors.red, borderRadius: BorderRadius.circular(12)),
            child: loading
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.white))
                : Text(label, style: AppText.s(14.5, W.w7, color: AppColors.white)),
          ),
        ),
      );
}

// ─────────────────────────────── Help & about, Report a problem

const _faq = [
  ('How do I change my workout or meal plan?', 'Your plan is set by {coach}. Tell him what you want changed in your weekly check-in, or talk to him at your next session.'),
  ('Why did I not get a reminder?', 'Check Notification settings and quiet hours. Notifications must also be allowed for the app in your phone settings.'),
  ('How do I switch kg to lb?', 'Open Units & preferences on the More page. {coach} still sees your numbers in the units he uses.'),
  ('What happens when my program ends?', '{program} ends on {end}. {coach} sets your next plan before that and it shows up in Train.'),
];

class _Hp extends ChangeNotifier {
  int open = -1;
  bool report = false, attach = false, busy = false;
  String? cat;
  final text = TextEditingController();
  _Hp() {
    text.addListener(notifyListeners);
  }
  void set(void Function() f) {
    f();
    notifyListeners();
  }
}

Future<void> showHelpAboutSheet(BuildContext context, MoreController c, {String? screenshot, String page = ''}) {
  final d = c.data!;
  final s = _Hp();
  final p = d.program;
  final coach = d.coachFirst;
  String fill(String t) => t
      .replaceAll('{coach}', coach)
      .replaceAll('{program}', p == null ? 'Your program' : '${p['name']}')
      .replaceAll('{end}', p == null ? 'its last day' : dayShort(DateTime.parse('${p['end']}')));
  const cats = [('broken', 'Something is broken'), ('numbers', 'Wrong numbers'), ('idea', 'An idea')];
  final phone = '${d.gym['phone'] ?? ''}';

  Future<void> send(BuildContext ctx) async {
    if (s.cat == null || s.text.text.trim().length < 3 || s.busy) return;
    s.set(() => s.busy = true);
    try {
      await c.report(s.cat!, s.text.text.trim(), screenshot: s.attach ? screenshot : null, page: page);
    } catch (e) {
      s.set(() => s.busy = false);
      if (context.mounted) moFailed(context, e);
      return;
    }
    if (ctx.mounted) Navigator.of(ctx).pop();
    if (context.mounted) showToast(context, 'Thanks, report sent', sub: 'The gym team replies by email within 2 days', kind: ToastKind.ok);
  }

  Widget row(AppIconData icon, String title, String sub, VoidCallback onTap, {bool first = false}) =>
      MoMenuRow(first: first, icon: icon, title: title, sub: sub, onTap: onTap);

  return showAppSheet(
    context,
    listen: s,
    titleOf: () => s.report ? 'Report a problem' : 'Help & about',
    subOf: () => s.report ? 'The gym team replies by email' : 'Answers, support and app version',
    footerStretch: true,
    builder: (ctx) {
      if (s.report) {
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 10, children: [
          Text('WHAT IS IT ABOUT?', style: AppText.s(11, W.w7, color: AppColors.muted, ls: 0.55)),
          MoChips(items: [for (final c in cats) c.$2], on: cats.where((x) => x.$1 == s.cat).firstOrNull?.$2, blue: true, height: 32,
              onPick: (t) => s.set(() => s.cat = cats.firstWhere((x) => x.$2 == t).$1)),
          _lbl('What happened?'),
          Container(
            constraints: const BoxConstraints(minHeight: 64),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(color: AppColors.white, borderRadius: BorderRadius.circular(10), border: Border.all(color: AppColors.line2)),
            child: TextField(
              controller: s.text,
              minLines: 2,
              maxLines: 6,
              maxLength: 2000,
              cursorColor: AppColors.accent,
              style: AppText.s(14, W.w5, h: 1.4),
              decoration: InputDecoration.collapsed(hintText: 'Tap to describe the problem', hintStyle: AppText.s(14, W.w5, color: AppColors.muted)).copyWith(counterText: ''),
            ),
          ),
          Container(height: 1, color: AppColors.line),
          CaCheckRow(on: s.attach, onTap: () => s.set(() => s.attach = !s.attach), title: 'Attach a screenshot of this screen', sub: screenshot == null ? 'Not available on this device' : 'Helps the team see the problem'),
        ]);
      }
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 12, children: [
        Text('COMMON QUESTIONS', style: AppText.s(11, W.w7, color: AppColors.muted, ls: 0.55)),
        Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.line)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            for (final (i, (q, a)) in _faq.indexed)
              Hover(
                onTap: () => s.set(() => s.open = s.open == i ? -1 : i),
                builder: (_, h, _) => Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(color: s.open == i ? AppColors.caWebBg : AppColors.white, border: i == 0 ? null : const Border(top: BorderSide(color: AppColors.line))),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 6, children: [
                    Row(spacing: 8, children: [
                      Expanded(child: Text(fill(q), style: AppText.s(13.5, W.w7, color: h ? AppColors.accentText : AppColors.text))),
                      AnimatedRotation(turns: s.open == i ? .5 : 0, duration: const Duration(milliseconds: 150), child: const AppIcon(AppIcons.chevronDown, size: 15, color: AppColors.muted)),
                    ]),
                    if (s.open == i) Text(fill(a), style: AppText.s(12.5, W.w4, color: AppColors.text2, h: 1.45)),
                  ]),
                ),
              ),
          ]),
        ),
        Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          row(AppIcons.flag, 'Report a problem', 'Something broken or wrong? Tell the gym team', () => s.set(() => s.report = true), first: true),
          row(AppIcons.phone, 'Gym front desk', [if (phone.isNotEmpty) phone, '${d.gym['hours']}'].join(' · '), () async {
            final n = phone.replaceAll(RegExp(r'[^0-9+]'), '');
            if (n.isEmpty) {
              showToast(context, 'Gym front desk', sub: 'Ask ${d.coachFirst} at your next session', kind: ToastKind.info);
              return;
            }
            await launchUrl(Uri.parse('tel:$n')).catchError((_) => false);
          }),
          row(AppIcons.file, 'Terms of use', 'What you agree to', () => showTermsSheet(context, readOnly: true)),
          row(AppIcons.lock, 'Privacy policy', 'How we keep your data safe', () => showTermsSheet(context, readOnly: true)),
          // Not on the board: the only way into the About page (ClientAbout), Gautam 2026-10-16.
          row(AppIcons.info, 'About ${d.gym['name'] ?? 'Train With Vimal'}', 'Coach, contact and app version', () {
            Navigator.of(ctx).pop();
            context.go('/more/about');
          }),
        ]),
        Column(children: [
          Text('${d.gym['name'] ?? 'Train With Vimal'}', style: AppText.s(13, W.w7)),
          Text('Version ${d.version} · Up to date', style: AppText.s(11.5, W.w4, color: AppColors.muted)),
        ]),
      ]);
    },
    footer: (ctx) => s.report
        ? pxFooter((ctx) => [
              CaButton('Back', kind: CaBtnKind.out, onPressed: () => s.set(() => s.report = false)),
              Opacity(
                opacity: s.cat != null && s.text.text.trim().length >= 3 ? 1 : .45,
                child: CaButton('Send report', icon: AppIcons.send, loading: s.busy, onPressed: () => send(ctx)),
              ),
            ])(ctx)
        : [CaButton('Close', kind: CaBtnKind.out, onPressed: () => Navigator.of(ctx).pop())],
  );
}

// ─────────────────────────────── My activity → one item

Future<void> showActivitySheet(BuildContext context, MoAct a) {
  final today = DateUtils.dateOnly(DateTime.now());
  final day = DateUtils.isSameDay(a.date, today)
      ? 'Today, ${dayShort(a.date)}'
      : DateUtils.isSameDay(a.date, today.subtract(const Duration(days: 1)))
          ? 'Yesterday, ${dayShort(a.date)}'
          : dayShort(a.date);
  return showAppSheet(
    context,
    title: a.title,
    sub: '$day · ${a.time}',
    footerStretch: true,
    builder: (_) => moKvs(a.rows, pad: 8),
    footer: (ctx) => [
      if (a.link != null)
        CaButton(a.label ?? 'Open', trailingIcon: AppIcons.chevronRight, onPressed: () {
          Navigator.of(ctx).pop();
          context.go(a.link!);
        })
      else
        CaButton('Close', kind: CaBtnKind.out, onPressed: () => Navigator.of(ctx).pop()),
    ],
  );
}
