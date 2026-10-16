import 'save_file_io.dart' if (dart.library.js_interop) 'save_file_web.dart' as impl;

/// Saves bytes the server sent (a CSV export) as a file: the browser download on web, the Downloads (or
/// documents) folder elsewhere. Returns where it went, for the toast.
Future<String> saveFile(String name, List<int> bytes, {String mime = 'text/csv'}) => impl.saveFile(name, bytes, mime);
