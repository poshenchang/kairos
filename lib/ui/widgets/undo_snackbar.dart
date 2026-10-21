// lib/ui/widgets/undo_snackbar.dart
//
// Transient "Deleted X · UNDO" snackbar shown after a soft delete.

import 'package:flutter/material.dart';

void showUndoSnackBar(
  BuildContext context, {
  required String message,
  required Future<void> Function() onUndo,
}) {
  final messenger = ScaffoldMessenger.of(context);
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(
    SnackBar(
      content: Text(message, maxLines: 1, overflow: TextOverflow.ellipsis),
      duration: const Duration(seconds: 5),
      // SnackBars with an action persist by default; this one should time out.
      persist: false,
      action: SnackBarAction(label: 'UNDO', onPressed: onUndo),
    ),
  );
}
