import 'package:flutter/material.dart';

import '../../../app/services.dart';
import '../../../core/api/api_error.dart';
import '../../../core/icons/app_icons.dart';
import '../../../core/theme/theme.dart';
import '../../../core/widgets/avatar.dart';
import '../../../core/widgets/badge.dart';
import '../../../core/widgets/button.dart';
import '../../../core/widgets/input.dart';
import '../../../core/widgets/overlays.dart';
import '../../../core/widgets/responsive.dart';
import '../../../core/widgets/tooltip.dart';
import '../../trainer/client_profile/cp_content_drawers.dart' show DrOpt, DrOpts, DrSwitch;
import '../clients/admin_client_drawers.dart';
import 'approvals_model.dart';

// Approvals → Review drawer (`.ap-drawer`), Reject, Ask for info and Move back modals.

Widget apAvatar(Map? p, {double size = 32}) => AppAvatar('${p?['full_name'] ?? ''}',
    size: size, colors: AppColors.avatarCode('${p?['avatar_color'] ?? 'c1'}'), initials: '${p?['initials'] ?? ''}'.isEmpty ? null : '${p?['initials']}');

/// `.ap-wait`: amber after 1 day, red after 2.
Widget apWait(ApRow r, {double size = 12.5}) =>
    Text(r.wait, maxLines: 1, style: AppText.s(size, W.w6, color: r.late ? AppColors.apWaitLate : (r.old ? AppColors.apWaitOld : AppColors.text)));

/// `.ap-pips`: five small bars, green for each setup step done.
Widget apPips(int done) => Row(mainAxisSize: MainAxisSize.min, spacing: 3, children: [
      for (var i = 0; i < 5; i++)
        Container(width: 12, height: 5, decoration: BoxDecoration(color: i < done ? AppColors.apOn : AppColors.sub, borderRadius: AppRadius.all(3))),
    ]);

/// What the Review drawer hands back: go to the previous / next person, or what was done.
enum ApOutcome { prev, next, approved, rejected, asked }

/// Review drawer for one sign-up: setup, contact, onboarding answers, trainer pick, approve options.
/// Footer: Reject · Ask for info · Approve and assign (Approve anyway when steps are missing).
Future<ApOutcome?> showReviewDrawer(BuildContext context, ApRow r, {required bool canStep}) {
  final detail = ValueNotifier<Map?>(null);
  final trainers = ValueNotifier<Map?>(null);
  final pick = ValueNotifier<String?>(null);
  final tell = ValueNotifier(true), finish = ValueNotifier(false), busy = ValueNotifier(false);
  final she = pronoun(r.gender, cap: true), her = objective(r.gender), hers = possessive(r.gender);

  Services.api.get<Map>('approvals/${r.id}/').then((d) => detail.value = d).catchError((_) => detail.value = const {});
  Services.api.get<Map>('approvals/${r.id}/trainers/').then((d) {
    trainers.value = d;
    final rows = (d['trainers'] as List).cast<Map>();
    final def = rows.where((t) => '${t['id']}' == '${d['default']}' && t['tag'] != 'full').firstOrNull ??
        rows.where((t) => t['tag'] == 'good_fit').firstOrNull ??
        rows.where((t) => t['tag'] != 'full').firstOrNull;
    pick.value = def == null ? null : '${def['id']}';
  }).catchError((_) {
    trainers.value = const {'trainers': []};
  });

  Future<void> approve(BuildContext ctx) async {
    if (pick.value == null) {
      showToast(ctx, 'Pick a trainer first', kind: ToastKind.info);
      return;
    }
    busy.value = true;
    try {
      await Services.api.post('approvals/${r.id}/approve/', {'trainer': pick.value, 'tell_client': tell.value, 'ask_finish_setup': finish.value});
      if (ctx.mounted) Navigator.of(ctx).pop(ApOutcome.approved);
    } on ApiError catch (e) {
      busy.value = false;
      if (ctx.mounted) showToast(ctx, 'Could not approve ${r.first}', sub: e.fields.values.expand((x) => x).join(' ').isNotEmpty ? e.fields.values.expand((x) => x).join(' ') : e.message, kind: ToastKind.info);
    }
  }

  Widget sub(String t, {String? end}) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(children: [
          Expanded(child: Text(t, style: AppText.s(12.5, W.w8))),
          if (end != null) Text(end, style: AppText.cap),
        ]),
      );

  Widget sec(List<Widget> children, {bool last = false}) => Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(border: last ? null : const Border(bottom: BorderSide(color: AppColors.line))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 8, children: children),
      );

  return showAppDrawer<ApOutcome>(
    context,
    title: r.name,
    sub: '${r.signedUp} · waiting ${r.wait}',
    leading: apAvatar(r.client, size: 34),
    headerAction: canStep
        ? Builder(
            builder: (ctx) => Row(mainAxisSize: MainAxisSize.min, spacing: 2, children: [
              AppIconButton(AppIcons.chevronLeft, tooltip: 'Previous', ghost: true, small: true, onPressed: () => Navigator.of(ctx).pop(ApOutcome.prev)),
              AppIconButton(AppIcons.chevronRight, tooltip: 'Next', ghost: true, small: true, onPressed: () => Navigator.of(ctx).pop(ApOutcome.next)),
            ]),
          )
        : null,
    builder: (ctx) => ValueListenableBuilder<Map?>(
      valueListenable: detail,
      builder: (ctx, d, _) {
        final steps = (d?['steps'] as List?)?.cast<Map>() ?? const [];
        final answers = (d?['answers'] as List?)?.cast<Map>() ?? const [];
        final note = '${d?['health_notes'] ?? ''}'.trim();
        final code = '${d?['invite_code'] ?? ''}';
        Widget kpi(String l, Widget v) => Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 2, children: [Text(l, style: AppText.s(11.5, W.w6, color: AppColors.muted)), v]),
              ),
            );
        Widget info(AppIconData ic, String l, String v) => Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 3, children: [
              Row(spacing: 6, children: [AppIcon(ic, size: 13, color: AppColors.muted), Text(l, style: AppText.s(11.5, W.w6, color: AppColors.muted))]),
              CutText(v.isEmpty ? '—' : v, maxLines: 1, style: AppText.s(13, W.w6)),
            ]);
        final infos = [
          info(AppIcons.phone, 'Mobile', r.phone),
          info(AppIcons.mail, 'Email', r.email),
          info(AppIcons.link, 'Invite code', code.isEmpty ? (d == null ? '…' : 'Added by the team') : code),
          info(AppIcons.mobile, 'Signed up from', r.from),
        ];
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(
            margin: const EdgeInsets.only(top: 12),
            decoration: BoxDecoration(border: Border.all(color: AppColors.line), borderRadius: AppRadius.all(10)),
            child: IntrinsicHeight(
              child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                kpi('Profile setup', Text('${r.setupDone} of 5 done', style: AppText.s(13.5, W.w7))),
                const VerticalDivider(width: 1, color: AppColors.line),
                kpi('Invited by', CutText('${r.invitedBy?['full_name'] ?? 'The team'}', maxLines: 1, style: AppText.s(13.5, W.w7))),
                const VerticalDivider(width: 1, color: AppColors.line),
                kpi('Waiting', apWait(r, size: 13.5)),
              ]),
            ),
          ),
          sec([
            if (note.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                decoration: BoxDecoration(color: AppColors.warnBg, borderRadius: AppRadius.all(AppRadius.item)),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 8, children: [
                  const Padding(padding: EdgeInsets.only(top: 1), child: AppIcon(AppIcons.alert, size: 16, color: AppColors.warnText)),
                  Expanded(
                    child: Text.rich(TextSpan(children: [
                      TextSpan(text: 'Health note. ', style: AppText.s(13, W.w7, color: AppColors.warnText)),
                      TextSpan(text: note),
                    ]), style: AppText.s(13, W.w5, color: AppColors.warnText, h: 1.45)),
                  ),
                ]),
              ),
            if (ctx.isPhone)
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 12, children: infos)
            else
              Column(spacing: 12, children: [
                Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 16, children: [Expanded(child: infos[0]), Expanded(child: infos[1])]),
                Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 16, children: [Expanded(child: infos[2]), Expanded(child: infos[3])]),
              ]),
          ]),
          sec([
            sub('Profile setup', end: '${r.setupDone} of 5 done'),
            if (d == null)
              const LinearProgressIndicator(minHeight: 2, color: AppColors.accent, backgroundColor: AppColors.sub)
            else
              for (final x in steps)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(spacing: 10, children: [
                    Container(
                      width: 18,
                      height: 18,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: x['done'] == true ? AppColors.apOn : null,
                        shape: BoxShape.circle,
                        border: x['done'] == true ? null : Border.all(color: AppColors.line2, width: 1.5),
                      ),
                      child: x['done'] == true ? const AppIcon(AppIcons.check, size: 11, color: AppColors.white) : null,
                    ),
                    Expanded(child: Text('${x['label']}', style: x['done'] == true ? AppText.s(13, W.w6) : AppText.s(13, W.w5, color: AppColors.muted))),
                    Text(x['done'] == true ? '${x['hint']}' : 'Not done', style: AppText.cap),
                  ]),
                ),
          ]),
          sec([
            sub('From $hers onboarding'),
            if (d != null && answers.isEmpty)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(color: AppColors.apEmpty, borderRadius: AppRadius.all(8)),
                child: Text('$she ${verb(r.gender, 'has')} not filled $hers goal and body details yet. Ask for info to remind $her.', style: AppText.s(12.5, W.w5, color: AppColors.muted)),
              )
            else
              DrOpts([
                for (final a in answers)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 7),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      SizedBox(width: ctx.isPhone ? 90 : 140, child: Text('${a['label']}', style: AppText.s(13, W.w5, color: AppColors.muted))),
                      Expanded(child: Text('${a['value']}', style: AppText.s(13, W.w6))),
                    ]),
                  ),
              ]),
          ]),
          ValueListenableBuilder<Map?>(
            valueListenable: trainers,
            builder: (ctx, t, _) {
              final rows = (t?['trainers'] as List?)?.cast<Map>() ?? const [];
              // invited trainer first, then good fits, then the rest by load (board order)
              final sorted = [...rows]..sort((a, b) {
                  int rank(Map x) => '${x['id']}' == '${t?['default']}' ? 0 : (x['tag'] == 'good_fit' ? 1 : (x['tag'] == 'full' ? 3 : 2));
                  return rank(a).compareTo(rank(b));
                });
              return sec([
                sub('Trainer', end: t == null ? null : '${t['with_space']} of ${t['total']} have space'),
                if (t == null)
                  const LinearProgressIndicator(minHeight: 2, color: AppColors.accent, backgroundColor: AppColors.sub)
                else if (rows.isEmpty)
                  Text('No trainers yet. Add one under Trainers first.', style: AppText.cap)
                else
                  ValueListenableBuilder<String?>(
                    valueListenable: pick,
                    builder: (_, p, _) => TrainerPickList([
                      for (final x in sorted)
                        TrainerPickRow(
                          t: x,
                          on: '${x['id']}' == p,
                          onTap: () => pick.value = '${x['id']}',
                          tags: [
                            if (x['tag'] == 'full') ('Full', Tone.warn),
                            if (x['tag'] == 'invited') ('Invited $her', Tone.neutral),
                            if (x['tag'] == 'good_fit') ('Good fit', Tone.ok),
                          ],
                        ),
                    ]),
                  ),
              ]);
            },
          ),
          sec(last: true, [
            sub('When you approve'),
            ValueListenableBuilder<bool>(
              valueListenable: tell,
              builder: (_, v, _) => DrSwitch(title: 'Tell $her by email and in the app', sub: '$she can log in right away', value: v, onChanged: (x) => tell.value = x),
            ),
            if (r.setupDone < 5)
              ValueListenableBuilder<bool>(
                valueListenable: finish,
                builder: (_, v, _) => DrSwitch(title: 'Ask $her to finish setup', sub: 'Only the steps not done', value: v, onChanged: (x) => finish.value = x),
              ),
          ]),
        ]);
      },
    ),
    footer: (ctx) => [
      AppButton('Reject', kind: BtnKind.textDanger, onPressed: () async {
        if (await showRejectModal(ctx, r) && ctx.mounted) Navigator.of(ctx).pop(ApOutcome.rejected);
      }),
      if (!ctx.isPhone) const Spacer(),
      AppButton('Ask for info', icon: AppIcons.send, expand: ctx.isPhone, onPressed: () async {
        if (await showAskInfoModal(ctx, r) && ctx.mounted) Navigator.of(ctx).pop(ApOutcome.asked);
      }),
      ValueListenableBuilder<bool>(
        valueListenable: busy,
        builder: (_, b, _) => AppButton.primary(r.setupDone < 5 ? 'Approve anyway' : 'Approve and assign',
            icon: AppIcons.check, expand: ctx.isPhone, loading: b, onPressed: b ? null : () => approve(ctx)),
      ),
    ],
  ).whenComplete(() => disposeLater([detail, trainers, pick, tell, finish, busy]));
}

/// Reject modal: reason (5), optional message, tell by email. Returns true when rejected.
Future<bool> showRejectModal(BuildContext context, ApRow r) async {
  const reasons = [
    ('not_fit', 'Not a fit for our coaching', 'Their goal or health needs a specialist'),
    ('has_account', 'Already has an account', 'Signed up twice with another email'),
    ('fake', 'Wrong or fake details', 'Name, phone or photos do not look right'),
    ('no_trainer', 'No trainer free right now', 'They can sign up again later'),
    ('other', 'Something else', 'Write it in the message'),
  ];
  var reason = 'not_fit';
  var tell = true, busy = false;
  String? err;
  final msg = TextEditingController();
  final her = objective(r.gender);
  final ok = await showAppModal<bool>(
    context,
    title: 'Reject ${r.first}?',
    body: '${r.first} will not be able to log in. You can move $her back to Waiting later from History.',
    icon: AppIcons.close,
    danger: true,
    wide: true,
    content: (ctx) => StatefulBuilder(
      builder: (ctx, set) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 12, children: [
        Text('Reason', style: AppText.s(12.5, W.w7, color: AppColors.text2)),
        DrOpts([for (final (k, t, s) in reasons) DrOpt(title: t, sub: s, on: reason == k, onTap: () => set(() => reason = k))]),
        Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 6, children: [
          Text(reason == 'other' ? 'Message to $her' : 'Message to $her (optional)', style: AppText.label),
          AppTextField(controller: msg, maxLines: 3, placeholder: 'Thanks for signing up. Right now we…', error: err),
        ]),
        DrSwitch(title: 'Tell $her by email', sub: '${pronoun(r.gender, cap: true)} ${verb(r.gender, 'sees')} the reason and your message', value: tell, onChanged: (v) => set(() => tell = v)),
        Padding(
          padding: const EdgeInsets.only(top: 6, bottom: 6),
          child: Row(mainAxisAlignment: MainAxisAlignment.end, spacing: 8, children: [
            Flexible(child: AppButton('Cancel', expand: ctx.isPhone, onPressed: () => Navigator.of(ctx).pop(false))),
            Flexible(
              child: AppButton('Reject', kind: BtnKind.danger, expand: ctx.isPhone, loading: busy, onPressed: busy
                  ? null
                  : () async {
                      if (reason == 'other' && msg.text.trim().isEmpty) {
                        set(() => err = 'Write the reason in the message.');
                        return;
                      }
                      set(() => busy = true);
                      try {
                        await Services.api.post('approvals/${r.id}/reject/', {'reason': reason, 'message': msg.text.trim(), 'tell_client': tell});
                        if (ctx.mounted) Navigator.of(ctx).pop(true);
                      } on ApiError catch (e) {
                        set(() {
                          busy = false;
                          err = e.fields['message']?.join(' ') ?? e.message;
                        });
                      }
                    }),
            ),
          ]),
        ),
      ]),
    ),
  );
  msg.dispose();
  return ok ?? false;
}

/// Ask for info modal: what to do (multi), message, send by (WhatsApp, Email, App notice). True when sent.
Future<bool> showAskInfoModal(BuildContext context, ApRow r) async {
  final left = 5 - r.setupDone;
  final items = [
    ('setup', 'Finish profile setup', left > 0 ? '$left step${left == 1 ? '' : 's'} left in the app' : 'All steps are done'),
    ('health_form', 'Fill the health form again', 'Some PAR-Q answers are missing'),
    ('doctor_note', 'Send a doctor note', 'Needed for blood pressure, heart or recent surgery'),
    ('photo', 'Add a profile photo', 'So their trainer can recognise them'),
    ('phone', 'Check the phone number', 'The OTP did not go through'),
  ];
  final picked = <String>{r.setupDone < 5 ? 'setup' : (r.healthNote ? 'doctor_note' : 'photo')};
  final channels = <String>{'whatsapp', 'email'};
  final msg = TextEditingController(text: 'Hi ${r.first}, before we start please finish the steps below in the app. It takes about 5 minutes.');
  var busy = false;
  String? err;
  final ok = await showAppModal<bool>(
    context,
    title: 'Ask ${r.first} for more info',
    body: '${pronoun(r.gender, cap: true)} ${verb(r.gender, 'stays')} in Waiting. You get a notice when ${pronoun(r.gender)} ${verb(r.gender, 'updates')} ${possessive(r.gender)} profile.',
    icon: AppIcons.send,
    wide: true,
    content: (ctx) => StatefulBuilder(
      builder: (ctx, set) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 12, children: [
        Text('What ${verb(r.gender, 'does')} ${pronoun(r.gender)} need to do?', style: AppText.s(12.5, W.w7, color: AppColors.text2)),
        DrOpts([
          for (final (k, t, s) in items)
            DrOpt(title: t, sub: s, multi: true, on: picked.contains(k), onTap: () => set(() => picked.contains(k) ? picked.remove(k) : picked.add(k))),
        ]),
        Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 6, children: [
          Text('Message', style: AppText.label),
          AppTextField(controller: msg, maxLines: 3),
        ]),
        Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
          Text('Send by', style: AppText.s(12.5, W.w6, color: AppColors.muted)),
          for (final (k, l) in [('whatsapp', 'WhatsApp'), ('email', 'Email'), ('in_app', 'App notice')])
            FilterChipX(l, selected: channels.contains(k), onTap: () => set(() => channels.contains(k) ? channels.remove(k) : channels.add(k))),
        ]),
        if (err != null) Text(err!, style: AppText.s(12.5, W.w6, color: AppColors.badText)),
        Padding(
          padding: const EdgeInsets.only(top: 6, bottom: 6),
          child: Row(spacing: 8, children: [
            Expanded(child: CutText('${picked.length} thing${picked.length == 1 ? '' : 's'} asked', maxLines: 1, style: AppText.cap)),
            AppButton('Cancel', onPressed: () => Navigator.of(ctx).pop(false)),
            AppButton.primary('Send request', loading: busy, onPressed: busy
                ? null
                : () async {
                    if (picked.isEmpty || channels.isEmpty) {
                      set(() => err = picked.isEmpty ? 'Pick at least one thing to ask for.' : 'Pick at least one way to send it.');
                      return;
                    }
                    set(() {
                      busy = true;
                      err = null;
                    });
                    try {
                      await Services.api.post('approvals/${r.id}/ask-info/', {'items': picked.toList(), 'channels': channels.toList(), 'message': msg.text.trim()});
                      if (ctx.mounted) Navigator.of(ctx).pop(true);
                    } on ApiError catch (e) {
                      set(() {
                        busy = false;
                        err = e.message;
                      });
                    }
                  }),
          ]),
        ),
      ]),
    ),
  );
  msg.dispose();
  return ok ?? false;
}

/// History → move back to Waiting. True when moved.
Future<bool> showMoveBackModal(BuildContext context, ApRow r) async {
  final her = objective(r.gender), she = pronoun(r.gender, cap: true);
  final approved = r.status == 'approved';
  final tr = '${r.assigned?['full_name'] ?? 'The trainer'}';
  final points = approved
      ? [
          '$she cannot log in until someone approves $her again. ${possessive(r.gender)[0].toUpperCase()}${possessive(r.gender).substring(1)} data stays.',
          '$tr stops seeing $her as a client. Plans you assigned are paused, not deleted.',
          '$she ${verb(r.gender, 'shows')} at the top of Waiting with a "Moved back" tag.',
        ]
      : [
          '${possessive(r.gender)[0].toUpperCase()}${possessive(r.gender).substring(1)} rejection is undone. $she still cannot log in until you approve $her.',
          'The reason "${r.why}" stays in ${possessive(r.gender)} history.',
          '$she ${verb(r.gender, 'shows')} at the top of Waiting with a "Moved back" tag.',
        ];
  var tell = false, busy = false;
  final ok = await showAppModal<bool>(
    context,
    title: 'Move ${r.first} back to Waiting?',
    body: 'You can decide again from the Waiting tab.',
    icon: AppIcons.undo,
    content: (ctx) => StatefulBuilder(
      builder: (ctx, set) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 12, children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(border: Border.all(color: AppColors.line), borderRadius: AppRadius.all(10)),
          child: Row(spacing: 10, children: [
            apAvatar(r.client),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                CutText(r.name, maxLines: 1, style: AppText.s(13.5, W.w7)),
                CutText('${r.decision} by ${r.decidedBy?['full_name'] ?? 'the team'}${r.decided == null ? '' : ' · ${apDay(r.decided!)}'}', maxLines: 1, style: AppText.s(12, W.w5, color: AppColors.muted)),
              ]),
            ),
            AppBadge(r.decision, tone: approved ? Tone.ok : Tone.bad),
          ]),
        ),
        Text('What happens', style: AppText.s(12.5, W.w7, color: AppColors.text2)),
        for (final p in points)
          Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 8, children: [
            Text('•', style: AppText.s(13, W.w5, color: AppColors.text2)),
            Expanded(child: Text(p, style: AppText.s(13, W.w5, color: AppColors.text2, h: 1.45))),
          ]),
        DrSwitch(title: 'Tell $her by email', sub: 'Only if you want $her to know it is being looked at again', value: tell, onChanged: (v) => set(() => tell = v)),
        Padding(
          padding: const EdgeInsets.only(top: 6, bottom: 6),
          child: Row(mainAxisAlignment: MainAxisAlignment.end, spacing: 8, children: [
            Flexible(child: AppButton('Cancel', expand: ctx.isPhone, onPressed: () => Navigator.of(ctx).pop(false))),
            Flexible(
              child: AppButton.primary('Move back', icon: AppIcons.undo, expand: ctx.isPhone, loading: busy, onPressed: busy
                  ? null
                  : () async {
                      set(() => busy = true);
                      try {
                        await Services.api.post('approvals/${r.id}/move-back/', {'tell_client': tell});
                        if (ctx.mounted) Navigator.of(ctx).pop(true);
                      } on ApiError catch (e) {
                        set(() => busy = false);
                        if (ctx.mounted) showToast(ctx, 'Could not move ${r.first} back', sub: e.message, kind: ToastKind.info);
                      }
                    }),
            ),
          ]),
        ),
      ]),
    ),
  );
  return ok ?? false;
}

/// "Tue, 6 Oct".
String apDay(DateTime d) {
  const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  return '${days[d.weekday - 1]}, ${d.day} ${months[d.month - 1]}';
}
