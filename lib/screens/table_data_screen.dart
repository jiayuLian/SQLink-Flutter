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

class TableDataScreen extends StatefulWidget {
  final MySQLService service;
  final String db;
  final String table;
  const TableDataScreen({
    super.key,
    required this.service,
    required this.db,
    required this.table,
  });

  @override
  State<TableDataScreen> createState() => _TableDataScreenState();
}

class _TableDataScreenState extends State<TableDataScreen> {
  ResultSetData? _data;
  int _total = 0;
  int _offset = 0;
  bool _loading = false;
  String? _error;
  String? _sortColumn;
  String _sortDir = 'ASC';
  final _where = TextEditingController();

  int get _pageSize =>
      Provider.of<AppSettings>(context, listen: false).pageSize;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final order = _sortColumn != null ? '$_sortColumn $_sortDir' : null;
      final data = await widget.service.fetchTable(
        widget.db,
        widget.table,
        limit: _pageSize,
        offset: _offset,
        where: _where.text.trim().isEmpty ? null : _where.text.trim(),
        order: order,
      );
      final total = await widget.service.countTable(
        widget.db,
        widget.table,
        where: _where.text.trim().isEmpty ? null : _where.text.trim(),
      );
      if (mounted) {
        setState(() {
          _data = data;
          _total = total;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _exportCsv() {
    if (_data == null || !_data!.isResultSet) return;
    final csv = toCsv(_data!.columns, _data!.rows);
    Share.shareXFiles(
      [XFile.fromData(utf8.encode(csv), name: '${widget.table}.csv', mimeType: 'text/csv')],
      subject: '${widget.db}.${widget.table}',
    );
  }

  @override
  Widget build(BuildContext context) {
    final page = (_offset / _pageSize) + 1;
    final totalPages = (_total / _pageSize).ceil();

    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.db}.${widget.table}'),
        actions: [
          IconButton(
            icon: const Icon(Icons.download),
            tooltip: '导出当前页 CSV',
            onPressed: _data?.isResultSet ?? false ? _exportCsv : null,
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _where,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      labelText: '筛选 (WHERE 片段，如 status=1)',
                    ),
                    onSubmitted: (_) {
                      _offset = 0;
                      _load();
                    },
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.search),
                  onPressed: () {
                    _offset = 0;
                    _load();
                  },
                ),
              ],
            ),
          ),
          if (_data?.isResultSet ?? false)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                children: [
                  const Text('排序:'),
                  const SizedBox(width: 8),
                  DropdownButton<String>(
                    hint: const Text('列'),
                    value: _sortColumn,
                    items: _data!.columns
                        .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                        .toList(),
                    onChanged: (v) => setState(() => _sortColumn = v),
                  ),
                  const SizedBox(width: 8),
                  DropdownButton<String>(
                    value: _sortDir,
                    items: const [
                      DropdownMenuItem(value: 'ASC', child: Text('升序')),
                      DropdownMenuItem(value: 'DESC', child: Text('降序')),
                    ],
                    onChanged: (v) => setState(() => _sortDir = v!),
                  ),
                  TextButton(
                    onPressed: _load,
                    child: const Text('应用'),
                  ),
                ],
              ),
            ),
          const Divider(),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(child: Text('错误：$_error', style: const TextStyle(color: Colors.red)))
                    : _data != null && _data!.isResultSet
                        ? ResultGrid(columns: _data!.columns, rows: _data!.rows)
                        : const Center(child: Text('无数据')),
          ),
          Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left),
                  onPressed: _offset >= _pageSize
                      ? () {
                          _offset -= _pageSize;
                          _load();
                        }
                      : null,
                ),
                Text('第 $page / ${totalPages == 0 ? 1 : totalPages} 页 · 共 $_total 行'),
                IconButton(
                  icon: const Icon(Icons.chevron_right),
                  onPressed: _offset + _pageSize < _total
                      ? () {
                          _offset += _pageSize;
                          _load();
                        }
                      : null,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
