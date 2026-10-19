// lib/data/database/tables/holidays_table.dart
//
// Drift table definition for academic breaks and holidays.
// Disables recurring classes and routines on active holiday dates.

import 'package:drift/drift.dart';

class Holidays extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().withLength(min: 1, max: 100)();
  TextColumn get groupName => text().withDefault(const Constant('US Holidays'))();
  DateTimeColumn get date => dateTime()();
  DateTimeColumn get endDate => dateTime().nullable()();
  BoolColumn get isEnabled => boolean().withDefault(const Constant(true))();
}

