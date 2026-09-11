import 'package:flutter/material.dart';

/// 简易 SQL 语法高亮（对齐 Swift highlightSQL）：
/// 关键字 / 反引号标识符 / 字符串 分别着色，用于「建表 SQL」展示。
/// 由表详情页与数据页共用。
class SqlHighlighter extends StatelessWidget {
  final String sql;
  final double fontSize;
  const SqlHighlighter(this.sql, {super.key, this.fontSize = 12});

  static const _keywords = {
    'CREATE', 'TABLE', 'TEMPORARY', 'PRIMARY', 'KEY', 'NOT', 'NULL',
    'AUTO_INCREMENT', 'DEFAULT', 'UNIQUE', 'INDEX', 'FOREIGN', 'REFERENCES',
    'ON', 'DELETE', 'UPDATE', 'CASCADE', 'SET', 'ENGINE', 'CHARSET', 'COLLATE',
    'COMMENT', 'VARCHAR', 'INT', 'BIGINT', 'TINYINT', 'SMALLINT', 'MEDIUMINT',
    'INTEGER', 'DECIMAL', 'NUMERIC', 'FLOAT', 'DOUBLE', 'CHAR', 'TEXT',
    'LONGTEXT', 'BLOB', 'DATE', 'DATETIME', 'TIMESTAMP', 'TIME', 'JSON',
    'UNSIGNED', 'IF', 'EXISTS', 'DROP', 'ALTER', 'ADD', 'MODIFY', 'COLUMN',
    'CONSTRAINT', 'VIEW', 'AS', 'SELECT', 'FROM', 'WHERE', 'AND', 'OR',
    'ORDER', 'BY', 'LIMIT', 'INNER', 'LEFT', 'RIGHT', 'OUTER', 'JOIN',
    'VALUES', 'INSERT', 'INTO', 'REPLACE', 'ZEROFILL', 'ALGORITHM', 'LOCK',
    'FULLTEXT', 'SPATIAL', 'ASC', 'DESC', 'DISTINCT', 'GROUP', 'HAVING',
    'LIKE', 'IN', 'IS', 'BETWEEN', 'ROW_FORMAT',
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final plainStyle = TextStyle(
      fontFamily: 'monospace',
      fontSize: fontSize,
      color: theme.colorScheme.onSurface,
    );

    TextSpan span(String text, Color color, {bool bold = false}) => TextSpan(
          text: text,
          style: plainStyle.copyWith(
            color: color,
            fontWeight: bold ? FontWeight.bold : null,
          ),
        );

    final spans = <TextSpan>[];
    final regex = RegExp(r"(\s+)|('[^']*')|(`[^`]+`)|(\w+)|(.+)");
    for (final m in regex.allMatches(sql)) {
      final text = m.group(0)!;
      if (m.group(1) != null) {
        spans.add(span(text, theme.colorScheme.onSurface));
      } else if (m.group(2) != null) {
        spans.add(span(text, isDark ? Colors.lightGreen : Colors.green));
      } else if (m.group(3) != null) {
        spans.add(
            span(text, isDark ? Colors.orange.shade300 : Colors.orange.shade800));
      } else if (m.group(4) != null) {
        if (_keywords.contains(text.toUpperCase())) {
          spans.add(
              span(text, isDark ? Colors.cyan.shade300 : Colors.blue, bold: true));
        } else {
          spans.add(span(text, theme.colorScheme.onSurface));
        }
      } else {
        spans.add(span(text, theme.colorScheme.onSurface));
      }
    }

    return RichText(text: TextSpan(children: spans, style: plainStyle));
  }
}
