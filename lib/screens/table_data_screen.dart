import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import '../services/mysql_service.dart';
import '../models/connection.dart' show ColumnInfo;
import '../models/filter_condition.dart';
import '../services/csv_export.dart';
import '../settings/app_settings.dart';
import '../widgets/result_grid.dart';
import '../widgets/filter_builder.dart';

/// 表数据页（对齐 Swift TableDataView）——进入表的**第二级**。
/// 版式与 Swift 一致：导航栏左侧「返回 + 筛选&排序」，右侧「编辑 / 导出」
/// （编辑态为「取消 / 保存」）；顶部状态条「共 N 条 · 第 x/y 页」；
/// 底部「上一页 / 页码 / 下一页 + N 条/页 + 缩放%」。
/// 筛选&排序状态由上层 [TableDetailScreen] 持有并共享（对齐 Swift @Binding）。
class TableDataScreen extends StatefulWidget {
  final MySQLService service;
  final String db;
  final String table;
  final TableFilterState filter;
  const TableDataScreen({
    super.key,
    required this.service,
    required this.db,
    required this.table,
    required this.filter,
  });

  @override
  State<TableDataScreen> createState() => _TableDataScreenState();
}

class _TableDataScreenState extends State<TableDataScreen> {
  ResultSetData? _data;
  List<ColumnInfo> _columns = [];
  int _rowCount = 0;
  int _page = 1;
  bool _loading = false;
  String? _error;

  final ResultGridController _gridController = ResultGridController();

  late int _pageSize;

  // 行内编辑模式（对齐 Swift TableDataView 的 edit mode）
  bool _editMode = false;
  List<List<String?>> _editing = [];
  bool _hasChanges = false;
  String? _editMessage;
  String? _editError;
  bool _saving = false;

  /// 导出进行中：导出会分块拉取**全部匹配行**，需要给用户反馈并防止重入。
  bool _exporting = false;

  // 编辑态单元格输入框控制器，按 "$ri-$ci" 持有，避免每次按键 setState 重建
  // DataTable 导致 TextFormField(initialValue) 光标跳到末尾（同筛选器焦点问题）。
  final Map<String, TextEditingController> _editControllers = {};

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

  int get _ps => _pageSize > 0 ? _pageSize : 100;

  /// 总页数（对齐 Swift maxPage）。
  int get _maxPage =>
      _rowCount <= 0 ? 1 : ((_rowCount + _ps - 1) ~/ _ps);

  /// 是否已应用筛选或排序（对齐 Swift hasFilterCondition）。
  bool get _hasFilter => widget.filter.hasFilter;

  @override
  void initState() {
    super.initState();
    _pageSize = 100;
    _loadColumns();
  }

  /// 首帧前才拿到 Provider 里的每页条数：在这里做**唯一一次**引导加载，
  /// 避免 initState 用默认 100 拉一遍、didChangeDependencies 再用设置值拉一遍，
  /// 两个并发请求互相覆盖导致列表与页码错乱。
  bool _bootstrapped = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final ps = Provider.of<AppSettings>(context, listen: false).pageSize;
    if (ps > 0) _pageSize = ps;
    if (!_bootstrapped) {
      _bootstrapped = true;
      _load();
    }
  }

  @override
  void dispose() {
    for (final c in _editControllers.values) {
      c.dispose();
    }
    _editControllers.clear();
    _gridController.dispose();
    super.dispose();
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
      final ps = _ps;
      // 先取总数用于分页；失败则退化为单页。
      int? total;
      try {
        total = await widget.service.countTable(
          widget.db,
          widget.table,
          where: widget.filter.where,
        );
      } catch (_) {
        total = null;
      }
      final pages = (total == null || total <= 0) ? 1 : ((total + ps - 1) ~/ ps);
      var page = _page < 1 ? 1 : _page;
      if (page > pages) page = pages;
      final offset = (page - 1) * ps;

      final data = await widget.service.fetchTable(
        widget.db,
        widget.table,
        limit: ps,
        offset: offset,
        where: widget.filter.where,
        order: widget.filter.order,
      );
      if (!mounted) return;
      setState(() {
        _page = page;
        _data = data;
        _rowCount =
            total ?? (offset + (data.isResultSet ? data.rows.length : 0));
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _changePageSize(int v) {
    final settings = Provider.of<AppSettings>(context, listen: false);
    settings.setPageSize(v);
    setState(() {
      _pageSize = v;
      _page = 1;
    });
    _load();
  }

  void _gotoPage(int page) {
    setState(() => _page = page);
    _load();
  }

  // ---- 点击标题显示完整表名 ----
  void _showFullTableName(String full) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('完整表名'),
        content: SelectableText(full),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: full));
              Navigator.of(ctx).pop();
            },
            child: const Text('复制'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  /// 导出**全部匹配行**（对齐 Swift 的 exportTableStreaming）：
  /// 按当前 WHERE / ORDER 分块拉取整表匹配数据后生成文件，
  /// 而不是只导出当前这一页（旧实现只导当前页，数据会缺）。
  Future<void> _export(String format) async {
    if (_exporting || _data == null || !_data!.isResultSet) return;
    setState(() => _exporting = true);
    try {
      final all = await widget.service.fetchAllRows(
        widget.db,
        widget.table,
        where: widget.filter.where,
        order: widget.filter.order,
      );
      // 空表时 fetchAllRows 至少拉一次，列名仍可用；兜底用当前页列名。
      final cols = all.columns.isNotEmpty ? all.columns : _data!.columns;
      final rows = all.rows;
      // 文件名带时间戳（对齐 Swift：`<table>_yyyyMMdd_HHmmss.csv`）。
      final name = '${widget.table}_${exportTimestamp()}';
      if (format == 'sql') {
        final sql = toSql(widget.table, cols, rows);
        await Share.shareXFiles(
          [
            XFile.fromData(utf8.encode(sql),
                name: '$name.sql', mimeType: 'text/sql')
          ],
          subject: '${widget.db}.${widget.table}',
        );
      } else {
        final csv = toCsv(cols, rows);
        await Share.shareXFiles(
          [
            XFile.fromData(utf8.encode(csv),
                name: '$name.csv', mimeType: 'text/csv')
          ],
          subject: '${widget.db}.${widget.table}',
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('导出失败：$e')));
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  // ---- 结构化筛选 & 排序（居中卡片弹窗，对齐 Swift filterOverlay） ----
  void _openFilter() {
    showFilterOverlay(
      context,
      child: FilterBuilder(
        columns: _columns,
        initialConditions: widget.filter.conditions,
        initialSortField: widget.filter.sortField,
        initialSortDir: widget.filter.sortDir,
        onApply: (where, order, conditions, sf, sd) {
          widget.filter.conditions = conditions;
          widget.filter.where = where;
          widget.filter.order = order;
          widget.filter.sortField = sf;
          widget.filter.sortDir = sd;
          _page = 1;
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
    // 为每个可编辑单元格建立控制器，初值取自当前行数据。
    _editControllers.clear();
    for (var ri = 0; ri < _editing.length; ri++) {
      for (var ci = 0; ci < _data!.columns.length; ci++) {
        _editControllers['$ri-$ci'] =
            TextEditingController(text: _editing[ri][ci] ?? '');
      }
    }
    _hasChanges = false;
    _editMessage = null;
    _editError = null;
    setState(() => _editMode = true);
  }

  void _cancelEdit() {
    _editMode = false;
    _editing = [];
    for (final c in _editControllers.values) {
      c.dispose();
    }
    _editControllers.clear();
    _hasChanges = false;
    _editMessage = null;
    _editError = null;
    setState(() {});
  }

  String _escId(String id) => '`${id.replaceAll('`', '``')}`';

  // 正确性优先：先转义反斜杠再转义单引号（与 csv_export.toSql 一致），
  // 否则含 \ 或 \' 的单元格值在 MySQL 默认 SQL 模式下会破坏 UPDATE 语句。
  String _quoteValue(String v) =>
      "'${v.replaceAll('\\', '\\\\').replaceAll("'", "\\'")}'";

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
      // 编辑态结束，释放所有单元格控制器，避免泄漏。
      for (final c in _editControllers.values) {
        c.dispose();
      }
      _editControllers.clear();
      await _load();
    } catch (e) {
      if (mounted) setState(() => _editError = '保存失败：$e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ps = _ps;
    final pk = _primaryKey();
    final pkOk = pk != null;
    final hasFilter = _hasFilter;
    final fullTitle = '${widget.db}.${widget.table}';

    return Scaffold(
      appBar: AppBar(
        // 对齐 Swift TableDataView：左侧「返回 + 筛选&排序」，右侧「编辑 / 导出」。
        automaticallyImplyLeading: false,
        leadingWidth: 112,
        leading: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back),
              tooltip: '返回',
              onPressed: () => Navigator.of(context).maybePop(),
            ),
            IconButton(
              icon: const Icon(Icons.filter_list),
              tooltip: '筛选&排序',
              onPressed: _editMode ? null : _openFilter,
            ),
          ],
        ),
        title: GestureDetector(
          onTap: () => _showFullTableName(fullTitle),
          child: Tooltip(
            message: fullTitle,
            child: Text(
              widget.table,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
        actions: [
          if (_editMode) ...[
            TextButton(
              onPressed: _saving ? null : _cancelEdit,
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: (_hasChanges && !_saving) ? _saveEdits : null,
              child: _saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('保存'),
            ),
          ] else ...[
            if (pkOk && hasFilter)
              IconButton(
                icon: const Icon(Icons.edit),
                tooltip: '编辑',
                onPressed: (_data?.isResultSet ?? false) ? _enterEdit : null,
              ),
            // 导出中显示转圈（导出会分块拉全量，可能耗时）。
            if (_exporting)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: Center(
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              )
            else
              PopupMenuButton<String>(
                icon: const Icon(Icons.ios_share),
                tooltip: '导出',
                enabled: _data?.isResultSet ?? false,
                onSelected: (v) => _export(v),
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
          // 顶部状态条（对齐 Swift：左「共 N 条 · 第 x/y 页」，右编辑态提示）
          Container(
            color: Colors.grey.withValues(alpha: 0.06),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Row(
              children: [
                Text(
                  '共 $_rowCount 条 · 第 $_page/$_maxPage 页',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
                const Spacer(),
                if (_editMode && !pkOk)
                  const Text(
                    '⚠ 无主键/唯一键，不可保存',
                    style: TextStyle(fontSize: 11, color: Colors.orange),
                    maxLines: 1,
                  ),
              ],
            ),
          ),
          if (_editMessage != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(_editMessage!,
                    style: const TextStyle(color: Colors.green, fontSize: 12)),
              ),
            ),
          if (_editError != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(_editError!,
                    style: const TextStyle(color: Colors.red, fontSize: 12)),
              ),
            ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Text('错误：$_error',
                              style: const TextStyle(color: Colors.red)),
                        ),
                      )
                    : _data != null && _data!.isResultSet
                        ? (_editMode
                            ? _buildEditableGrid()
                            : ResultGrid(
                                columns: _data!.columns,
                                rows: _data!.rows,
                                primaryKey: pk,
                                controller: _gridController,
                              ))
                        : const Center(child: Text('无数据')),
          ),
          const Divider(height: 1),
          // 底部分页栏（对齐 Swift：上一页 / 页码 / 下一页 + N 条/页 + 缩放%）
          ListenableBuilder(
            listenable: _gridController,
            builder: (context, _) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              child: Row(
                children: [
                  TextButton(
                    onPressed: (_page > 1 && !_loading && !_editMode)
                        ? () => _gotoPage(_page - 1)
                        : null,
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.chevron_left, size: 18),
                        Text('上一页'),
                      ],
                    ),
                  ),
                  Text('$_page / $_maxPage',
                      style: const TextStyle(fontSize: 12)),
                  TextButton(
                    onPressed: (_page < _maxPage && !_loading && !_editMode)
                        ? () => _gotoPage(_page + 1)
                        : null,
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('下一页'),
                        Icon(Icons.chevron_right, size: 18),
                      ],
                    ),
                  ),
                  const Spacer(),
                  PopupMenuButton<int>(
                    tooltip: '每页条数',
                    onSelected: _changePageSize,
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 50, child: Text('50 条/页')),
                      PopupMenuItem(value: 100, child: Text('100 条/页')),
                      PopupMenuItem(value: 200, child: Text('200 条/页')),
                      PopupMenuItem(value: 500, child: Text('500 条/页')),
                    ],
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 8),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('$ps 条/页',
                              style: const TextStyle(fontSize: 12)),
                          const Icon(Icons.arrow_drop_down, size: 18),
                        ],
                      ),
                    ),
                  ),
                  if (_gridController.scale != 1)
                    TextButton(
                      onPressed: _gridController.reset,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.refresh, size: 16),
                          Text('${(_gridController.scale * 100).round()}%',
                              style: const TextStyle(fontSize: 12)),
                        ],
                      ),
                    ),
                ],
              ),
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
    // 对齐 Swift：主键列底色为主题色 10%，表头标 🔑🔒（🔒 表示只读锁定）。
    final pkBg = Theme.of(context).colorScheme.primary.withValues(alpha: 0.10);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SingleChildScrollView(
        child: DataTable(
          columns: [
            for (var ci = 0; ci < cols.length; ci++)
              DataColumn(
                label: Text((ci == pkIndex ? '🔑🔒 ' : '') + cols[ci]),
              ),
          ],
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
                      controller: _editControllers['$ri-$ci'],
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
