import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import '../services/mysql_service.dart';
import '../models/connection.dart' show ColumnInfo;
import '../services/csv_export.dart';
import '../services/sql_split.dart';
import '../settings/app_settings.dart';
import '../widgets/result_grid.dart';

// 关键词含多词短语（如 ORDER BY），便于输入 OR 即提示 ORDER BY。
const _keywords = [
  'SELECT', 'SELECT *', 'FROM', 'WHERE', 'INSERT INTO', 'VALUES', 'UPDATE', 'SET',
  'DELETE FROM', 'CREATE TABLE', 'DROP TABLE', 'ALTER TABLE', 'DATABASE', 'TABLE',
  'LIMIT', 'ORDER BY', 'GROUP BY', 'HAVING', 'UNION', 'UNION ALL', 'DISTINCT',
  'JOIN', 'LEFT JOIN', 'RIGHT JOIN', 'INNER JOIN', 'ON', 'AS', 'AND', 'OR', 'NOT',
  'NULL', 'IS NULL', 'IS NOT NULL', 'LIKE', 'IN', 'BETWEEN', 'ASC', 'DESC',
  'COUNT', 'SUM', 'AVG', 'MAX', 'MIN', 'EXISTS', 'CASE', 'WHEN', 'THEN', 'ELSE', 'END',
];

class QueryConsoleScreen extends StatefulWidget {
  final MySQLService service;
  final String? db;
  final String? defaultTable;
  const QueryConsoleScreen({
    super.key,
    required this.service,
    this.db,
    this.defaultTable,
  });

  @override
  State<QueryConsoleScreen> createState() => _QueryConsoleScreenState();
}

class _QueryConsoleScreenState extends State<QueryConsoleScreen> {
  final _sql = TextEditingController();
  List<ResultSetData>? _outcomes;
  String? _error;
  String? _message;
  bool _running = false;
  List<String> _tables = [];
  List<ColumnInfo> _contextColumns = [];
  String _contextTable = '';
  // 自动从当前 SQL 中提取表名并加载列，用于字段补全（不依赖手动选上下文表）。
  final Map<String, List<ColumnInfo>> _sqlTableColumns = {};

  /// 缓存的设置对象。dispose 时不能再通过 context 取 Provider，
  /// 故在 initState 取一次并在整个生命周期复用。
  late AppSettings _settings;

  // 可编辑结果集（对齐 Swift 的 edit-from-result）。
  bool _canEdit = false;
  bool _editMode = false;
  List<String> _editColNames = [];
  List<Map<String, String?>> _editRowsOriginal = [];
  List<List<String?>> _editingRows = [];
  String? _editTable;
  String? _editDB;
  String? _editPK;
  int _editPKIndex = -1;
  bool _hasChanges = false;
  String? _editMessage;
  String? _editError;
  bool _saving = false;
  final Map<String, TextEditingController> _editControllers = {};

  @override
  void initState() {
    super.initState();
    _settings = Provider.of<AppSettings>(context, listen: false);
    _loadTables();
    _loadSavedSql();
    // 输入框变化时刷新候选提示。
    _sql.addListener(_onSqlChanged);
  }

  void _onSqlChanged() {
    if (mounted) setState(() {});
    _loadColumnsForSqlTables();
  }

  /// 从 SQL 中提取表名（支持 `db.table`、反引号全限定、裸标识符），
  /// 返回 表名 -> 库名(可空)。用于加载列信息做字段补全。
  Map<String, String?> _extractSqlTables() {
    final sql = _sql.text;
    final map = <String, String?>{};
    final regex = RegExp(
      r'\b(from|join|update|into)\b\s+([^\s;]+)',
      caseSensitive: false,
      multiLine: true,
    );
    for (final m in regex.allMatches(sql)) {
      // 去掉反引号与结尾标点（如 FROM t, u 里的逗号）。
      var raw = m.group(2)!.replaceAll('`', '');
      raw = raw.replaceAll(RegExp(r'[,.].*$'), '');
      if (raw.isEmpty) continue;
      final parts = raw.split('.');
      final db = parts.length >= 2 ? parts[0] : null;
      final table = parts.last;
      if (table.isNotEmpty) map[table] = db;
    }
    return map;
  }

  Future<void> _loadColumnsForSqlTables() async {
    final tables = _extractSqlTables();
    // 额外识别文本中直接出现的表名（如刚通过补全插入、尚未写 FROM 的场景），
    // 以便接着补全该表的字段。
    for (final m in RegExp(r'[A-Za-z0-9_$]+').allMatches(_sql.text)) {
      final word = m.group(0)!.toLowerCase();
      for (final t in _tables) {
        if (t.toLowerCase() == word && !tables.containsKey(t)) {
          tables[t] = null;
          break;
        }
      }
    }
    if (tables.isEmpty) return;
    for (final entry in tables.entries) {
      final table = entry.key;
      if (_sqlTableColumns.containsKey(table)) continue;
      // 优先用 SQL 中显式限定的库名，否则回退到当前控制台所在库。
      final db = entry.value ?? widget.db;
      if (db == null || db.isEmpty) continue;
      try {
        final cols = await widget.service.listColumns(db, table);
        if (mounted) setState(() => _sqlTableColumns[table] = cols);
      } catch (_) {
        // 忽略无权限或不存在的表。
      }
    }
  }

  @override
  void dispose() {
    // 对齐 Swift QueryConsoleView.onDisappear：退出控制台时保存当前 SQL。
    // （仅表内入口按表记忆；dispose 不能 await，故不等待落盘结果。）
    if (_rememberSqlByTable && _settings.autoSaveSQL) {
      _settings.saveSQL(widget.db ?? '_', widget.defaultTable!, _sql.text);
    }
    _sql.removeListener(_onSqlChanged);
    _sql.dispose();
    for (final c in _editControllers.values) c.dispose();
    _editControllers.clear();
    super.dispose();
  }

  Future<void> _loadTables() async {
    if (widget.db == null || widget.db!.isEmpty) return;
    try {
      final list = await widget.service.listTables(widget.db!);
      if (mounted) {
        setState(() => _tables = list.map((m) => m['name'] ?? '').toList());
        // 若提供了默认表且存在于列表中，自动设为上下文表。
        if (widget.defaultTable != null && _tables.contains(widget.defaultTable)) {
          _contextTable = widget.defaultTable!;
          _loadContextColumns();
        }
        // 兜底：即使下拉框没显示默认表，也加载其字段用于补全。
        if (widget.defaultTable != null &&
            widget.defaultTable!.isNotEmpty &&
            !_sqlTableColumns.containsKey(widget.defaultTable)) {
          _loadColumnsForTable(widget.defaultTable!);
        }
      }
    } catch (_) {
      // 表名仅用于补全提示，失败忽略。
    }
  }

  Future<void> _loadColumnsForTable(String table) async {
    if (widget.db == null || widget.db!.isEmpty || table.isEmpty) return;
    try {
      final cols = await widget.service.listColumns(widget.db!, table);
      if (mounted) setState(() => _sqlTableColumns[table] = cols);
    } catch (_) {
      // 忽略。
    }
  }

  /// 是否按「表」记忆 SQL：仅当从某张表内打开控制台（有 defaultTable）时启用。
  /// 从表列表页右上角打开（无默认表）时不记忆/不恢复，控制台始终空白，由用户自行输入。
  bool get _rememberSqlByTable =>
      widget.defaultTable != null && widget.defaultTable!.isNotEmpty;

  Future<void> _loadSavedSql() async {
    if (!_rememberSqlByTable) return;
    if (!_settings.autoSaveSQL) return;
    final saved =
        await _settings.getSavedSQL(widget.db ?? '_', widget.defaultTable!);
    if (saved != null && saved.isNotEmpty && mounted) {
      _sql.text = saved;
    }
  }

  Future<void> _saveSqlIfNeeded() async {
    if (!_rememberSqlByTable) return;
    if (_settings.autoSaveSQL) {
      await _settings.saveSQL(
          widget.db ?? '_', widget.defaultTable!, _sql.text);
    }
  }

  Future<void> _loadContextColumns() async {
    if (widget.db == null || widget.db!.isEmpty || _contextTable.isEmpty) {
      setState(() => _contextColumns = []);
      return;
    }
    try {
      final cols = await widget.service.listColumns(widget.db!, _contextTable);
      if (mounted) setState(() => _contextColumns = cols);
    } catch (_) {
      if (mounted) setState(() => _contextColumns = []);
    }
  }

  /// 取出光标前正在输入的「限定符 + 当前词」片段。
  /// - `a.` / `a.id` / `db.table.` → (限定符='a'/'a'/'db.table', 词=''/'id'/''')
  /// - `SEL` / `lvv_c` → (null, 'SEL'/'lvv_c')
  /// 分隔符用 *（可零个）——否则在输入框最开头打字（如 SEL）时匹配不到，
  /// 补全会始终为空。
  (String? qualifier, String word) _tokenAt(String text) {
    final dot = RegExp(r'([^\s,()`]*)\.([^\s,()`.=]*)$').firstMatch(text);
    if (dot != null) {
      return (
        dot.group(1)!.replaceAll('`', ''),
        dot.group(2)!.replaceAll('`', ''),
      );
    }
    final plain = RegExp(r'[\s,()`.=]*([^\s,()`.=]*)$').firstMatch(text);
    return (null, (plain?.group(1) ?? '').replaceAll('`', ''));
  }

  /// 解析 SQL 中的「别名/表名 → 真实表名（可带库前缀）」映射，
  /// 用于 `alias.` / `table.` 形式输入时补全对应表的字段。
  /// 支持 `FROM t a`、`FROM t AS a`、`JOIN t b ON ...`、逗号连接 `FROM t1 a, t2 b`、
  /// 以及 `FROM db.t a`（带库前缀）。
  Map<String, String> _aliasToTable() {
    final sql = _sql.text;
    final map = <String, String>{};
    const reserved = {
      'where', 'on', 'set', 'inner', 'left', 'right', 'cross', 'full', 'outer',
      'order', 'group', 'having', 'limit', 'join', 'as', 'and', 'or', 'not',
      'using', 'natural', 'union', 'asc', 'desc', 'values', 'by',
      'from', 'into', 'update', // 逗号连接时这些词可能出现在别名位置，需排除
    };
    final regex = RegExp(
      r'(?:\b(from|join|into|update)\b\s+|(,\s*))'
      r'`?((?:[A-Za-z0-9_\$]+\.)?[A-Za-z0-9_\$]+)`?'
      r'(?:\s+as\s+|\s+)`?([A-Za-z0-9_\$]+)`?',
      caseSensitive: false,
    );
    for (final m in regex.allMatches(sql)) {
      final tableExpr = m.group(3)!;
      final alias = m.group(4)!;
      if (reserved.contains(alias.toLowerCase())) continue;
      map[alias.toLowerCase()] = tableExpr;
    }
    return map;
  }

  /// 给定 `alias.` 或 `table.` 中的限定符，返回其可补全的字段列表。
  /// 别名 → 映射回真实表；直接表名（可带库前缀）则去掉库前缀按表名查。
  List<String> _columnsForQualifier(String qualifier) {
    final aliasMap = _aliasToTable();
    String tableRef = aliasMap[qualifier.toLowerCase()] ?? qualifier;
    if (tableRef.contains('.')) {
      final parts = tableRef.split('.');
      if (parts.length >= 2) tableRef = parts[parts.length - 1];
    }
    for (final entry in _sqlTableColumns.entries) {
      if (entry.key.toLowerCase() == tableRef.toLowerCase()) {
        return entry.value.map((c) => c.field).toList();
      }
    }
    if (_contextTable.toLowerCase() == tableRef.toLowerCase() && _contextColumns.isNotEmpty) {
      return _contextColumns.map((c) => c.field).toList();
    }
    return [];
  }

  /// 子序列模糊匹配：query 的字符按顺序出现在 s 中即算匹配
  /// （如 lvv_c → lvv_exchange_record）。
  bool _isSubsequence(String query, String s) {
    var i = 0;
    for (var j = 0; j < s.length && i < query.length; j++) {
      if (s[j] == query[i]) i++;
    }
    return i == query.length;
  }

  /// 候选池：
  /// - 若当前片段带限定符（`alias.` / `table.`）→ 只补全该限定符对应表的字段；
  /// - 否则按三层（关键词 → 表名 → 字段）补全：
  ///   关键词前缀匹配（含 ORDER BY 等多词短语）；表名前缀/包含/模糊子序列（≥3 字符）；
  ///   字段（上下文表 / SQL 中引用表的列）前缀/包含。
  List<String> get _suggestions {
    final cursor = _sql.selection.baseOffset.clamp(0, _sql.text.length);
    final (qualifier, w) = _tokenAt(_sql.text.substring(0, cursor));
    if (w.isEmpty && (qualifier == null || qualifier.isEmpty)) return [];
    final wu = w.toUpperCase();
    final out = <String>[];
    final seen = <String>{};
    void add(String item) {
      final u = item.toUpperCase();
      if (u == wu || !seen.add(u)) return;
      out.add(item);
    }

    // 1) 限定符补全：alias. / table. → 该表字段
    if (qualifier != null && qualifier.isNotEmpty) {
      final fields = _columnsForQualifier(qualifier);
      if (fields.isEmpty) return [];
      if (wu.isEmpty) {
        for (final f in fields) add(f);
      } else {
        for (final f in fields) {
          if (f.toUpperCase().startsWith(wu)) add(f);
        }
        if (wu.length >= 2) {
          for (final f in fields) {
            if (f.toUpperCase().contains(wu)) add(f);
          }
        }
      }
      return out.take(12).toList();
    }

    // 2) 关键词
    for (final k in _keywords) {
      if (k.toUpperCase().startsWith(wu)) add(k);
    }
    // 3) 表名
    for (final t in _tables) {
      if (t.toUpperCase().startsWith(wu)) add(t);
    }
    if (wu.length >= 2) {
      for (final t in _tables) {
        if (t.toUpperCase().contains(wu)) add(t);
      }
    }
    if (wu.length >= 3) {
      for (final t in _tables) {
        if (_isSubsequence(wu, t.toUpperCase())) add(t);
      }
    }
    // 4) 字段（上下文表 / SQL 中引用表的列）
    final fields = <String>{
      ..._contextColumns.map((c) => c.field),
      ..._sqlTableColumns.values.expand((c) => c.map((i) => i.field)),
    };
    for (final f in fields) {
      if (f.toUpperCase().startsWith(wu)) add(f);
    }
    if (wu.length >= 2) {
      for (final f in fields) {
        if (f.toUpperCase().contains(wu)) add(f);
      }
    }
    return out.take(12).toList();
  }

  Future<void> _run() async {
    // 收起软键盘，避免遮挡结果。
    FocusManager.instance.primaryFocus?.unfocus();
    final sql = _sql.text.trim();
    if (sql.isEmpty) return;
    // 全局历史始终记录（对齐 Swift QueryHistory.add，不受 autoSaveSQL 影响）。
    await _settings.addHistory(sql);
    await _saveSqlIfNeeded();
    setState(() {
      _running = true;
      _error = null;
      _message = null;
      _outcomes = null;
      _canEdit = false;
      _editMode = false;
      _editingRows = [];
      _editMessage = null;
      _editError = null;
    });
    try {
      final outs = await widget.service.execute(sql);
      final resultSets = outs.where((o) => o.isResultSet).toList();
      final okCount = outs.where((o) => !o.isResultSet).length;
      final msg = okCount > 0 && resultSets.isEmpty
          ? '执行成功（${outs.length} 条语句）'
          : resultSets.isNotEmpty
              ? '返回 ${resultSets.last.rows.length} 行'
              : '执行成功';
      if (mounted) setState(() => _outcomes = outs);
      // 单条语句、且产生唯一结果集时才尝试判定可编辑。
      // 用「引号/注释感知」的切分（对齐 Swift splitStatements），
      // 否则 `WHERE a='x;y'` 会被误判成两条语句而失去可编辑能力。
      final single = splitStatements(sql);
      if (single.length == 1 && resultSets.length == 1) {
        await _tryDetectEditable(single.first, resultSets.first);
      }
      if (mounted) setState(() => _message = msg);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _message = null;
          _canEdit = false;
        });
      }
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  /// 检测是否为「单表简单 SELECT」以便内联编辑（对齐 Swift tryDetectEditable）。
  /// 后端会员限制已按你的要求去掉；保留「必须带 WHERE」这一安全约束。
  Future<void> _tryDetectEditable(String raw, ResultSetData rs) async {
    final sql = raw.trim();
    final forbidden =
        RegExp(r'\b(join|union|group\s+by|having|limit|offset|into|update|delete|insert|replace)\b',
            caseSensitive: false);
    if (sql.contains(forbidden)) {
      if (mounted) setState(() => _canEdit = false);
      return;
    }
    if (!sql.toLowerCase().startsWith('select')) {
      if (mounted) setState(() => _canEdit = false);
      return;
    }
    final fromMatch = RegExp(r'\bfrom\b', caseSensitive: false).firstMatch(sql);
    if (fromMatch == null) {
      if (mounted) setState(() => _canEdit = false);
      return;
    }
    var rest = sql.substring(fromMatch.end).trim();
    String tableName;
    if (rest.startsWith('`')) {
      final end = rest.indexOf('`', 1);
      if (end < 0) {
        if (mounted) setState(() => _canEdit = false);
        return;
      }
      tableName = rest.substring(1, end);
      rest = rest.substring(end + 1).trim();
    } else {
      final parts = rest.split(RegExp(r'\s+'));
      tableName = parts.first;
      rest = parts.length > 1 ? parts.sublist(1).join(' ') : '';
    }
    if (tableName.isEmpty) {
      if (mounted) setState(() => _canEdit = false);
      return;
    }
    final restTrim = rest.trim();
    if (restTrim.startsWith(',') || restTrim.toLowerCase().contains(' join ')) {
      if (mounted) setState(() => _canEdit = false);
      return;
    }
    var useDB = widget.db ?? '';
    if (tableName.contains('.')) {
      final comps = tableName.split('.');
      if (comps.length == 2) {
        useDB = comps[0].replaceAll('`', '');
        tableName = comps[1].replaceAll('`', '');
      }
    }
    if (useDB.isEmpty) {
      if (mounted) setState(() => _canEdit = false);
      return;
    }
    try {
      final cols = await widget.service.listColumns(useDB, tableName);
      if (cols.isEmpty) {
        if (mounted) setState(() => _canEdit = false);
        return;
      }
      final pk = cols.where((c) => c.key == 'PRI').map((c) => c.field).firstOrNull ??
          cols.where((c) => c.key == 'UNI').map((c) => c.field).firstOrNull;
      if (pk == null) {
        if (mounted) setState(() => _canEdit = false);
        return;
      }
      final fieldSet = cols.map((c) => c.field.toLowerCase()).toSet();
      final resultNames = rs.columns.map((c) => c.toLowerCase());
      if (!resultNames.every((n) => fieldSet.contains(n))) {
        if (mounted) setState(() => _canEdit = false);
        return;
      }
      final hasWhere =
          RegExp(r'\bwhere\b', caseSensitive: false).hasMatch(sql);
      // 对齐 Swift enterEdit 的一致性守卫：结果集必须包含主键列，
      // 否则保存时无法定位行（会拼出 `WHERE pk = ''` 的假成功）。
      final pkIndex = rs.columns.indexOf(pk);
      if (mounted) {
        setState(() {
          _editTable = tableName;
          _editDB = useDB;
          _editColNames = List<String>.from(rs.columns);
          _editRowsOriginal = rs.rows
              .map((r) => Map<String, String?>.from(r))
              .toList();
          _editPK = pk;
          _editPKIndex = pkIndex;
          // 安全约束：必须带 WHERE 才允许编辑（防全表误改），且结果集须含主键列。
          _canEdit = hasWhere && pkIndex >= 0;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _canEdit = false);
    }
  }

  void _enterEdit() {
    if (_editRowsOriginal.isEmpty) return;
    _editingRows = _editRowsOriginal
        .map((r) => _editColNames.map((c) => r[c]).toList())
        .toList();
    _editControllers.clear();
    for (var ri = 0; ri < _editingRows.length; ri++) {
      for (var ci = 0; ci < _editColNames.length; ci++) {
        _editControllers['$ri-$ci'] =
            TextEditingController(text: _editingRows[ri][ci] ?? '');
      }
    }
    _hasChanges = false;
    _editMessage = null;
    _editError = null;
    setState(() => _editMode = true);
  }

  void _cancelEdit() {
    _editMode = false;
    _editingRows = [];
    for (final c in _editControllers.values) c.dispose();
    _editControllers.clear();
    _hasChanges = false;
    _editMessage = null;
    _editError = null;
    setState(() {});
  }

  String _escId(String id) => '`${id.replaceAll('`', '``')}`';
  String _quoteVal(String v) =>
      "'${v.replaceAll('\\', '\\\\').replaceAll("'", "\\'")}'";

  Future<void> _saveEdits() async {
    if (_editPK == null || _editPKIndex < 0) {
      setState(() => _editError = '未检测到主键或唯一键');
      return;
    }
    setState(() {
      _saving = true;
      _editError = null;
    });
    try {
      // 未生效的行数（主键为 NULL 无法定位 / 影响行数为 0）：用于避免「假成功」。
      var failed = 0;
      for (var ri = 0; ri < _editingRows.length; ri++) {
        if (ri >= _editRowsOriginal.length) continue;
        final sets = <String>[];
        for (var ci = 0; ci < _editColNames.length; ci++) {
          final colName = _editColNames[ci];
          final oldV = _editRowsOriginal[ri][colName];
          final newV = _editingRows[ri][ci];
          if (oldV != newV) {
            final col = _escId(colName);
            final isNull = newV == null || (newV.isEmpty && oldV == null);
            sets.add(isNull ? '$col = NULL' : '$col = ${_quoteVal(newV)}');
          }
        }
        if (sets.isEmpty) continue;
        // 主键为 NULL 时无法定位行：跳过并计入失败。否则会拼出
        // `WHERE pk = ''`，匹配不到任何记录却提示「保存成功」。
        final pkRaw = _editRowsOriginal[ri][_editPK];
        if (pkRaw == null) {
          failed++;
          continue;
        }
        final pkVal = _quoteVal(pkRaw);
        final sqlUpd = 'UPDATE ${_escId(_editDB!)}.${_escId(_editTable!)} '
            'SET ${sets.join(', ')} '
            'WHERE ${_escId(_editPK!)} = $pkVal LIMIT 1';
        final res = await widget.service.execute(sqlUpd);
        // 影响行数为 0 表示没有匹配到任何记录，不能报「保存成功」（对齐 Swift）。
        if (res.isNotEmpty &&
            !res.first.isResultSet &&
            res.first.affectedRows == 0) {
          failed++;
        }
      }
      // 回写结果集，使界面即时反映新值。
      final newRows = <Map<String, String?>>[];
      for (var ri = 0; ri < _editingRows.length; ri++) {
        final m = <String, String?>{};
        for (var ci = 0; ci < _editColNames.length; ci++) {
          m[_editColNames[ci]] = _editingRows[ri][ci];
        }
        newRows.add(m);
      }
      if (mounted) {
        setState(() {
          // 关键：只读结果表格取自 _outcomes，必须一起替换，
          // 否则「保存成功」后表格仍显示旧值（对齐 Swift 的 rows = editingRows）。
          final olds = _outcomes;
          if (olds != null) {
            var replaced = false;
            _outcomes = olds.map((o) {
              if (!replaced && o.isResultSet) {
                replaced = true;
                return ResultSetData.result(_editColNames, newRows);
              }
              return o;
            }).toList();
          }
          _editRowsOriginal = newRows;
          _editMode = false;
          _editingRows = [];
          _hasChanges = false;
          // 有行未生效时不能只说「保存成功」（对齐 Swift）。
          _editMessage = failed == 0
              ? '保存成功'
              : '保存完成（$failed 行未匹配到记录，未生效）';
          _message = null;
        });
      }
      for (final c in _editControllers.values) c.dispose();
      _editControllers.clear();
    } catch (e) {
      if (mounted) setState(() => _editError = '保存失败：$e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _insertSuggestion(String word) {
    final text = _sql.text;
    final cursor = _sql.selection.baseOffset.clamp(0, text.length);
    final before = text.substring(0, cursor);
    final (qualifier, _) = _tokenAt(before);
    late final int start;
    late final String inserted;
    if (qualifier != null && qualifier.isNotEmpty) {
      // 带限定符（如 a.）：只替换「.」之后的片段，保留 alias. 前缀。
      final dotIdx = before.lastIndexOf('.');
      start = dotIdx >= 0 ? dotIdx + 1 : cursor;
      inserted = word;
    } else {
      // 替换光标前最后一个词（含反引号）。
      final replacement = RegExp(r'[^\s,()`]*$').firstMatch(before);
      start = replacement?.start ?? cursor;
      inserted = '$word ';
    }
    final newBefore = before.replaceRange(start, before.length, inserted);
    final suffix = text.substring(cursor);
    _sql.text = '$newBefore$suffix';
    final newCursor = newBefore.length;
    _sql.selection = TextSelection.fromPosition(TextPosition(offset: newCursor));
  }

  void _insertSelectAll() {
    final t = _contextTable.isEmpty ? (widget.defaultTable ?? '') : _contextTable;
    if (t.isEmpty) return;
    _sql.text = 'SELECT * FROM `$t` ';
    _sql.selection = TextSelection.fromPosition(
      TextPosition(offset: _sql.text.length),
    );
  }

  void _exportCsv() {
    final rs = _outcomes?.where((o) => o.isResultSet).toList();
    if (rs == null || rs.isEmpty) return;
    final first = rs.last;
    final csv = toCsv(first.columns, first.rows);
    // 文件名带时间戳（对齐 Swift：query_result_yyyyMMdd_HHmmss.csv）。
    Share.shareXFiles(
      [
        XFile.fromData(utf8.encode(csv),
            name: 'query_result_${exportTimestamp()}.csv', mimeType: 'text/csv')
      ],
      subject: 'SQLink 查询结果',
    );
  }

  void _exportSql() {
    final rs = _outcomes?.where((o) => o.isResultSet).toList();
    if (rs == null || rs.isEmpty) return;
    final first = rs.last;
    final sql = toSql('query_result', first.columns, first.rows);
    Share.shareXFiles(
      [
        XFile.fromData(utf8.encode(sql),
            name: 'query_result_${exportTimestamp()}.sql', mimeType: 'text/sql')
      ],
      subject: 'SQLink 查询结果',
    );
  }

  void _showHistory() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (ctx) => _HistoryPage(
          history: _settings.history,
          onPick: (h) {
            _sql.text = h;
            _sql.selection = TextSelection.fromPosition(
              TextPosition(offset: _sql.text.length),
            );
            Navigator.of(ctx).pop();
          },
          onClear: () => _settings.clearHistory(),
        ),
      ),
    );
  }

  /// SQL 输入框描边（对齐 Swift：圆角 8 + 灰色 30% 细线，聚焦时主题色）。
  OutlineInputBorder _roundedBorder(ThemeData theme, {bool focused = false}) =>
      OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(
          color: focused
              ? theme.colorScheme.primary
              : Colors.grey.withValues(alpha: 0.3),
          width: focused ? 1.5 : 0.8,
        ),
      );

  /// 补全候选 chip（对齐 Swift QueryConsoleView 的 suggestion 按钮样式）。
  Widget _suggestionChip(String text, ThemeData theme) => InkWell(
        onTap: () => _insertSuggestion(text),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: theme.colorScheme.primary.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            text,
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 13,
              color: theme.colorScheme.primary,
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final resultSets = _outcomes?.where((o) => o.isResultSet).toList() ?? [];
    final isSingle = resultSets.length == 1;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('查询控制台'),
        // 对齐 Swift QueryConsoleView：历史（时钟）与导出（菜单）放在导航栏。
        actions: [
          IconButton(
            onPressed: _showHistory,
            icon: const Icon(Icons.history),
            tooltip: '查询历史',
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.ios_share),
            tooltip: '导出',
            enabled: resultSets.isNotEmpty,
            onSelected: (v) => v == 'sql' ? _exportSql() : _exportCsv(),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'csv', child: Text('导出 CSV')),
              PopupMenuItem(value: 'sql', child: Text('导出 SQL')),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          // 状态 / 上下文栏（对齐 Swift 顶部 HStack）。
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Flexible(
                  child: Text(
                    widget.db == null ? '未选择数据库' : '当前数据库：${widget.db}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurface.withValues(alpha: 0.6)),
                  ),
                ),
                if (widget.db != null) ...[
                  if (_contextTable.isNotEmpty || (widget.defaultTable?.isNotEmpty ?? false))
                    TextButton.icon(
                      style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 6)),
                      onPressed: _insertSelectAll,
                      icon: const Icon(Icons.add_box, size: 16),
                      label: const Text('SELECT *', style: TextStyle(fontSize: 12)),
                    ),
                  if (_tables.isNotEmpty)
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 140),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          isExpanded: true,
                          // 上下文表不在列表中时回退为「未选择」，避免 DropdownButton 断言失败。
                          value:
                              _tables.contains(_contextTable) ? _contextTable : null,
                          hint: const Text('上下文表', style: TextStyle(fontSize: 12)),
                          onChanged: (v) {
                            setState(() {
                              _contextTable = v ?? '';
                            });
                            _loadContextColumns();
                          },
                          items: [
                            const DropdownMenuItem(value: '', child: Text('无上下文')),
                            for (final t in _tables)
                              DropdownMenuItem(value: t, child: Text(t, overflow: TextOverflow.ellipsis)),
                          ],
                        ),
                      ),
                    ),
                ],
              ],
            ),
          ),
          // SQL 编辑框（对齐 Swift TextEditor：等宽、圆角 8、灰色细描边）。
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: TextField(
              controller: _sql,
              maxLines: 4,
              minLines: 2,
              style: TextStyle(
                fontFamily: 'monospace',
                color: theme.colorScheme.onSurface,
              ),
              decoration: InputDecoration(
                filled: true,
                fillColor: theme.colorScheme.surface,
                contentPadding: const EdgeInsets.all(10),
                border: _roundedBorder(theme),
                enabledBorder: _roundedBorder(theme),
                focusedBorder: _roundedBorder(theme, focused: true),
                hintText: '输入 SQL，例如 SELECT 1',
                hintStyle: TextStyle(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.4)),
              ),
            ),
          ),
        // 自动补全 chips（关键字 + 表名 + 上下文列）。
        // 对齐 Swift：等宽字体、主题色 12% 底、圆角 8。
        if (_suggestions.isNotEmpty)
          SizedBox(
            height: 38,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              children: [
                for (final s in _suggestions)
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: _suggestionChip(s, theme),
                    ),
                  ),
              ],
            ),
          ),
        const Divider(),
        // 运行 / 编辑 / 消息工具栏。
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Wrap(
            spacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              FilledButton.icon(
                onPressed: _running ? null : _run,
                icon: _running
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.play_arrow),
                label: Text(_running ? '执行中' : '运行'),
              ),
              // 导出与历史已上移到导航栏（对齐 Swift），此处不再重复。
              if (_canEdit)
                if (_editMode) ...[
                  TextButton.icon(
                    onPressed: _saving ? null : _cancelEdit,
                    icon: const Icon(Icons.close),
                    label: const Text('取消'),
                  ),
                  TextButton.icon(
                    onPressed: (_hasChanges && !_saving) ? _saveEdits : null,
                    icon: _saving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.save),
                    label: const Text('保存'),
                  ),
                ] else
                  TextButton.icon(
                    onPressed: _enterEdit,
                    icon: const Icon(Icons.edit),
                    label: const Text('编辑'),
                  ),
            ],
          ),
        ),
        // 将执行消息单独放一行，避免被工具栏按钮挤成“返回 19…”。
        if (_message != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
            child: Text(
              _message!,
              style: TextStyle(
                fontSize: 12,
                color: _message!.contains('成功') || _message!.contains('返回')
                    ? null
                    : Colors.red,
              ),
            ),
          ),
        if (_editMessage != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(_editMessage!,
                style: const TextStyle(color: Colors.green, fontSize: 12)),
          ),
        if (_editError != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(_editError!,
                style: const TextStyle(color: Colors.red, fontSize: 12)),
          ),
        const Divider(),
        Expanded(
          child: _buildBody(isSingle: isSingle, single: isSingle ? resultSets.first : null),
        ),
      ],
    ),
  );
}

  Widget _buildBody({
    required bool isSingle,
    ResultSetData? single,
  }) {
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text('错误：\n$_error', style: const TextStyle(color: Colors.red)),
        ),
      );
    }
    if (_outcomes == null) {
      return const Center(child: Text('运行 SQL 后在此显示结果'));
    }
    final resultSets = _outcomes!.where((o) => o.isResultSet).toList();
    final okCount = _outcomes!.where((o) => !o.isResultSet).length;
    return ListView(
      padding: const EdgeInsets.all(8),
      children: [
        if (okCount > 0)
          ListTile(
            leading: const Icon(Icons.check_circle, color: Colors.green),
            title: Text('$okCount 条语句执行成功（无结果集）'),
          ),
        if (isSingle && _editMode && single != null)
          // 对齐 Swift：编辑态表格固定 320 高（同时让内层横/纵向滚动生效）。
          SizedBox(height: 320, child: _buildEditableGrid())
        else
          for (var i = 0; i < resultSets.length; i++)
            Card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: Text(
                      '结果 #${i + 1} · ${resultSets[i].rows.length} 行',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  // 对齐 Swift ResultGridView 的 .frame(height: 320)：
                  // 固定高度可避免与外层 ListView 形成嵌套纵向滚动、内层滚动失效。
                  SizedBox(
                    height: 320,
                    child: ResultGrid(
                      columns: resultSets[i].columns,
                      rows: resultSets[i].rows,
                      primaryKey: isSingle ? _editPK : null,
                    ),
                  ),
                ],
              ),
            ),
      ],
    );
  }

  /// 编辑态可编辑表格（对齐 Swift EditableGridView，主键列只读锁定）。
  Widget _buildEditableGrid() {
    // 对齐 Swift：主键列底色为主题色 10%，表头标 🔑🔒（🔒 表示只读锁定）。
    final pkBg = Theme.of(context).colorScheme.primary.withValues(alpha: 0.10);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SingleChildScrollView(
        child: DataTable(
          columns: [
            for (var ci = 0; ci < _editColNames.length; ci++)
              DataColumn(
                label: Text((ci == _editPKIndex ? '🔑🔒 ' : '') + _editColNames[ci]),
              ),
          ],
          rows: List.generate(_editingRows.length, (ri) {
            return DataRow(
              cells: List.generate(_editColNames.length, (ci) {
                if (ci == _editPKIndex) {
                  final val = _editingRows[ri][ci];
                  return DataCell(
                    Container(
                      color: pkBg,
                      child: Text(
                        val ?? 'NULL',
                        style: TextStyle(
                          color: val == null ? Colors.grey : null,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  );
                }
                return DataCell(
                  SizedBox(
                    width: 140,
                    child: TextFormField(
                      controller: _editControllers['$ri-$ci'],
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        isCollapsed: true,
                        contentPadding: EdgeInsets.symmetric(vertical: 8),
                      ),
                      onChanged: (t) {
                        _editingRows[ri][ci] = t;
                        if (!_hasChanges) setState(() => _hasChanges = true);
                      },
                    ),
                  ),
                );
              }),
            );
          }),
        ),
      ),
    );
  }
}

/// SQL 历史页：独立页面 + AppBar + SafeArea，避免底部弹层与系统状态栏重叠。
class _HistoryPage extends StatelessWidget {
  final List<String> history;
  final ValueChanged<String> onPick;
  final VoidCallback onClear;

  const _HistoryPage({
    required this.history,
    required this.onPick,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        // 对齐 Swift QueryHistorySheet 的标题「查询历史」。
        title: const Text('查询历史'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          if (history.isNotEmpty)
            TextButton(
              onPressed: () {
                onClear();
                Navigator.of(context).pop();
              },
              child: const Text('清空'),
            ),
        ],
      ),
      body: SafeArea(
        child: history.isEmpty
            ? const Center(child: Text('暂无查询历史'))
            : ListView.separated(
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                itemCount: history.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (_, i) {
                  final h = history[i];
                  return ListTile(
                    title: Text(
                      h,
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => onPick(h),
                  );
                },
              ),
      ),
    );
  }
}
