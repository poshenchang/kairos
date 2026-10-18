/// Plain Dart enums used across the Kairos data layer.
/// These are NOT Drift tables — they are serialized to/from text columns.
library;

// ---------------------------------------------------------------------------
// EventType
// ---------------------------------------------------------------------------

enum EventType {
  classSession,
  gym,
  meeting,
  interview,
  transportation,
  autoScheduled,
  other;

  /// The string value persisted in the Drift database.
  String toDbString() {
    switch (this) {
      case EventType.classSession:
        return 'class';
      case EventType.gym:
        return 'gym';
      case EventType.meeting:
        return 'meeting';
      case EventType.interview:
        return 'interview';
      case EventType.transportation:
        return 'transportation';
      case EventType.autoScheduled:
        return 'auto_scheduled';
      case EventType.other:
        return 'other';
    }
  }

  /// Reconstruct an [EventType] from a database string.
  /// Throws [ArgumentError] if [value] is unrecognised.
  static EventType fromDbString(String value) {
    switch (value) {
      case 'class':
        return EventType.classSession;
      case 'gym':
        return EventType.gym;
      case 'meeting':
        return EventType.meeting;
      case 'interview':
        return EventType.interview;
      case 'transportation':
        return EventType.transportation;
      case 'auto_scheduled':
        return EventType.autoScheduled;
      case 'other':
        return EventType.other;
      default:
        throw ArgumentError.value(value, 'value', 'Unknown EventType db string');
    }
  }
}

// ---------------------------------------------------------------------------
// TaskPriority
// ---------------------------------------------------------------------------

enum TaskPriority {
  low(1),
  medium(2),
  high(3);

  const TaskPriority(this.value);

  /// Numeric value persisted in the database (1 = low, 2 = medium, 3 = high).
  final int value;

  /// Reconstruct a [TaskPriority] from its numeric db value.
  static TaskPriority fromValue(int value) {
    switch (value) {
      case 1:
        return TaskPriority.low;
      case 2:
        return TaskPriority.medium;
      case 3:
        return TaskPriority.high;
      default:
        throw ArgumentError.value(value, 'value', 'Unknown TaskPriority value');
    }
  }
}

// ---------------------------------------------------------------------------
// PreferredWindow
// ---------------------------------------------------------------------------

enum PreferredWindow {
  morning,
  afternoon,
  evening,
  any;

  /// The string value persisted in the Drift database.
  String toDbString() {
    switch (this) {
      case PreferredWindow.morning:
        return 'morning';
      case PreferredWindow.afternoon:
        return 'afternoon';
      case PreferredWindow.evening:
        return 'evening';
      case PreferredWindow.any:
        return 'any';
    }
  }

  /// Reconstruct a [PreferredWindow] from a database string.
  static PreferredWindow fromDbString(String value) {
    switch (value) {
      case 'morning':
        return PreferredWindow.morning;
      case 'afternoon':
        return PreferredWindow.afternoon;
      case 'evening':
        return PreferredWindow.evening;
      case 'any':
        return PreferredWindow.any;
      default:
        throw ArgumentError.value(
            value, 'value', 'Unknown PreferredWindow db string');
    }
  }
}

// ---------------------------------------------------------------------------
// PrepType
// ---------------------------------------------------------------------------

enum PrepType {
  exam,
  interview,
  essay,
  meeting,
  custom;

  /// Total prep minutes suggested by the auto-scheduler for this prep type.
  ///
  /// - exam      → 180 min (e.g. 3 × 60-min sessions)
  /// - interview → 120 min
  /// - essay     → 60  min
  /// - meeting   → 30  min
  /// - custom    → 60  min (user-defined; treated as default)
  int get defaultPrepMinutes {
    switch (this) {
      case PrepType.exam:
        return 180;
      case PrepType.interview:
        return 120;
      case PrepType.essay:
        return 60;
      case PrepType.meeting:
        return 30;
      case PrepType.custom:
        return 60;
    }
  }
}
