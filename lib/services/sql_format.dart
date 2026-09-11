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
  final n = compact.length;
  var i = 0;
  while (i < n) {
    final c = compact[i];
    final cu = compact.codeUnitAt(i);
    // 引号内的内容整体跳过：字符串 '...' / "..."、反引号标识符 `...` 里的
    // 括号与逗号不参与结构判断（否则 COMMENT '含(括号)' 会把层级算错）。
    if (cu == 0x27 || cu == 0x22 || cu == 0x60) {
      final start = i;
      i++;
      while (i < n) {
        final ch = compact.codeUnitAt(i);
        if (ch == 0x5C) {
          i = i + 2 <= n ? i + 2 : n;
          continue;
        }
        if (ch == cu) {
          i++;
          if (i < n && compact.codeUnitAt(i) == cu) {
            i++; // '' 转义
            continue;
          }
          break;
        }
        i++;
      }
      out.write(compact.substring(start, i));
      continue;
    }
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
    i++;
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
