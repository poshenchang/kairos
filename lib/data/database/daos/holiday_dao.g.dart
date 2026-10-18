// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'holiday_dao.dart';

// ignore_for_file: type=lint
mixin _$HolidayDaoMixin on DatabaseAccessor<AppDatabase> {
  $HolidaysTable get holidays => attachedDatabase.holidays;
  HolidayDaoManager get managers => HolidayDaoManager(this);
}

class HolidayDaoManager {
  final _$HolidayDaoMixin _db;
  HolidayDaoManager(this._db);
  $$HolidaysTableTableManager get holidays =>
      $$HolidaysTableTableManager(_db.attachedDatabase, _db.holidays);
}
