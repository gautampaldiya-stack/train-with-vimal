import 'package:dio/dio.dart';

/// Backend error shape: {"error": {"code", "message", "fields"}}.
class ApiError implements Exception {
  ApiError(this.message, {this.code = 'error', this.fields = const {}, this.status, this.offline = false});
  final String message;
  final String code;
  final Map<String, List<String>> fields;
  final int? status;
  final bool offline;

  String? field(String name) => fields[name]?.isNotEmpty == true ? fields[name]!.first : null;

  factory ApiError.from(Object e) {
    if (e is ApiError) return e;
    if (e is DioException) {
      final r = e.response;
      if (r == null) {
        return ApiError('No internet. We will try again when you are back online.', code: 'offline', offline: true);
      }
      final data = r.data;
      if (data is Map && data['error'] is Map) {
        final err = data['error'] as Map;
        final f = <String, List<String>>{};
        if (err['fields'] is Map) {
          (err['fields'] as Map).forEach((k, v) => f['$k'] = v is List ? v.map((x) => '$x').toList() : ['$v']);
        }
        return ApiError('${err['message'] ?? 'Something went wrong.'}', code: '${err['code'] ?? 'error'}', fields: f, status: r.statusCode);
      }
      return ApiError('Something went wrong (${r.statusCode}).', status: r.statusCode);
    }
    return ApiError('Something went wrong.');
  }

  @override
  String toString() => message;
}
