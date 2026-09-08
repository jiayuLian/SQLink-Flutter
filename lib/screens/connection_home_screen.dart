import 'package:flutter/material.dart';
import '../models/connection.dart';
import '../services/mysql_service.dart';
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
    // 连接成功后进入数据库浏览（分层下钻：库 → 表 → 数据），
    // 对齐 Swift 的 DatabaseBrowserView。若编辑连接时填写了默认数据库，
    // 直接进入该库的表列表；否则显示全部数据库列表。
    final defaultDb = widget.profile.database.trim();
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.profile.name.isEmpty
            ? widget.profile.host
            : widget.profile.name),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: '断开',
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
      body: DatabaseBrowserScreen(
        service: _service,
        db: defaultDb.isNotEmpty ? defaultDb : null,
      ),
    );
  }
}
