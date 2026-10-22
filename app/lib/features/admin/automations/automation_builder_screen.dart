import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart' show DateFormat;

import '../../../app/services.dart';
import '../../../app/shell/page.dart';
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
import '../../../core/widgets/select.dart';
import '../../../core/widgets/tabs.dart';
import '../../library/nutrition/meal_builder_sheets.dart' show NuStep;
import '../../trainer/client_profile/cp_content_drawers.dart' show DrSwitch, drField;
import '../../trainer/me/me_docs.dart' show DashedBox;
import 'automations_common.dart';

/// Admin → Automations → New automation / an automation (boards `AutomationNew`, `AutomationBuilder` and their
/// Mobile boards, D-51). 1 When does it start? (name, 15 triggers in Client / Schedule / Activity / Progress tabs,
/// the picked trigger's settings and a "Starts:" line) · 2 Who is it for? (package, trainer, stop when the client
/// responds) · 3 What happens next? (Wait, Send message, Send form, Assign task; ⋯ Move up / Move down / Remove).
/// Right: In plain words with what is still missing, and Last 30 days. Nothing is saved until Save as draft or
/// Turn on (Save and keep on when it is already on). `?starter=` fills it from a ready-made automation.
class AutomationBuilderScreen extends StatefulWidget {
  const AutomationBuilderScreen({super.key, required this.id, this.starter});
  final String id;
  final String? starter;
  @override
  State<AutomationBuilderScreen> createState() => _AutomationBuilderScreenState();
}

class _AutomationBuilderScreenState extends State<AutomationBuilderScreen> {
  bool get isNew => widget.id == 'new';
  bool loading = true, saving = false, dirty = false;
  ApiError? error;
  String? nameError;

  // what the pickers offer
  List<Map> forms = [], templates = [], trainers = [];
  List<String> packages = [];

  // the automation
  Map a = {};
  final name = TextEditingController();
  String status = 'draft', trigger = '', group = 'all', scopePackage = '', scopeTrainer = '', scopeTrainerName = '';
  final cfgs = <String, Map<String, Object?>>{};
  bool stop = true;
  List<AuStep> steps = [];
  Map runs = {};

  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  Future<void> load() async {
    try {
      final r = await Future.wait<Object>([
        Services.api.get<Map>('forms/', query: {'page_size': '100'}),
        Services.api.get<List>('message-templates/'),
        Services.api.get<Map>('trainers/', query: {'page_size': '100'}),
        Services.api.get<List>('automations/packages/'),
        if (!isNew) Services.api.get<Map>('automations/${widget.id}/'),
        if (!isNew) Services.api.get<Map>('automations/${widget.id}/runs/'),
        if (isNew && widget.starter != null) Services.api.get<Map>('automations/catalog/'),
      ]);
      if (!mounted) return;
      setState(() {
        forms = [for (final f in ((r[0] as Map)['results'] as List?) ?? const []) f as Map];
        templates = [for (final t in r[1] as List) t as Map];
        trainers = [for (final t in ((r[2] as Map)['results'] as List?) ?? const []) if ((t as Map)['status'] == 'active') t];
        packages = [for (final p in r[3] as List) '$p'];
        if (!isNew) {
          _fill(r[4] as Map);
          runs = r[5] as Map;
        } else if (widget.starter != null) {
          final s = [for (final x in ((r[4] as Map)['starters'] as List?) ?? const []) x as Map].where((x) => x['key'] == widget.starter).firstOrNull;
          if (s != null) _fillStarter(s);
        }
        error = null;
        loading = false;
      });
    } on ApiError catch (e) {
      if (mounted) {
        setState(() {
          error = e;
          loading = false;
        });
      }
    }
  }

  void _fill(Map d) {
    a = d;
    name.text = '${d['name']}';
    status = '${d['status']}';
    trigger = '${d['trigger'] ?? ''}';
    if (trigger.isNotEmpty) cfgs[trigger] = {...auDefaults(trigger), ...((d['trigger_config'] as Map?) ?? const {}).cast<String, Object?>()};
    scopePackage = '${d['scope_package'] ?? ''}';
    scopeTrainer = '${d['scope_trainer'] ?? ''}';
    if (scopeTrainer == 'null') scopeTrainer = '';
    scopeTrainerName = '${d['scope_trainer_name'] ?? ''}';
    stop = d['stop_on_response'] != false;
    steps = [for (final s in (d['steps'] as List?) ?? const []) AuStep.fromJson(s as Map)];
  }

  /// A ready-made automation: its forms are found by name in the library.
  void _fillStarter(Map s) {
    name.text = '${s['name']}';
    trigger = '${s['trigger']}';
    cfgs[trigger] = {...auDefaults(trigger), ...((s['trigger_config'] as Map?) ?? const {}).cast<String, Object?>()};
    stop = s['stop_on_response'] != false;
    steps = [
      for (final x in (s['steps'] as List?) ?? const [])
        AuStep.fromJson(x as Map)..form = _formIdByName('${((x['config'] as Map?) ?? const {})['form_name'] ?? ''}'),
    ];
    dirty = true;
  }

  String _formIdByName(String n) => '${forms.where((f) => f['name'] == n).firstOrNull?['id'] ?? ''}';

  // ─────────────────────────────── Lookups

  List<Map> get _sendable => forms.where((f) => f['status'] == 'published').toList();
  String _formName(String id) => '${forms.where((f) => '${f['id']}' == id).firstOrNull?['name'] ?? ''}';
  String _formLabel(AuStep s) {
    final n = s.form.isEmpty ? '' : _formName(s.form);
    return n.isNotEmpty ? n : (s.formName.isNotEmpty ? s.formName : 'Choose a form');
  }

  Map? _template(String key) => templates.where((t) => t['key'] == key).firstOrNull;
  String _templateName(String key) => '${_template(key)?['name'] ?? 'Choose a template'}';
  String _line(AuStep s) => s.line(templateName: _templateName, formLabel: _formLabel);

  Map<String, Object?> get _cfg => cfgs.putIfAbsent(trigger, () => auDefaults(trigger));

  void _edit(VoidCallback f) => setState(() {
        f();
        dirty = true;
      });

  /// What still stops it from being turned on (the warning in In plain words).
  List<String> get problems {
    final p = <String>[];
    if (trigger.isEmpty) p.add('Pick what starts it');
    if (trigger == 'form_sent' && '${_cfg['form'] ?? ''}'.isEmpty) p.add('Pick the form it waits for');
    if (steps.isEmpty) p.add('Add at least one step');
    if (steps.isNotEmpty && steps.last.kind == 'wait') p.add('Add a step that does something after the wait');
    for (final (i, s) in steps.indexed) {
      if (s.kind == 'message' && _template(s.template) == null) p.add('Step ${i + 1}: pick a message template');
      if (s.kind == 'form' && s.form.isEmpty) p.add('Step ${i + 1}: pick a form');
      if ((s.kind == 'message' || s.kind == 'form') && s.channels.isEmpty) p.add('Step ${i + 1}: pick at least one channel');
      if (s.kind == 'task' && s.title.trim().isEmpty) p.add('Step ${i + 1}: write the task');
    }
    return p;
  }

  // ─────────────────────────────── Page

  @override
  Widget build(BuildContext context) {
    if (loading || error != null) {
      final gone = error?.status == 404;
      return StaffPage(children: [
        _crumb(),
        if (loading)
          const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator(color: AppColors.accent, strokeWidth: 2.5)))
        else
          AppCard(
            child: EmptyState(gone ? 'This automation is gone' : 'Could not open this automation',
                icon: AppIcons.bolt,
                sub: gone ? 'It may have been deleted.' : error!.message,
                action: AppButton(gone ? 'Back to automations' : 'Try again', onPressed: gone ? () => context.go('/automations') : load)),
          ),
      ]);
    }
    final phone = context.isPhone;
    return StaffPage(
      children: [
        Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: phone ? 12 : 14, children: [_crumb(), _head(phone)]),
        LayoutBuilder(builder: (context, c) {
          final two = c.maxWidth >= 900;
          final main = Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 14, children: [_start(c.maxWidth - (two ? 356 : 0)), _who(), _next()]);
          final side = Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 14, children: [_plain(), _last30()]);
          if (!two) return Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 14, children: [main, side]);
          return Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 16, children: [Expanded(child: main), SizedBox(width: 340, child: side)]);
        }),
      ],
    );
  }

  Widget _crumb() => Row(spacing: 6, children: [
        Hover(
          onTap: _cancel,
          builder: (_, h, _) => Text('Automations', style: AppText.s(13, W.w5, color: h ? AppColors.text : AppColors.muted)),
        ),
        const AppIcon(AppIcons.chevronRight, size: 13, color: AppColors.chevron),
        Flexible(child: Text(isNew ? 'New automation' : 'Edit automation', maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(13, W.w6))),
      ]);

  Widget _head(bool phone) {
    final w = MediaQuery.sizeOf(context).width;
    final size = phone ? 17.0 : (w * 0.02).clamp(20.0, 28.0);
    final title = isNew ? 'New automation' : (name.text.trim().isEmpty ? '${a['name']}' : name.text.trim());
    final on = AppButton.primary(status == 'on' && !isNew ? 'Save and keep on' : 'Turn on', icon: AppIcons.bolt, loading: saving, expand: phone, onPressed: saving ? null : _turnOn);
    final cancel = AppButton('Cancel', expand: phone, onPressed: _cancel);
    final draft = AppButton('Save as draft', expand: phone, onPressed: saving ? null : _saveDraft);
    final text = Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 4, children: [
      Wrap(spacing: 10, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
        Text(title, style: AppText.h1.copyWith(fontSize: size)),
        auBadge(status),
      ]),
      Text('Trigger, conditions and steps. Nothing is saved until you turn it on or save it.', style: AppText.sub.copyWith(fontSize: phone ? 12 : 13)),
    ]);
    if (phone) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 10, children: [
        text,
        on,
        Row(spacing: 8, children: [Expanded(child: cancel), Expanded(child: draft)]),
      ]);
    }
    return Wrap(spacing: 12, runSpacing: 12, alignment: WrapAlignment.spaceBetween, crossAxisAlignment: WrapCrossAlignment.end, children: [
      ConstrainedBox(constraints: const BoxConstraints(maxWidth: 560), child: text),
      Row(mainAxisSize: MainAxisSize.min, spacing: 8, children: [cancel, draft, on]),
    ]);
  }

  /// `.au-sec`: a numbered section card.
  Widget _section(int n, String title, List<Widget> children) {
    final phone = context.isPhone;
    return AppCard(
      padding: EdgeInsets.symmetric(horizontal: phone ? 14 : 18, vertical: phone ? 14 : 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: phone ? 12 : 14, children: [
        Row(spacing: 10, children: [
          Container(
            width: 24,
            height: 24,
            alignment: Alignment.center,
            decoration: const BoxDecoration(color: AppColors.text, shape: BoxShape.circle),
            child: Text('$n', style: AppText.s(12, W.w8, color: AppColors.white)),
          ),
          Expanded(child: Text(title, style: AppText.s(15, W.w8))),
        ]),
        ...children,
      ]),
    );
  }

  // ─────────────────────────────── 1 When does it start?

  Widget _start(double width) {
    final inner = width - (context.isPhone ? 28 : 36) - 4;
    final cols = inner >= 600 ? 3 : (inner >= 420 ? 2 : 1);
    final shown = [for (final t in auTriggers) if (group == 'all' || t.$4 == group) t];
    return _section(1, 'When does it start?', [
      drField('Automation name', AppTextField(controller: name, placeholder: 'e.g. Welcome series', error: nameError, onChanged: (_) => _edit(() => nameError = null)), ),
      drField(
        'Start it when',
        UnderlineTabs<String>(
          pillCounts: true,
          gap: 24,
          items: [
            TabItem('all', 'All', count: auTriggers.length),
            for (final g in auGroups) TabItem(g.$1, g.$2, count: auTriggers.where((t) => t.$4 == g.$1).length),
          ],
          value: group,
          onChanged: (v) => setState(() => group = v),
        ),
      ),
      Column(spacing: cols == 1 ? 6 : 8, children: [
        for (var i = 0; i < shown.length; i += cols)
          IntrinsicHeight(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 8, children: [
              for (var j = i; j < i + cols; j++) Expanded(child: j < shown.length ? _triggerCard(shown[j], cols == 1) : const SizedBox()),
            ]),
          ),
      ]),
      trigger.isEmpty ? _noTrigger() : _triggerDetail(),
    ]);
  }

  Widget _triggerCard((String, String, String, String, AppIconData) t, bool tight) => Hover(
        onTap: () => _edit(() {
          trigger = t.$1;
          cfgs.putIfAbsent(trigger, () => auDefaults(trigger));
        }),
        builder: (_, h, _) {
          final on = trigger == t.$1;
          return Container(
            padding: tight ? const EdgeInsets.symmetric(horizontal: 10, vertical: 8) : const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: on ? AppColors.accentSoft : AppColors.card,
              borderRadius: AppRadius.all(10),
              border: Border.all(color: on ? AppColors.accent : (h ? AppColors.lineHover : AppColors.line2)),
            ),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 10, children: [
              AuTriggerTile(t.$1, size: 30),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 2, children: [
                  Text(t.$2, style: AppText.s(13, W.w7)),
                  Text(t.$3, style: AppText.s(11.5, W.w5, color: AppColors.muted, h: 1.4)),
                ]),
              ),
            ]),
          );
        },
      );

  Widget _noTrigger() => CustomPaint(
        painter: DashedBox(color: AppColors.line, radius: 12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(spacing: 10, children: [
            const AppIcon(AppIcons.bolt, size: 16, color: AppColors.muted),
            Expanded(child: Text('Pick what starts this automation. You can change it later.', style: AppText.s(13, W.w5, color: AppColors.muted))),
          ]),
        ),
      );

  /// `.au-det`: the picked trigger, its settings and the "Starts:" line.
  Widget _triggerDetail() {
    final t = auTrigger(trigger)!;
    final c = _cfg;
    final fields = auFields[trigger] ?? const [];
    final phone = context.isPhone;
    final groupName = auGroups.firstWhere((g) => g.$1 == t.$4).$2;
    void set(String k, Object? v) => _edit(() => c[k] = v);
    Widget sized(double w, Widget child) => phone ? child : SizedBox(width: w, child: child);
    final nf = auNumbers[trigger];
    final date = DateTime.tryParse('${c['date'] ?? ''}') ?? DateTime.now();
    final today = DateUtils.dateOnly(DateTime.now());
    final widgets = <Widget>[
      if (fields.contains('plan'))
        sized(
          300,
          drField(
            'Which plan',
            SegmentedTabs<String>(
              expand: phone,
              items: const [TabItem('any', 'Any plan'), TabItem('program', 'Program'), TabItem('meal_plan', 'Meal plan')],
              value: '${c['plan_type'] ?? 'any'}',
              onChanged: (v) => set('plan_type', v),
            ),
          ),
        ),
      if (fields.contains('day'))
        sized(
          364,
          drField(
            'Day',
            Row(spacing: phone ? 4 : 6, children: [
              for (final (i, d) in const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'].indexed)
                Expanded(
                  child: Hover(
                    onTap: () => set('weekday', i),
                    builder: (_, h, _) {
                      final on = (c['weekday'] as num?)?.toInt() == i;
                      return Container(
                        height: 34,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: on ? AppColors.accent : AppColors.card,
                          borderRadius: AppRadius.all(8),
                          border: Border.all(color: on ? AppColors.accent : (h ? AppColors.lineHover : AppColors.line2)),
                        ),
                        child: Text(d, style: AppText.s(phone ? 12 : 12.5, W.w6, color: on ? AppColors.white : AppColors.text2)),
                      );
                    },
                  ),
                ),
            ]),
          ),
        ),
      if (nf != null)
        sized(260, () {
          final v = (c[nf.$1] as num?)?.toInt() ?? nf.$4;
          return drField(
            nf.$2,
            NuStep(
              value: v == 0 && trigger == 'plan_ends' ? 'On the day' : '$v',
              unit: v == 0 && trigger == 'plan_ends' ? '' : nf.$3,
              onLess: v > nf.$4 ? () => set(nf.$1, (v - nf.$6).clamp(nf.$4, nf.$5)) : null,
              onMore: v < nf.$5 ? () => set(nf.$1, (v + nf.$6).clamp(nf.$4, nf.$5)) : null,
            ),
          );
        }()),
      if (fields.contains('date'))
        sized(
          260,
          drField(
            'Date',
            NuStep(
              value: DateFormat('d MMM yyyy').format(date),
              unit: '',
              onLess: date.isAfter(today) ? () => set('date', DateFormat('yyyy-MM-dd').format(date.subtract(const Duration(days: 1)))) : null,
              onMore: () => set('date', DateFormat('yyyy-MM-dd').format(date.add(const Duration(days: 1)))),
            ),
          ),
        ),
      if (fields.contains('form'))
        sized(
          280,
          drField(
            'Form',
            AppSelect('${c['form'] ?? ''}'.isEmpty ? 'Choose a form' : _formName('${c['form']}'), entries: [
              for (final f in _sendable)
                MenuEntry('${f['name']}', icon: AppIcons.clipboard, selected: '${f['id']}' == '${c['form']}', onTap: () => set('form', '${f['id']}')),
            ]),
          ),
        ),
      if (fields.contains('time'))
        sized(
          260,
          drField(
            'Time',
            NuStep(
              value: auClock(c['time']),
              unit: '',
              onLess: auSlot(c['time']) > 0 ? () => set('time', auHhmm(auSlot(c['time']) - 1)) : null,
              onMore: auSlot(c['time']) < 47 ? () => set('time', auHhmm(auSlot(c['time']) + 1)) : null,
            ),
          ),
        ),
    ];
    final note = auTriggerNotes[trigger];
    return Container(
      padding: phone ? const EdgeInsets.all(12) : const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(color: AppColors.tableHead, borderRadius: AppRadius.all(12), border: Border.all(color: AppColors.line)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 14, children: [
        Row(spacing: 10, children: [
          AuTriggerTile(trigger, size: 30),
          Flexible(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 1, children: [
              Text(t.$2, style: AppText.s(14, W.w7)),
              Text('$groupName trigger', style: AppText.s(12, W.w5, color: AppColors.muted)),
            ]),
          ),
          AppButton('Change', kind: BtnKind.text, size: BtnSize.sm, onPressed: () => setState(() {
                trigger = '';
                group = 'all';
                dirty = true;
              })),
          const Spacer(),
        ]),
        if (widgets.isNotEmpty)
          phone
              ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 12, children: widgets)
              : Wrap(spacing: 20, runSpacing: 14, crossAxisAlignment: WrapCrossAlignment.end, children: widgets),
        if (note != null) Text(note, style: AppText.s(12.5, W.w5, color: AppColors.text2)),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(color: AppColors.accentSoft, borderRadius: AppRadius.all(8)),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 8, children: [
            const Padding(padding: EdgeInsets.only(top: 1), child: AppIcon(AppIcons.bolt, size: 15, color: AppColors.accentText)),
            Expanded(
              child: Text.rich(
                TextSpan(children: [
                  TextSpan(text: 'Starts: ', style: AppText.s(13, W.w7, color: AppColors.accentText)),
                  TextSpan(text: auStarts(trigger, c, formName: _formName('${c['form'] ?? ''}')), style: AppText.s(13, W.w5, color: AppColors.accentText)),
                ]),
              ),
            ),
          ]),
        ),
      ]),
    );
  }

  // ─────────────────────────────── 2 Who is it for?

  Widget _who() {
    final pkg = drField(
      'Package',
      AppSelect(scopePackage.isEmpty ? 'Any package' : scopePackage, entries: [
        MenuEntry('Any package', selected: scopePackage.isEmpty, onTap: () => _edit(() => scopePackage = '')),
        for (final p in packages) MenuEntry(p, selected: p == scopePackage, onTap: () => _edit(() => scopePackage = p)),
      ]),
    );
    final tr = drField(
      'Trainer',
      AppSelect(scopeTrainer.isEmpty ? 'Any trainer' : scopeTrainerName, entries: [
        MenuEntry('Any trainer', selected: scopeTrainer.isEmpty, onTap: () => _edit(() => scopeTrainer = scopeTrainerName = '')),
        for (final t in trainers)
          MenuEntry('${t['full_name']}', selected: '${t['id']}' == scopeTrainer, onTap: () => _edit(() {
                scopeTrainer = '${t['id']}';
                scopeTrainerName = '${t['full_name']}';
              })),
      ]),
    );
    return _section(2, 'Who is it for?', [
      context.isPhone
          ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 12, children: [pkg, tr])
          : Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 12, children: [Expanded(child: pkg), Expanded(child: tr)]),
      DrSwitch(
        title: 'Stop when the client responds',
        sub: 'The remaining steps are skipped once the client sends the form or replies.',
        value: stop,
        onChanged: (v) => _edit(() => stop = v),
      ),
    ]);
  }

  // ─────────────────────────────── 3 What happens next?

  Widget _next() {
    final phone = context.isPhone;
    return _section(3, 'What happens next?', [
      if (steps.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 28),
          child: Text('No steps yet. Add what should happen after the trigger.', textAlign: TextAlign.center, style: AppText.s(13, W.w5, color: AppColors.muted)),
        ),
      if (steps.isNotEmpty)
        Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [for (final (i, s) in steps.indexed) KeyedSubtree(key: s.key, child: _step(i, s, phone))]),
      Padding(padding: EdgeInsets.only(left: phone ? 38 : 44), child: _addStep()),
    ]);
  }

  Widget _step(int i, AuStep s, bool phone) {
    final rail = phone ? 28.0 : 32.0;
    final (bg, fg) = auKindTone(s.kind);
    return Stack(children: [
      Positioned(left: rail / 2 - 1, top: rail + 4, bottom: 4, child: Container(width: 2, color: AppColors.line)),
      Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: phone ? 10 : 12, children: [
        Container(
          width: rail,
          height: rail,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
          child: AppIcon(auKindIcon(s.kind), size: 16, color: fg),
        ),
        Expanded(
          child: Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: EdgeInsets.symmetric(horizontal: phone ? 12 : 14, vertical: 12),
            decoration: BoxDecoration(color: AppColors.card, borderRadius: AppRadius.all(AppRadius.card), border: Border.all(color: AppColors.line)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: phone ? 10 : 12, children: [
              _stepHead(i, s, phone),
              switch (s.kind) {
                'wait' => _waitBody(s, phone),
                'form' => _sendBody(s, phone),
                'message' => _sendBody(s, phone),
                _ => _taskBody(s, phone),
              },
            ]),
          ),
        ),
      ]),
    ]);
  }

  Widget _stepHead(int i, AuStep s, bool phone) {
    final title = Text('Step ${i + 1} · ${auKindLabel(s.kind)}', style: AppText.s(13, W.w7, h: 1.35));
    final line = Text(_line(s), maxLines: phone ? 3 : 1, overflow: TextOverflow.ellipsis, style: AppText.s(12.5, W.w5, color: AppColors.muted, h: 1.4));
    final dots = Builder(builder: (b) => AppIconButton(AppIcons.dots, tooltip: 'Step options', small: true, ghost: true, onPressed: () => _stepMenu(b, i)));
    if (phone) {
      return Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 8, children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 2, children: [title, line])),
        dots,
      ]);
    }
    return Row(spacing: 10, children: [title, Expanded(child: line), dots]);
  }

  void _stepMenu(BuildContext anchor, int i) => showAppMenu(anchor, width: 200, [
        MenuEntry.header('Step ${i + 1}'),
        if (i > 0) MenuEntry('Move up', icon: AppIcons.chevronUpAlt, onTap: () => _edit(() => steps.insert(i - 1, steps.removeAt(i)))),
        if (i < steps.length - 1) MenuEntry('Move down', icon: AppIcons.chevronDown, onTap: () => _edit(() => steps.insert(i + 1, steps.removeAt(i)))),
        if (steps.length > 1) const MenuEntry.separator(),
        MenuEntry('Remove', icon: AppIcons.trash, danger: true, onTap: () => _remove(i)),
      ]);

  void _remove(int i) {
    final before = [...steps];
    final line = _line(steps[i]);
    _edit(() => steps.removeAt(i));
    showToast(context, 'Step removed', sub: line, action: 'Undo', onAction: () => _edit(() => steps = before));
  }

  Widget _waitBody(AuStep s, bool phone) => Wrap(spacing: 10, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
        SizedBox(
          width: phone ? 140 : 150,
          child: NuStep(
            value: '${s.amount}',
            unit: '',
            onLess: s.amount > 1 ? () => _edit(() => s.amount--) : null,
            onMore: s.amount < 72 ? () => _edit(() => s.amount++) : null,
          ),
        ),
        SegmentedTabs<String>(
          items: const [TabItem('hours', 'Hours'), TabItem('days', 'Days')],
          value: s.unit,
          onChanged: (v) => _edit(() => s.unit = v),
        ),
        Text('Pause before the next step', style: AppText.s(13, W.w5, color: AppColors.text2)),
      ]);

  /// Form and message steps: what to send, a link to edit it, Send by chips (and the message preview).
  Widget _sendBody(AuStep s, bool phone) {
    final isForm = s.kind == 'form';
    final pick = drField(
      isForm ? 'Form' : 'Message template',
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 6, children: [
        isForm
            ? AppSelect(_formLabel(s), entries: [
                for (final f in _sendable)
                  MenuEntry('${f['name']}', icon: AppIcons.clipboard, selected: '${f['id']}' == s.form, onTap: () => _edit(() {
                        s.form = '${f['id']}';
                        s.formName = '${f['name']}';
                      })),
              ])
            : AppSelect(_templateName(s.template), entries: [
                for (final t in templates) MenuEntry('${t['name']}', icon: AppIcons.send, selected: t['key'] == s.template, onTap: () => _edit(() => s.template = '${t['key']}')),
              ]),
        Align(
          alignment: Alignment.centerLeft,
          child: _link(isForm ? 'Open forms & check-ins' : 'Edit message templates', () => context.go(isForm ? (s.form.isEmpty ? '/forms' : '/forms/${s.form}') : '/emails')),
        ),
      ]),
    );
    final by = drField(
      'Send by',
      Wrap(spacing: 6, runSpacing: 6, children: [
        for (final c in auChannels) _channel(c.$2, s.channels.contains(c.$1), () => _edit(() => s.channels.contains(c.$1) ? s.channels.remove(c.$1) : s.channels.add(c.$1))),
      ]),
    );
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 12, children: [
      phone
          ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 12, children: [pick, by])
          : Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 12, children: [Expanded(child: pick), Expanded(child: by)]),
      if (!isForm && s.channels.isNotEmpty && _template(s.template) != null) _preview(s),
    ]);
  }

  Widget _link(String label, VoidCallback onTap) => Hover(
        onTap: onTap,
        builder: (_, h, _) => Text(label, style: AppText.s(12, W.w7, color: h ? AppColors.linkHover : AppColors.accentText)),
      );

  /// `.au-chc`: a channel chip, ticked when picked.
  Widget _channel(String label, bool on, VoidCallback onTap) => Hover(
        onTap: onTap,
        builder: (_, h, _) => Container(
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: on ? AppColors.accentSoft : AppColors.card,
            borderRadius: AppRadius.all(8),
            border: Border.all(color: on ? AppColors.accent : (h ? AppColors.lineHover : AppColors.line2)),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, spacing: 5, children: [
            if (on) const AppIcon(AppIcons.check, size: 13, color: AppColors.accentText),
            Text(label, style: AppText.s(12.5, W.w6, color: on ? AppColors.accentText : AppColors.text2)),
          ]),
        ),
      );

  /// `.au-mp`: the text of the first picked channel, with sample names filled in.
  Widget _preview(AuStep s) {
    // the first picked channel that has text (the board shows WhatsApp when it is picked)
    String text(String c) => '${(((_template(s.template)?['channels'] as Map?) ?? const {})[c] as Map?)?['body'] ?? ''}'.trim();
    final ch = s.channels.firstWhere((c) => text(c).isNotEmpty, orElse: () => s.channels.first);
    final body = text(ch);
    final filled = body
        .replaceAll('{{first_name}}', 'Sana')
        .replaceAll('{{coach_name}}', 'Coach Meera')
        .replaceAll('{{gym_name}}', 'Train With Vimal')
        .replaceAll(RegExp(r'\{\{\s*\w+\s*\}\}'), '…');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(color: AppColors.tableHead, borderRadius: AppRadius.all(10), border: Border.all(color: AppColors.line)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 4, children: [
        Text('${auChannel(ch)} preview'.toUpperCase(), style: AppText.over),
        Text(filled.isEmpty ? 'This template has no ${auChannel(ch)} text yet. Write it in Emails & alerts.' : filled,
            style: AppText.s(13, W.w5, color: filled.isEmpty ? AppColors.muted : AppColors.text2, h: 1.5)),
      ]),
    );
  }

  Widget _taskBody(AuStep s, bool phone) {
    final task = drField('Task', AppTextField(initial: s.title, placeholder: 'e.g. Call the client', onChanged: (v) => _edit(() => s.title = v)));
    final who = drField(
      'For',
      SegmentedTabs<String>(
        expand: true,
        height: 30,
        items: const [TabItem('trainer', 'Assigned trainer'), TabItem('owner', 'Owner')],
        value: s.assignee,
        onChanged: (v) => _edit(() => s.assignee = v),
      ),
    );
    return phone
        ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 12, children: [task, who])
        : Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 12, children: [Expanded(child: task), Expanded(child: who)]);
  }

  /// `.mb-addm` + the kinds menu, headed "It is added after the last step".
  Widget _addStep() => Builder(
        builder: (b) => Hover(
          onTap: () => _addMenu(b),
          builder: (_, h, _) => CustomPaint(
            painter: DashedBox(color: h ? AppColors.accent : AppColors.line2, radius: AppRadius.card),
            child: Container(
              height: 46,
              decoration: BoxDecoration(color: h ? AppColors.hover : null, borderRadius: AppRadius.all(AppRadius.card)),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, spacing: 6, children: [
                AppIcon(AppIcons.plus, size: 16, color: h ? AppColors.accentText : AppColors.text2),
                Text('Add a step', style: AppText.s(13.5, W.w7, color: h ? AppColors.accentText : AppColors.text2)),
              ]),
            ),
          ),
        ),
      );

  void _addMenu(BuildContext anchor) {
    final parq = forms.where((f) => '${f['name']}'.startsWith('PAR-Q')).firstOrNull;
    AuStep fresh(String k) => switch (k) {
          'wait' => AuStep('wait'),
          'message' => AuStep('message', template: _template('checkin-reminder') != null ? 'checkin-reminder' : '', channels: ['push']),
          'form' => AuStep('form', form: '${parq?['id'] ?? ''}', formName: '${parq?['name'] ?? ''}', channels: ['push']),
          _ => AuStep('task', title: 'Welcome call with the client'),
        };
    final box = anchor.findRenderObject() as RenderBox;
    showAppMenu(anchor, width: box.size.width.clamp(240.0, 320.0), alignRight: false, [
      const MenuEntry.header('It is added after the last step'),
      for (final k in auKinds)
        MenuEntry(k.$2, icon: auKindIcon(k.$1), sub: k.$3, onTap: () {
          _edit(() => steps.add(fresh(k.$1)));
          showToast(context, 'Step added', sub: k.$2);
        }),
    ]);
  }

  // ─────────────────────────────── Right: In plain words, Last 30 days

  Widget _side(String title, List<Widget> children) => AppCard(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 12, children: [Text(title, style: AppText.s(14.5, W.w8)), ...children]),
      );

  Widget _hint(String s) => Text(s, style: AppText.s(12, W.w5, color: AppColors.muted, h: 1.5));

  String get _audience {
    if (scopePackage.isNotEmpty && scopeTrainer.isNotEmpty) return '$scopeTrainerName’s clients on $scopePackage';
    if (scopePackage.isNotEmpty) return 'Clients on $scopePackage';
    if (scopeTrainer.isNotEmpty) return '$scopeTrainerName’s clients';
    return 'All clients';
  }

  Widget _plain() {
    final p = problems;
    final lines = [for (final s in steps) _line(s)];
    Widget item(int n, Widget child) => Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 20, child: Text('$n.', style: AppText.s(13, W.w5, color: AppColors.text2, h: 1.45))),
          Expanded(child: child),
        ]);
    return _side('In plain words', [
      _hint('This is what will happen for each client it applies to.'),
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 8, children: [
        item(
          1,
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(trigger.isEmpty ? 'Pick what starts it' : auStarts(trigger, _cfg, formName: _formName('${_cfg['form'] ?? ''}')), style: AppText.s(13, W.w7, h: 1.45)),
            Text(_audience, style: AppText.s(12, W.w5, color: AppColors.muted, h: 1.45)),
          ]),
        ),
        for (final (i, l) in lines.indexed) item(i + 2, Text(l, style: AppText.s(13, W.w5, color: AppColors.text2, h: 1.45))),
      ]),
      if (stop)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(color: AppColors.sub, borderRadius: AppRadius.all(8)),
          child: Row(spacing: 8, children: [
            const AppIcon(AppIcons.checkCircle, size: 16, color: AppColors.muted),
            Expanded(child: Text('Stops when the client responds.', style: AppText.s(12.5, W.w5, color: AppColors.text2))),
          ]),
        ),
      if (p.isNotEmpty)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(color: AppColors.warnBg, borderRadius: AppRadius.all(8)),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 8, children: [
            const Padding(padding: EdgeInsets.only(top: 1), child: AppIcon(AppIcons.flag, size: 16, color: AppColors.warnText)),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 2, children: [
                Text('Not ready to turn on', style: AppText.s(12.5, W.w7, color: AppColors.warnText)),
                for (final x in p) Text(x, style: AppText.s(12.5, W.w5, color: AppColors.warnText)),
              ]),
            ),
          ]),
        ),
    ]);
  }

  Widget _last30() {
    final rows = [for (final r in (runs['rows'] as List?) ?? const []) r as Map];
    if (isNew || ((runs['started'] as num?) ?? 0) == 0) {
      return _side('Last 30 days', [_hint('No runs yet. Clients show up here once it is on.')]);
    }
    final cells = [('${runs['started']}', 'started'), ('${runs['finished']}', 'finished'), ('${runs['stopped']}', 'stopped early')];
    return _side('Last 30 days', [
      Container(
        decoration: BoxDecoration(borderRadius: AppRadius.all(10), border: Border.all(color: AppColors.line)),
        child: IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            for (final (i, c) in cells.indexed)
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(border: i == 0 ? null : const Border(left: BorderSide(color: AppColors.line))),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 1, children: [
                    Text(c.$1, style: AppText.s(18, W.w8, tabular: true)),
                    Text(c.$2, style: AppText.s(11.5, W.w6, color: AppColors.muted)),
                  ]),
                ),
              ),
          ]),
        ),
      ),
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (final (i, r) in rows.take(6).indexed) _run(r, i == 0),
      ]),
    ]);
  }

  /// One client in the flow: where they are now.
  Widget _run(Map r, bool first) {
    final c = (r['client'] as Map?) ?? const {};
    final st = '${r['status']}';
    final step = (r['step_index'] as num?)?.toInt() ?? 0, total = (r['steps_total'] as num?)?.toInt() ?? steps.length;
    final last = '${r['last_message'] ?? ''}';
    final line = switch (st) {
      'finished' => 'Finished',
      'stopped' || 'failed' => last.isEmpty ? 'Stopped early' : last,
      'waiting' => 'Waiting · step $step of $total',
      _ => '${last.isEmpty ? 'Running' : last} · step $step of $total',
    };
    return Hover(
      onTap: c['id'] == null ? null : () => context.go('/clients/${c['id']}'),
      builder: (_, h, _) => Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(border: first ? null : const Border(top: BorderSide(color: AppColors.line))),
        child: Row(spacing: 10, children: [
          AppAvatar('${c['full_name']}', size: 26, colors: AppColors.avatarCode('${c['avatar_color'] ?? 'c1'}'), initials: '${c['initials'] ?? ''}'),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 1, children: [
              Text('${c['full_name']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(13, W.w7, color: h ? AppColors.accentText : AppColors.text)),
              Text(line, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(12, W.w5, color: AppColors.muted)),
            ]),
          ),
          Text(auAgo(r['updated_at'] ?? r['created_at']), style: AppText.s(11.5, W.w6, color: AppColors.muted)),
        ]),
      ),
    );
  }

  // ─────────────────────────────── Save

  Map<String, Object?> _body() {
    final cfg = trigger.isEmpty ? <String, Object?>{} : {for (final e in _cfg.entries) if (e.key != 'plan_type' || trigger == 'plan_starts') e.key: e.value};
    return {
      'name': name.text.trim(),
      'trigger': trigger,
      'trigger_config': cfg,
      'scope_package': scopePackage,
      'scope_trainer': scopeTrainer.isEmpty ? null : scopeTrainer,
      'stop_on_response': stop,
      'steps': [for (final s in steps) s.toJson()],
    };
  }

  /// Creates or updates the automation; returns its id, or null when it failed (the toast says why).
  Future<String?> _write() async {
    if (name.text.trim().length < 2) {
      setState(() => nameError = 'Name the automation.');
      showToast(context, 'Name the automation', sub: 'Give it a name you will recognise in the list', kind: ToastKind.err);
      return null;
    }
    try {
      final r = isNew ? await Services.api.post<Map>('automations/', _body()) : await Services.api.patch<Map>('automations/${widget.id}/', _body());
      return '${r['id']}';
    } on ApiError catch (e) {
      if (mounted) {
        setState(() => nameError = e.field('name'));
        showToast(context, 'Could not save', sub: e.field('name') ?? e.field('trigger_config') ?? e.field('steps') ?? e.message, kind: ToastKind.err);
      }
      return null;
    }
  }

  Future<void> _saveDraft() async {
    setState(() => saving = true);
    final id = await _write();
    if (id != null) {
      try {
        await Services.api.post('automations/$id/save-draft/');
      } on ApiError catch (_) {}
    }
    if (!mounted) return;
    setState(() => saving = false);
    if (id == null) return;
    showToast(context, 'Saved as a draft', sub: 'Turn it on when it is ready');
    _after(id, 'draft');
  }

  Future<void> _turnOn() async {
    final p = problems;
    if (p.isNotEmpty) return showToast(context, 'Not ready to turn on', sub: p.first, kind: ToastKind.err);
    setState(() => saving = true);
    final id = await _write();
    var ok = id != null;
    if (id != null) {
      try {
        await Services.api.post('automations/$id/turn-on/');
      } on ApiError catch (e) {
        ok = false;
        if (mounted) showToast(context, 'Not ready to turn on', sub: e.fields['problems']?.firstOrNull ?? e.message, kind: ToastKind.err);
      }
    }
    if (!mounted) return;
    setState(() => saving = false);
    if (id == null) return;
    if (ok) showToast(context, '${name.text.trim()} is on', sub: 'It starts with the next trigger', kind: ToastKind.ok);
    _after(id, ok ? 'on' : 'draft');
  }

  /// After a save: a new automation moves to its own address; an existing one reloads its runs.
  void _after(String id, String st) {
    if (isNew) {
      context.go('/automations/$id');
      return;
    }
    setState(() {
      status = st;
      dirty = false;
    });
    Services.api.get<Map>('automations/$id/runs/').then((r) {
      if (mounted) setState(() => runs = r);
    }, onError: (_) {});
  }

  Future<void> _cancel() async {
    if (dirty) {
      final ok = await confirmAction(context,
          title: 'Leave without saving?', body: 'Your changes to this automation are not saved.', confirm: 'Leave', danger: true, icon: AppIcons.alert);
      if (!ok || !mounted) return;
    }
    context.go('/automations');
  }
}
