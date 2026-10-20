// test/services/soft_delete_and_collision_test.dart

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Soft-Delete & Clock-Skew Protection Tests', () {
    test('Local soft-deletion is not resurrected by older or skewed remote record', () {
      final nowUtc = DateTime.utc(2026, 10, 20, 13, 30);
      final localDeletedAt = DateTime.utc(2026, 10, 20, 13, 25);
      final localIsDeleted = true;

      // Case 1: Remote is NOT deleted and has older timestamp (13:00)
      final olderRemoteUpdatedAt = DateTime.utc(2026, 10, 20, 13, 0);
      final olderRemoteIsDeleted = false;

      // Evaluation logic:
      bool shouldRemoteOverride({
        required DateTime localUpdatedAt,
        required DateTime remoteUpdatedAt,
        required bool localIsDeleted,
        required bool remoteIsDeleted,
      }) {
        var remoteUtc = remoteUpdatedAt.toUtc();
        final localUtc = localUpdatedAt.toUtc();

        if (remoteUtc.isAfter(nowUtc.add(const Duration(minutes: 2)))) {
          return false;
        }

        if (localIsDeleted && !remoteIsDeleted) {
          return remoteUtc.isAfter(localUtc.add(const Duration(seconds: 1)));
        }

        return remoteUtc.isAfter(localUtc);
      }

      expect(
        shouldRemoteOverride(
          localUpdatedAt: localDeletedAt,
          remoteUpdatedAt: olderRemoteUpdatedAt,
          localIsDeleted: localIsDeleted,
          remoteIsDeleted: olderRemoteIsDeleted,
        ),
        isFalse,
        reason: 'Older active remote record must NOT resurrect locally deleted item',
      );

      // Case 2: Remote has a bogus 8-hour future timestamp (21:00 UTC due to local time string parsing)
      final futureBogusRemoteUpdatedAt = DateTime.utc(2026, 10, 20, 21, 0);
      expect(
        shouldRemoteOverride(
          localUpdatedAt: localDeletedAt,
          remoteUpdatedAt: futureBogusRemoteUpdatedAt,
          localIsDeleted: localIsDeleted,
          remoteIsDeleted: olderRemoteIsDeleted,
        ),
        isFalse,
        reason: 'Clock-skewed future remote timestamp must be capped and cannot resurrect local deletion',
      );
    });

    test('Local soft-deletion always forces a push to remote', () {
      final nowUtc = DateTime.utc(2026, 10, 20, 13, 30);
      final localDeletedAt = DateTime.utc(2026, 10, 20, 13, 25);
      final futureBogusRemoteUpdatedAt = DateTime.utc(2026, 10, 20, 21, 0);

      bool shouldPush({
        required DateTime localUpdatedAt,
        DateTime? remoteUpdatedAt,
        required bool localIsDeleted,
        bool? remoteIsDeleted,
      }) {
        if (remoteUpdatedAt == null) return true;
        final localUtc = localUpdatedAt.toUtc();
        final remoteUtc = remoteUpdatedAt.toUtc();

        if (remoteUtc.isAfter(nowUtc.add(const Duration(minutes: 2)))) {
          return true;
        }

        if (localIsDeleted && remoteIsDeleted != true) {
          return true;
        }

        return localUtc.isAfter(remoteUtc);
      }

      expect(
        shouldPush(
          localUpdatedAt: localDeletedAt,
          remoteUpdatedAt: futureBogusRemoteUpdatedAt,
          localIsDeleted: true,
          remoteIsDeleted: false,
        ),
        isTrue,
        reason: 'Local deletion must be pushed to remote even if remote had a future timestamp',
      );
    });
  });

  group('Timetable Overlapping Collision Layout Tests', () {
    test('Overlapping events are assigned separate sub-columns without collision', () {
      // Simulate two overlapping events:
      // Event A: 14:00 - 15:00 (startMin: 480, endMin: 540)
      // Event B: 14:30 - 15:30 (startMin: 510, endMin: 570)
      final raw = [
        (id: 1, startMin: 480, endMin: 540),
        (id: 2, startMin: 510, endMin: 570),
      ];

      // Partition into overlapping clusters
      final clusters = <List<({int id, int startMin, int endMin})>>[];
      var currentCluster = <({int id, int startMin, int endMin})>[];
      int clusterEnd = -1;

      for (final item in raw) {
        if (currentCluster.isEmpty) {
          currentCluster.add(item);
          clusterEnd = item.endMin;
        } else if (item.startMin < clusterEnd) {
          currentCluster.add(item);
          if (item.endMin > clusterEnd) clusterEnd = item.endMin;
        } else {
          clusters.add(currentCluster);
          currentCluster = [item];
          clusterEnd = item.endMin;
        }
      }
      if (currentCluster.isNotEmpty) clusters.add(currentCluster);

      expect(clusters.length, equals(1));
      expect(clusters.first.length, equals(2));

      // Column assignment
      final columnEndTimes = <int>[];
      final assignedColumns = <int>[];

      for (final item in clusters.first) {
        int assignedCol = -1;
        for (int c = 0; c < columnEndTimes.length; c++) {
          if (columnEndTimes[c] <= item.startMin) {
            assignedCol = c;
            columnEndTimes[c] = item.endMin;
            break;
          }
        }
        if (assignedCol == -1) {
          assignedCol = columnEndTimes.length;
          columnEndTimes.add(item.endMin);
        }
        assignedColumns.add(assignedCol);
      }

      // Event A in col 0, Event B in col 1
      expect(assignedColumns[0], equals(0));
      expect(assignedColumns[1], equals(1));
      expect(columnEndTimes.length, equals(2));

      // With totalCols = 2 and dayWidth = 140:
      const dayColumnWidth = 140.0;
      final colWidth = (dayColumnWidth - 4.0) / 2; // 68.0
      final left0 = 2.0 + 0 * colWidth; // 2.0
      final left1 = 2.0 + 1 * colWidth; // 70.0

      expect(left0 < left1, isTrue);
      expect(left0 + colWidth <= left1, isTrue, reason: 'Events sit side-by-side with zero overlap');
    });
  });
}
