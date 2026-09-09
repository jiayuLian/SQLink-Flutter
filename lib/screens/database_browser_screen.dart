import 'package:flutter/material.dart';
import '../services/mysql_service.dart';
import '../screens/table_data_screen.dart';
import '../screens/query_console_screen.dart';

/// 数据库浏览（对齐 Swift 的 DatabaseBrowserView → TableListView 分层下钻）。
/// - [db] 为 null：显示数据库列表；点击进入该库的表列表。
/// - [db] 非 null：显示该库的表列表；点击进入表数据页。
/// 两级均提供「新建查询」入口；表列表页通过系统返回键回到数据库列表（切换库）。
/// 数据库列表与表列表顶部均提供搜索框，实时过滤名称（不区分大小写）。
class DatabaseBrowserScreen extends StatefulWidget {
  final MySQLService service;
  final String? db;
  const DatabaseBrowserScreen({super.key, required this.service, this.db});

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

  void _newQuery(BuildContext context, [String? db]) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => QueryConsoleScreen(
          service: widget.service,
          db: db ?? widget.service.profile.database,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDbList = widget.db == null;
    return Scaffold(
      appBar: AppBar(
        title: Text(isDbList ? '数据库' : widget.db!),
        // 表列表页由数据库列表 push 进入，系统返回键即「切换库」。
        actions: [
          IconButton(
            icon: const Icon(Icons.add_comment),
            tooltip: '新建查询',
            onPressed: () => _newQuery(context, isDbList ? null : widget.db),
          ),
        ],
      ),
      body: isDbList ? _buildDbList() : _buildTableList(),
    );
  }

  Widget _buildDbList() {
    return FutureBuilder<List<String>>(
      future: _databases,
      builder: (ctx, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return Center(child: Text('加载失败：${snap.error}'));
        }
        final dbs = snap.data ?? [];
        final filtered = dbs.where(_matches).toList();
        if (dbs.isEmpty) {
          return const Center(child: Text('没有可用的数据库'));
        }
        if (filtered.isEmpty) {
          return Column(
            children: [
              _searchBar(hint: '搜索数据库'),
              const Expanded(child: Center(child: Text('没有匹配的数据库'))),
            ],
          );
        }
        return Column(
          children: [
            _searchBar(hint: '搜索数据库'),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.all(12),
                itemCount: filtered.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (_, i) => Card(
                  child: ListTile(
                    leading: const Icon(Icons.folder),
                    title: Text(filtered[i]),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => DatabaseBrowserScreen(
                            service: widget.service, db: filtered[i]),
                      ),
                    ),
                  ),
                ),
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
      builder: (ctx, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return Center(child: Text('加载失败：${snap.error}'));
        }
        final tables = snap.data ?? [];
        final filtered = tables.where((t) => _matches(t['name'] ?? '')).toList();
        if (tables.isEmpty) {
          return const Center(child: Text('（该库没有表）'));
        }
        if (filtered.isEmpty) {
          return Column(
            children: [
              _searchBar(hint: '搜索表'),
              const Expanded(child: Center(child: Text('没有匹配的表'))),
            ],
          );
        }
        return Column(
          children: [
            _searchBar(hint: '搜索表'),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.all(12),
                itemCount: filtered.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (_, i) {
                  final t = filtered[i];
                  final isView = t['type'] == 'VIEW';
                  return Card(
                    child: ListTile(
                      leading: Icon(isView ? Icons.visibility : Icons.table_chart),
                      title: Text(t['name'] ?? ''),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => TableDataScreen(
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
