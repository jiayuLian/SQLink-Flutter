import 'package:flutter/material.dart';
import '../services/mysql_service.dart';
import '../models/connection.dart' show ColumnInfo;

class DatabaseBrowserScreen extends StatefulWidget {
  final MySQLService service;
  const DatabaseBrowserScreen({super.key, required this.service});

  @override
  State<DatabaseBrowserScreen> createState() => _DatabaseBrowserScreenState();
}

class _DatabaseBrowserScreenState extends State<DatabaseBrowserScreen> {
  late final Future<List<String>> _databases;

  @override
  void initState() {
    super.initState();
    _databases = widget.service.listDatabases();
  }

  @override
  Widget build(BuildContext context) {
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
        return ListView.builder(
          itemCount: dbs.length,
          itemBuilder: (_, i) => _DatabaseTile(service: widget.service, db: dbs[i]),
        );
      },
    );
  }
}

class _DatabaseTile extends StatefulWidget {
  final MySQLService service;
  final String db;
  const _DatabaseTile({required this.service, required this.db});

  @override
  State<_DatabaseTile> createState() => _DatabaseTileState();
}

class _DatabaseTileState extends State<_DatabaseTile> {
  List<Map<String, String>>? _tables;
  bool _loading = false;

  Future<void> _load() async {
    if (_tables != null) return;
    setState(() => _loading = true);
    try {
      _tables = await widget.service.listTables(widget.db);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      leading: const Icon(Icons.folder),
      title: Text(widget.db),
      onExpansionChanged: (v) => v ? _load() : null,
      children: [
        if (_loading)
          const ListTile(title: Text('加载表…'))
        else if (_tables == null)
          const SizedBox.shrink()
        else if (_tables!.isEmpty)
          const ListTile(title: Text('（无表）'))
        else
          for (final t in _tables!)
            _TableTile(service: widget.service, db: widget.db, table: t),
      ],
    );
  }
}

class _TableTile extends StatefulWidget {
  final MySQLService service;
  final String db;
  final Map<String, String> table;
  const _TableTile({
    required this.service,
    required this.db,
    required this.table,
  });

  @override
  State<_TableTile> createState() => _TableTileState();
}

class _TableTileState extends State<_TableTile> {
  List<ColumnInfo>? _columns;
  bool _loading = false;

  Future<void> _load() async {
    if (_columns != null) return;
    setState(() => _loading = true);
    try {
      _columns = await widget.service.listColumns(widget.db, widget.table['name']!);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isView = widget.table['type'] == 'VIEW';
    return ExpansionTile(
      leading: Icon(isView ? Icons.visibility : Icons.table_chart),
      title: Text(widget.table['name'] ?? ''),
      onExpansionChanged: (v) => v ? _load() : null,
      children: [
        ListTile(
          leading: const Icon(Icons.preview),
          title: const Text('浏览数据'),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => TableDataScreen(
                service: widget.service,
                db: widget.db,
                table: widget.table['name']!,
              ),
            ),
          ),
        ),
        if (_loading)
          const ListTile(title: Text('加载列…'))
        else if (_columns == null)
          const SizedBox.shrink()
        else
          for (final c in _columns!)
            ListTile(
              dense: true,
              title: Text(c.field),
              subtitle: Text(
                '${c.type}'
                '${c.key.isNotEmpty ? ' · key=${c.key}' : ''}'
                '${c.nullAllowed == 'NO' ? ' · NOT NULL' : ''}',
              ),
            ),
      ],
    );
  }
}
