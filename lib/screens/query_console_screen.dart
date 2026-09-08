import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:cross_file/cross_file.dart';
import '../services/mysql_service.dart';
import '../models/connection.dart' show ResultSetData;
import '../services/csv_export.dart';
import '../settings/app_settings.dart';
import '../widgets/result_grid.dart';

const _keywords = [
  'SELECT', 'FROM', 'WHERE', 'INSERT', 'INTO', 'VALUES', 'UPDATE', 'SET',
  'DELETE', 'CREATE', 'DROP', 'ALTER', 'TABLE', 'DATABASE', 'LIMIT', 'ORDER',
  'GROUP', 'BY', 'AND', 'OR', 'NOT', 'NULL', 'LIKE', 'IN', 'BETWEEN', 'JOIN',
  'LEFT', 'RIGHT', 'INNER', 'ON', 'AS', 'ASC', 'DESC', 'HAVING', 'UNION',
  'DISTINCT', 'COUNT', 'SUM', 'AVG', 'MAX', 'MIN',
];

class QueryConsoleScreen extends StatefulWidget {
  final MySQLService service;
  const QueryConsoleScreen({super.key, required this.service});

  @override
  State<QueryConsoleScreen> createState() => _QueryConsoleScreenState();
}

class _QueryConsoleScreenState extends State<QueryConsoleScreen> {
  final _sql = TextEditingController();
  List<ResultSetData>? _outcomes;
  String? _error;
  bool _running = false;

  String get _currentWord {
    final t = _sql.text;
    if (t.isEmpty) return '';
    final parts = t.split(RegExp(r'\s+'));
    return parts.last;
  }

  List<String> get _suggestions {
    final w = _currentWord.toUpperCase();
    if (w.isEmpty) return [];
    return _keywords.where((k) => k.startsWith(w) && k != w).toList();
  }

  Future<void> _run() async {
    final sql = _sql.text.trim();
    if (sql.isEmpty) return;
    setState(() {
      _running = true;
      _error = null;
      _outcomes = null;
    });
    try {
      final outs = await widget.service.execute(sql);
      final settings = Provider.of<AppSettings>(context, listen: false);
      if (settings.autoSaveSQL) await settings.addHistory(sql);
      if (mounted) setState(() => _outcomes = outs);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  void _insertSuggestion(String word) {
    final t = _sql.text;
    final trimmed = t.replaceAll(RegExp(r'\S+$'), '');
    _sql.text = '$trimmed$word ';
    _sql.selection = TextSelection.fromPosition(
      TextPosition(offset: _sql.text.length),
    );
  }

  void _exportCsv() {
    final rs = _outcomes?.where((o) => o.isResultSet).toList();
    if (rs == null || rs.isEmpty) return;
    final first = rs.first;
    final csv = toCsv(first.columns, first.rows);
    Share.shareXFiles(
      [XFile.fromData(utf8.encode(csv), name: 'sqlink_result.csv', mimeType: 'text/csv')],
      subject: 'SQLink 查询结果',
    );
  }

  void _showHistory() {
    final settings = Provider.of<AppSettings>(context, listen: false);
    showModalBottomSheet(
      context: context,
      builder: (ctx) => ListView(
        children: [
          const ListTile(title: Text('SQL 历史', style: TextStyle(fontWeight: FontWeight.bold))),
          if (settings.history.isEmpty)
            const ListTile(title: Text('暂无历史')),
          for (final h in settings.history)
            ListTile(
              title: Text(h, maxLines: 2, overflow: TextOverflow.ellipsis),
              onTap: () {
                _sql.text = h;
                Navigator.of(ctx).pop();
              },
            ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _sql.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _sql,
                  maxLines: 4,
                  minLines: 2,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    hintText: '输入 SQL，例如 SELECT 1',
                  ),
                ),
              ),
            ],
          ),
        ),
        if (_suggestions.isNotEmpty)
          SizedBox(
            height: 36,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: _suggestions
                  .map((s) => Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 3),
                        child: ActionChip(
                          label: Text(s),
                          onPressed: () => _insertSuggestion(s),
                        ),
                      ))
                  .toList(),
            ),
          ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            children: [
              FilledButton.icon(
                onPressed: _running ? null : _run,
                icon: _running
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.play_arrow),
                label: Text(_running ? '执行中' : '执行'),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.history),
                tooltip: '历史',
                onPressed: _showHistory,
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.download),
                tooltip: '导出 CSV',
                onPressed: (_outcomes?.any((o) => o.isResultSet) ?? false)
                    ? _exportCsv
                    : null,
              ),
            ],
          ),
        ),
        const Divider(),
        Expanded(
          child: _buildBody(),
        ),
      ],
    );
  }

  Widget _buildBody() {
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text('错误：\n$_error', style: const TextStyle(color: Colors.red)),
        ),
      );
    }
    if (_outcomes == null) {
      return const Center(child: Text('执行查询后显示结果'));
    }
    final resultSets = _outcomes!.where((o) => o.isResultSet).toList();
    final okCount = _outcomes!.where((o) => !o.isResultSet).length;
    return ListView(
      padding: const EdgeInsets.all(8),
      children: [
        if (okCount > 0)
          ListTile(
            leading: const Icon(Icons.check_circle, color: Colors.green),
            title: Text('$okCount 条语句执行成功（无结果集）'),
          ),
        for (var i = 0; i < resultSets.length; i++)
          Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text(
                    '结果 #${i + 1} · ${resultSets[i].rows.length} 行',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                ResultGrid(
                  columns: resultSets[i].columns,
                  rows: resultSets[i].rows,
                ),
              ],
            ),
          ),
      ],
    );
  }
}
