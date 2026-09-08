/// 筛选条件模型（对齐 Swift 的 FilterCondition / FilterOperator / FilterLogic）。
class FilterCondition {
  String field;
  FilterOp op;
  String value;
  bool enabled;
  FilterLogic logic; // 仅对非首条条件生效

  FilterCondition({
    this.field = '',
    this.op = FilterOp.contains,
    this.value = '',
    this.enabled = true,
    this.logic = FilterLogic.and,
  });
}

enum FilterOp {
  equal,
  notEqual,
  lessThan,
  lessOrEqual,
  greaterThan,
  greaterOrEqual,
  contains,
  notContains,
  startsWith,
  endsWith,
  isNull,
  isNotNull,
  isEmpty,
  isNotEmpty,
  custom,
}

extension FilterOpX on FilterOp {
  String get label {
    switch (this) {
      case FilterOp.equal:
        return '=';
      case FilterOp.notEqual:
        return '≠';
      case FilterOp.lessThan:
        return '<';
      case FilterOp.lessOrEqual:
        return '≤';
      case FilterOp.greaterThan:
        return '>';
      case FilterOp.greaterOrEqual:
        return '≥';
      case FilterOp.contains:
        return '包含';
      case FilterOp.notContains:
        return '不包含';
      case FilterOp.startsWith:
        return '开头是';
      case FilterOp.endsWith:
        return '结尾是';
      case FilterOp.isNull:
        return '为空(NULL)';
      case FilterOp.isNotNull:
        return '非空';
      case FilterOp.isEmpty:
        return '为空串';
      case FilterOp.isNotEmpty:
        return '非空串';
      case FilterOp.custom:
        return '自定义 SQL';
    }
  }

  /// 是否需要在 UI 中显示「值」输入框。
  bool get needsValue =>
      this != FilterOp.isNull &&
      this != FilterOp.isNotNull &&
      this != FilterOp.isEmpty &&
      this != FilterOp.isNotEmpty;
}

enum FilterLogic { and, or }

extension FilterLogicX on FilterLogic {
  String get label => this == FilterLogic.or ? 'OR' : 'AND';
}

/// 按字段/运算符/值拼接 WHERE 片段（对齐 Swift buildWhereClause）。
/// 首条不加前导关系；其余用自身 logic 与前一项连接，并用括号包裹避免优先级歧义。
String? buildWhereClause(List<FilterCondition> conditions) {
  final parts = <String>[];
  for (final c in conditions) {
    if (!c.enabled || c.field.isEmpty) continue;
    final f = '`${c.field.replaceAll('`', '``')}`';
    final part = _sqlPart(f, c);
    if (part.isEmpty) continue;
    if (parts.isEmpty) {
      parts.add('($part)');
    } else {
      parts.add('${c.logic.label} ($part)');
    }
  }
  return parts.isEmpty ? null : parts.join(' ');
}

String _sqlPart(String f, FilterCondition c) {
  switch (c.op) {
    case FilterOp.equal:
      return '$f = ${_quote(c.value)}';
    case FilterOp.notEqual:
      return '$f != ${_quote(c.value)}';
    case FilterOp.lessThan:
      return '$f < ${_quote(c.value)}';
    case FilterOp.lessOrEqual:
      return '$f <= ${_quote(c.value)}';
    case FilterOp.greaterThan:
      return '$f > ${_quote(c.value)}';
    case FilterOp.greaterOrEqual:
      return '$f >= ${_quote(c.value)}';
    case FilterOp.contains:
      return "$f LIKE '%${_like(c.value)}%' ESCAPE '\\\\'";
    case FilterOp.notContains:
      return "$f NOT LIKE '%${_like(c.value)}%' ESCAPE '\\\\'";
    case FilterOp.startsWith:
      return "$f LIKE '${_like(c.value)}%' ESCAPE '\\\\'";
    case FilterOp.endsWith:
      return "$f LIKE '%${_like(c.value)}' ESCAPE '\\\\'";
    case FilterOp.isNull:
      return '$f IS NULL';
    case FilterOp.isNotNull:
      return '$f IS NOT NULL';
    case FilterOp.isEmpty:
      return "$f = ''";
    case FilterOp.isNotEmpty:
      return "$f != ''";
    case FilterOp.custom:
      return c.value;
  }
}

String? buildOrderBy(String field, String dir) {
  if (field.isEmpty) return null;
  final f = '`${field.replaceAll('`', '``')}`';
  final d = dir.toUpperCase() == 'DESC' ? 'DESC' : 'ASC';
  return '$f $d';
}

String _quote(String v) {
  final e = v.replaceAll('\\', '\\\\').replaceAll("'", "\\'");
  return "'$e'";
}

String _like(String v) => v
    .replaceAll('\\', '\\\\')
    .replaceAll("'", "''")
    .replaceAll('%', r'\%')
    .replaceAll('_', r'\_');
