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

/// 表「筛选 & 排序」状态。结构页与数据页共享同一实例，改动互通（对齐 Swift
/// TableDetailView ↔ TableDataView 通过 @Binding 共享筛选状态的做法）。
class TableFilterState {
  List<FilterCondition> conditions = [];
  String? where;
  String? order;
  String sortField = '';
  String sortDir = 'ASC';

  bool get hasFilter =>
      (where != null && where!.isNotEmpty) || (order != null && order!.isNotEmpty);

  void clear() {
    conditions = [];
    where = null;
    order = null;
    sortField = '';
    sortDir = 'ASC';
  }
}

/// 运算符枚举按 Swift FilterOperator 的顺序排列（含 不开始于/不结束于/在列表/不在列表）。
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
  notStartsWith,
  endsWith,
  notEndsWith,
  isNull,
  isNotNull,
  isEmpty,
  isNotEmpty,
  inList,
  notInList,
  custom,
}

extension FilterOpX on FilterOp {
  /// 文案对齐 Swift FilterOperator.label。
  String get label {
    switch (this) {
      case FilterOp.equal:
        return '等于';
      case FilterOp.notEqual:
        return '不等于';
      case FilterOp.lessThan:
        return '小于';
      case FilterOp.lessOrEqual:
        return '小于等于';
      case FilterOp.greaterThan:
        return '大于';
      case FilterOp.greaterOrEqual:
        return '大于等于';
      case FilterOp.contains:
        return '包含';
      case FilterOp.notContains:
        return '不包含';
      case FilterOp.startsWith:
        return '开始以';
      case FilterOp.notStartsWith:
        return '不开始于';
      case FilterOp.endsWith:
        return '结束于';
      case FilterOp.notEndsWith:
        return '不结束于';
      case FilterOp.isNull:
        return '是 null';
      case FilterOp.isNotNull:
        return '不是 null';
      case FilterOp.isEmpty:
        return '是空的';
      case FilterOp.isNotEmpty:
        return '不是空的';
      case FilterOp.inList:
        return '在列表';
      case FilterOp.notInList:
        return '不在列表';
      case FilterOp.custom:
        return '自定义';
    }
  }

  /// 是否需要在 UI 中显示「值」输入框（对齐 Swift FilterOperator.needsValue）。
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
    case FilterOp.notStartsWith:
      return "$f NOT LIKE '${_like(c.value)}%' ESCAPE '\\\\'";
    case FilterOp.endsWith:
      return "$f LIKE '%${_like(c.value)}' ESCAPE '\\\\'";
    case FilterOp.notEndsWith:
      return "$f NOT LIKE '%${_like(c.value)}' ESCAPE '\\\\'";
    case FilterOp.isNull:
      return '$f IS NULL';
    case FilterOp.isNotNull:
      return '$f IS NOT NULL';
    case FilterOp.isEmpty:
      return "$f = ''";
    case FilterOp.isNotEmpty:
      return "$f != ''";
    case FilterOp.inList:
      final vals = _splitValues(c.value);
      if (vals.isEmpty) return '';
      return '$f IN (${vals.join(', ')})';
    case FilterOp.notInList:
      final vals = _splitValues(c.value);
      if (vals.isEmpty) return '';
      return '$f NOT IN (${vals.join(', ')})';
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

/// 「在列表 / 不在列表」：逗号分隔，逐项去空格后转义（对齐 Swift inList / notInList）。
List<String> _splitValues(String v) => v
    .split(',')
    .map((s) => s.trim())
    .where((s) => s.isNotEmpty)
    .map(_quote)
    .toList();

String _quote(String v) {
  final e = v.replaceAll('\\', '\\\\').replaceAll("'", "\\'");
  return "'$e'";
}

/// LIKE 字面量转义（对齐 Swift quoteLikeLiteral：先转义反斜杠，再转义引号与通配符）。
String _like(String v) => v
    .replaceAll('\\', '\\\\')
    .replaceAll("'", "\\'")
    .replaceAll('%', r'\%')
    .replaceAll('_', r'\_');
