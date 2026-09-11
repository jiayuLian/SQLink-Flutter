import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 结果表格缩放控制器：让外层（数据页 / 控制台底部工具栏）
/// 能读取当前缩放比例并在点击「xx%」时复位（对齐 Swift gridScale 的 % 按钮）。
class ResultGridController extends ChangeNotifier {
  double _scale = 1.0;
  double get scale => _scale;

  static double _clamp(double v) => v < 0.6 ? 0.6 : (v > 3.0 ? 3.0 : v);

  void setScale(double v) {
    final nv = _clamp(v);
    if ((nv - _scale).abs() < 0.001) return;
    _scale = nv;
    notifyListeners();
  }

  void reset() => setScale(1.0);
}

/// 查询结果表格（Navicat 风格，对齐 Swift ResultGridView）。
/// 主键列（PRI/UNI）以 🔑 标记并以主题色高亮；单元格等宽字体、定宽列、隔行底色；
/// 点按单元格弹出完整值并支持复制。
/// 支持双指捏合缩放（0.6~3.0）+ 双击复位（对齐 Swift gridScale 手势）。
class ResultGrid extends StatefulWidget {
  final List<String> columns;
  final List<Map<String, String?>> rows;

  /// 真实主键列名（PRI 优先，其次 UNI）；为 null 时不高亮。
  final String? primaryKey;

  /// 可选控制器：外部可读取/复位缩放比例。
  final ResultGridController? controller;

  const ResultGrid({
    super.key,
    required this.columns,
    required this.rows,
    this.primaryKey,
    this.controller,
  });

  @override
  State<ResultGrid> createState() => _ResultGridState();
}

class _ResultGridState extends State<ResultGrid> {
  // 表格缩放（对齐 Swift gridScale）。
  double _scale = 1.0;
  double _startScale = 1.0;

  static double _clamp(double v) => v < 0.6 ? 0.6 : (v > 3.0 ? 3.0 : v);

  @override
  void initState() {
    super.initState();
    if (widget.controller != null) _scale = widget.controller!.scale;
    widget.controller?.addListener(_syncFromController);
  }

  @override
  void didUpdateWidget(covariant ResultGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller?.removeListener(_syncFromController);
      widget.controller?.addListener(_syncFromController);
      if (widget.controller != null) _scale = widget.controller!.scale;
    }
  }

  @override
  void dispose() {
    widget.controller?.removeListener(_syncFromController);
    super.dispose();
  }

  void _syncFromController() {
    final c = widget.controller;
    if (c != null && (c.scale - _scale).abs() > 0.001) {
      setState(() => _scale = c.scale);
    }
  }

  void _applyScale(double v) {
    final nv = _clamp(v);
    setState(() => _scale = nv);
    widget.controller?.setScale(nv);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final pkIndex = widget.primaryKey == null ? -1 : widget.columns.indexOf(widget.primaryKey!);
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

    // 对齐 Swift ResultGridView：不显示行号列，表头直接是列名。
    final header = Row(
      children: [
        for (var ci = 0; ci < widget.columns.length; ci++)
          headerCell((ci == pkIndex ? '🔑 ' : '') + widget.columns[ci], ci == pkIndex),
      ],
    );

    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        header,
        for (var ri = 0; ri < widget.rows.length; ri++)
          Row(
            children: [
              for (var ci = 0; ci < widget.columns.length; ci++)
                cell(widget.rows[ri][widget.columns[ci]], ci == pkIndex, ri, ci),
            ],
          ),
      ],
    );

    if (widget.rows.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Text('无结果集', style: TextStyle(color: Colors.grey)),
      );
    }

    return GestureDetector(
      // 双指捏合缩放（对齐 Swift MagnificationGesture）。
      onScaleStart: (_) => _startScale = _scale,
      onScaleUpdate: (d) {
        if (d.pointerCount >= 2) {
          _applyScale(_startScale * d.scale);
        }
      },
      // 双击复位（对齐 Swift onTapGesture(count: 2) { gridScale = 1 }）。
      onDoubleTap: () => _applyScale(1.0),
      child: SingleChildScrollView(
        scrollDirection: Axis.vertical,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Transform.scale(
            scale: _scale,
            alignment: Alignment.topLeft,
            child: body,
          ),
        ),
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
