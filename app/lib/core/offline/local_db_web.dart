import 'package:sembast_web/sembast_web.dart';

Future<Database> openDb() => databaseFactoryWeb.openDatabase('twv.db');
