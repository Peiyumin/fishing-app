import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../app_theme.dart';
import '../models/official.dart';
import '../services/api_client.dart';
import '../services/official_service.dart';
import '../widgets/center_toast.dart';

/// 写 / 改一条公告（官方工作台 - 发布公告）
///
/// 为什么单开一页而不是弹个输入框：公告是「平台对全体用户说话」，
/// 字数多、要改错别字、要配图、要置顶，挤在一个小弹窗里很容易发出去才发现写错。
///
/// v41 起公告的归宿变了：它不再是帖子，不会出现在首页「钓友动态」和「发现」里，
/// 而是进「消息 → 系统通知」，以官方头像 + 「官方公告」标签的样子出现。
/// 所以这一页除了标题正文，还多了「插入图片」（最多 9 张）。
class NoticeEditorScreen extends StatefulWidget {
  /// 传入 = 编辑这条；null = 新建
  final OfficialNotice? notice;

  const NoticeEditorScreen({super.key, this.notice});

  @override
  State<NoticeEditorScreen> createState() => _NoticeEditorScreenState();
}

/// 编辑器里的一张图：可能是刚选的本地文件，也可能是上次就传好的远程地址
class _DraftImage {
  final String path;
  final bool local; // true = 本机文件，提交前要上传
  _DraftImage(this.path, {required this.local});
}

/// 是不是已经在服务器上的图片地址
bool _isRemote(String p) =>
    p.startsWith('http://') || p.startsWith('https://');

class _NoticeEditorScreenState extends State<NoticeEditorScreen> {
  late final TextEditingController _title;
  late final TextEditingController _body;
  late bool _pinned;
  late final List<_DraftImage> _images;
  bool _saving = false;

  final _picker = ImagePicker();

  static const int _titleMax = 60;
  static const int _bodyMax = 5000;
  static const int _imageMax = 9;

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: widget.notice?.title ?? '');
    _body = TextEditingController(text: widget.notice?.content ?? '');
    _pinned = widget.notice?.pinned ?? true;
    _images = (widget.notice?.images ?? const <String>[])
        // 只有 http(s) 才算「已经在服务器上」；其余当本机文件处理。
        // 后端返回的一律是绝对 URL，所以这个判断不会误伤正常数据，
        // 但能挡住「传进来一个本地路径却去发网络请求」的怪状况。
        .map((u) => _DraftImage(u, local: !_isRemote(u)))
        .toList();
  }

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  /// 相册多选（一次最多补到 9 张）
  Future<void> _pickImages() async {
    final remain = _imageMax - _images.length;
    if (remain <= 0) {
      CenterToast.show(context, '最多 $_imageMax 张图片');
      return;
    }
    try {
      final picked = await _picker.pickMultiImage(maxWidth: 1440, limit: remain);
      if (picked.isEmpty) return;
      setState(() {
        for (final x in picked) {
          if (_images.length >= _imageMax) break;
          _images.add(_DraftImage(x.path, local: true));
        }
      });
    } catch (e) {
      if (mounted) CenterToast.show(context, '选图失败，请检查相册权限');
    }
  }

  /// 拍照追加一张
  Future<void> _takePhoto() async {
    if (_images.length >= _imageMax) {
      CenterToast.show(context, '最多 $_imageMax 张图片');
      return;
    }
    try {
      final x = await _picker.pickImage(
          source: ImageSource.camera, maxWidth: 1440);
      if (x == null) return;
      setState(() => _images.add(_DraftImage(x.path, local: true)));
    } catch (e) {
      if (mounted) CenterToast.show(context, '拍照失败，请检查相机权限');
    }
  }

  Future<void> _submit() async {
    final title = _title.text.trim();
    final body = _body.text.trim();
    if (title.isEmpty) {
      CenterToast.show(context, '请填写公告标题', icon: Icons.edit_outlined);
      return;
    }
    if (body.isEmpty) {
      CenterToast.show(context, '请填写公告内容', icon: Icons.edit_outlined);
      return;
    }
    setState(() => _saving = true);
    try {
      // 先把本机图片传上去，再把「远程 + 新上传」按原顺序拼成最终列表。
      // 顺序很重要：公告里配图是有上下文的（比如先截图后说明），
      // 之前直接 addAll 到末尾会把新图排到最后，用户看着莫名其妙。
      final locals = _images.where((e) => e.local).map((e) => e.path).toList();
      List<String> uploaded = const [];
      if (locals.isNotEmpty) {
        uploaded = await ApiClient.uploadImages(locals, watermark: true);
        if (uploaded.length != locals.length) {
          throw const ApiException('图片上传没有全部成功，请重试');
        }
      }
      var cursor = 0;
      final finalUrls = <String>[];
      for (final img in _images) {
        if (img.local) {
          finalUrls.add(uploaded[cursor++]);
        } else {
          finalUrls.add(img.path);
        }
      }

      await OfficialService.saveNotice(
        id: widget.notice?.id ?? '',
        title: title,
        content: body,
        images: finalUrls,
        pinned: _pinned,
      );
      if (!mounted) return;
      CenterToast.show(context, widget.notice == null ? '公告已发布' : '公告已更新',
          icon: Icons.check_circle_outline);
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      final net = ApiClient.asNetError(e);
      final msg = net != null
          ? '网络不太好，请稍后再试'
          : (e is ApiException ? e.message : '发布失败：$e');
      CenterToast.show(context, msg);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.notice != null;
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: Text(editing ? '编辑公告' : '发布公告'),
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(14, 6, 14, 10),
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(AppTheme.radiusMd),
              boxShadow: AppTheme.lightShadow,
            ),
            child: Column(
              children: [
                TextField(
                  controller: _title,
                  maxLength: _titleMax,
                  textInputAction: TextInputAction.next,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                  decoration: const InputDecoration(
                    hintText: '标题，例如：渔报已完成升级，恢复使用',
                    border: InputBorder.none,
                    counterStyle: TextStyle(fontSize: 10.5, color: AppTheme.textTertiary),
                  ),
                ),
                const Divider(height: 1, color: AppTheme.divider),
                TextField(
                  controller: _body,
                  maxLength: _bodyMax,
                  maxLines: null,
                  minLines: 8,
                  keyboardType: TextInputType.multiline,
                  style: const TextStyle(fontSize: 13.5, height: 1.6),
                  decoration: const InputDecoration(
                    hintText: '正文。建议说清三件事：发生了什么、现在能不能正常用、有问题找谁。',
                    border: InputBorder.none,
                    counterStyle: TextStyle(fontSize: 10.5, color: AppTheme.textTertiary),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          _imageCard(),
          const SizedBox(height: 10),
          Container(
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(AppTheme.radiusMd),
              boxShadow: AppTheme.lightShadow,
            ),
            child: SwitchListTile(
              value: _pinned,
              onChanged: (v) => setState(() => _pinned = v),
              activeColor: AppTheme.accent,
              activeTrackColor: AppTheme.accent.withOpacity(0.45),
              title: const Text('置顶',
                  style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
              subtitle: const Text('置顶的公告排在系统通知最前面，适合「恢复使用」这类必须看到的',
                  style: TextStyle(fontSize: 11, color: AppTheme.textSecondary)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 14),
            ),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.starLight,
              borderRadius: BorderRadius.circular(AppTheme.radiusMd),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline, size: 16, color: AppTheme.starDark),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '公告不进首页「钓友动态」，也不会出现在「发现」里 —— 它会以「官方公告」的形式'
                    '躺在用户的「消息 → 系统通知」中，带头像、标题、配图和日期。'
                    '写错了可以随时回来改，改完内容立刻生效。',
                    style: TextStyle(fontSize: 11.5, color: AppTheme.starDark, height: 1.5),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
          child: SizedBox(
            height: 46,
            child: ElevatedButton(
              onPressed: _saving ? null : _submit,
              child: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : Text(editing ? '保存修改' : '立即发布'),
            ),
          ),
        ),
      ),
    );
  }

  /// 配图区：3 列宫格 + 一个「添加」方块
  Widget _imageCard() {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        boxShadow: AppTheme.lightShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('配图',
                  style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
              const SizedBox(width: 6),
              Text('${_images.length}/$_imageMax',
                  style: const TextStyle(fontSize: 11, color: AppTheme.textTertiary)),
              const Spacer(),
              TextButton.icon(
                onPressed: _images.length >= _imageMax ? null : _pickImages,
                icon: const Icon(Icons.add_photo_alternate_outlined, size: 17),
                label: const Text('从相册选', style: TextStyle(fontSize: 12)),
                style: TextButton.styleFrom(
                  foregroundColor: AppTheme.primary,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: const Size(0, 30),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          GridView.count(
            crossAxisCount: 3,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            children: [
              for (var i = 0; i < _images.length; i++) _thumb(i),
              if (_images.length < _imageMax) _addTile(),
            ],
          ),
          const SizedBox(height: 6),
          const Text('最多 9 张。用户点开公告后，图片按这个顺序排在正文下面。',
              style: TextStyle(fontSize: 10.5, color: AppTheme.textTertiary)),
        ],
      ),
    );
  }

  Widget _thumb(int index) {
    final img = _images[index];
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (img.local)
            Image.file(File(img.path), fit: BoxFit.cover)
          else
            CachedNetworkImage(
              imageUrl: img.path,
              fit: BoxFit.cover,
              placeholder: (_, __) => Container(color: AppTheme.divider),
              errorWidget: (_, __, ___) => Container(
                color: AppTheme.divider,
                alignment: Alignment.center,
                child: const Icon(Icons.broken_image_outlined,
                    size: 20, color: AppTheme.textTertiary),
              ),
            ),
          Positioned(
            top: 2,
            right: 2,
            child: GestureDetector(
              onTap: () => setState(() => _images.removeAt(index)),
              child: Container(
                width: 20,
                height: 20,
                decoration: const BoxDecoration(
                  color: Colors.black54,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: const Icon(Icons.close, size: 13, color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _addTile() {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: _showAddSheet,
        child: Ink(
          decoration: BoxDecoration(
            color: AppTheme.background,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppTheme.border),
          ),
          child: const Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.add, size: 22, color: AppTheme.textTertiary),
              SizedBox(height: 2),
              Text('添加图片',
                  style: TextStyle(fontSize: 10.5, color: AppTheme.textTertiary)),
            ],
          ),
        ),
      ),
    );
  }

  void _showAddSheet() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined,
                  color: AppTheme.primary),
              title: const Text('从相册选择'),
              onTap: () {
                Navigator.of(ctx).pop();
                _pickImages();
              },
            ),
            ListTile(
              leading:
                  const Icon(Icons.photo_camera_outlined, color: AppTheme.primary),
              title: const Text('拍照'),
              onTap: () {
                Navigator.of(ctx).pop();
                _takePhoto();
              },
            ),
          ],
        ),
      ),
    );
  }
}
