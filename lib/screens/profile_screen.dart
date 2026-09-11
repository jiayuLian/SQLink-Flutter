import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../settings/app_settings.dart';

/// 「我的」标签页（对齐 Swift ProfileView 的版式：外观 / 关于）。
/// 说明：Flutter 版按用户要求去掉了账号 / 会员 / 激活体系，故此处不含账号区。
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  static const _authorWeChat = 'cute6697';
  static const _authorEmail = 'lianjiayu998@163.com';

  @override
  Widget build(BuildContext context) {
    final settings = Provider.of<AppSettings>(context);
    return Scaffold(
      appBar: AppBar(title: const Text('我的')),
      body: ListView(
        children: [
          // 外观（对齐 Swift ProfileView 的「外观」Section）
          const _SectionHeader('外观'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: SegmentedButton<ThemeMode>(
              segments: const [
                ButtonSegment(value: ThemeMode.system, label: Text('跟随系统')),
                ButtonSegment(value: ThemeMode.light, label: Text('浅色')),
                ButtonSegment(value: ThemeMode.dark, label: Text('深色')),
              ],
              selected: {settings.themeMode},
              onSelectionChanged: (s) => settings.setTheme(s.first),
            ),
          ),

          // 查询（保留 Flutter 版既有设置项）
          const _SectionHeader('查询'),
          SwitchListTile(
            title: const Text('自动保存 SQL 历史'),
            value: settings.autoSaveSQL,
            onChanged: (v) => settings.setAutoSave(v),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextFormField(
              initialValue: settings.pageSize.toString(),
              decoration: const InputDecoration(labelText: '默认每页条数'),
              keyboardType: TextInputType.number,
              onFieldSubmitted: (v) {
                final n = int.tryParse(v);
                if (n != null && n > 0) settings.setPageSize(n);
              },
            ),
          ),

          // 关于（对齐 Swift AboutView）
          const _SectionHeader('关于'),
          const ListTile(
            title: Text('当前版本'),
            trailing: Text('1.0.0'),
          ),
          ListTile(
            title: const Text('微信号'),
            trailing: const Text(_authorWeChat),
            onTap: () {
              Clipboard.setData(const ClipboardData(text: _authorWeChat));
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('微信号 $_authorWeChat 已复制，添加时请备注来意'),
                ),
              );
            },
          ),
          ListTile(
            title: const Text('邮箱'),
            subtitle: const Text(_authorEmail),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 24),
            child: Text(
              'SQLink 为本地远程 MySQL 客户端，连接密码仅保存在本机'
              '（iOS Keychain / Android 加密存储），不会上传任何服务器。',
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        title,
        style: const TextStyle(fontWeight: FontWeight.bold),
      ),
    );
  }
}
