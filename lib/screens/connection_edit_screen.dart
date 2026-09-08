import 'package:flutter/material.dart';
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
  bool _testing = false;

  @override
  void initState() {
    super.initState();
    // 编辑时基于原对象做一份拷贝：开关等直接改动不会污染 store 里已存的连接，
    // 只有点「保存」(upsert) 才真正写回。
    _p = widget.profile?.copyWith() ??
        ConnectionProfile(
          name: '',
          host: '',
          port: 3306,
          user: 'root',
          database: '',
          useTLS: true,
          trustSelfSigned: true,
        );
    // 编辑时不预填密码：避免泄漏密码长度，且「留空」语义统一为「保留原密码」。
  }

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  void _save() async {
    if (!_formKey.currentState!.validate()) return;
    _formKey.currentState!.save();
    // 对齐 Swift：信任自签名证书恒等于 TLS 开关（buildProfile 写 trustSelfSigned: useTLS）。
    _p.trustSelfSigned = _p.useTLS;
    // 仅当用户确实输入了非空密码才写入；留空 = 保留原密码（不覆盖）。
    if (_passwordChanged && _passwordController.text.isNotEmpty) {
      await SecureStorage.setPassword(_p.id, _passwordController.text);
    }
    if (!mounted) return;
    Provider.of<ConnectionStore>(context, listen: false).upsert(_p);
    Navigator.of(context).pop();
  }

  /// 对齐 Swift 编辑器的「测试」按钮：用当前表单参数直接建连，验证主机/端口/账号/密码。
  Future<void> _test() async {
    if (!_formKey.currentState!.validate()) return;
    _formKey.currentState!.save();
    _p.trustSelfSigned = _p.useTLS;
    setState(() => _testing = true);
    try {
      final svc = MySQLService(_p);
      await svc.connect(_passwordController.text);
      svc.close();
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('连接成功 ✓')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('连接失败：$e')));
      }
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.profile == null ? '新增连接' : '编辑连接'),
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
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              initialValue: _p.name,
              decoration: const InputDecoration(labelText: '名称（可选）'),
              onSaved: (v) => _p.name = v?.trim() ?? '',
            ),
            TextFormField(
              initialValue: _p.host,
              decoration: const InputDecoration(labelText: '主机 / IP *'),
              validator: (v) => (v == null || v.trim().isEmpty) ? '必填' : null,
              onSaved: (v) => _p.host = v!.trim(),
            ),
            TextFormField(
              initialValue: _p.port.toString(),
              decoration: const InputDecoration(labelText: '端口 *'),
              keyboardType: TextInputType.number,
              validator: (v) {
                final n = int.tryParse(v ?? '');
                return (n == null || n <= 0) ? '端口无效' : null;
              },
              onSaved: (v) => _p.port = int.parse(v!),
            ),
            TextFormField(
              initialValue: _p.user,
              decoration: const InputDecoration(labelText: '用户名 *'),
              onSaved: (v) => _p.user = v?.trim() ?? 'root',
            ),
            TextFormField(
              controller: _passwordController,
              decoration: InputDecoration(
                labelText: widget.profile == null ? '密码（可选）' : '新密码（留空表示保留原密码）',
              ),
              obscureText: true,
              onChanged: (_) => _passwordChanged = true,
            ),
            TextFormField(
              initialValue: _p.database,
              decoration: const InputDecoration(labelText: '默认数据库（可选）'),
              onSaved: (v) => _p.database = v?.trim() ?? '',
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              title: const Text('使用 TLS/SSL 加密'),
              subtitle: const Text('启用加密传输，并自动信任自签名证书（适用于自建服务器）'),
              value: _p.useTLS,
              onChanged: (v) => setState(() => _p.useTLS = v),
            ),
          ],
        ),
      ),
    );
  }
}
