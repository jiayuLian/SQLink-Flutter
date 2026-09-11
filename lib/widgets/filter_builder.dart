import 'package:flutter/material.dart';
import '../models/connection.dart' show ColumnInfo;
import '../models/filter_condition.dart';

/// 结构化「筛选&排序」构建器（对齐 Swift 的 TableFilterView）。
/// 由调用方以**居中卡片弹窗**（showGeneralDialog + Center + 圆角 Material）承载，
/// 与 Swift 的 filterOverlay 版式一致；本组件只负责卡片内部内容。
/// 内容：多条件（启用/AND·OR/字段/运算符/值）+ 排序；点「应用」按 Swift 的
/// buildWhereClause / buildOrderBy 拼出 WHERE / ORDER，随后自行关闭弹窗。
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
  final _controllers = <String, TextEditingController>{};

  @override
  void initState() {
    super.initState();
    // 深拷贝草稿，避免直接改动外部传入的条件列表（未点「应用」不生效，对齐 Swift draft*）。
    _drafts = widget.initialConditions
        .map((c) => FilterCondition(
              id: c.id,
              field: c.field,
              op: c.op,
              value: c.value,
              enabled: c.enabled,
              logic: c.logic,
            ))
        .toList();
    _sortField = widget.initialSortField;
    _sortDir = widget.initialSortDir;
    // 对齐 Swift TableFilterView.onAppear：排序字段已不属于当前表时归零，
    // 否则 DropdownButton 会因 value 不在 items 中触发断言崩溃。
    if (_sortField.isNotEmpty && !_fieldNames.contains(_sortField)) {
      _sortField = '';
    }
    for (final c in _drafts) {
      _controllers[_keyFor(c)] = TextEditingController(text: c.value);
    }
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  List<String> get _fieldNames => widget.columns.map((c) => c.field).toList();

  /// 控制器键 = 条件的稳定 id（不再用 hashCode，避免理论上的碰撞导致两行共用控制器）。
  String _keyFor(FilterCondition c) => c.id;

  void _add() {
    final f = _fieldNames.isNotEmpty ? _fieldNames.first : '';
    final condition = FilterCondition(
      field: f,
      op: FilterOp.contains,
      value: '',
      enabled: true,
      // 对齐 Swift：首条不显示 AND/OR 关系，其余默认 AND。
      logic: FilterLogic.and,
    );
    _drafts.add(condition);
    _controllers[_keyFor(condition)] = TextEditingController(text: '');
    setState(() {});
  }

  void _remove(int i) {
    final c = _drafts[i];
    _controllers.remove(_keyFor(c))?.dispose();
    _drafts.removeAt(i);
    if (_drafts.isNotEmpty) _drafts[0].logic = FilterLogic.and;
    setState(() {});
  }

  void _clearAll() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    _controllers.clear();
    _drafts = [];
    _sortField = '';
    _sortDir = 'ASC';
    setState(() {});
  }

  void _apply() {
    final where = buildWhereClause(_drafts);
    final order = buildOrderBy(_sortField, _sortDir);
    // 先交付结果，再关闭弹窗（对齐 Swift：变更落定后 dispatch 关闭）。
    widget.onApply(where, order, _drafts, _sortField, _sortDir);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
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
    );
  }

  Widget _headerBar(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          const Spacer(),
          Text('筛选 & 排序', style: theme.textTheme.titleMedium),
          const Spacer(),
          Row(
            children: [
              TextButton(
                onPressed: _clearAll,
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
  }

  Widget _conditionRow(int i) {
    final c = _drafts[i];
    final showLogic = i > 0;
    return Card(
      // 按 id 定位（对齐 Swift `ForEach($draftConditions)` 用 UUID 标识元素）：
      // 删除中间某条时，其余行的输入框（焦点/光标/控制器）不会错位。
      key: ValueKey(c.id),
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
                    // 字段不在当前表列中时回退为未选择，避免 DropdownButton 断言失败。
                    value: _fieldNames.contains(c.field) ? c.field : null,
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
                controller: _controllers[_keyFor(c)],
                decoration: const InputDecoration(
                  // 用 hintText（占位）而不是 labelText：对齐 Swift
                  // `TextField("值", text:)` 的语义——输入内容后提示「值」随即消失。
                  // 若用 labelText，标签会一直浮在输入内容上方（isCollapsed 下甚至与
                  // 内容重叠），看起来像「值」没被清掉。
                  hintText: '值',
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
                    value:
                        _sortField.isEmpty || !_fieldNames.contains(_sortField)
                            ? null
                            : _sortField,
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

/// 以「居中卡片 + 半透明遮罩」方式弹出筛选&排序弹窗（对齐 Swift filterOverlay：
/// 遮罩点击关闭、卡片圆角、最高 85% 屏幕高度）。
Future<void> showFilterOverlay(
  BuildContext context, {
  required Widget child,
}) {
  return showGeneralDialog(
    context: context,
    barrierDismissible: true,
    barrierLabel: '筛选 & 排序',
    barrierColor: Colors.black.withValues(alpha: 0.35),
    transitionDuration: const Duration(milliseconds: 120),
    pageBuilder: (ctx, _, __) {
      final maxH = MediaQuery.of(ctx).size.height * 0.85;
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxH),
            child: Material(
              color: Theme.of(ctx).colorScheme.surface,
              elevation: 10,
              clipBehavior: Clip.antiAlias,
              borderRadius: BorderRadius.circular(12),
              child: child,
            ),
          ),
        ),
      );
    },
    transitionBuilder: (ctx, anim, _, page) => FadeTransition(
      opacity: anim,
      child: ScaleTransition(
        scale: Tween<double>(begin: 0.96, end: 1.0).animate(anim),
        child: page,
      ),
    ),
  );
}
