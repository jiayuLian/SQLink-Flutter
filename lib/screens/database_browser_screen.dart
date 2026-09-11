import 'package:flutter/material.dart';
import '../services/mysql_service.dart';
import '../screens/table_detail_screen.dart';
import '../screens/query_console_screen.dart';

/// 数据库浏览（对齐 Swift 的 DatabaseBrowserView → TableListView 分层下钻）。
/// - [db] 为 null：显示数据库列表；导航栏标题为连接名；点击某库进入表列表。
/// - [db] 非 null：显示该库的表列表；点击表进入**表详情页**（两级进表）。
/// 两级列表的**首行**均为「新建查询」（对齐 Swift：
/// 库列表「新建查询」→ 不指定库；表列表「新建查询（库：db）」）。
/// 表列表导航栏右侧提供「切换库」（仅从库列表进入时显示），点击返回库列表。
/// 两个列表顶部均提供搜索框，实时过滤名称（对齐 Swift `.searchable`）。
class DatabaseBrowserScreen extends StatefulWidget {
  final MySQLService service;

  /// 数据库列表页的标题（对齐 Swift：`profile.name`）。
  final String title;
  final String? db;

  /// 表列表页是否显示「切换库」。从库列表进入时为 true；
  /// 用连接里配置的默认库直入时为 false（上游没有库列表可切）。
  final bool showSwitchDb;

  const DatabaseBrowserScreen({
    super.key,
    required this.service,
    required this.title,
    this.db,
    this.showSwitchDb = false,
  });

  @override
  State<DatabaseBrowserScreen> createState() => _DatabaseBrowserScreenState();
}

class _DatabaseBrowserScreenState extends State<DatabaseBrowserScreen> {
  late final Future<List<String>> _databases;
  late final Future<List<Map<String, String>>> _tables;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    if (widget.db == null) {
      _databases = widget.service.listDatabases();
    } else {
      _tables = widget.service.listTables(widget.db!);
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  bool _matches(String text) {
    if (_searchQuery.isEmpty) return true;
    return text.toLowerCase().contains(_searchQuery.toLowerCase());
  }

  Widget _searchBar({required String hint}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: TextField(
        controller: _searchController,
        decoration: InputDecoration(
          hintText: hint,
          prefixIcon: const Icon(Icons.search),
          suffixIcon: _searchQuery.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    _searchController.clear();
                    setState(() => _searchQuery = '');
                  },
                ),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(vertical: 10),
        ),
        onChanged: (v) => setState(() => _searchQuery = v),
      ),
    );
  }

  /// 「新建查询」首个列表行（对齐 Swift 的 NavigationLink 首行）。
  Widget _newQueryRow(String label, String? db) {
    final color = Theme.of(context).colorScheme.primary;
    return Card(
      child: ListTile(
        leading: Icon(Icons.terminal, color: color),
        title: Text(
          label,
          style: TextStyle(color: color),
          overflow: TextOverflow.ellipsis,
        ),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => QueryConsoleScreen(service: widget.service, db: db),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDbList = widget.db == null;
    return Scaffold(
      appBar: AppBar(
        // 对齐 Swift：库列表标题 = 连接名；表列表标题 = 库名。
        title: Text(isDbList ? widget.title : widget.db!),
        actions: [
          if (!isDbList && widget.showSwitchDb)
            TextButton(
              onPressed: () => Navigator.of(context).maybePop(),
              child: const Text('切换库'),
            ),
        ],
      ),
      body: isDbList ? _buildDbList() : _buildTableList(),
    );
  }

  Widget _buildDbList() {
    return FutureBuilder<List<String>>(
      future: _databases,
      builder: (_, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return Center(child: Text('加载失败：${snap.error}'));
        }
        final dbs = snap.data ?? [];
        final filtered = dbs.where(_matches).toList();
        if (dbs.isEmpty) {
          return Column(
            children: [
              _searchBar(hint: '搜索数据库'),
              Expanded(
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: _newQueryRow('新建查询', null),
                    ),
                    const Expanded(child: Center(child: Text('没有可用的数据库'))),
                  ],
                ),
              ),
            ],
          );
        }
        return Column(
          children: [
            _searchBar(hint: '搜索数据库'),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.all(12),
                // 首行固定为「新建查询」，其余为数据库。
                itemCount: filtered.length + 1,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (_, i) {
                  if (i == 0) return _newQueryRow('新建查询', null);
                  final db = filtered[i - 1];
                  return Card(
                    child: ListTile(
                      leading: const Icon(Icons.folder),
                      title: Text(db),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => DatabaseBrowserScreen(
                            service: widget.service,
                            title: widget.title,
                            db: db,
                            // 从库列表进入，故表列表可「切换库」。
                            showSwitchDb: true,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildTableList() {
    return FutureBuilder<List<Map<String, String>>>(
      future: _tables,
      builder: (_, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return Center(child: Text('加载失败：${snap.error}'));
        }
        final tables = snap.data ?? [];
        final filtered = tables.where((t) => _matches(t['name'] ?? '')).toList();
        if (tables.isEmpty) {
          return Column(
            children: [
              _searchBar(hint: '搜索表'),
              Expanded(
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: _newQueryRow('新建查询（库：${widget.db}）', widget.db),
                    ),
                    const Expanded(child: Center(child: Text('（该库没有表）'))),
                  ],
                ),
              ),
            ],
          );
        }
        return Column(
          children: [
            _searchBar(hint: '搜索表'),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.all(12),
                itemCount: filtered.length + 1,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (_, i) {
                  if (i == 0) {
                    return _newQueryRow('新建查询（库：${widget.db}）', widget.db);
                  }
                  final t = filtered[i - 1];
                  final isView = t['type'] == 'VIEW';
                  return Card(
                    child: ListTile(
                      leading:
                          Icon(isView ? Icons.visibility : Icons.table_chart),
                      title: Text(t['name'] ?? ''),
                      trailing: const Icon(Icons.chevron_right),
                      // 两级进表：先进表详情页（结构 / 建表 SQL / 匹配 N 条），
                      // 再从详情页进「查看数据」（对齐 Swift TableDetailView）。
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => TableDetailScreen(
                            service: widget.service,
                            db: widget.db!,
                            table: t['name']!,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}
