// lib/ui/widgets/habit_schedule_dialog.dart
//
// Dialog allowing the user to configure a default weekly schedule for a habit,
// supporting complex routines (e.g. everyday at 8am, or Monday night & Wednesday noon).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:kairos/data/database/app_database.dart';
import 'package:kairos/services/habit_schedule_service.dart';

class HabitScheduleDialog extends ConsumerStatefulWidget {
  final Habit habit;

  const HabitScheduleDialog({super.key, required this.habit});

  static Future<void> show(BuildContext context, Habit habit) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => HabitScheduleDialog(habit: habit),
    );
  }

  @override
  ConsumerState<HabitScheduleDialog> createState() => _HabitScheduleDialogState();
}

class _HabitScheduleDialogState extends ConsumerState<HabitScheduleDialog> {
  late List<HabitDefaultSlot> _slots;

  // New slot form state
  final Set<int> _selectedDays = {1}; // 1 = Mon, ..., 7 = Sun
  TimeOfDay _selectedTime = const TimeOfDay(hour: 20, minute: 0);
  int _durationMinutes = 60;

  @override
  void initState() {
    super.initState();
    final notifier = ref.read(habitScheduleProvider.notifier);
    _slots = List.from(notifier.getSlots(widget.habit.id));
    _durationMinutes = widget.habit.minSessionMinutes;
  }

  void _addSlotsForSelectedDays() {
    final newSlots = <HabitDefaultSlot>[];
    for (final day in _selectedDays) {
      // Check if slot already exists for that day & time
      final exists = _slots.any(
        (s) => s.weekday == day && s.hour == _selectedTime.hour && s.minute == _selectedTime.minute,
      );
      if (!exists) {
        newSlots.add(
          HabitDefaultSlot(
            weekday: day,
            hour: _selectedTime.hour,
            minute: _selectedTime.minute,
            durationMinutes: _durationMinutes,
          ),
        );
      }
    }

    if (newSlots.isNotEmpty) {
      setState(() {
        _slots.addAll(newSlots);
        _slots.sort((a, b) {
          final dayCompare = (a.weekday % 7).compareTo(b.weekday % 7);
          if (dayCompare != 0) return dayCompare;
          return (a.hour * 60 + a.minute).compareTo(b.hour * 60 + b.minute);
        });
      });
    }
  }

  void _applyPreset(List<int> weekdays, TimeOfDay time) {
    setState(() {
      _selectedDays.clear();
      _selectedDays.addAll(weekdays);
      _selectedTime = time;
    });
    _addSlotsForSelectedDays();
  }

  Future<void> _save() async {
    await ref.read(habitScheduleProvider.notifier).setSlots(widget.habit.id, _slots);
    if (mounted) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text('Saved ${_slots.length} default weekly slots for "${widget.habit.title}"'),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Padding(
      padding: EdgeInsets.only(
        top: 20,
        left: 20,
        right: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Title & Close
            Row(
              children: [
                const Icon(Icons.calendar_month, color: Colors.blueAccent),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Default Schedule: ${widget.habit.title}',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        'Automate weekly habit slots (e.g. Mon night & Wed noon)',
                        style: TextStyle(fontSize: 12, color: isDark ? Colors.grey[400] : Colors.grey[600]),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const Divider(height: 20),

            // Configured Slots List
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Weekly Schedule Slots (${_slots.length})',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
                if (_slots.isNotEmpty)
                  TextButton(
                    onPressed: () => setState(() => _slots.clear()),
                    style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                    child: const Text('Clear All', style: TextStyle(color: Colors.redAccent, fontSize: 12)),
                  ),
              ],
            ),
            const SizedBox(height: 6),

            if (_slots.isEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Text(
                  'No default slots set yet. Add time slots below or use a quick preset.',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                  textAlign: TextAlign.center,
                ),
              )
            else
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: _slots.asMap().entries.map((entry) {
                  final idx = entry.key;
                  final slot = entry.value;
                  return Chip(
                    visualDensity: VisualDensity.compact,
                    backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
                    side: BorderSide(color: theme.colorScheme.primary.withValues(alpha: 0.3)),
                    label: Text(
                      '${slot.weekdayName} ${slot.timeFormatted} (${slot.durationMinutes}m)',
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                    deleteIcon: const Icon(Icons.close, size: 14),
                    onDeleted: () => setState(() => _slots.removeAt(idx)),
                  );
                }).toList(),
              ),

            const SizedBox(height: 16),

            // Quick Presets
            const Text(
              'Quick Routine Presets',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                ActionChip(
                  visualDensity: VisualDensity.compact,
                  label: const Text('Everyday 8:00 AM', style: TextStyle(fontSize: 11)),
                  onPressed: () => _applyPreset([1, 2, 3, 4, 5, 6, 7], const TimeOfDay(hour: 8, minute: 0)),
                ),
                ActionChip(
                  visualDensity: VisualDensity.compact,
                  label: const Text('Everyday 9:00 PM', style: TextStyle(fontSize: 11)),
                  onPressed: () => _applyPreset([1, 2, 3, 4, 5, 6, 7], const TimeOfDay(hour: 21, minute: 0)),
                ),
                ActionChip(
                  visualDensity: VisualDensity.compact,
                  label: const Text('Mon/Wed/Fri 12:00 PM', style: TextStyle(fontSize: 11)),
                  onPressed: () => _applyPreset([1, 3, 5], const TimeOfDay(hour: 12, minute: 0)),
                ),
                ActionChip(
                  visualDensity: VisualDensity.compact,
                  label: const Text('Tue/Thu 7:00 PM', style: TextStyle(fontSize: 11)),
                  onPressed: () => _applyPreset([2, 4], const TimeOfDay(hour: 19, minute: 0)),
                ),
                ActionChip(
                  visualDensity: VisualDensity.compact,
                  label: const Text('Weekends 9:30 AM', style: TextStyle(fontSize: 11)),
                  onPressed: () => _applyPreset([6, 7], const TimeOfDay(hour: 9, minute: 30)),
                ),
              ],
            ),

            const SizedBox(height: 18),
            const Divider(height: 1),
            const SizedBox(height: 12),

            // Custom Slot Builder
            const Text(
              'Add Custom Weekly Slot',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            ),
            const SizedBox(height: 8),

            // Day Picker Chips
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildDaySelectChip(7, 'Sun'),
                _buildDaySelectChip(1, 'Mon'),
                _buildDaySelectChip(2, 'Tue'),
                _buildDaySelectChip(3, 'Wed'),
                _buildDaySelectChip(4, 'Thu'),
                _buildDaySelectChip(5, 'Fri'),
                _buildDaySelectChip(6, 'Sat'),
              ],
            ),
            const SizedBox(height: 10),

            // Time & Duration Pickers
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.access_time, size: 16),
                    label: Text(
                      DateFormat('h:mm a').format(DateTime(2026, 1, 1, _selectedTime.hour, _selectedTime.minute)),
                      style: const TextStyle(fontSize: 12),
                    ),
                    onPressed: () async {
                      final picked = await showTimePicker(
                        context: context,
                        initialTime: _selectedTime,
                      );
                      if (picked != null) setState(() => _selectedTime = picked);
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButtonFormField<int>(
                    value: _durationMinutes,
                    decoration: const InputDecoration(
                      contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: (<int>{10, 15, 20, 25, 30, 45, 60, 90, 120, _durationMinutes}
                        .toList()
                      ..sort())
                        .map((d) {
                        final label = d >= 60 && d % 60 == 0
                            ? '${d ~/ 60} hour session'
                            : (d >= 60 ? '${(d / 60).toStringAsFixed(1)} hour session' : '$d min session');
                        return DropdownMenuItem<int>(
                          value: d,
                          child: Text(label, style: const TextStyle(fontSize: 12)),
                        );
                      }).toList(),
                    onChanged: (val) {
                      if (val != null) setState(() => _durationMinutes = val);
                    },
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Add', style: TextStyle(fontSize: 12)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blueAccent,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                  onPressed: _selectedDays.isEmpty ? null : _addSlotsForSelectedDays,
                ),
              ],
            ),

            const SizedBox(height: 24),

            // Save Button
            SizedBox(
              width: double.infinity,
              height: 46,
              child: ElevatedButton(
                onPressed: _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: theme.colorScheme.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('Save Default Schedule', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDaySelectChip(int day, String label) {
    final isSelected = _selectedDays.contains(day);
    return FilterChip(
      label: Text(label, style: const TextStyle(fontSize: 11)),
      selected: isSelected,
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      onSelected: (val) {
        setState(() {
          if (val) {
            _selectedDays.add(day);
          } else {
            if (_selectedDays.length > 1) {
              _selectedDays.remove(day);
            }
          }
        });
      },
    );
  }
}

