import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app/services.dart';
import '../../../app/shell/page.dart';
import '../../../core/api/api_error.dart';
import '../../../core/icons/app_icons.dart';
import '../../../core/realtime/realtime.dart';
import '../../../core/theme/theme.dart';
import '../../../core/widgets/avatar.dart';
import '../../../core/widgets/button.dart';
import '../../../core/widgets/card.dart';
import '../../../core/widgets/hover.dart';
import '../../../core/widgets/overlays.dart';
import '../../../core/widgets/responsive.dart';
import '../../../core/widgets/tabs.dart';

const _page = 30;

/// One row of `notifications/` (or a live `notification` socket event, same names).
class StaffNotice {
  StaffNotice(Map j)
      : id = '${j['id']}',
        title = '${j['title'] ?? ''}',
        body = '${j['body'] ?? ''}',
        route = '${(j['data'] as Map?)?['route'] ?? ''}',
        actor = '${j['actor_name'] ?? ''}',
        initials = '${j['actor_initials'] ?? ''}',
        color = '${j['actor_color'] ?? ''}',
        at = DateTime.tryParse('${j['created_at']}')?.toLocal() ?? DateTime.now(),
        read = j['read_at'] != null;
  final String id, title, body, route, actor, initials, color;
  final DateTime at;
  bool read;
}

/// Admin and trainer → Notifications (D-59): everything the bell has ever shown, newest first. All / Unread tabs,
/// rows by day, tap opens the page it is about (and marks it read), ⋯ marks read / unread or deletes (Undo), Mark
/// all read (Undo), Show more (cursor paged). New ones come in live over the socket. No board for this page: it
/// uses the Activity log's card, day headers and footer, and the bell dropdown's rows.
class StaffNotificationsScreen extends StatefulWidget {
  const StaffNotificationsScreen({super.key, this.unreadOnly = false});
  final bool unreadOnly;
  @override
  State<StaffNotificationsScreen> createState() => _StaffNotificationsScreenState();
}

class _StaffNotificationsScreenState extends State<StaffNotificationsScreen> {
  late bool unreadTab = widget.unreadOnly;
  List<StaffNotice> rows = [];
  String? cursor;
  int unread = 0, total = 0;
  bool loading = true, more = false;
  ApiError? error;
  int _req = 0;
  StreamSubscription<RealtimeEvent>? _socket;

  /// Deletes wait for the toast's Undo (10 s); leaving the page sends them at once.
  final Map<String, Timer> _deleting = {};

  @override
  void initState() {
    super.initState();
    _load();
    _socket = Services.realtime.events.where((e) => e.event == 'notification' || e.event == 'unread').listen(_live);
  }

  @override
  void dispose() {
    _socket?.cancel();
    for (final MapEntry(key: id, value: t) in _deleting.entries) {
      t.cancel();
      _delete(id);
    }
    super.dispose();
  }

  Future<void> _load() async {
    final req = ++_req;
    setState(() => loading = true);
    try {
      final r = await Future.wait([
        Services.api.get<Map>('notifications/', query: {'page_size': _page, if (unreadTab) 'unread': 1}),
        Services.api.get<Map>('notifications/unread/'),
      ]);
      if (req != _req || !mounted) return;
      rows = [for (final x in (r[0]['results'] as List?) ?? const []) StaffNotice(x as Map)];
      cursor = _cursor(r[0]['next']);
      _counts(r[1]);
      error = null;
    } on ApiError catch (e) {
      if (req != _req || !mounted) return;
      error = e;
    }
    setState(() => loading = false);
  }

  void _counts(Map c) {
    unread = (c['count'] as num?)?.toInt() ?? unread;
    total = (c['total'] as num?)?.toInt() ?? total;
  }

  String? _cursor(Object? next) => next == null ? null : Uri.tryParse('$next')?.queryParameters['cursor'];

  Future<void> _more() async {
    if (cursor == null || more) return;
    final req = _req;
    setState(() => more = true);
    try {
      final r = await Services.api.get<Map>('notifications/', query: {'page_size': _page, 'cursor': cursor, if (unreadTab) 'unread': 1});
      if (req != _req || !mounted) return;
      final have = {for (final n in rows) n.id};
      rows = [...rows, for (final x in (r['results'] as List?) ?? const []) if (!have.contains('${(x as Map)['id']}')) StaffNotice(x)];
      cursor = _cursor(r['next']);
    } on ApiError catch (e) {
      if (mounted) showToast(context, 'Could not load more', sub: e.message, kind: ToastKind.info);
    }
    if (mounted) setState(() => more = false);
  }

  /// A new one goes on top (it is unread, so on both tabs); `unread` keeps the count in step with other tabs.
  void _live(RealtimeEvent e) {
    if (!mounted) return;
    setState(() {
      if (e.event == 'unread') {
        unread = (e.payload['count'] as num?)?.toInt() ?? unread;
        return;
      }
      final n = StaffNotice(e.payload);
      if (n.title.isEmpty || rows.any((r) => r.id == n.id)) return;
      rows = [n, ...rows];
      total++;
      unread++;
    });
  }

  void _tab(bool u) {
    if (u == unreadTab) return;
    setState(() {
      unreadTab = u;
      rows = [];
      cursor = null;
    });
    _load();
  }

  Future<void> _setRead(StaffNotice n, bool read) async {
    if (n.read == read) return;
    setState(() {
      n.read = read;
      unread = (unread + (read ? -1 : 1)).clamp(0, 1 << 30);
    });
    try {
      await Services.api.post('notifications/${n.id}/${read ? 'read' : 'unread_one'}/');
    } on ApiError catch (e) {
      if (!mounted) return;
      setState(() {
        n.read = !read;
        unread = (unread + (read ? 1 : -1)).clamp(0, 1 << 30);
      });
      showToast(context, 'Could not update', sub: e.message, kind: ToastKind.info);
    }
  }

  void _open(StaffNotice n) {
    _setRead(n, true);
    if (n.route.isNotEmpty) context.go(n.route);
  }

  Future<void> _readAll() async {
    final was = [for (final n in rows) if (!n.read) n];
    final count = unread;
    if (count == 0) return;
    setState(() {
      for (final n in was) {
        n.read = true;
      }
      unread = 0;
      if (unreadTab) rows = [];
    });
    try {
      await Services.api.post('notifications/read_all/');
    } on ApiError catch (e) {
      if (mounted) showToast(context, 'Could not mark all read', sub: e.message, kind: ToastKind.info);
      _load();
      return;
    }
    if (!mounted) return;
    showToast(context, 'All marked as read', sub: '$count notification${count == 1 ? '' : 's'}', kind: ToastKind.ok, action: 'Undo', onAction: () async {
      await Future.wait([for (final n in was) Services.api.post('notifications/${n.id}/unread_one/').catchError((_) => null)]);
      if (mounted) _load();
    });
  }

  void _remove(StaffNotice n) {
    final at = rows.indexOf(n);
    setState(() {
      rows.remove(n);
      total = (total - 1).clamp(0, 1 << 30);
      if (!n.read) unread = (unread - 1).clamp(0, 1 << 30);
    });
    _deleting[n.id] = Timer(const Duration(seconds: 10), () {
      _deleting.remove(n.id);
      _delete(n.id);
    });
    showToast(context, 'Notification deleted', sub: n.title, kind: ToastKind.ok, action: 'Undo', onAction: () {
      _deleting.remove(n.id)?.cancel();
      if (!mounted) return;
      setState(() {
        rows.insert(at.clamp(0, rows.length), n);
        total++;
        if (!n.read) unread++;
      });
    });
  }

  void _delete(String id) => Services.api.delete('notifications/$id/').catchError((_) => null);

  void _menu(BuildContext anchor, StaffNotice n) => showAppMenu(anchor, width: 210, [
        if (n.route.isNotEmpty) MenuEntry('Open', icon: AppIcons.open, onTap: () => _open(n)),
        n.read
            ? MenuEntry('Mark as unread', icon: AppIcons.bell, onTap: () => _setRead(n, false))
            : MenuEntry('Mark as read', icon: AppIcons.check, onTap: () => _setRead(n, true)),
        const MenuEntry.separator(),
        MenuEntry('Delete', icon: AppIcons.trash, danger: true, onTap: () => _remove(n)),
      ]);

  /// Admin: Emails & alerts → Team alerts. Trainer: My profile → Account (Notifications).
  void _settings() => context.go(Services.session.me?.role == Role.admin ? '/emails?tab=alerts' : '/me/account');

  // ─────────────────────────────── Page

  String get _sub {
    if (unread > 0) return '$unread unread · $total in all';
    return total > 0 ? 'All caught up · $total in all' : 'All caught up';
  }

  @override
  Widget build(BuildContext context) {
    final phone = context.isPhone;
    final compact = compactTop(context);
    return StaffPage(
      maxWidth: 820,
      onRefresh: _load,
      header: PageTop(
        title: 'Notifications',
        sub: _sub,
        actions: [
          AppButton('Mark all read', icon: AppIcons.check, iconOnly: compact, tooltip: 'Mark all read', onPressed: unread > 0 ? _readAll : null),
          AppButton('Settings', icon: AppIcons.gear, iconOnly: true, tooltip: 'Notification settings', onPressed: _settings),
        ],
      ),
      children: [
        AppCard(
          padding: EdgeInsets.zero,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Padding(
              padding: EdgeInsets.fromLTRB(phone ? 12 : 16, 6, phone ? 12 : 16, 0),
              child: UnderlineTabs<bool>(
                items: [TabItem(false, 'All', count: total), TabItem(true, 'Unread', count: unread)],
                value: unreadTab,
                onChanged: _tab,
              ),
            ),
            if (error != null && rows.isEmpty)
              EmptyState('Could not load notifications', sub: error!.message, action: AppButton('Try again', onPressed: _load))
            else if (loading && rows.isEmpty)
              const Padding(
                padding: EdgeInsets.all(40),
                child: Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.2, color: AppColors.accent))),
              )
            else if (rows.isEmpty)
              unreadTab
                  ? const EmptyState('All caught up', sub: 'You have read everything. New notifications show up here.', icon: AppIcons.check)
                  : const EmptyState('No notifications yet', sub: 'Check-ins, new clients, sessions and team news show up here.', icon: AppIcons.bell)
            else
              Opacity(opacity: loading ? .55 : 1, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: _days(phone))),
            if (rows.isNotEmpty) _foot(),
          ]),
        ),
      ],
    );
  }

  Widget _foot() {
    final all = unreadTab ? unread : total;
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppColors.line))),
      child: Row(children: [
        Expanded(child: Text('Showing ${rows.length} of ${all < rows.length ? rows.length : all}', style: AppText.cap)),
        if (cursor != null) AppButton('Show more', loading: more, onPressed: _more),
      ]),
    );
  }

  List<Widget> _days(bool phone) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final groups = <DateTime, List<StaffNotice>>{};
    for (final n in rows) {
      groups.putIfAbsent(DateTime(n.at.year, n.at.month, n.at.day), () => []).add(n);
    }
    final out = <Widget>[];
    for (final MapEntry(key: d, value: items) in groups.entries) {
      final diff = today.difference(d).inDays;
      final label = diff == 0 ? 'Today' : (diff == 1 ? 'Yesterday' : DateFormat(d.year == now.year ? 'EEE, d MMM' : 'd MMM y').format(d));
      out.add(Padding(
        padding: EdgeInsets.fromLTRB(phone ? 12 : 16, 14, 16, 6),
        child: Row(spacing: 6, children: [
          Text(label.toUpperCase(), style: AppText.s(11.5, W.w6, color: AppColors.muted, ls: .46)),
          Text('·', style: AppText.s(11.5, W.w5, color: AppColors.muted)),
          Text('${items.length}', style: AppText.s(11.5, W.w5, color: AppColors.muted)),
        ]),
      ));
      out.add(Padding(
        padding: EdgeInsets.symmetric(horizontal: phone ? 6 : 10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 2, children: [
          for (final n in items) _NoticeRow(n, today: diff == 0, onOpen: () => _open(n), onMenu: (b) => _menu(b, n)),
        ]),
      ));
    }
    return out;
  }
}

/// The bell dropdown's row, page size: who (initials) or a bell for the system, the title (bold while unread), the
/// body, the time, a blue dot while unread and ⋯ (always on touch, on hover with a mouse).
class _NoticeRow extends StatelessWidget {
  const _NoticeRow(this.n, {required this.today, required this.onOpen, required this.onMenu});
  final StaffNotice n;
  final bool today;
  final VoidCallback onOpen;
  final void Function(BuildContext anchor) onMenu;

  String get _time {
    if (!today) return DateFormat('h:mm a').format(n.at).toLowerCase();
    final d = DateTime.now().difference(n.at);
    if (d.inMinutes < 1) return 'just now';
    if (d.inHours < 1) return '${d.inMinutes} min ago';
    return '${d.inHours} h ago';
  }

  @override
  Widget build(BuildContext context) {
    final touch = !context.isDesktop;
    return Semantics(
      button: true,
      label: n.title,
      child: Hover(
        onTap: onOpen,
        builder: (_, h, _) => Container(
          padding: const EdgeInsets.fromLTRB(10, 10, 4, 10),
          decoration: BoxDecoration(
            color: h ? AppColors.sub : (n.read ? null : AppColors.tdNoteNew),
            borderRadius: AppRadius.all(AppRadius.item),
          ),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 12, children: [
            if (n.initials.isNotEmpty)
              AppAvatar(n.actor, size: 32, colors: AppColors.avatarCode(n.color.isEmpty ? 'c1' : n.color), initials: n.initials)
            else
              Container(
                width: 32,
                height: 32,
                alignment: Alignment.center,
                decoration: const BoxDecoration(color: AppColors.accentSoft, shape: BoxShape.circle),
                child: const AppIcon(AppIcons.bell, size: 15, color: AppColors.accent),
              ),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 2, children: [
                Text(n.title, style: AppText.s(13.5, n.read ? W.w6 : W.w7, h: 1.35, color: h && n.route.isNotEmpty ? AppColors.accentText : AppColors.text)),
                if (n.body.isNotEmpty) Text(n.body, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppText.s(12.5, W.w4, color: AppColors.text2, h: 1.4)),
                Text(_time, style: AppText.s(12, W.w5, color: AppColors.muted)),
              ]),
            ),
            SizedBox(
              width: 10,
              height: 30,
              child: Center(
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(color: n.read ? Colors.transparent : AppColors.accent, shape: BoxShape.circle),
                ),
              ),
            ),
            Opacity(
              opacity: touch || h ? 1 : 0,
              child: Builder(builder: (b) => AppIconButton(AppIcons.dots, tooltip: 'More', small: true, ghost: true, fill: true, onPressed: () => onMenu(b))),
            ),
          ]),
        ),
      ),
    );
  }
}
