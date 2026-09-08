import 'package:flutter/material.dart';

/// 查询结果表格（水平+垂直双向滚动，NULL 置灰）。
/// 对齐 Swift ResultGridView：主键列（PRI/UNI）以 🔑 标记并加强调背景高亮。
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final headerColor = isDark ? Colors.teal.shade900 : Colors.teal.shade50;
    final nullColor = Colors.grey.shade500;
    final pkBg = isDark ? Colors.amber.shade900.withOpacity(0.35) : Colors.amber.shade100;
    final pkIndex = primaryKey == null ? -1 : columns.indexOf(primaryKey!);

    return SingleChildScrollView(
      scrollDirection: Axis.vertical,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingRowColor: WidgetStateProperty.all<Color?>(headerColor),
          columns: [
            const DataColumn(
              label: Text('#', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
            for (var ci = 0; ci < columns.length; ci++)
              DataColumn(
                label: Text(
                  (ci == pkIndex ? '🔑 ' : '') + columns[ci],
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
          ],
          rows: [
            for (var i = 0; i < rows.length; i++)
              DataRow(
                cells: [
                  DataCell(
                    Text('${i + 1}', style: TextStyle(color: nullColor)),
                  ),
                  for (var ci = 0; ci < columns.length; ci++)
                    _buildCell(columns[ci], rows[i][columns[ci]], ci == pkIndex, pkBg),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildCell(String col, String? v, bool isPk, Color? pkBg) {
    return DataCell(
      Container(
        color: isPk ? pkBg : null,
        child: Text(
          v ?? 'NULL',
          style: v == null
              ? TextStyle(color: Colors.grey.shade500, fontStyle: FontStyle.italic)
              : (isPk
                  ? const TextStyle(fontWeight: FontWeight.w600)
                  : null),
        ),
      ),
    );
  }
}
