import 'package:flutter/material.dart';
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
    return Dismissible(
      key: Key(profile.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        color: Colors.red,
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      confirmDismiss: (direction) async {
        return await showDialog<bool>(
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
      },
      onDismissed: (_) async {
        await SecureStorage.deletePassword(profile.id);
        Provider.of<ConnectionStore>(context, listen: false).remove(profile.id);
      },
      child: Card(
        child: ListTile(
          leading: const Icon(Icons.storage),
          title: Text(profile.name.isEmpty ? profile.host : profile.name),
          subtitle: Text(
            '${profile.user}@${profile.host}:${profile.port}'
            '${profile.database.isNotEmpty ? ' / ${profile.database}' : ''}'
            '${profile.useTLS ? ' · TLS' : ' · 明文'}',
          ),
          trailing: IconButton(
            icon: const Icon(Icons.edit),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => ConnectionEditScreen(profile: profile),
              ),
            ),
          ),
          onTap: () => _connect(context),
        ),
      ),
    );
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
