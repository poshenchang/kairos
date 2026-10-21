// lib/ui/widgets/calendar_import_card.dart
//
// Settings card to import events from an iCalendar (.ics) file or link:
// choose a source, review what was found (and what will be skipped), pick a
// category, then import. Events already in Kairos (same title and start
// time) are skipped, so re-importing the same calendar is safe.

import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:kairos/data/database/app_database.dart';
import 'package:kairos/data/repositories/repository_providers.dart';
import 'package:kairos/services/ics_import.dart';
import 'package:kairos/services/settings_service.dart';
import 'package:kairos/services/supabase_sync_service.dart';
import 'package:kairos/services/timezone_service.dart';
import 'package:kairos/ui/providers/app_providers.dart';

class CalendarImportCard extends ConsumerStatefulWidget {
  const CalendarImportCard({super.key});

  @override
  ConsumerState<CalendarImportCard> createState() => _CalendarImportCardState();
}

class _CalendarImportCardState extends ConsumerState<CalendarImportCard> {
  final _urlController = TextEditingController();
  IcsParseResult? _parsed;
  String? _sourceName;
  String? _error;
  bool _busy = false;
  String _category = 'schoolwork';

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  void _load(String content, String sourceName) {
    if (!content.contains('BEGIN:VCALENDAR')) {
      setState(() => _error = "That doesn't look like a calendar (.ics) file.");
      return;
    }
    final settings = ref.read(settingsNotifierProvider);
    final parsed = parseIcs(
      content,
      fromActive: (wall) => TimezoneService.instance.fromActiveTime(wall, settings),
      toActive: (utc) => TimezoneService.instance.toActiveTime(utc, settings),
    );
    setState(() {
      _parsed = parsed;
      _sourceName = sourceName;
      _error = parsed.events.isEmpty ? 'No events Kairos can import were found.' : null;
    });
  }

  Future<void> _pickFile() async {
    setState(() => _error = null);
    // FileType.any: iOS greys out .ics files when filtering by extension
    final file = await FilePicker.pickFile(dialogTitle: 'Choose a calendar file (.ics)');
    if (file == null) return;
    _load(utf8.decode(await file.readAsBytes(), allowMalformed: true), file.name);
  }

  Future<void> _fetchUrl() async {
    final raw = _urlController.text.trim();
    if (raw.isEmpty) return;
    final uri = Uri.tryParse(raw.replaceFirst(RegExp(r'^webcals?://'), 'https://'));
    if (uri == null || !uri.hasScheme) {
      setState(() => _error = 'Enter a full link starting with https:// or webcal://');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final res = await http.get(uri);
      if (res.statusCode != 200) throw Exception('HTTP ${res.statusCode}');
      _load(utf8.decode(res.bodyBytes, allowMalformed: true), uri.host);
    } catch (e) {
      setState(() => _error = kIsWeb
          // Most calendar servers don't send CORS headers, so browsers can't fetch them
          ? "Couldn't fetch that link from the browser (the calendar server doesn't allow it). "
              'Download the .ics file and choose it above, or import the link from the desktop app.'
          : "Couldn't fetch that link ($e).");
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _import() async {
    final parsed = _parsed;
    if (parsed == null) return;
    setState(() => _busy = true);

    final dao = ref.read(eventDaoProvider);
    final existing = await dao.getAllEvents();
    final seen = existing.map((e) => '${e.title}|${e.startTime.toUtc().millisecondsSinceEpoch}').toSet();
    var added = 0;
    var duplicates = 0;
    for (final e in parsed.events) {
      final key = '${e.title}|${e.startUtc.millisecondsSinceEpoch}';
      if (!seen.add(key)) {
        duplicates++;
        continue;
      }
      await dao.insertEvent(EventsCompanion.insert(
        title: e.title,
        category: Value(_category),
        eventType: Value(_category),
        startTime: e.startUtc,
        endTime: e.endUtc,
        isRecurring: Value(e.rrule != null),
        rrule: Value(e.rrule),
        notes: Value(e.notes),
      ));
      added++;
    }
    if (ref.read(settingsNotifierProvider).isSupabaseConfigured && added > 0) {
      ref.read(supabaseSyncServiceProvider.notifier).syncNow();
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _parsed = null;
      _sourceName = null;
    });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('Imported $added ${added == 1 ? 'event' : 'events'}'
          '${duplicates > 0 ? ' ($duplicates already in Kairos)' : ''}.'),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final categories = ref.watch(allCategoriesProvider).value ?? [];
    if (categories.isNotEmpty && !categories.any((c) => c.slug == _category)) _category = categories.first.slug;
    final parsed = _parsed;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Import Calendar', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            const SizedBox(height: 6),
            Text(
              'Add your class timetable or another calendar from an .ics file or link '
              '(e.g. Google Calendar → Settings → Export, or a course system\'s calendar link).',
              style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 14),
            OutlinedButton.icon(
              icon: const Icon(Icons.upload_file),
              label: const Text('Choose .ics file'),
              onPressed: _busy ? null : _pickFile,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _urlController,
                    keyboardType: TextInputType.url,
                    decoration: const InputDecoration(
                      labelText: 'Or paste a calendar link',
                      hintText: 'https://… or webcal://…',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => _fetchUrl(),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.tonal(onPressed: _busy ? null : _fetchUrl, child: const Text('Fetch')),
              ],
            ),
            if (_busy) ...[
              const SizedBox(height: 12),
              const LinearProgressIndicator(),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: TextStyle(color: theme.colorScheme.error, fontSize: 13)),
            ],
            if (parsed != null && parsed.events.isNotEmpty) ...[
              const Divider(height: 28),
              Text(_sourceName ?? '', style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text(_summary(parsed), style: const TextStyle(fontSize: 13)),
              if (parsed.skippedTotal > 0) ...[
                const SizedBox(height: 4),
                Text(
                  _skippedSummary(parsed),
                  style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                isExpanded: true,
                initialValue: categories.any((c) => c.slug == _category) ? _category : null,
                decoration: const InputDecoration(labelText: 'Category for imported events', border: OutlineInputBorder()),
                items: [
                  for (final c in categories) DropdownMenuItem(value: c.slug, child: Text('${c.emoji} ${c.name}')),
                ],
                onChanged: (v) {
                  if (v != null) setState(() => _category = v);
                },
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                icon: const Icon(Icons.download_done),
                label: Text('Import ${parsed.events.length} ${parsed.events.length == 1 ? 'event' : 'events'}'),
                onPressed: _busy ? null : _import,
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _summary(IcsParseResult r) {
    final recurring = r.events.where((e) => e.rrule != null).length;
    final oneOff = r.events.length - recurring;
    return [
      if (recurring > 0) '$recurring repeating ${recurring == 1 ? 'event' : 'events'}',
      if (oneOff > 0) '$oneOff one-off ${oneOff == 1 ? 'event' : 'events'}',
    ].join(' · ');
  }

  String _skippedSummary(IcsParseResult r) {
    final parts = [
      if (r.skippedAllDay > 0) '${r.skippedAllDay} all-day',
      if (r.skippedUnsupportedRepeat > 0) '${r.skippedUnsupportedRepeat} with repeat rules Kairos doesn\'t support (e.g. monthly, every other week)',
      if (r.skippedCancelled > 0) '${r.skippedCancelled} cancelled',
      if (r.skippedInvalid > 0) '${r.skippedInvalid} unreadable',
    ];
    return 'Will skip: ${parts.join(', ')}.';
  }
}
