import 'package:flutter_test/flutter_test.dart';
import 'package:pocketbase_drift/pocketbase_drift.dart';

void main() {
  // Helper function to easily test the parser
  String parseFilter(String filter) {
    final baseFields = {'id', 'created', 'updated', 'service'};
    final parser = FilterParser(filter, baseFields: baseFields);
    return parser.parse();
  }

  group('Basic Operators', () {
    test('parses equality operator', () {
      final filter = 'name = "test"';
      final expected = "json_extract(services.data, '\$.name') = 'test'";
      expect(parseFilter(filter), expected);
    });

    test('parses not-equal operator', () {
      final filter = 'status != "done"';
      final expected = "json_extract(services.data, '\$.status') != 'done'";
      expect(parseFilter(filter), expected);
    });

    test('parses comparison operators', () {
      expect(
        parseFilter('score > 100'),
        "json_extract(services.data, '\$.score') > 100",
      );
      expect(
        parseFilter('score >= 100'),
        "json_extract(services.data, '\$.score') >= 100",
      );
      expect(
        parseFilter('score < 100'),
        "json_extract(services.data, '\$.score') < 100",
      );
      expect(
        parseFilter('score <= 100'),
        "json_extract(services.data, '\$.score') <= 100",
      );
    });

    test('parses LIKE operator (~)', () {
      final filter = 'name ~ "test"';
      // Should auto-wrap in % for wildcard
      final expected = "json_extract(services.data, '\$.name') LIKE '%test%'";
      expect(parseFilter(filter), expected);
    });

    test('parses NOT LIKE operator (!~)', () {
      final filter = 'name !~ "test"';
      final expected =
          "json_extract(services.data, '\$.name') NOT LIKE '%test%'";
      expect(parseFilter(filter), expected);
    });

    test('preserves wildcards in LIKE operator', () {
      final filter = 'name ~ "test%"';
      // Should NOT double-wrap since wildcard is present
      final expected = "json_extract(services.data, '\$.name') LIKE 'test%'";
      expect(parseFilter(filter), expected);
    });
  });

  group('Logical Operators', () {
    test('parses logical AND with &&', () {
      final filter = 'name = "test" && status = "active"';
      final expected =
          "json_extract(services.data, '\$.name') = 'test' AND json_extract(services.data, '\$.status') = 'active'";
      expect(parseFilter(filter), expected);
    });

    test('parses logical AND with keyword', () {
      final filter = 'name = "test" AND status = "active"';
      final expected =
          "json_extract(services.data, '\$.name') = 'test' AND json_extract(services.data, '\$.status') = 'active'";
      expect(parseFilter(filter), expected);
    });

    test('parses logical OR with ||', () {
      final filter = 'name = "test" || status = "pending"';
      final expected =
          "json_extract(services.data, '\$.name') = 'test' OR json_extract(services.data, '\$.status') = 'pending'";
      expect(parseFilter(filter), expected);
    });

    test('parses logical OR with keyword (case-insensitive)', () {
      final filter = 'name = "test" or status = "pending"';
      final expected =
          "json_extract(services.data, '\$.name') = 'test' OR json_extract(services.data, '\$.status') = 'pending'";
      expect(parseFilter(filter), expected);
    });

    test('parses nested expressions with parentheses', () {
      final filter = 'id = "123" && (status = "done" || name ~ "task")';
      final expected =
          "id = '123' AND (json_extract(services.data, '\$.status') = 'done' OR json_extract(services.data, '\$.name') LIKE '%task%')";
      expect(parseFilter(filter), expected);
    });

    test('parses deeply nested expressions', () {
      final filter =
          '(name = "A" && (status = "B" || status = "C")) || id = "D"';
      final expected =
          "(json_extract(services.data, '\$.name') = 'A' AND (json_extract(services.data, '\$.status') = 'B' OR json_extract(services.data, '\$.status') = 'C')) OR id = 'D'";
      expect(parseFilter(filter), expected);
    });
  });

  group('Null Handling', () {
    test('parses null equality as IS NULL', () {
      final filter = 'completed_at = null';
      final expected = "json_extract(services.data, '\$.completed_at') IS NULL";
      expect(parseFilter(filter), expected);
    });

    test('parses null inequality as IS NOT NULL', () {
      final filter = 'user != null';
      final expected = "json_extract(services.data, '\$.user') IS NOT NULL";
      expect(parseFilter(filter), expected);
    });

    test('handles null with base fields', () {
      final filter = 'id = null';
      expect(parseFilter(filter), 'id IS NULL');
    });
  });

  group('Boolean Handling', () {
    test('parses true literal for JSON fields', () {
      final filter = 'active = true';
      // JSON fields use true/false literals
      final expected = "json_extract(services.data, '\$.active') = true";
      expect(parseFilter(filter), expected);
    });

    test('parses false literal for JSON fields', () {
      final filter = 'active = false';
      final expected = "json_extract(services.data, '\$.active') = false";
      expect(parseFilter(filter), expected);
    });

    test('parses boolean literals case-insensitively', () {
      expect(
        parseFilter('active = TRUE'),
        "json_extract(services.data, '\$.active') = true",
      );
      expect(
        parseFilter('active = False'),
        "json_extract(services.data, '\$.active') = false",
      );
    });
  });

  group('Numeric Handling', () {
    test('parses integer values', () {
      final filter = 'score > 100';
      final expected = "json_extract(services.data, '\$.score') > 100";
      expect(parseFilter(filter), expected);
    });

    test('parses decimal values', () {
      final filter = 'price = 19.99';
      final expected = "json_extract(services.data, '\$.price') = 19.99";
      expect(parseFilter(filter), expected);
    });

    test('parses negative numbers', () {
      final filter = 'temperature < -10';
      final expected = "json_extract(services.data, '\$.temperature') < -10";
      expect(parseFilter(filter), expected);
    });
  });

  group('Any-of Operators', () {
    test('parses ?= operator', () {
      final filter = 'tags ?= "flutter"';
      final expected =
          "EXISTS (SELECT 1 FROM json_each(json_extract(services.data, '\$.tags')) WHERE value = 'flutter')";
      expect(parseFilter(filter), expected);
    });

    test('parses ?!= operator', () {
      final filter = 'tags ?!= "deprecated"';
      final expected =
          "EXISTS (SELECT 1 FROM json_each(json_extract(services.data, '\$.tags')) WHERE value != 'deprecated')";
      expect(parseFilter(filter), expected);
    });

    test('parses ?~ operator with LIKE', () {
      final filter = 'tags ?~ "flutter"';
      final expected =
          "EXISTS (SELECT 1 FROM json_each(json_extract(services.data, '\$.tags')) WHERE value LIKE '%flutter%')";
      expect(parseFilter(filter), expected);
    });

    test('parses ?!~ operator', () {
      final filter = 'tags ?!~ "test"';
      final expected =
          "EXISTS (SELECT 1 FROM json_each(json_extract(services.data, '\$.tags')) WHERE value NOT LIKE '%test%')";
      expect(parseFilter(filter), expected);
    });

    test('parses ?> operator', () {
      final filter = 'scores ?> 80';
      final expected =
          "EXISTS (SELECT 1 FROM json_each(json_extract(services.data, '\$.scores')) WHERE value > 80)";
      expect(parseFilter(filter), expected);
    });

    test('parses ?>= operator', () {
      final filter = 'scores ?>= 80';
      final expected =
          "EXISTS (SELECT 1 FROM json_each(json_extract(services.data, '\$.scores')) WHERE value >= 80)";
      expect(parseFilter(filter), expected);
    });

    test('parses ?< operator', () {
      final filter = 'scores ?< 50';
      final expected =
          "EXISTS (SELECT 1 FROM json_each(json_extract(services.data, '\$.scores')) WHERE value < 50)";
      expect(parseFilter(filter), expected);
    });

    test('parses ?<= operator', () {
      final filter = 'scores ?<= 50';
      final expected =
          "EXISTS (SELECT 1 FROM json_each(json_extract(services.data, '\$.scores')) WHERE value <= 50)";
      expect(parseFilter(filter), expected);
    });
  });

  group('Field Modifiers', () {
    test('parses :lower modifier', () {
      final filter = 'name:lower = "john"';
      final expected = "LOWER(json_extract(services.data, '\$.name')) = 'john'";
      expect(parseFilter(filter), expected);
    });

    test('parses :lower modifier with LIKE', () {
      final filter = 'email:lower ~ "gmail"';
      final expected =
          "LOWER(json_extract(services.data, '\$.email')) LIKE '%gmail%'";
      expect(parseFilter(filter), expected);
    });

    test('parses :length modifier', () {
      final filter = 'tags:length > 2';
      final expected =
          "json_array_length(json_extract(services.data, '\$.tags')) > 2";
      expect(parseFilter(filter), expected);
    });

    test('parses :length modifier with equality', () {
      final filter = 'items:length = 0';
      final expected =
          "json_array_length(json_extract(services.data, '\$.items')) = 0";
      expect(parseFilter(filter), expected);
    });
  });

  group('DateTime Macros', () {
    test('resolves @now macro', () {
      final result = parseFilter('created > @now');
      // Check that @now was replaced with a datetime string
      expect(result, contains("created >"));
      expect(result, contains("'20")); // Year prefix
      expect(result, isNot(contains('@now')));
    });

    test('resolves @todayStart macro', () {
      final result = parseFilter('created >= @todayStart');
      expect(result, contains("created >="));
      expect(result, contains("T00:00:00")); // Start of day
      expect(result, isNot(contains('@todayStart')));
    });

    test('resolves @todayEnd macro', () {
      final result = parseFilter('created <= @todayEnd');
      expect(result, contains("created <="));
      expect(result, contains("T23:59:59")); // End of day
      expect(result, isNot(contains('@todayEnd')));
    });

    test('resolves @year macro', () {
      final result = parseFilter('birth_year = @year');
      final currentYear = DateTime.now().year.toString();
      expect(result, contains(currentYear));
      expect(result, isNot(contains('@year')));
    });

    test('resolves multiple macros', () {
      final result =
          parseFilter('created >= @monthStart && created <= @monthEnd');
      expect(result, isNot(contains('@monthStart')));
      expect(result, isNot(contains('@monthEnd')));
      expect(result, contains('AND'));
    });
  });

  group('Comment Stripping', () {
    test('strips single-line comments', () {
      final filter = 'name = "test" // this is a comment';
      final expected = "json_extract(services.data, '\$.name') = 'test'";
      expect(parseFilter(filter), expected);
    });

    test('preserves // inside strings', () {
      final filter = 'url = "https://example.com"';
      final expected =
          "json_extract(services.data, '\$.url') = 'https://example.com'";
      expect(parseFilter(filter), expected);
    });
  });

  group('Quote Normalization', () {
    test('converts double quotes to single quotes', () {
      final filter = 'name = "test"';
      final result = parseFilter(filter);
      expect(result, contains("= 'test'"));
    });

    test('handles single quotes in values', () {
      final filter = "name = \"O'Brien\"";
      final result = parseFilter(filter);
      // Single quotes should be escaped by doubling
      expect(result, contains("= 'O''Brien'"));
    });
  });

  group('Base Fields', () {
    test('does not wrap base fields in json_extract', () {
      final filter = 'id = "123"';
      expect(parseFilter(filter), "id = '123'");
    });

    test('wraps non-base fields in json_extract', () {
      final filter = 'custom_field = "value"';
      expect(
        parseFilter(filter),
        "json_extract(services.data, '\$.custom_field') = 'value'",
      );
    });

    test('handles created and updated as base fields', () {
      expect(
        parseFilter('created > "2024-01-01"'),
        "created > '2024-01-01'",
      );
      expect(
        parseFilter('updated < "2024-12-31"'),
        "updated < '2024-12-31'",
      );
    });
  });

  group('Complex Filters', () {
    test('parses complex filter with mixed operators and nesting', () {
      final filter =
          'created > "2024-01-01" && (status = "active" || (priority > 5 && owner != null))';
      final expected =
          "created > '2024-01-01' AND (json_extract(services.data, '\$.status') = 'active' OR (json_extract(services.data, '\$.priority') > 5 AND json_extract(services.data, '\$.owner') IS NOT NULL))";
      expect(parseFilter(filter), expected);
    });

    test('handles whitespace variations', () {
      final filter = ' name   =   "test"   ||   status != "done" ';
      final expected =
          "json_extract(services.data, '\$.name') = 'test' OR json_extract(services.data, '\$.status') != 'done'";
      expect(parseFilter(filter), expected);
    });

    test('combines any-of with regular operators', () {
      final filter = 'tags ?= "flutter" && active = true';
      final result = parseFilter(filter);
      expect(result, contains('EXISTS'));
      expect(result, contains('AND'));
      expect(result, contains('= true'));
    });
  });

  group('Error Handling', () {
    test('throws FormatException for invalid filter', () {
      expect(
        () => parseFilter('invalid filter without operator'),
        throwsFormatException,
      );
    });
  });
}
