import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/connection.dart';
import '../services/connection_store.dart';
import '../services/secure_storage.dart';

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

  @override
  void initState() {
    super.initState();
    _p = widget.profile ??
        ConnectionProfile(
          name: '',
          host: '',
          port: 3306,
          user: 'root',
          database: '',
          useTLS: true,
          trustSelfSigned: true,
        );
    if (widget.profile != null) {
      SecureStorage.getPassword(_p.id).then((pw) {
        if (mounted) _passwordController.text = pw ?? '';
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
    if (_passwordChanged) {
      await SecureStorage.setPassword(_p.id, _passwordController.text);
    }
    if (!mounted) return;
    Provider.of<ConnectionStore>(context, listen: false).upsert(_p);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.profile == null ? '新增连接' : '编辑连接'),
        actions: [
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
              decoration: const InputDecoration(labelText: '密码'),
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
              value: _p.useTLS,
              onChanged: (v) => setState(() => _p.useTLS = v),
            ),
            SwitchListTile(
              title: const Text('信任自签名证书'),
              subtitle: const Text('仅在使用 TLS 时生效；关闭则校验证书链'),
              value: _p.trustSelfSigned,
              onChanged: (v) => setState(() => _p.trustSelfSigned = v),
            ),
          ],
        ),
      ),
    );
  }
}
