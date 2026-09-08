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
    // 正确性优先：仅真正的 NULL 导出为 NULL；空字符串 '' 导出为 ''（而非 NULL），
    // 否则重导入时空串会变成 NULL，造成数据失真。
    if (v == null) return 'NULL';
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

