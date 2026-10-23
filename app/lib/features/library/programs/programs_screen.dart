import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../app/services.dart';
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
import '../../../core/widgets/overlays.dart';
import '../../../core/widgets/responsive.dart';
import '../../../core/widgets/tabs.dart';
import '../../trainer/me/me_common.dart' show meField;
import '../lib_common.dart';
import '../../../core/widgets/tooltip.dart';
import 'builder_sheets.dart' show showNameModal;

/// Programs page (boards `Programs` / `ProgramsMobile`): master plans as cards, Active / Archived, search,
/// New program, and each card's ⋯ (Open · Duplicate · Archive / Restore · Delete). A card opens the builder.
/// What this person may do comes from `programs/counts/` → `can` and each card's `can_edit` (D-39).
class ProgramsScreen extends StatefulWidget {
  const ProgramsScreen({super.key});
  @override
  State<ProgramsScreen> createState() => _ProgramsScreenState();
}

class _ProgramsScreenState extends State<ProgramsScreen> {
  String tab = 'active', q = '';
  List<Map> rows = [];
  Map counts = const {};
  String? next;
  bool loading = true, more = false;
  ApiError? error;
  Timer? _debounce;
  int _req = 0;

  Map get _can => (counts['can'] as Map?) ?? const {};
  bool get canCreate => _can['create'] == true;

  @override
  void initState() {
    super.initState();
    programsChanged.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    programsChanged.removeListener(_load);
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final req = ++_req;
    setState(() => loading = rows.isEmpty);
    try {
      final r = await Future.wait([
        Services.api.get<Map>('programs/', query: {'tab': tab, 'search': q, 'page_size': 24}),
        Services.api.get<Map>('programs/counts/'),
      ]);
      if (req != _req || !mounted) return;
      setState(() {
        rows = [for (final x in r[0]['results'] as List) x as Map];
        next = r[0]['next'] as String?;
        counts = r[1];
        error = null;
        loading = false;
      });
    } on ApiError catch (e) {
      if (req != _req || !mounted) return;
      setState(() {
        error = e;
        loading = false;
      });
    }
  }

  Future<void> _more() async {
    final n = next;
    if (n == null || more) return;
    setState(() => more = true);
    try {
      final page = Uri.parse(n).queryParameters['page'];
      final r = await Services.api.get<Map>('programs/', query: {'tab': tab, 'search': q, 'page_size': 24, 'page': page});
      if (!mounted) return;
      setState(() {
        rows = [...rows, for (final x in r['results'] as List) x as Map];
        next = r['next'] as String?;
      });
    } on ApiError catch (e) {
      if (mounted) showToast(context, 'Could not load more', sub: e.message, kind: ToastKind.err);
    }
    if (mounted) setState(() => more = false);
  }

  void _search(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      q = v.trim();
      _load();
    });
  }

  // ─────────────────────────────── actions

  Future<void> _run(Future<void> Function() f, {String fail = 'Could not do that'}) async {
    try {
      await f();
    } on ApiError catch (e) {
      if (mounted) showToast(context, fail, sub: e.message, kind: ToastKind.err);
    }
    if (mounted) _load();
  }

  Future<void> _duplicate(Map p) async {
    if (!await confirmDuplicate(context, '"${p['name']}"', body: 'Same weeks and workouts, no clients. The original stays as it is.')) return;
    await _run(() async {
        final c = await Services.api.post<Map>('programs/${p['id']}/duplicate/');
        if (!mounted) return;
        showToast(context, 'Program duplicated', sub: '${c['name']}', action: 'Undo', onAction: () => _run(() => Services.api.delete('programs/${c['id']}/')));
      }, fail: 'Could not duplicate it');
  }

  void _archive(Map p) {
    final arch = p['archived'] == true;
    _run(() async {
      await Services.api.post('programs/${p['id']}/${arch ? 'unarchive' : 'archive'}/');
      if (!mounted) return;
      showToast(context, '${p['name']} ${arch ? 'restored' : 'archived'}',
          sub: 'Assigned clients keep their plan',
          action: 'Undo',
          onAction: () => _run(() => Services.api.post('programs/${p['id']}/${arch ? 'archive' : 'unarchive'}/')));
    });
  }

  Future<void> _delete(Map p) async {
    int n = 0;
    try {
      n = ((await Services.api.get<Map>('programs/${p['id']}/delete-preview/'))['clients'] as num?)?.toInt() ?? 0;
    } on ApiError catch (_) {}
    if (!mounted) return;
    final ok = await confirmAction(context,
        title: 'Delete this program?',
        body: '${p['name']} will be removed for good${n > 0 ? ' and unassigned from ${plural(n, 'client')}' : ''}. Workouts they already logged stay safe.',
        confirm: 'Delete',
        danger: true,
        icon: AppIcons.trash);
    if (!ok) return;
    _run(() async {
      await Services.api.delete('programs/${p['id']}/');
      if (!mounted) return;
      showToast(context, 'Program deleted', sub: '${p['name']}', action: 'Undo', onAction: () => _run(() => Services.api.post('programs/${p['id']}/restore/')));
    }, fail: 'Could not delete it');
  }

  Future<void> _rename(Map p) async {
    final v = await showNameModal(context,
        title: 'Rename program', sub: 'Clients see the new name in their app', label: 'Program name', initial: '${p['name']}', button: 'Save');
    if (v == null || v == p['name']) return;
    _run(() async {
      await Services.api.patch('programs/${p['id']}/', {'name': v});
      if (mounted) showToast(context, 'Program renamed', sub: v);
    }, fail: 'Could not rename it');
  }

  void _menu(BuildContext anchor, Map p) {
    final arch = p['archived'] == true, edit = p['can_edit'] == true;
    final n = (p['client_count'] as num?)?.toInt() ?? 0;
    showAppMenu(anchor, width: 230, [
      MenuEntry('Open', icon: AppIcons.open, onTap: () => context.go('/programs/${p['id']}')),
      if (edit) MenuEntry('Rename', icon: AppIcons.edit, onTap: () => _rename(p)),
      if (_can['assign'] == true && !arch) MenuEntry('Assign to clients', icon: AppIcons.clientsAlt, onTap: () => context.go('/programs/${p['id']}?open=assign')),
      if (n > 0) MenuEntry('See assigned clients', icon: AppIcons.eye, sub: plural(n, 'client'), onTap: () => context.go('/programs/${p['id']}?open=clients')),
      if (canCreate) MenuEntry(edit ? 'Duplicate' : 'Duplicate to edit', icon: AppIcons.copy, onTap: () => _duplicate(p)),
      if (edit) MenuEntry(arch ? 'Restore' : 'Archive', icon: arch ? AppIcons.undo : AppIcons.archive, onTap: () => _archive(p)),
      if (edit) const MenuEntry.separator(),
      if (edit) MenuEntry('Delete', icon: AppIcons.trash, danger: true, onTap: () => _delete(p)),
    ]);
  }

  // ─────────────────────────────── build

  @override
  Widget build(BuildContext context) {
    final phone = context.isPhone;
    return StaffPage(
      onRefresh: _load,
      header: PageTop(
        title: 'Programs',
        sub: 'Master plans for your clients. Change one and everyone following it gets the update.',
        actions: [
          if (canCreate)
            phone
                ? _PlusButton(onTap: () => showNewProgram(context))
                : AppButton.primary('New program', icon: AppIcons.plus, onPressed: () => showNewProgram(context)),
        ],
      ),
      children: [
        _tools(phone),
        if (loading)
          const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator(color: AppColors.accent, strokeWidth: 2.5)))
        else if (error != null)
          AppCard(child: EmptyState('Could not load programs', sub: error!.message, action: AppButton('Try again', onPressed: _load)))
        else if (rows.isEmpty)
          _empty()
        else ...[
          LayoutBuilder(builder: (context, b) {
            final cols = phone ? 1 : (b.maxWidth / 340).floor().clamp(1, 3);
            final gap = phone ? 10.0 : 16.0;
            final w = (b.maxWidth - gap * (cols - 1)) / cols;
            return Wrap(spacing: gap, runSpacing: gap, children: [
              for (final p in rows) SizedBox(width: w, child: _ProgramCard(p, phone: phone, onMenu: (a) => _menu(a, p))),
            ]);
          }),
          if (next != null) Center(child: AppButton(more ? 'Loading…' : 'Show more', onPressed: more ? null : _more)),
        ],
      ],
    );
  }

  Widget _tools(bool phone) {
    final tabs = SegmentedTabs<String>(
      items: [
        TabItem('active', 'Active', count: (counts['active'] as num?)?.toInt() ?? 0),
        TabItem('archived', 'Archived', count: (counts['archived'] as num?)?.toInt() ?? 0),
      ],
      value: tab,
      onChanged: (v) {
        if (v == tab) return;
        setState(() {
          tab = v;
          rows = [];
        });
        _load();
      },
    );
    final search = AppSearchField(placeholder: 'Search programs', icon: AppIcons.search, onChanged: _search);
    return Row(spacing: phone ? 8 : 10, children: [
      if (phone) Expanded(child: search) else SizedBox(width: 320, child: search),
      if (!phone) const Spacer(),
      tabs,
    ]);
  }

  Widget _empty() {
    final searching = q.isNotEmpty;
    return AppCard(
      child: EmptyState(
        searching ? 'No program matches' : (tab == 'active' ? 'No programs yet' : 'Nothing archived'),
        icon: AppIcons.dumbbell,
        sub: searching
            ? 'Try another name.'
            : tab == 'active'
                ? 'Build your first master plan and assign it to clients.'
                : 'Programs you archive are kept here and can be restored any time.',
      ),
    );
  }
}

/// Phone header: the blue + button (`.btn.pri` icon only, 36).
class _PlusButton extends StatelessWidget {
  const _PlusButton({required this.onTap});
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: 'New program',
        child: Hover(
          onTap: onTap,
          builder: (_, h, _) => Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: h ? AppColors.accentText : AppColors.accent, borderRadius: AppRadius.all(AppRadius.btn)),
            child: const AppIcon(AppIcons.plus, size: 18, color: AppColors.white),
          ),
        ),
      );
}

/// `.pg-card`. Phone: icon left of the name and goal, ⋯ on the right, then tags, week and footer full width.
class _ProgramCard extends StatelessWidget {
  const _ProgramCard(this.p, {required this.phone, required this.onMenu});
  final Map p;
  final bool phone;
  final void Function(BuildContext anchor) onMenu;

  @override
  Widget build(BuildContext context) {
    final arch = p['archived'] == true;
    final tone = AppColors.pgTones['${p['id']}'.codeUnits.fold<int>(0, (a, c) => a + c) % 4];
    final pattern = [for (final x in (p['week_pattern'] as List? ?? const [])) x == true];
    final days = pattern.where((x) => x).length;
    final icon = IconTile(AppIcons.dumbbell, size: 40, radius: 10, iconSize: 18, bg: tone.$1, fg: tone.$2);
    final dots = Builder(builder: (a) => AppIconButton(AppIcons.dots, tooltip: 'More actions', small: true, ghost: true, fill: true, onPressed: () => onMenu(a)));
    final name = CutText('${p['name']}',
        maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(phone ? 15.5 : 16, W.w8, ls: -0.24, h: 1.3));
    final goal = CutText('${p['goal_line'] ?? ''}'.isEmpty ? '${p['level_label'] ?? ''}' : '${p['goal_line']}',
        maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(phone ? 12.5 : 13, W.w5, color: AppColors.muted));
    final tags = Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
      AppBadge('${p['weeks']} weeks', tone: Tone.info, plain: true),
      // `.badge.plain` with no tone: no fill, dark bold text.
      SizedBox(
        height: 22,
        child: Center(widthFactor: 1, child: Text('$days days / week', style: AppText.s(11.5, W.w7, color: AppColors.text2))),
      ),
      if (arch) const AppBadge('Archived', tone: Tone.warn, plain: true),
    ]);
    // who made it sits at the right end of the same line
    final tagRow = Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 8, children: [
      Expanded(child: tags),
      if (p['owner'] is Map) ownerTag(p['owner'] as Map),
    ]);
    return Semantics(
      button: true,
      label: '${p['name']}',
      child: Hover(
        onTap: () => context.go('/programs/${p['id']}'),
        builder: (_, h, _) => Container(
          padding: phone ? const EdgeInsets.fromLTRB(14, 14, 14, 12) : const EdgeInsets.fromLTRB(18, 16, 18, 14),
          decoration: BoxDecoration(
            color: arch ? AppColors.pgArchBg : AppColors.card,
            borderRadius: AppRadius.all(AppRadius.card),
            border: Border.all(color: h ? AppColors.line2 : AppColors.line),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            // name and level sit next to the icon (Gautam), ⋯ at the right
            Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 12, children: [
              icon,
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 2, children: [name, goal])),
              Transform.translate(offset: const Offset(4, -2), child: dots),
            ]),
            SizedBox(height: phone ? 10 : 12),
            tagRow,
            SizedBox(height: phone ? 6 : 14),
            WeekPattern(pattern.length == 7 ? pattern : List.filled(7, false), muted: arch),
            SizedBox(height: phone ? 10 : 12),
            const Divider1(),
            SizedBox(height: phone ? 10 : 12),
            _foot(),
          ]),
        ),
      ),
    );
  }

  Widget _foot() {
    final n = (p['client_count'] as num?)?.toInt() ?? 0;
    final avs = [for (final c in (p['clients'] as List? ?? const [])) c as Map];
    final muted = AppText.s(12.5, W.w5, color: AppColors.muted);
    // Fixed height: "Not assigned" and the avatar row keep every card the same height.
    return SizedBox(height: 26, child: Row(spacing: 8, children: [
      if (n > 0) ...[
        SizedBox(
          height: 26,
          width: 26.0 + 19 * (avs.length + (n > avs.length ? 1 : 0) - 1).clamp(0, 3),
          child: Stack(children: [
            for (final (i, c) in avs.indexed)
              Positioned(left: 19.0 * i, child: _ring(AppAvatar('${c['full_name']}', size: 22, initials: '${c['initials']}', colors: AppColors.avatarCode('${c['avatar_color'] ?? 'c1'}')))),
            if (n > avs.length)
              Positioned(
                left: 19.0 * avs.length,
                child: _ring(Container(
                  width: 22,
                  height: 22,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(color: AppColors.sub, shape: BoxShape.circle),
                  child: Text('+${n - avs.length}', style: AppText.s(9.5, W.w8, color: AppColors.text2)),
                )),
              ),
          ]),
        ),
        Text(plural(n, 'client'), style: AppText.s(12.5, W.w7, color: AppColors.text2)),
      ] else ...[
        const AppIcon(AppIcons.clientsAlt, size: 15, color: AppColors.muted),
        Text('Not assigned', style: AppText.s(12.5, W.w6, color: AppColors.muted)),
      ],
      Expanded(child: CutText(editedOn(p['updated_at']), maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.right, style: muted)),
    ]));
  }

  Widget _ring(Widget av) => Container(
        padding: const EdgeInsets.all(2),
        decoration: const BoxDecoration(color: AppColors.card, shape: BoxShape.circle),
        child: av,
      );
}

/// New program modal: name, length (1–24 weeks), training days (1–7), week preview. Opens the builder.
Future<void> showNewProgram(BuildContext context) async {
  final name = TextEditingController();
  var weeks = 8, days = 4;
  var saving = false;
  final err = ValueNotifier<String?>(null);
  final id = await showAppModal<String>(
    context,
    title: 'New program',
    body: 'A master plan you can assign to any client',
    icon: AppIcons.dumbbell,
    width: 460,
    content: (ctx) => StatefulBuilder(
      builder: (ctx, set) {
        final steppers = [
          meField('Length', LibStepper(value: weeks, unit: 'weeks', min: 1, max: 24, onChanged: (v) => set(() => weeks = v))),
          meField('Training days per week', LibStepper(value: days, unit: 'days', min: 1, max: 7, onChanged: (v) => set(() => days = v))),
        ];
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 14, children: [
          ValueListenableBuilder(
            valueListenable: err,
            builder: (_, e, _) => meField('Program name',
                AppTextField(controller: name, placeholder: 'e.g. Strength Base', autofocus: !ctx.isPhone, onChanged: (_) => err.value = null),
                req: true, error: e),
          ),
          if (ctx.isPhone)
            ...steppers
          else
            Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 12, children: [for (final s in steppers) Expanded(child: s)]),
          Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 8, children: [
            WeekPattern([for (var i = 0; i < 7; i++) i < days], big: true),
            Text('The other days start as rest days. You can change every week later.', style: AppText.s(12, W.w5, color: AppColors.muted)),
          ]),
        ]);
      },
    ),
    actions: (ctx) => [
      AppButton('Cancel', expand: ctx.isPhone, onPressed: () => Navigator.of(ctx).pop()),
      StatefulBuilder(
        builder: (bctx, set) => AppButton.primary('Create program', expand: ctx.isPhone, loading: saving, onPressed: () async {
          set(() => saving = true);
          try {
            final p = await Services.api.post<Map>('programs/', {'name': name.text.trim(), 'weeks': weeks, 'days_per_week': days});
            if (ctx.mounted) Navigator.of(ctx).pop('${p['id']}');
          } on ApiError catch (e) {
            set(() => saving = false);
            if (!ctx.mounted) return;
            final f = e.field('name');
            err.value = f;
            showToast(ctx, 'Could not create it', sub: f ?? e.message, kind: ToastKind.err);
          }
        }),
      ),
    ],
  );
  disposeLater([name, err]);
  if (id != null && context.mounted) {
    showToast(context, 'Program created', sub: 'Add exercises to each day');
    context.go('/programs/$id');
  }
}
