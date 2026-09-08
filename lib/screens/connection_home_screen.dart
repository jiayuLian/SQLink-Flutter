import 'package:flutter/material.dart';
import '../models/connection.dart';
import '../services/mysql_service.dart';
import 'query_console_screen.dart';
import 'database_browser_screen.dart';

class ConnectionHomeScreen extends StatefulWidget {
  final ConnectionProfile profile;
  final String password;
  const ConnectionHomeScreen({
    super.key,
    required this.profile,
    required this.password,
  });

  @override
  State<ConnectionHomeScreen> createState() => _ConnectionHomeScreenState();
}

class _ConnectionHomeScreenState extends State<ConnectionHomeScreen> {
  late final MySQLService _service;
  bool _connecting = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _service = MySQLService(widget.profile);
    _connect();
  }

  Future<void> _connect() async {
    try {
      await _service.connect(widget.password);
      if (mounted) setState(() => _connecting = false);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  @override
  void dispose() {
    _service.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.profile.name)),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, size: 48, color: Colors.red),
                const SizedBox(height: 12),
                Text('连接失败：\n$_error', textAlign: TextAlign.center),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('返回'),
                ),
              ],
            ),
          ),
        ),
      );
    }
    if (_connecting) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.profile.name)),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.profile.name.isEmpty
              ? widget.profile.host
              : widget.profile.name),
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.terminal), text: '查询'),
              Tab(icon: Icon(Icons.schema), text: '浏览'),
            ],
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.logout),
              tooltip: '断开',
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        ),
        body: TabBarView(
          children: [
            QueryConsoleScreen(service: _service, db: widget.profile.database),
            DatabaseBrowserScreen(service: _service),
          ],
        ),
      ),
    );
  }
}
