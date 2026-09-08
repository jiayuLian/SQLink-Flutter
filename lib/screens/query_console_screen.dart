import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import '../services/mysql_service.dart';
import '../models/connection.dart' show ColumnInfo;
import '../services/csv_export.dart';
import '../settings/app_settings.dart';
import '../widgets/result_grid.dart';

const _keywords = [
  'SELECT', 'FROM', 'WHERE', 'INSERT', 'INTO', 'VALUES', 'UPDATE', 'SET',
  'DELETE', 'CREATE', 'DROP', 'ALTER', 'TABLE', 'DATABASE', 'LIMIT', 'ORDER',
  'GROUP', 'BY', 'AND', 'OR', 'NOT', 'NULL', 'LIKE', 'IN', 'BETWEEN', 'JOIN',
  'LEFT', 'RIGHT', 'INNER', 'ON', 'AS', 'ASC', 'DESC', 'HAVING', 'UNION',
  'DISTINCT', 'COUNT', 'SUM', 'AVG', 'MAX', 'MIN',
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
      }
    } catch (_) {
      // 表名仅用于补全提示，失败忽略。
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

  String get _currentWord {
    final t = _sql.text;
    if (t.isEmpty) return '';
    final parts = t.split(RegExp(r'\s+'));
    return parts.last;
  }

  List<String> get _suggestions {
    final w = _currentWord.toUpperCase();
    if (w.isEmpty) return [];
    final pool = <String>[
      ..._keywords,
      ..._tables,
      ..._contextColumns.map((c) => c.field),
    ];
    final seen = <String>{};
    final out = <String>[];
    for (final item in pool) {
      final u = item.toUpperCase();
      if (u.startsWith(w) && !seen.contains(u) && u != w) {
        seen.add(u);
        out.add(item);
      }
    }
    return out;
  }

  Future<void> _run() async {
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
        RegExp(r'(?i)\b(join|union|group\s+by|having|limit|offset|into|update|delete|insert|replace)\b');
    if (sql.contains(forbidden)) {
      if (mounted) setState(() => _canEdit = false);
      return;
    }
    if (!sql.toLowerCase().startsWith('select')) {
      if (mounted) setState(() => _canEdit = false);
      return;
    }
    final fromMatch = RegExp(r'(?i)\bfrom\b').firstMatch(sql);
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
          RegExp(r'(?i)\bwhere\b').hasMatch(sql);
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
    final t = _sql.text;
    final trimmed = t.replaceAll(RegExp(r'\S+$'), '');
    _sql.text = '$trimmed$word ';
    _sql.selection = TextSelection.fromPosition(
      TextPosition(offset: _sql.text.length),
    );
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
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => ListView(
        children: [
          ListTile(
            title: const Text('SQL 历史', style: TextStyle(fontWeight: FontWeight.bold)),
            trailing: settings.history.isEmpty
                ? null
                : TextButton(
                    onPressed: () {
                      settings.clearHistory();
                      Navigator.of(ctx).pop();
                    },
                    child: const Text('清空'),
                  ),
          ),
          if (settings.history.isEmpty)
            const ListTile(title: Text('暂无历史')),
          for (final h in settings.history)
            ListTile(
              title: Text(h, maxLines: 2, overflow: TextOverflow.ellipsis),
              onTap: () {
                _sql.text = h;
                Navigator.of(ctx).pop();
              },
            ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _sql.dispose();
    for (final c in _editControllers.values) c.dispose();
    _editControllers.clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final resultSets = _outcomes?.where((o) => o.isResultSet).toList() ?? [];
    final isSingle = resultSets.length == 1;
    return Column(
      children: [
        // 状态 / 上下文栏（对齐 Swift 顶部 HStack）。
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  widget.db == null ? '未选择数据库' : '当前数据库：${widget.db}',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ),
              if (widget.db != null) ...[
                if (_contextTable.isNotEmpty || (widget.defaultTable?.isNotEmpty ?? false))
                  TextButton.icon(
                    onPressed: _insertSelectAll,
                    icon: const Icon(Icons.add_box, size: 16),
                    label: const Text('SELECT *', style: TextStyle(fontSize: 12)),
                  ),
                if (_tables.isNotEmpty)
                  DropdownButton<String>(
                    value: _contextTable,
                    hint: const Text('上下文表', style: TextStyle(fontSize: 12)),
                    underline: const SizedBox.shrink(),
                    onChanged: (v) {
                      setState(() {
                        _contextTable = v ?? '';
                      });
                      _loadContextColumns();
                    },
                    items: [
                      const DropdownMenuItem(value: '', child: Text('无上下文')),
                      for (final t in _tables)
                        DropdownMenuItem(value: t, child: Text(t)),
                    ],
                  ),
              ],
            ],
          ),
        ),
        // SQL 编辑框（等宽字体，对齐 Swift .monospaced）。
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: TextField(
            controller: _sql,
            maxLines: 4,
            minLines: 2,
            style: const TextStyle(fontFamily: 'monospace'),
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              hintText: '输入 SQL，例如 SELECT 1',
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
          child: Row(
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
              const SizedBox(width: 8),
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
              const Spacer(),
              if (_message != null)
                Expanded(
                  child: Text(
                    _message!,
                    style: TextStyle(
                      fontSize: 12,
                      color: _message!.contains('成功') || _message!.contains('返回')
                          ? null
                          : Colors.red,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
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
