import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/services.dart';
import '../api/api_error.dart';
import '../theme/theme.dart';
import 'button.dart';

/// Loads data for a screen: shows the cached copy at once (offline friendly), then the fresh one.
/// [reloadOn] lets a screen refresh when outbox items with these tags sync or a realtime event arrives.
class Loader<T> extends StatefulWidget {
  const Loader({super.key, required this.fetch, required this.builder, this.cacheKey, this.map, this.reloadOn = const [], this.loading, this.events = const []});
  final Future<dynamic> Function() fetch;
  final T Function(dynamic json)? map;
  final Widget Function(BuildContext context, T data, Future<void> Function() reload) builder;
  final String? cacheKey;
  final List<String> reloadOn, events;
  final Widget? loading;

  @override
  State<Loader<T>> createState() => LoaderState<T>();
}

class LoaderState<T> extends State<Loader<T>> {
  T? _data;
  ApiError? _error;
  bool _busy = false;
  final _subs = <StreamSubscription>[];

  @override
  void initState() {
    super.initState();
    _start();
    if (widget.reloadOn.isNotEmpty) {
      _subs.add(Services.outbox.results.where((r) => widget.reloadOn.any((t) => r.tag.startsWith(t))).listen((_) => reload()));
    }
    if (widget.events.isNotEmpty) {
      _subs.add(Services.realtime.events.where((e) => widget.events.contains(e.event)).listen((_) => reload()));
    }
  }

  @override
  void didUpdateWidget(covariant Loader<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.cacheKey != widget.cacheKey) {
      _data = null;
      _start();
    }
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    super.dispose();
  }

  T _map(dynamic j) => widget.map != null ? widget.map!(j) : j as T;

  Future<void> _start() async {
    if (widget.cacheKey != null) {
      final c = await Services.cache.read(widget.cacheKey!);
      if (c != null && mounted && _data == null) setState(() => _data = _map(c));
    }
    await reload();
  }

  Future<void> reload() async {
    if (_busy) return;
    _busy = true;
    try {
      final j = await widget.fetch();
      if (widget.cacheKey != null) unawaited(Services.cache.write(widget.cacheKey!, j));
      if (mounted) {
        setState(() {
          _data = _map(j);
          _error = null;
        });
      }
    } on ApiError catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      _busy = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_data != null) return widget.builder(context, _data as T, reload);
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, spacing: 10, children: [
            Text(_error!.offline ? 'You are offline' : 'Could not load this', style: AppText.s(15, W.w7)),
            Text(_error!.message, style: AppText.sub, textAlign: TextAlign.center),
            AppButton('Try again', onPressed: reload),
          ]),
        ),
      );
    }
    return widget.loading ?? const Center(child: Padding(padding: EdgeInsets.all(32), child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.2, color: AppColors.accent))));
  }
}
