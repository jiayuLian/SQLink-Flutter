import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/update_service.dart';

/// 弹出「发现新版本」对话框（更新内容 + 去下载）。
///
/// 跳转策略：Android 给 APK 直链（一点即下）；iOS 只能打开发行版页面，
/// 由用户自行下载 IPA 后用 TrollStore 安装。
Future<void> showUpdateDialog(BuildContext context, UpdateInfo info) async {
  // 先取出 messenger，避免 await 之后再摸外层 context（use_build_context_synchronously）。
  final messenger = ScaffoldMessenger.of(context);
  final isIOS = Theme.of(context).platform == TargetPlatform.iOS;
  final url = isIOS ? info.releaseUrl : info.primaryUrl;

  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('发现新版本'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('最新版本 ${info.latestLabel}　当前 ${info.currentLabel}',
                  style: const TextStyle(fontSize: 13)),
              if (info.notes.isNotEmpty) ...[
                const SizedBox(height: 14),
                const Text('更新内容',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                _NotesView(info.notes),
              ],
              const SizedBox(height: 14),
              Text(
                isIOS
                    ? '下载 IPA 后用 TrollStore 安装即可覆盖旧版本。'
                    : '下载 APK 后直接覆盖安装，连接与设置都会保留。',
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(ctx)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: 0.6),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('稍后'),
        ),
        FilledButton(
          onPressed: () async {
            final ok = await _open(url);
            if (ctx.mounted) Navigator.of(ctx).pop();
            if (!ok) {
              messenger.showSnackBar(
                SnackBar(content: Text('无法打开链接：$url')),
              );
            }
          },
          child: const Text('去下载'),
        ),
      ],
    ),
  );
}

Future<bool> _open(String url) async {
  try {
    return await launchUrl(Uri.parse(url),
        mode: LaunchMode.externalApplication);
  } catch (_) {
    return false;
  }
}

/// 把更新记录（Markdown 原文）渲染成简易列表：
/// `### 日期` 作为小节标题，`- 条目` 作为项目符号行，其余按普通文本。
class _NotesView extends StatelessWidget {
  final String text;
  const _NotesView(this.text);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurface.withValues(alpha: 0.75);
    final children = <Widget>[];
    for (final raw in text.split('\n')) {
      final line = raw.trim();
      if (line.isEmpty) continue;
      if (line.startsWith('### ')) {
        children.add(Padding(
          padding: const EdgeInsets.only(top: 6, bottom: 2),
          child: Text(line.substring(4).trim(),
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
        ));
      } else if (line.startsWith('- ')) {
        children.add(Padding(
          padding: const EdgeInsets.only(left: 4, top: 3),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('•  ', style: TextStyle(fontSize: 13, color: muted)),
              Expanded(
                child: Text(line.substring(2).trim(),
                    style: TextStyle(fontSize: 13, height: 1.5, color: muted)),
              ),
            ],
          ),
        ));
      } else {
        children.add(Padding(
          padding: const EdgeInsets.only(top: 3, bottom: 2),
          child: Text(line,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
        ));
      }
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: children);
  }
}
