/// SQL 文本整理工具（对齐 Swift TableDetailView 的 formatCreateTable）。

/// 把 `SHOW CREATE TABLE` 的整段语句整理成带缩进的多行文本
/// （只增删空白，不改变 SQL 语义）：
/// - 压平所有空白；
/// - 在第一个 `(` 后换行、顶层 `,` 后换行、末尾 `)` 前换行；
/// - 把 ENGINE / DEFAULT CHARSET / COLLATE / AUTO_INCREMENT / ROW_FORMAT / COMMENT
///   这些表选项各自单独成行。
String formatCreateTable(String raw) {
  final compact = raw.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (compact.isEmpty) return raw;

  final out = StringBuffer();
  var depth = 0;
  for (var i = 0; i < compact.length; i++) {
    final c = compact[i];
    if (c == '(') {
      out.write('(');
      depth += 1;
      if (depth == 1) out.write('\n  ');
    } else if (c == ')') {
      depth -= 1;
      out.write(depth <= 0 ? '\n)' : ')');
      if (depth < 0) depth = 0;
    } else if (c == ',') {
      out.write(depth == 1 ? ',\n  ' : ',');
    } else {
      out.write(c);
    }
  }

  var s = out.toString();
  const opts = <List<String>>[
    ['ENGINE', r'\w+'],
    ['DEFAULT CHARSET', r'\w+'],
    ['COLLATE', r'\w+'],
    ['AUTO_INCREMENT', r'\d+'],
    ['ROW_FORMAT', r'\w+'],
    ['COMMENT', r"'[^']*'"],
  ];
  for (final o in opts) {
    final re = RegExp(
      r'(\s+)' + RegExp.escape(o[0]) + r'(\s*=\s*' + o[1] + r')',
    );
    s = s.replaceAllMapped(re, (m) => '\n${o[0]}${m.group(2)}');
  }
  return s;
}
