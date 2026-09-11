import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../settings/app_settings.dart';

/// 「我的」标签页（对齐 Swift ProfileView 的版式：分组卡片 + 外观 / 关于）。
/// 说明：Flutter 版按用户要求去掉了账号 / 会员 / 激活体系，故此处不含账号区。
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  static const _authorWeChat = 'cute6697';
  static const _authorEmail = 'lianjiayu998@163.com';

  @override
  Widget build(BuildContext context) {
    final settings = Provider.of<AppSettings>(context);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('我的')),
      // 分组卡片版式（对齐 Swift ProfileView 的 Form + Section）。
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
        children: [
          // 外观
          Card(
            margin: EdgeInsets.zero,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const _SectionHeader('外观'),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                  child: SegmentedButton<ThemeMode>(
                    segments: const [
                      ButtonSegment(
                          value: ThemeMode.system, label: Text('跟随系统')),
                      ButtonSegment(value: ThemeMode.light, label: Text('浅色')),
                      ButtonSegment(value: ThemeMode.dark, label: Text('深色')),
                    ],
                    selected: {settings.themeMode},
                    onSelectionChanged: (s) => settings.setTheme(s.first),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // 查询（保留 Flutter 版既有设置项）
          Card(
            margin: EdgeInsets.zero,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const _SectionHeader('查询'),
                SwitchListTile(
                  title: const Text('自动保存 SQL 历史'),
                  value: settings.autoSaveSQL,
                  onChanged: (v) => settings.setAutoSave(v),
                ),
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  child: TextFormField(
                    initialValue: settings.pageSize.toString(),
                    decoration: const InputDecoration(
                      labelText: '默认每页条数',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                    // 输入即生效（原来只在按回车 onSubmit 时保存，输完直接点别处
                    // 会静默丢失），空串 / 非数字 / 非正数一律忽略。
                    onChanged: (v) {
                      final n = int.tryParse(v.trim());
                      if (n != null && n > 0) settings.setPageSize(n);
                    },
                    onFieldSubmitted: (v) {
                      final n = int.tryParse(v.trim());
                      if (n != null && n > 0) settings.setPageSize(n);
                    },
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // 关于（对齐 Swift AboutView）
          Card(
            margin: EdgeInsets.zero,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const _SectionHeader('关于'),
                const ListTile(
                  title: Text('当前版本'),
                  trailing: Text('1.0.0'),
                ),
                const Divider(height: 1),
                ListTile(
                  title: const Text('微信号'),
                  trailing: const Text(_authorWeChat),
                  onTap: () {
                    Clipboard.setData(
                        const ClipboardData(text: _authorWeChat));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('微信号 $_authorWeChat 已复制，添加时请备注来意'),
                      ),
                    );
                  },
                ),
                const Divider(height: 1),
                const ListTile(
                  title: Text('邮箱'),
                  subtitle: Text(_authorEmail),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  child: Text(
                    'SQLink 为本地远程 MySQL 客户端，连接密码仅保存在本机'
                    '（iOS Keychain / Android 加密存储），不会上传任何服务器。',
                    style: TextStyle(
                      fontSize: 12,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                ),
              ],
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
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
      child: Text(
        title,
        style: const TextStyle(fontWeight: FontWeight.bold),
      ),
    );
  }
}
