// lib/services/quick_add_parser.dart
//
// Parses one-line quick-add input such as `HW3 fri 5pm #school` into a task
// draft. Rule-based and local: recognised tokens are pulled out and whatever
// text remains becomes the title. Text in "double quotes" is never parsed.
//
// Recognised (case-insensitive, first match of each kind wins):
//   #cat                       category whose slug or name starts with "cat"
//   today, tmr, tomorrow       due date
//   mon..sun, next fri         next such weekday after today / a week later
//   10/28, 10/28/2027          month/day[/year]
//   oct 28, 28 oct             month name + day
//   in 3 days, in 2 weeks      relative date
//   23:59, 5pm, 5:30pm, noon   due time
//   weekly, every fri          weekly recurrence

import 'package:kairos/data/database/app_database.dart';

enum QuickAddTokenKind { category, date, time, recurrence }

/// One recognised piece of the input, with its position so the UI can turn it
/// back into plain title text.
class QuickAddToken {
  final QuickAddTokenKind kind;
  final int start;
  final int end;
  final String raw;

  const QuickAddToken(this.kind, this.start, this.end, this.raw);
}

class QuickAddResult {
  final String title;
  final List<QuickAddToken> tokens;

  /// Slug of the matched category, if any.
  final String? category;

  /// Wall-clock due date/time in the user's active timezone, or null when no
  /// date or time was given.
  final DateTime? due;
  final bool isRecurring;

  /// True when a time was typed; false means the 23:59 default was used.
  final bool hasExplicitTime;

  const QuickAddResult({
    required this.title,
    required this.tokens,
    this.category,
    this.due,
    this.isRecurring = false,
    this.hasExplicitTime = false,
  });
}

const _weekdays = {
  'mon': 1, 'monday': 1,
  'tue': 2, 'tues': 2, 'tuesday': 2,
  'wed': 3, 'weds': 3, 'wednesday': 3,
  'thu': 4, 'thur': 4, 'thurs': 4, 'thursday': 4,
  'fri': 5, 'friday': 5,
  'sat': 6, 'saturday': 6,
  'sun': 7, 'sunday': 7,
};

const _months = {
  'jan': 1, 'january': 1, 'feb': 2, 'february': 2, 'mar': 3, 'march': 3,
  'apr': 4, 'april': 4, 'may': 5, 'jun': 6, 'june': 6, 'jul': 7, 'july': 7,
  'aug': 8, 'august': 8, 'sep': 9, 'sept': 9, 'september': 9, 'oct': 10, 'october': 10,
  'nov': 11, 'november': 11, 'dec': 12, 'december': 12,
};

final _weekdayAlt = (_weekdays.keys.toList()..sort((a, b) => b.length - a.length)).join('|');
final _monthAlt = (_months.keys.toList()..sort((a, b) => b.length - a.length)).join('|');

// Word boundaries that also work next to CJK text and punctuation.
const _pre = r'(?<![\w/:#])';
const _post = r'(?![\w/:])';

final _recurrenceRe = RegExp('$_pre(?:every\\s+($_weekdayAlt)|weekly|every\\s+week)$_post', caseSensitive: false);
final _relativeRe = RegExp('${_pre}in\\s+(\\d{1,3})\\s+(days?|weeks?)$_post', caseSensitive: false);
final _nextWeekdayRe = RegExp('${_pre}next\\s+($_weekdayAlt)$_post', caseSensitive: false);
final _keywordDateRe = RegExp('$_pre(today|tonight|tomorrow|tmrw?|tmr)$_post', caseSensitive: false);
final _weekdayRe = RegExp('$_pre($_weekdayAlt)$_post', caseSensitive: false);
final _numericDateRe = RegExp('$_pre(\\d{1,2})/(\\d{1,2})(?:/(\\d{2}|\\d{4}))?$_post');
final _monthDayRe = RegExp('$_pre($_monthAlt)\\.?\\s+(\\d{1,2})(?:st|nd|rd|th)?$_post', caseSensitive: false);
final _dayMonthRe = RegExp('$_pre(\\d{1,2})(?:st|nd|rd|th)?\\s+($_monthAlt)$_post', caseSensitive: false);
final _ampmTimeRe = RegExp('$_pre(\\d{1,2})(?::(\\d{2}))?\\s?(am|pm)$_post', caseSensitive: false);
final _clockTimeRe = RegExp('$_pre(\\d{1,2}):(\\d{2})$_post');
final _namedTimeRe = RegExp('$_pre(noon|midnight)$_post', caseSensitive: false);
final _categoryRe = RegExp(r'(?<![\w#])#([^\s#"]+)');
final _quotedRe = RegExp(r'"([^"]*)"');

QuickAddResult parseQuickAdd(
  String input, {
  required DateTime now,
  required List<Category> categories,
}) {
  final today = DateTime(now.year, now.month, now.day);
  final tokens = <QuickAddToken>[];
  final quoted = _quotedRe.allMatches(input).toList();

  bool isFree(int start, int end) =>
      !quoted.any((q) => start < q.end && end > q.start) && !tokens.any((t) => start < t.end && end > t.start);

  /// First match of [re] outside quotes and existing tokens.
  RegExpMatch? take(RegExp re, QuickAddTokenKind kind) {
    for (final m in re.allMatches(input)) {
      if (isFree(m.start, m.end)) {
        tokens.add(QuickAddToken(kind, m.start, m.end, m.group(0)!));
        return m;
      }
    }
    return null;
  }

  // ── Category ──
  String? category;
  for (final m in _categoryRe.allMatches(input)) {
    if (!isFree(m.start, m.end)) continue;
    final needle = m.group(1)!.toLowerCase();
    final match = categories.where((c) => c.slug.toLowerCase().startsWith(needle) || c.name.toLowerCase().startsWith(needle)).firstOrNull;
    if (match == null) continue; // unknown tags stay in the title
    category = match.slug;
    tokens.add(QuickAddToken(QuickAddTokenKind.category, m.start, m.end, m.group(0)!));
    break;
  }

  // ── Recurrence (may also fix the date) ──
  DateTime? date;
  var isRecurring = false;
  final rec = take(_recurrenceRe, QuickAddTokenKind.recurrence);
  if (rec != null) {
    isRecurring = true;
    if (rec.group(1) != null) date = _nextWeekday(today, _weekdays[rec.group(1)!.toLowerCase()]!);
  }

  // ── Date (most specific patterns first) ──
  var tonight = false;
  if (date == null) {
    RegExpMatch? m;
    if ((m = take(_relativeRe, QuickAddTokenKind.date)) != null) {
      final n = int.parse(m!.group(1)!);
      date = today.add(Duration(days: m.group(2)!.toLowerCase().startsWith('week') ? n * 7 : n));
    } else if ((m = take(_nextWeekdayRe, QuickAddTokenKind.date)) != null) {
      date = _nextWeekday(today, _weekdays[m!.group(1)!.toLowerCase()]!).add(const Duration(days: 7));
    } else if ((m = take(_monthDayRe, QuickAddTokenKind.date)) != null) {
      date = _monthDay(today, _months[m!.group(1)!.toLowerCase()]!, int.parse(m.group(2)!), null);
    } else if ((m = take(_dayMonthRe, QuickAddTokenKind.date)) != null) {
      date = _monthDay(today, _months[m!.group(2)!.toLowerCase()]!, int.parse(m.group(1)!), null);
    } else if ((m = take(_numericDateRe, QuickAddTokenKind.date)) != null) {
      final y = m!.group(3) == null ? null : int.parse(m.group(3)!.length == 2 ? '20${m.group(3)}' : m.group(3)!);
      date = _monthDay(today, int.parse(m.group(1)!), int.parse(m.group(2)!), y);
      if (date == null) tokens.removeLast(); // not a real date (e.g. 13/40): leave it as text
    } else if ((m = take(_keywordDateRe, QuickAddTokenKind.date)) != null) {
      final word = m!.group(1)!.toLowerCase();
      tonight = word == 'tonight';
      date = word == 'today' || tonight ? today : today.add(const Duration(days: 1));
    } else if ((m = take(_weekdayRe, QuickAddTokenKind.date)) != null) {
      date = _nextWeekday(today, _weekdays[m!.group(1)!.toLowerCase()]!);
    }
  }

  // ── Time ──
  int? hour;
  int? minute;
  RegExpMatch? t;
  if ((t = take(_ampmTimeRe, QuickAddTokenKind.time)) != null) {
    final h = int.parse(t!.group(1)!);
    final min = int.parse(t.group(2) ?? '0');
    if (h >= 1 && h <= 12 && min < 60) {
      final pm = t.group(3)!.toLowerCase() == 'pm';
      hour = (h % 12) + (pm ? 12 : 0);
      minute = min;
    } else {
      tokens.removeLast();
    }
  } else if ((t = take(_clockTimeRe, QuickAddTokenKind.time)) != null) {
    final h = int.parse(t!.group(1)!);
    final min = int.parse(t.group(2)!);
    if (h < 24 && min < 60) {
      hour = h;
      minute = min;
    } else {
      tokens.removeLast();
    }
  } else if ((t = take(_namedTimeRe, QuickAddTokenKind.time)) != null) {
    // "midnight" as a deadline means the end of that day, not its start
    final noon = t!.group(1)!.toLowerCase() == 'noon';
    hour = noon ? 12 : 23;
    minute = noon ? 0 : 59;
  }

  // ── Resolve the due date/time ──
  DateTime? due;
  if (date != null) {
    final h = hour ?? (tonight ? 21 : 23);
    final min = minute ?? (tonight ? 0 : 59);
    due = DateTime(date.year, date.month, date.day, h, min);
  } else if (hour != null) {
    due = DateTime(today.year, today.month, today.day, hour, minute!);
    if (!due.isAfter(now)) due = due.add(const Duration(days: 1));
  }

  tokens.sort((a, b) => a.start.compareTo(b.start));
  return QuickAddResult(
    title: _remainingTitle(input, tokens),
    tokens: tokens,
    category: category,
    due: due,
    isRecurring: isRecurring,
    hasExplicitTime: hour != null || tonight,
  );
}

/// Input with recognised tokens removed and quote marks dropped.
String _remainingTitle(String input, List<QuickAddToken> tokens) {
  final buffer = StringBuffer();
  var pos = 0;
  for (final t in tokens) {
    buffer.write(input.substring(pos, t.start));
    buffer.write(' ');
    pos = t.end;
  }
  buffer.write(input.substring(pos));
  return buffer.toString().replaceAll('"', '').replaceAll(RegExp(r'\s+'), ' ').trim();
}

/// The first [weekday] strictly after [today].
DateTime _nextWeekday(DateTime today, int weekday) {
  var days = (weekday - today.weekday) % 7;
  if (days == 0) days = 7;
  return today.add(Duration(days: days));
}

/// [month]/[day] in [year], or the next such date from [today] when no year
/// is given. Null when the date doesn't exist.
DateTime? _monthDay(DateTime today, int month, int day, int? year) {
  if (month < 1 || month > 12 || day < 1 || day > 31) return null;
  DateTime build(int y) => DateTime(y, month, day);
  var d = build(year ?? today.year);
  if (d.month != month) return null; // e.g. Feb 30 rolled over
  if (year == null && d.isBefore(today)) d = build(today.year + 1);
  return d;
}

/// Wraps [token]'s text in quotes so the parser treats it as title text.
String keepTokenAsText(String input, QuickAddToken token) =>
    '${input.substring(0, token.start)}"${token.raw}"${input.substring(token.end)}';
