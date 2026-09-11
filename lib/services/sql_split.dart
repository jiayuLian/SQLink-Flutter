/// 把一段可能包含多条语句的 SQL 文本按分号切分成语句列表。
///
/// 与朴素的 `split(';')` 不同，这里**识别字符串字面量、反引号标识符与注释**，
/// 因此 `SELECT * FROM t WHERE a='x;y'` 不会被误切成两条语句。
/// 对齐 Swift 版 QueryConsoleView.splitStatements。
library;

bool _isWs(String c) =>
    c == ' ' || c == '\t' || c == '\n' || c == '\r' || c == '\f' || c == '\v';

List<String> splitStatements(String text) {
  final out = <String>[];
  final buf = StringBuffer();
  var inSingle = false;
  var inDouble = false;
  var inBacktick = false;
  var inLineComment = false;
  var inBlockComment = false;

  void flush() {
    final t = buf.toString().trim();
    if (t.isNotEmpty) out.add(t);
    buf.clear();
  }

  // split('') 会把代理对拆成两半，但写回时仍是同一串，往返无损；
  // 这里只与 ASCII 字符比较，故可接受。
  final chars = text.split('');
  var i = 0;
  while (i < chars.length) {
    final c = chars[i];
    final next = i + 1 < chars.length ? chars[i + 1] : null;

    if (inLineComment) {
      buf.write(c);
      if (c == '\n') inLineComment = false;
      i++;
      continue;
    }
    if (inBlockComment) {
      buf.write(c);
      if (c == '*' && next == '/') {
        buf.write('/');
        inBlockComment = false;
        i += 2;
        continue;
      }
      i++;
      continue;
    }
    if (inSingle) {
      buf.write(c);
      if (c == r'\' && next != null) {
        buf.write(next);
        i += 2;
        continue;
      }
      if (c == "'") {
        if (next == "'") {
          buf.write("'");
          i += 2;
          continue;
        }
        inSingle = false;
      }
      i++;
      continue;
    }
    if (inDouble) {
      buf.write(c);
      if (c == r'\' && next != null) {
        buf.write(next);
        i += 2;
        continue;
      }
      if (c == '"') {
        if (next == '"') {
          buf.write('"');
          i += 2;
          continue;
        }
        inDouble = false;
      }
      i++;
      continue;
    }
    if (inBacktick) {
      buf.write(c);
      if (c == '`') {
        if (next == '`') {
          buf.write('`');
          i += 2;
          continue;
        }
        inBacktick = false;
      }
      i++;
      continue;
    }

    // 普通状态：识别注释 / 引号起始 / 语句分隔符。
    if (c == '-' && next == '-' && i + 2 < chars.length && _isWs(chars[i + 2])) {
      buf.write('--');
      buf.write(chars[i + 2]);
      inLineComment = true;
      i += 3;
      continue;
    }
    if (c == '#') {
      buf.write(c);
      inLineComment = true;
      i++;
      continue;
    }
    if (c == '/' && next == '*') {
      buf.write('/*');
      inBlockComment = true;
      i += 2;
      continue;
    }
    if (c == "'") {
      buf.write(c);
      inSingle = true;
      i++;
      continue;
    }
    if (c == '"') {
      buf.write(c);
      inDouble = true;
      i++;
      continue;
    }
    if (c == '`') {
      buf.write(c);
      inBacktick = true;
      i++;
      continue;
    }
    if (c == ';') {
      flush();
      i++;
      continue;
    }
    buf.write(c);
    i++;
  }
  flush();
  return out;
}
