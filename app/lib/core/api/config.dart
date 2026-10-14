/// Backend address. Pass at build/run time: --dart-define=API_URL=https://api.example.com
abstract final class AppConfig {
  static const apiUrl = String.fromEnvironment('API_URL', defaultValue: 'http://localhost:8000');
  static String get apiBase => '$apiUrl/api/v1/';
  static String get wsUrl => '${apiUrl.replaceFirst('http', 'ws')}/ws/notifications/';
}
