import 'package:path_provider/path_provider.dart';
import 'package:sembast/sembast_io.dart';

Future<Database> openDb() async {
  final dir = await getApplicationDocumentsDirectory();
  return databaseFactoryIo.openDatabase('${dir.path}/twv.db');
}
