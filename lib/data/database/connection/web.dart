// lib/data/database/connection/web.dart

import 'package:drift/drift.dart';
import 'package:drift/wasm.dart';

LazyDatabase openConnection() {
  return LazyDatabase(() async {
    final result = await WasmDatabase.open(
      databaseName: 'kairos',
      sqlite3Uri: Uri.parse('sqlite3.wasm'),
      driftWorkerUri: Uri.parse('drift_worker.js'),
    );
    return result.resolvedExecutor;
  });
}

