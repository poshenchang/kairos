// lib/ui/widgets/help_guide_dialog.dart
//
// Interactive tutorial and feature guide for students (Dark & Light mode adaptive).

import 'package:flutter/material.dart';

class HelpGuideDialog extends StatelessWidget {
  const HelpGuideDialog({super.key});

  static void show(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => const HelpGuideDialog(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Dialog(
      backgroundColor: theme.cardTheme.color ?? (isDark ? const Color(0xFF1E293B) : Colors.white),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(
          color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
        ),
      ),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 580, maxHeight: 680),
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            Row(
              children: [
                Icon(Icons.school, color: theme.colorScheme.primary, size: 28),
                const SizedBox(width: 12),
                Text(
                  'Kairos Student Guide',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : const Color(0xFF0F172A),
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Master your time, eliminate decision fatigue, and automate your schedule.',
              style: TextStyle(
                color: isDark ? Colors.white60 : Colors.black54,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: ListView(
                children: [
                  _buildSection(
                    context: context,
                    icon: Icons.event,
                    iconColor: Colors.blueAccent,
                    title: '1. Event Types & Weekly Routines',
                    description:
                        '• Classes & Gym: Mark events with "Repeats Weekly" to generate weekly slots automatically.\n'
                        '• Commute / Transportation: Mark transit between hometown and university. Kairos marks transit blocks as productive time and suggests reading or review.\n'
                        '• One-Offs: Quick meetings, interviews, and doctor appointments.',
                  ),
                  const SizedBox(height: 16),
                  _buildSection(
                    context: context,
                    icon: Icons.auto_awesome,
                    iconColor: Colors.purpleAccent,
                    title: '2. Auto-Preparation Blocks',
                    description:
                        '• When scheduling an Exam, Interview, or Presentation, toggle "Requires Preparation Block" and choose desired prep time (e.g. 90m).\n'
                        '• The Auto-Scheduler will find open gaps in the days leading up to the event and insert study/prep blocks automatically!',
                  ),
                  const SizedBox(height: 16),
                  _buildSection(
                    context: context,
                    icon: Icons.task_alt,
                    iconColor: Colors.deepOrangeAccent,
                    title: '3. Tasks & Deadlines (Smart Dashboard)',
                    description:
                        '• One-Off Deadlines: Essays, report submissions, applications.\n'
                        '• Weekly Problem Sets: When marked as recurring, the dashboard ONLY shows the next upcoming instance, keeping your view clean and focused.\n'
                        '• Visual Urgency: Red (Overdue), Orange (Due in <24h), Amber (Due in <72h).',
                  ),
                  const SizedBox(height: 16),
                  _buildSection(
                    context: context,
                    icon: Icons.repeat,
                    iconColor: Colors.greenAccent,
                    title: '4. Frequency Habits (No Rigid Deadlines)',
                    description:
                        '• For activities like Practicing Instruments (Piano, Violin) or Personal Research, where there is no strict deadline but you want consistency.\n'
                        '• Set target frequency (e.g. 3×/week) and preferred window (Morning, Afternoon, Evening).\n'
                        '• 1-tap "+ Log Session" right from the Dashboard or Habits screen.',
                  ),
                  const SizedBox(height: 16),
                  _buildSection(
                    context: context,
                    icon: Icons.lightbulb,
                    iconColor: Colors.amberAccent,
                    title: '5. Eliminating Idle Time & Focus Mode',
                    description:
                        '• Never wonder what to do next: The top hero card checks your free time and highlights the highest-priority task or habit session.\n'
                        '• Tap "Start Focus Timer" to launch an instant 15m, 25m, or 50m Pomodoro timer with zero hesitation.',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 46,
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).pop(),
                style: ElevatedButton.styleFrom(
                  backgroundColor: theme.colorScheme.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('Got it!'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSection({
    required BuildContext context,
    required IconData icon,
    required Color iconColor,
    required String title,
    required String description,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: iconColor.withOpacity(isDark ? 0.12 : 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: iconColor.withOpacity(isDark ? 0.35 : 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: iconColor, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    color: isDark ? iconColor : iconColor.withAlpha(240),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            description,
            style: TextStyle(
              fontSize: 13,
              height: 1.45,
              color: isDark ? const Color(0xFFE2E8F0) : const Color(0xFF334155),
            ),
          ),
        ],
      ),
    );
  }
}
