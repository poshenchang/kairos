// lib/ui/screens/calendar/widgets/drag_schedule_item.dart
//
// Data model representing a draggable task, subtask, or habit payload
// that can be dropped onto the weekly timetable grid for semi-manual scheduling.

import 'package:kairos/data/database/app_database.dart';

enum DragScheduleType {
  task,
  subtask,
  habit,
  prep,
}

class DragScheduleItem {
  final DragScheduleType type;
  final String title;
  final String category;
  final int durationMinutes;
  final Task? task;
  final Subtask? subtask;
  final Habit? habit;
  final Event? parentEvent;

  const DragScheduleItem({
    required this.type,
    required this.title,
    required this.category,
    required this.durationMinutes,
    this.task,
    this.subtask,
    this.habit,
    this.parentEvent,
  });

  /// The auto-schedule source string recorded in the Event table
  /// to track which task, subtask, habit, or prep spawned the scheduled block.
  String get scheduleSource {
    return switch (type) {
      DragScheduleType.habit => 'habit:${habit?.id ?? 0}',
      DragScheduleType.subtask => 'task:${task?.id ?? 0}:subtask:${subtask?.id ?? 0}',
      DragScheduleType.task => 'task:${task?.id ?? 0}',
      DragScheduleType.prep => 'event:${parentEvent?.id ?? 0}:prep',
    };
  }
}

