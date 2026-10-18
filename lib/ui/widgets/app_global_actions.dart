// lib/ui/widgets/app_global_actions.dart
//
// Uniform top-right action buttons across all Kairos screens:
// - Auto-Scheduler run trigger
// - Dark/Light mode toggle
// - Add Task
// - Add Event
// - Help & Student Guide
// - Settings

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:kairos/core/scheduler/scheduler_provider.dart';
import 'package:kairos/ui/theme/theme_provider.dart';
import 'package:kairos/ui/widgets/add_event_dialog.dart';
import 'package:kairos/ui/widgets/add_task_dialog.dart';
import 'package:kairos/ui/widgets/help_guide_dialog.dart';

class AppGlobalActions extends ConsumerWidget {
  final bool showScheduler;
  final bool showAddButtons;

  const AppGlobalActions({
    super.key,
    this.showScheduler = true,
    this.showAddButtons = true,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final schedulerState = ref.watch(schedulerNotifierProvider);
    final themeMode = ref.watch(themeModeProvider);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showScheduler)
          IconButton(
            tooltip: 'Run Auto-Scheduler Now',
            icon: schedulerState.isLoading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.auto_awesome, color: Colors.blueAccent),
            onPressed: schedulerState.isLoading
                ? null
                : () async {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Auto-scheduler running... optimizing free time!'),
                        duration: Duration(seconds: 2),
                      ),
                    );
                    await ref.read(schedulerNotifierProvider.notifier).run();
                  },
          ),
        IconButton(
          tooltip: 'Toggle Dark / Light Mode',
          icon: Icon(
            themeMode == ThemeMode.dark ? Icons.light_mode : Icons.dark_mode_outlined,
          ),
          onPressed: () {
            final current = ref.read(themeModeProvider);
            final isDark = current == ThemeMode.dark ||
                (current == ThemeMode.system &&
                    MediaQuery.of(context).platformBrightness == Brightness.dark);
            ref.read(themeModeProvider.notifier).state =
                isDark ? ThemeMode.light : ThemeMode.dark;
          },
        ),
        if (showAddButtons) ...[
          IconButton(
            tooltip: 'Add Task / Deadline',
            icon: const Icon(Icons.add_task),
            onPressed: () => AddTaskDialog.show(context),
          ),
          IconButton(
            tooltip: 'Add Calendar Event',
            icon: const Icon(Icons.add_circle_outline),
            onPressed: () => AddEventDialog.show(context),
          ),
        ],
        IconButton(
          tooltip: 'Student Guide & Tutorial',
          icon: const Icon(Icons.help_outline),
          onPressed: () => HelpGuideDialog.show(context),
        ),
        IconButton(
          tooltip: 'Settings & Appearance',
          icon: const Icon(Icons.settings_outlined),
          onPressed: () => context.go('/settings'),
        ),
      ],
    );
  }
}

