import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../settings/app_settings.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = Provider.of<AppSettings>(context);
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('外观', style: TextStyle(fontWeight: FontWeight.bold)),
          DropdownButtonFormField<ThemeMode>(
            initialValue: settings.themeMode,
            decoration: const InputDecoration(labelText: '主题'),
            items: const [
              DropdownMenuItem(value: ThemeMode.system, child: Text('跟随系统')),
              DropdownMenuItem(value: ThemeMode.light, child: Text('浅色')),
              DropdownMenuItem(value: ThemeMode.dark, child: Text('深色')),
            ],
            onChanged: (v) => settings.setTheme(v!),
          ),
          const SizedBox(height: 16),
          const Text('查询', style: TextStyle(fontWeight: FontWeight.bold)),
          SwitchListTile(
            title: const Text('自动保存 SQL 历史'),
            value: settings.autoSaveSQL,
            onChanged: (v) => settings.setAutoSave(v),
          ),
          TextFormField(
            initialValue: settings.pageSize.toString(),
            decoration: const InputDecoration(labelText: '每页条数'),
            keyboardType: TextInputType.number,
            onFieldSubmitted: (v) {
              final n = int.tryParse(v);
              if (n != null && n > 0) settings.setPageSize(n);
            },
          ),
          const SizedBox(height: 16),
          const Text(
            'SQLink 为本地远程 MySQL 客户端，连接密码仅保存在本机'
            '（iOS Keychain / Android 加密存储），不会上传任何服务器。',
            style: TextStyle(color: Colors.grey),
          ),
        ],
      ),
    );
  }
}
