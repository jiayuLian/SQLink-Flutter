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

  /// 页面已销毁标记：建连是异步的，若用户在连接过程中返回，
  /// 完成后的连接会挂在已废弃的 service 上永不关闭（socket 泄漏）。
  bool _disposed = false;

  @override
  void initState() {
    super.initState();
    _service = MySQLService(widget.profile);
    _connect();
  }

  Future<void> _connect() async {
    try {
      await _service.connect(widget.password);
      if (_disposed) {
        _service.close();
        return;
      }
      if (mounted) setState(() => _connecting = false);
    } catch (e) {
      if (_disposed) return;
      if (mounted) setState(() => _error = e.toString());
    }
  }

  @override
  void dispose() {
    _disposed = true;
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
                Text(
                  '连接失败：\n${_error!.startsWith('Exception: ') ? _error!.substring('Exception: '.length) : _error}',
                  textAlign: TextAlign.center,
                ),
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
    // 对齐 Swift 的 DatabaseBrowserView。去掉外层 AppBar，避免和
    // DatabaseBrowserScreen 的 AppBar 叠加出现两个返回箭头。
    // 若编辑连接时填写了默认数据库，直接进入该库的表列表；
    // 否则显示全部数据库列表。
    final defaultDb = widget.profile.database.trim();
    return Scaffold(
      body: DatabaseBrowserScreen(
        service: _service,
        // 对齐 Swift DatabaseBrowserView：库列表标题为连接名。
        title: widget.profile.name.isEmpty
            ? widget.profile.host
            : widget.profile.name,
        db: defaultDb.isNotEmpty ? defaultDb : null,
        // 用默认库直入表列表时，上游没有库列表可切换，故不出「切换库」。
        showSwitchDb: false,
      ),
    );
  }
}
