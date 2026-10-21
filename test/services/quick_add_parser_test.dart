// test/services/quick_add_parser_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:kairos/data/database/app_database.dart';
import 'package:kairos/services/quick_add_parser.dart';

Category _cat(String slug, String name) => Category(
      id: slug.hashCode,
      name: name,
      slug: slug,
      emoji: '📌',
      colorHex: '#4A90D9',
      isSystem: true,
      isDeleted: false,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );

void main() {
  // Wednesday, Oct 21 2026, 14:00
  final now = DateTime(2026, 10, 21, 14, 0);
  final categories = [_cat('schoolwork', 'Schoolwork'), _cat('personal', 'Personal')];

  QuickAddResult parse(String input) => parseQuickAdd(input, now: now, categories: categories);

  test('the example from the design: title, weekday, time, category', () {
    final r = parse('HW3 fri 5pm #school');
    expect(r.title, 'HW3');
    expect(r.due, DateTime(2026, 10, 23, 17, 0));
    expect(r.category, 'schoolwork');
    expect(r.hasExplicitTime, isTrue);
    expect(r.tokens.map((t) => t.kind), [QuickAddTokenKind.date, QuickAddTokenKind.time, QuickAddTokenKind.category]);
  });

  test('plain text is all title and has no due date', () {
    final r = parse('Read chapter 2');
    expect(r.title, 'Read chapter 2');
    expect(r.due, isNull);
    expect(r.tokens, isEmpty);
  });

  group('dates', () {
    test('today / tomorrow / tmr default to 23:59', () {
      expect(parse('x today').due, DateTime(2026, 10, 21, 23, 59));
      expect(parse('x tomorrow').due, DateTime(2026, 10, 22, 23, 59));
      expect(parse('x tmr').due, DateTime(2026, 10, 22, 23, 59));
      expect(parse('x today').hasExplicitTime, isFalse);
    });

    test('tonight means today 21:00', () {
      expect(parse('x tonight').due, DateTime(2026, 10, 21, 21, 0));
    });

    test('a weekday is the next one after today; next adds a week', () {
      expect(parse('x wed').due, DateTime(2026, 10, 28, 23, 59)); // today is Wednesday
      expect(parse('x Friday').due, DateTime(2026, 10, 23, 23, 59));
      expect(parse('x next fri').due, DateTime(2026, 10, 30, 23, 59));
    });

    test('numeric and month-name dates; past dates roll to next year', () {
      expect(parse('x 10/28').due, DateTime(2026, 10, 28, 23, 59));
      expect(parse('x oct 28').due, DateTime(2026, 10, 28, 23, 59));
      expect(parse('x 28 Oct').due, DateTime(2026, 10, 28, 23, 59));
      expect(parse('x 3/1').due, DateTime(2027, 3, 1, 23, 59));
      expect(parse('x 3/1/2028').due, DateTime(2028, 3, 1, 23, 59));
    });

    test('relative dates', () {
      expect(parse('x in 3 days').due, DateTime(2026, 10, 24, 23, 59));
      expect(parse('x in 2 weeks').due, DateTime(2026, 11, 4, 23, 59));
    });

    test('impossible dates stay in the title', () {
      final r = parse('Lab 13/40');
      expect(r.due, isNull);
      expect(r.title, 'Lab 13/40');
    });
  });

  group('times', () {
    test('am/pm, 24h, noon, midnight', () {
      expect(parse('x fri 9am').due, DateTime(2026, 10, 23, 9, 0));
      expect(parse('x fri 5:30 pm').due, DateTime(2026, 10, 23, 17, 30));
      expect(parse('x fri 12am').due, DateTime(2026, 10, 23, 0, 0));
      expect(parse('x fri 18:45').due, DateTime(2026, 10, 23, 18, 45));
      expect(parse('x fri noon').due, DateTime(2026, 10, 23, 12, 0));
      expect(parse('x fri midnight').due, DateTime(2026, 10, 23, 23, 59));
    });

    test('a time alone means today, or tomorrow once it has passed', () {
      expect(parse('x 5pm').due, DateTime(2026, 10, 21, 17, 0));
      expect(parse('x 9am').due, DateTime(2026, 10, 22, 9, 0));
    });

    test('impossible times stay in the title', () {
      expect(parse('Ratio 25:99').due, isNull);
      expect(parse('Ratio 25:99').title, 'Ratio 25:99');
    });
  });

  group('categories', () {
    test('matches slug or name prefix, case-insensitively', () {
      expect(parse('x #PERS').category, 'personal');
      expect(parse('x #schoolwork').category, 'schoolwork');
    });

    test('unknown tags stay in the title', () {
      final r = parse('Buy milk #groceries');
      expect(r.category, isNull);
      expect(r.title, 'Buy milk #groceries');
    });
  });

  group('recurrence', () {
    test('every <weekday> sets the date and recurrence', () {
      final r = parse('Problem set every mon 9am');
      expect(r.isRecurring, isTrue);
      expect(r.due, DateTime(2026, 10, 26, 9, 0));
      expect(r.title, 'Problem set');
    });

    test('weekly alone needs a date from elsewhere', () {
      expect(parse('Reading weekly').isRecurring, isTrue);
      expect(parse('Reading weekly').due, isNull);
      expect(parse('Reading weekly fri').due, DateTime(2026, 10, 23, 23, 59));
    });
  });

  group('literal text', () {
    test('quoted text is never parsed and loses its quotes in the title', () {
      final r = parse('"Friday Night Lights" essay tmr');
      expect(r.title, 'Friday Night Lights essay');
      expect(r.due, DateTime(2026, 10, 22, 23, 59));
    });

    test('keepTokenAsText turns a parsed token back into title text', () {
      const input = 'SAT prep';
      final sat = parse(input).tokens.single; // read as Saturday
      expect(parse(input).due, DateTime(2026, 10, 24, 23, 59));
      final fixed = keepTokenAsText(input, sat);
      expect(fixed, '"SAT" prep');
      expect(parse(fixed).title, 'SAT prep');
      expect(parse(fixed).due, isNull);
    });

    test('only the first date counts; later date words stay in the title', () {
      final r = parse('SAT prep tmr');
      expect(r.due, DateTime(2026, 10, 22, 23, 59));
      expect(r.title, 'SAT prep');
    });

    test('words containing date keywords are left alone', () {
      expect(parse('Sunset photos').due, isNull);
      expect(parse('Monday.com setup').tokens.single.raw, 'Monday'); // whole word only
    });

    test('Chinese titles keep their text', () {
      final r = parse('國防政策期中報告 oct 28 noon #school');
      expect(r.title, '國防政策期中報告');
      expect(r.due, DateTime(2026, 10, 28, 12, 0));
      expect(r.category, 'schoolwork');
    });
  });
}
