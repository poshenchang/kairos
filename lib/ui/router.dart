// lib/ui/router.dart
//
// Application routing configuration using GoRouter.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:kairos/ui/screens/calendar/calendar_screen.dart';
import 'package:kairos/ui/screens/dashboard/dashboard_screen.dart';
import 'package:kairos/ui/screens/habits/habits_screen.dart';
import 'package:kairos/ui/screens/scheduler/scheduler_screen.dart';
import 'package:kairos/ui/screens/settings/settings_screen.dart';
import 'package:kairos/ui/screens/shell_screen.dart';
import 'package:kairos/ui/screens/tasks/tasks_screen.dart';

final _rootNavigatorKey = GlobalKey<NavigatorState>();

final appRouter = GoRouter(
  navigatorKey: _rootNavigatorKey,
  initialLocation: '/dashboard',
  routes: [
    StatefulShellRoute.indexedStack(
      builder: (context, state, navigationShell) {
        return ShellScreen(navigationShell: navigationShell);
      },
      branches: [
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/dashboard',
              builder: (context, state) => const DashboardScreen(),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/calendar',
              builder: (context, state) => const CalendarScreen(),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/tasks',
              builder: (context, state) => const TasksScreen(),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/habits',
              builder: (context, state) => const HabitsScreen(),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/scheduler',
              builder: (context, state) => const SchedulerScreen(),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/settings',
              builder: (context, state) => const SettingsScreen(),
            ),
          ],
        ),
      ],
    ),
  ],
);
