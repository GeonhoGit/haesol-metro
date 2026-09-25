import 'package:flutter/material.dart';

import 'game/catalog.dart';
import 'game/progress.dart';
import 'ui/app.dart';

export 'ui/app.dart' show HaesolApp;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final catalog = await PuzzleCatalog.load();
  final store = await ProgressStore.open();
  runApp(HaesolApp(catalog: catalog, store: store));
}
