import 'package:flutter/material.dart';
import '../services/mysql_service.dart';
import '../screens/table_data_screen.dart';
import '../screens/query_console_screen.dart';

/// 数据库浏览（对齐 Swift 的 DatabaseBrowserView → TableListView 分层下钻）。
/// - [db] 为 null：显示数据库列表；点击进入该库的表列表。
/// - [db] 非 null：显示该库的表列表；点击进入表数据页。
/// 两级均提供「新建查询」入口；表列表页通过系统返回键回到数据库列表（切换库）。
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

  @override
  void initState() {
    super.initState();
    if (widget.db == null) {
      _databases = widget.service.listDatabases();
    } else {
      _tables = widget.service.listTables(widget.db!);
    }
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
        if (dbs.isEmpty) {
          return const Center(child: Text('没有可用的数据库'));
        }
        return ListView.separated(
          padding: const EdgeInsets.all(12),
          itemCount: dbs.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (_, i) => Card(
            child: ListTile(
              leading: const Icon(Icons.folder),
              title: Text(dbs[i]),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) =>
                      DatabaseBrowserScreen(service: widget.service, db: dbs[i]),
                ),
              ),
            ),
          ),
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
        if (tables.isEmpty) {
          return const Center(child: Text('（该库没有表）'));
        }
        return ListView.separated(
          padding: const EdgeInsets.all(12),
          itemCount: tables.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (_, i) {
            final t = tables[i];
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
        );
      },
    );
  }
}
