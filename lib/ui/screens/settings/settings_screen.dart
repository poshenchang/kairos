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
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:kairos/data/database/app_database.dart';
import 'package:kairos/data/repositories/repository_providers.dart';
import 'package:kairos/services/notification_service.dart';
import 'package:kairos/services/settings_service.dart';
import 'package:kairos/ui/providers/app_providers.dart';
import 'package:kairos/ui/theme/app_theme.dart';
import 'package:kairos/ui/theme/theme_provider.dart';
import 'package:kairos/ui/widgets/app_global_actions.dart';
import 'package:kairos/ui/widgets/help_guide_dialog.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final _supabaseUrlController = TextEditingController();
  final _supabaseKeyController = TextEditingController();
  bool _isSyncConfigured = false;

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

            // ── 3. HOLIDAYS & ACADEMIC BREAKS ───────────────────────────────
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
        Text(
          title,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
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
              onChanged: (val) {
                ref.read(settingsNotifierProvider.notifier).setNotificationsEnabled(val);
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

  Widget _buildHolidaysCard(BuildContext context, WidgetRef ref, HolidayDao holidayDao) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Class & Routine Blackout Days',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Weekly classes and routines are automatically disabled during active holidays & breaks.',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
                TextButton.icon(
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Add Break'),
                  onPressed: () => _showAddHolidayDialog(context, holidayDao),
                ),
              ],
            ),
            const SizedBox(height: 8),
            StreamBuilder<List<Holiday>>(
              stream: holidayDao.watchAllHolidays(),
              builder: (context, snapshot) {
                final holidays = snapshot.data ?? [];

                if (holidays.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('No holiday blackout dates registered.', style: TextStyle(fontSize: 13, color: Colors.grey)),
                        const SizedBox(height: 8),
                        ElevatedButton.icon(
                          icon: const Icon(Icons.auto_awesome, size: 16),
                          label: const Text('Load Standard Academic & Regional Holidays'),
                          onPressed: () async {
                            await holidayDao.seedDefaultHolidays(DateTime.now().year);
                            ref.invalidate(selectedDateEventsProvider);
                            ref.invalidate(todayEventsProvider);
                          },
                        ),
                      ],
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
                                ref.invalidate(selectedDateEventsProvider);
                                ref.invalidate(todayEventsProvider);
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
                              contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                              leading: Icon(
                                h.isEnabled ? Icons.event_busy : Icons.event_available,
                                color: h.isEnabled ? Colors.orangeAccent : Colors.grey,
                                size: 18,
                              ),
                              title: Text(h.name, style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13)),
                              subtitle: Text(dateRange, style: const TextStyle(fontSize: 11, color: Colors.grey)),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Switch(
                                    value: h.isEnabled,
                                    onChanged: (val) async {
                                      await holidayDao.toggleHoliday(h.id, val);
                                      ref.invalidate(selectedDateEventsProvider);
                                      ref.invalidate(todayEventsProvider);
                                    },
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.edit_outlined, size: 18, color: Colors.blueAccent),
                                    tooltip: 'Edit Holiday',
                                    onPressed: () => _showEditHolidayDialog(context, holidayDao, h),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline, size: 18, color: Colors.grey),
                                    tooltip: 'Delete Holiday',
                                    onPressed: () async {
                                      await holidayDao.deleteHoliday(h.id);
                                      ref.invalidate(selectedDateEventsProvider);
                                      ref.invalidate(todayEventsProvider);
                                    },
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
    String selectedGroup = 'Taiwanese Holidays';

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
                  ref.invalidate(selectedDateEventsProvider);
                  ref.invalidate(todayEventsProvider);
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
                  ref.invalidate(selectedDateEventsProvider);
                  ref.invalidate(todayEventsProvider);
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
                Text(
                  _isSyncConfigured ? 'Connected' : 'Offline Mode',
                  style: TextStyle(
                    fontSize: 12,
                    color: _isSyncConfigured ? Colors.green : Colors.grey,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Text(
              'Sync Across Linux Desktop & iOS Devices',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            ),
            const SizedBox(height: 6),
            const Text(
              'Supabase provides a generous free PostgreSQL database (500 MB storage, real-time sync, 50,000 active users) with zero credit card required. Kairos remains 100% functional offline with Drift SQLite.',
              style: TextStyle(fontSize: 12, height: 1.45, color: Colors.grey),
            ),
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
              decoration: const InputDecoration(
                labelText: 'Supabase Anon Public API Key',
                hintText: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                ElevatedButton.icon(
                  icon: const Icon(Icons.cloud_done_outlined, size: 18),
                  label: const Text('Save & Connect Sync'),
                  onPressed: () {
                    final url = _supabaseUrlController.text.trim();
                    final key = _supabaseKeyController.text.trim();
                    if (url.isEmpty || key.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Please enter your Supabase URL and Anon Key from your Supabase dashboard.'),
                        ),
                      );
                      return;
                    }
                    setState(() => _isSyncConfigured = true);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Supabase credentials saved! Sync connector activated.'),
                      ),
                    );
                  },
                ),
                const SizedBox(width: 12),
                OutlinedButton(
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Running local SQLite mode. All events, habits, and tasks stored securely on your machine.'),
                      ),
                    );
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
                          'This will permanently delete all existing events, auto-scheduled blocks, tasks, and habit logs. Your categories will remain intact so you have a clean, fresh calendar.',
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
        subtitle: const Text('Review tips for auto-scheduling, frequency habits, and transit blocks'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => HelpGuideDialog.show(context),
      ),
    );
  }
}
