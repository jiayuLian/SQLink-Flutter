import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:provider/provider.dart';
import '../models/connection.dart';
import '../services/connection_store.dart';
import '../services/secure_storage.dart';
import 'connection_edit_screen.dart';
import 'connection_home_screen.dart';

class ConnectionsScreen extends StatelessWidget {
  const ConnectionsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // 对齐 Swift ConnectionsView：新增入口在导航栏右上角「+」；「我的」为独立底部标签。
    return Scaffold(
      appBar: AppBar(
        title: const Text('SQLink'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: '新增连接',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const ConnectionEditScreen()),
            ),
          ),
        ],
      ),
      body: Consumer<ConnectionStore>(
        builder: (context, store, _) {
          if (store.connections.isEmpty) {
            // 对齐 Swift ConnectionsView 空态：次要文字色。
            return const Center(
              child: Text(
                '还没有连接，点右上角 + 添加一个',
                style: TextStyle(color: Colors.grey),
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: store.connections.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, i) {
              final c = store.connections[i];
              return _ConnectionCard(profile: c);
            },
          );
        },
      ),
    );
  }
}

class _ConnectionCard extends StatelessWidget {
  final ConnectionProfile profile;
  const _ConnectionCard({required this.profile});

  @override
  Widget build(BuildContext context) {
    // 对齐 Swift ConnectionsView.swipeActions：
    // 左滑（end）露出“编辑 + 删除”两个窄按钮；右滑（start）露出“编辑”。
    // 卡片内容始终可见，不会被整行红色背景遮住。
    return Slidable(
      key: ValueKey(profile.id),
      startActionPane: ActionPane(
        motion: const BehindMotion(),
        extentRatio: 0.22,
        children: [
          SlidableAction(
            onPressed: (_) => _openEdit(context),
            backgroundColor: Theme.of(context).colorScheme.primary,
            foregroundColor: Colors.white,
            icon: Icons.edit,
            label: '编辑',
          ),
        ],
      ),
      endActionPane: ActionPane(
        motion: const BehindMotion(),
        extentRatio: 0.44,
        children: [
          SlidableAction(
            onPressed: (_) => _openEdit(context),
            backgroundColor: Theme.of(context).colorScheme.primary,
            foregroundColor: Colors.white,
            icon: Icons.edit,
            label: '编辑',
          ),
          SlidableAction(
            onPressed: (_) => _confirmDelete(context),
            backgroundColor: Colors.red,
            foregroundColor: Colors.white,
            icon: Icons.delete,
            label: '删除',
          ),
        ],
      ),
      child: Card(
        child: ListTile(
          // 对齐 Swift ConnectionRow：图标用强调色。
          leading: Icon(Icons.dns, color: Theme.of(context).colorScheme.primary),
          title: Text(profile.name.isEmpty ? profile.host : profile.name),
          subtitle: Text(
            // 对齐 Swift ConnectionRow：`user@host:port` + 有库时紧接 `/db`（不带空格）。
            '${profile.user}@${profile.host}:${profile.port}'
            '${profile.database.isNotEmpty ? '/${profile.database}' : ''}',
          ),
          // 对齐 Swift ConnectionRow：TLS 锁图标 + 行内铅笔按钮。
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (profile.useTLS)
                const Tooltip(
                  message: '已启用 SSL 加密',
                  child: Icon(Icons.lock, size: 18, color: Colors.green),
                ),
              IconButton(
                icon: const Icon(Icons.edit),
                tooltip: '编辑',
                onPressed: () => _openEdit(context),
              ),
            ],
          ),
          onTap: () => _connect(context),
          // 对齐 Swift ConnectionRow 的 .contextMenu：长按弹出「编辑 / 删除」。
          onLongPress: () => _showContextMenu(context),
        ),
      ),
    );
  }

  /// 长按菜单（对齐 Swift 的 contextMenu）。
  void _showContextMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit),
              title: const Text('编辑'),
              onTap: () {
                Navigator.of(ctx).pop();
                _openEdit(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete, color: Colors.red),
              title: const Text('删除', style: TextStyle(color: Colors.red)),
              onTap: () {
                Navigator.of(ctx).pop();
                _confirmDelete(context);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _openEdit(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ConnectionEditScreen(profile: profile),
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context) async {
    // 连接名为空时回退显示 host（对齐列表行/错误提示的展示口径）。
    final label = profile.name.isEmpty ? profile.host : profile.name;
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('删除连接'),
            content: Text('确定删除连接「$label」？密码也会一并清除。'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('取消'),
              ),
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('删除'),
              ),
            ],
          ),
        ) ??
        false;
    if (confirmed) {
      await SecureStorage.deletePassword(profile.id);
      if (context.mounted) {
        Provider.of<ConnectionStore>(context, listen: false).remove(profile.id);
      }
    }
  }

  void _connect(BuildContext context) async {
    final scaffold = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context);
    // 先弹 loading，再取密码建连；用标志位保证无论走哪条分支都只关一次，
    // 避免中途 return 时留下一个吞掉点击的 loading 遮罩。
    var dialogOpen = true;
    void closeLoading() {
      if (!dialogOpen) return;
      dialogOpen = false;
      nav.pop();
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    try {
      final pw = await SecureStorage.getPassword(profile.id) ?? '';
      closeLoading();
      if (!context.mounted) return;
      await nav.push(
        MaterialPageRoute(
          builder: (_) => ConnectionHomeScreen(profile: profile, password: pw),
        ),
      );
    } catch (e) {
      closeLoading();
      // 去掉 Dart Exception 默认前缀，与测试按钮提示保持一致。
      final detail = e.toString();
      final msg = detail.startsWith('Exception: ')
          ? detail.substring('Exception: '.length)
          : detail;
      scaffold.showSnackBar(SnackBar(content: Text('连接失败：$msg')));
    }
  }
}
