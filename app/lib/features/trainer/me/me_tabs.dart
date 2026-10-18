import 'package:flutter/material.dart';

import '../../../app/services.dart';
import '../../../core/api/api_error.dart';
import '../../../core/icons/app_icons.dart';
import '../../../core/theme/theme.dart';
import '../../../core/widgets/avatar.dart';
import '../../../core/widgets/badge.dart' show FilterChipX;
import '../../../core/widgets/button.dart';
import '../../../core/widgets/card.dart';
import '../../../core/widgets/hover.dart';
import '../../../core/widgets/input.dart';
import '../../../core/widgets/overlays.dart';
import '../../../core/widgets/responsive.dart';
import '../../../core/widgets/tooltip.dart';
import 'me_common.dart';
import 'me_model.dart';
import 'me_overview.dart';

// ═══════════════════════════════ What clients see

/// Toggle rows (`.tp-perm`) with the live preview of "My trainer" in the client app. Each switch saves right away.
class MeClientsSeeTab extends StatefulWidget {
  const MeClientsSeeTab(this.c, {super.key});
  final MeController c;
  @override
  State<MeClientsSeeTab> createState() => _MeClientsSeeTabState();
}

class _MeClientsSeeTabState extends State<MeClientsSeeTab> {
  String who = 'your clients';
  MeController get c => widget.c;

  @override
  void initState() {
    super.initState();
    // "Live preview · what Riya sees": the first of the trainer's own clients.
    Services.api.get<Map>('clients/', query: {'page_size': 1, 'status': 'active'}).then((r) {
      final rows = (r['results'] as List?) ?? const [];
      if (rows.isNotEmpty && mounted) setState(() => who = '${(rows.first as Map)['full_name'] ?? ''}'.split(' ').first);
    }).catchError((_) {});
  }

  Future<void> _set(String k, bool v) async {
    try {
      await c.setVisible(k, v);
    } on ApiError catch (e) {
      if (mounted) showToast(context, 'Could not save', sub: e.message, kind: ToastKind.err);
    }
  }

  List<(String, String, String, bool)> get _rows {
    final soc = [for (final (k, _) in c.social) switch (k) { 'instagram' => 'Instagram', 'youtube' => 'YouTube', 'facebook' => 'Facebook', _ => 'Website' }];
    String on(String k, String s) => s.isNotEmpty ? s : (c.vis[k] == true ? 'Shown' : 'Hidden');
    return [
      ('photo_name', 'Photo and name', 'Clients always see this', true),
      ('speciality', 'Speciality', on('speciality', c.speciality.join(', ')), false),
      ('experience', 'Experience', on('experience', c.yearsText), false),
      ('about', 'About', on('about', '${c.profile['bio'] ?? ''}'.isEmpty ? '' : 'Short bio'), false),
      ('languages', 'Languages', on('languages', c.languages.join(', ')), false),
      ('certificates', 'Certificates', 'Only verified ones you allow', false),
      ('social', 'Social media', on('social', soc.join(', ')), false),
      ('mobile', 'Mobile number', 'Only you and admins see it', false),
      ('email', 'Email', on('email', ''), false),
    ];
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: c,
        builder: (context, _) {
          final list = MeCard(
            title: 'What clients see',
            sub: 'On “My trainer” in the client app',
            child: Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Column(children: [
                for (final (k, t, s, lock) in _rows) MeToggleRow(title: t, sub: s, locked: lock, value: c.vis[k] == true, onChanged: (v) => _set(k, v)),
              ]),
            ),
          );
          final side = Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 10, children: [
            meLabel('Live preview · what $who sees'),
            _preview(),
            Text('Changes here show up in the client app right away.', style: AppText.cap),
          ]);
          return LayoutBuilder(builder: (context, b) {
            if (b.maxWidth < 940) return Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 12, children: [list, side]);
            return Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 24, children: [
              ConstrainedBox(constraints: const BoxConstraints(maxWidth: 520), child: SizedBox(width: (b.maxWidth - 404).clamp(0, 520), child: list)),
              SizedBox(width: 380, child: side),
            ]);
          });
        },
      );

  /// `.tp-phone`: the card as the client app shows it, built from the API's preview (only fields switched on).
  Widget _preview() {
    final p = c.preview;
    Widget r(String l, String v) => Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppColors.line))),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 12, children: [
            Text(l, style: AppText.s(12.5, W.w4, color: AppColors.muted)),
            Expanded(child: Text(v, textAlign: TextAlign.right, style: AppText.s(12.5, W.w6))),
          ]),
        );
    final spec = [for (final s in (p['speciality'] as List?) ?? const []) '$s'];
    final langs = [for (final s in (p['languages'] as List?) ?? const []) '$s'];
    final certs = [for (final x in (p['certificates'] as List?) ?? const []) x as Map];
    final soc = (p['social'] as Map?) ?? const {};
    final about = '${p['about'] ?? ''}';
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppColors.white, borderRadius: AppRadius.all(18), border: Border.all(color: AppColors.line)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 10, children: [
        Row(spacing: 12, children: [
          AppAvatar(c.name, size: 56, url: c.avatar, colors: AppColors.avatarCode(c.color), initials: c.initials),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(c.name, style: AppText.s(16, W.w7)),
              Text('Your trainer', style: AppText.s(12, W.w5, color: AppColors.muted)),
            ]),
          ),
        ]),
        Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (spec.isNotEmpty) r('Speciality', spec.join(', ')),
          if (p['experience_years'] != null) r('Experience', '${p['experience_years']} ${p['experience_years'] == 1 ? 'year' : 'years'}'),
          if (langs.isNotEmpty) r('Languages', langs.join(', ')),
          if (p['phone'] != null) r('Mobile', mePhone('${p['phone']}')),
          if (p['email'] != null) r('Email', '${p['email']}'),
        ]),
        if (about.isNotEmpty) Text(about, style: AppText.s(12.5, W.w4, color: AppColors.text2, h: 1.5)),
        if (p.containsKey('certificates')) ...[
          meLabel('Certificates'),
          if (certs.isEmpty) Text('None verified yet', style: AppText.s(12, W.w4, color: AppColors.muted)),
          for (final x in certs)
            Row(spacing: 8, children: [
              const AppIcon(AppIcons.award, size: 16, color: AppColors.tlChFg),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${x['name']}', style: AppText.s(12.5, W.w6)),
                  if ('${x['issuer'] ?? ''}'.isNotEmpty) Text('${x['issuer']}', style: AppText.s(11.5, W.w4, color: AppColors.muted)),
                ]),
              ),
            ]),
        ],
        if (soc.isNotEmpty) ...[
          meLabel('Follow'),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final e in soc.entries) meSocial(e.key == 'page_link' ? 'facebook' : (e.key == 'website' ? 'web' : '${e.key}'), e.key == 'instagram' ? '${e.value}' : meBareUrl('${e.value}')),
          ]),
        ],
      ]),
    );
  }
}

// ═══════════════════════════════ My access

/// Hints as the trainer reads them (the admin board says "his").
const _hints = {
  'clients.view_assigned': 'Profile, plans and logs',
  'clients.view_all': 'Every client of the gym',
  'clients.approve_signups': 'Only people invited by you',
  'training.programs_edit': 'For your clients',
  'nutrition.meal_plans': 'Make and change',
};

/// Board "Ask for more access" options → permission keys.
const _asks = [
  ('clients.view_all', 'See all clients', 'To cover other trainers'),
  ('training.edit_templates', 'Edit gym templates', 'Change master programs and meal plans'),
  ('checkins.edit_forms', 'Edit check-in forms', 'Change the gym’s forms'),
  ('clients.pause', 'Pause or resume clients', ''),
];

/// My access: level card (Switched on, Clients you see, Asked for, Ask for more access) and the read-only
/// permission chips ("Ticked ones are on for you. The rest only Vimal can switch on.").
class MeAccessTab extends StatelessWidget {
  const MeAccessTab(this.c, {super.key});
  final MeController c;

  @override
  Widget build(BuildContext context) {
    final phone = context.isPhone;
    final asked = c.asked;
    final n = (c.stats['clients'] as num?) ?? 0;
    final tip = switch ('${c.me['access_mode']}') {
      'all' => 'Every client of the gym: their plans, logs and check-ins. Set by Vimal.',
      'custom' => 'Vimal picked what you can do below.',
      _ => 'Only the clients given to you: their plans, logs and check-ins. Set by Vimal.',
    };
    final ask = AppButton('Ask for more access', icon: AppIcons.key, expand: phone, onPressed: () => showAskAccess(context, c));
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 16, children: [
      _AccessCard(c: c, phone: phone, tip: tip, clients: n.toInt(), asked: asked, ask: ask),
      AppCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const CardHeader('What you can do', sub: 'Ticked ones are on for you. The rest only Vimal can switch on.', padding: EdgeInsets.fromLTRB(16, 14, 16, 12)),
          for (final g in c.groups) _group(g, phone),
        ]),
      ),
    ]);
  }

  Widget _group(Map g, bool phone) {
    final items = [for (final i in g['items'] as List) i as Map];
    final on = items.where((i) => i['on'] == true).length;
    final head = Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, spacing: 6, children: [
      Text('${g['group']}', style: AppText.s(13, W.w7)),
      Text('$on of ${items.length}', style: AppText.s(12, W.w5, color: AppColors.muted)),
    ]);
    final chips = Wrap(spacing: 6, runSpacing: 6, children: [
      for (final i in items)
        AppTooltip(
          message: _hints[i['key']] ?? ('${i['hint'] ?? ''}'.isNotEmpty ? '${i['hint']}' : (i['on'] == true ? 'On' : 'Off')),
          child: Container(
            height: 28,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(color: i['on'] == true ? AppColors.permOnBg : AppColors.permOffBg, borderRadius: AppRadius.all(7)),
            child: Row(mainAxisSize: MainAxisSize.min, spacing: 5, children: [
              AppIcon(i['on'] == true ? AppIcons.check : AppIcons.lock, size: 13, color: i['on'] == true ? AppColors.permOnText : AppColors.muted),
              Text('${i['label']}', style: AppText.s(12.5, W.w6, color: i['on'] == true ? AppColors.permOnText : AppColors.muted)),
            ]),
          ),
        ),
    ]);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppColors.line))),
      child: LayoutBuilder(builder: (context, b) {
        if (b.maxWidth < 560) return Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 8, children: [head, chips]);
        return Row(crossAxisAlignment: CrossAxisAlignment.center, spacing: 12, children: [SizedBox(width: 130, child: head), Expanded(child: chips)]);
      }),
    );
  }
}

/// "Your access" card (`.card.me-acc`): the level with its icon and what it means, Ask for more access, then a strip
/// with Switched on (14 of 19 and a bar of one segment a permission), Clients you see and Asked for.
class _AccessCard extends StatelessWidget {
  const _AccessCard({required this.c, required this.phone, required this.tip, required this.clients, required this.asked, required this.ask});
  final MeController c;
  final bool phone;
  final String tip;
  final int clients;
  final Map<String, dynamic>? asked;
  final Widget ask;

  @override
  Widget build(BuildContext context) {
    final on = c.permsOn, total = c.permsTotal;
    final pct = total == 0 ? 0 : (on * 100 / total).round();
    final level = Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: phone ? 12 : 14, children: [
      IconTile(AppIcons.key, size: phone ? 40 : 48, radius: phone ? 11 : 13, iconSize: phone ? 20 : 24, bg: AppColors.hover, fg: AppColors.accentText),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 3, children: [
          Text('YOUR ACCESS', style: AppText.s(phone ? 11 : 11.5, W.w7, color: AppColors.muted, ls: .5)),
          Row(spacing: 6, children: [
            Flexible(child: Text(c.accessLevel, style: AppText.s(phone ? 17 : 19, W.w8, ls: -0.3))),
            AppTooltip(message: tip, child: const AppIcon(AppIcons.infoAlt, size: 15, color: AppColors.muted)),
          ]),
          Text(tip.replaceFirst(' Set by Vimal.', ''), style: AppText.s(phone ? 12.5 : 13, W.w5, color: AppColors.text2, h: 1.4)),
        ]),
      ),
    ]);

    // One segment a permission: blue = switched on.
    final bar = Row(spacing: 3, children: [
      for (var i = 0; i < total; i++)
        Expanded(
          child: Container(
            height: 6,
            decoration: BoxDecoration(color: i < on ? AppColors.accent : AppColors.segTrack, borderRadius: AppRadius.all(3)),
          ),
        ),
    ]);
    Widget label(String t) => Text(t.toUpperCase(), style: AppText.s(11, W.w7, color: AppColors.muted, ls: .44));
    final switched = Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 6, children: [
      label('Switched on'),
      Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, spacing: 6, children: [
        Text('$on', style: AppText.s(20, W.w8, ls: -0.4, tabular: true)),
        Text('of $total', style: AppText.s(13, W.w6, color: AppColors.muted)),
        const Spacer(),
        Text('$pct%', style: AppText.s(12.5, W.w7, color: AppColors.accentText, tabular: true)),
      ]),
      bar,
    ]);
    final sees = Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 6, children: [
      label('Clients you see'),
      Row(spacing: 8, children: [
        IconTile(c.seesAll ? AppIcons.clients : AppIcons.person, size: 26, radius: 7, iconSize: 14, bg: AppColors.okBg, fg: AppColors.okText),
        Flexible(child: Text(c.seesAll ? 'Every client' : 'Only yours ($clients)', maxLines: 2, style: AppText.s(14, W.w7, h: 1.25))),
      ]),
    ]);
    final a = asked;
    final askedW = Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 6, children: [
      label('Asked for'),
      if (a == null)
        Row(spacing: 8, children: [
          const IconTile(AppIcons.check, size: 26, radius: 7, iconSize: 14, bg: AppColors.sub, fg: AppColors.muted),
          Flexible(child: Text('Nothing', style: AppText.s(14, W.w7, color: AppColors.text2))),
        ])
      else
        Row(spacing: 8, children: [
          const IconTile(AppIcons.clock, size: 26, radius: 7, iconSize: 14, bg: AppColors.warnBg, fg: AppColors.warnText),
          Flexible(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 1, children: [
              Text((a['labels'] as List).join(', '), maxLines: 2, overflow: TextOverflow.ellipsis, style: AppText.s(13.5, W.w7, h: 1.25)),
              Text('Waiting for Vimal${a['at'] == null ? '' : ' · sent ${meDmy(a['at'])}'}', style: AppText.s(12, W.w6, color: AppColors.warnText)),
            ]),
          ),
        ]),
    ]);
    const vline = SizedBox(height: 52, child: VerticalDivider(width: 1, thickness: 1, color: AppColors.line));
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(color: AppColors.card, borderRadius: AppRadius.all(AppRadius.card), border: Border.all(color: AppColors.line)),
      child: LayoutBuilder(builder: (context, b) {
        final wide = b.maxWidth >= 600, mid = b.maxWidth >= 700;
        final head = Padding(
          padding: phone ? const EdgeInsets.fromLTRB(16, 16, 16, 14) : const EdgeInsets.fromLTRB(20, 18, 20, 16),
          child: wide
              ? Row(crossAxisAlignment: CrossAxisAlignment.center, spacing: 20, children: [Expanded(child: level), ask])
              : level,
        );
        final strip = Container(
          padding: phone ? const EdgeInsets.fromLTRB(16, 14, 16, 14) : const EdgeInsets.fromLTRB(20, 14, 20, 16),
          decoration: const BoxDecoration(color: AppColors.tableHead, border: Border(top: BorderSide(color: AppColors.line))),
          child: mid
              ? Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                  Expanded(flex: 5, child: Padding(padding: const EdgeInsets.only(right: 20), child: switched)),
                  vline,
                  Expanded(flex: 4, child: Padding(padding: const EdgeInsets.symmetric(horizontal: 20), child: sees)),
                  vline,
                  Expanded(flex: 4, child: Padding(padding: const EdgeInsets.only(left: 20), child: askedW)),
                ])
              : Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 14, children: [
                  switched,
                  const Divider1(),
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(child: Padding(padding: const EdgeInsets.only(right: 12), child: sees)),
                    Expanded(child: askedW),
                  ]),
                ]),
        );
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          head,
          strip,
          if (!wide)
            Container(
              padding: phone ? const EdgeInsets.fromLTRB(16, 12, 16, 14) : const EdgeInsets.fromLTRB(20, 12, 20, 14),
              decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppColors.line))),
              child: ask,
            ),
        ]);
      }),
    );
  }
}

/// "Ask for more access" modal: one of the options the trainer does not have yet, a reason, Send request.
Future<void> showAskAccess(BuildContext context, MeController c) async {
  final perms = (c.me['permissions'] as Map?) ?? const {};
  final opts = _asks.where((a) => perms[a.$1] != true).toList();
  if (opts.isEmpty) {
    showToast(context, 'You have all of these already', sub: 'Talk to Vimal for anything else', kind: ToastKind.info);
    return;
  }
  var pick = opts.first.$1;
  var sending = false;
  String? err;
  final why = TextEditingController();
  final sent = await showAppModal<String>(
    context,
    title: 'Ask for more access',
    body: 'Vimal gets your request and decides.',
    icon: AppIcons.key,
    width: 480,
    content: (ctx) => StatefulBuilder(
      builder: (ctx, set) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 14, children: [
        meField(
          'What do you need?',
          Container(
            decoration: BoxDecoration(borderRadius: AppRadius.all(10), border: Border.all(color: AppColors.line2)),
            clipBehavior: Clip.antiAlias,
            child: Column(children: [
              for (final (i, (k, t, s)) in opts.indexed)
                Hover(
                  onTap: () => set(() => pick = k),
                  builder: (_, h, _) => Container(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                    decoration: BoxDecoration(
                      color: pick == k ? AppColors.hover : (h ? AppColors.sub : null),
                      border: i == 0 ? null : const Border(top: BorderSide(color: AppColors.line)),
                    ),
                    child: Row(spacing: 10, children: [
                      AppRadio(selected: pick == k),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 1, children: [
                          Text(t, style: AppText.s(13.5, W.w7)),
                          if (s.isNotEmpty) Text(s, style: AppText.s(12, W.w5, color: AppColors.muted)),
                        ]),
                      ),
                    ]),
                  ),
                ),
            ]),
          ),
        ),
        meField('Why (optional)', AppTextField(controller: why, placeholder: 'I cover Karan’s clients on Sundays', maxLines: 3, minLines: 2), error: err),
      ]),
    ),
    actions: (ctx) => [
      AppButton('Cancel', expand: ctx.isPhone, onPressed: () => Navigator.of(ctx).pop()),
      StatefulBuilder(
        builder: (bctx, set) => AppButton.primary('Send request', expand: ctx.isPhone, loading: sending, onPressed: () async {
          set(() => sending = true);
          try {
            await c.askAccess([pick], why.text.trim());
            if (ctx.mounted) Navigator.of(ctx).pop(pick);
          } on ApiError catch (e) {
            err = e.message;
            set(() => sending = false);
            if (ctx.mounted) showToast(ctx, 'Could not send it', sub: e.message, kind: ToastKind.err);
          }
        }),
      ),
    ],
  );
  why.dispose();
  if (sent != null && context.mounted) {
    showToast(context, 'Request sent to Vimal', sub: _asks.firstWhere((a) => a.$1 == sent).$2, kind: ToastKind.ok);
  }
}

// ═══════════════════════════════ My activity

const _ranges = [('today', 'Today'), ('7d', 'Last 7 days'), ('30d', 'Last 30 days'), ('3m', 'Last 3 months'), ('all', 'All time')];
const _kinds = [('', 'All'), ('checkin', 'Check-in'), ('plan', 'Plan'), ('client', 'Client'), ('login', 'Login')];
const _page = 8;

/// My activity: range menu, kind chips with counts, rows by day (old → new), "Showing 8 of 11" + Show more.
class MeActivityTab extends StatefulWidget {
  const MeActivityTab(this.c, {super.key});
  final MeController c;
  @override
  State<MeActivityTab> createState() => _MeActivityTabState();
}

class _MeActivityTabState extends State<MeActivityTab> {
  String range = '7d', kind = '';
  List<Map> rows = [];
  Map counts = const {}, days = const {};
  int total = 0;
  bool loading = true, more = false, hasMore = false;
  ApiError? error;
  int _req = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Map<String, dynamic> get _q => {'range': range, if (kind.isNotEmpty) 'kind': kind, 'limit': _page};

  Future<void> _load() async {
    final req = ++_req;
    setState(() => loading = true);
    try {
      final r = await Services.api.get<Map>('trainers/me/activity/', query: _q);
      if (req != _req || !mounted) return;
      rows = [for (final x in (r['results'] as List?) ?? const []) x as Map];
      counts = (r['counts'] as Map?) ?? const {};
      days = (r['days'] as Map?) ?? const {};
      total = (r['count'] as num?)?.toInt() ?? rows.length;
      hasMore = r['has_more'] == true;
      error = null;
    } on ApiError catch (e) {
      if (req != _req || !mounted) return;
      error = e;
    }
    setState(() => loading = false);
  }

  Future<void> _more() async {
    if (more) return;
    final req = _req;
    setState(() => more = true);
    try {
      final r = await Services.api.get<Map>('trainers/me/activity/', query: {..._q, 'offset': rows.length});
      if (req != _req || !mounted) return;
      rows = [...rows, for (final x in (r['results'] as List?) ?? const []) x as Map];
      days = {...days, ...((r['days'] as Map?) ?? const {})};
      hasMore = r['has_more'] == true;
    } on ApiError catch (e) {
      if (mounted) showToast(context, 'Could not load more', sub: e.message, kind: ToastKind.info);
    }
    if (mounted) setState(() => more = false);
  }

  int _n(String k) => ((counts[k.isEmpty ? 'all' : k] as num?) ?? 0).toInt();

  @override
  Widget build(BuildContext context) {
    if (error != null && rows.isEmpty) return MeError(error!.message, onRetry: _load);
    return AppCard(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          CardHeader('My activity', sub: 'What you did in the app', padding: const EdgeInsets.fromLTRB(16, 12, 16, 6), action: _rangeButton()),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
            child: Row(spacing: 6, children: [
              for (final (k, l) in _kinds)
                FilterChipX(l, selected: kind == k, count: _n(k), onTap: () {
                  if (kind == k) return;
                  setState(() => kind = k);
                  _load();
                }),
            ]),
          ),
          if (loading && rows.isEmpty)
            const MeLoading()
          else if (rows.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 24),
              child: Text('Nothing matches. Try a longer date range or fewer filters.', textAlign: TextAlign.center, style: AppText.s(13, W.w5, color: AppColors.muted)),
            )
          else
            Opacity(opacity: loading ? .55 : 1, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: _days())),
          if (rows.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(top: 6),
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
              decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppColors.line))),
              child: Row(children: [
                Expanded(child: Text('Showing ${rows.length} of ${total < rows.length ? rows.length : total}', style: AppText.cap)),
                if (hasMore) AppButton('Show more', size: BtnSize.sm, loading: more, onPressed: _more),
              ]),
            ),
        ]),
      ),
    );
  }

  Widget _rangeButton() {
    final label = _ranges.firstWhere((r) => r.$1 == range).$2;
    return Builder(
      builder: (b) => AppButton(label, size: BtnSize.sm, icon: AppIcons.calStat, trailingIcon: AppIcons.chevronDown, onPressed: () => showAppMenu(b, [
            for (final (v, l) in _ranges)
              MenuEntry(l, selected: v == range, onTap: () {
                if (v == range) return;
                setState(() => range = v);
                _load();
              }),
          ])),
    );
  }

  List<Widget> _days() {
    final groups = <DateTime, List<Map>>{};
    for (final r in rows) {
      final t = meParse(r['created_at']) ?? DateTime.now();
      groups.putIfAbsent(DateTime(t.year, t.month, t.day), () => []).add(r);
    }
    final out = <Widget>[];
    for (final MapEntry(key: d, value: items) in groups.entries) {
      final key = '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
      final n = (days[key] as num?)?.toInt() ?? items.length;
      out.add(Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
        child: Row(spacing: 6, children: [
          Text(meDayLabel(d).toUpperCase(), style: AppText.s(11.5, W.w6, color: AppColors.muted, ls: .46)),
          Text('·', style: AppText.s(11.5, W.w5, color: AppColors.muted)),
          Text('${n < items.length ? items.length : n}', style: AppText.s(11.5, W.w5, color: AppColors.muted)),
        ]),
      ));
      out.add(Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (var i = 0; i < items.length; i++) _ActRow(items[i], last: i == items.length - 1),
        ]),
      ));
    }
    return out;
  }
}

/// `.tp-tl-row`: round kind icon, "Verb <b>who</b>", old → new or a note, time on the right (hover: where from).
class _ActRow extends StatelessWidget {
  const _ActRow(this.r, {required this.last});
  final Map r;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final (ic, bg, fg) = meActLook('${r['kind']}');
    final from = '${r['change_from'] ?? ''}', to = '${r['change_to'] ?? ''}';
    final note = '${r['note'] ?? ''}', who = '${r['who'] ?? ''}';
    final src = '${r['source'] ?? ''}';
    final time = Padding(padding: const EdgeInsets.only(top: 5), child: Text(meTime(r['created_at']), style: AppText.s(12, W.w5, color: AppColors.muted)));
    return Stack(children: [
      if (!last) Positioned(left: 13, top: 34, bottom: 0, child: Container(width: 1.5, color: AppColors.line)),
      Padding(
        padding: const EdgeInsets.fromLTRB(0, 5, 0, 7),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 10, children: [
          Container(width: 28, height: 28, alignment: Alignment.center, decoration: BoxDecoration(color: bg, shape: BoxShape.circle), child: AppIcon(ic, size: 14, color: fg)),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 1, children: [
                Text.rich(TextSpan(style: AppText.s(13.5, W.w4, color: AppColors.text2, h: 1.3), children: [
                  TextSpan(text: '${r['verb']}'),
                  if (who.isNotEmpty) ...[const TextSpan(text: ' '), TextSpan(text: who, style: AppText.s(13.5, W.w6, h: 1.3))],
                ])),
                if (from.isNotEmpty || to.isNotEmpty)
                  Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 6, children: [
                    Text(from, style: AppText.s(12.5, W.w4, color: AppColors.muted).copyWith(decoration: TextDecoration.lineThrough, decorationColor: AppColors.muted)),
                    const AppIcon(AppIcons.arrowRightAlt, size: 13, color: AppColors.muted),
                    Text(to, style: AppText.s(12.5, W.w6, color: AppColors.accentText)),
                  ])
                else if (note.isNotEmpty)
                  Text(note, style: AppText.s(12.5, W.w4, color: AppColors.muted, h: 1.3)),
              ]),
            ),
          ),
          if (src.isEmpty) time else AppTooltip(message: src, side: TipSide.below, child: time),
        ]),
      ),
    ]);
  }
}
