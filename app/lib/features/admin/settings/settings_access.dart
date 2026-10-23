import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../app/services.dart';
import '../../../core/api/api_error.dart';
import '../../../core/icons/app_icons.dart';
import '../../../core/theme/theme.dart';
import '../../../core/widgets/badge.dart';
import '../../../core/widgets/button.dart';
import '../../../core/widgets/card.dart';
import '../../../core/widgets/hover.dart';
import '../../../core/widgets/input.dart';
import '../../../core/widgets/overlays.dart';
import '../../../core/widgets/responsive.dart';
import '../../../core/widgets/tooltip.dart';
import '../../trainer/client_profile/cp_content_drawers.dart' show DrSwitch;
import '../forms/forms_common.dart' show FmNote;
import 'settings_common.dart';
import 'settings_screen.dart' show stError, stLoading;

// ─────────────────────────────── Roles & access

/// Roles & access tab: the three role cards and `What each role can do`. Only the trainer cells that the app
/// enforces can change; the admin column, admin-only work and the client column are locked (D-53).
class RolesTab extends StatefulWidget {
  const RolesTab({super.key, required this.cw});
  final double cw;
  @override
  State<RolesTab> createState() => _RolesTabState();
}

class _RolesTabState extends State<RolesTab> {
  Map data = {};
  Map<String, bool> trainer = {}, client = {};
  ApiError? error;
  bool loading = true, saving = false;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final r = await Services.api.get<Map>('settings/roles/');
      if (!mounted) return;
      setState(() {
        _take(r);
        loading = false;
      });
    } on ApiError catch (e) {
      if (mounted) {
        setState(() {
          loading = false;
          error = e;
        });
      }
    }
  }

  void _take(Map r) {
    data = r;
    trainer = Map<String, bool>.from(r['trainer'] as Map);
    client = Map<String, bool>.from(r['client'] as Map);
  }

  bool get dirty => !_same(trainer, data['trainer']) || !_same(client, data['client']);
  bool _same(Map<String, bool> a, Object? b) => b is Map && a.entries.every((e) => b[e.key] == e.value);
  bool _locked(String role, String key) => ((data['locked'] as Map?)?[role] as List? ?? const []).contains(key);

  void _reset() {
    final d = data['defaults'] as Map? ?? {};
    setState(() {
      trainer = Map<String, bool>.from((d['trainer'] as Map?) ?? data['trainer']);
      client = Map<String, bool>.from((d['client'] as Map?) ?? data['client']);
      // locked cells keep their fixed value
      for (final k in [...trainer.keys]) {
        if (_locked('trainer', k)) trainer[k] = (data['trainer'] as Map)[k] == true;
      }
      for (final k in [...client.keys]) {
        if (_locked('client', k)) client[k] = (data['client'] as Map)[k] == true;
      }
    });
  }

  Future<void> _save() async {
    setState(() => saving = true);
    try {
      final r = await Services.api.put<Map>('settings/roles/', {'trainer': trainer, 'client': client});
      if (!mounted) return;
      setState(() {
        _take(r);
        saving = false;
      });
      showToast(context, 'Permissions saved', sub: 'Applied to every trainer and client');
    } on ApiError catch (e) {
      if (!mounted) return;
      setState(() => saving = false);
      showToast(context, 'Could not save', sub: e.message, kind: ToastKind.err);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (error != null && data.isEmpty) return stError('roles', error!, load);
    if (loading && data.isEmpty) return stLoading();
    final cw = widget.cw;
    final counts = data['counts'] as Map? ?? {};
    final tn = counts['trainer'] ?? 0, cn = counts['client'] ?? 0;
    final wide = cw >= 820;
    final cards = [
      _RoleCard(
        fill: wide,
        tone: 0,
        name: 'Admin',
        count: 'Owner · only one · you',
        what: 'Everything: clients, trainers, plans, content and settings',
        note: 'There is exactly one admin per gym. Ownership cannot be moved from inside the app, and trainers cannot be given admin access.',
      ),
      _RoleCard(
        fill: wide,
        tone: 1,
        name: 'Trainer',
        count: '$tn member${tn == 1 ? '' : 's'}',
        what: 'Assigned clients, programs, meal plans, daily and weekly check-ins',
        note: "A trainer's access level is set on the trainer's own profile.",
        link: 'Open trainers',
        onLink: () => context.go('/trainers'),
      ),
      _RoleCard(
        fill: wide,
        tone: 2,
        name: 'Client',
        count: '$cn active',
        what: 'Own plan, logging and check-ins',
        note: 'Clients only ever see their own plan and data.',
        link: 'Open clients',
        onLink: () => context.go('/clients'),
      ),
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 16, children: [
      if (wide)
        IntrinsicHeight(child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 14, children: [for (final c in cards) Expanded(child: c)]))
      else
        Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 14, children: cards),
      _matrix(cw),
    ]);
  }

  Widget _matrix(double cw) {
    final phone = cw < 600;
    final cell = phone ? 56.0 : 92.0;
    final perms = [for (final p in (data['permissions'] as List? ?? [])) p as Map];
    Widget head(String t) => SizedBox(width: cell, child: Text(t, textAlign: TextAlign.center, style: AppText.s(phone ? 11 : 12, W.w6, color: AppColors.text2)));
    Widget box(String role, String key) {
      if (role == 'admin') return const AppTooltip(message: 'The admin always has every permission', child: StBox(on: true, locked: true));
      final map = role == 'trainer' ? trainer : client;
      final on = map[key] == true;
      if (_locked(role, key)) {
        final why = role == 'client'
            ? 'Clients only ever see their own plan and data'
            : (on ? 'Every trainer always sees their own clients' : 'Only the admin can do this');
        return AppTooltip(message: why, child: StBox(on: on, locked: true));
      }
      return AppTooltip(
        message: on ? 'Take it away from trainers' : 'Give it to trainers',
        child: Hover(onTap: () => setState(() => map[key] = !on), builder: (_, _, _) => StBox(on: on)),
      );
    }

    final note = Text('The admin always has every permission. Changes apply to every trainer and client.', style: AppText.s(12.5, W.w6, color: AppColors.muted, h: 1.45));
    final buttons = [
      AppButton('Reset', kind: BtnKind.text, icon: AppIcons.undo, onPressed: _reset),
      AppButton.primary('Save', icon: AppIcons.check, loading: saving, onPressed: _save),
    ];
    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.line))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 2, children: [
            Text('What each role can do', style: AppText.s(15, W.w8)),
            Text(dirty ? 'Not saved yet' : 'Tick a box to give a role that permission.', style: AppText.s(12.5, W.w5, color: AppColors.muted)),
          ]),
        ),
        Container(
          color: AppColors.tableHead,
          padding: EdgeInsets.fromLTRB(phone ? 14 : 12, 9, phone ? 4 : 0, 9),
          child: Row(children: [
            Expanded(child: Text('Permission', style: AppText.s(phone ? 11 : 12, W.w6, color: AppColors.text2))),
            head('Admin'),
            head('Trainer'),
            head('Client'),
          ]),
        ),
        for (final p in perms)
          Container(
            padding: EdgeInsets.fromLTRB(phone ? 14 : 12, 10, phone ? 4 : 0, 10),
            decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppColors.line))),
            child: Row(children: [
              Expanded(child: Text('${p['label']}', style: AppText.s(13, W.w6, h: 1.35))),
              for (final role in ['admin', 'trainer', 'client']) SizedBox(width: cell, child: Center(child: box(role, '${p['key']}'))),
            ]),
          ),
        Container(
          padding: EdgeInsets.symmetric(horizontal: phone ? 14 : 18, vertical: 12),
          decoration: const BoxDecoration(
            color: AppColors.hbSaveBg,
            border: Border(top: BorderSide(color: AppColors.line)),
            borderRadius: BorderRadius.vertical(bottom: Radius.circular(AppRadius.card)),
          ),
          child: phone
              ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 10, children: [note, Row(children: [buttons[0], const Spacer(), buttons[1]])])
              : Row(spacing: 10, children: [Expanded(child: note), ...buttons]),
        ),
      ]),
    );
  }
}

/// `.st-rc`: one role.
class _RoleCard extends StatelessWidget {
  const _RoleCard({required this.tone, required this.name, required this.count, required this.what, required this.note, this.link, this.onLink, this.fill = false});
  final int tone;

  /// In a row of equal-height cards the button sits at the bottom (`margin-top: auto`).
  final bool fill;
  final String name, count, what, note;
  final String? link;
  final VoidCallback? onLink;
  @override
  Widget build(BuildContext context) {
    final tones = [AppColors.hbTones[0], AppColors.hbTones[1], AppColors.hbTones[2]];
    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 10, children: [
        Row(spacing: 10, children: [
          IconTile(AppIcons.shield, size: 34, radius: 9, iconSize: 18, bg: tones[tone].$1, fg: tones[tone].$2),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 2, children: [
              Text(name, style: AppText.s(15, W.w7)),
              Text(count, style: AppText.s(12, W.w6, color: AppColors.muted)),
            ]),
          ),
        ]),
        Text(what, style: AppText.s(13, W.w5, color: AppColors.text2, h: 1.5)),
        FmNote(AppIcons.lock, note),
        if (link != null) ...[
          if (fill) const Spacer(),
          Align(alignment: Alignment.centerLeft, child: AppButton(link!, size: BtnSize.sm, trailingIcon: AppIcons.chevronRight, onPressed: onLink)),
        ],
      ]),
    );
  }
}

// ─────────────────────────────── Integrations

const _intNames = {'whatsapp': 'WhatsApp Business', 'email_domain': 'Email sending', 'health': 'Apple Health / Health Connect'};
const _intShort = {'whatsapp': 'WA', 'email_domain': 'EM', 'health': 'HC'};
const _intText = {
  'whatsapp': 'Reminders, check-in nudges and invites on WhatsApp, from your business number.',
  'email_domain': 'Welcome emails, check-in reminders and alerts from your own address.',
  'health': 'Steps, sleep, heart rate and workouts from client phones.',
};
const _steps = {
  'whatsapp': [
    ('Connect a business number', 'The number must be registered with the WhatsApp Business API.'),
    ('Display name review', 'Meta reviews the display name, usually within 24 hours.'),
    ('Message templates', 'Reminders and nudges are sent from approved templates.'),
  ],
  'email_domain': [
    ('Add your domain', 'Tell us the domain your emails should come from, for example trainwithvimal.com.'),
    ('Add three DNS records', 'SPF, DKIM and DMARC records go into your domain provider (GoDaddy, Hostinger and others).'),
    ('We verify the records', 'DNS changes take 15 minutes to 48 hours. Until then emails keep going from the platform address.'),
  ],
};
const _health = [
  ('steps', 'Steps', 'Daily step count on the client profile and in Today'),
  ('sleep', 'Sleep', 'Hours slept, next to the daily check-in'),
  ('hr', 'Heart rate', 'Resting heart rate on the progress tab'),
  ('workouts', 'Workouts', 'Runs and rides done outside the app'),
];

String _statusLabel(String s) => switch (s) { 'connected' => 'Connected', 'pending' => 'Checking DNS', _ => 'Not connected' };
Tone _statusTone(String s) => switch (s) { 'connected' => Tone.ok, 'pending' => Tone.warn, _ => Tone.neutral };

class IntegrationsTab extends StatefulWidget {
  const IntegrationsTab({super.key, required this.cw});
  final double cw;
  @override
  State<IntegrationsTab> createState() => _IntegrationsTabState();
}

class _IntegrationsTabState extends State<IntegrationsTab> {
  List<Map> ints = [];
  ApiError? error;
  bool loading = true;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final r = await Services.api.get<List>('settings/integrations/');
      if (!mounted) return;
      setState(() {
        ints = [for (final x in r) x as Map];
        loading = false;
      });
    } on ApiError catch (e) {
      if (mounted) {
        setState(() {
          loading = false;
          error = e;
        });
      }
    }
  }

  void _put(Map row) => setState(() => ints = [for (final x in ints) x['kind'] == row['kind'] ? row : x]);

  Future<Map?> _op(String kind, String op, [Map<String, dynamic>? body]) async {
    final r = await Services.api.post<Map>('settings/integrations/$kind/$op/', body);
    if (mounted) _put(r);
    return r;
  }

  Future<void> _open(Map x) async {
    final kind = '${x['kind']}';
    final status = '${x['status']}';
    final res = await showIntegrationModal(context, x, op: _op);
    if (!mounted || res == null) return;
    if (res == 'disconnect') {
      final ok = await _confirmDisconnect(kind);
      if (!ok || !mounted) return;
      try {
        await _op(kind, 'disconnect');
        if (!mounted) return;
        showToast(context, '${_intNames[kind]} disconnected', action: 'Undo', onAction: () async {
          try {
            await _op(kind, 'undo', {'status': status});
          } on ApiError catch (e) {
            if (mounted) showToast(context, 'Could not undo', sub: e.message, kind: ToastKind.err);
          }
        });
      } on ApiError catch (e) {
        if (mounted) showToast(context, 'Could not disconnect', sub: e.message, kind: ToastKind.err);
      }
      return;
    }
    final row = res as Map;
    if (status == 'not_connected') {
      showToast(context, '${_intNames[kind]} connected',
          sub: kind == 'email_domain' ? (row['status'] == 'connected' ? 'Emails now come from your own address' : 'We will email you when all three are verified') : null);
    } else if (kind == 'email_domain') {
      row['status'] == 'connected'
          ? showToast(context, 'All three records are verified', sub: 'Emails now come from your own address')
          : showToast(context, 'Checking the DNS records', sub: 'We will email you when all three are verified');
    } else {
      showToast(context, 'Saved');
    }
  }

  Future<bool> _confirmDisconnect(String kind) async {
    final r = await showAppModal<bool>(
      context,
      title: 'Disconnect ${_intNames[kind]}?',
      body: switch (kind) {
        'whatsapp' => 'Automations and messages stop sending on WhatsApp. Email and push keep working.',
        'email_domain' => 'Emails go back to the platform address.',
        _ => 'Client health data stops syncing. Past data stays.',
      },
      icon: AppIcons.link,
      danger: true,
      actions: (ctx) => [
        AppButton('Keep it', onPressed: () => Navigator.of(ctx).pop(false), expand: ctx.isPhone),
        AppButton('Disconnect', kind: BtnKind.danger, onPressed: () => Navigator.of(ctx).pop(true), expand: ctx.isPhone),
      ],
    );
    return r == true;
  }

  @override
  Widget build(BuildContext context) {
    if (error != null && ints.isEmpty) return stError('integrations', error!, load);
    if (loading && ints.isEmpty) return stLoading();
    final cw = widget.cw;
    final wide = cw >= 980;
    // Apple Health / Health Connect card hidden for now (Gautam 2026-10-23): the phone side is not built yet.
    final cards = [for (final x in ints.where((x) => x['kind'] != 'health')) _IntCard(x: x, fill: wide, onOpen: () => _open(x))];
    final note = Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(color: AppColors.sub, borderRadius: AppRadius.all(8)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 8, children: [
        const Padding(padding: EdgeInsets.only(top: 1), child: AppIcon(AppIcons.mail, size: 16, color: AppColors.muted)),
        Expanded(
          child: Wrap(children: [
            Text('Which alerts go out, and the sender name clients see, are set in ', style: AppText.s(12.5, W.w5, color: AppColors.text2, h: 1.45)),
            Hover(
              onTap: () => context.go('/emails'),
              builder: (_, h, _) => Text('Emails & alerts.',
                  style: AppText.s(12.5, W.w6, color: AppColors.accentText, h: 1.45).copyWith(decoration: h ? TextDecoration.underline : null, decorationColor: AppColors.accentText)),
            ),
          ]),
        ),
      ]),
    );
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 16, children: [
      if (wide)
        IntrinsicHeight(child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 14, children: [for (final c in cards) Expanded(child: c)]))
      else
        Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 14, children: cards),
      note,
    ]);
  }
}

/// `.st-ic`: one integration card.
class _IntCard extends StatelessWidget {
  const _IntCard({required this.x, required this.onOpen, this.fill = false});
  final Map x;
  final bool fill;
  final VoidCallback onOpen;
  @override
  Widget build(BuildContext context) {
    final kind = '${x['kind']}', status = '${x['status']}';
    final (bg, fg) = AppColors.stIntTones[kind] ?? AppColors.hbTones[0];
    final used = [for (final u in (x['used'] as List? ?? [])) u as Map];
    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 10, children: [
        Row(spacing: 10, children: [
          Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: bg, borderRadius: AppRadius.all(11)),
            child: Text(_intShort[kind] ?? '', style: AppText.s(13, W.w8, color: fg)),
          ),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 2, children: [
              Text(_intNames[kind] ?? '${x['label']}', style: AppText.s(15, W.w7)),
              AppBadge(_statusLabel(status), tone: _statusTone(status), plain: true),
            ]),
          ),
        ]),
        Text(_intText[kind] ?? '', style: AppText.s(13, W.w5, color: AppColors.text2, h: 1.5)),
        Container(
          padding: const EdgeInsets.only(top: 10),
          decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppColors.line))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 6, children: [
            Text('USED IN', style: AppText.over),
            for (final u in used)
              Hover(
                onTap: () => context.go('${u['path']}'),
                builder: (_, h, _) => Row(mainAxisSize: MainAxisSize.min, spacing: 6, children: [
                  const AppIcon(AppIcons.link, size: 14, color: AppColors.accentText),
                  Flexible(
                    child: Text('${u['label']}',
                        style: AppText.s(13, W.w6, color: AppColors.accentText).copyWith(decoration: h ? TextDecoration.underline : null, decorationColor: AppColors.accentText)),
                  ),
                ]),
              ),
          ]),
        ),
        if (fill) const Spacer(),
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Row(spacing: 8, children: [
            Expanded(child: CutText('${x['meta'] ?? ''}', maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.cap)),
            status == 'not_connected'
                ? AppButton.primary('Connect', size: BtnSize.sm, onPressed: onOpen)
                : AppButton('Manage', size: BtnSize.sm, onPressed: onOpen),
          ]),
        ),
      ]),
    );
  }
}

/// Connect / Manage modal. Returns the updated row, 'disconnect' when the owner picked Disconnect, or null.
Future<Object?> showIntegrationModal(BuildContext context, Map x, {required Future<Map?> Function(String kind, String op, [Map<String, dynamic>? body]) op}) {
  final kind = '${x['kind']}', status = '${x['status']}';
  final cfg = (x['config'] as Map?) ?? {};
  final numC = TextEditingController(text: kind == 'whatsapp' && status != 'not_connected' ? '${x['meta'] ?? ''}' : '');
  if (numC.text == 'No business number yet') numC.clear();
  final domC = TextEditingController(text: '${cfg['domain'] ?? ''}');
  final types = <String, bool>{for (final h in _health) h.$1: ((cfg['types'] as Map?)?[h.$1] ?? h.$1 != 'hr') == true};
  final err = ValueNotifier<String?>(null);
  final busy = ValueNotifier<bool>(false);
  final conn = status != 'not_connected';
  final records = [for (final r in (cfg['records'] as List? ?? [])) r as Map];

  Future<void> go(BuildContext ctx) async {
    err.value = null;
    String o;
    Map<String, dynamic>? body;
    switch (kind) {
      case 'whatsapp':
        if (numC.text.trim().isEmpty) {
          err.value = 'Enter the business number.';
          return;
        }
        o = conn ? 'save' : 'connect';
        body = {'config': {'number': numC.text.trim()}};
      case 'email_domain':
        if (domC.text.trim().isEmpty) {
          err.value = 'Enter the domain your emails should come from.';
          return;
        }
        final same = domC.text.trim().toLowerCase() == '${cfg['domain'] ?? ''}'.toLowerCase();
        o = !conn ? 'connect' : (same ? 'check' : 'save');
        body = o == 'check' ? null : {'config': {'domain': domC.text.trim()}};
      default:
        if (!types.values.any((v) => v)) {
          err.value = 'Turn on at least one.';
          return;
        }
        o = conn ? 'save' : 'connect';
        body = {'config': {'types': types}};
    }
    busy.value = true;
    try {
      final r = await op(kind, o, body);
      if (ctx.mounted) Navigator.of(ctx).pop(r);
    } on ApiError catch (e) {
      busy.value = false;
      final f = e.fields;
      err.value = (f['number'] ?? f['domain'] ?? f['types'] ?? f['config'])?.first ?? e.message;
    }
  }

  Widget field(String label, TextEditingController c, String hint, TextInputType kb) => ValueListenableBuilder(
        valueListenable: err,
        builder: (_, e, _) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 6, children: [
          Text(label, style: AppText.label),
          AppTextField(controller: c, keyboard: kb, error: e, onChanged: (_) => err.value = null),
          if (e == null) Text(hint, style: AppText.s(12, W.w5, color: AppColors.muted)),
        ]),
      );

  final goLabel = !conn ? 'Connect' : (kind == 'email_domain' ? 'Check records again' : 'Save');
  return showAppModal<Object>(
    context,
    title: _intNames[kind] ?? '',
    body: conn ? _statusLabel(status) : 'Set it up once. It works for every client.',
    icon: AppIcons.link,
    width: 520,
    content: (ctx) => StatefulBuilder(
      builder: (ctx, set) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 16, children: [
        if (_steps[kind] != null)
          Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 12, children: [
            for (final (i, s) in _steps[kind]!.indexed)
              Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 10, children: [
                Builder(builder: (_) {
                  final ok = status == 'connected' || (status == 'pending' && i < 2);
                  return Container(
                    width: 24,
                    height: 24,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: ok ? AppColors.okBg : AppColors.sub, shape: BoxShape.circle),
                    child: Text('${i + 1}', style: AppText.s(12, W.w8, color: ok ? AppColors.okText : AppColors.text2)),
                  );
                }),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 2, children: [
                    Text(s.$1, style: AppText.s(13.5, W.w7)),
                    Text(s.$2, style: AppText.s(12.5, W.w5, color: AppColors.muted, h: 1.45)),
                  ]),
                ),
              ]),
          ]),
        if (kind == 'whatsapp') field('Business number', numC, 'Registered with the WhatsApp Business API', TextInputType.phone),
        if (kind == 'email_domain') ...[
          ListenableBuilder(
            listenable: domC,
            builder: (_, _) => field(
              'Sending domain',
              domC,
              'Emails come from hello@${domC.text.trim().isEmpty ? 'yourdomain.com' : domC.text.trim().toLowerCase()} once verified',
              TextInputType.url,
            ),
          ),
          Container(
            decoration: BoxDecoration(border: Border.all(color: AppColors.line), borderRadius: AppRadius.all(10)),
            child: Column(children: [
              for (final (i, d) in [('SPF', '@'), ('DKIM', 'twv._domainkey'), ('DMARC', '_dmarc')].indexed)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                  decoration: i == 0 ? null : const BoxDecoration(border: Border(top: BorderSide(color: AppColors.line))),
                  child: Row(spacing: 10, children: [
                    SizedBox(width: 56, child: Text(d.$1, style: AppText.s(13, W.w7))),
                    Expanded(child: CutText('TXT · ${d.$2}', maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.mono(12.5, color: AppColors.muted))),
                    Builder(builder: (_) {
                      final ok = status == 'connected' || records.any((r) => r['label'] == d.$1 && r['ok'] == true);
                      return AppBadge(ok ? 'Verified' : 'Waiting', tone: ok ? Tone.ok : Tone.warn, plain: true);
                    }),
                  ]),
                ),
            ]),
          ),
        ],
        if (kind == 'health') ...[
          Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 10, children: [
            for (final h in _health)
              DrSwitch(
                title: h.$2,
                sub: h.$3,
                value: types[h.$1] == true,
                onChanged: (v) {
                  err.value = null;
                  set(() => types[h.$1] = v);
                },
              ),
          ]),
          ValueListenableBuilder(
            valueListenable: err,
            builder: (_, e, _) => e == null ? const SizedBox.shrink() : Text(e, style: AppText.s(12, W.w6, color: AppColors.badText)),
          ),
          const FmNote(AppIcons.assign, 'Each client turns it on in their own app. Nothing is read without their permission.'),
        ],
      ]),
    ),
    lead: conn
        ? Align(alignment: Alignment.centerLeft, child: Builder(builder: (ctx) => AppButton('Disconnect', kind: BtnKind.textDanger, onPressed: () => Navigator.of(ctx).pop('disconnect'))))
        : null,
    actions: (ctx) => [
      if (conn && ctx.isPhone) AppButton('Disconnect', kind: BtnKind.textDanger, onPressed: () => Navigator.of(ctx).pop('disconnect')),
      AppButton('Cancel', onPressed: () => Navigator.of(ctx).pop(), expand: ctx.isPhone),
      ValueListenableBuilder(
        valueListenable: busy,
        builder: (_, b, _) => AppButton.primary(goLabel, icon: AppIcons.check, loading: b, onPressed: () => go(ctx), expand: ctx.isPhone),
      ),
    ],
  ).whenComplete(() => disposeLater([numC, domC, err, busy]));
}
