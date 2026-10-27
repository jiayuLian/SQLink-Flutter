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

  /// 失败页「重试」：回到连接中状态重新建连，不用退出去重来。
  void _retry() {
    setState(() {
      _error = null;
      _connecting = true;
    });
    _connect();
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
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // 网络抖动 / 服务器刚重启时，不用退出去重新点一次连接。
                    FilledButton(
                      onPressed: _retry,
                      child: const Text('重试'),
                    ),
                    const SizedBox(width: 12),
                    OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('返回'),
                    ),
                  ],
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
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 18),
                Text(
                  '正在连接 ${widget.profile.host}:${widget.profile.port}…',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 14),
                ),
                const SizedBox(height: 6),
                const Text(
                  '主机不可达时最长等待 30 秒\n等不及可以直接取消',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
                const SizedBox(height: 20),
                // 取消：退出本页即可。dispose 会关掉正在建的连接，
                // connect() 完成时 _disposed 兜底再关一次，不会泄漏 socket。
                OutlinedButton(
                  onPressed: () => Navigator.of(context).maybePop(),
                  child: const Text('取消'),
                ),
              ],
            ),
          ),
        ),
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
