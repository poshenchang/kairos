// test/data/soft_delete_restore_test.dart
//
// Undo-after-delete: restore methods clear isDeleted and bump updatedAt
// far enough that sync treats the restore as newer than the deletion.

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kairos/data/database/app_database.dart';

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() => db.close());

  test('restoreTask brings a deleted task back with a newer timestamp', () async {
    final id = await db.taskDao.insertTask(TasksCompanion.insert(
      title: 'Accounting HW',
      dueDate: DateTime.utc(2026, 10, 27, 8),
    ));

    await db.taskDao.deleteTask(id);
    expect(await db.taskDao.getIncompleteTasks(), isEmpty);
    final deleted = (await db.select(db.tasks).get()).single;
    expect(deleted.isDeleted, isTrue);

    // Undo in the same second as the delete (timestamps are second-precision)
    await db.taskDao.restoreTask(id);
    final restored = (await db.taskDao.getIncompleteTasks()).single;

    expect(restored.id, id);
    expect(restored.isDeleted, isFalse);
    // Sync only revives a deleted record on other devices when the active one is >1s newer
    expect(restored.updatedAt.isAfter(deleted.updatedAt.add(const Duration(seconds: 1))), isTrue);
  });

  test('restoreHabit brings a deleted habit back', () async {
    final id = await db.habitDao.insertHabit(HabitsCompanion.insert(title: 'Duolingo'));

    await db.habitDao.deleteHabit(id);
    expect(await db.habitDao.getAllHabits(), isEmpty);

    await db.habitDao.restoreHabit(id);
    expect((await db.habitDao.getAllHabits()).single.id, id);
  });

  test('restoreEvent brings a deleted event back', () async {
    final id = await db.eventDao.insertEvent(EventsCompanion.insert(
      title: 'Lecture',
      category: const Value('schoolwork'),
      startTime: DateTime(2026, 10, 20, 10),
      endTime: DateTime(2026, 10, 20, 12),
    ));

    await db.eventDao.deleteEvent(id);
    expect(await db.eventDao.getAllEvents(), isEmpty);

    await db.eventDao.restoreEvent(id);
    expect((await db.eventDao.getAllEvents()).single.id, id);
  });
}
