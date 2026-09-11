import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../services/update_service.dart';
import '../settings/app_settings.dart';
import '../widgets/update_dialog.dart';

/// 「我的」标签页（对齐 Swift ProfileView 的版式：分组卡片 + 外观 / 关于）。
/// 说明：Flutter 版按用户要求去掉了账号 / 会员 / 激活体系，故此处不含账号区。
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  static const _authorWeChat = 'cute6697';
  static const _authorEmail = 'lianjiayu998@163.com';

  /// 本机版本（形如 `1.0.0 (123)`），读取完成前显示占位。
  String _versionLabel = '';

  /// 是否正在检查更新。
  bool _checking = false;

  /// 上次检查是否发现有新版本（用于在「检查更新」行右侧提示）。
  bool _hasUpdate = false;

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    final local = await UpdateService.localVersion();
    if (!mounted) return;
    setState(() => _versionLabel = '${local.version} (${local.build})');
  }

  /// 用户主动点「检查更新」：无论结果如何都要给一句反馈，不静默。
  Future<void> _checkUpdate() async {
    if (_checking) return;
    setState(() => _checking = true);
    final result = await UpdateService.check();
    if (!mounted) return;
    setState(() {
      _checking = false;
      _hasUpdate = result.status == UpdateStatus.available;
    });

    final info = result.info;
    if (result.status == UpdateStatus.available && info != null) {
      // 用户主动检查时照常弹窗（即使启动时的静默检查已经提示过）。
      await UpdateService.markNotified(info.latestLabel);
      await UpdateService.markChecked();
      if (!mounted) return;
      await showUpdateDialog(context, info);
      return;
    }
    if (!mounted) return;
    final message = result.status == UpdateStatus.failed
        ? (result.error ?? '检查更新失败')
        : '当前已是最新版本';
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

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
                ListTile(
                  title: const Text('当前版本'),
                  trailing:
                      Text(_versionLabel.isEmpty ? '读取中…' : _versionLabel),
                ),
                const Divider(height: 1),
                ListTile(
                  title: const Text('检查更新'),
                  trailing: _checking
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (_hasUpdate)
                              Text(
                                '有新版本',
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                              ),
                            const SizedBox(width: 4),
                            Icon(
                              Icons.chevron_right,
                              size: 20,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurface
                                  .withValues(alpha: 0.3),
                            ),
                          ],
                        ),
                  onTap: _checking ? null : _checkUpdate,
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
