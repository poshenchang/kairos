// lib/data/database/daos/restore_timestamp.dart
//
// Timestamp for undoing a soft delete.

/// `updatedAt` to stamp on a restored row.
///
/// Drift stores timestamps at one-second precision, and sync only lets an
/// active record revive a deleted one when it is more than 1s newer
/// (see `_shouldRemoteOverrideLocal`). An undo tapped within the same second
/// as the delete would otherwise stay deleted on other devices.
DateTime restoreTimestamp(DateTime deletedAt) {
  final now = DateTime.now().toUtc();
  final minimum = deletedAt.toUtc().add(const Duration(seconds: 2));
  return now.isAfter(minimum) ? now : minimum;
}
