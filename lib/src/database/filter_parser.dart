import 'package:flutter/foundation.dart';

/// Represents a single term in a filter expression, like `name = "value"`.
@immutable
class FilterTerm {
  const FilterTerm(
    this.field,
    this.operator,
    this.value, {
    this.modifier,
    this.isAnyOf = false,
  });

  final String field;
  final String operator;
  final String? value; // Value can be null for operators like IS NULL
  final String? modifier; // Field modifier like :lower, :length
  final bool isAnyOf; // Whether this is a ?= style operator

  @override
  String toString() => '$field $operator ${value ?? ''}'.trim();
}

/// Represents a logical operator in a filter expression.
enum LogicalOperator {
  and,
  or;

  @override
  String toString() => name.toUpperCase();
}

/// Represents the type of a value literal
enum ValueType {
  string,
  number,
  boolean,
  nullValue,
}

/// A class responsible for parsing a PocketBase filter string into a valid
/// SQL `WHERE` clause for Drift.
///
/// This parser accepts **PocketBase-compatible filter syntax** and translates
/// it to SQLite-compatible SQL. This ensures filters can work on both the
/// remote PocketBase server and the local SQLite cache.
///
/// ## Supported Features
///
/// **Operators:**
/// - `=`, `!=`, `>`, `>=`, `<`, `<=`
/// - `~` (LIKE/Contains), `!~` (NOT LIKE)
/// - `?=`, `?!=`, `?>`, `?>=`, `?<`, `?<=`, `?~`, `?!~` (any-of operators for arrays)
///
/// **Logical operators:**
/// - `&&` or `AND`
/// - `||` or `OR`
/// - `(...)` for grouping
///
/// **Value types:**
/// - Strings: `"value"` or `'value'`
/// - Numbers: `123`, `19.99`
/// - Booleans: `true`, `false`
/// - Null: `null`
///
/// **DateTime macros:**
/// - `@now`, `@todayStart`, `@todayEnd`
/// - `@yesterday`, `@tomorrow`
/// - `@monthStart`, `@monthEnd`, `@yearStart`, `@yearEnd`
/// - `@second`, `@minute`, `@hour`, `@day`, `@weekday`, `@month`, `@year`
///
/// **Field modifiers:**
/// - `:lower` - Case-insensitive comparison
/// - `:length` - Array length check
///
/// **Comments:**
/// - `// single line comments` are stripped
class FilterParser {
  FilterParser(this.filter, {required this.baseFields});

  final String filter;
  final Set<String> baseFields;
  final List<dynamic> _tokens = [];

  /// Parses the filter string and generates the SQL WHERE clause.
  String parse() {
    // Pre-process: strip comments and resolve macros
    final processedFilter = _preProcess(filter);
    _tokenize(processedFilter);
    return _buildSql();
  }

  /// Pre-processes the filter string:
  /// 1. Strips single-line comments (// ...)
  /// 2. Resolves datetime macros (@now, @todayStart, etc.)
  String _preProcess(String input) {
    var result = input;

    // Strip single-line comments (but not inside quotes)
    result = _stripComments(result);

    // Resolve datetime macros
    result = _resolveMacros(result);

    return result;
  }

  /// Strips single-line comments while respecting quoted strings.
  String _stripComments(String input) {
    final buffer = StringBuffer();
    bool inSingleQuote = false;
    bool inDoubleQuote = false;

    for (int i = 0; i < input.length; i++) {
      final char = input[i];
      final isEscaped = i > 0 && input[i - 1] == r'\';

      if (!isEscaped) {
        if (char == "'" && !inDoubleQuote) {
          inSingleQuote = !inSingleQuote;
        } else if (char == '"' && !inSingleQuote) {
          inDoubleQuote = !inDoubleQuote;
        }
      }

      // Check for comment start outside quotes
      if (!inSingleQuote &&
          !inDoubleQuote &&
          char == '/' &&
          i + 1 < input.length &&
          input[i + 1] == '/') {
        // Skip until end of line or end of string
        while (i < input.length && input[i] != '\n') {
          i++;
        }
        continue;
      }

      buffer.write(char);
    }

    return buffer.toString();
  }

  /// Resolves PocketBase datetime macros to their actual values.
  String _resolveMacros(String input) {
    final now = DateTime.now().toUtc();
    final today = DateTime.utc(now.year, now.month, now.day);

    final macros = <String, String>{
      // Datetime macros
      '@now': "'${now.toIso8601String()}'",
      '@todayStart': "'${today.toIso8601String()}'",
      '@todayEnd':
          "'${today.add(const Duration(hours: 23, minutes: 59, seconds: 59, milliseconds: 999)).toIso8601String()}'",
      '@yesterday':
          "'${today.subtract(const Duration(days: 1)).toIso8601String()}'",
      '@tomorrow': "'${today.add(const Duration(days: 1)).toIso8601String()}'",
      '@monthStart':
          "'${DateTime.utc(now.year, now.month, 1).toIso8601String()}'",
      '@monthEnd':
          "'${DateTime.utc(now.year, now.month + 1, 0, 23, 59, 59, 999).toIso8601String()}'",
      '@yearStart': "'${DateTime.utc(now.year, 1, 1).toIso8601String()}'",
      '@yearEnd':
          "'${DateTime.utc(now.year, 12, 31, 23, 59, 59, 999).toIso8601String()}'",

      // Numeric datetime components
      '@second': '${now.second}',
      '@minute': '${now.minute}',
      '@hour': '${now.hour}',
      '@day': '${now.day}',
      '@weekday': '${now.weekday % 7}', // 0=Sunday in PocketBase
      '@month': '${now.month}',
      '@year': '${now.year}',
    };

    var result = input;
    // Sort by length descending to avoid partial replacements (e.g., @month before @monthStart)
    final sortedMacros = macros.keys.toList()
      ..sort((a, b) => b.length.compareTo(a.length));

    for (final macro in sortedMacros) {
      result = result.replaceAll(macro, macros[macro]!);
    }

    return result;
  }

  /// Breaks the filter string into a series of [FilterTerm]s, [LogicalOperator]s,
  /// and nested [FilterParser] instances for parenthesized groups. This tokenizer
  /// correctly handles operators inside quoted strings and nested parentheses.
  void _tokenize(String filterStr) {
    // Use word boundaries (\b) to ensure 'AND' and 'OR' are matched as whole words
    // and not as parts of other words (e.g., the 'or' in 'priority').
    final logicalRegex =
        RegExp(r'\s*(&&|\|\||\bAND\b|\bOR\b)\s*', caseSensitive: false);

    // Operator regex supporting:
    // - Standard operators: =, !=, >, >=, <, <=, ~, !~
    // - Any-of operators: ?=, ?!=, ?>, ?>=, ?<, ?<=, ?~, ?!~
    // Field names can include modifiers like :lower, :length
    final termRegex = RegExp(
        r'^\s*([\w\.\-]+(?::\w+)?)\s*(\?!~|\?!=|\?>=|\?<=|\?>|\?<|\?~|\?=|!~|!=|>=|<=|~|=|>|<)\s*(.*)$',
        caseSensitive: false);

    int balance = 0;
    int lastSplit = 0;
    bool inSingleQuote = false;
    bool inDoubleQuote = false;

    for (int i = 0; i < filterStr.length; i++) {
      final char = filterStr[i];

      // Toggle quote state if the quote is not escaped.
      final isEscaped = i > 0 && filterStr[i - 1] == r'\';
      if (!isEscaped) {
        if (char == "'" && !inDoubleQuote) {
          inSingleQuote = !inSingleQuote;
        } else if (char == '"' && !inSingleQuote) {
          inDoubleQuote = !inDoubleQuote;
        }
      }

      // If we are inside a quote, we don't care about operators or parentheses.
      if (inSingleQuote || inDoubleQuote) {
        continue;
      }

      if (char == '(') {
        balance++;
      } else if (char == ')') {
        balance--;
      } else if (balance == 0) {
        // Potential logical operator found at the top level (not in parentheses or quotes).
        final match = logicalRegex.matchAsPrefix(filterStr, i);
        if (match != null) {
          final termString = filterStr.substring(lastSplit, i).trim();
          if (termString.isNotEmpty) {
            _addTerm(termString, termRegex);
          }

          final operator = match.group(1)!.toUpperCase();
          if (operator == '&&' || operator == 'AND') {
            _tokens.add(LogicalOperator.and);
          } else if (operator == '||' || operator == 'OR') {
            _tokens.add(LogicalOperator.or);
          }

          i = match.end - 1; // Move cursor past the operator
          lastSplit = match.end;
        }
      }
    }

    // Add the final term after the last operator.
    final lastTermString = filterStr.substring(lastSplit).trim();
    if (lastTermString.isNotEmpty) {
      _addTerm(lastTermString, termRegex);
    }
  }

  /// Adds a parsed term or a nested parser to the token list.
  void _addTerm(String termString, RegExp termRegex) {
    // Handle parenthesis by recursively parsing the inner content.
    if (termString.startsWith('(') && termString.endsWith(')')) {
      final innerFilter = termString.substring(1, termString.length - 1);
      final subParser = FilterParser(innerFilter, baseFields: baseFields);
      _tokens.add(subParser); // Add the sub-parser itself as a token.
    } else {
      final termMatch = termRegex.firstMatch(termString);
      if (termMatch != null) {
        var field = termMatch.group(1)!.trim();
        final operator = termMatch.group(2)!.trim();
        final value = termMatch.group(3)!.trim();

        // Parse field modifiers (e.g., name:lower -> field: name, modifier: lower)
        String? modifier;
        if (field.contains(':')) {
          final parts = field.split(':');
          field = parts[0];
          modifier = parts[1].toLowerCase();
        }

        // Check if this is an "any-of" operator
        final isAnyOf = operator.startsWith('?');

        _tokens.add(FilterTerm(
          field,
          operator,
          value.isEmpty ? null : value,
          modifier: modifier,
          isAnyOf: isAnyOf,
        ));
      } else {
        throw FormatException('Invalid filter term: "$termString"');
      }
    }
  }

  /// Determines the type of a value
  (ValueType, dynamic) _parseValue(String? value) {
    if (value == null || value.isEmpty) {
      return (ValueType.nullValue, null);
    }

    final trimmed = value.trim();

    // Check for null literal
    if (trimmed.toLowerCase() == 'null') {
      return (ValueType.nullValue, null);
    }

    // Check for boolean literals
    if (trimmed.toLowerCase() == 'true') {
      return (ValueType.boolean, true);
    }
    if (trimmed.toLowerCase() == 'false') {
      return (ValueType.boolean, false);
    }

    // Check for numeric literals (integers and decimals, including negative)
    if (RegExp(r'^-?\d+\.?\d*$').hasMatch(trimmed)) {
      return (ValueType.number, trimmed);
    }

    // Everything else is treated as a string
    return (ValueType.string, trimmed);
  }

  /// A helper function to correctly quote a field for SQL based on whether it's
  /// a base field or a JSON field.
  String _quoteField(String field, {String? modifier}) {
    String fieldSql;

    if (baseFields.contains(field.toLowerCase())) {
      fieldSql = field;
    } else {
      // All other fields are assumed to be in the 'data' JSON column.
      fieldSql = "json_extract(services.data, '\$.$field')";
    }

    // Apply modifiers
    if (modifier != null) {
      switch (modifier) {
        case 'lower':
          fieldSql = 'LOWER($fieldSql)';
          break;
        case 'length':
          // For length, we need json_array_length instead of json_extract
          if (baseFields.contains(field.toLowerCase())) {
            // Base fields shouldn't have :length modifier, but handle gracefully
            fieldSql = 'LENGTH($fieldSql)';
          } else {
            fieldSql =
                "json_array_length(json_extract(services.data, '\$.$field'))";
          }
          break;
      }
    }

    return fieldSql;
  }

  /// Translates a PocketBase operator to its SQLite equivalent.
  String _translateOperator(String pbOperator) {
    // Strip the '?' prefix if present - we handle any-of differently
    final baseOp =
        pbOperator.startsWith('?') ? pbOperator.substring(1) : pbOperator;

    switch (baseOp.toUpperCase()) {
      case '~':
        return 'LIKE';
      case '!~':
        return 'NOT LIKE';
      default:
        return baseOp;
    }
  }

  /// Normalizes quotes in a value string to use single quotes for SQLite string literals.
  ///
  /// In SQLite:
  /// - Single quotes (') are used for string literals (values)
  /// - Double quotes (") are used for identifiers (column/table names)
  ///
  /// This method converts double-quoted values to single-quoted to prevent SQLite
  /// from misinterpreting values as identifiers, which can cause errors when the
  /// value happens to match a column name.
  ///
  /// Example: "value" -> 'value'
  String _normalizeValueQuotes(String value) {
    // Check if the value is wrapped in double quotes
    if (value.length >= 2 && value.startsWith('"') && value.endsWith('"')) {
      // Extract the content inside the double quotes
      final content = value.substring(1, value.length - 1);
      // Escape any single quotes in the content by doubling them (SQLite convention)
      final escapedContent = content.replaceAll("'", "''");
      // Wrap in single quotes
      return "'$escapedContent'";
    }
    // If already single-quoted or not quoted, return as-is
    return value;
  }

  /// Builds SQL for an "any-of" operator using EXISTS subquery.
  String _buildAnyOfSql(String field, String operator, String valueSql) {
    // Get the base operator without the '?' prefix
    final translatedOp = _translateOperator(operator);

    // Build the JSON field path for json_each
    final jsonPath = baseFields.contains(field.toLowerCase())
        ? field
        : "json_extract(services.data, '\$.$field')";

    return 'EXISTS (SELECT 1 FROM json_each($jsonPath) WHERE value $translatedOp $valueSql)';
  }

  /// Builds the final SQL string from the tokenized parts.
  String _buildSql() {
    final sqlParts = <String>[];
    for (final token in _tokens) {
      if (token is FilterTerm) {
        final fieldSql = _quoteField(token.field, modifier: token.modifier);
        final (valueType, parsedValue) = _parseValue(token.value);

        // Handle null comparisons
        if (valueType == ValueType.nullValue) {
          if (token.operator == '=' || token.operator == '?=') {
            sqlParts.add('$fieldSql IS NULL');
          } else if (token.operator == '!=' || token.operator == '?!=') {
            sqlParts.add('$fieldSql IS NOT NULL');
          } else {
            // Other operators with null don't make sense, but handle gracefully
            sqlParts.add('$fieldSql IS NULL');
          }
          continue;
        }

        final operatorSql = _translateOperator(token.operator);
        String valueSql;

        // Build value SQL based on type
        switch (valueType) {
          case ValueType.boolean:
            // SQLite uses 1/0 for booleans, but JSON stores true/false
            // For json_extract, we need to compare against JSON boolean
            if (!baseFields.contains(token.field.toLowerCase())) {
              valueSql = parsedValue == true ? 'true' : 'false';
            } else {
              valueSql = parsedValue == true ? '1' : '0';
            }
            break;
          case ValueType.number:
            valueSql = parsedValue.toString();
            break;
          case ValueType.string:
            valueSql = _normalizeValueQuotes(parsedValue as String);
            // PocketBase's LIKE operators (~ and !~) auto-wrap the value in '%'
            // if no wildcard is present.
            if (token.operator == '~' ||
                token.operator == '!~' ||
                token.operator == '?~' ||
                token.operator == '?!~') {
              // The value now has single quotes. Check if the content has a '%'.
              if (!valueSql.substring(1, valueSql.length - 1).contains('%')) {
                final unquotedValue =
                    valueSql.substring(1, valueSql.length - 1);
                // Re-quote with the wildcards.
                valueSql = "'%${unquotedValue.replaceAll("'", "''")}%'";
              }
            }
            break;
          case ValueType.nullValue:
            // Already handled above
            valueSql = 'NULL';
            break;
        }

        // Build the SQL - either normal or EXISTS for any-of
        if (token.isAnyOf) {
          sqlParts.add(_buildAnyOfSql(token.field, token.operator, valueSql));
        } else {
          sqlParts.add('$fieldSql $operatorSql $valueSql');
        }
      } else if (token is LogicalOperator) {
        sqlParts.add(token.toString());
      } else if (token is FilterParser) {
        // Recursively build the SQL for the sub-query and wrap it in parentheses.
        sqlParts.add('(${token.parse()})');
      }
    }
    return sqlParts.join(' ');
  }
}
