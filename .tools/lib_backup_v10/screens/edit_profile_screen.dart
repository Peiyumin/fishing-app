import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../app_theme.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../services/api_client.dart';
import '../services/api_config.dart';
import '../services/session_provider.dart';

/// 编辑资料：更换头像 + 修改昵称 + 修改登录密码
class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _nickCtrl = TextEditingController();
  final _oldPwdCtrl = TextEditingController();
  final _newPwdCtrl = TextEditingController();
  final _newPwd2Ctrl = TextEditingController();
  final _picker = ImagePicker();

  String? _avatarPath; // 新选择的本地头像路径
  bool _saving = false;
  bool _pwdSaving = false;
  bool _showPwdForm = false;

  @override
  void initState() {
    super.initState();
    _nickCtrl.text =
        Provider.of<SessionProvider>(context, listen: false).nickname ?? '';
  }

  @override
  void dispose() {
    _nickCtrl.dispose();
    _oldPwdCtrl.dispose();
    _newPwdCtrl.dispose();
    _newPwd2Ctrl.dispose();
    super.dispose();
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  /// 选择新头像（相册 / 拍照，压缩到 512px，统一转 jpeg）
  Future<void> _pickAvatar(ImageSource source) async {
    final x = await _picker.pickImage(source: source, maxWidth: 512, maxHeight: 512, imageQuality: 85);
    if (x != null) setState(() => _avatarPath = x.path);
  }

  void _showAvatarSheet() {
    showModalBottomSheet(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo),
              title: const Text('从相册选择'),
              onTap: () {
                Navigator.pop(context);
                _pickAvatar(ImageSource.gallery);
              },
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('拍照'),
              onTap: () {
                Navigator.pop(context);
                _pickAvatar(ImageSource.camera);
              },
            ),
          ],
        ),
      ),
    );
  }

  /// 保存资料（昵称 + 头像）
  Future<void> _save() async {
    final sp = Provider.of<SessionProvider>(context, listen: false);
    final nick = _nickCtrl.text.trim();
    if (nick.isEmpty) {
      _toast('昵称不能为空');
      return;
    }
    if (nick.length > 20) {
      _toast('昵称最多 20 个字');
      return;
    }
    setState(() => _saving = true);
    try {
      String? avatarUrl;
      if (_avatarPath != null) {
        avatarUrl = await ApiClient.uploadFile(_avatarPath!,
            contentType: 'image/jpeg');
      }
      await sp.updateProfile(nickname: nick, avatar: avatarUrl);
      if (mounted) {
        _toast('资料已保存');
        Navigator.of(context).pop();
      }
    } catch (e) {
      _toast('保存失败：$e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// 修改登录密码
  Future<void> _savePassword() async {
    final sp = Provider.of<SessionProvider>(context, listen: false);
    final old = _oldPwdCtrl.text;
    final n1 = _newPwdCtrl.text;
    final n2 = _newPwd2Ctrl.text;
    if (old.isEmpty || n1.isEmpty) {
      _toast('请填写原密码和新密码');
      return;
    }
    if (n1.length < 6) {
      _toast('新密码至少 6 位');
      return;
    }
    if (n1 != n2) {
      _toast('两次输入的新密码不一致');
      return;
    }
    setState(() => _pwdSaving = true);
    try {
      await sp.changePassword(old, n1);
      _toast('密码已修改，请牢记新密码');
      _oldPwdCtrl.clear();
      _newPwdCtrl.clear();
      _newPwd2Ctrl.clear();
      if (mounted) setState(() => _showPwdForm = false);
    } catch (e) {
      _toast('修改失败：$e');
    } finally {
      if (mounted) setState(() => _pwdSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sp = Provider.of<SessionProvider>(context);
    final avatarUrl = sp.avatar;
    final demo = !ApiConfig.enabled;

    return Scaffold(
      appBar: AppBar(title: const Text('编辑资料')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (demo)
            Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.orange.shade200),
              ),
              child: const Text('当前为演示模式（未配置后端），资料修改不可用。',
                  style: TextStyle(fontSize: 13, color: Colors.brown)),
            ),
          // 头像
          Center(
            child: Stack(
              children: [
                CircleAvatar(
                  radius: 46,
                  backgroundColor: AppTheme.primary,
                  backgroundImage: _avatarPath != null
                      ? FileImage(File(_avatarPath!))
                      : (avatarUrl != null && avatarUrl.isNotEmpty
                          ? CachedNetworkImageProvider(avatarUrl)
                          : null) as ImageProvider?,
                  child: _avatarPath == null &&
                          (avatarUrl == null || avatarUrl.isEmpty)
                      ? const Icon(Icons.person,
                          size: 46, color: Colors.white)
                      : null,
                ),
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: GestureDetector(
                    onTap: demo ? null : _showAvatarSheet,
                    child: const CircleAvatar(
                      radius: 16,
                      backgroundColor: AppTheme.primary,
                      child: Icon(Icons.camera_alt,
                          size: 16, color: Colors.white),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          const Center(
            child: Text('点击相机图标更换头像',
                style: TextStyle(fontSize: 12, color: Colors.grey)),
          ),
          const SizedBox(height: 20),
          // 昵称
          TextField(
            controller: _nickCtrl,
            maxLength: 20,
            decoration: const InputDecoration(
              labelText: '昵称',
              hintText: '最多 20 个字',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.person_outline),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 46,
            child: ElevatedButton(
              onPressed: (demo || _saving) ? null : _save,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                foregroundColor: Colors.white,
              ),
              child: _saving
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                          strokeWidth: 2.5, color: Colors.white),
                    )
                  : const Text('保存资料'),
            ),
          ),
          const SizedBox(height: 24),
          const Divider(),
          // 修改密码（折叠面板）
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.lock_outline),
            title: const Text('修改登录密码'),
            trailing: Icon(_showPwdForm
                ? Icons.expand_less
                : Icons.expand_more),
            onTap: demo
                ? null
                : () => setState(() => _showPwdForm = !_showPwdForm),
          ),
          if (_showPwdForm && !demo) ...[
            const SizedBox(height: 8),
            TextField(
              controller: _oldPwdCtrl,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: '原密码',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _newPwdCtrl,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: '新密码（至少 6 位）',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _newPwd2Ctrl,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: '确认新密码',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 44,
              child: OutlinedButton(
                onPressed: _pwdSaving ? null : _savePassword,
                child: _pwdSaving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2.5),
                      )
                    : const Text('确认修改密码'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
