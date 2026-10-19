// lib/data/repositories/repository_providers.dart
//
// Riverpod providers for DAOs and Repositories.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kairos/core/scheduler/scheduler_provider.dart';
import 'package:kairos/data/database/app_database.dart';
import 'package:kairos/data/repositories/event_repository.dart';
import 'package:kairos/data/repositories/task_repository.dart';

export 'package:kairos/core/scheduler/scheduler_provider.dart' show appDatabaseProvider;

final categoryDaoProvider = Provider<CategoryDao>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return db.categoryDao;
});

final eventDaoProvider = Provider<EventDao>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return db.eventDao;
});

final taskDaoProvider = Provider<TaskDao>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return db.taskDao;
});

final habitDaoProvider = Provider<HabitDao>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return db.habitDao;
});

final holidayDaoProvider = Provider<HolidayDao>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return db.holidayDao;
});

final eventRepositoryProvider = Provider<EventRepository>((ref) {
  final dao = ref.watch(eventDaoProvider);
  final holidayDao = ref.watch(holidayDaoProvider);
  return EventRepository(dao, holidayDao);
});

final taskRepositoryProvider = Provider<TaskRepository>((ref) {
  final dao = ref.watch(taskDaoProvider);
  return TaskRepository(dao);
});
