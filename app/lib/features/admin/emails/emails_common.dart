import 'package:flutter/material.dart';

import '../../../app/services.dart';
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
import '../../trainer/client_profile/cp_content_drawers.dart' show drField;
import '../forms/forms_common.dart' show FmCheck;

/// Emails & alerts (boards `Emails` + `EmailsMobile`, D-52): channels, groups, limits and the preview cards.

const emChannels = ['email', 'push', 'whatsapp', 'in_app'];
const emChannelLabel = {'email': 'Email', 'push': 'Push', 'whatsapp': 'WhatsApp', 'in_app': 'In-app'};
// Packages group hidden: packages are not used for now (Gautam 2026-10-23).
const emGroups = [('access', 'Access'), ('coaching', 'Coaching'), /* ('packages', 'Packages'), */ ('team', 'Team')];

/// Message length per channel (server `CHANNEL_LIMITS`) and the subject / title limit.
const emBodyLimit = {'email': 2000, 'push': 120, 'whatsapp': 1000, 'in_app': 500};
const emSubjectLimit = 50;
const emVariables = ['first_name', 'coach_name', 'gym_name', /* 'package_name', (packages hidden) */ 'date'];

/// "How Sana, a sample client, would see it" (board sample values).
const emSample = {
  'first_name': 'Sana',
  'coach_name': 'Meera',
  'gym_name': 'Train With Vimal',
  'package_name': 'Quarterly Transformation',
  'date': '7 Oct',
};

String emFill(String s) => s.replaceAllMapped(RegExp(r'\{\{\s*(\w+)\s*\}\}'), (m) => emSample[m[1]] ?? m[0]!);

/// Subject (email) or title (push, in-app); WhatsApp has none.
String emHeadKey(String ch) => ch == 'email' ? 'subject' : 'title';

/// `.em-cd i` / `.em-ct i`: green dot when the channel is on.
class EmDot extends StatelessWidget {
  const EmDot(this.on, {super.key});
  final bool on;
  @override
  Widget build(BuildContext context) => Container(
        width: 7,
        height: 7,
        decoration: BoxDecoration(color: on ? AppColors.emDotOn : AppColors.emDotOff, shape: BoxShape.circle),
      );
}

/// The message as one client sees it on this channel (`.hb-phone.em-ph`), or the Off note.
class EmPreview extends StatelessWidget {
  const EmPreview({super.key, required this.channel, required this.on, required this.head, required this.body, required this.sender, required this.replyTo});
  final String channel, head, body, sender, replyTo;
  final bool on;

  @override
  Widget build(BuildContext context) {
    final h = emFill(head), b = emFill(body);
    final Widget inner;
    if (!on) {
      inner = Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Text('Off: this message is not sent on this channel.', style: AppText.s(13, W.w5, color: AppColors.muted, h: 1.5)),
      );
    } else if (channel == 'email') {
      inner = EmMail(sender: sender, line: 'to Sana · $replyTo', subject: h, body: b);
    } else if (channel == 'push') {
      inner = Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(color: AppColors.emPushBg, borderRadius: AppRadius.all(14), boxShadow: AppShadows.emPush),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 10, children: [
          Container(
            width: 32,
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: AppColors.text, borderRadius: AppRadius.all(8)),
            child: Text('TV', style: AppText.s(11, W.w8, color: AppColors.white)),
          ),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 2, children: [
              Row(spacing: 6, children: [
                Expanded(child: Text(h, style: AppText.s(13, W.w7))),
                Text('now', style: AppText.s(11, W.w5, color: AppColors.muted)),
              ]),
              Text(b, style: AppText.s(12.5, W.w5, color: AppColors.text2, h: 1.45)),
            ]),
          ),
        ]),
      );
    } else if (channel == 'whatsapp') {
      inner = ClipRRect(
        borderRadius: AppRadius.all(12),
        child: ColoredBox(
          color: AppColors.emWaWall,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Container(
              color: AppColors.emWaHead,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Text(sender, style: AppText.s(13, W.w7, color: AppColors.white)),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: Container(
                margin: const EdgeInsets.all(10),
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 6),
                decoration: const BoxDecoration(
                  color: AppColors.white,
                  borderRadius: BorderRadius.only(topLeft: Radius.circular(8), topRight: Radius.circular(8), bottomRight: Radius.circular(8), bottomLeft: Radius.circular(2)),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Text(b, style: AppText.s(12.5, W.w5, color: AppColors.emWaText, h: 1.5)),
                  Text('9:00 am', style: AppText.s(10.5, W.w5, color: AppColors.emWaTime)),
                ]),
              ),
            ),
          ]),
        ),
      );
    } else {
      inner = Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(color: AppColors.card, borderRadius: AppRadius.all(12), border: Border.all(color: AppColors.line)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 10, children: [
          IconTile(AppIcons.bell, size: 30, radius: 8, iconSize: 16, bg: AppColors.hbTones[0].$1, fg: AppColors.hbTones[0].$2),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 2, children: [
              Text(h, style: AppText.s(13, W.w7)),
              Text(b, style: AppText.s(12.5, W.w5, color: AppColors.text2, h: 1.45)),
            ]),
          ),
        ]),
      );
    }
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: AppColors.hbPhone, borderRadius: AppRadius.all(16)),
      child: inner,
    );
  }
}

/// `.em-mail`: sender row, subject, text (email preview and Sender → Clients see).
class EmMail extends StatelessWidget {
  const EmMail({super.key, required this.sender, required this.line, required this.subject, required this.body});
  final String sender, line, subject, body;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: AppColors.card, borderRadius: AppRadius.all(12), border: Border.all(color: AppColors.line)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 8, children: [
          Container(
            padding: const EdgeInsets.only(bottom: 8),
            decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.line))),
            child: Row(spacing: 8, children: [
              AppAvatar(sender, size: 24, initials: 'TV', colors: AppColors.avatarCode('c1')),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 1, children: [
                  CutText(sender, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(12.5, W.w7)),
                  CutText(line, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(11, W.w5, color: AppColors.muted)),
                ]),
              ),
            ]),
          ),
          Text(subject, style: AppText.s(14, W.w7)),
          Text(body, style: AppText.s(12.5, W.w5, color: AppColors.text2, h: 1.55)),
        ]),
      );
}

/// `.mb-sh`: side card title row.
Widget emSideHead(String title, {Widget? end}) => Row(spacing: 8, children: [
      Expanded(child: Text(title, style: AppText.s(14.5, W.w8))),
      ?end,
    ]);

/// `.fm-au`: an automation that uses this message (opens the builder).
class EmUsedRow extends StatelessWidget {
  const EmUsedRow({super.key, required this.name, required this.line, required this.onTap});
  final String name, line;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Hover(
        onTap: onTap,
        builder: (_, h, _) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(borderRadius: AppRadius.all(8), border: Border.all(color: h ? AppColors.line2 : AppColors.line)),
          child: Row(spacing: 8, children: [
            const AppIcon(AppIcons.bolt, size: 15, color: AppColors.fmBolt),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 1, children: [
                CutText(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(13, W.w6, color: h ? AppColors.accentText : AppColors.text)),
                CutText(line, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(11.5, W.w6, color: AppColors.muted)),
              ]),
            ),
            const AppIcon(AppIcons.chevronRight, size: 15, color: AppColors.muted),
          ]),
        ),
      );
}

/// Label with the red `*` (`.req`).
Widget emReq(String label) => Text.rich(TextSpan(text: label, style: AppText.label, children: [TextSpan(text: '*', style: AppText.label.copyWith(color: AppColors.badText))]));

// ─────────────────────────────── New message template

/// `New message template` modal: name, group, channels. Returns the new template or null.
Future<Map?> showNewTemplate(BuildContext context) {
  final name = TextEditingController();
  var group = 'coaching';
  final picked = <String>{'push', 'whatsapp'};
  String? error;
  var saving = false;
  const subs = {
    'email': 'Subject and a longer message',
    'push': 'Short title and text on the phone',
    'whatsapp': 'From your WhatsApp number',
    'in_app': "In the app's notifications",
  };
  return showAppModal<Map>(
    context,
    title: 'New message template',
    body: 'Write it once, then use it in any automation',
    icon: AppIcons.mail,
    width: 500,
    content: (ctx) => StatefulBuilder(
      builder: (ctx, set) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 16, children: [
        Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 6, children: [
          emReq('Template name'),
          AppTextField(controller: name, placeholder: 'Workout streak', error: error, autofocus: !ctx.isPhone, onChanged: (_) {
            if (error != null) set(() => error = null);
          }),
        ]),
        drField(
          'Group',
          // Fit-width tabs, not stretched (Gautam 2026-10-23).
          Align(
            alignment: Alignment.centerLeft,
            child: SegmentedTabs<String>(
              items: const [TabItem('access', 'Access'), TabItem('coaching', 'Coaching') /* , TabItem('packages', 'Packages') */],
              value: group,
              onChanged: (v) => set(() => group = v),
            ),
          ),
        ),
        Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 6, children: [
          Text('Channels', style: AppText.label),
          for (final (i, c) in emChannels.indexed)
            Hover(
              onTap: () => set(() => picked.contains(c) ? picked.remove(c) : picked.add(c)),
              builder: (_, h, _) => Container(
                padding: const EdgeInsets.symmetric(vertical: 9),
                decoration: BoxDecoration(border: i == 0 ? null : const Border(top: BorderSide(color: AppColors.line))),
                child: Row(spacing: 12, children: [
                  FmCheck(on: picked.contains(c), square: true),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 1, children: [
                      Text(emChannelLabel[c]!, style: AppText.s(13.5, W.w7, color: h ? AppColors.accentText : AppColors.text)),
                      Text(subs[c]!, style: AppText.s(12, W.w5, color: AppColors.muted)),
                    ]),
                  ),
                ]),
              ),
            ),
          Text('You can turn channels on or off later in the editor.', style: AppText.s(12, W.w5, color: AppColors.muted)),
        ]),
        // Smaller buttons with room under them (Gautam 2026-10-23).
        Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 12),
          child: Row(mainAxisAlignment: MainAxisAlignment.end, spacing: 8, children: [
          if (!ctx.isPhone) AppButton('Cancel', size: BtnSize.sm, onPressed: () => Navigator.of(ctx).pop()),
          Expanded(
            flex: ctx.isPhone ? 1 : 0,
            child: Opacity(
              opacity: picked.isEmpty ? .5 : 1,
              child: AppButton.primary('Create template', icon: AppIcons.check, size: BtnSize.sm, loading: saving, expand: ctx.isPhone, onPressed: () async {
                final n = name.text.trim();
                if (n.isEmpty) return set(() => error = 'Give the template a name.');
                if (picked.isEmpty) {
                  showToast(ctx, 'Pick a channel', sub: 'A template needs at least one', kind: ToastKind.err);
                  return;
                }
                set(() => saving = true);
                try {
                  final r = await Services.api.post<Map>('message-templates/', {
                    'name': n,
                    'group': group,
                    'channels': [for (final c in emChannels) if (picked.contains(c)) c],
                  });
                  if (ctx.mounted) Navigator.of(ctx).pop(r);
                } on ApiError catch (e) {
                  set(() {
                    saving = false;
                    error = e.fields['name']?.first ?? e.message;
                  });
                }
              }),
            ),
          ),
        ]),
        ),
      ]),
    ),
  );
}
