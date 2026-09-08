import 'package:flutter/material.dart';
import '../models/connection.dart' show ColumnInfo;
import '../models/filter_condition.dart'
    show
        FilterCondition,
        FilterOp,
        FilterLogic,
        buildWhereClause,
        buildOrderBy;

/// 结构化「筛选&排序」构建器（对齐 Swift 的 TableFilterView）。
/// 以底部弹窗形式呈现：多条件（字段/运算符/值/AND·OR/启用）+ 排序；
/// 点「应用」时按 Swift 的 buildWhereClause / buildOrderBy 逻辑拼出 WHERE / ORDER 字符串。
class FilterBuilder extends StatefulWidget {
  final List<ColumnInfo> columns;
  final List<FilterCondition> initialConditions;
  final String initialSortField;
  final String initialSortDir;
  final void Function(
    String? where,
    String? order,
    List<FilterCondition> conditions,
    String sortField,
    String sortDir,
  ) onApply;

  const FilterBuilder({
    super.key,
    required this.columns,
    required this.initialConditions,
    required this.initialSortField,
    required this.initialSortDir,
    required this.onApply,
  });

  @override
  State<FilterBuilder> createState() => _FilterBuilderState();
}

class _FilterBuilderState extends State<FilterBuilder> {
  late List<FilterCondition> _drafts;
  late String _sortField;
  late String _sortDir;

  @override
  void initState() {
    super.initState();
    // 深拷贝草稿，避免直接改动外部传入的条件列表。
    _drafts = widget.initialConditions
        .map((c) => FilterCondition(
              field: c.field,
              op: c.op,
              value: c.value,
              enabled: c.enabled,
              logic: c.logic,
            ))
        .toList();
    _sortField = widget.initialSortField;
    _sortDir = widget.initialSortDir;
  }

  List<String> get _fieldNames => widget.columns.map((c) => c.field).toList();

  void _add() {
    final f = _fieldNames.isNotEmpty ? _fieldNames.first : '';
    _drafts.add(FilterCondition(
      field: f,
      op: FilterOp.contains,
      value: '',
      enabled: true,
      logic: FilterLogic.and,
    ));
    setState(() {});
  }

  void _remove(int i) {
    _drafts.removeAt(i);
    // 删除后首条不再显示 AND/OR 关系。
    if (_drafts.isNotEmpty) _drafts[0].logic = FilterLogic.and;
    setState(() {});
  }

  void _apply() {
    final where = buildWhereClause(_drafts);
    final order = buildOrderBy(_sortField, _sortDir);
    widget.onApply(where, order, _drafts, _sortField, _sortDir);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _headerBar(context),
          const Divider(height: 1),
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.add),
                    title: const Text('添加筛选条件'),
                    onTap: _add,
                  ),
                  for (var i = 0; i < _drafts.length; i++) _conditionRow(i),
                  const Divider(),
                  _sortSection(),
                  const SizedBox(height: 12),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _headerBar(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('取消'),
            ),
            const Spacer(),
            Text('筛选 & 排序', style: Theme.of(context).textTheme.titleMedium),
            const Spacer(),
            Row(
              children: [
                TextButton(
                  onPressed: () {
                    _drafts = [];
                    _sortField = '';
                    _sortDir = 'ASC';
                    setState(() {});
                  },
                  child: const Text('清除'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _apply,
                  child: const Text('应用'),
                ),
              ],
            ),
          ],
        ),
      );

  Widget _conditionRow(int i) {
    final c = _drafts[i];
    final showLogic = i > 0;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Switch(
                  value: c.enabled,
                  onChanged: (v) => setState(() => c.enabled = v),
                ),
                if (showLogic)
                  DropdownButton<FilterLogic>(
                    value: c.logic,
                    items: FilterLogic.values
                        .map((l) => DropdownMenuItem(value: l, child: Text(l.label)))
                        .toList(),
                    onChanged: (v) => setState(() => c.logic = v ?? FilterLogic.and),
                  ),
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButton<String>(
                    isExpanded: true,
                    value: c.field.isEmpty ? null : c.field,
                    hint: const Text('字段'),
                    items: _fieldNames
                        .map((f) => DropdownMenuItem(value: f, child: Text(f)))
                        .toList(),
                    onChanged: (v) => setState(() => c.field = v ?? ''),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.delete, color: Colors.red),
                  onPressed: () => _remove(i),
                ),
              ],
            ),
            DropdownButton<FilterOp>(
              isExpanded: true,
              value: c.op,
              items: FilterOp.values
                  .map((op) => DropdownMenuItem(value: op, child: Text(op.label)))
                  .toList(),
              onChanged: (v) => setState(() => c.op = v ?? FilterOp.contains),
            ),
            if (c.op.needsValue)
              TextField(
                controller: TextEditingController(text: c.value),
                decoration: const InputDecoration(
                  labelText: '值',
                  isCollapsed: true,
                  contentPadding: EdgeInsets.symmetric(vertical: 10),
                ),
                onChanged: (t) => c.value = t,
              ),
          ],
        ),
      ),
    );
  }

  Widget _sortSection() => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('排序', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Row(
              children: [
                const Text('字段：'),
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButton<String>(
                    isExpanded: true,
                    value: _sortField.isEmpty ? null : _sortField,
                    hint: const Text('无'),
                    items: [
                      const DropdownMenuItem(value: '', child: Text('无')),
                      ..._fieldNames
                          .map((f) => DropdownMenuItem(value: f, child: Text(f)))
                          .toList(),
                    ],
                    onChanged: (v) => setState(() => _sortField = v ?? ''),
                  ),
                ),
                const SizedBox(width: 12),
                const Text('方向：'),
                DropdownButton<String>(
                  value: _sortDir,
                  items: const [
                    DropdownMenuItem(value: 'ASC', child: Text('升序')),
                    DropdownMenuItem(value: 'DESC', child: Text('降序')),
                  ],
                  onChanged: (v) => setState(() => _sortDir = v ?? 'ASC'),
                ),
              ],
            ),
          ],
        ),
      );
}
