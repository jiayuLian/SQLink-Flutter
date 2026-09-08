import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 查询结果表格（Navicat 风格，对齐 Swift ResultGridView）。
/// 主键列（PRI/UNI）以 🔑 标记并以主题色高亮；单元格等宽字体、定宽列、隔行底色；
/// 点按单元格弹出完整值并支持复制。
class ResultGrid extends StatelessWidget {
  final List<String> columns;
  final List<Map<String, String?>> rows;

  /// 真实主键列名（PRI 优先，其次 UNI）；为 null 时不高亮。
  final String? primaryKey;

  const ResultGrid({
    super.key,
    required this.columns,
    required this.rows,
    this.primaryKey,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final pkIndex = primaryKey == null ? -1 : columns.indexOf(primaryKey!);
    const minW = 80.0;
    const maxW = 160.0;
    const mono = TextStyle(fontFamily: 'monospace');

    Widget headerCell(String label, bool isPk) => Container(
          constraints: const BoxConstraints(minWidth: minW),
          width: maxW,
          padding: const EdgeInsets.all(6),
          color: isPk
              ? scheme.primary.withValues(alpha: 0.22)
              : scheme.primary.withValues(alpha: 0.10),
          child: Text(
            label,
            style: mono.copyWith(fontSize: 13, fontWeight: FontWeight.bold),
            overflow: TextOverflow.ellipsis,
          ),
        );

    Widget cell(String? v, bool isPk, int ri, int ci) {
      final stripe = (ri + ci) % 2 == 0;
      final bg = isPk
          ? scheme.primary.withValues(alpha: 0.10)
          : (stripe ? Colors.grey.withValues(alpha: isDark ? 0.12 : 0.04) : null);
      return GestureDetector(
        onTap: () => _showCell(context, v),
        child: Container(
          constraints: const BoxConstraints(minWidth: minW),
          width: maxW,
          padding: const EdgeInsets.all(6),
          color: bg,
          child: Text(
            v ?? 'NULL',
            style: mono.copyWith(
              fontSize: 12,
              color: v == null ? Colors.grey.shade500 : null,
              fontStyle: v == null ? FontStyle.italic : null,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      );
    }

    final header = Row(
      children: [
        Container(
          width: 44,
          padding: const EdgeInsets.all(6),
          color: scheme.primary.withValues(alpha: 0.10),
          child: const Text('#', style: TextStyle(fontWeight: FontWeight.bold)),
        ),
        for (var ci = 0; ci < columns.length; ci++)
          headerCell((ci == pkIndex ? '🔑 ' : '') + columns[ci], ci == pkIndex),
      ],
    );

    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        header,
        for (var ri = 0; ri < rows.length; ri++)
          Row(
            children: [
              Container(
                width: 44,
                padding: const EdgeInsets.all(6),
                color: (ri % 2 == 0)
                    ? Colors.grey.withValues(alpha: isDark ? 0.12 : 0.04)
                    : null,
                child: Text('${ri + 1}',
                    style: TextStyle(color: Colors.grey.shade500)),
              ),
              for (var ci = 0; ci < columns.length; ci++)
                cell(rows[ri][columns[ci]], ci == pkIndex, ri, ci),
            ],
          ),
      ],
    );

    if (rows.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Text('无结果集', style: TextStyle(color: Colors.grey)),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.vertical,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: body,
      ),
    );
  }

  void _showCell(BuildContext context, String? value) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('单元格值'),
        content: SelectableText(
          value ?? 'NULL',
          style: const TextStyle(fontFamily: 'monospace'),
        ),
        actions: [
          TextButton(
            onPressed: () {
              if (value != null) {
                Clipboard.setData(ClipboardData(text: value));
              }
              Navigator.of(context).pop();
            },
            child: const Text('复制'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }
}
