import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../models/connection.dart';
import '../services/connection_store.dart';
import '../services/secure_storage.dart';
import '../services/mysql_service.dart';

class ConnectionEditScreen extends StatefulWidget {
  final ConnectionProfile? profile;
  const ConnectionEditScreen({super.key, this.profile});

  @override
  State<ConnectionEditScreen> createState() => _ConnectionEditScreenState();
}

class _ConnectionEditScreenState extends State<ConnectionEditScreen> {
  final _formKey = GlobalKey<FormState>();
  late ConnectionProfile _p;
  final _passwordController = TextEditingController();
  bool _passwordChanged = false;
  bool _showPassword = false;
  bool _testing = false;
  String? _testMessage;
  bool _testOk = false;

  @override
  void initState() {
    super.initState();
    _p = widget.profile?.copyWith() ??
        ConnectionProfile(
          name: '',
          host: '',
          port: 3306,
          user: 'root',
          database: '',
        );
    // 新建连接：TLS 默认开启、始终信任自签名证书（与 Swift 一致）。
    // 编辑已有连接：尊重已存值，避免把用户显式选了明文的连接偷偷改回加密。
    if (widget.profile == null) {
      _p.useTLS = true;
      _p.trustSelfSigned = true;
    }
    // 编辑时若已存密码，预填到密码框以便测试/保存（与 Swift 一致）。
    if (widget.profile != null) {
      SecureStorage.getPassword(_p.id).then((pw) {
        if (pw != null && pw.isNotEmpty && mounted) {
          _passwordController.text = pw;
        }
      });
    }
  }

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  void _save() async {
    if (!_formKey.currentState!.validate()) return;
    _formKey.currentState!.save();
    // 自签名信任跟随 SSL 开关（与 Swift 一致：关闭 SSL 即明文连接）。
    _p.trustSelfSigned = _p.useTLS;
    if (_passwordChanged) {
      final pw = _passwordController.text;
      if (pw.isNotEmpty) {
        await SecureStorage.setPassword(_p.id, pw);
      } else {
        await SecureStorage.deletePassword(_p.id);
      }
    }
    if (!mounted) return;
    Provider.of<ConnectionStore>(context, listen: false).upsert(_p);
    // 先取 messenger 再 pop：pop 之后 context 已失效，拿不到 Scaffold。
    final messenger = ScaffoldMessenger.of(context);
    final isNew = widget.profile == null;
    Navigator.of(context).pop();
    messenger.showSnackBar(SnackBar(
      content: Text(isNew ? '已添加连接' : '已保存修改'),
      duration: const Duration(seconds: 1),
    ));
  }

  /// 测试结果详情：错误信息有时很长（握手失败、DNS、SSL 证书链），
  /// 横幅只能显示两行，点开看全文并可一键复制，方便贴给别人排查。
  void _showTestDetail() {
    final msg = _testMessage ?? '';
    final ok = _testOk;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ok ? '连接成功' : '连接失败'),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: SelectableText(
              msg,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: msg));
              Navigator.of(ctx).pop();
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                content: Text('错误详情已复制'),
                duration: Duration(seconds: 1),
              ));
            },
            child: const Text('复制'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  /// 测试结果横幅：固定在表单上方，不随 ListView 滚动，
  /// 点「测试」后无论当前滚到哪都能立刻看到结果。
  Widget _buildTestBanner() {
    final ok = _testOk;
    final color = ok ? Colors.green : Colors.red;
    return Material(
      color: color.withValues(alpha: 0.12),
      child: InkWell(
        onTap: ok ? () => setState(() => _testMessage = null) : _showTestDetail,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(ok ? Icons.check_circle : Icons.error,
                  color: color, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _testMessage ?? '',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: color, fontSize: 13),
                    ),
                    if (!ok)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          '点此查看完整错误',
                          style: TextStyle(
                            fontSize: 11,
                            color: color.withValues(alpha: 0.75),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 18),
                tooltip: '关闭提示',
                onPressed: () => setState(() => _testMessage = null),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 对齐 Swift 编辑器的「测试」按钮：用当前表单参数直接建连，验证主机/端口/账号/密码。
  Future<void> _test() async {
    // 校验不通过时表单红字可能在屏幕外，给一句明确提示，
    // 否则用户会觉得「点了测试没任何反应」。
    if (!_formKey.currentState!.validate()) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('请先补全标红的必填项'),
        duration: Duration(seconds: 2),
      ));
      return;
    }
    _formKey.currentState!.save();
    _p.trustSelfSigned = _p.useTLS;
    setState(() {
      _testing = true;
      _testMessage = null;
    });
    final svc = MySQLService(_p);
    try {
      final pw = _passwordController.text.isNotEmpty
          ? _passwordController.text
          : (widget.profile != null
              ? (await SecureStorage.getPassword(_p.id)) ?? ''
              : '');
      await svc.connect(pw);
      if (mounted) {
        setState(() {
          _testOk = true;
          _testMessage = '连接成功 ✓';
        });
      }
    } catch (e) {
      if (mounted) {
        String detail = e.toString();
        // 去掉 Dart Exception 的默认 "Exception: " 前缀，让提示更直接。
        if (detail.startsWith('Exception: ')) {
          detail = detail.substring('Exception: '.length);
        }
        setState(() {
          _testOk = false;
          _testMessage = '连接失败：$detail';
        });
      }
    } finally {
      // 无论成功失败都关闭连接，避免失败时残留半开 socket。
      svc.close();
      if (mounted) setState(() => _testing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isNew = widget.profile == null;
    return Scaffold(
      appBar: AppBar(
        title: Text(isNew ? '新建连接' : '编辑连接'),
        // 对齐 Swift ConnectionEditorView：导航栏左侧「取消」（直接返回，不保存）。
        leadingWidth: 72,
        leading: TextButton(
          onPressed: () => Navigator.of(context).maybePop(),
          child: const Text('取消'),
        ),
        actions: [
          TextButton(
            onPressed: _testing ? null : _test,
            child: _testing
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('测试'),
          ),
          TextButton(onPressed: _save, child: const Text('保存')),
        ],
      ),
      body: Column(
        children: [
          // 测试结果固定在表单上方：点「测试」时用户可能正滚在页面中间或底部，
          // 结果放 ListView 末尾会看不见（原来的问题）。
          if (_testMessage != null) _buildTestBanner(),
          Expanded(
            child: Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('基本信息',
                              style: TextStyle(fontWeight: FontWeight.bold)),
                          const SizedBox(height: 8),
                          TextFormField(
                            initialValue: _p.name,
                            decoration:
                                const InputDecoration(labelText: '连接名称（可选）'),
                            onSaved: (v) => _p.name = v?.trim() ?? '',
                          ),
                          TextFormField(
                            initialValue: _p.host,
                            decoration: const InputDecoration(labelText: '主机 / IP'),
                            textInputAction: TextInputAction.next,
                            validator: (v) =>
                                (v == null || v.trim().isEmpty) ? '必填' : null,
                            onSaved: (v) => _p.host = v!.trim(),
                          ),
                          TextFormField(
                            initialValue: _p.port.toString(),
                            decoration: const InputDecoration(labelText: '端口'),
                            keyboardType: TextInputType.number,
                            textInputAction: TextInputAction.next,
                            // 只让数字进框：中文输入法下仍能打出字母，光靠
                            // keyboardType 拦不住，会出现「端口无效」的无谓报错。
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly
                            ],
                            validator: (v) {
                              final n = int.tryParse((v ?? '').trim());
                              // 对齐可连接范围（Swift 只校验能转成 Int，这里补上上界，
                              // 避免保存一个 MySQL 无法使用的端口）。
                              if (n == null || n <= 0 || n > 65535) {
                                return '端口无效（1-65535）';
                              }
                              return null;
                            },
                            onSaved: (v) => _p.port = int.parse(v!.trim()),
                          ),
                          TextFormField(
                            initialValue: _p.user,
                            decoration: const InputDecoration(labelText: '用户名'),
                            textInputAction: TextInputAction.next,
                            validator: (v) =>
                                (v == null || v.trim().isEmpty) ? '必填' : null,
                            onSaved: (v) => _p.user = v?.trim() ?? 'root',
                          ),
                          TextFormField(
                            controller: _passwordController,
                            decoration: InputDecoration(
                              labelText: '密码',
                              suffixIcon: IconButton(
                                icon: Icon(_showPassword
                                    ? Icons.visibility
                                    : Icons.visibility_off),
                                onPressed: () =>
                                    setState(() => _showPassword = !_showPassword),
                              ),
                            ),
                            obscureText: !_showPassword,
                            onChanged: (_) => _passwordChanged = true,
                          ),
                          TextFormField(
                            initialValue: _p.database,
                            decoration:
                                const InputDecoration(labelText: '默认数据库（可选）'),
                            onSaved: (v) => _p.database = v?.trim() ?? '',
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('安全',
                              style: TextStyle(fontWeight: FontWeight.bold)),
                          const SizedBox(height: 8),
                          const Text(
                            '已启用加密传输，并自动信任自签名证书（适用于自建服务器）。关闭后将使用明文连接。',
                            style: TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                          const SizedBox(height: 4),
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            secondary:
                                const Icon(Icons.lock, color: Colors.green),
                            title: const Text('使用 SSL 连接'),
                            value: _p.useTLS,
                            onChanged: (v) => setState(() => _p.useTLS = v),
                          ),
                        ],
                      ),
                    ),
                  ),
                  // 底部不再放测试结果，避免「测试了看不到结果」。
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
