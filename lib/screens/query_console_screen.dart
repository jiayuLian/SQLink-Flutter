import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import '../services/mysql_service.dart';
import '../models/connection.dart' show ColumnInfo;
import '../services/csv_export.dart';
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

  Future<void> _loadSavedSql() async {
    final settings = Provider.of<AppSettings>(context, listen: false);
    if (!settings.autoSaveSQL) return;
    final saved = await settings.getSavedSQL(widget.db ?? '_', widget.defaultTable ?? '_');
    if (saved != null && saved.isNotEmpty && mounted) {
      _sql.text = saved;
    }
  }

  Future<void> _saveSqlIfNeeded() async {
    final settings = Provider.of<AppSettings>(context, listen: false);
    if (settings.autoSaveSQL) {
      await settings.saveSQL(widget.db ?? '_', widget.defaultTable ?? '_', _sql.text);
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

  /// 取出光标前正在输入的“当前词”。以空格/换行/逗号/括号/反引号/等号/点为界，
  /// 并去掉首尾反引号，方便对 `table`.`field` 这种场景也能提示。
  /// 分隔符用 *（可零个）——否则在输入框最开头打字（如 SEL）时匹配不到，
  /// 补全会始终为空。
  String get _currentWord {
    final t = _sql.text.substring(0, _sql.selection.baseOffset.clamp(0, _sql.text.length));
    final match = RegExp(r'[\s,()`.=]*([^\s,()`.=]*)$').firstMatch(t);
    return (match?.group(1) ?? '').replaceAll('`', '');
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

  /// 候选池分三层，按优先级依次追加（关键词 → 表名 → 字段）：
  /// - 关键词：前缀匹配（含 ORDER BY 等多词短语）；
  /// - 表名：前缀 → 包含 → 模糊子序列（≥3 字符）；
  /// - 字段（上下文表 / SQL 中引用表的列）：前缀 → 包含。
  List<String> get _suggestions {
    final w = _currentWord;
    if (w.isEmpty) return [];
    final wu = w.toUpperCase();
    final out = <String>[];
    final seen = <String>{};
    void add(String item) {
      final u = item.toUpperCase();
      if (u == wu || !seen.add(u)) return;
      out.add(item);
    }

    for (final k in _keywords) {
      if (k.toUpperCase().startsWith(wu)) add(k);
    }
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
    final settings = Provider.of<AppSettings>(context, listen: false);
    await settings.addHistory(sql);
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
      final single = sql.split(';').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
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
      if (mounted) {
        setState(() {
          _editTable = tableName;
          _editDB = useDB;
          _editColNames = List<String>.from(rs.columns);
          _editRowsOriginal = rs.rows
              .map((r) => Map<String, String?>.from(r))
              .toList();
          _editPK = pk;
          _editPKIndex = rs.columns.indexOf(pk);
          // 安全约束：必须带 WHERE 才允许编辑（防全表误改）。
          _canEdit = hasWhere;
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
      for (var ri = 0; ri < _editingRows.length; ri++) {
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
        final pkVal = _quoteVal(_editRowsOriginal[ri][_editPK] ?? '');
        final sqlUpd = 'UPDATE ${_escId(_editDB!)}.${_escId(_editTable!)} '
            'SET ${sets.join(', ')} '
            'WHERE ${_escId(_editPK!)} = $pkVal LIMIT 1';
        await widget.service.execute(sqlUpd);
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
          _editRowsOriginal = newRows;
          _editMode = false;
          _editingRows = [];
          _hasChanges = false;
          _editMessage = '保存成功';
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
    // 替换光标前最后一个词（含反引号）。
    final replacement = RegExp(r'[^\s,()`]*$').firstMatch(before);
    final start = replacement?.start ?? cursor;
    final newBefore = before.replaceRange(start, before.length, word);
    final suffix = text.substring(cursor);
    _sql.text = '$newBefore $suffix';
    final newCursor = newBefore.length + 1;
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
    Share.shareXFiles(
      [XFile.fromData(utf8.encode(csv), name: 'sqlink_result.csv', mimeType: 'text/csv')],
      subject: 'SQLink 查询结果',
    );
  }

  void _exportSql() {
    final rs = _outcomes?.where((o) => o.isResultSet).toList();
    if (rs == null || rs.isEmpty) return;
    final first = rs.last;
    final sql = toSql('query_result', first.columns, first.rows);
    Share.shareXFiles(
      [XFile.fromData(utf8.encode(sql), name: 'sqlink_result.sql', mimeType: 'text/sql')],
      subject: 'SQLink 查询结果',
    );
  }

  void _showHistory() {
    final settings = Provider.of<AppSettings>(context, listen: false);
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (ctx) => _HistoryPage(
          history: settings.history,
          onPick: (h) {
            _sql.text = h;
            _sql.selection = TextSelection.fromPosition(
              TextPosition(offset: _sql.text.length),
            );
            Navigator.of(ctx).pop();
          },
          onClear: () => settings.clearHistory(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final resultSets = _outcomes?.where((o) => o.isResultSet).toList() ?? [];
    final isSingle = resultSets.length == 1;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('查询控制台'),
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
                          value: _contextTable.isEmpty ? null : _contextTable,
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
          // SQL 编辑框：带填充背景与主题自适应文字颜色，避免黑底看不清。
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
                fillColor: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                border: const OutlineInputBorder(),
                hintText: '输入 SQL，例如 SELECT 1',
                hintStyle: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.4)),
              ),
            ),
          ),
        // 自动补全 chips（关键字 + 表名 + 上下文列）。
        if (_suggestions.isNotEmpty)
          SizedBox(
            height: 38,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              children: _suggestions
                  .map((s) => Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 3),
                        child: ActionChip(
                          label: Text(s),
                          onPressed: () => _insertSuggestion(s),
                        ),
                      ))
                  .toList(),
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
              if (resultSets.isNotEmpty) ...[
                IconButton(
                  onPressed: _exportCsv,
                  icon: const Icon(Icons.download),
                  tooltip: '导出 CSV',
                ),
                IconButton(
                  onPressed: _exportSql,
                  icon: const Icon(Icons.table_view),
                  tooltip: '导出 SQL',
                ),
              ],
              IconButton(
                onPressed: _showHistory,
                icon: const Icon(Icons.history),
                tooltip: 'SQL 历史',
              ),
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
      return const Center(child: Text('执行查询后显示结果'));
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
          _buildEditableGrid()
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
                  ResultGrid(
                    columns: resultSets[i].columns,
                    rows: resultSets[i].rows,
                    primaryKey: isSingle ? _editPK : null,
                  ),
                ],
              ),
            ),
      ],
    );
  }

  /// 编辑态可编辑表格（对齐 Swift EditableGridView，主键列只读锁定）。
  Widget _buildEditableGrid() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final pkBg = isDark ? Colors.amber.shade900.withValues(alpha: 0.35) : Colors.amber.shade100;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SingleChildScrollView(
        child: DataTable(
          columns: [
            for (var ci = 0; ci < _editColNames.length; ci++)
              DataColumn(
                label: Text((ci == _editPKIndex ? '🔑 ' : '') + _editColNames[ci]),
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
        title: const Text('SQL 历史'),
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
