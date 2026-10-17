import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../app/services.dart';
import '../../../core/icons/app_icons.dart';
import '../../../core/theme/theme.dart';
import '../../../core/widgets/avatar.dart';
import '../../../core/widgets/badge.dart';
import '../../../core/widgets/card.dart';
import '../../../core/widgets/responsive.dart';
import '../../client/progress/progress_model.dart' show PxWeight;
import '../../client/progress/progress_parts.dart' show PxWeightChart;
import 'cp_common.dart';
import 'cp_model.dart';

/// Overview tab: About, Weight trend, Last 7 days, Latest note (left) · Needs attention, Coaching, Current plans,
/// Check-ins and schedule (right). Everything from `clients/<id>/overview/`.
class CpOverviewTab extends StatelessWidget {
  const CpOverviewTab(this.c, {super.key});
  final CpController c;

  Map get o => c.overview;

  @override
  Widget build(BuildContext context) => CpColumns(
        leftFlex: 7,
        rightFlex: 5,
        left: [_about(), _weight(), _week(context), _note()],
        right: [_attention(), _coaching(), _plans(), _schedule()],
      );

  // ─────────────────────────────── About

  /// What the client answered in onboarding (the gym's coaching form) and the coach changed in Edit profile; the
  /// server words every value (age from the date of birth, "—" only when nothing is there) — D-36.
  Widget _about() {
    final about = (o['about'] as Map?) ?? const {};
    final items = (about['items'] as List?) ?? const [];
    return CpCard(
      title: 'About ${c.first}',
      sub: 'From onboarding · edit in Edit profile',
      child: CpKvGrid([
        for (final it in items) ('${it['label']}', '${it['value'] ?? '—'}', warn: it['warn'] == true),
      ]),
    );
  }

  // ─────────────────────────────── Weight trend

  Widget _weight() {
    final w = (o['weight_trend'] as Map?) ?? const {};
    final pts = [
      for (final p in (w['points'] as List?) ?? const [])
        if (cpParse(p['date']) != null) PxWeight(cpParse(p['date'])!, (p['kg'] as num).toDouble()),
    ];
    final ch = w['change'] as num?, to = w['to_goal'] as num?;
    final sub = [
      if (ch != null) '${cpSigned(ch, 'kg')} in 30 days',
      if (to != null) to.abs() < .05 ? 'at goal' : '${cpKg(to.abs(), keep: true)} to goal',
    ].join(' · ');
    return CpCard(
      title: 'Weight trend',
      sub: sub.isEmpty ? 'Last 30 days' : sub,
      action: CpLink('Open progress', onTap: () => c.setTab('progress')),
      child: pts.length < 2
          ? const EmptyState('Not enough weigh-ins yet', sub: 'The line shows after two weigh-ins.')
          : Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 8, children: [
              PxWeightChart(points: pts, goal: (w['goal'] as num?)?.toDouble(), selected: null, onPick: (_) {}, height: 170, dots: false),
              Row(children: [
                Text('${cpDm(pts.first.date)} · ${cpKg(pts.first.kg, keep: true)}', style: AppText.cap),
                const Spacer(),
                Text(cpDm(pts[pts.length ~/ 2].date), style: AppText.cap),
                const Spacer(),
                Text('${cpDm(pts.last.date)} · ${cpKg(pts.last.kg, keep: true)}', style: AppText.cap),
              ]),
            ]),
    );
  }

  // ─────────────────────────────── Last 7 days

  Widget _week(BuildContext context) {
    final days = (o['last_7_days'] as List?) ?? const [];
    const rows = [('workout', 'Workout'), ('meals', 'Meals'), ('checkin', 'Check-in'), ('habits', 'Habits')];
    final labelW = context.isPhone ? 64.0 : 86.0;
    Widget cell(String st) {
      final (bg, fg, ic) = switch (st) {
        'done' => (AppColors.okBg, AppColors.okText, AppIcons.check),
        'partial' => (AppColors.warnBg, AppColors.warnText, null),
        'missed' => (AppColors.badBg, AppColors.badText, AppIcons.close),
        'today' => (AppColors.white, AppColors.muted, null),
        _ => (AppColors.sub, AppColors.muted, null), // rest
      };
      return Container(
        height: 22,
        margin: const EdgeInsets.symmetric(horizontal: 2.5),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(5),
          border: st == 'today' ? Border.all(color: AppColors.line2) : null,
        ),
        child: ic != null ? AppIcon(ic, size: 12, color: fg, stroke: 2.2) : (st == 'partial' ? Text('–', style: AppText.s(12, W.w7, color: fg)) : null),
      );
    }

    Widget legend(Color c, String l) => Row(mainAxisSize: MainAxisSize.min, spacing: 6, children: [
          Container(width: 10, height: 10, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(3))),
          Text(l, style: AppText.cap),
        ]);

    return CpCard(
      title: 'Last 7 days',
      sub: 'What ${c.first} did each day',
      action: CpLink('Open logs', onTap: () => c.setTab('logs')),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 8, children: [
        Row(children: [
          SizedBox(width: labelW),
          for (final d in days)
            Expanded(child: Text(DateFormat('EEE').format(cpParse(d['date']) ?? DateTime.now()), textAlign: TextAlign.center, style: AppText.s(12, W.w6, color: AppColors.muted))),
        ]),
        for (final (k, l) in rows)
          Row(children: [
            SizedBox(width: labelW, child: Text(l, style: AppText.s(13, W.w5, color: AppColors.text2))),
            for (final d in days) Expanded(child: cell('${d[k]}')),
          ]),
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Wrap(spacing: 14, runSpacing: 6, children: [
            legend(AppColors.okBg, 'Done'),
            legend(AppColors.warnBg, 'Partly'),
            legend(AppColors.badBg, 'Missed'),
            legend(AppColors.sub, 'Rest day'),
          ]),
        ),
      ]),
    );
  }

  // ─────────────────────────────── Latest note

  Widget _note() {
    final n = o['latest_note'] as Map?;
    return CpCard(
      title: 'Latest note',
      sub: 'Staff only',
      action: CpLink(n == null ? 'Add a note' : 'All notes', onTap: () => c.setTab('notes')),
      child: n == null
          ? Text('No notes yet. Notes you write about ${c.first} show here; ${c.first} never sees them.', style: AppText.sub)
          : Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 8, children: [
              Padding(padding: const EdgeInsets.only(left: 4), child: Text('${n['body']}', style: AppText.s(14, W.w5, h: 1.5))),
              Row(spacing: 8, children: [
                AppAvatar('${n['author']}', size: 20, initials: '${n['author_initials'] ?? ''}'),
                Text('${n['author']} · ${cpAgo(n['created_at'])}', style: AppText.cap),
              ]),
            ]),
    );
  }

  // ─────────────────────────────── Needs attention

  Widget _attention() {
    final items = (o['needs_attention'] as List?) ?? const [];
    return CpCard(
      title: 'Needs attention',
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 10),
      child: items.isEmpty
          ? Padding(padding: const EdgeInsets.fromLTRB(12, 4, 12, 8), child: Text('Nothing needs you right now.', style: AppText.sub))
          : Column(children: [
              for (final it in items)
                AppRow(
                  leading: switch ('${it['kind']}') {
                    'flag' => cpIcon(AppIcons.flag, bg: AppColors.warnBg, fg: AppColors.warnText),
                    'checkin' => cpIcon(AppIcons.clipboard, bg: AppColors.infoBg, fg: AppColors.infoText),
                    _ => cpIcon(AppIcons.dumbbell, bg: AppColors.badBg, fg: AppColors.badText),
                  },
                  title: '${it['title']}',
                  sub: '${it['detail'] ?? ''}'.isEmpty ? (it['kind'] == 'missed' ? 'Not logged' : null) : '${it['detail']}',
                  chevron: it['kind'] != 'flag',
                  onTap: switch ('${it['kind']}') {
                    'flag' => () => c.setTab('notes'),
                    'checkin' => () => c.setTab('logs', log: 'weekly'),
                    _ => () => c.setTab('logs', log: 'workouts'),
                  },
                ),
            ]),
    );
  }

  // ─────────────────────────────── Coaching

  Widget _coaching() {
    final about = (o['about'] as Map?) ?? const {};
    final t = about['trainer'] as Map?;
    final plans = (o['current_plans'] as Map?) ?? const {};
    final w = plans['workout'] as Map?, m = plans['meal_plan'] as Map?;
    final onb = (c.detail['onboarding'] as Map?) ?? const {};
    final me = Services.session.me?.id;
    final goal = '${about['goal'] ?? ''}';
    return CpCard(
      title: 'Coaching',
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 0, children: [
        LayoutBuilder(builder: (context, b) {
          Widget kv(String l, Widget v) => Container(
                width: (b.maxWidth - 20) / 2,
                padding: const EdgeInsets.symmetric(vertical: 9),
                decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.line))),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 3, children: [Text(l, style: AppText.s(12.5, W.w5, color: AppColors.muted)), v]),
              );
          Text v(String s) => Text(s, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppText.s(14, W.w7));
          return Wrap(spacing: 20, children: [
            kv(
              'Trainer',
              t == null
                  ? v('No trainer')
                  : Row(spacing: 6, children: [
                      AppAvatar('${t['full_name']}', size: 20, initials: '${t['initials'] ?? ''}', colors: AppColors.avatarCode('${t['avatar_color'] ?? 'c1'}')),
                      Flexible(child: v('${t['full_name']}${t['id'] == me ? ' (you)' : ''}')),
                    ]),
            ),
            kv('Program', v(w == null ? 'None yet' : '${w['name']} · week ${w['week']} of ${w['weeks']}')),
            kv('Meal plan', v(m == null ? 'None yet' : '${m['name']}')),
            kv('Goal', v([if (goal.isNotEmpty) goal, if (about['target_weight'] != null) cpKg(about['target_weight'])].join(' · ').ifEmpty('—'))),
            kv('Joined', v(cpDmy(about['start_date'] ?? about['joined']))),
            kv('Onboarding', v((onb['done'] ?? 0) >= (onb['total'] ?? 1) ? 'Done' : '${onb['done']} of ${onb['total']} steps')),
          ]);
        }),
        if ((o['coaching'] as Map?)?['next_session'] case final Map s)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Row(spacing: 10, children: [
              cpIcon(AppIcons.calendar, bg: AppColors.infoBg, fg: AppColors.infoText),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 2, children: [
                  Text('Next session · ${s['kind']}', style: AppText.rowTitle),
                  Text('${cpDay(s['start'])}, ${cpTime(s['start'])} · ${s['trainer']}', style: AppText.rowSub),
                ]),
              ),
            ]),
          ),
      ]),
    );
  }

  // ─────────────────────────────── Current plans

  Widget _plans() {
    final p = (o['current_plans'] as Map?) ?? const {};
    final w = p['workout'] as Map?, m = p['meal_plan'] as Map?, s = p['supplements'] as Map?, h = p['habits'] as Map?;
    final kcal = NumberFormat.decimalPattern('en_IN');
    final rows = [
      (AppIcons.dumbbell, 'workout', w == null ? 'No workout plan' : '${w['name']}',
          w == null ? 'Assign one from Plans' : ['Workout', 'week ${w['week']} of ${w['weeks']}', if (w['edited'] == true) 'edited for ${c.first}'].join(' · ')),
      (AppIcons.apple, 'meal', m == null ? 'No meal plan' : '${m['name']}',
          m == null ? 'Assign one from Plans' : ['Meal plan', if (m['kcal'] != null) '${kcal.format(m['kcal'])} kcal', '${m['meals']} meals', if ('${m['diet'] ?? ''}'.isNotEmpty) '${m['diet']}'.toLowerCase()].join(' · ')),
      (AppIcons.pill, 'supplements', s == null ? 'No supplements' : '${s['count']} supplement${s['count'] == 1 ? '' : 's'}',
          s == null ? 'Assign a supplement plan' : ((s['items'] as List?) ?? const []).join(', ')),
      (AppIcons.checkCircle, 'habits', h == null ? 'No habits' : '${h['count']} habit${h['count'] == 1 ? '' : 's'}',
          h == null ? 'Assign a habit plan' : ((h['items'] as List?) ?? const []).join(', ')),
    ];
    return CpCard(
      title: 'Current plans',
      action: CpLink('Open plans', onTap: () => c.setTab('plans')),
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 10),
      child: Column(children: [
        for (final (ic, slot, t, sub) in rows) AppRow(leading: cpIcon(ic), title: t, sub: sub, chevron: true, onTap: () => c.setTab('plans', plan: slot)),
      ]),
    );
  }

  // ─────────────────────────────── Check-ins and schedule

  Widget _schedule() {
    final s = (o['checkins_schedule'] as Map?) ?? const {};
    final d = (s['daily'] as Map?) ?? const {}, w = (s['weekly'] as Map?) ?? const {};
    final m = (s['measurements'] as Map?) ?? const {}, p = (s['photos'] as Map?) ?? const {};
    String every(Object? n) => (n ?? 1) == 1 ? 'Every week' : 'Every $n weeks';
    final sent = (d['sent'] as num?) ?? 0, days = (d['days'] as num?) ?? 7;
    final rows = [
      (AppIcons.clipboard, 'Daily check-in', 'Every day · reminder ${d['time'] ?? ''}', '$sent of $days this week', sent >= days - 1 ? Tone.ok : (sent == 0 ? Tone.bad : Tone.warn), 'daily'),
      (
        AppIcons.calendar,
        '${s['weekly_form'] ?? 'Weekly check-in'}',
        'Every Sunday · next ${cpDay(w['next'])}',
        w['waiting_week'] != null ? 'Week ${w['waiting_week']} to review' : (w['sent_this_week'] == true ? 'Sent' : 'Due Sunday'),
        w['waiting_week'] != null ? Tone.info : (w['sent_this_week'] == true ? Tone.ok : Tone.neutral),
        'weekly'
      ),
      (AppIcons.ruler, 'Measurements', '${every(m['every_weeks'])} · next ${cpDay(m['next'])}', m['due'] == true ? 'Due' : 'On time', m['due'] == true ? Tone.warn : Tone.ok, 'progress'),
      (AppIcons.camera, 'Progress photos', '${every(p['every_weeks'])} · next ${cpDay(p['next'])}', p['last'] == null ? 'None yet' : 'Last ${cpDm(p['last'])}', Tone.neutral, 'progress'),
    ];
    return CpCard(
      title: 'Check-ins and schedule',
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 10),
      child: Column(children: [
        for (final (ic, t, sub, chip, tone, go) in rows)
          AppRow(
            leading: cpIcon(ic),
            title: t,
            sub: sub,
            trailing: AppBadge(chip, tone: tone),
            onTap: () => go == 'progress' ? c.setTab('progress') : c.setTab('logs', log: go),
          ),
      ]),
    );
  }
}

extension on String {
  String ifEmpty(String other) => isEmpty ? other : this;
}
