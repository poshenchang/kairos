// lib/data/database/connection/unsupported.dart

import 'package:drift/drift.dart';

LazyDatabase openConnection() => throw UnsupportedError(
      'Cannot open database: platform not supported.',
    );

