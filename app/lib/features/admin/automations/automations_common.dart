import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;

import '../../../core/icons/app_icons.dart';
import '../../../core/theme/theme.dart';
import '../../../core/widgets/badge.dart';
import '../../../core/widgets/card.dart';
import '../../../core/widgets/hover.dart';

/// Shared bits of Admin → Automations (boards `Automations`, `AutomationNew`, `AutomationBuilder`, D-51).

/// The 15 triggers in board order: key, name, line under it, group, icon.
const auTriggers = <(String, String, String, String, AppIconData)>[
  ('client_approved', 'New client approved', 'As soon as they are approved.', 'client', AppIcons.usersAlt),
  ('plan_starts', 'Plan starts', 'A program or meal plan starts.', 'client', AppIcons.target),
  ('plan_ends', 'Plan ends', 'Before a plan ends.', 'client', AppIcons.flag),
  // Packages are not used for now (Gautam 2026-10-23); the server hides this trigger too (HIDDEN_TRIGGERS).
  // ('package_ending', 'Package ending', 'Before a package ends.', 'client', AppIcons.clock),
  ('birthday', 'Client birthday', 'On the client’s birthday.', 'client', AppIcons.star),
  ('every_week', 'Every week', 'Same day and time each week.', 'schedule', AppIcons.calendarAlt),
  ('every_day', 'Every day', 'Same time every day.', 'schedule', AppIcons.sun),
  ('on_date', 'On a date', 'Once, on a date you pick.', 'schedule', AppIcons.bell),
  ('missed_checkin', 'Missed check-in', 'A check-in is late.', 'activity', AppIcons.clipboard),
  ('missed_workouts', 'Missed workouts', 'Workouts missed in a row.', 'activity', AppIcons.dumbbell),
  ('no_activity', 'No app activity', 'The app is not opened.', 'activity', AppIcons.moon),
  ('form_sent', 'Form sent in', 'A client sends a form.', 'activity', AppIcons.send),
  ('workout_streak', 'Workout streak', 'Workouts done days in a row.', 'activity', AppIcons.bolt),
  ('goal_weight', 'Goal weight reached', 'Weight reaches the goal.', 'progress', AppIcons.target),
  ('weight_flat', 'Weight not changing', 'Weight stays the same.', 'progress', AppIcons.scale),
];

const auGroups = [('client', 'Client'), ('schedule', 'Schedule'), ('activity', 'Activity'), ('progress', 'Progress')];

(String, String, String, String, AppIconData)? auTrigger(String key) {
  for (final t in auTriggers) {
    if (t.$1 == key) return t;
  }
  return null;
}

AppIconData auTriggerIcon(String key) => auTrigger(key)?.$5 ?? AppIcons.bolt;

/// Builder tones follow the group (Client blue, Schedule green, Activity orange, Progress purple).
(Color, Color) auGroupTone(String key) {
  final g = auTrigger(key)?.$4 ?? 'client';
  return AppColors.hbTones[[for (final x in auGroups) x.$1].indexOf(g).clamp(0, 3)];
}

/// The list's own tones (`TONE` on the Automations board); the rest are blue.
(Color, Color) auListTone(String key) =>
    AppColors.hbTones[const {'every_week': 1, 'missed_checkin': 2, 'package_ending': 2, 'missed_workouts': 3}[key] ?? 0];

/// `.hb-ic` with the trigger's icon.
class AuTriggerTile extends StatelessWidget {
  const AuTriggerTile(this.trigger, {super.key, this.size = 34, this.tone});
  final String trigger;
  final double size;
  final (Color, Color)? tone;
  @override
  Widget build(BuildContext context) {
    final (bg, fg) = tone ?? auGroupTone(trigger);
    return IconTile(auTriggerIcon(trigger), size: size, bg: bg, fg: fg, radius: size >= 34 ? 9 : 8, iconSize: size >= 34 ? 18 : 16);
  }
}

const auChannels = [('email', 'Email'), ('push', 'Push'), ('whatsapp', 'WhatsApp'), ('in_app', 'In-app')];
String auChannel(String k) => {for (final c in auChannels) c.$1: c.$2}[k] ?? k;

/// "Push and Email" in the order they were picked.
String auChannelsLine(List<String> ch) => ch.isEmpty ? 'No channel yet' : ch.map(auChannel).join(' and ');

/// Step kinds: label on the card, the Add a step line, icon and its colours (`.au-dot`, `.au-fc`).
const auKinds = <(String, String, String)>[
  ('wait', 'Wait', 'Pause before the next step'),
  ('message', 'Send message', 'A template by email, push, WhatsApp or in-app'),
  ('form', 'Send form', 'A form or check-in from Forms & check-ins'),
  ('task', 'Assign task', 'A to-do for the trainer or the owner'),
];

String auKindLabel(String k) => {for (final x in auKinds) x.$1: x.$2}[k] ?? k;

AppIconData auKindIcon(String k) => switch (k) {
      'wait' => AppIcons.clock,
      'message' => AppIcons.send,
      'form' => AppIcons.clipboard,
      _ => AppIcons.checkCircle,
    };

(Color, Color) auKindTone(String k) => switch (k) {
      'message' => (AppColors.accentSoft, AppColors.accentText),
      'form' => (AppColors.okBg, AppColors.okText),
      'task' => (AppColors.hbTones[3].$1, AppColors.hbTones[3].$2),
      _ => (AppColors.sub, AppColors.text2),
    };

/// One step of an automation, as the builder edits it.
class AuStep {
  AuStep(this.kind, {this.id, this.amount = 1, this.unit = 'days', this.template = '', this.form = '', this.formName = '', List<String>? channels, this.title = '', this.assignee = 'trainer', this.dueDays = 1})
      : channels = channels ?? [];

  factory AuStep.fromJson(Map j) {
    final c = (j['config'] as Map?) ?? const {};
    final days = (c['days'] as num?)?.toInt() ?? 0, hours = (c['hours'] as num?)?.toInt() ?? 0;
    return AuStep(
      '${j['kind']}',
      id: (j['id'] as num?)?.toInt(),
      amount: days > 0 ? days : (hours > 0 ? hours : 1),
      unit: days > 0 || hours == 0 ? 'days' : 'hours',
      template: '${c['template'] ?? ''}',
      form: '${c['form'] ?? ''}',
      formName: '${c['form_name'] ?? ''}',
      channels: [for (final x in (c['channels'] as List?) ?? const []) '$x'],
      title: '${c['title'] ?? ''}',
      assignee: c['assignee'] == 'owner' ? 'owner' : 'trainer',
      dueDays: (c['due_days'] as num?)?.toInt() ?? 1,
    );
  }

  final key = UniqueKey();
  int? id;
  String kind, unit, template, form, formName, title, assignee;
  int amount, dueDays;
  List<String> channels;

  AuStep copy() => AuStep(kind, id: id, amount: amount, unit: unit, template: template, form: form, formName: formName, channels: [...channels], title: title, assignee: assignee, dueDays: dueDays);

  Map<String, Object?> toJson() => {
        'id': ?id,
        'kind': kind,
        'config': switch (kind) {
          'wait' => {'days': unit == 'days' ? amount : 0, 'hours': unit == 'hours' ? amount : 0},
          'message' => {'template': template, 'channels': channels},
          'form' => {'form': form, 'form_name': formName, 'channels': channels},
          _ => {'title': title, 'assignee': assignee, 'due_days': dueDays},
        },
      };

  /// `.au-fc` chip: "1 day", "24 h", "Form", "Push + WhatsApp", "Task".
  String get chip => switch (kind) {
        'wait' => unit == 'hours' ? '$amount h' : '$amount ${amount == 1 ? 'day' : 'days'}',
        'form' => 'Form',
        'message' => channels.isEmpty ? 'Message' : channels.map(auChannel).join(' + '),
        _ => 'Task',
      };

  /// "Send the form “Weekly check-in” by Push and Email" (In plain words, the step card head).
  String line({required String Function(String) templateName, required String Function(AuStep) formLabel}) => switch (kind) {
        'wait' => 'Wait $amount ${amount == 1 ? unit.replaceAll(RegExp(r's$'), '') : unit}',
        'form' => 'Send the form “${formLabel(this)}” by ${auChannelsLine(channels)}',
        'message' => 'Send “${templateName(template)}” by ${auChannelsLine(channels)}',
        _ => 'Task for the ${assignee == 'owner' ? 'owner' : 'assigned trainer'}: $title',
      };
}

/// `.au-fc`: a step chip in the list (icon + text) and the dashed "+N more".
class AuChip extends StatelessWidget {
  const AuChip(this.kind, this.text, {super.key});
  final String? kind;
  final String text;
  static TextStyle get style => AppText.s(11.5, W.w7);

  @override
  Widget build(BuildContext context) {
    final more = kind == null;
    final (bg, fg) = more ? (AppColors.card, AppColors.text2) : auKindTone(kind!);
    return Container(
      height: 24,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(color: bg, borderRadius: AppRadius.all(6), border: more ? Border.all(color: AppColors.line2) : null),
      child: Row(mainAxisSize: MainAxisSize.min, spacing: 4, children: [
        if (!more) AppIcon(auKindIcon(kind!), size: 13, color: fg),
        Text(text, maxLines: 1, style: style.copyWith(color: fg)),
      ]),
    );
  }

  /// Width the chip takes (for fitting chips on one line).
  static double widthOf(String? kind, String text) {
    final tp = TextPainter(text: TextSpan(text: text, style: style), textDirection: TextDirection.ltr, maxLines: 1)..layout();
    return tp.width + 16 + (kind == null ? 2 : 17);
  }
}

/// `.au-ar`: the small chevron between chips.
const auArrow = Padding(padding: EdgeInsets.symmetric(horizontal: 4), child: AppIcon(AppIcons.chevronRight, size: 12, color: AppColors.fmDrag));

/// On (green) · Draft (amber) · Off (grey).
Widget auBadge(String status) => switch (status) {
      'on' => const AppBadge('On', tone: Tone.ok, plain: true),
      'draft' => const AppBadge('Draft', tone: Tone.warn, plain: true),
      _ => const AppBadge('Off', plain: true),
    };

/// Who it is for, as one line: "All clients", "Package: 3 months · Gym", "Trainer: Aman Verma".
String auAudience(Map a) {
  final p = '${a['scope_package'] ?? ''}', t = '${a['scope_trainer_name'] ?? ''}';
  if (p.isNotEmpty && t.isNotEmpty) return 'Package: $p · Trainer: $t';
  if (p.isNotEmpty) return 'Package: $p';
  if (t.isNotEmpty) return 'Trainer: $t';
  return 'All clients';
}

// ─────────────────────────────── Trigger settings

/// Number settings: config key, label, unit, min, max, step.
const auNumbers = <String, (String, String, String, int, int, int)>{
  'plan_ends': ('days_before', 'Days before the end', 'days', 0, 14, 1),
  'package_ending': ('days_before', 'Days before the end', 'days', 1, 30, 1),
  'missed_checkin': ('hours', 'Not sent within', 'hours', 6, 72, 6),
  'missed_workouts': ('count', 'Missed in a row', 'workouts', 1, 10, 1),
  'no_activity': ('days', 'No activity for', 'days', 2, 30, 1),
  'workout_streak': ('days', 'Days in a row', 'days', 3, 60, 1),
  'weight_flat': ('weeks', 'Same weight for', 'weeks', 1, 8, 1),
};

/// Which fields each trigger shows (`TD` on the board): plan, day, num, date, form, time.
const auFields = <String, List<String>>{
  'plan_starts': ['plan'],
  'plan_ends': ['num', 'time'],
  'package_ending': ['num', 'time'],
  'birthday': ['time'],
  'every_week': ['day', 'time'],
  'every_day': ['time'],
  'on_date': ['date', 'time'],
  'missed_checkin': ['num'],
  'missed_workouts': ['num'],
  'no_activity': ['num'],
  'form_sent': ['form'],
  'workout_streak': ['num'],
  'weight_flat': ['num'],
};

/// Starting values for a trigger the admin has just picked.
Map<String, Object?> auDefaults(String t) {
  final tomorrow = DateTime.now().add(const Duration(days: 4));
  return switch (t) {
    'plan_starts' => {'plan_type': 'any'},
    'plan_ends' => {'days_before': 3, 'time': '09:00'},
    'package_ending' => {'days_before': 7, 'time': '09:00'},
    'birthday' => {'time': '08:00'},
    'every_week' => {'weekday': 6, 'time': '09:00'},
    'every_day' => {'time': '07:00'},
    'on_date' => {'date': DateFormat('yyyy-MM-dd').format(tomorrow), 'time': '10:00'},
    'missed_checkin' => {'hours': 24},
    'missed_workouts' => {'count': 3},
    'no_activity' => {'days': 5},
    'form_sent' => {'form': ''},
    'workout_streak' => {'days': 7},
    'weight_flat' => {'weeks': 3},
    _ => {},
  };
}

/// "09:30" ↔ half-hour slot 19.
int auSlot(Object? hhmm) {
  final p = '${hhmm ?? '09:00'}'.split(':');
  final h = int.tryParse(p.first) ?? 9, m = p.length > 1 ? int.tryParse(p[1]) ?? 0 : 0;
  return (h * 2 + (m >= 30 ? 1 : 0)).clamp(0, 47);
}

String auHhmm(int slot) => '${(slot ~/ 2).toString().padLeft(2, '0')}:${slot.isOdd ? '30' : '00'}';

/// "9:00 am" (`fmtT` on the board).
String auClock(Object? hhmm) {
  final s = auSlot(hhmm), h = s ~/ 2;
  return '${h % 12 == 0 ? 12 : h % 12}:${s.isOdd ? '30' : '00'} ${h < 12 ? 'am' : 'pm'}';
}

const auWeekdays = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];

/// The "Starts:" line under the trigger settings (`trigS` on the board).
String auStarts(String t, Map c, {String formName = ''}) {
  int n(String k) => (c[k] as num?)?.toInt() ?? 0;
  final plan = const {'program': 'program', 'meal_plan': 'meal plan'}[c['plan_type']] ?? 'program or meal plan';
  final date = DateTime.tryParse('${c['date'] ?? ''}');
  return switch (t) {
    'client_approved' => 'Right after a client is approved',
    'plan_starts' => 'When a client’s $plan starts',
    'plan_ends' => '${n('days_before') > 0 ? '${n('days_before')} ${n('days_before') == 1 ? 'day' : 'days'} before' : 'On the day'} a client’s plan ends, at ${auClock(c['time'])}',
    'package_ending' => '${n('days_before')} days before a package ends, at ${auClock(c['time'])}',
    'birthday' => 'On the client’s birthday at ${auClock(c['time'])}',
    'every_week' => 'Every ${auWeekdays[n('weekday').clamp(0, 6)]} at ${auClock(c['time'])}',
    'every_day' => 'Every day at ${auClock(c['time'])}',
    'on_date' => 'Once, on ${date == null ? 'a date' : DateFormat('d MMM yyyy').format(date)} at ${auClock(c['time'])}',
    'missed_checkin' => 'When a check-in is not sent within ${n('hours')} hours',
    'missed_workouts' => 'When ${n('count')} workouts in a row are missed',
    'no_activity' => 'When a client has not opened the app for ${n('days')} days',
    'form_sent' => formName.isEmpty ? 'When a client sends the form you pick' : 'When a client sends “$formName”',
    'workout_streak' => 'When a client finishes workouts ${n('days')} days in a row',
    'goal_weight' => 'When a client’s weight reaches their goal',
    'weight_flat' => 'When weight stays within 0.5 kg for ${n('weeks')} ${n('weeks') == 1 ? 'week' : 'weeks'}',
    _ => 'Pick what starts it',
  };
}

/// Grey note under some triggers (`TNOTE`).
const auTriggerNotes = {
  'goal_weight': 'Uses the goal weight in each client’s profile.',
  'no_activity': 'Opening the app, logging a meal or a workout all count as activity.',
  'workout_streak': 'Starts once per streak, on the day it is reached.',
  'client_approved': 'Runs once for each client.',
  'plan_starts': 'Runs on the start date of the plan, at 9 am.',
  'missed_checkin': 'Counts from the time the check-in was due.',
};

/// "2 d ago" in the Last 30 days list.
String auAgo(Object? iso) {
  final d = DateTime.tryParse('${iso ?? ''}')?.toLocal();
  if (d == null) return '';
  final s = DateTime.now().difference(d);
  if (s.inMinutes < 1) return 'just now';
  if (s.inHours < 1) return '${s.inMinutes} min ago';
  if (s.inDays < 1) return '${s.inHours} h ago';
  return '${s.inDays} d ago';
}

/// `.cp-tog` with a hover hand; the list uses it as the On / Off switch.
class AuSwitch extends StatelessWidget {
  const AuSwitch({super.key, required this.on, required this.onTap});
  final bool on;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Hover(
        onTap: onTap,
        builder: (_, _, _) => AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 30,
          height: 18,
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(color: on ? AppColors.accent : AppColors.line2, borderRadius: AppRadius.all(9)),
          child: AnimatedAlign(
            duration: const Duration(milliseconds: 150),
            alignment: on ? Alignment.centerRight : Alignment.centerLeft,
            child: Container(width: 14, height: 14, decoration: const BoxDecoration(color: AppColors.white, shape: BoxShape.circle)),
          ),
        ),
      );
}
