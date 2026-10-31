import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../widgets/emoji_panel.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../services/api_client.dart';
import '../services/api_config.dart';
import '../services/session_provider.dart';
import '../widgets/center_toast.dart';
import '../widgets/user_avatar.dart';

/// 编辑资料：更换头像 + 修改昵称 + 修改登录密码
class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _nickCtrl = TextEditingController();
  final _bioCtrl = TextEditingController();
  final _oldPwdCtrl = TextEditingController();
  final _newPwdCtrl = TextEditingController();
  final _newPwd2Ctrl = TextEditingController();
  final _picker = ImagePicker();

  String? _avatarPath; // 新选择的本地头像路径
  String? _coverPath; // 新选择的本地背景图路径（v2.1.56）
  bool _coverCleared = false; // 用户点了「恢复默认」
  bool _saving = false;
  bool _pwdSaving = false;
  bool _showPwdForm = false;

  @override
  void initState() {
    super.initState();
    _nickCtrl.text =
        Provider.of<SessionProvider>(context, listen: false).nickname ?? '';
    _bioCtrl.text =
        Provider.of<SessionProvider>(context, listen: false).bio ?? '';
  }

  @override
  void dispose() {
    _nickCtrl.dispose();
    _bioCtrl.dispose();
    _oldPwdCtrl.dispose();
    _newPwdCtrl.dispose();
    _newPwd2Ctrl.dispose();
    super.dispose();
  }

  void _toast(String msg) {
    if (!mounted) return;
    CenterToast.show(context, msg);
  }

  /// 选择新头像（相册 / 拍照，压缩到 512px，统一转 jpeg）
  Future<void> _pickAvatar(ImageSource source) async {
    final x = await _picker.pickImage(source: source, maxWidth: 512, maxHeight: 512, imageQuality: 85);
    if (x != null) setState(() => _avatarPath = x.path);
  }

  /// 选背景图：宽一点、质量高一点（横图铺满主页顶部）
  Future<void> _pickCover(ImageSource source) async {
    final x = await _picker.pickImage(
      source: source,
      maxWidth: 1440,
      maxHeight: 900,
      imageQuality: 82,
    );
    if (x != null) {
      setState(() {
        _coverPath = x.path;
        _coverCleared = false;
      });
    }
  }

  void _showCoverSheet() {
    showModalBottomSheet(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('从相册选择'),
              onTap: () {
                Navigator.pop(context);
                _pickCover(ImageSource.gallery);
              },
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined),
              title: const Text('拍照'),
              onTap: () {
                Navigator.pop(context);
                _pickCover(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.restart_alt),
              title: const Text('恢复默认背景'),
              subtitle: const Text('用 App 自带的深绿渐变'),
              onTap: () {
                Navigator.pop(context);
                setState(() {
                  _coverPath = null;
                  _coverCleared = true;
                });
              },
            ),
          ],
        ),
      ),
    );
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
    final bio = _bioCtrl.text.trim();
    if (nick.isEmpty) {
      _toast('昵称不能为空');
      return;
    }
    if (nick.length > 20) {
      _toast('昵称最多 20 个字');
      return;
    }
    if (bio.length > 50) {
      _toast('个性签名最多 50 个字');
      return;
    }
    setState(() => _saving = true);
    try {
      String? avatarUrl;
      if (_avatarPath != null) {
        avatarUrl = await ApiClient.uploadFile(_avatarPath!,
            contentType: 'image/jpeg');
      }
      String? coverUrl;
      if (_coverPath != null) {
        coverUrl = await ApiClient.uploadFile(_coverPath!,
            contentType: 'image/jpeg');
      } else if (_coverCleared) {
        coverUrl = ''; // 空串 = 清掉背景图，回到默认渐变
      }
      await sp.updateProfile(
        nickname: nick,
        avatar: avatarUrl,
        cover: coverUrl,
        bio: bio,
      );
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

  /// 背景图选择卡（点击整块就能换）
  Widget _coverCard(SessionProvider sp, bool demo) {
    final local = _coverPath;
    final remote = _coverCleared ? null : sp.coverUrl;
    return GestureDetector(
      onTap: demo ? null : _showCoverSheet,
      child: Container(
        height: 132,
        width: double.infinity,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppTheme.radiusLg),
          gradient: AppTheme.brandGradient,
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (local != null)
              Image.file(File(local), fit: BoxFit.cover)
            else if (remote != null)
              CachedNetworkImage(
                imageUrl: remote,
                fit: BoxFit.cover,
                placeholder: (_, __) => const ColoredBox(
                    color: AppTheme.primaryLight, child: SizedBox.expand()),
                errorWidget: (_, __, ___) => const SizedBox.shrink(),
              ),
            // 底部压暗，白字才看得清
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.black.withOpacity(0.45),
                  ],
                ),
              ),
            ),
            Positioned(
              left: 12,
              bottom: 10,
              child: Row(
                children: [
                  const Icon(Icons.wallpaper, size: 15, color: Colors.white),
                  const SizedBox(width: 6),
                  Text(
                    (local != null || remote != null) ? '点击更换背景图' : '点击上传背景图',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      shadows: [Shadow(blurRadius: 4, color: Colors.black45)],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sp = Provider.of<SessionProvider>(context);
    // 用 avatarUrl（自动补端口/拼域名），直接用 sp.avatar 会因后台丢端口 404
    final avatarUrl = sp.avatarUrl;
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
          // 背景图（v2.1.56：主页顶部大图，所有人都能看到）
          _coverCard(sp, demo),
          const SizedBox(height: 6),
          const Text('背景图会显示在你的主页顶部，别人也能看到',
              style: TextStyle(fontSize: 11.5, color: AppTheme.textTertiary)),
          const SizedBox(height: 18),
          // 头像
          Center(
            child: Stack(
              children: [
                _avatarPath != null
                    ? CircleAvatar(
                        radius: 46,
                        backgroundColor: AppTheme.primary,
                        backgroundImage: FileImage(File(_avatarPath!)),
                      )
                    : UserAvatar(
                        url: avatarUrl,
                        userId: sp.isLoggedIn ? sp.userId : null,
                        radius: 46,
                        member: sp.vip,
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
                style: TextStyle(fontSize: 12, color: AppTheme.textTertiary)),
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
          // 个性签名
          TextField(
            controller: _bioCtrl,
            maxLength: 50,
            maxLines: 2,
            decoration: InputDecoration(
              labelText: '个性签名',
              hintText: '一句话介绍自己，最多 50 个字',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.edit_note),
              suffixIcon: IconButton(
                icon: const Icon(Icons.emoji_emotions_outlined,
                    size: 20, color: AppTheme.textSecondary),
                tooltip: '表情',
                onPressed: () => showEmojiSheet(context, _bioCtrl),
              ),
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
