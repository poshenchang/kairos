// lib/ui/screens/settings/settings_screen.dart
//
// Dedicated Settings Screen:
// - Full aesthetic palettes (Neon Cyber, Pastel, Nordic, Sunset, Oceanic) & Dark/Light mode
// - Push & Desktop Notifications toggle (Linux & iOS)
// - Academic Breaks & Holidays Manager (Disables weekly classes/routines)
// - Default Calendar View selector (Timetable vs List)
// - Supabase Cloud Sync & Account credentials
// - Calendar Data Management (Clear dummy/all events & tasks, reset categories)
// - Student Guide & Help

import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:kairos/data/database/app_database.dart';
import 'package:kairos/data/repositories/repository_providers.dart';
import 'package:kairos/services/notification_service.dart';
import 'package:kairos/services/platform_notification/notification_bridge.dart';
import 'package:kairos/services/settings_service.dart';
import 'package:kairos/services/supabase_sync_service.dart';
import 'package:kairos/services/timezone_service.dart';
import 'package:kairos/ui/providers/app_providers.dart';
import 'package:kairos/ui/theme/app_theme.dart';
import 'package:kairos/ui/theme/theme_provider.dart';
import 'package:kairos/ui/widgets/app_global_actions.dart';
import 'package:kairos/ui/widgets/help_guide_dialog.dart';

const _kSupabaseSqlSetupScript = '''
-- Kairos Database Schema for Supabase Cloud Sync

CREATE TABLE IF NOT EXISTS public.categories (
    sync_id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    slug TEXT NOT NULL,
    emoji TEXT DEFAULT '📌',
    color_hex TEXT DEFAULT '#4A90D9',
    is_system BOOLEAN DEFAULT FALSE,
    is_deleted BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.events (
    sync_id TEXT PRIMARY KEY,
    title TEXT NOT NULL,
    category TEXT DEFAULT 'other',
    event_type TEXT,
    start_time TIMESTAMPTZ NOT NULL,
    end_time TIMESTAMPTZ NOT NULL,
    is_recurring BOOLEAN DEFAULT FALSE,
    rrule TEXT,
    requires_prep BOOLEAN DEFAULT FALSE,
    prep_minutes INT,
    is_auto_scheduled BOOLEAN DEFAULT FALSE,
    auto_schedule_source TEXT,
    notes TEXT,
    is_deleted BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.tasks (
    sync_id TEXT PRIMARY KEY,
    title TEXT NOT NULL,
    category TEXT DEFAULT 'other',
    description TEXT,
    due_date TIMESTAMPTZ NOT NULL,
    estimated_minutes INT,
    priority INT DEFAULT 3,
    is_recurring BOOLEAN DEFAULT FALSE,
    rrule TEXT,
    is_completed BOOLEAN DEFAULT FALSE,
    completed_at TIMESTAMPTZ,
    is_deleted BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.subtasks (
    sync_id TEXT PRIMARY KEY,
    task_sync_id TEXT NOT NULL,
    title TEXT NOT NULL,
    is_completed BOOLEAN DEFAULT FALSE,
    is_deleted BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.habits (
    sync_id TEXT PRIMARY KEY,
    title TEXT NOT NULL,
    description TEXT,
    category TEXT DEFAULT 'other',
    frequency_per_week INT DEFAULT 1,
    preferred_time_of_day TEXT DEFAULT 'anytime',
    min_session_minutes INT DEFAULT 30,
    max_session_minutes INT DEFAULT 60,
    days_filter TEXT DEFAULT 'all',
    is_active BOOLEAN DEFAULT TRUE,
    default_schedule TEXT,
    is_deleted BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.habit_logs (
    sync_id TEXT PRIMARY KEY,
    habit_sync_id TEXT NOT NULL,
    completed_at TIMESTAMPTZ DEFAULT NOW(),
    duration_minutes INT DEFAULT 30,
    notes TEXT,
    is_deleted BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.holidays (
    sync_id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    group_name TEXT DEFAULT 'US Holidays',
    date TIMESTAMPTZ NOT NULL,
    end_date TIMESTAMPTZ,
    is_enabled BOOLEAN DEFAULT TRUE,
    is_deleted BOOLEAN DEFAULT FALSE,
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE public.habit_logs ADD COLUMN IF NOT EXISTS is_deleted BOOLEAN DEFAULT FALSE;
ALTER TABLE public.habits ADD COLUMN IF NOT EXISTS default_schedule TEXT;

-- Enable Row Level Security and allow read/write with Publishable Key
ALTER TABLE public.categories ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.events ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.tasks ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.subtasks ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.habits ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.habit_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.holidays ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Allow all on categories" ON public.categories;
CREATE POLICY "Allow all on categories" ON public.categories FOR ALL USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS "Allow all on events" ON public.events;
CREATE POLICY "Allow all on events" ON public.events FOR ALL USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS "Allow all on tasks" ON public.tasks;
CREATE POLICY "Allow all on tasks" ON public.tasks FOR ALL USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS "Allow all on subtasks" ON public.subtasks;
CREATE POLICY "Allow all on subtasks" ON public.subtasks FOR ALL USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS "Allow all on habits" ON public.habits;
CREATE POLICY "Allow all on habits" ON public.habits FOR ALL USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS "Allow all on habit_logs" ON public.habit_logs;
CREATE POLICY "Allow all on habit_logs" ON public.habit_logs FOR ALL USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS "Allow all on holidays" ON public.holidays;
CREATE POLICY "Allow all on holidays" ON public.holidays FOR ALL USING (true) WITH CHECK (true);

-- Grant API access to anon and authenticated roles
GRANT USAGE ON SCHEMA public TO anon, authenticated, service_role;
GRANT ALL ON ALL TABLES IN SCHEMA public TO anon, authenticated, service_role;
GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO anon, authenticated, service_role;
GRANT ALL ON ALL ROUTINES IN SCHEMA public TO anon, authenticated, service_role;

ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO anon, authenticated, service_role;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO anon, authenticated, service_role;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON ROUTINES TO anon, authenticated, service_role;

-- Refresh PostgREST schema cache
NOTIFY pgrst, 'reload schema';
''';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final _supabaseUrlController = TextEditingController();
  final _supabaseKeyController = TextEditingController();

  @override
  void initState() {
    super.initState();
    final settings = ref.read(settingsNotifierProvider);
    _supabaseUrlController.text = settings.supabaseUrl;
    _supabaseKeyController.text = settings.supabasePublishableKey;
  }

  @override
  void dispose() {
    _supabaseUrlController.dispose();
    _supabaseKeyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final currentMode = ref.watch(themeModeProvider);
    final currentPalette = ref.watch(themePaletteProvider);
    final settings = ref.watch(settingsNotifierProvider);
    final holidayDao = ref.watch(holidayDaoProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: const [
          AppGlobalActions(showAddButtons: false),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── 1. APPEARANCE & WHOLE PALETTES ─────────────────────────────
            _buildSectionHeader('Appearance & Aesthetics', Icons.palette_outlined),
            const SizedBox(height: 12),
            _buildThemeModeCard(context, ref, currentMode),
            const SizedBox(height: 16),
            _buildPalettesCard(context, ref, currentPalette),

            const SizedBox(height: 28),

            // ── 2. NOTIFICATIONS & CALENDAR PREFERENCES ─────────────────────
            _buildSectionHeader('Notifications & Calendar Preferences', Icons.notifications_active_outlined),
            const SizedBox(height: 12),
            _buildNotificationsAndPreferencesCard(context, ref, settings),

            const SizedBox(height: 28),

            // ── 3. TIMEZONE & REGIONAL CONFIGURATION ────────────────────────
            _buildSectionHeader('Timezone & Regional Schedule', Icons.schedule_outlined),
            const SizedBox(height: 12),
            _buildTimezoneCard(context, ref, settings),

            const SizedBox(height: 28),

            // ── 4. HOLIDAYS & ACADEMIC BREAKS ───────────────────────────────
            _buildSectionHeader('Academic Breaks & Holiday Blackouts', Icons.beach_access_outlined),
            const SizedBox(height: 12),
            _buildHolidaysCard(context, ref, holidayDao),

            const SizedBox(height: 28),

            // ── 4. CROSS-DEVICE SYNC & ACCOUNT (SUPABASE) ───────────────────
            _buildSectionHeader('Cloud Sync & Account (Supabase)', Icons.cloud_sync_outlined),
            const SizedBox(height: 12),
            _buildSupabaseSyncCard(context),

            const SizedBox(height: 28),

            // ── 5. CALENDAR DATA MANAGEMENT ─────────────────────────────────
            _buildSectionHeader('Calendar & Data Management', Icons.folder_delete_outlined),
            const SizedBox(height: 12),
            _buildDataManagementCard(context, ref),

            const SizedBox(height: 28),

            // ── 6. ABOUT & TUTORIAL ─────────────────────────────────────────
            _buildSectionHeader('About & Help', Icons.info_outline),
            const SizedBox(height: 12),
            _buildAboutCard(context),

            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            title,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
        ),
      ],
    );
  }

  Widget _buildThemeModeCard(BuildContext context, WidgetRef ref, ThemeMode mode) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Theme Mode',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            ),
            const SizedBox(height: 6),
            const Text(
              'Select between system default, pure dark, or clean light appearance.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 14),
            SegmentedButton<ThemeMode>(
              segments: const [
                ButtonSegment(
                  value: ThemeMode.system,
                  icon: Icon(Icons.brightness_auto),
                  label: Text('System'),
                ),
                ButtonSegment(
                  value: ThemeMode.light,
                  icon: Icon(Icons.light_mode),
                  label: Text('Light'),
                ),
                ButtonSegment(
                  value: ThemeMode.dark,
                  icon: Icon(Icons.dark_mode),
                  label: Text('Dark'),
                ),
              ],
              selected: {mode},
              onSelectionChanged: (newSelection) {
                ref.read(themeModeProvider.notifier).state = newSelection.first;
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPalettesCard(BuildContext context, WidgetRef ref, AppPaletteId activePalette) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Full Color Palettes',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            ),
            const SizedBox(height: 6),
            const Text(
              'Choose a cohesive aesthetic theme across the whole UI (backgrounds, surfaces, borders, and buttons).',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 16),
            Column(
              children: AppTheme.palettes.values.map((palette) {
                final isSelected = palette.id == activePalette;
                final theme = Theme.of(context);
                final isDark = theme.brightness == Brightness.dark;

                return InkWell(
                  onTap: () {
                    ref.read(themePaletteProvider.notifier).state = palette.id;
                  },
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isSelected
                            ? theme.colorScheme.primary
                            : (isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
                        width: isSelected ? 2 : 1,
                      ),
                      color: isSelected
                          ? theme.colorScheme.primary.withValues(alpha: isDark ? 0.15 : 0.08)
                          : Colors.transparent,
                    ),
                    child: Row(
                      children: [
                        Row(
                          children: palette.previewColors.map((color) {
                            return Container(
                              margin: const EdgeInsets.only(right: 4),
                              width: 18,
                              height: 18,
                              decoration: BoxDecoration(
                                color: color,
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white24, width: 1),
                              ),
                            );
                          }).toList(),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                palette.name,
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                  color: isSelected ? theme.colorScheme.primary : null,
                                ),
                              ),
                              Text(
                                palette.description,
                                style: const TextStyle(fontSize: 12, color: Colors.grey),
                              ),
                            ],
                          ),
                        ),
                        if (isSelected)
                          Icon(Icons.check_circle, color: theme.colorScheme.primary, size: 22)
                        else
                          const Icon(Icons.circle_outlined, color: Colors.grey, size: 22),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNotificationsAndPreferencesCard(
    BuildContext context,
    WidgetRef ref,
    SettingsState settings,
  ) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Push & Desktop Notifications', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              subtitle: const Text('Receive alerts for upcoming deadlines, exam prep sessions, and habits (Linux DBus & iOS).', style: TextStyle(fontSize: 12, color: Colors.grey)),
              value: settings.notificationsEnabled,
              onChanged: (val) async {
                ref.read(settingsNotifierProvider.notifier).setNotificationsEnabled(val);
                if (val) {
                  await NotificationService.instance.requestPermission();
                }
              },
            ),
            const Divider(height: 16),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Suggest Daily Habits During Free Time', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              subtitle: const Text('When free time (30+ min) is detected between 9am and 10pm, suggest an uncompleted and unscheduled daily habit randomly.', style: TextStyle(fontSize: 12, color: Colors.grey)),
              value: settings.suggestHabitsInFreeTime,
              onChanged: settings.notificationsEnabled
                  ? (val) {
                      ref.read(settingsNotifierProvider.notifier).setSuggestHabitsInFreeTime(val);
                    }
                  : null,
            ),

            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  icon: const Icon(Icons.security, size: 16),
                  label: const Text('Grant Browser / OS Permission'),
                  onPressed: () async {
                    final status = await NotificationService.instance.requestPermission();
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Notification permission: $status')),
                      );
                    }
                  },
                ),
                OutlinedButton.icon(
                  icon: const Icon(Icons.notifications_active, size: 16),
                  label: const Text('Send Test Notification'),
                  onPressed: () async {
                    await NotificationService.instance.showNotification(
                      id: 9999,
                      title: 'Kairos Notification Test',
                      body: 'Desktop & Push notifications are working perfectly on your device!',
                    );
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Test notification dispatched!')),
                      );
                    }
                  },
                ),
              ],
            ),
            const Divider(height: 24),
            const Text('Default Calendar Display', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            const SizedBox(height: 4),
            const Text('Choose your default view for the calendar tab (Timetable schedule grid is set as default).', style: TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 10),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(
                  value: 'timetable',
                  icon: Icon(Icons.calendar_view_week, size: 16),
                  label: Text('Timetable'),
                ),
                ButtonSegment(
                  value: 'list',
                  icon: Icon(Icons.view_agenda, size: 16),
                  label: Text('Agenda'),
                ),
                ButtonSegment(
                  value: 'all',
                  icon: Icon(Icons.category, size: 16),
                  label: Text('All Events'),
                ),
              ],
              selected: {settings.calendarViewMode == 'all' ? 'all' : (settings.calendarViewMode == 'list' ? 'list' : 'timetable')},
              onSelectionChanged: (val) {
                ref.read(settingsNotifierProvider.notifier).setCalendarViewMode(val.first);
              },
            ),
            const SizedBox(height: 14),
            const Row(
              children: [
                Icon(Icons.calendar_today, size: 16, color: Colors.blueAccent),
                SizedBox(width: 8),
                Text('Week Start: Sunday (Default configured)', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTimezoneCard(BuildContext context, WidgetRef ref, SettingsState settings) {
    final theme = Theme.of(context);
    final detectedLabel = TimezoneService.instance.getDetectedTimezoneLabel();
    final isAuto = settings.timezoneMode == 'auto';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.schedule, size: 20, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                const Text(
                  'Timezone & Schedule Alignment',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Kairos guarantees your schedule reflects your intended wall-clock hours across cloud devices. You can auto-detect system timezone or choose a fixed timezone.',
              style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 16),

            // Mode Selector: Auto vs Manual
            SegmentedButton<String>(
              segments: const [
                ButtonSegment<String>(
                  value: 'auto',
                  icon: Icon(Icons.my_location, size: 16),
                  label: Text('Auto-Detect'),
                ),
                ButtonSegment<String>(
                  value: 'manual',
                  icon: Icon(Icons.edit_location_alt_outlined, size: 16),
                  label: Text('Manual'),
                ),
              ],
              selected: {settings.timezoneMode},
              onSelectionChanged: (newSelection) {
                final mode = newSelection.first;
                ref.read(settingsNotifierProvider.notifier).setTimezoneConfig(
                      mode: mode,
                    );
                ref.invalidate(todayEventsProvider);
                ref.invalidate(selectedDateEventsProvider);
                ref.invalidate(smartSuggestionProvider);
              },
            ),
            const SizedBox(height: 16),

            if (isAuto) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle_outline, color: Colors.green, size: 20),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Active System Timezone:',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            detectedLabel,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: theme.colorScheme.primary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ] else ...[
              Text(
                'Select Timezone:',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: theme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: theme.colorScheme.outline),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<int>(
                    value: kCommonTimezones.any((tz) => tz.offsetMinutes == settings.manualTimezoneOffsetMinutes)
                        ? settings.manualTimezoneOffsetMinutes
                        : 480,
                    isExpanded: true,
                    items: kCommonTimezones.map((tz) {
                      return DropdownMenuItem<int>(
                        value: tz.offsetMinutes,
                        child: Text(
                          tz.label,
                          style: const TextStyle(fontSize: 13),
                          overflow: TextOverflow.ellipsis,
                        ),
                      );
                    }).toList(),
                    onChanged: (newOffset) {
                      if (newOffset == null) return;
                      final option = kCommonTimezones.firstWhere(
                        (tz) => tz.offsetMinutes == newOffset,
                        orElse: () => kCommonTimezones.first,
                      );
                      ref.read(settingsNotifierProvider.notifier).setTimezoneConfig(
                            mode: 'manual',
                            manualOffsetMinutes: option.offsetMinutes,
                            manualName: option.label,
                          );
                      ref.invalidate(todayEventsProvider);
                      ref.invalidate(selectedDateEventsProvider);
                      ref.invalidate(smartSuggestionProvider);
                    },
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildHolidaysCard(BuildContext context, WidgetRef ref, HolidayDao holidayDao) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                final isCompact = constraints.maxWidth < 480;
                const textColumn = Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Class & Routine Blackout Days',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                    SizedBox(height: 3),
                    Text(
                      'Weekly classes and routines are automatically disabled during active holidays & breaks.',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                );

                final addButton = FilledButton.icon(
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Add Break'),
                  onPressed: () => _showAddHolidayDialog(context, holidayDao),
                );

                if (isCompact) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      textColumn,
                      const SizedBox(height: 12),
                      addButton,
                    ],
                  );
                }

                return Row(
                  children: [
                    const Expanded(child: textColumn),
                    const SizedBox(width: 12),
                    addButton,
                  ],
                );
              },
            ),
            const SizedBox(height: 8),
            StreamBuilder<List<Holiday>>(
              stream: holidayDao.watchAllHolidays(),
              builder: (context, snapshot) {
                final holidays = snapshot.data ?? [];

                if (holidays.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16.0),
                    child: Center(
                      child: Text(
                        'No custom holidays registered. Tap "+ Add Break" above to register holiday blackout dates.',
                        style: TextStyle(fontSize: 13, color: Colors.grey),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  );
                }

                // Group holidays by groupName
                final groups = <String, List<Holiday>>{};
                for (final h in holidays) {
                  final g = h.groupName.isNotEmpty ? h.groupName : 'Custom';
                  groups.putIfAbsent(g, () => []).add(h);
                }

                const knownOrder = ['Taiwanese Holidays', 'US Holidays', 'Academic Breaks', 'Custom'];
                final sortedGroupNames = groups.keys.toList()
                  ..sort((a, b) {
                    final idxA = knownOrder.indexOf(a);
                    final idxB = knownOrder.indexOf(b);
                    if (idxA != -1 && idxB != -1) return idxA.compareTo(idxB);
                    if (idxA != -1) return -1;
                    if (idxB != -1) return 1;
                    return a.compareTo(b);
                  });

                return Column(
                  children: sortedGroupNames.map((groupName) {
                    final groupHolidays = groups[groupName]!;
                    final activeCount = groupHolidays.where((h) => h.isEnabled).length;
                    final allActive = activeCount == groupHolidays.length;

                    String groupEmoji;
                    if (groupName.contains('Taiwan')) {
                      groupEmoji = '🇹🇼';
                    } else if (groupName.contains('US')) {
                      groupEmoji = '🇺🇸';
                    } else if (groupName.contains('Academic')) {
                      groupEmoji = '🎓';
                    } else {
                      groupEmoji = '🌴';
                    }

                    return Container(
                      margin: const EdgeInsets.only(top: 8),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Theme.of(context).brightness == Brightness.dark
                              ? const Color(0xFF334155)
                              : const Color(0xFFE2E8F0),
                        ),
                      ),
                      child: ExpansionTile(
                        initiallyExpanded: groupName.contains('Taiwan') || groupName.contains('Academic'),
                        tilePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                        leading: Text(groupEmoji, style: const TextStyle(fontSize: 20)),
                        title: Text(
                          groupName,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                        subtitle: Text(
                          '$activeCount of ${groupHolidays.length} active',
                          style: TextStyle(
                            fontSize: 12,
                            color: activeCount > 0 ? Colors.green : Colors.grey,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Switch(
                              value: allActive,
                              onChanged: (val) async {
                                await holidayDao.toggleHolidayGroup(groupName, val);
                                if (val) {
                                  await ref.read(eventRepositoryProvider).autoCancelRecurringEventsForActiveHolidays();
                                }
                                ref.invalidate(selectedDateEventsProvider);
                                ref.invalidate(todayEventsProvider);
                                ref.invalidate(allEventsStreamProvider);
                                ref.read(supabaseSyncServiceProvider.notifier).syncNow();
                              },
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_sweep_outlined, size: 20, color: Colors.grey),
                              tooltip: 'Delete Group "$groupName"',
                              onPressed: () async {
                                final confirm = await showDialog<bool>(
                                  context: context,
                                  builder: (ctx) => AlertDialog(
                                    title: Text('Delete $groupName?'),
                                    content: Text('Are you sure you want to delete all ${groupHolidays.length} holidays in "$groupName"? This will be permanently synced to your cloud account.'),
                                    actions: [
                                      TextButton(
                                        onPressed: () => Navigator.of(ctx).pop(false),
                                        child: const Text('Cancel'),
                                      ),
                                      FilledButton(
                                        onPressed: () => Navigator.of(ctx).pop(true),
                                        style: FilledButton.styleFrom(backgroundColor: Colors.red),
                                        child: const Text('Delete Group'),
                                      ),
                                    ],
                                  ),
                                );
                                if (confirm == true) {
                                  await holidayDao.deleteHolidayGroup(groupName);
                                  ref.invalidate(selectedDateEventsProvider);
                                  ref.invalidate(todayEventsProvider);
                                  ref.invalidate(allEventsStreamProvider);
                                  ref.read(supabaseSyncServiceProvider.notifier).syncNow();
                                }
                              },
                            ),
                          ],
                        ),
                        children: [
                          const Divider(height: 1),
                          ...groupHolidays.map((h) {
                            final dateRange = h.endDate != null
                                ? '${DateFormat('MMM d').format(h.date)} – ${DateFormat('MMM d').format(h.endDate!)} (Annual)'
                                : '${DateFormat('MMMM d').format(h.date)} (Annual)';

                            return ListTile(
                              dense: true,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                              leading: Icon(
                                h.isEnabled ? Icons.event_busy : Icons.event_available,
                                color: h.isEnabled ? Colors.orangeAccent : Colors.grey,
                                size: 18,
                              ),
                              title: Text(h.name, style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13), softWrap: true),
                              subtitle: Text(dateRange, style: const TextStyle(fontSize: 11, color: Colors.grey), softWrap: true),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Transform.scale(
                                    scale: 0.8,
                                    child: Switch(
                                      value: h.isEnabled,
                                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                      onChanged: (val) async {
                                        await holidayDao.toggleHoliday(h.id, val);
                                        if (val) {
                                          await ref.read(eventRepositoryProvider).autoCancelRecurringEventsForActiveHolidays();
                                        }
                                        ref.invalidate(selectedDateEventsProvider);
                                        ref.invalidate(todayEventsProvider);
                                        ref.invalidate(allEventsStreamProvider);
                                        ref.read(supabaseSyncServiceProvider.notifier).syncNow();
                                      },
                                    ),
                                  ),
                                  PopupMenuButton<String>(
                                    icon: const Icon(Icons.more_vert, size: 18, color: Colors.grey),
                                    padding: EdgeInsets.zero,
                                    onSelected: (action) async {
                                      if (action == 'edit') {
                                        _showEditHolidayDialog(context, holidayDao, h);
                                      } else if (action == 'delete') {
                                        await holidayDao.deleteHoliday(h.id);
                                        ref.invalidate(selectedDateEventsProvider);
                                        ref.invalidate(todayEventsProvider);
                                        ref.invalidate(allEventsStreamProvider);
                                        ref.read(supabaseSyncServiceProvider.notifier).syncNow();
                                      }
                                    },
                                    itemBuilder: (ctx) => [
                                      const PopupMenuItem(
                                        value: 'edit',
                                        child: Row(
                                          children: [
                                            Icon(Icons.edit_outlined, size: 16, color: Colors.blueAccent),
                                            SizedBox(width: 8),
                                            Text('Edit Break'),
                                          ],
                                        ),
                                      ),
                                      const PopupMenuItem(
                                        value: 'delete',
                                        child: Row(
                                          children: [
                                            Icon(Icons.delete_outline, size: 16, color: Colors.redAccent),
                                            SizedBox(width: 8),
                                            Text('Delete Break'),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            );
                          }),
                        ],
                      ),
                    );
                  }).toList(),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showAddHolidayDialog(BuildContext context, HolidayDao holidayDao) {
    final nameCtrl = TextEditingController();
    DateTime startDate = DateTime.now();
    DateTime? endDate;
    String selectedGroup = 'Custom';

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          return AlertDialog(
            title: const Text('Add Academic Break / Holiday'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Holiday or Break Name',
                      hintText: 'e.g. Spring Break, Fall Reading Day',
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: selectedGroup,
                    decoration: const InputDecoration(
                      labelText: 'Holiday Group',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'Taiwanese Holidays', child: Text('🇹🇼 Taiwanese Holidays')),
                      DropdownMenuItem(value: 'US Holidays', child: Text('🇺🇸 US Holidays')),
                      DropdownMenuItem(value: 'Academic Breaks', child: Text('🎓 Academic Breaks')),
                      DropdownMenuItem(value: 'Custom', child: Text('🌴 Custom Breaks')),
                    ],
                    onChanged: (val) {
                      if (val != null) setDialogState(() => selectedGroup = val);
                    },
                  ),
                  const SizedBox(height: 12),
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.calendar_today, size: 20),
                    title: Text('Start Date: ${DateFormat('MMM d, yyyy').format(startDate)}'),
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: startDate,
                        firstDate: DateTime(2020),
                        lastDate: DateTime(2035),
                      );
                      if (picked != null) setDialogState(() => startDate = picked);
                    },
                  ),
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.event_repeat, size: 20),
                    title: Text(
                      endDate != null
                          ? 'End Date: ${DateFormat('MMM d, yyyy').format(endDate!)}'
                          : 'Single-day holiday (tap to make multi-day break)',
                    ),
                    trailing: endDate != null
                        ? IconButton(
                            icon: const Icon(Icons.close, size: 16),
                            onPressed: () => setDialogState(() => endDate = null),
                          )
                        : null,
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: endDate ?? startDate.add(const Duration(days: 4)),
                        firstDate: startDate,
                        lastDate: DateTime(2035),
                      );
                      if (picked != null) setDialogState(() => endDate = picked);
                    },
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () async {
                  if (nameCtrl.text.trim().isEmpty) return;
                  await holidayDao.insertHoliday(
                    HolidaysCompanion.insert(
                      name: nameCtrl.text.trim(),
                      groupName: Value(selectedGroup),
                      date: startDate,
                      endDate: endDate != null ? Value(endDate!) : const Value(null),
                      isEnabled: const Value(true),
                    ),
                  );
                  await ref.read(eventRepositoryProvider).autoCancelRecurringEventsForActiveHolidays();
                  ref.invalidate(selectedDateEventsProvider);
                  ref.invalidate(todayEventsProvider);
                  ref.invalidate(allEventsStreamProvider);
                  ref.read(supabaseSyncServiceProvider.notifier).syncNow();
                  if (dialogContext.mounted) {
                    Navigator.of(dialogContext).pop();
                  }
                },
                child: const Text('Add Holiday'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showEditHolidayDialog(BuildContext context, HolidayDao holidayDao, Holiday holiday) {
    final nameCtrl = TextEditingController(text: holiday.name);
    DateTime startDate = holiday.date;
    DateTime? endDate = holiday.endDate;
    String selectedGroup = holiday.groupName;

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          return AlertDialog(
            title: const Text('Edit Holiday / Academic Break'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Holiday or Break Name',
                      hintText: 'e.g. Spring Break, Fall Reading Day',
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: selectedGroup,
                    decoration: const InputDecoration(
                      labelText: 'Holiday Group',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'Taiwanese Holidays', child: Text('🇹🇼 Taiwanese Holidays')),
                      DropdownMenuItem(value: 'US Holidays', child: Text('🇺🇸 US Holidays')),
                      DropdownMenuItem(value: 'Academic Breaks', child: Text('🎓 Academic Breaks')),
                      DropdownMenuItem(value: 'Custom', child: Text('🌴 Custom Breaks')),
                    ],
                    onChanged: (val) {
                      if (val != null) setDialogState(() => selectedGroup = val);
                    },
                  ),
                  const SizedBox(height: 12),
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.calendar_today, size: 20),
                    title: Text('Start Date: ${DateFormat('MMMM d').format(startDate)} (Repeats annually)'),
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: startDate,
                        firstDate: DateTime(2020),
                        lastDate: DateTime(2035),
                      );
                      if (picked != null) setDialogState(() => startDate = picked);
                    },
                  ),
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.event_repeat, size: 20),
                    title: Text(
                      endDate != null
                          ? 'End Date: ${DateFormat('MMMM d').format(endDate!)}'
                          : 'Single-day holiday (tap to make multi-day break)',
                    ),
                    trailing: endDate != null
                        ? IconButton(
                            icon: const Icon(Icons.close, size: 16),
                            onPressed: () => setDialogState(() => endDate = null),
                          )
                        : null,
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: endDate ?? startDate.add(const Duration(days: 4)),
                        firstDate: startDate,
                        lastDate: DateTime(2035),
                      );
                      if (picked != null) setDialogState(() => endDate = picked);
                    },
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () async {
                  if (nameCtrl.text.trim().isEmpty) return;
                  await holidayDao.updateHoliday(
                    holiday.toCompanion(true).copyWith(
                      name: Value(nameCtrl.text.trim()),
                      groupName: Value(selectedGroup),
                      date: Value(startDate),
                      endDate: endDate != null ? Value(endDate!) : const Value(null),
                    ),
                  );
                  await ref.read(eventRepositoryProvider).autoCancelRecurringEventsForActiveHolidays();
                  ref.invalidate(selectedDateEventsProvider);
                  ref.invalidate(todayEventsProvider);
                  ref.invalidate(allEventsStreamProvider);
                  ref.read(supabaseSyncServiceProvider.notifier).syncNow();
                  if (dialogContext.mounted) {
                    Navigator.of(dialogContext).pop();
                  }
                },
                child: const Text('Save Changes'),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSupabaseSyncCard(BuildContext context) {
    final settings = ref.watch(settingsNotifierProvider);
    final syncState = ref.watch(supabaseSyncServiceProvider);
    final isConnected = settings.isSupabaseConfigured;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.bolt, size: 14, color: Colors.green),
                      SizedBox(width: 4),
                      Text(
                        '100% Free Supabase Backend',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.green,
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (syncState.status == SyncStatus.syncing) ...[
                      const SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      const SizedBox(width: 6),
                    ],
                    Text(
                      syncState.status == SyncStatus.syncing
                          ? 'Syncing...'
                          : isConnected
                              ? 'Connected'
                              : 'Offline Mode',
                      style: TextStyle(
                        fontSize: 12,
                        color: isConnected ? Colors.green : Colors.grey,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Sync Across Web, Desktop & Mobile',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                ),
                TextButton.icon(
                  icon: const Icon(Icons.code, size: 16),
                  label: const Text('SQL Setup', style: TextStyle(fontSize: 12)),
                  onPressed: () => _showSqlSetupDialog(context),
                ),
                IconButton(
                  icon: const Icon(Icons.help_outline, size: 18, color: Colors.blueAccent),
                  tooltip: 'How to obtain Supabase API keys',
                  onPressed: () => _showSupabaseInstructionsDialog(context),
                ),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              'Supabase provides a generous free PostgreSQL database (500 MB storage, real-time sync, 50,000 active users) with zero credit card required. Kairos remains 100% functional offline with Drift SQLite.',
              style: TextStyle(fontSize: 12, height: 1.45, color: Colors.grey),
            ),
            if (syncState.lastSyncTime != null) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.check_circle_outline, size: 14, color: Colors.green.shade600),
                  const SizedBox(width: 4),
                  Text(
                    'Last synced: ${DateFormat.jm().format(syncState.lastSyncTime!)} · ${DateFormat.MMMd().format(syncState.lastSyncTime!)}',
                    style: TextStyle(fontSize: 11, color: Colors.green.shade600),
                  ),
                ],
              ),
            ],
            if (syncState.errorMessage != null) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline, size: 16, color: Colors.red),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        syncState.errorMessage!,
                        style: const TextStyle(fontSize: 11, color: Colors.red),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 16),
            TextField(
              controller: _supabaseUrlController,
              decoration: const InputDecoration(
                labelText: 'Supabase Project URL',
                hintText: 'https://xyzcompany.supabase.co',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _supabaseKeyController,
              obscureText: true,
              decoration: InputDecoration(
                labelText: 'Supabase Publishable API Key',
                hintText: 'sb_publishable_... (or legacy anon key)',
                border: const OutlineInputBorder(),
                isDense: true,
                suffixIcon: IconButton(
                  icon: const Icon(Icons.help_outline, size: 18),
                  tooltip: 'How to obtain this key',
                  onPressed: () => _showSupabaseInstructionsDialog(context),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 12,
              runSpacing: 10,
              children: [
                ElevatedButton.icon(
                  icon: const Icon(Icons.cloud_done_outlined, size: 18),
                  label: const Text('Save & Connect Sync'),
                  onPressed: () async {
                    final url = _supabaseUrlController.text.trim();
                    final key = _supabaseKeyController.text.trim();
                    if (url.isEmpty || key.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Please enter your Supabase URL and Publishable Key from your Supabase dashboard.'),
                        ),
                      );
                      return;
                    }
                    await ref.read(settingsNotifierProvider.notifier).setSupabaseConfig(url, key);
                    final success = await ref.read(supabaseSyncServiceProvider.notifier).syncNow();
                    if (context.mounted) {
                      if (success) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Connected to Supabase! Sync completed successfully.'),
                          ),
                        );
                      } else {
                        final err = ref.read(supabaseSyncServiceProvider).errorMessage ?? 'Sync failed';
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            backgroundColor: Colors.red.shade800,
                            content: Text(err),
                            duration: const Duration(seconds: 6),
                          ),
                        );
                      }
                    }
                  },
                ),
                if (isConnected)
                  OutlinedButton.icon(
                    icon: syncState.status == SyncStatus.syncing
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.sync, size: 18),
                    label: const Text('Sync Now'),
                    onPressed: syncState.status == SyncStatus.syncing
                        ? null
                        : () async {
                            final success = await ref.read(supabaseSyncServiceProvider.notifier).syncNow();
                            if (context.mounted) {
                              if (success) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Cloud sync completed!')),
                                );
                              } else {
                                final err = ref.read(supabaseSyncServiceProvider).errorMessage ?? 'Sync failed';
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(backgroundColor: Colors.red.shade800, content: Text(err)),
                                );
                              }
                            }
                          },
                  ),
                if (isConnected)
                  OutlinedButton.icon(
                    icon: const Icon(Icons.cloud_download_outlined, size: 18, color: Colors.amberAccent),
                    label: const Text('Reset Local & Pull Cloud', style: TextStyle(color: Colors.amberAccent)),
                    onPressed: syncState.status == SyncStatus.syncing
                        ? null
                        : () async {
                            final confirm = await showDialog<bool>(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                title: const Row(
                                  children: [
                                    Icon(Icons.warning_amber_rounded, color: Colors.amberAccent),
                                    SizedBox(width: 8),
                                    Text('Reset Local Database?'),
                                  ],
                                ),
                                content: const Text(
                                  'This will wipe the local browser/device cache and pull fresh, authoritative data from Supabase.\n\n'
                                  'Use this to eliminate stale cache, duplicated items, or corrupted timetables without leaking bad data back to the server.',
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(ctx, false),
                                    child: const Text('Cancel'),
                                  ),
                                  ElevatedButton(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.amber.shade800,
                                      foregroundColor: Colors.white,
                                    ),
                                    onPressed: () => Navigator.pop(ctx, true),
                                    child: const Text('Wipe Local & Pull Fresh'),
                                  ),
                                ],
                              ),
                            );
                            if (confirm == true && context.mounted) {
                              try {
                                await ref.read(supabaseSyncServiceProvider.notifier).resetLocalDatabaseAndPull();
                                ref.invalidate(selectedDateEventsProvider);
                                ref.invalidate(todayEventsProvider);
                                ref.invalidate(allEventsStreamProvider);
                                ref.invalidate(dashboardTasksProvider);
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('Local database reset and refreshed cleanly from Supabase!')),
                                  );
                                }
                              } catch (e) {
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(backgroundColor: Colors.red.shade800, content: Text('Reset failed: $e')),
                                  );
                                }
                              }
                            }
                          },
                  ),
                OutlinedButton(
                  onPressed: () async {
                    await ref.read(settingsNotifierProvider.notifier).clearSupabaseConfig();
                    _supabaseUrlController.clear();
                    _supabaseKeyController.clear();
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Switched to local SQLite mode. Sync credentials removed.'),
                        ),
                      );
                    }
                  },
                  child: const Text('Use Local Only'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showSqlSetupDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.terminal, color: Colors.blueAccent),
            SizedBox(width: 8),
            Text('Supabase SQL Schema Setup'),
          ],
        ),
        content: SizedBox(
          width: 550,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Run this script once in your Supabase Dashboard → SQL Editor to create the tables required for cloud sync:',
                style: TextStyle(fontSize: 12, color: Theme.of(ctx).colorScheme.onSurface),
              ),
              const SizedBox(height: 10),
              Container(
                height: 220,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.grey.withValues(alpha: 0.3)),
                ),
                child: SingleChildScrollView(
                  child: SelectableText(
                    _kSupabaseSqlSetupScript,
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          ElevatedButton.icon(
            icon: const Icon(Icons.copy, size: 16),
            label: const Text('Copy SQL Script'),
            onPressed: () {
              Clipboard.setData(const ClipboardData(text: _kSupabaseSqlSetupScript));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('SQL setup script copied to clipboard!')),
              );
              Navigator.of(ctx).pop();
            },
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _showSupabaseInstructionsDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.key, color: Colors.blueAccent),
            SizedBox(width: 8),
            Text('How to Get Supabase API Keys', style: TextStyle(fontSize: 16)),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Supabase provides a free cloud PostgreSQL backend to sync Kairos across Linux, iOS, and other devices without a credit card.',
                style: TextStyle(
                  fontSize: 13,
                  height: 1.4,
                  color: Theme.of(ctx).colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Steps to obtain your keys:',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: Theme.of(ctx).colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 8),
              _buildInstructionStep(
                ctx,
                number: '1',
                title: 'Create a free project',
                description: 'Sign up or log in at https://supabase.com and create a new project.',
              ),
              _buildInstructionStep(
                ctx,
                number: '2',
                title: 'Open API settings',
                description: 'In your project dashboard, click the Settings (gear icon) in the bottom-left, then select "API Keys" (under Configuration).',
              ),
              _buildInstructionStep(
                ctx,
                number: '3',
                title: 'Copy Project URL',
                description: 'Copy the Project URL (e.g. https://xyzcompany.supabase.co) and paste it into the URL field.',
              ),
              _buildInstructionStep(
                ctx,
                number: '4',
                title: 'Copy Publishable Key',
                description: 'Under the "Publishable and secret API keys" tab, copy the Publishable API Key (starts with sb_publishable_..., or legacy anon key).',
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.amber.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.amber.withValues(alpha: 0.3)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.shield_outlined, size: 18, color: Colors.amber),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Important: Why Publishable Key?\nSupabase is deprecating legacy "anon" and "service_role" keys. The new Publishable key (sb_publishable_...) is safe to use in client apps because permissions are governed by Row Level Security (RLS).\n\nNEVER enter a Secret key (sb_secret_... or service_role) here.',
                        style: TextStyle(
                          fontSize: 11,
                          height: 1.35,
                          color: Theme.of(ctx).colorScheme.onSurface,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
  }

  Widget _buildInstructionStep(
    BuildContext context, {
    required String number,
    required String title,
    required String description,
  }) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 10,
            backgroundColor: Colors.blueAccent.withValues(alpha: 0.2),
            child: Text(
              number,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: Colors.blueAccent,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text.rich(
              TextSpan(
                style: TextStyle(
                  fontSize: 12,
                  color: theme.colorScheme.onSurface,
                  height: 1.3,
                ),
                children: [
                  TextSpan(
                    text: '$title: ',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  TextSpan(text: description),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDataManagementCard(BuildContext context, WidgetRef ref) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.cleaning_services_outlined, color: Colors.redAccent, size: 20),
                SizedBox(width: 8),
                Text(
                  'Clean Slate & Reset Options',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.redAccent),
                ),
              ],
            ),
            const SizedBox(height: 6),
            const Text(
              'Clear dummy sample events and tasks to start with a completely empty calendar, or restore initial system categories.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 10,
              children: [
                ElevatedButton.icon(
                  icon: const Icon(Icons.delete_sweep, size: 18),
                  label: const Text('Clear All Events & Tasks (Empty Calendar)'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red.shade700,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () async {
                    final confirm = await showDialog<bool>(
                      context: context,
                      builder: (dialogContext) => AlertDialog(
                        title: const Text('Clear All Events & Tasks?'),
                        content: const Text(
                          'This will permanently delete all existing events, assistant-scheduled blocks, tasks, and habit logs. Your categories will remain intact so you have a clean, fresh calendar.',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.of(dialogContext).pop(false),
                            child: const Text('Cancel'),
                          ),
                          ElevatedButton(
                            onPressed: () => Navigator.of(dialogContext).pop(true),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red,
                              foregroundColor: Colors.white,
                            ),
                            child: const Text('Clear Everything'),
                          ),
                        ],
                      ),
                    );

                    if (confirm == true) {
                      final db = ref.read(appDatabaseProvider);
                      final events = await db.eventDao.getAllEvents();
                      for (final e in events) {
                        await db.eventDao.deleteEvent(e.id);
                      }
                      await db.eventDao.deleteAutoScheduledEvents();

                      final tasks = await db.taskDao.getAllTasks();
                      for (final t in tasks) {
                        await db.taskDao.deleteTask(t.id);
                      }

                      final habits = await db.habitDao.getAllActiveHabits();
                      for (final h in habits) {
                        await db.habitDao.deleteHabit(h.id);
                      }

                      ref.invalidate(todayEventsProvider);
                      ref.invalidate(selectedDateEventsProvider);
                      ref.invalidate(dashboardTasksProvider);
                      ref.invalidate(incompleteTasksStreamProvider);
                      ref.invalidate(activeHabitsProvider);
                      ref.invalidate(weeklyHabitCompletionsProvider);

                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('All dummy/existing calendar items cleared! Calendar is now clean & empty.'),
                            backgroundColor: Colors.green,
                          ),
                        );
                      }
                    }
                  },
                ),
                OutlinedButton.icon(
                  icon: const Icon(Icons.restore, size: 18),
                  label: const Text('Reset Default Categories'),
                  onPressed: () async {
                    final db = ref.read(appDatabaseProvider);
                    final defaults = [
                      CategoriesCompanion.insert(
                        name: 'Schoolwork',
                        slug: 'schoolwork',
                        emoji: const Value('🎓'),
                        colorHex: const Value('#4A90D9'),
                        isSystem: const Value(true),
                      ),
                      CategoriesCompanion.insert(
                        name: 'Work',
                        slug: 'work',
                        emoji: const Value('💼'),
                        colorHex: const Value('#E67E22'),
                        isSystem: const Value(true),
                      ),
                      CategoriesCompanion.insert(
                        name: 'Research',
                        slug: 'research',
                        emoji: const Value('🔬'),
                        colorHex: const Value('#8E44AD'),
                        isSystem: const Value(true),
                      ),
                      CategoriesCompanion.insert(
                        name: 'Personal',
                        slug: 'personal',
                        emoji: const Value('🧘'),
                        colorHex: const Value('#27AE60'),
                        isSystem: const Value(true),
                      ),
                      CategoriesCompanion.insert(
                        name: 'Social',
                        slug: 'social',
                        emoji: const Value('🎉'),
                        colorHex: const Value('#EC4899'),
                        isSystem: const Value(true),
                      ),
                      CategoriesCompanion.insert(
                        name: 'Commute',
                        slug: 'transportation',
                        emoji: const Value('🚆'),
                        colorHex: const Value('#E74C3C'),
                        isSystem: const Value(true),
                      ),
                      CategoriesCompanion.insert(
                        name: 'Other',
                        slug: 'other',
                        emoji: const Value('🌐'),
                        colorHex: const Value('#7F8C8D'),
                        isSystem: const Value(true),
                      ),
                    ];
                    for (final cat in defaults) {
                      await db.categoryDao.insertCategory(cat);
                    }
                    ref.invalidate(allCategoriesProvider);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Default categories restored!')),
                      );
                    }
                  },
                ),
                if (kIsWeb)
                  OutlinedButton.icon(
                    icon: const Icon(Icons.refresh, size: 18, color: Colors.orangeAccent),
                    label: const Text('Clear Web App Cache & Reload', style: TextStyle(color: Colors.orangeAccent)),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Colors.orangeAccent),
                    ),
                    onPressed: () async {
                      final confirm = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('Clear Browser Cache & Reload?'),
                          content: const Text(
                            'This will unregister web service workers, wipe offline browser caches, and perform a hard reload to fetch the latest Kairos version.',
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.of(ctx).pop(false),
                              child: const Text('Cancel'),
                            ),
                            FilledButton(
                              onPressed: () => Navigator.of(ctx).pop(true),
                              child: const Text('Reload Now'),
                            ),
                          ],
                        ),
                      );
                      if (confirm == true) {
                        await hardReloadBrowser();
                      }
                    },
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAboutCard(BuildContext context) {
    return Card(
      child: ListTile(
        leading: const Icon(Icons.school, color: Colors.blueAccent, size: 30),
        title: const Text('Kairos Guide & Tutorial', style: TextStyle(fontWeight: FontWeight.bold)),
        subtitle: const Text('Review tips for Schedule Assistant, frequency habits, and transit blocks'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => HelpGuideDialog.show(context),
      ),
    );
  }
}
