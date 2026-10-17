import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../app/services.dart';
import '../../../core/api/api_error.dart';
import '../../../core/icons/app_icons.dart';
import '../../../core/theme/theme.dart';
import '../../../core/widgets/button.dart';
import '../../../core/widgets/card.dart';
import '../../../core/widgets/input.dart';
import '../../../core/widgets/overlays.dart';
import '../../../core/widgets/responsive.dart';
import '../../../core/widgets/select.dart';
import '../../../core/widgets/tabs.dart';
import 'cp_content_drawers.dart';
import 'cp_forms_editor.dart';
import 'cp_model.dart';

/// What Send a form ended with: sent (the new list key), or "edit her copy first" (the editor opens).
class CpSendResult {
  const CpSendResult.sent(this.key, this.name) : formId = null, opts = null;
  const CpSendResult.edit(this.formId, this.name, this.opts) : key = null;
  final String? key, formId;
  final String name;
  final CpSendOpts? opts;
}

class _Send extends ChangeNotifier {
  String? form;
  String q = '', mode = 'once', send = 'now', by = 'push_whatsapp', every = '6', time = '18:00', until = '';
  int days = 2;
  DateTime? untilDate;
  bool editFirst = false, remind = true, review = true, busy = false;

  void set(VoidCallback f) {
    f();
    notifyListeners();
  }
}

/// Send a form to Riya: 1. Pick a form (the library's forms, "Sending" / "Sent 1 Oct" on what she has), 2. When
/// (Once: Send · Answer within / Repeats: Every · At · Until; Send by), 3. Options (edit her copy first, remind
/// after 24 h, answers go to her trainer).
Future<CpSendResult?> showSendFormDrawer(BuildContext context, CpController c, List<Map> forms) {
  final s = _Send();
  final her = cpHerObj(c);
  final trainer = (((c.overview['about'] as Map?) ?? const {})['trainer'] as Map?)?['full_name'];
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final sunday = today.add(Duration(days: (7 - now.weekday) % 7 == 0 ? 7 : (7 - now.weekday) % 7));
  final sendDays = [
    ('now', 'Now'),
    (DateFormat('yyyy-MM-dd').format(today.add(const Duration(days: 1))), 'Tomorrow, 10:00 am'),
    (DateFormat('yyyy-MM-dd').format(sunday), '${DateFormat('EEE, d MMM').format(sunday)}, 10:00 am'),
  ];
  const within = [(1, '1 day'), (2, '2 days'), (3, '3 days'), (7, '1 week')];
  const everyOpts = [('0', 'Monday'), ('1', 'Tuesday'), ('2', 'Wednesday'), ('3', 'Thursday'), ('4', 'Friday'), ('5', 'Saturday'), ('6', 'Sunday'), ('month', 'Month (1st)')];
  const times = [('07:00', '7:00 am'), ('09:00', '9:00 am'), ('12:00', '12:00 pm'), ('18:00', '6:00 pm'), ('20:00', '8:00 pm')];
  const bys = [('push', 'Push'), ('push_whatsapp', 'Push + WhatsApp'), ('push_email', 'Push + email')];
  String l<T>(List<(T, String)> xs, T v) => xs.firstWhere((x) => x.$1 == v, orElse: () => xs.first).$2;

  Map? picked() => forms.where((f) => '${f['id']}' == s.form).firstOrNull;

  Map<String, dynamic> body() => {
        'mode': s.mode,
        if (s.mode == 'once') ...{'send': s.send, 'answer_days': s.days, if (s.send != 'now') 'time': '10:00'},
        if (s.mode == 'repeat') ...{
          'every': s.every == 'month' ? 'month' : 'week',
          if (s.every != 'month') 'weekday': int.parse(s.every),
          'month_day': 1,
          'time': s.time,
          if (s.untilDate != null) 'until': DateFormat('yyyy-MM-dd').format(s.untilDate!),
        },
        'by': s.by,
        'remind': s.remind,
      };

  String summary() {
    final f = picked();
    if (f == null) return 'Pick a form';
    final when = s.mode == 'once'
        ? (s.send == 'now' ? 'now, answer in ${l(within, s.days)}' : '${l(sendDays, s.send).toLowerCase()}, answer in ${l(within, s.days)}')
        : (s.every == 'month' ? 'every month, ${l(times, s.time)}' : 'every ${l(everyOpts, s.every)}, ${l(times, s.time)}');
    return '${f['name']} · $when';
  }

  Future<void> go(BuildContext ctx) async {
    final f = picked();
    if (f == null) return;
    if (s.editFirst) {
      Navigator.of(ctx).pop(CpSendResult.edit('${f['id']}', '${f['name']}', CpSendOpts(body())));
      return;
    }
    s.set(() => s.busy = true);
    try {
      final r = await Services.api.post<Map>('clients/${c.id}/forms/', {'form': f['id'], ...body()});
      if (ctx.mounted) Navigator.of(ctx).pop(CpSendResult.sent('${r['key']}', '${f['name']}'));
    } on ApiError catch (e) {
      s.set(() => s.busy = false);
      if (ctx.mounted) showToast(ctx, 'Could not send', sub: e.message);
    }
  }

  return showAppDrawer<CpSendResult>(
    context,
    title: 'Send a form to ${c.first}',
    sub: 'Check-ins, surveys and feedback forms. The master form is not changed.',
    icon: AppIcons.forms,
    builder: (ctx) => ListenableBuilder(
      listenable: s,
      builder: (ctx, _) {
        final shown = [for (final f in forms) if (s.q.isEmpty || '${f['name']}'.toLowerCase().contains(s.q.toLowerCase())) f];
        final two = !ctx.isPhone;
        Widget row(List<Widget> xs) => two
            ? Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 12, children: [for (final x in xs) Expanded(child: x)])
            : Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 12, children: xs);
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          DrSec(
            title: '1. Pick a form',
            sub: 'Master forms from the library. ${c.first} gets ${cpHer(c)} own copy.',
            inlineSub: true,
            children: [
              AppSearchField(placeholder: 'Search forms', icon: AppIcons.search, onChanged: (v) => s.set(() => s.q = v.trim())),
              if (forms.isEmpty)
                const EmptyState('No forms to send', sub: 'Publish a form in Forms & check-ins first.')
              else if (shown.isEmpty)
                EmptyState('Nothing matches “${s.q}”', sub: 'Try another word.')
              else
                DrOpts([
                  for (final f in shown)
                    DrOpt(
                      title: '${f['name']}',
                      badge: '${f['has'] ?? ''}',
                      sub: '${f['sub'] ?? ''}',
                      end: '${f['questions']} questions',
                      on: s.form == '${f['id']}',
                      onTap: () => s.set(() => s.form = '${f['id']}'),
                    ),
                ]),
            ],
          ),
          DrSec(title: '2. When', children: [
            Align(
              alignment: Alignment.centerLeft,
              child: SegmentedTabs<String>(
                items: const [TabItem('once', 'Once'), TabItem('repeat', 'Repeats')],
                value: s.mode,
                onChanged: (v) => s.set(() => s.mode = v),
              ),
            ),
            if (s.mode == 'once')
              row([
                drField('Send', AppSelect(l(sendDays, s.send), entries: [for (final (v, t) in sendDays) MenuEntry(t, selected: s.send == v, onTap: () => s.set(() => s.send = v))])),
                drField('Answer within', AppSelect(l(within, s.days), entries: [for (final (v, t) in within) MenuEntry(t, selected: s.days == v, onTap: () => s.set(() => s.days = v))])),
              ])
            else
              row([
                drField('Every', AppSelect(l(everyOpts, s.every), entries: [for (final (v, t) in everyOpts) MenuEntry(t, selected: s.every == v, onTap: () => s.set(() => s.every = v))])),
                drField('At', AppSelect(l(times, s.time), entries: [for (final (v, t) in times) MenuEntry(t, selected: s.time == v, onTap: () => s.set(() => s.time = v))])),
                drField(
                  'Until',
                  s.untilDate == null && s.until != 'date'
                      ? AppSelect('No end date', entries: [
                          const MenuEntry('No end date', selected: true),
                          MenuEntry('Pick a date…', onTap: () => s.set(() => s.until = 'date')),
                        ])
                      : DrDateBox(s.untilDate, onPick: (d) => s.set(() => s.untilDate = d)),
                ),
              ]),
            drField('Send by', AppSelect(l(bys, s.by), entries: [for (final (v, t) in bys) MenuEntry(t, selected: s.by == v, onTap: () => s.set(() => s.by = v))])),
          ]),
          DrSec(title: '3. Options', last: true, children: [
            DrSwitch(
              title: 'Edit ${c.first}’s copy before sending',
              sub: 'Opens the form editor first. Add, remove or change questions just for $her.',
              value: s.editFirst,
              onChanged: (v) => s.set(() => s.editFirst = v),
            ),
            DrSwitch(
              title: 'Remind $her if ${cpShe(c)} does not answer',
              sub: 'One reminder after 24 hours',
              value: s.remind,
              onChanged: (v) => s.set(() => s.remind = v),
            ),
            if (trainer != null)
              Text('Answers go to $trainer in Check-ins to review.', style: AppText.s(12.5, W.w5, color: AppColors.muted)),
          ]),
        ]);
      },
    ),
    footer: (ctx) => [
      if (!ctx.isPhone) Expanded(child: ListenableBuilder(listenable: s, builder: (_, _) => Text(summary(), maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(12.5, W.w6, color: AppColors.muted)))),
      AppButton('Cancel', expand: ctx.isPhone, onPressed: () => Navigator.of(ctx).pop()),
      ListenableBuilder(
        listenable: s,
        builder: (_, _) => AppButton.primary(s.editFirst ? 'Edit and send' : 'Send form',
            icon: AppIcons.send, expand: ctx.isPhone, loading: s.busy, onPressed: s.form == null ? null : () => go(ctx)),
      ),
    ],
  ).whenComplete(() => disposeLater([s]));
}
