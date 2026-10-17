import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../app/shell/page.dart';
import '../../../core/api/api_error.dart';
import '../../../core/icons/app_icons.dart';
import '../../../core/theme/theme.dart';
import '../../../core/widgets/avatar.dart';
import '../../../core/widgets/badge.dart';
import '../../../core/widgets/button.dart';
import '../../../core/widgets/card.dart';
import '../../../core/widgets/hover.dart';
import '../../../core/widgets/input.dart';
import '../../../core/widgets/responsive.dart';
import '../../../core/widgets/tabs.dart';
import 'tc_model.dart';
import 'tc_parts.dart';

/// One list for the page and the phone's open check-in, so ← Back lands on the same tab, type and rows.
final _shared = TcController();

/// Check-ins (boards `TrainerCheckins` + `TrainerCheckinsMobile`). Web: list on the left (360 wide), the open
/// check-in on the right. Phone: the list; a tap opens the check-in in the same card (`/checkins/<id>`).
class TrainerCheckinsScreen extends StatefulWidget {
  const TrainerCheckinsScreen({super.key, this.id});

  /// `/checkins/<id>`: open this one.
  final String? id;

  @override
  State<TrainerCheckinsScreen> createState() => _TrainerCheckinsScreenState();
}

class _TrainerCheckinsScreenState extends State<TrainerCheckinsScreen> {
  TcController get c => _shared;
  late final q = TextEditingController(text: c.search);
  final _list = ScrollController();

  @override
  void initState() {
    super.initState();
    if (widget.id != null) c.selected = widget.id;
    c.load(keepSelection: widget.id != null || c.rows.isNotEmpty);
  }

  @override
  void dispose() {
    q.dispose();
    _list.dispose();
    super.dispose();
  }

  void _profile(String clientId) => context.go('/clients/$clientId');

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: c,
        builder: (context, _) {
          final phone = context.isPhone;
          final open = phone && widget.id != null;
          return StaffPage(
            onRefresh: () => c.load(keepSelection: true),
            header: PageTop(title: 'Check-ins', sub: c.subline),
            children: [
              AppCard(
                padding: EdgeInsets.zero,
                child: phone
                    ? (open ? _phoneDetail(widget.id!) : _listPane(phone: true))
                    : SizedBox(
                        // Fits the window under the title, so the page itself never scrolls (the list and the panel do).
                        height: (MediaQuery.sizeOf(context).height - 180).clamp(480.0, 1000.0),
                        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                          Container(
                            width: 360,
                            decoration: const BoxDecoration(border: Border(right: BorderSide(color: AppColors.line))),
                            child: _listPane(phone: false),
                          ),
                          Expanded(child: _detail()),
                        ]),
                      ),
              ),
            ],
          );
        },
      );

  // ─────────────────────────────── Left: tabs, search, type chips, rows

  Widget _listPane({required bool phone}) {
    final pad = phone ? 16.0 : 14.0;
    final top = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: EdgeInsets.fromLTRB(pad, 4, pad, 0),
        child: UnderlineTabs<String>(
          items: [for (final (k, l) in TcController.tabs) TabItem(k, l, count: k == 'to_review' ? (c.tabCount(k) > 0 ? c.tabCount(k) : null) : null)],
          value: c.tab,
          onChanged: c.setTab,
        ),
      ),
      Padding(
        padding: EdgeInsets.fromLTRB(pad, 12, pad, 8),
        child: AppSearchField(controller: q, placeholder: 'Search client', icon: AppIcons.search, onChanged: c.setSearch),
      ),
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.fromLTRB(pad, 0, pad, 10),
        child: Row(spacing: 6, children: [
          for (final (k, l) in TcController.kinds) FilterChipX(l, selected: c.kind == k, count: c.kindCount(k), onTap: () => c.setKind(k)),
        ]),
      ),
    ]);
    final items = _items(phone);
    if (phone) return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [top, items]);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      top,
      Expanded(child: SingleChildScrollView(controller: _list, child: items)),
    ]);
  }

  Widget _items(bool phone) {
    if (c.error != null && c.rows.isEmpty) {
      return EmptyState('Could not load check-ins', sub: c.error!.message, action: AppButton('Try again', onPressed: c.load));
    }
    if (c.rows.isEmpty && c.loading) {
      return const Padding(
        padding: EdgeInsets.all(40),
        child: Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.2, color: AppColors.accent))),
      );
    }
    if (c.rows.isEmpty) {
      final caught = c.tab == 'to_review' && c.kind == 'all' && c.search.isEmpty;
      return _Blank(
        icon: AppIcons.checkCircle,
        title: caught ? 'All caught up' : 'Nothing here',
        sub: caught ? 'New check-ins show up here as clients send them.' : (c.search.isNotEmpty ? 'Try another name.' : 'Try another type.'),
      );
    }
    return Padding(
      padding: EdgeInsets.fromLTRB(phone ? 6 : 8, 0, phone ? 6 : 8, phone ? 6 : 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (final (i, r) in c.rows.indexed)
          _Row(
            r,
            on: !phone && r.id == c.selected,
            divider: phone && i > 0,
            gap: !phone && i > 0,
            onTap: () => phone ? context.go('/checkins/${r.id}') : c.select(r.id),
          ),
        if (c.next != null)
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 4),
            child: Center(child: AppButton('Show more', size: BtnSize.sm, loading: c.more, onPressed: c.loadMore)),
          ),
      ]),
    );
  }

  // ─────────────────────────────── Right: the open check-in

  Widget _detail() {
    final r = c.current;
    if (r == null) {
      return c.loading && c.rows.isEmpty
          ? const SizedBox()
          : const _Blank(icon: AppIcons.clipboard, title: 'Pick a check-in', sub: 'Its answers show here.');
    }
    return TcPanel(key: ValueKey('tc-${r.id}-${r.reviewed}'), c: c, row: r, onProfile: () => _profile(r.clientId));
  }

  /// Phone `/checkins/<id>`: the row from the list, or (opened from a link) from the check-in itself.
  Widget _phoneDetail(String id) {
    final r = c.rows.where((x) => x.id == id).firstOrNull;
    void back() => context.go('/checkins');
    if (r != null) {
      if (c.selected != id) WidgetsBinding.instance.addPostFrameCallback((_) => c.select(id));
      return TcPanel(key: ValueKey('tc-${r.id}-${r.reviewed}'), c: c, row: r, onProfile: () => _profile(r.clientId), onBack: back);
    }
    return FutureBuilder<Map>(
      future: c.detail(id),
      builder: (context, snap) {
        if (snap.hasError) {
          return EmptyState('Could not open this check-in',
              sub: snap.error is ApiError ? (snap.error as ApiError).message : null, action: AppButton('Back to check-ins', onPressed: back));
        }
        if (!snap.hasData) {
          return const Padding(
            padding: EdgeInsets.all(40),
            child: Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.2, color: AppColors.accent))),
          );
        }
        final row = TcRow(snap.data!);
        return TcPanel(key: ValueKey('tc-${row.id}-${row.reviewed}'), c: c, row: row, onProfile: () => _profile(row.clientId), onBack: back);
      },
    );
  }
}

/// `.tc-it`: avatar · name + age (red after 48 h) · kind · summary or "✓ Replied: …".
class _Row extends StatelessWidget {
  const _Row(this.r, {required this.on, required this.divider, required this.gap, required this.onTap});
  final TcRow r;
  final bool on, divider, gap;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final line = r.reviewed ? 'Replied: ${r.reply.isNotEmpty ? r.reply : 'Reviewed'}' : r.summary;
    return Padding(
      padding: EdgeInsets.only(top: gap ? 2 : 0),
      child: Hover(
        onTap: onTap,
        builder: (context, h, _) => Container(
          padding: EdgeInsets.symmetric(horizontal: 10, vertical: divider || !gap && !on ? 11 : 10),
          decoration: BoxDecoration(
            color: on || h ? AppColors.hover : null,
            borderRadius: divider ? null : BorderRadius.circular(8),
            border: divider ? const Border(top: BorderSide(color: AppColors.line)) : null,
          ),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 10, children: [
            AppAvatar(r.name, size: 32, colors: AppColors.avatarCode(r.color), initials: r.initials),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(spacing: 8, children: [
                  Expanded(
                    child: Text(r.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(13.5, r.reviewed ? W.w6 : W.w7)),
                  ),
                  Text(r.age, style: AppText.s(12, W.w7, color: r.late ? AppColors.badText : AppColors.muted)),
                ]),
                const SizedBox(height: 1),
                Text(r.kind, style: AppText.s(12, W.w6, color: AppColors.text2)),
                const SizedBox(height: 2),
                Row(spacing: 4, children: [
                  if (r.reviewed) const AppIcon(AppIcons.check, size: 13, color: AppColors.tdOkIcon),
                  Expanded(child: Text(line, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(12.5, W.w5, color: AppColors.muted))),
                ]),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

/// `.tc-empty` / `.tc-none`.
class _Blank extends StatelessWidget {
  const _Blank({required this.icon, required this.title, required this.sub});
  final AppIconData icon;
  final String title, sub;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 48),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          AppIcon(icon, size: 26, color: AppColors.muted),
          const SizedBox(height: 10),
          Text(title, textAlign: TextAlign.center, style: AppText.s(14, W.w7)),
          const SizedBox(height: 4),
          Text(sub, textAlign: TextAlign.center, style: AppText.s(12.5, W.w5, color: AppColors.muted)),
        ]),
      );
}
