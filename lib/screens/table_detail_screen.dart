import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/connection.dart' show ColumnInfo;
import '../models/filter_condition.dart';
import '../services/mysql_service.dart';
import '../services/sql_format.dart';
import '../widgets/filter_builder.dart';
import '../widgets/sql_highlighter.dart';
import 'query_console_screen.dart';
import 'table_data_screen.dart';

/// 表详情页（对齐 Swift TableDetailView）——进入表的**第一级**。
/// 内容分四段：结构（列 + key 徽标 + 备注）/「查看建表 SQL」/
/// 「查看数据（匹配 N 条）」/「打开查询控制台」。
/// 筛选&排序状态在此页持有（[TableFilterState]），与数据页共享，
/// 因此在详情页设置的条件、回到详情页仍保留（对齐 Swift 的 @Binding 提升）。
class TableDetailScreen extends StatefulWidget {
  final MySQLService service;
  final String db;
  final String table;
  const TableDetailScreen({
    super.key,
    required this.service,
    required this.db,
    required this.table,
  });

  @override
  State<TableDetailScreen> createState() => _TableDetailScreenState();
}

class _TableDetailScreenState extends State<TableDetailScreen> {
  final TableFilterState _filter = TableFilterState();

  List<ColumnInfo> _columns = [];
  int? _rowCount;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final cols = await widget.service.listColumns(widget.db, widget.table);
      int? cnt;
      try {
        cnt = await widget.service.countTable(
          widget.db,
          widget.table,
          where: _filter.where,
        );
      } catch (_) {
        // 计数失败不影响结构展示。
      }
      if (mounted) {
        setState(() {
          _columns = cols;
          _rowCount = cnt;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// 筛选状态摘要（对齐 Swift filterStatusSummary）。
  String get _filterSummary {
    final parts = <String>[];
    if (_filter.where != null) {
      final n = _filter.conditions
          .where((c) => c.enabled && c.field.isNotEmpty)
          .length;
      if (n > 0) parts.add('$n 个筛选');
    }
    if (_filter.order != null && _filter.sortField.isNotEmpty) {
      parts.add('排序：${_filter.sortField} ${_filter.sortDir == 'DESC' ? '降序' : '升序'}');
    }
    return parts.join('，');
  }

  void _openFilter() {
    showFilterOverlay(
      context,
      child: FilterBuilder(
        columns: _columns,
        initialConditions: _filter.conditions,
        initialSortField: _filter.sortField,
        initialSortDir: _filter.sortDir,
        onApply: (where, order, conditions, sf, sd) {
          _filter.conditions = conditions;
          _filter.where = where;
          _filter.order = order;
          _filter.sortField = sf;
          _filter.sortDir = sd;
          _load();
        },
      ),
    );
  }

  void _openData() {
    Navigator.of(context)
        .push(
          MaterialPageRoute(
            builder: (_) => TableDataScreen(
              service: widget.service,
              db: widget.db,
              table: widget.table,
              filter: _filter,
            ),
          ),
        )
        // 返回后刷新「匹配 N 条」（数据页里可能改过筛选条件）。
        .then((_) {
      if (mounted) _load();
    });
  }

  void _openConsole() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => QueryConsoleScreen(
          service: widget.service,
          db: widget.db,
          defaultTable: widget.table,
        ),
      ),
    );
  }

  Future<void> _showDdl() async {
    showDialog(
      context: context,
      builder: (_) => _DdlDialog(
        service: widget.service,
        db: widget.db,
        table: widget.table,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = TextStyle(
      fontSize: 12,
      color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
    );
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.table),
        actions: [
          IconButton(
            icon: const Icon(Icons.filter_list),
            tooltip: '筛选&排序',
            onPressed: _columns.isEmpty ? null : _openFilter,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text('加载失败：$_error',
                        style: const TextStyle(color: Colors.red)),
                  ),
                )
              // 分组卡片版式（对齐 Swift TableDetailView 的 List + Section）。
              : ListView(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
                  children: [
                    Card(
                      margin: EdgeInsets.zero,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _sectionHeader('结构（${_columns.length} 列）'),
                          if (_columns.isEmpty)
                            const Padding(
                              padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
                              child: Text('加载中…',
                                  style: TextStyle(color: Colors.grey)),
                            ),
                          for (final c in _columns) _columnTile(c, theme),
                          const Divider(height: 1),
                          Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: TextButton.icon(
                                onPressed: _showDdl,
                                icon: const Icon(Icons.description_outlined),
                                label: const Text('查看建表 SQL'),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (_filterSummary.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Card(
                        margin: EdgeInsets.zero,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  _filterSummary,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: muted,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    Card(
                      margin: EdgeInsets.zero,
                      child: ListTile(
                        leading: const Icon(Icons.table_chart_outlined),
                        title: const Text('查看数据'),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _rowCount == null ? '加载中…' : '匹配 $_rowCount 条',
                              style: muted,
                            ),
                            const Icon(Icons.chevron_right),
                          ],
                        ),
                        onTap: _openData,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Card(
                      margin: EdgeInsets.zero,
                      child: ListTile(
                        leading: const Icon(Icons.terminal),
                        title: const Text('打开查询控制台'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: _openConsole,
                      ),
                    ),
                  ],
                ),
    );
  }

  Widget _sectionHeader(String title) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
        child: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
      );

  /// 单列信息（对齐 Swift TableDetailView 的列行）：字段名（粗）+ key 徽标 +
  /// 类型/NULL 说明 + 备注。
  Widget _columnTile(ColumnInfo c, ThemeData theme) {
    final hasKey = c.key.isNotEmpty && c.key != ' ';
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  c.field,
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.bold),
                ),
              ),
              if (hasKey)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    c.key,
                    style: TextStyle(
                      fontSize: 12,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            '${c.type}  ${c.nullAllowed == 'NO' ? 'NOT NULL' : 'NULL'}',
            style: TextStyle(
              fontSize: 12,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
          if (c.comment.isNotEmpty)
            Text(
              '备注：${c.comment}',
              style: TextStyle(
                fontSize: 12,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
        ],
      ),
    );
  }
}

/// 建表 SQL 弹窗（对齐 Swift TableDetailView 的 DDL sheet）：
/// 等宽字体、可双指缩放、左上「1:1」复位、右上复制、右下「完成」。
class _DdlDialog extends StatefulWidget {
  final MySQLService service;
  final String db;
  final String table;
  const _DdlDialog({
    required this.service,
    required this.db,
    required this.table,
  });

  @override
  State<_DdlDialog> createState() => _DdlDialogState();
}

class _DdlDialogState extends State<_DdlDialog> {
  bool _loading = true;
  String _ddl = '';
  String? _error;
  double _scale = 1.0;
  double _startScale = 1.0;

  static double _clamp(double v) => v < 0.6 ? 0.6 : (v > 4.0 ? 4.0 : v);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final sql = await widget.service.showCreateTable(widget.db, widget.table);
      if (mounted) {
        setState(() {
          _ddl = sql;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  String get _display =>
      _ddl.isEmpty ? '（无建表语句）' : formatCreateTable(_ddl);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      titlePadding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
      contentPadding: const EdgeInsets.fromLTRB(12, 0, 12, 0),
      title: Row(
        children: [
          TextButton(
            onPressed: () => setState(() => _scale = 1.0),
            child: const Text('1:1'),
          ),
          Expanded(
            child: Text(
              '建表 SQL',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.copy),
            tooltip: '复制',
            onPressed: () {
              Clipboard.setData(ClipboardData(text: _display));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('建表 SQL 已复制')),
              );
            },
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('完成'),
          ),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: _loading
            ? const SizedBox(
                height: 120,
                child: Center(child: CircularProgressIndicator()),
              )
            : _error != null
                ? SingleChildScrollView(
                    child: Text('加载失败：$_error',
                        style: const TextStyle(color: Colors.red)),
                  )
                // 对齐 Swift：等宽高亮文本铺在次级背景色圆角卡片上（可缩放）。
                : Container(
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest
                          .withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    padding: const EdgeInsets.all(12),
                    child: GestureDetector(
                      onScaleStart: (_) => _startScale = _scale,
                      onScaleUpdate: (d) => setState(
                          () => _scale = _clamp(_startScale * d.scale)),
                      onDoubleTap: () => setState(() => _scale = 1.0),
                      child: SizedBox(
                        height: 320,
                        child: SingleChildScrollView(
                          child: Transform.scale(
                            scale: _scale,
                            alignment: Alignment.topLeft,
                            child: SqlHighlighter(_display),
                          ),
                        ),
                      ),
                    ),
                  ),
      ),
    );
  }
}
