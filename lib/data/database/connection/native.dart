// lib/data/database/connection/native.dart

import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

LazyDatabase openConnection() {
  return LazyDatabase(() async {
    final supportDir = await getApplicationSupportDirectory();
    if (!await supportDir.exists()) {
      await supportDir.create(recursive: true);
    }
    final file = File(p.join(supportDir.path, 'kairos.sqlite'));

    // Migrate any legacy database file from ~/Documents/kairos.sqlite
    try {
      final docDir = await getApplicationDocumentsDirectory();
      final legacyFile = File(p.join(docDir.path, 'kairos.sqlite'));
      if (await legacyFile.exists()) {
        if (!await file.exists()) {
          await legacyFile.rename(file.path);
        } else {
          await legacyFile.delete();
        }
        final legacyWal = File(p.join(docDir.path, 'kairos.sqlite-wal'));
        if (await legacyWal.exists()) {
          if (!await File(p.join(supportDir.path, 'kairos.sqlite-wal')).exists()) {
            await legacyWal.rename(p.join(supportDir.path, 'kairos.sqlite-wal'));
          } else {
            await legacyWal.delete();
          }
        }
        final legacyShm = File(p.join(docDir.path, 'kairos.sqlite-shm'));
        if (await legacyShm.exists()) {
          if (!await File(p.join(supportDir.path, 'kairos.sqlite-shm')).exists()) {
            await legacyShm.rename(p.join(supportDir.path, 'kairos.sqlite-shm'));
          } else {
            await legacyShm.delete();
          }
        }
      }
    } catch (_) {
      // Ignore migration errors and continue with support directory file
    }

    return NativeDatabase.createInBackground(file);
  });
}

