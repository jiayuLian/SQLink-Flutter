/// 极简 CSV 导出（兼容逗号/引号/换行转义）。
String toCsv(List<String> columns, List<Map<String, String?>> rows) {
  final buf = StringBuffer();
  buf.writeln(columns.map(_cell).join(','));
  for (final row in rows) {
    buf.writeln(columns.map((c) => _cell(row[c])).join(','));
  }
  return buf.toString();
}

String _cell(String? v) {
  if (v == null) return '';
  if (v.contains(',') || v.contains('"') || v.contains('\n') || v.contains('\r')) {
    return '"${v.replaceAll('"', '""')}"';
  }
  return v;
}

/// SQL (INSERT) 导出，对齐 Swift ExportUtils.buildSQL。
/// 生成形如：INSERT INTO `t` (`a`,`b`) VALUES ('1','x'), ('2','y');
String toSql(
  String insertInto,
  List<String> columns,
  List<Map<String, String?>> rows,
) {
  final escId = (String s) => '`${s.replaceAll('`', '``')}`';
  final quote = (String? v) {
    // 对齐 Swift ExportUtils.buildSQL：空字符串与 NULL 统一导出为 NULL
    // （注意：重导入时 '' 会变成 NULL，这是 Swift 的既有行为，这里保持一致）。
    if (v == null || v.isEmpty) return 'NULL';
    final escaped = v.replaceAll('\\', '\\\\').replaceAll("'", "\\'");
    return "'$escaped'";
  };
  final cols = columns.map(escId).join(', ');
  final lines = rows.map((r) {
    final vals = columns.map((c) => quote(r[c])).join(', ');
    return 'INSERT INTO ${escId(insertInto)} ($cols) VALUES ($vals);';
  });
  return lines.join('\n');
}

