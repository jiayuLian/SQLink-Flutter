import 'package:flutter/material.dart';

/// 查询结果表格（水平+垂直双向滚动，NULL 置灰）。
class ResultGrid extends StatelessWidget {
  final List<String> columns;
  final List<Map<String, String?>> rows;

  const ResultGrid({super.key, required this.columns, required this.rows});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final headerColor = isDark ? Colors.teal.shade900 : Colors.teal.shade50;
    final nullColor = isDark ? Colors.grey.shade500 : Colors.grey.shade500;

    return SingleChildScrollView(
      scrollDirection: Axis.vertical,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingRowColor: WidgetStateProperty.all(headerColor),
          columns: [
            const DataColumn(label: Text('#', style: TextStyle(fontWeight: FontWeight.bold))),
            ...columns.map(
              (c) => DataColumn(
                label: Text(c, style: const TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),
          ],
          rows: [
            for (var i = 0; i < rows.length; i++)
              DataRow(
                cells: [
                  DataCell(Text('${i + 1}', style: TextStyle(color: nullColor))),
                  ...columns.map((c) {
                    final v = rows[i][c];
                    return DataCell(
                      Text(
                        v ?? 'NULL',
                        style: v == null
                            ? TextStyle(color: nullColor, fontStyle: FontStyle.italic)
                            : null,
                      ),
                    );
                  }),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
