// lib/ui/screens/calendar/widgets/all_events_view.dart
//
// Directory panel showing all calendar events, default grouped by category,
// with search and filter capabilities and direct Edit/Delete actions.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:kairos/data/database/app_database.dart';
import 'package:kairos/data/repositories/event_repository.dart';
import 'package:kairos/data/repositories/repository_providers.dart';
import 'package:kairos/ui/providers/app_providers.dart';
import 'package:kairos/ui/widgets/add_event_dialog.dart';
import 'package:kairos/ui/widgets/category_badge.dart';
import 'package:kairos/ui/widgets/edit_event_dialog.dart';

class AllEventsView extends ConsumerStatefulWidget {
  const AllEventsView({super.key});

  @override
  ConsumerState<AllEventsView> createState() => _AllEventsViewState();
}

class _AllEventsViewState extends ConsumerState<AllEventsView> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  String? _selectedCategoryFilter;
  bool _groupByCategory = true;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final allEventsAsync = ref.watch(allEventsStreamProvider);
    final categoriesAsync = ref.watch(allCategoriesProvider);
    final categories = categoriesAsync.value ?? [];
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Column(
      children: [
        // ── Search & Filter Bar ─────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Search events by name or location...',
                    prefixIcon: const Icon(Icons.search, size: 20),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 18),
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _searchQuery = '');
                            },
                          )
                        : null,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onChanged: (val) => setState(() => _searchQuery = val.trim().toLowerCase()),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.outlined(
                icon: Icon(
                  _groupByCategory ? Icons.category : Icons.calendar_month,
                  color: _groupByCategory ? theme.colorScheme.primary : Colors.grey,
                ),
                tooltip: _groupByCategory ? 'Grouped by Category' : 'Sorted by Date',
                onPressed: () => setState(() => _groupByCategory = !_groupByCategory),
              ),
            ],
          ),
        ),

        // ── Category Filter Chips ───────────────────────────────────────────
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Row(
            children: [
              ChoiceChip(
                label: const Text('All Categories'),
                selected: _selectedCategoryFilter == null,
                onSelected: (_) => setState(() => _selectedCategoryFilter = null),
              ),
              const SizedBox(width: 6),
              ...categories.map((c) {
                return Padding(
                  padding: const EdgeInsets.only(right: 6.0),
                  child: ChoiceChip(
                    label: Text('${c.emoji} ${c.name}'),
                    selected: _selectedCategoryFilter == c.slug,
                    onSelected: (val) {
                      setState(() => _selectedCategoryFilter = val ? c.slug : null);
                    },
                  ),
                );
              }),
            ],
          ),
        ),

        const Divider(height: 1),

        // ── Events List ─────────────────────────────────────────────────────
        Expanded(
          child: allEventsAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (err, _) => Center(child: Text('Error loading events: $err')),
            data: (allEvents) {
              var filtered = allEvents;

              // Apply category filter
              if (_selectedCategoryFilter != null) {
                filtered = filtered
                    .where((e) => e.category.toLowerCase() == _selectedCategoryFilter!.toLowerCase())
                    .toList();
              }

              // Apply search query
              if (_searchQuery.isNotEmpty) {
                filtered = filtered.where((e) {
                  final titleMatch = e.title.toLowerCase().contains(_searchQuery);
                  final notesMatch = e.notes?.toLowerCase().contains(_searchQuery) ?? false;
                  final categoryMatch = e.category.toLowerCase().contains(_searchQuery);
                  return titleMatch || notesMatch || categoryMatch;
                }).toList();
              }

              if (filtered.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.event_busy, size: 52, color: Colors.grey),
                      const SizedBox(height: 12),
                      Text(
                        _searchQuery.isNotEmpty || _selectedCategoryFilter != null
                            ? 'No events match your search or filter.'
                            : 'No events created yet.',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Create recurring classes, meetings, or sessions below.',
                        style: TextStyle(color: Colors.grey, fontSize: 13),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        icon: const Icon(Icons.add),
                        label: const Text('Add Event'),
                        onPressed: () => AddEventDialog.show(context),
                      ),
                    ],
                  ),
                );
              }

              if (!_groupByCategory) {
                // Flat sorted list by start time
                return ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  itemCount: filtered.length,
                  itemBuilder: (context, index) {
                    final event = filtered[index];
                    return _buildEventTile(context, event, isDark, categories);
                  },
                );
              }

              // Grouped by Category
              final groups = <String, List<Event>>{};
              for (final event in filtered) {
                final catKey = event.category.toLowerCase();
                groups.putIfAbsent(catKey, () => []).add(event);
              }

              // Sort categories: Social before Other, Other always comes last
              const preferredOrder = [
                'schoolwork',
                'work',
                'research',
                'personal',
                'social',
                'transportation',
                'commute',
              ];

              final sortedCategoryKeys = groups.keys.toList()
                ..sort((a, b) {
                  final slugA = a.toLowerCase();
                  final slugB = b.toLowerCase();
                  if (slugA == 'other' && slugB != 'other') return 1;
                  if (slugB == 'other' && slugA != 'other') return -1;
                  final idxA = preferredOrder.indexOf(slugA);
                  final idxB = preferredOrder.indexOf(slugB);
                  if (idxA != -1 && idxB != -1) return idxA.compareTo(idxB);
                  if (idxA != -1) return -1;
                  if (idxB != -1) return 1;
                  return slugA.compareTo(slugB);
                });

              return ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                itemCount: sortedCategoryKeys.length,
                itemBuilder: (context, catIndex) {
                  final catSlug = sortedCategoryKeys[catIndex];
                  final eventsInCat = groups[catSlug]!
                    ..sort((a, b) {
                      // Hard events (!isAutoScheduled) first, soft (isAutoScheduled) later
                      if (!a.isAutoScheduled && b.isAutoScheduled) return -1;
                      if (a.isAutoScheduled && !b.isAutoScheduled) return 1;
                      return a.startTime.compareTo(b.startTime);
                    });

                  // Category meta
                  Category? catObj;
                  for (final c in categories) {
                    if (c.slug.toLowerCase() == catSlug) {
                      catObj = c;
                      break;
                    }
                  }

                  final catName = catObj?.name ?? (catSlug.isNotEmpty ? '${catSlug[0].toUpperCase()}${catSlug.substring(1)}' : 'Other');
                  final catEmoji = catObj?.emoji ?? '📌';

                  return Card(
                    margin: const EdgeInsets.only(bottom: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: BorderSide(
                        color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(12.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Category Header
                          Row(
                            children: [
                              Text(catEmoji, style: const TextStyle(fontSize: 18)),
                              const SizedBox(width: 8),
                              Text(
                                catName,
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                              ),
                              const Spacer(),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.primary.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  '${eventsInCat.length} ${eventsInCat.length == 1 ? 'event' : 'events'}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: theme.colorScheme.primary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const Divider(height: 18),
                          // Events inside category (Hard events first, soft events later)
                          ...eventsInCat.map((event) => _buildEventTile(context, event, isDark, categories)),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildEventTile(BuildContext context, Event event, bool isDark, List<Category> categories) {
    final start = event.startTime.toLocal();
    final end = event.endTime.toLocal();
    final isReminder = event.eventType == 'reminder';

    String timeScheduleText;
    if (isReminder) {
      if (event.isRecurring) {
        final isDaily = event.rrule?.contains('FREQ=DAILY') ?? false;
        if (isDaily) {
          timeScheduleText = 'Every Day • Reminder at ${DateFormat('h:mm a').format(start)}';
        } else {
          timeScheduleText = 'Repeats Weekly • ${DateFormat('EEEE').format(start)} at ${DateFormat('h:mm a').format(start)}';
        }
      } else {
        timeScheduleText = '${DateFormat('EEE, MMM d, yyyy').format(start)} • Reminder at ${DateFormat('h:mm a').format(start)}';
      }
    } else if (event.isRecurring) {
      final isDaily = event.rrule?.contains('FREQ=DAILY') ?? false;
      if (isDaily) {
        timeScheduleText = 'Every Day • ${DateFormat('h:mm a').format(start)} – ${DateFormat('h:mm a').format(end)}';
      } else {
        timeScheduleText = 'Repeats Weekly • ${DateFormat('EEEE').format(start)} ${DateFormat('h:mm a').format(start)} – ${DateFormat('h:mm a').format(end)}';
      }
    } else {
      timeScheduleText = '${DateFormat('EEE, MMM d, yyyy').format(start)} • ${DateFormat('h:mm a').format(start)} – ${DateFormat('h:mm a').format(end)}';
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: event.isAutoScheduled
              ? Colors.purple.withValues(alpha: 0.3)
              : (isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: isReminder
                ? Colors.amber.withValues(alpha: 0.15)
                : _getCategoryColor(event.category).withValues(alpha: 0.15),
            child: isReminder
                ? const Icon(Icons.notifications_active, color: Colors.amber, size: 18)
                : Text(
                    _getCategoryEmoji(event.category, categories),
                    style: const TextStyle(fontSize: 16),
                  ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        event.title,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                    ),
                    if (isReminder)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.amber.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text(
                          'Reminder',
                          style: TextStyle(fontSize: 10, color: Colors.amber, fontWeight: FontWeight.bold),
                        ),
                      )
                    else if (event.isAutoScheduled)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.purple.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text(
                          'Scheduled',
                          style: TextStyle(fontSize: 10, color: Colors.purple, fontWeight: FontWeight.bold),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  timeScheduleText,
                  style: TextStyle(fontSize: 12, color: isDark ? Colors.white70 : Colors.black87),
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    CategoryBadge(categorySlugOrName: event.category, compact: true),
                    if (isReminder)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.amber.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.notifications_active, size: 10, color: Colors.amber),
                            SizedBox(width: 3),
                            Text('Reminder', style: TextStyle(fontSize: 10, color: Colors.amber, fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                    if (event.isRecurring)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.blue.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.repeat, size: 10, color: Colors.blueAccent),
                            SizedBox(width: 3),
                            Text('Repeating', style: TextStyle(fontSize: 10, color: Colors.blueAccent, fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                    if (event.requiresPrep)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.purple.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.flash_on, size: 10, color: Colors.purple),
                            const SizedBox(width: 3),
                            Text(
                              (event.prepMinutes ?? 60) >= 60 && (event.prepMinutes ?? 60) % 60 == 0
                                  ? '${(event.prepMinutes ?? 60) ~/ 60}h prep'
                                  : '${event.prepMinutes ?? 60}m prep',
                              style: const TextStyle(fontSize: 10, color: Colors.purple, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
                if (event.isRecurring) ...[
                  Builder(
                    builder: (context) {
                      final cancelled = EventRepository.getCancelledDates(event.rrule);
                      if (cancelled.isEmpty) return const SizedBox.shrink();

                      return Container(
                        margin: const EdgeInsets.only(top: 6),
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.orange.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.orange.withValues(alpha: 0.25)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.event_busy, size: 13, color: Colors.orange),
                                const SizedBox(width: 4),
                                Text(
                                  'Temporarily cancelled (${cancelled.length}):',
                                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.orange),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Wrap(
                              spacing: 6,
                              runSpacing: 4,
                              children: cancelled.map((dStr) {
                                DateTime? parsed;
                                try {
                                  final p = dStr.split('-');
                                  parsed = DateTime(int.parse(p[0]), int.parse(p[1]), int.parse(p[2]));
                                } catch (_) {}
                                final label = parsed != null ? DateFormat('MMM d, yyyy').format(parsed) : dStr;
                                return ActionChip(
                                  avatar: const Icon(Icons.restore, size: 14, color: Colors.green),
                                  label: Text('Restore $label', style: const TextStyle(fontSize: 11)),
                                  visualDensity: VisualDensity.compact,
                                  padding: const EdgeInsets.symmetric(horizontal: 4),
                                  onPressed: () async {
                                    await ref.read(eventRepositoryProvider).restoreRecurringOccurrence(event.id, dStr);
                                    ref.invalidate(allEventsStreamProvider);
                                    ref.invalidate(selectedDateEventsProvider);
                                    ref.invalidate(todayEventsProvider);
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                          content: Text('Restored "$label" occurrence for "${event.title}"!'),
                                          behavior: SnackBarBehavior.floating,
                                        ),
                                      );
                                    }
                                  },
                                );
                              }).toList(),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ],
                if (event.notes != null && event.notes!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4.0),
                    child: Text(
                      event.notes!,
                      style: const TextStyle(fontSize: 11, color: Colors.grey),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
            ),
          ),
          Column(
            children: [
              IconButton(
                icon: const Icon(Icons.edit_outlined, size: 18, color: Colors.blueGrey),
                tooltip: 'Edit Event',
                onPressed: () => EditEventDialog.show(context, event),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline, size: 18, color: Colors.grey),
                tooltip: 'Delete Event',
                onPressed: () async {
                  await ref.read(eventDaoProvider).deleteEvent(event.id);
                  ref.invalidate(allEventsStreamProvider);
                  ref.invalidate(selectedDateEventsProvider);
                  ref.invalidate(todayEventsProvider);
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _getCategoryEmoji(String categorySlugOrName, List<Category> categories) {
    for (final c in categories) {
      if (c.slug.toLowerCase() == categorySlugOrName.toLowerCase() ||
          c.name.toLowerCase() == categorySlugOrName.toLowerCase()) {
        if (c.emoji.isNotEmpty) return c.emoji;
      }
    }
    return switch (categorySlugOrName.toLowerCase()) {
      'schoolwork' => '🎓',
      'work' => '💼',
      'research' => '🔬',
      'personal' => '🧘',
      'social' => '🎉',
      'commute' || 'transportation' => '🚆',
      _ => '🌐',
    };
  }

  Color _getCategoryColor(String category) {
    return switch (category.toLowerCase()) {
      'schoolwork' => const Color(0xFF4A90D9),
      'work' => const Color(0xFFE67E22),
      'research' => const Color(0xFF8E44AD),
      'personal' => const Color(0xFF27AE60),
      'social' => const Color(0xFFEC4899),
      'commute' || 'transportation' => const Color(0xFFE74C3C),
      _ => const Color(0xFF3B82F6),
    };
  }
}

