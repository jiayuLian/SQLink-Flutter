import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import '../services/mysql_service.dart';
import '../models/connection.dart' show ColumnInfo;
import '../models/filter_condition.dart' show FilterCondition;
import '../services/csv_export.dart';
import '../settings/app_settings.dart';
import '../widgets/result_grid.dart';
import '../widgets/filter_builder.dart';

class TableDataScreen extends StatefulWidget {
  final MySQLService service;
  final String db;
  final String table;
  const TableDataScreen({
    super.key,
    required this.service,
    required this.db,
    required this.table,
  });

  @override
  State<TableDataScreen> createState() => _TableDataScreenState();
}

class _TableDataScreenState extends State<TableDataScreen> {
  ResultSetData? _data;
  List<ColumnInfo> _columns = [];
  int _total = 0;
  int _offset = 0;
  bool _loading = false;
  String? _error;

  // 筛选 & 排序（对齐 Swift 的 activeWhere / activeOrderBy）
  List<FilterCondition> _conditions = [];
  String? _activeWhere;
  String? _activeOrderBy;
  String _sortField = '';
  String _sortDir = 'ASC';

  // 行内编辑模式（对齐 Swift TableDataView 的 edit mode）
  bool _editMode = false;
  List<List<String?>> _editing = [];
  bool _hasChanges = false;
  String? _editMessage;
  String? _editError;
  bool _saving = false;

  int get _pageSize => Provider.of<AppSettings>(context, listen: false).pageSize;

  /// 主键：优先 PRI，其次 UNI（对齐 Swift 的 primaryKey 判定）。
  String? _primaryKey() {
    for (final c in _columns) {
      if (c.key == 'PRI') return c.field;
    }
    for (final c in _columns) {
      if (c.key == 'UNI') return c.field;
    }
    return null;
  }

  int get _pkIndex {
    final pk = _primaryKey();
    if (pk == null || _data == null) return -1;
    final i = _data!.columns.indexOf(pk);
    return i < 0 ? -1 : i;
  }

  @override
  void initState() {
    super.initState();
    _loadColumns();
    _load();
  }

  Future<void> _loadColumns() async {
    try {
      final cols = await widget.service.listColumns(widget.db, widget.table);
      if (mounted) setState(() => _columns = cols);
    } catch (_) {
      // 列信息仅用于主键检测；失败不影响浏览。
    }
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final ps = _pageSize > 0 ? _pageSize : 100;
      final data = await widget.service.fetchTable(
        widget.db,
        widget.table,
        limit: ps,
        offset: _offset,
        where: _activeWhere,
        order: _activeOrderBy,
      );
      // 计数失败不影响数据展示：用当前页行数兜底。
      int total;
      try {
        total = await widget.service.countTable(
          widget.db,
          widget.table,
          where: _activeWhere,
        );
      } catch (_) {
        total = data.isResultSet ? data.rows.length : 0;
      }
      if (mounted) {
        setState(() {
          _data = data;
          _total = total;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _exportCsv() {
    if (_data == null || !_data!.isResultSet) return;
    final csv = toCsv(_data!.columns, _data!.rows);
    Share.shareXFiles(
      [XFile.fromData(utf8.encode(csv), name: '${widget.table}.csv', mimeType: 'text/csv')],
      subject: '${widget.db}.${widget.table}',
    );
  }

  void _exportSql() {
    if (_data == null || !_data!.isResultSet) return;
    final sql = toSql(widget.table, _data!.columns, _data!.rows);
    Share.shareXFiles(
      [XFile.fromData(utf8.encode(sql), name: '${widget.table}.sql', mimeType: 'text/sql')],
      subject: '${widget.db}.${widget.table}',
    );
  }

  // ---- 结构化筛选 & 排序 ----
  void _openFilter() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => FilterBuilder(
        columns: _columns,
        initialConditions: _conditions,
        initialSortField: _sortField,
        initialSortDir: _sortDir,
        onApply: (where, order, conditions, sf, sd) {
          _conditions = conditions
              .map((c) => FilterCondition(
                    field: c.field,
                    op: c.op,
                    value: c.value,
                    enabled: c.enabled,
                    logic: c.logic,
                  ))
              .toList();
          _activeWhere = where;
          _activeOrderBy = order;
          _sortField = sf;
          _sortDir = sd;
          _offset = 0;
          Navigator.of(context).pop();
          _load();
        },
      ),
    );
  }

  // ---- 行内编辑（对齐 Swift saveEdits） ----
  void _enterEdit() {
    if (_data == null || !_data!.isResultSet) return;
    _editing = _data!.rows
        .map((r) => _data!.columns.map((c) => r[c]).toList())
        .toList();
    _hasChanges = false;
    _editMessage = null;
    _editError = null;
    setState(() => _editMode = true);
  }

  void _cancelEdit() {
    _editMode = false;
    _editing = [];
    _hasChanges = false;
    _editMessage = null;
    _editError = null;
    setState(() {});
  }

  String _escId(String id) => '`${id.replaceAll('`', '``')}`';

  String _quoteValue(String v) => "'${v.replaceAll("'", "''")}'";

  Future<void> _saveEdits() async {
    final pk = _primaryKey();
    if (pk == null || _pkIndex < 0) {
      setState(() => _editError = '未检测到主键或唯一键');
      return;
    }
    setState(() => _saving = true);
    try {
      for (var ri = 0; ri < _editing.length; ri++) {
        final sets = <String>[];
        for (var ci = 0; ci < _data!.columns.length; ci++) {
          final colName = _data!.columns[ci];
          final oldV = _data!.rows[ri][colName];
          final newV = _editing[ri][ci];
          if (oldV != newV) {
            final col = _escId(colName);
            // 对齐 Swift：若清空的是原本为 NULL 的单元则写 NULL；否则按实际值处理。
            final isNull = newV == null || (newV.isEmpty && oldV == null);
            sets.add(isNull ? '$col = NULL' : '$col = ${_quoteValue(newV)}');
          }
        }
        if (sets.isEmpty) continue;
        final pkVal = _quoteValue(_data!.rows[ri][pk] ?? '');
        final sql = 'UPDATE ${_escId(widget.db)}.${_escId(widget.table)} '
            'SET ${sets.join(', ')} '
            'WHERE ${_escId(pk)} = $pkVal LIMIT 1';
        await widget.service.execute(sql);
      }
      if (mounted) {
        setState(() {
          _editMode = false;
          _editing = [];
          _hasChanges = false;
          _editMessage = '保存成功';
          _editError = null;
        });
      }
      await _load();
    } catch (e) {
      if (mounted) setState(() => _editError = '保存失败：$e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ps = _pageSize > 0 ? _pageSize : 100;
    final page = _offset ~/ ps + 1;
    final totalPages = (_total / ps).ceil();
    final pkOk = _primaryKey() != null;
    final hasFilter = _activeWhere != null || _activeOrderBy != null;

    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.db}.${widget.table}'),
        actions: [
          if (_editMode) ...[
            IconButton(
              icon: const Icon(Icons.close),
              tooltip: '取消',
              onPressed: _saving ? null : _cancelEdit,
            ),
            IconButton(
              icon: _saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save),
              tooltip: '保存',
              onPressed: (_hasChanges && !_saving) ? _saveEdits : null,
            ),
          ] else ...[
            if (pkOk)
              IconButton(
                icon: const Icon(Icons.edit),
                tooltip: '编辑',
                onPressed: _data?.isResultSet ?? false ? _enterEdit : null,
              ),
            IconButton(
              icon: const Icon(Icons.filter_alt),
              tooltip: '筛选 & 排序',
              onPressed: !_editMode ? _openFilter : null,
            ),
            PopupMenuButton<String>(
              icon: const Icon(Icons.download),
              tooltip: '导出',
              enabled: _data?.isResultSet ?? false,
              onSelected: (v) => v == 'sql' ? _exportSql() : _exportCsv(),
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'csv', child: Text('导出 CSV')),
                PopupMenuItem(value: 'sql', child: Text('导出 SQL')),
              ],
            ),
          ],
        ],
      ),
      body: Column(
        children: [
          if (hasFilter)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(
                children: [
                  Chip(
                    label: Text(
                      [
                        if (_activeWhere != null) '已筛选',
                        if (_activeOrderBy != null)
                          '排序：$_sortField ${_sortDir == 'DESC' ? '降序' : '升序'}',
                      ].join('，'),
                      style: const TextStyle(fontSize: 12),
                    ),
                    deleteIcon: const Icon(Icons.clear, size: 16),
                    onDeleted: () {
                      _conditions = [];
                      _activeWhere = null;
                      _activeOrderBy = null;
                      _sortField = '';
                      _offset = 0;
                      _load();
                    },
                  ),
                ],
              ),
            ),
          if (_editMessage != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(_editMessage!,
                  style: const TextStyle(color: Colors.green, fontSize: 12)),
            ),
          if (_editError != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(_editError!,
                  style: const TextStyle(color: Colors.red, fontSize: 12)),
            ),
          if (!_editMode && !pkOk)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              child: Text('⚠ 无主键/唯一键，不可编辑',
                  style: TextStyle(color: Colors.orange, fontSize: 12)),
            ),
          const Divider(),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(
                        child: Text('错误：$_error',
                            style: const TextStyle(color: Colors.red)))
                    : _data != null && _data!.isResultSet
                        ? (_editMode
                            ? _buildEditableGrid()
                            : ResultGrid(
                                columns: _data!.columns,
                                rows: _data!.rows,
                                primaryKey: _primaryKey(),
                              ))
                        : const Center(child: Text('无数据')),
          ),
          Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left),
                  onPressed: (_offset >= ps && !_editMode)
                      ? () {
                          _offset -= ps;
                          _load();
                        }
                      : null,
                ),
                Text('第 $page / ${totalPages == 0 ? 1 : totalPages} 页 · 共 $_total 行'),
                IconButton(
                  icon: const Icon(Icons.chevron_right),
                  onPressed: (_offset + ps < _total && !_editMode)
                      ? () {
                          _offset += ps;
                          _load();
                        }
                      : null,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 编辑态的双向滚动可编辑表格；主键列只读（对齐 Swift EditableGridView 锁定 PK）。
  Widget _buildEditableGrid() {
    final cols = _data!.columns;
    final pkIndex = _pkIndex;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final pkBg = isDark ? Colors.amber.shade900.withValues(alpha: 0.35) : Colors.amber.shade100;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SingleChildScrollView(
        child: DataTable(
          columns: cols
              .map((c) => DataColumn(
                    label: Text((cols.indexOf(c) == pkIndex ? '🔑 ' : '') + c),
                  ))
              .toList(),
          rows: List.generate(_editing.length, (ri) {
            return DataRow(
              cells: List.generate(cols.length, (ci) {
                if (ci == pkIndex) {
                  final val = _editing[ri][ci];
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
                      initialValue: _editing[ri][ci] ?? '',
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        isCollapsed: true,
                        contentPadding: EdgeInsets.symmetric(vertical: 8),
                      ),
                      onChanged: (t) {
                        _editing[ri][ci] = t;
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
