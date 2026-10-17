import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../app/services.dart';
import '../../../core/api/api_error.dart';
import '../../../core/icons/app_icons.dart';
import '../../../core/theme/theme.dart';
import '../../../core/widgets/avatar.dart';
import '../../../core/widgets/badge.dart';
import '../../../core/widgets/hover.dart';
import 'me_common.dart';
import 'me_model.dart';

/// Overview tab: Professional details, Contact and account, Certificates (left); This week, Clients who need you,
/// Recent activity (right).
class MeOverviewTab extends StatelessWidget {
  const MeOverviewTab(this.c, {super.key, required this.onTab, required this.onEdit});
  final MeController c;
  final ValueChanged<String> onTab;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) => MeColumns(
        leftFlex: 16,
        rightFlex: 10,
        left: [_pro(), _contact(), _certs()],
        right: [_week(), _attention(context), _MeRecent(c, onAll: () => onTab('activity'))],
      );

  Widget _pro() {
    final p = c.profile;
    final bio = '${p['bio'] ?? ''}', best = '${p['works_best_with'] ?? ''}';
    return MeCard(
      title: 'Professional details',
      sub: 'Clients see only what you switch on in What clients see',
      action: MeTextBtn('Edit', onTap: onEdit),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        MeKv([
          ('Speciality', c.speciality.isEmpty ? MeKv.text('') : Wrap(spacing: 4, runSpacing: 4, children: [for (final s in c.speciality) meChip(s)])),
          ('Experience', MeKv.text(c.since == null ? '' : '${c.yearsText} · since ${c.since}')),
          ('Trains', MeKv.text(c.mode)),
          ('Languages', MeKv.text(c.languages.join(', '))),
          ('Gender', MeKv.text(c.gender)),
          ('Best with', MeKv.text(best)),
        ]),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 4, children: [
            meLabel('About you'),
            Text(bio.isEmpty ? 'Nothing yet. Add a short bio in Edit my details.' : bio,
                style: AppText.s(13, W.w4, color: bio.isEmpty ? AppColors.muted : AppColors.text, h: 1.5)),
          ]),
        ),
        if (c.social.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 6, children: [
              meLabel('Social media'),
              Wrap(spacing: 6, runSpacing: 6, children: [for (final (k, t) in c.social) meSocial(k, t)]),
            ]),
          ),
      ]),
    );
  }

  Widget _contact() {
    final login = c.lastLogin;
    final loginText = login == null ? '' : '${'${login['text']}'.substring(0, 1).toUpperCase()}${'${login['text']}'.substring(1)} · ${login['device']}';
    return MeCard(
      title: 'Contact and account',
      action: MeTextBtn('Edit', onTap: onEdit),
      child: MeKv([
        ('Mobile', MeKv.text(c.phone)),
        ('Email', MeKv.text('${c.me['email'] ?? ''}')),
        ('Joined', MeKv.text(meDmy(c.me['joining_date']))),
        ('Last login', MeKv.text(loginText)),
        ('Most clients', MeKv.text('${c.me['max_clients'] ?? ''}')),
        ('Access', MeKv.text('${c.accessLevel} · ${c.permsOn} of ${c.permsTotal}')),
      ]),
    );
  }

  Widget _certs() {
    final top = c.certs.take(3).toList();
    return MeCard(
      title: 'Certificates',
      sub: c.certSummary,
      action: MeTextBtn('All documents', onTap: () => onTab('documents')),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: top.isEmpty
            ? Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text('Upload your certificates in Documents. Clients see them after Vimal verifies them.', style: AppText.s(12.5, W.w5, color: AppColors.muted, h: 1.45)),
              )
            : Column(children: [
                for (final (i, d) in top.indexed)
                  _row(
                    first: i == 0,
                    lead: meDocIcon('${d['kind']}'),
                    title: '${d['name']}',
                    sub: '${d['issuer'] ?? ''}',
                    trail: AppBadge(meDocBadge(d), tone: meDocTone(d), plain: true),
                  ),
              ]),
      ),
    );
  }

  Widget _week() {
    final w = (c.me['week'] as Map?) ?? const {};
    return MeCard(
      title: 'This week',
      sub: '${w['range'] ?? ''}',
      child: MeKv([for (final r in (w['rows'] as List?) ?? const []) ('${(r as Map)['label']}', MeKv.text('${r['value']}'))]),
    );
  }

  Widget _attention(BuildContext context) {
    final rows = [for (final r in (c.me['attention'] as List?) ?? const []) r as Map];
    final n = (c.stats['clients'] as num?) ?? 0;
    return MeCard(
      title: 'Clients who need you',
      sub: 'From your $n ${n == 1 ? 'client' : 'clients'}',
      action: MeTextBtn('My clients', onTap: () => context.go('/clients')),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: rows.isEmpty
            ? Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text('Everyone is on track.', style: AppText.s(12.5, W.w5, color: AppColors.muted)),
              )
            : Column(children: [
                for (final (i, r) in rows.indexed)
                  _row(
                    first: i == 0,
                    onTap: () => context.go('/clients/${r['id']}'),
                    lead: AppAvatar('${r['name']}', size: 30, colors: AppColors.avatarCode('${r['color'] ?? 'c1'}'), initials: '${r['initials'] ?? ''}'),
                    title: '${r['name']}',
                    sub: '${r['why']}',
                    trail: AppBadge('${r['badge']}', tone: r['tone'] == 'bad' ? Tone.bad : Tone.warn, plain: true),
                  ),
              ]),
      ),
    );
  }
}

/// `.tp-row` / `.tp-cert`: icon, bold line over a grey line, something on the right, line between rows.
Widget _row({required bool first, required Widget lead, required String title, String sub = '', Widget? trail, VoidCallback? onTap, bool small = false}) => Hover(
      onTap: onTap,
      builder: (_, h, _) => Container(
        padding: EdgeInsets.symmetric(vertical: small ? 8 : 10),
        decoration: BoxDecoration(border: first ? null : const Border(top: BorderSide(color: AppColors.line))),
        child: Row(spacing: 10, children: [
          lead,
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 1, children: [
              Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppText.s(13, small ? W.w4 : W.w6, color: onTap != null && h ? AppColors.accent : AppColors.text)),
              if (sub.isNotEmpty) Text(sub, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppText.s(12, W.w4, color: AppColors.muted)),
            ]),
          ),
          ?trail,
        ]),
      ),
    );

/// The round kind icon of My activity rows (`.tp-aic` / `.tp-tl-ic`).
(AppIconData, Color, Color) meActLook(String kind) => switch (kind) {
      'checkin' => (AppIcons.docLines, AppColors.tlCiBg, AppColors.tlCiFg),
      'plan' => (AppIcons.dumbbell, AppColors.tlPkBg, AppColors.tlPkFg),
      'client' => (AppIcons.usersAlt, AppColors.tlTlBg, AppColors.tlTlFg),
      'session' => (AppIcons.calendar, AppColors.tlPlBg, AppColors.tlPlFg),
      'login' => (AppIcons.logIn, AppColors.sub, AppColors.muted),
      _ => (AppIcons.activity, AppColors.sub, AppColors.muted),
    };

/// Recent activity card: the latest 5 things the trainer did, "All activity" opens the tab.
class _MeRecent extends StatefulWidget {
  const _MeRecent(this.c, {required this.onAll});
  final MeController c;
  final VoidCallback onAll;
  @override
  State<_MeRecent> createState() => _MeRecentState();
}

class _MeRecentState extends State<_MeRecent> {
  List<Map> rows = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await Services.api.get<Map>('trainers/me/activity/', query: {'range': 'all', 'limit': 5});
      rows = [for (final x in (r['results'] as List?) ?? const []) x as Map];
    } on ApiError catch (_) {}
    if (mounted) setState(() => loading = false);
  }

  String _when(Object? at) {
    final t = meParse(at);
    if (t == null) return '';
    final now = DateTime.now();
    final days = DateTime(now.year, now.month, now.day).difference(DateTime(t.year, t.month, t.day)).inDays;
    if (days == 0) return meTime(at);
    if (days == 1) return 'Yesterday';
    return meDayLabel(t).replaceFirst(RegExp(r'^\w+, '), '');
  }

  @override
  Widget build(BuildContext context) => MeCard(
        title: 'Recent activity',
        action: MeTextBtn('All activity', onTap: widget.onAll),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: loading
              ? const MeLoading()
              : rows.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Text('Nothing yet.', style: AppText.s(12.5, W.w5, color: AppColors.muted)),
                    )
                  : Column(children: [
                      for (final (i, r) in rows.indexed)
                        () {
                          final (ic, bg, fg) = meActLook('${r['kind']}');
                          final who = '${r['who'] ?? ''}';
                          return _row(
                            first: i == 0,
                            small: true,
                            lead: Container(
                              width: 26,
                              height: 26,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
                              child: AppIcon(ic, size: 14, color: fg),
                            ),
                            title: '${r['verb']}${who.isEmpty ? '' : ' $who'}',
                            trail: Text(_when(r['created_at']), style: AppText.s(12, W.w5, color: AppColors.muted)),
                          );
                        }(),
                    ]),
        ),
      );
}
