import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 结果表格缩放控制器：让外层（数据页 / 控制台底部工具栏）
/// 能读取当前缩放比例并在点击「xx%」时复位（对齐 Swift gridScale 的 % 按钮）。
class ResultGridController extends ChangeNotifier {
  double _scale = 1.0;
  double get scale => _scale;

  /// 下限 0.5：字号会等比缩到 6px，已是「缩略图」可辨认的极限
  /// （再小就只能看清色块了）。上限 3.0 与 Swift 版一致。
  static double _clamp(double v) => v < 0.5 ? 0.5 : (v > 3.0 ? 3.0 : v);

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
/// 点按单元格弹出完整值并支持复制，长按可直接复制。
/// 支持双指捏合缩放（0.5~3.0）+ 双击复位（对齐 Swift gridScale 手势）。
/// 列宽按内容自适应（不再固定 160px），短列省下的空间直接换成多看到几列。
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

  // 表头横向滚动控制器：表头固定在顶部，但横向必须与数据区同步，
  // 否则左右滑动后列名和列内容会错位。
  final ScrollController _headerH = ScrollController();
  final ScrollController _bodyH = ScrollController();

  // 列宽基准（100% 时的像素宽度），按内容测量后缓存；
  // 缩放时只做乘法（_baseWidths[ci] * _scale），避免捏合过程中每帧重排文字。
  List<double>? _baseWidths;

  /// 点击 +/− 的档位：缩得越小步长越小，保证每一下都有明显变化，
  /// 且 100% 一定命中（不会停在 113% 这类别扭值）。捏合缩放仍是连续值。
  static const List<double> _stops = [
    0.5, 0.6, 0.75, 0.9, 1.0, 1.2, 1.4, 1.7, 2.0, 2.4, 2.8, 3.0
  ];

  static double _clamp(double v) => v < 0.5 ? 0.5 : (v > 3.0 ? 3.0 : v);

  /// 找比当前比例大/小的下一档。
  double _nextStop(bool zoomIn) {
    if (zoomIn) {
      for (final s in _stops) {
        if (s > _scale + 0.001) return s;
      }
      return _stops.last;
    }
    for (final s in _stops.reversed) {
      if (s < _scale - 0.001) return s;
    }
    return _stops.first;
  }

  /// 量一段文字在指定字号/字重下的宽度。
  double _textWidth(String text, double fontSize, FontWeight weight) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
            fontFamily: 'monospace', fontSize: fontSize, fontWeight: weight),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    return tp.width;
  }

  /// 估算每列需要多宽：表头与前 40 行内容里最宽的那个，夹在 56~220px。
  /// 固定 160px 会让 `id`/`status`/`age` 这类短列白白吃掉一半屏幕。
  List<double> _ensureWidths() {
    final cached = _baseWidths;
    if (cached != null && cached.length == widget.columns.length) return cached;
    const sampleLimit = 40;
    final sample =
        widget.rows.length > sampleLimit ? sampleLimit : widget.rows.length;
    final result = <double>[];
    for (var ci = 0; ci < widget.columns.length; ci++) {
      final col = widget.columns[ci];
      final isPk = col == widget.primaryKey;
      var w = _textWidth((isPk ? '🔑 ' : '') + col, 13, FontWeight.bold);
      for (var ri = 0; ri < sample; ri++) {
        final v = widget.rows[ri][col];
        if (v == null || v.isEmpty) continue;
        final vw = _textWidth(v, 12, FontWeight.normal);
        if (vw > w) w = vw;
      }
      // +12 是左右内边距（各 6px），避免文字贴边。
      result.add((w + 12).clamp(56.0, 220.0).toDouble());
    }
    _baseWidths = result;
    return result;
  }

  @override
  void initState() {
    super.initState();
    if (widget.controller != null) _scale = widget.controller!.scale;
    widget.controller?.addListener(_syncFromController);
    _bodyH.addListener(_syncHeaderScroll);
  }

  @override
  void didUpdateWidget(covariant ResultGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 换页/换表后内容变了，列宽估算要重算。
    if (oldWidget.columns != widget.columns || oldWidget.rows != widget.rows) {
      _baseWidths = null;
    }
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller?.removeListener(_syncFromController);
      widget.controller?.addListener(_syncFromController);
      if (widget.controller != null) _scale = widget.controller!.scale;
    }
  }

  @override
  void dispose() {
    _bodyH.removeListener(_syncHeaderScroll);
    _headerH.dispose();
    _bodyH.dispose();
    widget.controller?.removeListener(_syncFromController);
    super.dispose();
  }

  /// 把数据区的横向偏移同步给固定表头。
  void _syncHeaderScroll() {
    if (!mounted || !_headerH.hasClients || !_bodyH.hasClients) return;
    final target = _bodyH.offset.clamp(0.0, _headerH.position.maxScrollExtent);
    if ((_headerH.offset - target).abs() > 0.01) {
      _headerH.jumpTo(target);
    }
  }

  void _syncFromController() {
    final c = widget.controller;
    if (c != null && (c.scale - _scale).abs() > 0.001) {
      setState(() => _scale = c.scale);
      // 缩放后列宽变化，等布局完成再把表头对齐到数据区。
      WidgetsBinding.instance.addPostFrameCallback((_) => _syncHeaderScroll());
    }
  }

  void _applyScale(double v) {
    final nv = _clamp(v);
    setState(() => _scale = nv);
    widget.controller?.setScale(nv);
    // 布局尺寸随字号/列宽一起缩放（不使用 Transform.scale），
    // 这样放大后滚动范围也会同步变大，且表头不会盖住数据行。
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncHeaderScroll());
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final pkIndex =
        widget.primaryKey == null ? -1 : widget.columns.indexOf(widget.primaryKey!);
    // 缩放直接作用到列宽/内边距/字号（与 Swift 版一致），
    // 不用 Transform.scale —— 后者只改绘制不改布局，放大后滚动范围不会变，
    // 而且固定表头会压到数据行上。
    // 列宽不再固定 160：按内容测一次基准宽度，缩放时整体乘系数。
    final colWidths = _ensureWidths();
    final pad = 6.0 * _scale;
    const mono = TextStyle(fontFamily: 'monospace');

    // 表头（对齐 Swift ResultGridView.headerCell）：
    // 非主键列 Color.gray.opacity(0.18)，主键列 accentColor.opacity(0.18)。
    Widget headerCell(String label, bool isPk, int ci) => Container(
          width: colWidths[ci] * _scale,
          padding: EdgeInsets.all(pad),
          color: isPk
              ? scheme.primary.withValues(alpha: 0.18)
              : Colors.grey.withValues(alpha: 0.18),
          child: Text(
            label,
            style: mono.copyWith(
                fontSize: 13 * _scale, fontWeight: FontWeight.bold),
            overflow: TextOverflow.ellipsis,
          ),
        );

    // 数据单元格（对齐 Swift ResultGridView.resultCell）：
    // 主键列 accentColor.opacity(0.10)；其余按 (行+列)%2==0 铺 Color.gray.opacity(0.04)。
    Widget cell(String? v, String colName, bool isPk, int ri, int ci) {
      final stripe = (ri + ci) % 2 == 0;
      final bg = isPk
          ? scheme.primary.withValues(alpha: 0.10)
          : (stripe ? Colors.grey.withValues(alpha: isDark ? 0.12 : 0.04) : null);
      return GestureDetector(
        onTap: () => _showCell(context, colName, v),
        onLongPress: () => _copyCell(context, colName, v),
        child: Container(
          width: colWidths[ci] * _scale,
          constraints: BoxConstraints(
            // 缩小后行太矮不好长按复制，给一个最低行高。
            minHeight: (26 * _scale).clamp(22.0, 78.0).toDouble(),
          ),
          padding: EdgeInsets.all(pad),
          color: bg,
          child: Text(
            v ?? 'NULL',
            style: mono.copyWith(
              fontSize: 12 * _scale,
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
          headerCell(
              (ci == pkIndex ? '🔑 ' : '') + widget.columns[ci],
              ci == pkIndex,
              ci),
      ],
    );

    final rowsBody = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var ri = 0; ri < widget.rows.length; ri++)
          Row(
            children: [
              for (var ci = 0; ci < widget.columns.length; ci++)
                cell(widget.rows[ri][widget.columns[ci]], widget.columns[ci],
                    ci == pkIndex, ri, ci),
            ],
          ),
      ],
    );

    // 对齐 Swift ResultGridView：以 columns.isEmpty 判空。
    // 用 rows.isEmpty 会把「有列但 0 行」的空表误判成「无结果集」，看不到列头。
    if (widget.columns.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Text('无结果集', style: TextStyle(color: Colors.grey)),
      );
    }

    // 表格 + 右下角缩放按钮：双指捏合仍然可用，另外提供单击 +/− 的入口，
    // 模拟器/单手场景下手势不好触发时可以直接点。
    return Stack(
      fit: StackFit.expand,
      children: [
        GestureDetector(
          // 双指捏合缩放（对齐 Swift MagnificationGesture）。
          onScaleStart: (_) => _startScale = _scale,
          onScaleUpdate: (d) {
            if (d.pointerCount >= 2) {
              _applyScale(_startScale * d.scale);
            }
          },
          // 双击复位（对齐 Swift onTapGesture(count: 2) { gridScale = 1 }）。
          onDoubleTap: () => _applyScale(1.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 固定表头：只参与横向滚动（由数据区驱动），不参与纵向滚动，
              // 所以往下滑数据时字段名一直留在顶部。
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                controller: _headerH,
                physics: const NeverScrollableScrollPhysics(),
                child: header,
              ),
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.vertical,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    controller: _bodyH,
                    child: rowsBody,
                  ),
                ),
              ),
            ],
          ),
        ),
        Positioned(
          right: 8,
          bottom: 8,
          child: _buildZoomButtons(scheme),
        ),
      ],
    );
  }

  /// 右下角缩放按钮组：＋ / 百分比（点一下复位 100%）/ －。
  /// 与双指捏合共用同一个 _scale，范围 0.5~3.0；点击走预设档位，手感更稳。
  Widget _buildZoomButtons(ColorScheme scheme) {
    final canZoomIn = _scale < 2.999;
    final canZoomOut = _scale > 0.501;

    Widget button(IconData icon, String tooltip, bool enabled, VoidCallback onTap) {
      return Material(
        type: MaterialType.transparency,
        child: InkResponse(
          onTap: enabled ? onTap : null,
          radius: 20,
          containedInkWell: true,
          child: Tooltip(
            message: tooltip,
            child: SizedBox(
              width: 42,
              height: 40,
              child: Icon(
                icon,
                size: 18,
                color: enabled
                    ? scheme.primary
                    : scheme.onSurface.withValues(alpha: 0.25),
              ),
            ),
          ),
        ),
      );
    }

    return Material(
      color: scheme.surface,
      elevation: 3,
      shadowColor: Colors.black.withValues(alpha: 0.35),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: scheme.onSurface.withValues(alpha: 0.12),
            width: 0.5,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            button(Icons.add, '放大', canZoomIn, () => _applyScale(_nextStop(true))),
            // 百分比：点一下复位到 100%（等价于双击表格复位）。
            InkWell(
              onTap: () => _applyScale(1.0),
              child: Container(
                width: 42,
                height: 24,
                alignment: Alignment.center,
                child: Text(
                  '${(_scale * 100).round()}%',
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 10,
                    color: scheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
              ),
            ),
            button(Icons.remove, '缩小', canZoomOut,
                () => _applyScale(_nextStop(false))),
          ],
        ),
      ),
    );
  }

  /// 查看完整值（对齐 Swift CellValueSheet：标题为列名、正文等宽、底部「复制完整值」）。
  void _showCell(BuildContext context, String column, String? value) {
    final display = value == null ? 'NULL' : (value.isEmpty ? '空字符串' : value);
    final copyText = value;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(column),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: SelectableText(
              display,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 14),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: copyText == null
                ? null
                : () {
                    Clipboard.setData(ClipboardData(text: copyText));
                    Navigator.of(ctx).pop();
                  },
            child: const Text('复制完整值'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('完成'),
          ),
        ],
      ),
    );
  }

  /// 长按直接复制（对齐 Swift ResultGridView 的 contextMenu「复制值」）。
  void _copyCell(BuildContext context, String column, String? value) {
    if (value == null) return;
    Clipboard.setData(ClipboardData(text: value));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('已复制「$column」的值'),
        duration: const Duration(seconds: 1),
      ),
    );
  }
}
