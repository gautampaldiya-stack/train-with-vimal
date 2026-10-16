import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';

import '../icons/app_icons.dart';
import '../theme/theme.dart';
import 'hover.dart';

/// Videos and pictures shown in the app (Library items, exercise guide): an in-app player with a seek bar and
/// full screen, and a full-screen picture viewer with pinch zoom and paging.

// ─────────────────────────────── Video

/// Owns one [VideoPlayerController] and tells listeners about play / position changes.
class VideoCtl extends ChangeNotifier {
  VideoCtl(String url, {this.fallbackSeconds = 0, this.onEnd}) {
    if (url.isEmpty) return;
    final v = _v = VideoPlayerController.networkUrl(Uri.parse(url));
    v.addListener(_tick);
    v.initialize().then((_) {
      ready = true;
      notifyListeners();
    }).catchError((Object _) {
      failed = true;
      notifyListeners();
    });
  }

  VideoPlayerController? _v;
  final int fallbackSeconds;
  final VoidCallback? onEnd;
  bool ready = false, failed = false, _ended = false, _gone = false;

  /// Highest share of the video seen (0–100), for "watched" progress.
  int maxPct = 0;

  bool get hasFile => _v != null;
  VideoPlayerController? get player => ready ? _v : null;
  int get dur => ready ? _v!.value.duration.inSeconds : fallbackSeconds;
  int get pos => ready ? _v!.value.position.inSeconds : 0;
  double get pct {
    if (!ready) return 0;
    final d = _v!.value.duration.inMilliseconds;
    return d > 0 ? (_v!.value.position.inMilliseconds / d).clamp(0.0, 1.0) : 0;
  }

  bool get playing => ready && _v!.value.isPlaying;
  bool get finished => ready && dur > 0 && _v!.value.position.inMilliseconds >= _v!.value.duration.inMilliseconds - 250;
  double get aspect => ready && _v!.value.aspectRatio > 0 ? _v!.value.aspectRatio : 16 / 9;

  void _tick() {
    if (_gone || !ready) return;
    maxPct = (pct * 100).round().clamp(maxPct, 100);
    if (finished && !_v!.value.isPlaying && !_ended) {
      _ended = true;
      onEnd?.call();
    }
    notifyListeners();
  }

  Future<void> toggle() async {
    final v = _v;
    if (v == null || !ready) return;
    if (v.value.isPlaying) {
      await v.pause();
    } else {
      if (finished) await v.seekTo(Duration.zero);
      _ended = false;
      await v.play();
    }
  }

  /// Moving the player to / from full screen re-attaches it on web, which pauses it: play again if it was.
  void keepPlaying(bool was) {
    if (was) Future.delayed(const Duration(milliseconds: 250), () => _gone ? null : _v?.play());
  }

  Future<void> seekTo(double fraction, {bool play = false}) async {
    final v = _v;
    if (v == null || !ready) return;
    _ended = false;
    await v.seekTo(v.value.duration * fraction.clamp(0.0, 1.0));
    if (play) await v.play();
  }

  Future<void> seekSeconds(int s, {bool play = true}) async {
    final v = _v;
    if (v == null || !ready) return;
    _ended = false;
    await v.seekTo(Duration(seconds: s));
    if (play) await v.play();
  }

  @override
  void dispose() {
    _gone = true;
    _v?.removeListener(_tick);
    _v?.dispose();
    super.dispose();
  }
}

String mediaClock(int s) => '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';

/// `lb-vid`: the player box. Before a file loads it sits on [bg] (the item's tone); once the video is ready the
/// picture fills it on black. Label chip top left, full screen top right, round play button, seek bar and times.
class VideoBox extends StatelessWidget {
  const VideoBox({super.key, required this.ctl, required this.label, required this.bg, required this.fg, required this.height, this.onTapEmpty, this.lengthText, this.radius = 12, this.poster});
  final VideoCtl ctl;
  final String Function() label;
  final double radius;

  /// Picture behind the controls before a file plays (a YouTube still).
  final String? poster;
  final Color bg, fg;
  final double height;

  /// Play tapped when there is nothing to play here (no file, or the browser can't play it).
  final VoidCallback? onTapEmpty;
  final String? lengthText;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: ctl,
        builder: (context, _) => ClipRRect(
          borderRadius: AppRadius.all(radius),
          child: SizedBox(height: height, child: _VideoFace(ctl: ctl, label: label, bg: bg, fg: fg, onTapEmpty: onTapEmpty, lengthText: lengthText, full: false, poster: poster)),
        ),
      );
}

class _VideoFace extends StatelessWidget {
  const _VideoFace({required this.ctl, required this.label, required this.bg, required this.fg, required this.full, this.onTapEmpty, this.lengthText, this.poster});
  final String? poster;
  final VideoCtl ctl;
  final String Function() label;
  final Color bg, fg;
  final bool full;
  final VoidCallback? onTapEmpty;
  final String? lengthText;

  @override
  Widget build(BuildContext context) {
    final p = ctl.player;
    final dark = p != null;
    final ink = dark ? AppColors.white : fg;
    return Container(
      color: dark ? AppColors.black : bg,
      child: Stack(children: [
        if (p == null && (poster ?? '').isNotEmpty) Positioned.fill(child: NetImage(poster!, fit: BoxFit.cover)),
        if (p != null)
          Positioned.fill(
            child: GestureDetector(
              onTap: ctl.toggle,
              child: Center(child: AspectRatio(aspectRatio: ctl.aspect, child: VideoPlayer(p))),
            ),
          ),
        // Soft dark band at the bottom so the times and bar read on any video.
        if (p != null)
          const Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: 64,
            child: IgnorePointer(
              child: DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: AppColors.videoScrim))),
            ),
          ),
        Positioned.fill(
          child: Padding(
            padding: EdgeInsets.fromLTRB(12, full ? 16 : 10, 12, full ? 20 : 10),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Row(children: [
                Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                    height: 24,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    decoration: BoxDecoration(color: AppColors.white.withValues(alpha: .85), borderRadius: AppRadius.all(99)),
                    child: Row(mainAxisSize: MainAxisSize.min, spacing: 6, children: [
                      AppIcon(AppIcons.video, size: 13, color: AppColors.text),
                      Flexible(child: Text(label(), maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.s(11.5, W.w7, h: 1))),
                    ]),
                  ),
                  ),
                ),
                if (p != null)
                  _RoundBtn(
                    icon: full ? AppIcons.close : AppIcons.expand,
                    label: full ? 'Close full screen' : 'Full screen',
                    onTap: () {
                      final was = ctl.playing;
                      if (full) {
                        Navigator.of(context).pop();
                        ctl.keepPlaying(was);
                      } else {
                        showVideoFull(context, ctl, label: label);
                        ctl.keepPlaying(was);
                      }
                    },
                  ),
              ]),
              Column(spacing: 4, children: [
                _SeekBar(ctl: ctl, color: ink),
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  Text(mediaClock(ctl.pos), style: AppText.s(11.5, W.w7, color: ink, tabular: true)),
                  Text(ctl.dur > 0 ? mediaClock(ctl.dur) : (lengthText ?? ''), style: AppText.s(11.5, W.w7, color: ink, tabular: true)),
                ]),
              ]),
            ]),
          ),
        ),
        Align(
          alignment: const Alignment(0, -0.12),
          child: Semantics(
                label: 'Play or pause',
                button: true,
                child: Hover(
                  onTap: () => p != null ? ctl.toggle() : onTapEmpty?.call(),
                  builder: (_, h, _) => AnimatedScale(
                    scale: h ? 1.05 : 1,
                    duration: const Duration(milliseconds: 120),
                    child: Container(
                      width: 58,
                      height: 58,
                      alignment: Alignment.center,
                      decoration: const BoxDecoration(color: AppColors.white, shape: BoxShape.circle, boxShadow: [BoxShadow(color: AppColors.lbPlayShadow, blurRadius: 16, offset: Offset(0, 4))]),
                      child: ctl.hasFile && !ctl.ready && !ctl.failed
                          ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.2, color: AppColors.text))
                          : AppIcon(ctl.playing ? AppIcons.pause : AppIcons.play, size: 24, color: AppColors.text, fill: !ctl.playing),
                    ),
                  ),
                ),
              ),
        ),
      ]),
    );
  }
}

/// Seek bar: tap or drag anywhere on it to jump there.
class _SeekBar extends StatelessWidget {
  const _SeekBar({required this.ctl, required this.color});
  final VideoCtl ctl;
  final Color color;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, box) {
          void at(double x) => ctl.seekTo(x / box.maxWidth);
          return Semantics(
            slider: true,
            label: 'Seek',
            value: '${(ctl.pct * 100).round()}%',
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (d) => at(d.localPosition.dx),
              onHorizontalDragUpdate: (d) => at(d.localPosition.dx),
              child: SizedBox(
                height: 14,
                child: Center(
                  child: ClipRRect(
                    borderRadius: AppRadius.all(99),
                    child: Container(
                      height: 5,
                      color: AppColors.white.withValues(alpha: .7),
                      alignment: Alignment.centerLeft,
                      child: FractionallySizedBox(widthFactor: ctl.pct, child: Container(color: color)),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      );
}

class _RoundBtn extends StatelessWidget {
  const _RoundBtn({required this.icon, required this.label, required this.onTap});
  final AppIconData icon;
  final String label;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Semantics(
        label: label,
        button: true,
        child: Hover(
          onTap: onTap,
          builder: (_, h, _) => Container(
            width: 30,
            height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: AppColors.white.withValues(alpha: h ? 1 : .85), shape: BoxShape.circle),
            child: AppIcon(icon, size: 15, color: AppColors.text),
          ),
        ),
      );
}

/// The same player full screen on black (rotating the phone gives a bigger picture).
Future<void> showVideoFull(BuildContext context, VideoCtl ctl, {required String Function() label}) => Navigator.of(context, rootNavigator: true).push(
      PageRouteBuilder<void>(
        opaque: true,
        transitionDuration: const Duration(milliseconds: 160),
        pageBuilder: (_, _, _) => Scaffold(
          backgroundColor: AppColors.black,
          body: SafeArea(
            child: ListenableBuilder(
              listenable: ctl,
              builder: (ctx, _) => _VideoFace(ctl: ctl, label: label, bg: AppColors.black, fg: AppColors.white, full: true),
            ),
          ),
        ),
        transitionsBuilder: (_, a, _, child) => FadeTransition(opacity: a, child: child),
      ),
    );

// ─────────────────────────────── YouTube

/// The video id in a youtu.be / youtube.com/watch / shorts / embed link ('' when it is not one).
String youtubeId(String url) => url.isEmpty ? '' : (YoutubePlayerController.convertUrlToId(url) ?? '');

/// A YouTube video playing right here (YouTube's own player: play, seek, full screen), with
/// "Open in YouTube" under it for people who prefer the app.
class YoutubeBox extends StatefulWidget {
  const YoutubeBox({super.key, required this.url, this.onReady});
  final String url;

  /// Gives the parent the controller (chapters jump with `seekTo`).
  final ValueChanged<YoutubePlayerController>? onReady;
  @override
  State<YoutubeBox> createState() => _YoutubeBoxState();
}

class _YoutubeBoxState extends State<YoutubeBox> {
  late final YoutubePlayerController yt = YoutubePlayerController.fromVideoId(
    videoId: youtubeId(widget.url),
    params: const YoutubePlayerParams(showFullscreenButton: true, strictRelatedVideos: true),
  );

  @override
  void initState() {
    super.initState();
    widget.onReady?.call(yt);
  }

  @override
  void dispose() {
    yt.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 8, children: [
        ClipRRect(
          borderRadius: AppRadius.all(12),
          child: ColoredBox(color: AppColors.black, child: YoutubePlayer(controller: yt, aspectRatio: 16 / 9, backgroundColor: AppColors.black)),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: Semantics(
            link: true,
            child: Hover(
              onTap: () => launchUrl(Uri.parse(widget.url), mode: LaunchMode.externalApplication),
              builder: (_, h, _) => Row(mainAxisSize: MainAxisSize.min, spacing: 5, children: [
                Text('Open in YouTube', style: AppText.s(12.5, W.w7, color: h ? AppColors.accentHover : AppColors.accentText)),
                AppIcon(AppIcons.external, size: 13, color: h ? AppColors.accentHover : AppColors.accentText),
              ]),
            ),
          ),
        ),
      ]);
}

// ─────────────────────────────── Pictures

/// Full-screen pictures on black: pinch / scroll to zoom, swipe or arrows for the next one, "2 / 6" at the top.
Future<void> showImageViewer(BuildContext context, List<String> urls, {int start = 0, String? title}) => Navigator.of(context, rootNavigator: true).push(
      PageRouteBuilder<void>(
        opaque: true,
        transitionDuration: const Duration(milliseconds: 160),
        pageBuilder: (_, _, _) => _ImageViewer(urls: urls, start: start, title: title),
        transitionsBuilder: (_, a, _, child) => FadeTransition(opacity: a, child: child),
      ),
    );

class _ImageViewer extends StatefulWidget {
  const _ImageViewer({required this.urls, required this.start, this.title});
  final List<String> urls;
  final int start;
  final String? title;
  @override
  State<_ImageViewer> createState() => _ImageViewerState();
}

class _ImageViewerState extends State<_ImageViewer> {
  late final _pages = PageController(initialPage: widget.start);
  late int i = widget.start;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _go(int to) => _pages.animateToPage(to, duration: const Duration(milliseconds: 220), curve: Curves.easeOut);

  @override
  Widget build(BuildContext context) {
    final n = widget.urls.length;
    return Scaffold(
      backgroundColor: AppColors.black,
      body: SafeArea(
        child: Stack(children: [
          PageView.builder(
            controller: _pages,
            itemCount: n,
            onPageChanged: (v) => setState(() => i = v),
            itemBuilder: (_, k) => InteractiveViewer(
              minScale: 1,
              maxScale: 5,
              child: Center(child: NetImage(widget.urls[k], fit: BoxFit.contain, dark: true)),
            ),
          ),
          Positioned(
            left: 12,
            right: 12,
            top: 10,
            child: Row(spacing: 10, children: [
              Expanded(
                child: Text(
                  [if (widget.title != null) widget.title!, if (n > 1) '${i + 1} / $n'].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.s(13.5, W.w7, color: AppColors.white),
                ),
              ),
              _RoundBtn(icon: AppIcons.close, label: 'Close', onTap: () => Navigator.of(context).pop()),
            ]),
          ),
          if (n > 1 && i > 0)
            Align(alignment: Alignment.centerLeft, child: Padding(padding: const EdgeInsets.all(10), child: _RoundBtn(icon: AppIcons.chevronLeft, label: 'Previous', onTap: () => _go(i - 1)))),
          if (n > 1 && i < n - 1)
            Align(alignment: Alignment.centerRight, child: Padding(padding: const EdgeInsets.all(10), child: _RoundBtn(icon: AppIcons.chevronRight, label: 'Next', onTap: () => _go(i + 1)))),
        ]),
      ),
    );
  }
}

/// A network picture with a spinner while it loads and a quiet placeholder if it fails.
class NetImage extends StatelessWidget {
  const NetImage(this.url, {super.key, this.fit = BoxFit.contain, this.dark = false, this.height});
  final String url;
  final BoxFit fit;
  final bool dark;
  final double? height;
  @override
  Widget build(BuildContext context) => Image.network(
        url,
        fit: fit,
        height: height,
        loadingBuilder: (_, child, p) => p == null
            ? child
            : SizedBox(
                height: height ?? 160,
                child: Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.2, color: dark ? AppColors.white : AppColors.accent))),
              ),
        errorBuilder: (_, _, _) => SizedBox(
          height: height ?? 160,
          child: Center(child: AppIcon(AppIcons.photo, size: 28, color: dark ? AppColors.white : AppColors.muted)),
        ),
      );
}
