import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'tables.dart';
import 'converters.dart';
import '../models/models.dart';

part 'app_database.g.dart';

@DriftDatabase(tables: [
  Accounts,
  Bills,
  Budgets,
  Categories,
  Piggybanks,
  Tags,
  Shortcuts,
  ShortcutTags,
])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  @override
  int get schemaVersion => 1;

  /// Deletes every row. Children first, as foreign keys are not enforced.
  Future<void> wipe() => transaction(() async {
    for (final table in allTables.toList().reversed) {
      await delete(table).go();
    }
  });
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dbFolder = await getApplicationDocumentsDirectory();
    final file = File(p.join(dbFolder.path, 'app_database.sqlite'));
    return NativeDatabase.createInBackground(file);
  });
}
