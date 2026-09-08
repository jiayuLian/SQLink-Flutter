import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:provider/provider.dart';
import '../models/connection.dart';
import '../services/connection_store.dart';
import '../services/secure_storage.dart';
import 'connection_edit_screen.dart';
import 'connection_home_screen.dart';
import 'settings_screen.dart';

class ConnectionsScreen extends StatelessWidget {
  const ConnectionsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('SQLink'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: '设置',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
          ),
        ],
      ),
      body: Consumer<ConnectionStore>(
        builder: (context, store, _) {
          if (store.connections.isEmpty) {
            return const Center(
              child: Text('还没有连接，点右下角 + 添加一个 MySQL 连接'),
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
      floatingActionButton: FloatingActionButton(
        tooltip: '新增连接',
        child: const Icon(Icons.add),
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const ConnectionEditScreen()),
        ),
      ),
    );
  }
}

class _ConnectionCard extends StatelessWidget {
  final ConnectionProfile profile;
  const _ConnectionCard({required this.profile});

  @override
  Widget build(BuildContext context) {
    // 对齐 Swift 版 ConnectionsView.swipeActions：
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
          leading: const Icon(Icons.storage),
          title: Text(profile.name.isEmpty ? profile.host : profile.name),
          subtitle: Text(
            '${profile.user}@${profile.host}:${profile.port}'
            '${profile.database.isNotEmpty ? ' / ${profile.database}' : ''}',
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (profile.useTLS)
                const Tooltip(
                  message: '已启用 SSL 加密',
                  child: Icon(Icons.lock, size: 18, color: Colors.green),
                ),
            ],
          ),
          onTap: () => _connect(context),
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
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('删除连接'),
            content: Text('确定删除连接「${profile.name}」？密码也会一并清除。'),
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
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    try {
      final pw = await SecureStorage.getPassword(profile.id) ?? '';
      if (!context.mounted) return;
      Navigator.of(context).pop(); // 关闭 loading
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ConnectionHomeScreen(profile: profile, password: pw),
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      Navigator.of(context).pop();
      scaffold.showSnackBar(SnackBar(content: Text('连接失败：$e')));
    }
  }
}
