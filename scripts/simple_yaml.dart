/// A deliberately small YAML-subset reader for the release and traceability
/// tooling in `scripts/`.
///
/// It exists so these scripts need no new package dependency (and so
/// `pubspec.yaml` / `pubspec.lock` stay untouched). It reads exactly the
/// shapes used by `pubspec.lock` and by `docs/traceability/*.yaml`:
///
/// * block mappings (`key: value`, `key:` + an indented block);
/// * block sequences (`- scalar`, `- key: value` item mappings), indented
///   under their key or at the same indent as it;
/// * plain, single-quoted and double-quoted scalars; `true`/`false`,
///   `null`/`~`, integers; the empty flow collections `[]` and `{}`;
/// * full-line comments and ` #` trailing comments outside quotes.
///
/// Anything else (anchors, multi-line scalars, flow collections with
/// content, documents markers, tabs for indentation) throws
/// [YamlSubsetException] rather than being guessed at: these files are
/// release evidence, and a silently mis-read file is worse than a loud
/// failure.
library;

class YamlSubsetException implements Exception {
  YamlSubsetException(this.message, [this.line]);

  final String message;
  final int? line;

  @override
  String toString() => line == null
      ? 'YamlSubsetException: $message'
      : 'YamlSubsetException (line $line): $message';
}

class _Line {
  _Line(this.number, this.indent, this.text);

  final int number;
  final int indent;
  final String text;
}

/// Parses [source] and returns a `Map<String, Object?>`, `List<Object?>`,
/// scalar, or `null` for an empty document.
Object? parseYamlSubset(String source) {
  final lines = <_Line>[];
  final raw = source.replaceAll('\r\n', '\n').split('\n');
  for (var i = 0; i < raw.length; i++) {
    final line = raw[i];
    if (line.contains('\t') && line.trimLeft().startsWith('\t')) {
      throw YamlSubsetException('tab indentation is not supported', i + 1);
    }
    final stripped = _stripComment(line, i + 1).trimRight();
    if (stripped.trim().isEmpty) continue;
    if (stripped.trim() == '---' || stripped.trim() == '...') {
      throw YamlSubsetException('document markers are not supported', i + 1);
    }
    final indent = stripped.length - stripped.trimLeft().length;
    lines.add(_Line(i + 1, indent, stripped.trimLeft()));
  }
  if (lines.isEmpty) return null;
  final parser = _Parser(lines);
  final value = parser.parseBlock(lines.first.indent);
  if (parser.index != lines.length) {
    final line = lines[parser.index];
    throw YamlSubsetException('unexpected content "${line.text}"', line.number);
  }
  return value;
}

String _stripComment(String line, int number) {
  String? quote;
  for (var i = 0; i < line.length; i++) {
    final c = line[i];
    if (quote != null) {
      if (quote == '"' && c == '\\') {
        i++;
        continue;
      }
      if (c == quote) quote = null;
      continue;
    }
    if (c == '"' || c == "'") {
      // A quote opens a quoted scalar only at the start of a token, so the
      // apostrophe in a plain scalar such as `don't` is left alone.
      if (i == 0 || line[i - 1] == ' ') quote = c;
      continue;
    }
    if (c == '#' && (i == 0 || line[i - 1] == ' ')) return line.substring(0, i);
  }
  return line;
}

class _Parser {
  _Parser(this.lines);

  final List<_Line> lines;
  int index = 0;

  bool _isListItem(String text) => text == '-' || text.startsWith('- ');

  Object? parseBlock(int indent) {
    final first = lines[index];
    if (first.indent != indent) {
      throw YamlSubsetException('inconsistent indentation', first.number);
    }
    return _isListItem(first.text) ? _parseList(indent) : _parseMap(indent);
  }

  List<Object?> _parseList(int indent) {
    final result = <Object?>[];
    while (index < lines.length) {
      final line = lines[index];
      if (line.indent < indent) break;
      if (line.indent > indent) {
        throw YamlSubsetException('unexpected indentation', line.number);
      }
      if (!_isListItem(line.text)) break;
      final rest = line.text == '-' ? '' : line.text.substring(2).trimLeft();
      if (rest.isEmpty) {
        index++;
        result.add(_nestedOrNull(indent));
      } else if (_splitKey(rest, line.number) != null) {
        // An item mapping: re-read this line as a key at the item's column.
        final column = indent + (line.text.length - rest.length);
        lines[index] = _Line(line.number, column, rest);
        result.add(_parseMap(column));
      } else {
        index++;
        result.add(_scalar(rest, line.number));
      }
    }
    return result;
  }

  Map<String, Object?> _parseMap(int indent) {
    final result = <String, Object?>{};
    while (index < lines.length) {
      final line = lines[index];
      if (line.indent < indent) break;
      if (line.indent > indent) {
        throw YamlSubsetException('unexpected indentation', line.number);
      }
      if (_isListItem(line.text)) break;
      final split = _splitKey(line.text, line.number);
      if (split == null) {
        throw YamlSubsetException(
          'expected "key: value", got "${line.text}"',
          line.number,
        );
      }
      final key = split.$1;
      if (result.containsKey(key)) {
        throw YamlSubsetException('duplicate key "$key"', line.number);
      }
      index++;
      if (split.$2.isEmpty) {
        // A block value: deeper-indented block, or a list at the same indent.
        if (index < lines.length &&
            lines[index].indent == indent &&
            _isListItem(lines[index].text)) {
          result[key] = _parseList(indent);
        } else {
          result[key] = _nestedOrNull(indent);
        }
      } else {
        result[key] = _scalar(split.$2, line.number);
      }
    }
    return result;
  }

  Object? _nestedOrNull(int parentIndent) {
    if (index < lines.length && lines[index].indent > parentIndent) {
      return parseBlock(lines[index].indent);
    }
    return null;
  }

  /// Returns (key, rest) when [text] starts with a mapping key.
  (String, String)? _splitKey(String text, int number) {
    String key;
    String rest;
    if (text.startsWith('"') || text.startsWith("'")) {
      final end = _closingQuote(text, number);
      final after = text.substring(end + 1);
      if (!(after == ':' || after.startsWith(': '))) return null;
      key = _scalar(text.substring(0, end + 1), number).toString();
      rest = after.substring(1).trim();
    } else {
      final colon = text.indexOf(': ');
      if (colon > 0) {
        key = text.substring(0, colon);
        rest = text.substring(colon + 2).trim();
      } else if (text.endsWith(':')) {
        key = text.substring(0, text.length - 1);
        rest = '';
      } else {
        return null;
      }
    }
    return (key, rest);
  }

  int _closingQuote(String text, int number) {
    final quote = text[0];
    for (var i = 1; i < text.length; i++) {
      if (quote == '"' && text[i] == '\\') {
        i++;
        continue;
      }
      if (text[i] == quote) {
        if (quote == "'" && i + 1 < text.length && text[i + 1] == "'") {
          i++;
          continue;
        }
        return i;
      }
    }
    throw YamlSubsetException('unterminated quoted string', number);
  }

  Object? _scalar(String text, int number) {
    if (text.startsWith('"') || text.startsWith("'")) {
      final end = _closingQuote(text, number);
      if (end != text.length - 1) {
        throw YamlSubsetException('content after a quoted string', number);
      }
      final body = text.substring(1, end);
      if (text[0] == "'") return body.replaceAll("''", "'");
      return body.replaceAllMapped(RegExp(r'\\(.)'), (m) {
        switch (m[1]) {
          case 'n':
            return '\n';
          case 't':
            return '\t';
          case '"':
            return '"';
          case '\\':
            return '\\';
          default:
            throw YamlSubsetException('unsupported escape \\${m[1]}', number);
        }
      });
    }
    if (text == '[]') return <Object?>[];
    if (text == '{}') return <String, Object?>{};
    if (text.startsWith('[') ||
        text.startsWith('{') ||
        text.startsWith('&') ||
        text.startsWith('*') ||
        text.startsWith('|') ||
        text.startsWith('>') ||
        text.startsWith('!')) {
      throw YamlSubsetException('unsupported YAML construct "$text"', number);
    }
    if (text == 'true') return true;
    if (text == 'false') return false;
    if (text == 'null' || text == '~') return null;
    if (RegExp(r'^-?\d+$').hasMatch(text)) return int.parse(text);
    return text;
  }
}
