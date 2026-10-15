import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../app/router.dart';
import '../../app/services.dart';
import '../../core/icons/app_icons.dart';
import '../../core/theme/theme.dart';
import '../../core/widgets/client.dart';
import '../../core/widgets/overlays.dart';
import 'account_widgets.dart';
import 'auth_frame.dart';

/// We explain first, then the phone / browser asks (boards `ClientPermissions`, `ClientPermissionsWeb`).
///
/// After the email is confirmed the page asks for notifications. Camera and photos use the same
/// page the first time they are needed: `/permissions?kind=camera&next=/progress`.
enum PermKind { notifications, camera, photos }

enum _Ps { ask, allowed, blocked }

class _Kind {
  const _Kind(this.when, this.ill, this.title, this.allowT, this.body, this.perks, this.okBody, this.noTail, this.settingName, this.short);
  final String when, ill, title, allowT, body, okBody, noTail, settingName, short;
  final List<(AppIconData, String, CaTone)> perks;
}

_Kind _kind(PermKind k, String coach) => switch (k) {
      PermKind.notifications => _Kind(
          'After you verify your email',
          'notifications',
          'Stay on track',
          'Allow notifications',
          'Get a nudge at the right time, and know the moment your coach replies.',
          const [
            (AppIcons.bell, 'Account approved and check-in due alerts', CaTone.blue),
            (AppIcons.calendarAlt, 'Workout and meal reminders, at your times', CaTone.green),
            (AppIcons.check, 'Replies and plan updates from your coach', CaTone.purple),
          ],
          'We will remind you at your times and ping you when $coach approves you.',
          'won’t get alerts. We still send emails.',
          'Show notifications',
          'Notifications',
        ),
      PermKind.camera => const _Kind(
          'When you first take a progress photo',
          'personal',
          'Use your camera',
          'Allow camera',
          'Take progress and meal photos right inside the app.',
          [
            (AppIcons.camera, 'Front, side and back progress photos', CaTone.blue),
            (AppIcons.food, 'Snap a meal for your coach to check', CaTone.green),
            (AppIcons.lock, 'Photos stay private to you and your coach', CaTone.purple),
          ],
          'We will open the camera when you add a photo.',
          'can’t take photos in the app.',
          'Use your camera',
          'Use your camera',
        ),
      PermKind.photos => const _Kind(
          'When you first pick a photo',
          'personal',
          'Pick from your photos',
          'Allow photos',
          'Choose photos you already took, like last month’s progress shot.',
          [
            (AppIcons.photo, 'Add older progress photos to compare', CaTone.blue),
            (AppIcons.lock, 'Only the photos you pick are uploaded', CaTone.green),
            (AppIcons.progress, 'See your change side by side', CaTone.purple),
          ],
          'We will open your photos when you add one.',
          'can’t pick photos from this device.',
          'See your photos',
          'Pick from your photos',
        ),
    };

/// Remembered answer per kind: allowed / blocked / later (null = not asked yet).
Future<String?> permAnswer(PermKind k) async => (await SharedPreferences.getInstance()).getString('twv.perm.${k.name}');

class PermissionsScreen extends StatefulWidget {
  const PermissionsScreen({super.key, this.kind = PermKind.notifications, this.next});
  final PermKind kind;

  /// Where to go after; empty = the normal landing page (approval wait, setup or home).
  final String? next;
  @override
  State<PermissionsScreen> createState() => _PermissionsScreenState();
}

class _PermissionsScreenState extends State<PermissionsScreen> {
  late PermKind _k = widget.kind;
  _Ps _s = _Ps.ask;
  bool _busy = false;
  final Map<PermKind, String?> _answers = {};

  String get _coach => Services.session.me?.coachFirst ?? 'your coach';
  bool get _web => kIsWeb;
  String get _where => _web ? 'browser' : 'phone';

  @override
  void initState() {
    super.initState();
    _loadAnswers();
  }

  Future<void> _loadAnswers() async {
    for (final k in PermKind.values) {
      _answers[k] = await permAnswer(k);
    }
    if (mounted) setState(() {});
  }

  Future<void> _remember(String a) async {
    _answers[_k] = a;
    (await SharedPreferences.getInstance()).setString('twv.perm.${_k.name}', a);
  }

  Permission get _perm => switch (_k) {
        PermKind.notifications => Permission.notification,
        PermKind.camera => Permission.camera,
        PermKind.photos => Permission.photos,
      };

  Future<void> _allow() async {
    setState(() => _busy = true);
    PermissionStatus st;
    try {
      // Browsers pick photos through the file picker, no permission needed.
      st = _web && _k == PermKind.photos ? PermissionStatus.granted : await _perm.request();
    } catch (_) {
      st = PermissionStatus.granted; // platform without this permission (desktop)
    }
    if (!mounted) return;
    final ok = st.isGranted || st.isLimited || st.isProvisional;
    await _remember(ok ? 'allowed' : 'blocked');
    if (!mounted) return;
    setState(() {
      _busy = false;
      _s = ok ? _Ps.allowed : _Ps.blocked;
    });
    if (ok) showToast(context, 'You are all set', sub: 'You can change this in your $_where settings', kind: ToastKind.ok);
  }

  Future<void> _notNow() async {
    await _remember('later');
    if (!mounted) return;
    showToast(context, 'No problem', sub: 'We will ask again when you need it', kind: ToastKind.info);
    _finish();
  }

  Future<void> _settings() async {
    showToast(context, 'Opening settings', sub: _web ? 'Site settings for ${Uri.base.host}' : 'Settings › Apps › Train With Vimal', kind: ToastKind.info);
    if (!_web) await openAppSettings();
  }

  void _finish() {
    final me = Services.session.me;
    final next = widget.next;
    context.go(next != null && next.isNotEmpty ? next : (me == null ? '/login' : landingFor(me)));
  }

  void _pick(PermKind k) => setState(() {
        _k = k;
        _s = switch (_answers[k]) { 'allowed' => _Ps.allowed, 'blocked' => _Ps.blocked, _ => _Ps.ask };
      });

  @override
  Widget build(BuildContext context) {
    final k = _kind(_k, _coach);
    final how = _web
        ? ['Click the lock next to the web address', 'Find ${k.settingName.toLowerCase()}', 'Change it to Allow']
        : ['Open your phone Settings', 'Tap Apps, then Train With Vimal', 'Turn on ${_k.name}'];
    final (children, foot) = switch (_s) {
      _Ps.ask => (
          [
            AuthTop(lead: _When(k.when), hideOnWeb: false, help: !authSplit(context)),
            IllBox(k.ill),
            AuthHeading(k.title, sub: k.body),
            Column(spacing: 4, children: [
              for (final (icon, t, tone) in k.perks)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(spacing: 12, children: [
                    CaIconTile(icon: icon, tone: tone),
                    Expanded(child: Text(t, style: AppText.s(14, W.w7, h: 1.35))),
                  ]),
                ),
            ]),
            CaCaption('You can change this any time in your $_where settings.', icon: AppIcons.info),
          ],
          [
            CaButton(k.allowT, loading: _busy, onPressed: _allow),
            CaButton('Not now', kind: CaBtnKind.out, onPressed: _notNow),
          ],
        ),
      _Ps.allowed => (
          [
            AuthTop(lead: _When(k.when), hideOnWeb: false, help: !authSplit(context)),
            const StatusBadge(ok: true),
            AuthHeading('You are all set', sub: k.okBody, center: true),
          ],
          [CaButton(widget.next == null && _k == PermKind.notifications ? 'Continue' : 'Done', trailingIcon: AppIcons.chevronRight, onPressed: _finish)],
        ),
      _Ps.blocked => (
          [
            AuthTop(lead: _When(k.when), hideOnWeb: false, help: !authSplit(context)),
            const _BlockedBadge(),
            AuthHeading('Permission not given', sub: 'Your $_where blocked it. The app still works, you just ${k.noTail}', center: true),
            CaCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 10, children: [
                Text('To turn it on later', style: AppText.s(15, W.w8)),
                for (final (i, t) in how.indexed)
                  Row(spacing: 10, children: [
                    Container(
                      width: 22,
                      height: 22,
                      alignment: Alignment.center,
                      decoration: const BoxDecoration(color: AppColors.accentSoft, shape: BoxShape.circle),
                      child: Text('${i + 1}', style: AppText.s(11.5, W.w8, color: AppColors.accentText)),
                    ),
                    Expanded(child: Text(t, style: AppText.s(13, W.w6, color: AppColors.text2))),
                  ]),
              ]),
            ),
          ],
          [
            CaButton('Open settings', onPressed: _settings),
            CaButton('Continue without it', kind: CaBtnKind.out, onPressed: _finish),
          ],
        ),
    };
    (String, CaTone) pill(PermKind p) => switch (_answers[p]) {
          'allowed' => ('Allowed', CaTone.green),
          'blocked' => ('Blocked', CaTone.amber),
          'later' => ('Not now', CaTone.gray),
          _ => ('To ask', CaTone.gray),
        };
    return AuthFrame(
      list: BrandList(
        kicker: 'PERMISSIONS',
        title: 'Your phone asks once',
        sub: 'We explain first, so you can choose. You can change it any time in settings.',
        numbered: false,
        card: ('Nothing is turned on without you.', 'The browser asks only after you tap Allow.'),
        rows: [
          for (final p in PermKind.values)
            BrandRow(_kind(p, _coach).short, _kind(p, _coach).when, current: p == _k, pill: pill(p).$1, pillTone: pill(p).$2, onTap: () => _pick(p)),
        ],
      ),
      foot: foot,
      children: children,
    );
  }
}

/// `ac-when`: grey pill saying when the app asks.
class _When extends StatelessWidget {
  const _When(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.centerLeft,
        child: Container(
          height: 26,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(color: AppColors.sub, borderRadius: BorderRadius.circular(99)),
          child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(11.5, W.w7, color: AppColors.text2, h: 1.2)),
        ),
      );
}

/// `wl-badge wait` with the alert icon.
class _BlockedBadge extends StatelessWidget {
  const _BlockedBadge();
  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.only(top: authSplit(context) ? 0 : 26),
        child: Center(
          child: Container(
            width: 64,
            height: 64,
            alignment: Alignment.center,
            decoration: const BoxDecoration(color: AppColors.amberBg, shape: BoxShape.circle),
            child: const AppIcon(AppIcons.alert, size: 30, color: AppColors.amberText, stroke: 2.2),
          ),
        ),
      );
}
