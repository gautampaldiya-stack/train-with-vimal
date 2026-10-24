import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'api_error.dart';
import 'config.dart';
import 'token_store.dart';

/// One dio client for the whole app: adds the access token, refreshes it once on 401, maps errors to [ApiError].
class Api {
  Api(this.tokens) {
    _dio = Dio(BaseOptions(
      baseUrl: AppConfig.apiBase,
      connectTimeout: const Duration(seconds: 12),
      receiveTimeout: const Duration(seconds: 30),
      headers: {'X-Client': kIsWeb ? 'web' : defaultTargetPlatform.name},
    ));
    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (o, h) {
        if (tokens.access != null && o.extra['auth'] != false) o.headers['Authorization'] = 'Bearer ${tokens.access}';
        h.next(o);
      },
      onError: (e, h) async {
        final r = e.response;
        final retried = e.requestOptions.extra['retried'] == true;
        if (r?.statusCode == 401 && !retried && tokens.refresh != null && e.requestOptions.extra['auth'] != false) {
          if (await _refresh()) {
            final o = e.requestOptions..extra['retried'] = true;
            o.headers['Authorization'] = 'Bearer ${tokens.access}';
            try {
              return h.resolve(await _dio.fetch(o));
            } on DioException catch (e2) {
              return h.next(e2);
            }
          }
          if (tokens.refresh == null) onSignedOut?.call(); // refused, not just offline
        }
        h.next(e);
      },
    ));
  }

  final TokenStore tokens;
  late final Dio _dio;
  VoidCallback? onSignedOut;
  Completer<bool>? _refreshing;

  /// An access token good for at least another minute (refreshed first if not), for callers outside dio:
  /// the realtime socket reconnects with this, never with the token it first got (they last 15 min).
  Future<String?> freshAccess() async {
    final a = tokens.access;
    if (a == null) return null;
    final exp = _expiry(a);
    if (exp != null && exp.difference(DateTime.now()) > const Duration(minutes: 1)) return a;
    if (tokens.refresh == null || !await _refresh()) return null;
    return tokens.access;
  }

  /// `exp` from the JWT payload (null when it can't be read: the server then says no and we refresh on retry).
  static DateTime? _expiry(String jwt) {
    try {
      final part = jwt.split('.')[1];
      final m = jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(part)))) as Map;
      return DateTime.fromMillisecondsSinceEpoch(((m['exp'] as num).toInt()) * 1000);
    } catch (_) {
      return null;
    }
  }

  Future<bool> _refresh() async {
    if (_refreshing != null) return _refreshing!.future;
    final c = _refreshing = Completer<bool>();
    try {
      final r = await _dio.post('auth/refresh/', data: {'refresh': tokens.refresh}, options: Options(extra: {'auth': false}));
      await tokens.save(r.data['access'], r.data['refresh']);
      c.complete(true);
    } on DioException catch (e) {
      // Only a refused refresh token signs out; no network / server restarting keeps it for the next try.
      final code = e.response?.statusCode;
      if (code == 400 || code == 401) await tokens.clear();
      c.complete(false);
    } catch (_) {
      c.complete(false);
    } finally {
      _refreshing = null;
    }
    return c.future;
  }

  Future<T> _run<T>(Future<Response> Function() f) async {
    try {
      final r = await f();
      return r.data as T;
    } catch (e) {
      throw ApiError.from(e);
    }
  }

  Future<T> get<T>(String path, {Map<String, dynamic>? query}) => _run(() => _dio.get(path, queryParameters: _clean(query)));

  Future<T> post<T>(String path, [Object? data, String? idempotencyKey, bool auth = true]) => _run(() => _dio.post(path,
      data: data, options: Options(headers: {'Idempotency-Key': ?idempotencyKey}, extra: {'auth': auth})));

  /// A file upload that reports how far it got (0 → 1).
  Future<T> upload<T>(String path, Object data, {void Function(double)? onProgress}) => _run(() => _dio.post(path,
      data: data, onSendProgress: onProgress == null ? null : (sent, total) => total > 0 ? onProgress(sent / total) : null));

  Future<T> put<T>(String path, [Object? data, String? idempotencyKey]) =>
      _run(() => _dio.put(path, data: data, options: Options(headers: {'Idempotency-Key': ?idempotencyKey})));

  Future<T> patch<T>(String path, [Object? data, String? idempotencyKey]) =>
      _run(() => _dio.patch(path, data: data, options: Options(headers: {'Idempotency-Key': ?idempotencyKey})));

  Future<T> delete<T>(String path, [Object? data, String? idempotencyKey]) =>
      _run(() => _dio.delete(path, data: data, options: Options(headers: {'Idempotency-Key': ?idempotencyKey})));

  /// Raw request used by the offline outbox (keeps its own key).
  Future<dynamic> send(String method, String path, Object? data, String key) =>
      _run(() => _dio.request(path, data: data, options: Options(method: method, headers: {'Idempotency-Key': key})));

  Future<Response<List<int>>> download(String path, {Map<String, dynamic>? query}) =>
      _dio.get<List<int>>(path, queryParameters: _clean(query), options: Options(responseType: ResponseType.bytes));

  Map<String, dynamic>? _clean(Map<String, dynamic>? q) => q == null ? null : (Map.of(q)..removeWhere((k, v) => v == null || v == ''));
}

/// A paginated list response from DRF: {count, next, previous, results}.
class Page<T> {
  Page(this.items, this.count, this.hasMore);
  final List<T> items;
  final int count;
  final bool hasMore;

  static Page<T> from<T>(dynamic data, T Function(Map<String, dynamic>) map) {
    if (data is List) return Page(data.cast<Map<String, dynamic>>().map(map).toList(), data.length, false);
    final m = data as Map<String, dynamic>;
    final list = (m['results'] as List? ?? const []).cast<Map<String, dynamic>>();
    return Page(list.map(map).toList(), (m['count'] as num?)?.toInt() ?? list.length, m['next'] != null);
  }
}
