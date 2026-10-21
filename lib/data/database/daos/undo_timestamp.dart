// lib/data/database/daos/undo_timestamp.dart
//
// Timestamp for undoing a change (restoring a deleted row, un-completing a task).

/// `updatedAt` to stamp on a row when undoing a change made at [changedAt].
///
/// Drift stores timestamps at one-second precision, and sync only lets the
/// undone version win when it is strictly newer (more than 1s newer when
/// reviving a deleted row, see `_shouldRemoteOverrideLocal`). An undo tapped
/// within the same second as the change would otherwise lose on other devices.
DateTime undoTimestamp(DateTime changedAt) {
  final now = DateTime.now().toUtc();
  final minimum = changedAt.toUtc().add(const Duration(seconds: 2));
  return now.isAfter(minimum) ? now : minimum;
}
