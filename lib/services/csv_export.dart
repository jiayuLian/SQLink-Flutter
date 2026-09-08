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
