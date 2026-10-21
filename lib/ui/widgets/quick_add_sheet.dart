// lib/ui/widgets/quick_add_sheet.dart
//
// One-line task entry ("HW3 fri 5pm #school") with a live preview of what
// was understood. Each recognised piece shows as a chip; removing a chip
// turns that text back into part of the title. "More options" opens the full
// form prefilled with the parsed values.

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:kairos/data/database/app_database.dart';
import 'package:kairos/data/repositories/repository_providers.dart';
import 'package:kairos/services/form_defaults_service.dart';
import 'package:kairos/services/quick_add_parser.dart';
import 'package:kairos/services/settings_service.dart';
import 'package:kairos/services/timezone_service.dart';
import 'package:kairos/ui/providers/app_providers.dart';
import 'package:kairos/ui/widgets/task_form_sheet.dart';
import 'package:kairos/ui/widgets/undo_snackbar.dart';

class QuickAddSheet extends ConsumerStatefulWidget {
  const QuickAddSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => const QuickAddSheet(),
    );
  }

  @override
  ConsumerState<QuickAddSheet> createState() => _QuickAddSheetState();
}

class _QuickAddSheetState extends ConsumerState<QuickAddSheet> {
  final _controller = TextEditingController();

  @override
  void initState() {
    super.initState();
    _controller.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  QuickAddResult _parse(List<Category> categories) {
    final now = TimezoneService.instance.activeNow(ref.read(settingsNotifierProvider));
    return parseQuickAdd(_controller.text, now: now, categories: categories);
  }

  String _defaultCategory(List<Category> categories) {
    final last = ref.read(formDefaultsServiceProvider).lastTaskCategory;
    if (last != null && categories.any((c) => c.slug == last)) return last;
    return categories.any((c) => c.slug == 'schoolwork') ? 'schoolwork' : (categories.firstOrNull?.slug ?? 'other');
  }

  void _keepAsText(QuickAddToken token) {
    final text = keepTokenAsText(_controller.text, token);
    _controller.value = TextEditingValue(text: text, selection: TextSelection.collapsed(offset: text.length));
  }

  Future<void> _add(QuickAddResult r, String category) async {
    if (r.title.isEmpty) return;
    if (r.due == null) return _openFullForm(r, category);

    final settings = ref.read(settingsNotifierProvider);
    final defaults = ref.read(formDefaultsServiceProvider);
    final dao = ref.read(taskDaoProvider);
    final id = await dao.insertTask(TasksCompanion.insert(
      title: r.title,
      category: Value(category),
      dueDate: TimezoneService.instance.fromActiveTime(r.due!, settings),
      isRecurring: Value(r.isRecurring),
      rrule: Value(r.isRecurring ? weeklyRrule(r.due!) : null),
      estimatedMinutes: Value(defaults.lastTaskEstimatedMinutes ?? 120),
    ));
    if (!mounted) return;

    showUndoSnackBar(
      context,
      message: 'Added "${r.title}" · due ${_formatDue(r.due!)}',
      onUndo: () => dao.deleteTask(id),
    );
    Navigator.of(context).pop();
  }

  void _openFullForm(QuickAddResult r, String category) {
    final navigator = Navigator.of(context);
    final parentContext = navigator.context;
    navigator.pop();
    TaskFormSheet.show(
      parentContext,
      draft: TaskDraft(title: r.title, due: r.due, category: category, isRecurring: r.isRecurring),
    );
  }

  String _formatDue(DateTime due) {
    final now = TimezoneService.instance.activeNow(ref.read(settingsNotifierProvider));
    final today = DateTime(now.year, now.month, now.day);
    final dueDay = DateTime(due.year, due.month, due.day);
    final day = switch (dueDay.difference(today).inDays) {
      0 => 'today',
      1 => 'tomorrow',
      _ => DateFormat('EEE, MMM d').format(due),
    };
    return '$day at ${DateFormat('HH:mm').format(due)}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final categories = ref.watch(allCategoriesProvider).value ?? [];
    final r = _parse(categories);
    final category = r.category ?? _defaultCategory(categories);
    final cat = categories.where((c) => c.slug == category).firstOrNull;
    final hasInput = _controller.text.trim().isNotEmpty;

    String chipLabel(QuickAddToken t) => switch (t.kind) {
          QuickAddTokenKind.category => '${cat?.emoji ?? '#'} ${cat?.name ?? category}',
          QuickAddTokenKind.date => DateFormat('EEE, MMM d').format(r.due!),
          QuickAddTokenKind.time => DateFormat('HH:mm').format(r.due!),
          QuickAddTokenKind.recurrence => 'Repeats weekly',
        };
    IconData chipIcon(QuickAddToken t) => switch (t.kind) {
          QuickAddTokenKind.category => Icons.label_outline,
          QuickAddTokenKind.date => Icons.event,
          QuickAddTokenKind.time => Icons.schedule,
          QuickAddTokenKind.recurrence => Icons.repeat,
        };

    return Padding(
      padding: EdgeInsets.only(
        top: 20,
        left: 20,
        right: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _controller,
            autofocus: true,
            textInputAction: TextInputAction.done,
            decoration: const InputDecoration(
              labelText: 'New task',
              hintText: 'e.g. HW3 fri 5pm #school',
              border: OutlineInputBorder(),
            ),
            onSubmitted: (_) => _add(r, category),
          ),
          const SizedBox(height: 12),
          // ── Live preview ──
          AnimatedSize(
            duration: const Duration(milliseconds: 150),
            alignment: Alignment.topLeft,
            child: !hasInput
                ? Text(
                    'Type a title, then optionally a due date/time (fri, tmr, oct 28, 5pm), '
                    '#category, or "weekly". Wrap text in "quotes" to keep it as-is.',
                    style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurfaceVariant),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        r.title.isEmpty ? 'Title missing' : r.title,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: r.title.isEmpty ? theme.colorScheme.error : null,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final t in r.tokens)
                            InputChip(
                              avatar: Icon(chipIcon(t), size: 16),
                              label: Text(chipLabel(t)),
                              tooltip: 'From "${t.raw}"',
                              deleteButtonTooltipMessage: 'Keep "${t.raw}" in the title',
                              onDeleted: () => _keepAsText(t),
                            ),
                          if (r.category == null)
                            Chip(
                              avatar: const Icon(Icons.label_outline, size: 16),
                              label: Text('${cat?.emoji ?? ''} ${cat?.name ?? category} (default)'.trim()),
                              labelStyle: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Icon(
                            r.due == null ? Icons.warning_amber_rounded : Icons.alarm,
                            size: 16,
                            color: r.due == null ? Colors.orange : theme.colorScheme.primary,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              r.due == null
                                  ? 'No due date yet: add one (e.g. fri) or pick it in More options'
                                  : 'Due ${_formatDue(r.due!)}${r.hasExplicitTime ? '' : ' (default time)'}',
                              style: TextStyle(fontSize: 13, color: r.due == null ? Colors.orange : null),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
          ),
          const SizedBox(height: 12),
          // Side by side when they fit, stacked on very narrow screens
          OverflowBar(
            alignment: MainAxisAlignment.spaceBetween,
            overflowAlignment: OverflowBarAlignment.end,
            children: [
              TextButton(
                onPressed: () => _openFullForm(r, category),
                child: const Text('More options'),
              ),
              FilledButton.icon(
                onPressed: r.title.isEmpty ? null : () => _add(r, category),
                icon: Icon(r.due == null ? Icons.edit_calendar : Icons.add),
                label: Text(r.due == null ? 'Pick date' : 'Add'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
