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
    // TLS 始终开启、始终信任自签名证书，无需用户操作。
    _p.useTLS = true;
    _p.trustSelfSigned = true;
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
    // TLS 恒开、自签名恒信任。
    _p.useTLS = true;
    _p.trustSelfSigned = true;
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
    Navigator.of(context).pop();
  }

  /// 对齐 Swift 编辑器的「测试」按钮：用当前表单参数直接建连，验证主机/端口/账号/密码。
  Future<void> _test() async {
    if (!_formKey.currentState!.validate()) return;
    _formKey.currentState!.save();
    _p.useTLS = true;
    _p.trustSelfSigned = true;
    setState(() {
      _testing = true;
      _testMessage = null;
    });
    try {
      final pw = _passwordController.text.isNotEmpty
          ? _passwordController.text
          : (widget.profile != null
              ? (await SecureStorage.getPassword(_p.id)) ?? ''
              : '');
      final svc = MySQLService(_p);
      await svc.connect(pw);
      svc.close();
      if (mounted) {
        setState(() {
          _testOk = true;
          _testMessage = '连接成功 ✓';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _testOk = false;
          _testMessage = '连接失败：$e';
        });
      }
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isNew = widget.profile == null;
    return Scaffold(
      appBar: AppBar(
        title: Text(isNew ? '新建连接' : '编辑连接'),
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
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('基本信息', style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    TextFormField(
                      initialValue: _p.name,
                      decoration: const InputDecoration(labelText: '连接名称（可选）'),
                      onSaved: (v) => _p.name = v?.trim() ?? '',
                    ),
                    TextFormField(
                      initialValue: _p.host,
                      decoration: const InputDecoration(labelText: '主机 / IP'),
                      validator: (v) => (v == null || v.trim().isEmpty) ? '必填' : null,
                      onSaved: (v) => _p.host = v!.trim(),
                    ),
                    TextFormField(
                      initialValue: _p.port.toString(),
                      decoration: const InputDecoration(labelText: '端口'),
                      keyboardType: TextInputType.number,
                      validator: (v) {
                        final n = int.tryParse(v ?? '');
                        return (n == null || n <= 0) ? '端口无效' : null;
                      },
                      onSaved: (v) => _p.port = int.parse(v!),
                    ),
                    TextFormField(
                      initialValue: _p.user,
                      decoration: const InputDecoration(labelText: '用户名'),
                      validator: (v) => (v == null || v.trim().isEmpty) ? '必填' : null,
                      onSaved: (v) => _p.user = v?.trim() ?? 'root',
                    ),
                    TextFormField(
                      controller: _passwordController,
                      decoration: InputDecoration(
                        labelText: '密码',
                        suffixIcon: IconButton(
                          icon: Icon(_showPassword ? Icons.visibility_off : Icons.visibility),
                          onPressed: () => setState(() => _showPassword = !_showPassword),
                        ),
                      ),
                      obscureText: !_showPassword,
                      onChanged: (_) => _passwordChanged = true,
                    ),
                    TextFormField(
                      initialValue: _p.database,
                      decoration: const InputDecoration(labelText: '默认数据库（可选）'),
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
                    const Text('安全', style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    const Text(
                      '已启用加密传输，并自动信任自签名证书（适用于自建服务器）。关闭后将使用明文连接。',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(Icons.lock, size: 18, color: Colors.green),
                        const SizedBox(width: 8),
                        Text(
                          '使用 SSL 连接',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.primary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            if (_testMessage != null) ...[
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    _testMessage!,
                    style: TextStyle(
                      color: _testOk ? Colors.green : Colors.red,
                      fontSize: 13,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
