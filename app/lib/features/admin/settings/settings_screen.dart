import 'package:dio/dio.dart' show FormData, MultipartFile;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';

import '../../../app/services.dart';
import '../../../app/shell/page.dart';
import '../../../core/api/api_error.dart';
import '../../../core/icons/app_icons.dart';
import '../../../core/theme/theme.dart';
import '../../../core/widgets/button.dart';
import '../../../core/widgets/card.dart';
import '../../../core/widgets/hover.dart';
import '../../../core/widgets/input.dart';
import '../../../core/widgets/overlays.dart';
import '../../../core/widgets/responsive.dart';
import '../../../core/widgets/select.dart';
import '../../../core/widgets/tabs.dart';
import '../../../core/widgets/tooltip.dart';
import '../../trainer/me/me_pick.dart';
import 'settings_access.dart';
import 'settings_common.dart';

/// Admin → Settings (boards `Settings` + `SettingsMobile`, D-53). Four tabs:
/// - General: the gym profile (name, contact, address, link) and the defaults every new client starts with.
/// - Branding: logo, brand colour and default theme, saved as a draft until Apply; the client app preview.
/// - Roles & access: the three roles and the permission matrix (trainer column; locked cells stay as they are).
/// - Integrations: WhatsApp Business, the own email domain (DNS check) and Apple Health / Health Connect.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, this.tab});
  final String? tab;
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late String tab = switch (widget.tab) { 'b' || 'branding' => 'b', 'r' || 'roles' => 'r', 'i' || 'integrations' => 'i', _ => 'g' };
  int gen = 0; // pull to refresh: the open tab loads again

  @override
  Widget build(BuildContext context) {
    return StaffPage(
      onRefresh: () async => setState(() => gen++),
      header: PageTop(
        title: 'Settings',
        subWrap: true,
        sub: switch (tab) {
          'b' => 'How your app, emails and invite links look to clients.',
          'r' => 'Who can see and change what. Trainer access is fine-tuned on each trainer profile.',
          'i' => 'Outside services the app sends through or reads from.',
          _ => 'Your gym details and the defaults every new client starts with.',
        },
      ),
      children: [
        Transform.translate(
          offset: const Offset(0, -6),
          child: UnderlineTabs<String>(
            gap: context.isPhone ? 20 : 24,
            items: const [TabItem('g', 'General'), TabItem('b', 'Branding'), TabItem('r', 'Roles & access'), TabItem('i', 'Integrations')],
            value: tab,
            onChanged: (v) => setState(() => tab = v),
          ),
        ),
        LayoutBuilder(
          builder: (context, box) => KeyedSubtree(
            key: ValueKey('$tab$gen'),
            child: switch (tab) {
              'b' => _BrandingTab(cw: box.maxWidth),
              'r' => RolesTab(cw: box.maxWidth),
              'i' => IntegrationsTab(cw: box.maxWidth),
              _ => _GeneralTab(cw: box.maxWidth, toBranding: () => setState(() => tab = 'b')),
            },
          ),
        ),
      ],
    );
  }
}

/// Loading and error states shared by the tabs.
Widget stLoading() => const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator(color: AppColors.accent, strokeWidth: 2.5)));
Widget stError(String what, ApiError e, VoidCallback retry) =>
    AppCard(child: EmptyState('Could not load $what', sub: e.message, action: AppButton('Try again', onPressed: retry)));

/// `.st-grid`: the main column and a 340 px side column (stacked on narrow screens).
Widget stGrid(double cw, List<Widget> main, Widget side) {
  if (cw < 860) return Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 14, children: [...main, side]);
  return Align(
    alignment: Alignment.topLeft,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 1100),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 16, children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 14, children: main)),
        SizedBox(width: 340, child: side),
      ]),
    ),
  );
}

// ─────────────────────────────── General

class _GeneralTab extends StatefulWidget {
  const _GeneralTab({required this.cw, required this.toBranding});
  final double cw;
  final VoidCallback toBranding;
  @override
  State<_GeneralTab> createState() => _GeneralTabState();
}

class _GeneralTabState extends State<_GeneralTab> {
  Map gym = {};
  ApiError? error;
  bool loading = true, saving = false, savedNow = false;
  Map<String, String?> errs = {};
  final c = {for (final k in ['name', 'email', 'phone', 'address', 'instagram']) k: TextEditingController()};

  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void dispose() {
    for (final x in c.values) {
      x.dispose();
    }
    super.dispose();
  }

  Future<void> load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final r = await Services.api.get<Map>('settings/gym/');
      if (!mounted) return;
      setState(() {
        gym = r;
        loading = false;
        for (final e in c.entries) {
          e.value.text = '${r[e.key] ?? ''}';
        }
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

  String get _savedLine {
    if (savedNow) return 'Saved just now';
    final at = DateTime.tryParse('${gym['profile_saved_at'] ?? ''}')?.toLocal();
    return at == null ? 'Not saved from here yet' : 'Last saved ${at.day} ${stMonths[at.month - 1]}';
  }

  Future<void> _save() async {
    if (c['name']!.text.trim().isEmpty) return setState(() => errs = {'name': 'Enter the gym or business name.'});
    setState(() => saving = true);
    try {
      final r = await Services.api.patch<Map>('settings/gym/', {for (final e in c.entries) e.key: e.value.text.trim()});
      if (!mounted) return;
      setState(() {
        gym = r;
        saving = false;
        savedNow = true;
        errs = {};
        for (final e in c.entries) {
          e.value.text = '${r[e.key] ?? ''}';
        }
      });
      showToast(context, 'Gym profile saved', sub: 'Emails and the client app use the new details');
    } on ApiError catch (e) {
      if (!mounted) return;
      setState(() {
        saving = false;
        errs = {for (final k in c.keys) k: e.fields[k]?.first};
      });
      if (errs.values.every((v) => v == null)) showToast(context, 'Could not save', sub: e.message, kind: ToastKind.err);
    }
  }

  /// Regional & defaults save at once.
  Future<void> _patch(Map<String, dynamic> body, {String? toast, String? sub, Map<String, dynamic>? undo}) async {
    final before = Map.of(gym);
    setState(() => gym = {...gym, ...body});
    try {
      final r = await Services.api.patch<Map>('settings/gym/', body);
      if (!mounted) return;
      setState(() => gym = {...gym, ...r});
      if (toast != null) showToast(context, toast, sub: sub, action: undo == null ? null : 'Undo', onAction: undo == null ? null : () => _patch(undo));
    } on ApiError catch (e) {
      if (!mounted) return;
      setState(() => gym = before);
      showToast(context, 'Could not change it', sub: e.message, kind: ToastKind.err);
    }
  }

  Widget _field(String key, Widget label, {TextInputType? keyboard, int maxLines = 1}) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 6, children: [
        label,
        AppTextField(
          controller: c[key],
          keyboard: keyboard,
          maxLines: maxLines,
          minLines: 1,
          error: errs[key],
          onChanged: (_) {
            if (errs[key] != null) setState(() => errs = {...errs, key: null});
          },
        ),
      ]);

  @override
  Widget build(BuildContext context) {
    if (error != null && gym.isEmpty) return stError('the gym profile', error!, load);
    if (loading && gym.isEmpty) return stLoading();
    final cw = widget.cw, phone = cw < 600;
    final profile = StEditCard(
      cw: cw,
      icon: AppIcons.home,
      tone: 0,
      title: 'Gym profile',
      sub: 'Clients see this on emails and in their app',
      body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 16, children: [
        _field('name', Text.rich(TextSpan(text: 'Gym / business name', style: AppText.label, children: [TextSpan(text: '*', style: AppText.label.copyWith(color: AppColors.badText))]))),
        if (phone) ...[
          _field('email', Text('Contact email', style: AppText.label), keyboard: TextInputType.emailAddress),
          _field('phone', Text('Phone / WhatsApp', style: AppText.label), keyboard: TextInputType.phone),
        ] else
          Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 12, children: [
            Expanded(child: _field('email', Text('Contact email', style: AppText.label), keyboard: TextInputType.emailAddress)),
            Expanded(child: _field('phone', Text('Phone / WhatsApp', style: AppText.label), keyboard: TextInputType.phone)),
          ]),
        _field('address', Text('Address', style: AppText.label), maxLines: phone ? 2 : 1),
        _field('instagram', Text('Website / Instagram', style: AppText.label), keyboard: TextInputType.url),
      ]),
      foot: phone
          ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 10, children: [
              stFootNote(_savedLine),
              Align(alignment: Alignment.centerRight, child: AppButton.primary('Save changes', icon: AppIcons.check, loading: saving, onPressed: _save)),
            ])
          : Row(spacing: 10, children: [Expanded(child: stFootNote(_savedLine)), AppButton.primary('Save changes', icon: AppIcons.check, loading: saving, onPressed: _save)]),
    );

    final units = '${gym['default_units'] ?? 'metric'}';
    final tz = [for (final t in (gym['timezones'] as List? ?? [])) t as Map];
    final langs = [for (final t in (gym['languages'] as List? ?? [])) t as Map];
    String label(List<Map> list, String v) => '${(list.where((t) => t['value'] == v).firstOrNull ?? {'label': v})['label']}';
    Widget select(List<Map> list, String key) {
      final v = '${gym[key] ?? ''}';
      final s = AppSelect(label(list, v), entries: [
        for (final t in list) MenuEntry('${t['label']}', selected: t['value'] == v, onTap: () => _patch({key: t['value']})),
      ]);
      return phone ? s : SizedBox(width: 220, child: s);
    }

    final regional = StEditCard(
      cw: cw,
      icon: AppIcons.globe,
      tone: 1,
      title: 'Regional & defaults',
      sub: 'New clients get these by default and can change their own units',
      body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 14, children: [
        StRow(
          first: true,
          phone: phone,
          title: 'Units',
          sub: units == 'metric' ? 'Weight in kg, body in cm, food in grams' : 'Weight in lb, body in inches, food in ounces',
          control: SegmentedTabs<String>(
            items: const [TabItem('metric', 'Metric · kg, cm'), TabItem('imperial', 'Imperial · lb, in')],
            value: units,
            onChanged: (v) {
              if (v == units) return;
              _patch({'default_units': v}, toast: 'Units set to $v', sub: 'For new clients', undo: {'default_units': units});
            },
          ),
        ),
        StRow(
          phone: phone,
          title: 'Week starts on',
          sub: 'Calendar, weekly check-ins and habit streaks',
          control: SegmentedTabs<String>(
            items: const [TabItem('mon', 'Monday'), TabItem('sun', 'Sunday')],
            value: '${gym['week_start'] ?? 'mon'}',
            onChanged: (v) => _patch({'week_start': v}),
          ),
        ),
        StRow(phone: phone, stretch: true, title: 'Timezone', sub: 'Reminders and automations run on this clock', control: select(tz, 'timezone')),
        StRow(phone: phone, stretch: true, title: 'App language', sub: 'Menus and default messages', control: select(langs, 'language')),
      ]),
    );

    final side = AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 12, children: [
        Text('Where these details show', style: AppText.s(14.5, W.w8)),
        Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 8, children: [
          StLinkRow(icon: AppIcons.palette, title: 'Client app', sub: 'Name, logo and brand colour', onTap: widget.toBranding),
          StLinkRow(icon: AppIcons.link, title: 'Emails and WhatsApp', sub: 'Sender name and contact details', onTap: () => context.go('/emails?tab=sender')),
          StLinkRow(icon: AppIcons.link, title: 'Invite links', sub: 'Name and address on the invite page', onTap: () => context.go('/approvals')),
          StLinkRow(icon: AppIcons.link, title: 'Forms and waivers', sub: 'Business name on signed waivers', onTap: () => context.go('/forms')),
        ]),
      ]),
    );
    return stGrid(cw, [profile, regional], side);
  }
}

// ─────────────────────────────── Branding

class _BrandingTab extends StatefulWidget {
  const _BrandingTab({required this.cw});
  final double cw;
  @override
  State<_BrandingTab> createState() => _BrandingTabState();
}

class _BrandingTabState extends State<_BrandingTab> {
  Map br = {};
  ApiError? error;
  bool loading = true, applying = false, uploading = false;
  final hexC = TextEditingController();
  final hexF = FocusNode();
  String? hexErr;

  @override
  void initState() {
    super.initState();
    load();
    hexF.addListener(() {
      if (!hexF.hasFocus) _hexDone();
    });
  }

  @override
  void dispose() {
    hexC.dispose();
    hexF.dispose();
    super.dispose();
  }

  Future<void> load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final r = await Services.api.get<Map>('settings/branding/');
      if (!mounted) return;
      _take(r);
      setState(() => loading = false);
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
    br = r;
    if (!hexF.hasFocus) hexC.text = col;
    hexErr = null;
  }

  Map get _draft => (br['branding_draft'] as Map?) ?? {};
  String get col => '${_draft['accent_color'] ?? br['accent_color'] ?? '#2563EB'}'.toUpperCase();
  String get theme => '${_draft['theme'] ?? br['theme'] ?? 'light'}';
  bool get applied => br['applied'] != false;
  Color get color => stHex(col) ?? AppColors.accent;

  Future<void> _draftPatch(Map<String, dynamic> body) async {
    final before = br;
    setState(() => br = {...br, 'branding_draft': {..._draft, ...body}, 'applied': false});
    try {
      final r = await Services.api.patch<Map>('settings/branding/', body);
      if (mounted) setState(() => _take(r));
    } on ApiError catch (e) {
      if (!mounted) return;
      setState(() => _take(before));
      showToast(context, 'Could not change it', sub: e.message, kind: ToastKind.err);
    }
  }

  void _hexDone() {
    final v = hexC.text.trim().toUpperCase();
    final full = v.startsWith('#') ? v : '#$v';
    if (stHex(full) == null) {
      setState(() => hexErr = 'Use a colour like #2563EB.');
      return;
    }
    hexC.text = full;
    if (full != col) _draftPatch({'accent_color': full});
  }

  Future<void> _apply() async {
    setState(() => applying = true);
    try {
      final r = await Services.api.post<Map>('settings/branding/apply/');
      if (!mounted) return;
      setState(() {
        _take(r);
        applying = false;
      });
      showToast(context, 'Branding applied', sub: 'Clients see it next time they open the app');
    } on ApiError catch (e) {
      if (!mounted) return;
      setState(() => applying = false);
      showToast(context, 'Could not apply', sub: e.message, kind: ToastKind.err);
    }
  }

  Future<void> _reset() async {
    try {
      final r = await Services.api.post<Map>('settings/branding/reset/');
      if (!mounted) return;
      setState(() => _take(r));
      showToast(context, 'Branding reset', sub: 'Blue and light theme');
    } on ApiError catch (e) {
      if (mounted) showToast(context, 'Could not reset', sub: e.message, kind: ToastKind.err);
    }
  }

  Future<void> _upload() async {
    final f = await pickDocument(ext: const ['png', 'jpg', 'jpeg', 'webp', 'svg']);
    if (f == null || !mounted) return;
    setState(() => uploading = true);
    try {
      final r = await Services.api.upload<Map>('settings/branding/logo/', FormData.fromMap({'logo': MultipartFile.fromBytes(f.$2, filename: f.$1)}));
      if (!mounted) return;
      setState(() {
        _take(r);
        uploading = false;
      });
      final px = r['logo_px'];
      showToast(context, 'Logo uploaded', sub: [r['logo_name'] ?? f.$1, ?px].join(' · '));
    } on ApiError catch (e) {
      if (!mounted) return;
      setState(() => uploading = false);
      showToast(context, 'Could not upload the logo', sub: e.fields['logo']?.first ?? e.message, kind: ToastKind.err);
    }
  }

  Future<void> _removeLogo() async {
    try {
      await Services.api.delete('settings/branding/logo/');
      if (!mounted) return;
      setState(() => br = {...br, 'logo': null, 'logo_name': null, 'logo_px': null});
      showToast(context, 'Logo removed', sub: 'Your initials show until you upload a new one');
    } on ApiError catch (e) {
      if (mounted) showToast(context, 'Could not remove the logo', sub: e.message, kind: ToastKind.err);
    }
  }

  /// `.st-lg`: the logo, or the gym's initials on the brand colour.
  Widget _logo(double size, double radius, double font) {
    final url = br['logo'] as String?;
    final initials = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: color, borderRadius: AppRadius.all(radius)),
      child: Text(stInitials('${br['name'] ?? ''}'), style: AppText.s(font, W.w8, color: AppColors.white)),
    );
    if (url == null || url.isEmpty) return initials;
    final img = url.toLowerCase().endsWith('.svg')
        ? SvgPicture.network(url, width: size, height: size, fit: BoxFit.cover, placeholderBuilder: (_) => initials)
        : Image.network(url, width: size, height: size, fit: BoxFit.cover, errorBuilder: (_, _, _) => initials);
    return ClipRRect(borderRadius: AppRadius.all(radius), child: SizedBox(width: size, height: size, child: img));
  }

  @override
  Widget build(BuildContext context) {
    if (error != null && br.isEmpty) return stError('branding', error!, load);
    if (loading && br.isEmpty) return stLoading();
    final cw = widget.cw, phone = cw < 600;
    final hasLogo = (br['logo'] as String?)?.isNotEmpty == true;
    final card = StEditCard(
      cw: cw,
      icon: AppIcons.palette,
      tone: 3,
      title: 'Branding',
      sub: 'Your logo and colour in the client app, emails and invite links',
      body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 16, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 14, children: [
          _logo(64, 16, 20),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 3, children: [
              Text('Logo', style: AppText.s(13.5, W.w7)),
              Text('Square PNG or SVG, at least 512 x 512. Shown on the app icon screen, emails and invites.', style: AppText.s(12, W.w5, color: AppColors.muted, h: 1.45)),
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Wrap(spacing: 6, runSpacing: 6, children: [
                  AppButton('Upload logo', icon: AppIcons.uploadAlt, size: BtnSize.sm, loading: uploading, onPressed: _upload),
                  if (hasLogo) AppButton('Remove', kind: BtnKind.text, size: BtnSize.sm, onPressed: _removeLogo),
                ]),
              ),
            ]),
          ),
        ]),
        Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 6, children: [
          Text('Brand colour', style: AppText.label),
          Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
            for (final s in AppColors.stSwatches)
              AppTooltip(
                message: stHexOf(s),
                child: Hover(
                  onTap: () {
                    if (stHexOf(s) != col) _draftPatch({'accent_color': stHexOf(s)});
                  },
                  builder: (_, _, _) {
                    final on = stHexOf(s) == col;
                    return Container(
                      width: 32,
                      height: 32,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: s,
                        shape: BoxShape.circle,
                        boxShadow: on ? const [BoxShadow(color: AppColors.card, spreadRadius: 2), BoxShadow(color: AppColors.text, spreadRadius: 4)] : null,
                      ),
                      child: on ? const AppIcon(AppIcons.check, size: 15, color: AppColors.white) : null,
                    );
                  },
                ),
              ),
            Padding(
              padding: const EdgeInsets.only(left: 6),
              child: SizedBox(
                width: 130,
                child: AppTextField(
                  controller: hexC,
                  focusNode: hexF,
                  fontSize: 13,
                  formatters: [FilteringTextInputFormatter.allow(RegExp(r'[#0-9a-fA-F]')), LengthLimitingTextInputFormatter(7)],
                  prefix: Padding(
                    padding: const EdgeInsets.only(left: 12, right: 8),
                    child: Container(width: 16, height: 16, decoration: BoxDecoration(color: color, borderRadius: AppRadius.all(4))),
                  ),
                  onSubmitted: (_) => _hexDone(),
                  onChanged: (_) {
                    if (hexErr != null) setState(() => hexErr = null);
                  },
                ),
              ),
            ),
          ]),
          Text(hexErr ?? 'Buttons, links, progress bars and the selected tab use this colour.',
              style: AppText.s(12, hexErr == null ? W.w5 : W.w6, color: hexErr == null ? AppColors.muted : AppColors.badText)),
        ]),
        Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 6, children: [
          Text('Default theme for clients', style: AppText.label),
          SegmentedTabs<String>(
            items: const [TabItem('light', 'Light'), TabItem('dark', 'Dark'), TabItem('system', 'Match phone')],
            value: theme,
            onChanged: (v) {
              if (v != theme) _draftPatch({'theme': v});
            },
          ),
          Text(
            theme == 'system' ? 'The app follows each client’s phone setting. Clients can still pick their own.' : 'Clients start in $theme mode and can change it in their app.',
            style: AppText.s(12, W.w5, color: AppColors.muted, h: 1.45),
          ),
        ]),
      ]),
      foot: Row(spacing: 10, children: [
        AppButton('Reset', kind: BtnKind.text, icon: AppIcons.undo, onPressed: _reset),
        Expanded(child: Text(applied ? 'Applied' : 'Not applied yet', textAlign: TextAlign.right, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(12.5, W.w6, color: AppColors.muted))),
        AppButton.primary('Apply', icon: AppIcons.check, loading: applying, onPressed: _apply),
      ]),
    );
    // Stacked on a tablet the preview keeps its phone-like width.
    final preview = cw < 860 && !phone ? Align(alignment: Alignment.topLeft, child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 400), child: _preview(phone))) : _preview(phone);
    return stGrid(cw, [card], preview);
  }

  /// `Client app preview`: a small Today screen in the picked colour and theme.
  Widget _preview(bool phone) {
    final dark = theme == 'dark';
    final txt = dark ? AppColors.stDarkText : AppColors.text;
    final line = dark ? AppColors.stDarkCardLine : AppColors.line;
    Widget tab(AppIconData i, String t, bool on) => Expanded(
          child: Column(spacing: 2, children: [
            AppIcon(i, size: 17, color: on ? color : AppColors.muted),
            Text(t, style: AppText.s(10.5, W.w6, color: on ? color : AppColors.muted)),
          ]),
        );
    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 12, children: [
        Row(spacing: 8, children: [
          Expanded(child: Text('Client app preview', style: AppText.s(14.5, W.w8))),
          Text(switch (theme) { 'dark' => 'Dark', 'system' => 'Match phone · light shown', _ => 'Light' }, style: AppText.cap),
        ]),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: AppColors.hbPhone, borderRadius: AppRadius.all(16)),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: dark ? AppColors.stAppDark : AppColors.stApp,
              borderRadius: AppRadius.all(14),
              border: Border.all(color: dark ? AppColors.stAppDarkLine : AppColors.line),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 10, children: [
              Row(spacing: 8, children: [
                _logo(28, 8, 10.5),
                Expanded(child: Text('${br['name'] ?? 'Train With Vimal'}', maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(13, W.w7, color: txt))),
              ]),
              Text('Good morning, Sana', style: AppText.s(16, W.w8, color: txt)),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: dark ? AppColors.stDarkCard : AppColors.card,
                  borderRadius: AppRadius.all(12),
                  border: Border.all(color: line),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 6, children: [
                  Text("Today's workout", style: AppText.s(11.5, W.w6, color: AppColors.muted)),
                  Text('Upper body · Week 3', style: AppText.s(14, W.w7, color: txt)),
                  ClipRRect(
                    borderRadius: AppRadius.all(3),
                    child: Container(
                      height: 6,
                      color: dark ? AppColors.stDarkCardLine : AppColors.sub,
                      alignment: Alignment.centerLeft,
                      child: FractionallySizedBox(widthFactor: .4, heightFactor: 1, child: Container(decoration: BoxDecoration(color: color, borderRadius: AppRadius.all(3)))),
                    ),
                  ),
                  Container(
                    height: 34,
                    margin: const EdgeInsets.only(top: 4),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: color, borderRadius: AppRadius.all(9)),
                    child: Text('Start workout', style: AppText.s(13, W.w7, color: AppColors.white)),
                  ),
                ]),
              ),
              Container(
                padding: const EdgeInsets.only(top: 8),
                decoration: BoxDecoration(border: Border(top: BorderSide(color: line))),
                child: Row(children: [
                  tab(AppIcons.home, 'Today', true),
                  tab(AppIcons.programs, 'Train', false),
                  tab(AppIcons.bowl, 'Eat', false),
                  tab(AppIcons.progress, 'Progress', false),
                ]),
              ),
            ]),
          ),
        ),
        Text('Changes show for every client after Apply.', style: AppText.s(12, W.w5, color: AppColors.muted)),
      ]),
    );
  }
}
