// lib/services/ics_import.dart
//
// Parses iCalendar (.ics) files into events Kairos can store.
//
// Supported: timed one-off events; weekly (BYDAY) and daily repeats with
// UNTIL/COUNT and EXDATE; single-occurrence overrides (RECURRENCE-ID), which
// become one-off events plus an EXDATE on their series. Times may be UTC,
// TZID-qualified, or floating (read as the user's active timezone).
//
// Skipped and counted, never silently dropped: all-day events, cancelled
// events, and repeat rules Kairos can't represent (monthly, INTERVAL > 1, ...).

import 'package:intl/intl.dart';
import 'package:timezone/timezone.dart' as tz;

class ImportedEvent {
  final String title;
  final DateTime startUtc;
  final DateTime endUtc;

  /// Kairos RRULE (FREQ/BYDAY/UNTIL/COUNT/EXDATE=yyyy-MM-dd), or null.
  final String? rrule;
  final String? notes;

  const ImportedEvent({required this.title, required this.startUtc, required this.endUtc, this.rrule, this.notes});
}

class IcsParseResult {
  final List<ImportedEvent> events;
  final int skippedAllDay;
  final int skippedCancelled;
  final int skippedUnsupportedRepeat;
  final int skippedInvalid;

  const IcsParseResult({
    required this.events,
    this.skippedAllDay = 0,
    this.skippedCancelled = 0,
    this.skippedUnsupportedRepeat = 0,
    this.skippedInvalid = 0,
  });

  int get skippedTotal => skippedAllDay + skippedCancelled + skippedUnsupportedRepeat + skippedInvalid;
}

/// A content line: `NAME;PARAM=V;...:value`.
class _Prop {
  final String name;
  final Map<String, String> params;
  final String value;

  _Prop(this.name, this.params, this.value);
}

/// Parses [content]. [fromActive] converts a floating wall-clock time (no
/// timezone) to UTC; [toActive] converts UTC to the user's wall clock, used
/// for EXDATE day keys.
IcsParseResult parseIcs(
  String content, {
  required DateTime Function(DateTime wall) fromActive,
  required DateTime Function(DateTime utc) toActive,
}) {
  final vevents = <List<_Prop>>[];
  List<_Prop>? current;
  var depth = 0; // nested components inside VEVENT (e.g. VALARM) are ignored
  for (final line in _unfold(content)) {
    final prop = _parseLine(line);
    if (prop == null) continue;
    if (prop.name == 'BEGIN') {
      if (prop.value.toUpperCase() == 'VEVENT' && current == null) {
        current = [];
      } else if (current != null) {
        depth++;
      }
    } else if (prop.name == 'END') {
      if (current != null && depth > 0) {
        depth--;
      } else if (current != null && prop.value.toUpperCase() == 'VEVENT') {
        vevents.add(current);
        current = null;
      }
    } else if (current != null && depth == 0) {
      current.add(prop);
    }
  }

  var allDay = 0, cancelled = 0, unsupported = 0, invalid = 0;
  final masters = <String, _Draft>{}; // UID -> recurring series
  final singles = <_Draft>[];
  final overrides = <({String uid, DateTime originalUtc, _Draft draft})>[];

  for (final props in vevents) {
    _Prop? get(String name) => props.where((p) => p.name == name).firstOrNull;

    final start = get('DTSTART');
    if (start == null) {
      invalid++;
      continue;
    }
    if ((get('STATUS')?.value.toUpperCase() ?? '') == 'CANCELLED') {
      cancelled++;
      continue;
    }
    if (start.params['VALUE']?.toUpperCase() == 'DATE' || !start.value.contains('T')) {
      allDay++;
      continue;
    }

    final startUtc = _parseDateTime(start, fromActive);
    if (startUtc == null) {
      invalid++;
      continue;
    }
    final end = get('DTEND');
    final duration = get('DURATION');
    final endUtc = end != null
        ? _parseDateTime(end, fromActive)
        : startUtc.add(duration != null ? _parseDuration(duration.value) ?? Duration.zero : Duration.zero);
    if (endUtc == null || endUtc.isBefore(startUtc)) {
      invalid++;
      continue;
    }

    final title = _unescape(get('SUMMARY')?.value ?? '').trim();
    final location = _unescape(get('LOCATION')?.value ?? '').trim();
    final description = _unescape(get('DESCRIPTION')?.value ?? '').trim();
    final notes = [if (location.isNotEmpty) '📍 $location', if (description.isNotEmpty) description].join('\n');

    final draft = _Draft(
      title: title.isEmpty ? '(untitled)' : (title.length > 200 ? title.substring(0, 200) : title),
      startUtc: startUtc,
      endUtc: endUtc,
      notes: notes.isEmpty ? null : notes,
    );

    final recurrenceId = get('RECURRENCE-ID');
    final uid = get('UID')?.value;
    if (recurrenceId != null && uid != null) {
      final originalUtc = _parseDateTime(recurrenceId, fromActive);
      if (originalUtc != null) overrides.add((uid: uid, originalUtc: originalUtc, draft: draft));
      continue;
    }

    final rrule = get('RRULE');
    if (rrule == null) {
      singles.add(draft);
      continue;
    }
    final converted = _convertRrule(rrule.value);
    if (converted == null) {
      unsupported++;
      continue;
    }
    // iCalendar weekly rules may omit BYDAY (meaning the start's weekday), but
    // Kairos expands a BYDAY-less weekly rule to nothing, so spell it out
    draft.rruleBase = converted.startsWith('FREQ=WEEKLY') && !converted.contains('BYDAY=')
        ? '$converted;BYDAY=${const ['MO', 'TU', 'WE', 'TH', 'FR', 'SA', 'SU'][toActive(startUtc).weekday - 1]}'
        : converted;
    for (final ex in props.where((p) => p.name == 'EXDATE')) {
      for (final part in ex.value.split(',')) {
        final exUtc = _parseDateTime(_Prop('EXDATE', ex.params, part), fromActive);
        if (exUtc != null) draft.exdates.add(_dayKey(toActive(exUtc)));
      }
    }
    if (uid != null) {
      masters[uid] = draft;
    } else {
      singles.add(draft);
    }
  }

  // A moved/edited occurrence replaces that day of its series
  for (final o in overrides) {
    masters[o.uid]?.exdates.add(_dayKey(toActive(o.originalUtc)));
    singles.add(o.draft);
  }

  return IcsParseResult(
    events: [...masters.values, ...singles].map((d) => d.build()).toList(),
    skippedAllDay: allDay,
    skippedCancelled: cancelled,
    skippedUnsupportedRepeat: unsupported,
    skippedInvalid: invalid,
  );
}

class _Draft {
  final String title;
  final DateTime startUtc;
  final DateTime endUtc;
  final String? notes;
  String? rruleBase;
  final Set<String> exdates = {};

  _Draft({required this.title, required this.startUtc, required this.endUtc, this.notes});

  ImportedEvent build() => ImportedEvent(
        title: title,
        startUtc: startUtc,
        endUtc: endUtc,
        notes: notes,
        rrule: rruleBase == null ? null : (exdates.isEmpty ? rruleBase : '$rruleBase;EXDATE=${(exdates.toList()..sort()).join(',')}'),
      );
}

/// RFC 5545 line unfolding: a line starting with space/tab continues the previous one.
List<String> _unfold(String content) {
  final out = <String>[];
  for (final raw in content.replaceAll('\r\n', '\n').replaceAll('\r', '\n').split('\n')) {
    if ((raw.startsWith(' ') || raw.startsWith('\t')) && out.isNotEmpty) {
      out[out.length - 1] += raw.substring(1);
    } else if (raw.isNotEmpty) {
      out.add(raw);
    }
  }
  return out;
}

_Prop? _parseLine(String line) {
  // The value starts at the first ':' that isn't inside a quoted parameter
  var inQuotes = false;
  var colon = -1;
  for (var i = 0; i < line.length; i++) {
    final c = line[i];
    if (c == '"') inQuotes = !inQuotes;
    if (c == ':' && !inQuotes) {
      colon = i;
      break;
    }
  }
  if (colon <= 0) return null;
  final head = line.substring(0, colon).split(';');
  final params = <String, String>{};
  for (final p in head.skip(1)) {
    final eq = p.indexOf('=');
    if (eq > 0) params[p.substring(0, eq).toUpperCase()] = p.substring(eq + 1).replaceAll('"', '');
  }
  return _Prop(head.first.toUpperCase(), params, line.substring(colon + 1));
}

String _unescape(String v) => v
    .replaceAll(r'\n', '\n')
    .replaceAll(r'\N', '\n')
    .replaceAll(r'\,', ',')
    .replaceAll(r'\;', ';')
    .replaceAll(r'\\', r'\');

final _dateTimeRe = RegExp(r'^(\d{4})(\d{2})(\d{2})T(\d{2})(\d{2})(\d{2})(Z?)$');

/// UTC instant for a DATE-TIME property (UTC, TZID, or floating).
DateTime? _parseDateTime(_Prop p, DateTime Function(DateTime wall) fromActive) {
  final m = _dateTimeRe.firstMatch(p.value.trim());
  if (m == null) return null;
  final parts = [for (var i = 1; i <= 6; i++) int.parse(m.group(i)!)];
  if (m.group(7) == 'Z') return DateTime.utc(parts[0], parts[1], parts[2], parts[3], parts[4], parts[5]);

  final loc = _location(p.params['TZID']);
  if (loc != null) return tz.TZDateTime(loc, parts[0], parts[1], parts[2], parts[3], parts[4], parts[5]).toUtc();
  // No or unknown TZID: floating time in the user's timezone
  return fromActive(DateTime(parts[0], parts[1], parts[2], parts[3], parts[4], parts[5])).toUtc();
}

/// IANA location for [tzid]. Some exporters prefix the id
/// (e.g. "/freeassociation.sourceforge.net/Asia/Taipei"), so shorter
/// suffixes are tried too.
tz.Location? _location(String? tzid) {
  if (tzid == null) return null;
  final segments = tzid.split('/').where((s) => s.isNotEmpty).toList();
  for (var i = 0; i < segments.length; i++) {
    try {
      return tz.getLocation(segments.sublist(i).join('/'));
    } catch (_) {}
  }
  return null;
}

Duration? _parseDuration(String v) {
  final m = RegExp(r'^([+-])?P(?:(\d+)W)?(?:(\d+)D)?(?:T(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?)?$').firstMatch(v.trim());
  if (m == null) return null;
  int g(int i) => int.tryParse(m.group(i) ?? '') ?? 0;
  return Duration(days: g(2) * 7 + g(3), hours: g(4), minutes: g(5), seconds: g(6));
}

/// Converts an iCalendar RRULE to the subset Kairos expands, or null.
String? _convertRrule(String value) {
  final params = <String, String>{};
  for (final part in value.split(';')) {
    final eq = part.indexOf('=');
    if (eq > 0) params[part.substring(0, eq).toUpperCase()] = part.substring(eq + 1);
  }
  final freq = params['FREQ']?.toUpperCase();
  if (freq != 'WEEKLY' && freq != 'DAILY') return null;
  if ((int.tryParse(params['INTERVAL'] ?? '1') ?? 1) != 1) return null;
  const supported = {'FREQ', 'INTERVAL', 'BYDAY', 'UNTIL', 'COUNT', 'WKST'};
  if (params.keys.any((k) => !supported.contains(k))) return null;

  final out = ['FREQ=$freq'];
  final byday = params['BYDAY'];
  if (byday != null) {
    // Kairos only understands plain weekday codes (no "1MO"-style ordinals)
    if (!RegExp(r'^(MO|TU|WE|TH|FR|SA|SU)(,(MO|TU|WE|TH|FR|SA|SU))*$').hasMatch(byday.toUpperCase())) return null;
    out.add('BYDAY=${byday.toUpperCase()}');
  }
  final until = params['UNTIL'];
  if (until != null) {
    // Normalise date-only UNTIL to the end of that day
    final u = until.length == 8 ? '${until}T235959Z' : until;
    out.add('UNTIL=$u');
  }
  if (params['COUNT'] != null) out.add('COUNT=${params['COUNT']}');
  return out.join(';');
}

String _dayKey(DateTime wall) => DateFormat('yyyy-MM-dd').format(wall);
