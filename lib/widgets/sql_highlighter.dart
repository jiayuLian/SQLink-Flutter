import 'package:flutter/material.dart';

/// SQL 语法高亮，用于「建表 SQL」展示（由表详情页调用）。
///
/// 配色对齐 **Navicat 表结构（DDL）视图**——靠"少量高饱和色 + 正文色"做区分，
/// 而不是把所有 token 都涂成一种颜色（那样整段看起来只有一个色，反而难分辨）：
///   - 关键字（CREATE TABLE / varchar / NOT NULL / COMMENT / COLLATE / USING BTREE…）→ 蓝色
///   - 字符串与字面量（'主键ID'、DEFAULT '0'）→ 红色
///   - 数字（32、100、211、10,2）→ 绿色
///   - 标识符（表名 / 列名 / 索引名 / 字符集名 utf8mb4_unicode_ci / InnoDB）→ 正文色（不上色）
///   - 标点 ( ) , = ; → 正文色
///   - 注释 -- / # / /* */ → 灰色
/// 该映射由用户提供的 Navicat 截图逐 token 像素采样（墨水吸收谱）还原而来。
///
/// 实现为**逐字符扫描**，不使用正则的 `(.+)` 兜底分支：
/// 旧版正则 `(\s+)|('[^']*')|(`[^`]+`)|(\w+)|(.+)` 的最后一段是「贪婪匹配到行尾」，
/// 一旦列定义里出现不属于前面任何分支的标点（典型是 `varchar(32)` 的 `(`），
/// 该行 `(` 之后的全部内容（COLLATE / NOT NULL / COMMENT / 注释字符串）都会被
/// 当成一段纯文本输出，于是丢色。现已改为逐字符分类，任意位置都不会再丢失高亮。
class SqlHighlighter extends StatelessWidget {
  final String sql;
  final double fontSize;
  const SqlHighlighter(this.sql, {super.key, this.fontSize = 12});

  static const _keywords = {
    'CREATE', 'TABLE', 'TEMPORARY', 'PRIMARY', 'KEY', 'NOT', 'NULL',
    'AUTO_INCREMENT', 'DEFAULT', 'UNIQUE', 'INDEX', 'FOREIGN', 'REFERENCES',
    'ON', 'DELETE', 'UPDATE', 'CASCADE', 'RESTRICT', 'ACTION', 'SET', 'ENGINE',
    'CHARSET', 'CHARACTER', 'COLLATE', 'COMMENT', 'VARCHAR', 'INT', 'BIGINT',
    'TINYINT', 'SMALLINT', 'MEDIUMINT', 'INTEGER', 'DECIMAL', 'NUMERIC',
    'FLOAT', 'DOUBLE', 'CHAR', 'TEXT', 'TINYTEXT', 'MEDIUMTEXT', 'LONGTEXT',
    'BLOB', 'TINYBLOB', 'MEDIUMBLOB', 'LONGBLOB', 'DATE', 'DATETIME',
    'TIMESTAMP', 'TIME', 'YEAR', 'JSON', 'ENUM', 'BINARY', 'VARBINARY',
    'UNSIGNED', 'SIGNED', 'ZEROFILL', 'IF', 'EXISTS', 'DROP', 'ALTER', 'ADD',
    'MODIFY', 'CHANGE', 'COLUMN', 'CONSTRAINT', 'VIEW', 'AS', 'SELECT', 'FROM',
    'WHERE', 'AND', 'OR', 'ORDER', 'BY', 'LIMIT', 'OFFSET', 'INNER', 'LEFT',
    'RIGHT', 'OUTER', 'JOIN', 'UNION', 'VALUES', 'INSERT', 'INTO', 'REPLACE',
    'ALGORITHM', 'LOCK', 'FULLTEXT', 'SPATIAL', 'ASC', 'DESC', 'DISTINCT',
    'GROUP', 'HAVING', 'LIKE', 'IN', 'IS', 'BETWEEN', 'USING', 'BTREE', 'HASH',
    'ROW_FORMAT', 'DYNAMIC', 'COMPRESSED', 'REDUNDANT', 'FIXED', 'STATS_PERSISTENT',
    'STATS_AUTO_RECALC', 'PACK_KEYS', 'CHECKSUM', 'DELAY_KEY_WRITE', 'CONNECTION',
    'DATA', 'DIRECTORY', 'INSERT_METHOD', 'AVG_ROW_LENGTH', 'KEY_BLOCK_SIZE',
    'MAX_ROWS', 'MIN_ROWS', 'PASSWORD', 'COMPRESSION', 'ENCRYPTION',
    'INVISIBLE', 'VISIBLE', 'GENERATED', 'ALWAYS', 'STORED', 'VIRTUAL',
    'CONVERT', 'TO', 'DEFINER', 'INVOKER', 'TRIGGER', 'FUNCTION', 'PROCEDURE',
    'RETURNS', 'DETERMINISTIC', 'BEGIN', 'END',
  };

  static bool _isSpace(int c) =>
      c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D;

  static bool _isWordChar(int c) =>
      (c >= 0x30 && c <= 0x39) || // 0-9
      (c >= 0x41 && c <= 0x5A) || // A-Z
      (c >= 0x61 && c <= 0x7A) || // a-z
      c == 0x5F || // _
      c == 0x24 || // $
      c >= 0x80; // 非 ASCII（中文列名等）

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

    // Navicat 配色（浅色主题对 Navicat 原色做了加深，保证在浅灰底上的对比度；
    // 深色主题换成同色系的亮版）。标识符与标点一律用正文色，不做额外着色。
    final kwColor = isDark
        ? const Color(0xFF4DA3FF) // 关键字：蓝
        : const Color(0xFF0A6BD8);
    final strColor = isDark
        ? const Color(0xFFFF6B85) // 字符串/字面量：红（原版 #FF1744）
        : const Color(0xFFD81B3C);
    final numColor = isDark
        ? const Color(0xFF3DDC84) // 数字：绿（原版 #00C853）
        : const Color(0xFF0A7A3E);
    final cmtColor = isDark ? Colors.grey.shade500 : Colors.grey.shade600;
    final plainColor = theme.colorScheme.onSurface;

    final spans = <TextSpan>[];
    final buf = StringBuffer();
    Color? bufColor;
    var bufBold = false;

    void flush() {
      if (buf.isEmpty) return;
      spans.add(span(buf.toString(), bufColor ?? plainColor, bold: bufBold));
      buf.clear();
      bufColor = null;
      bufBold = false;
    }

    // 相邻同色文本合并进同一个 span，避免产生大量碎片
    void push(String text, Color color, {bool bold = false}) {
      if (bufColor == color && bufBold == bold) {
        buf.write(text);
        return;
      }
      flush();
      bufColor = color;
      bufBold = bold;
      buf.write(text);
    }

    final n = sql.length;
    var i = 0;
    while (i < n) {
      final c = sql.codeUnitAt(i);

      // 空白
      if (_isSpace(c)) {
        final start = i;
        while (i < n && _isSpace(sql.codeUnitAt(i))) {
          i++;
        }
        push(sql.substring(start, i), plainColor);
        continue;
      }

      // 行注释 -- 与 #
      if ((c == 0x2D && i + 1 < n && sql.codeUnitAt(i + 1) == 0x2D) ||
          c == 0x23) {
        final start = i;
        while (i < n && sql.codeUnitAt(i) != 0x0A) {
          i++;
        }
        push(sql.substring(start, i), cmtColor);
        continue;
      }

      // 块注释 /* ... */
      if (c == 0x2F && i + 1 < n && sql.codeUnitAt(i + 1) == 0x2A) {
        final end = sql.indexOf('*/', i + 2);
        final stop = end < 0 ? n : end + 2;
        push(sql.substring(i, stop), cmtColor);
        i = stop;
        continue;
      }

      // 字符串 '...'（支持 '' 与 \' 转义）
      if (c == 0x27 || c == 0x22) {
        final start = i;
        final quote = c;
        i++;
        while (i < n) {
          final ch = sql.codeUnitAt(i);
          if (ch == 0x5C) {
            i = i + 2 <= n ? i + 2 : n;
            continue;
          }
          if (ch == quote) {
            i++;
            if (i < n && sql.codeUnitAt(i) == quote) {
              i++; // '' 转义
              continue;
            }
            break;
          }
          i++;
        }
        push(sql.substring(start, i), strColor);
        continue;
      }

      // 反引号标识符 `...`
      if (c == 0x60) {
        final start = i;
        i++;
        while (i < n) {
          final ch = sql.codeUnitAt(i);
          i++;
          if (ch == 0x60) break;
        }
        push(sql.substring(start, i), plainColor);
        continue;
      }

      // 数字（含小数）
      if (c >= 0x30 && c <= 0x39) {
        final start = i;
        while (i < n) {
          final ch = sql.codeUnitAt(i);
          if ((ch >= 0x30 && ch <= 0x39) || ch == 0x2E) {
            i++;
          } else {
            break;
          }
        }
        push(sql.substring(start, i), numColor);
        continue;
      }

      // 单词：关键字 → 蓝加粗；其余标识符（列名/表名/字符集名等）→ 正文色（对齐 Navicat）
      if (_isWordChar(c)) {
        final start = i;
        while (i < n && _isWordChar(sql.codeUnitAt(i))) {
          i++;
        }
        final word = sql.substring(start, i);
        if (_keywords.contains(word.toUpperCase())) {
          push(word, kwColor, bold: true);
        } else {
          push(word, plainColor);
        }
        continue;
      }

      // 其它标点：逐字符（关键：不再贪婪吞掉整行）
      push(sql[i], plainColor);
      i++;
    }
    flush();

    return RichText(text: TextSpan(children: spans, style: plainStyle));
  }
}
