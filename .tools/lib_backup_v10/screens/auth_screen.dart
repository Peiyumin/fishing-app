import 'package:flutter/material.dart';

import '../app_theme.dart';
import 'package:provider/provider.dart';

import '../services/session_provider.dart';

/// 登录 / 注册页（邮箱 + 密码；注册额外填写昵称）
class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  bool _isRegister = false;
  final _phone = TextEditingController();
  final _pwd = TextEditingController();
  final _name = TextEditingController();
  bool _busy = false;

  Future<void> _submit() async {
    final sp = Provider.of<SessionProvider>(context, listen: false);
    if (_phone.text.isEmpty || _pwd.text.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('请填写手机号和密码')));
      return;
    }
    setState(() => _busy = true);
    try {
      if (_isRegister) {
        if (_name.text.isEmpty) {
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('请填写昵称')));
          return;
        }
        await sp.signUp(_phone.text.trim(), _pwd.text, _name.text.trim());
      } else {
        await sp.signIn(_phone.text.trim(), _pwd.text);
      }
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('操作失败：$e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_isRegister ? '注册' : '登录')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const SizedBox(height: 24),
            const Icon(Icons.phishing, size: 64, color: AppTheme.primary),
            const SizedBox(height: 24),
            TextField(
              controller: _phone,
              decoration: const InputDecoration(
                labelText: '手机号', border: OutlineInputBorder()),
              keyboardType: TextInputType.phone,
            ),
            const SizedBox(height: 12),
            if (_isRegister)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: TextField(
                  controller: _name,
                  decoration: const InputDecoration(
                    labelText: '昵称', border: OutlineInputBorder()),
                ),
              ),
            TextField(
              controller: _pwd,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: '密码', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 46,
              child: ElevatedButton(
                onPressed: _busy ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  foregroundColor: Colors.white,
                ),
                child: _busy
                    ? const CircularProgressIndicator(color: Colors.white)
                    : Text(_isRegister ? '注册' : '登录'),
              ),
            ),
            TextButton(
              onPressed: () => setState(() => _isRegister = !_isRegister),
              child: Text(_isRegister
                  ? '已有账号？去登录'
                  : '没有账号？去注册'),
            ),
          ],
        ),
      ),
    );
  }
}
