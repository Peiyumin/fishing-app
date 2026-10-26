import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../app_theme.dart';
import '../widgets/emoji_panel.dart';
import '../models/fishing_species.dart';
import '../models/post.dart';
import '../services/api_client.dart';
import '../services/api_config.dart';
import '../services/location_service.dart';
import '../services/post_service.dart';
import '../services/refresh_bus.dart';
import '../services/session_provider.dart';
import '../utils/geo_names.dart';
import '../widgets/center_toast.dart';
import '../widgets/location_prompt.dart';
import 'auth_screen.dart';
import 'watermark_camera_screen.dart';

/// 渔获发布页
///  - 进入即自动定位，可开关「是否公开钓点位置」
///  - 照片/视频走「钓鱼打卡」水印相机（时间·天气·温度·气压·位置）
///  - 钓到了什么：多鱼种 + 尾数
///  - 配色沿用 App 品牌绿（不用参考图的金色）
class PublishCatchScreen extends StatefulWidget {
  /// 传入则为「编辑模式」，预填该动态内容；不传为「发布模式」
  final Post? existing;

  const PublishCatchScreen({super.key, this.existing});

  @override
  State<PublishCatchScreen> createState() => _PublishCatchScreenState();
}

class _PublishCatchScreenState extends State<PublishCatchScreen> {
  final _storyCtrl = TextEditingController();

  final List<String> _images = [];
  final List<String> _existingImages = []; // 编辑模式下已有的网络图片
  String? _video;
  bool _editMode = false;

  String? _placeLabel; // 「许昌·禹州市」
  String? _placeDetail; // 「河南省许昌市禹州市…」
  double? _lat;
  double? _lng;
  bool _locating = true;
  bool _locPublic = true; // 钓点位置是否公开

  final List<_CatchItem> _catches = [];
  bool _submitting = false;

  static const int _maxMedia = 5;
  static const int _maxStory = 3000;
  final _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    final ex = widget.existing;
    if (ex != null) {
      // 编辑模式：预填内容，不再自动定位（保留原发布位置）
      _editMode = true;
      _storyCtrl.text = ex.body ?? '';
      _existingImages.addAll(ex.imageUrls);
      _locPublic = ex.locPublic;
      for (final f in ex.fish) {
        final name = (f['name'] ?? '').toString().trim();
        if (name.isEmpty) continue;
        final c = _CatchItem(name);
        c.count = (f['count'] as num?)?.toInt() ?? 1;
        _catches.add(c);
      }
      _lat = ex.lat;
      _lng = ex.lng;
      _placeLabel = ex.locationName;
      _locating = false;
    } else {
      // 首帧后再拿定位：iOS 在首帧前弹权限框会被系统丢掉
      WidgetsBinding.instance.addPostFrameCallback((_) => _locate());
    }
  }

  @override
  void dispose() {
    _storyCtrl.dispose();
    super.dispose();
  }

  /// 自动定位 + 逆地编码（失败时降级为坐标，不影响发布）
  Future<void> _locate({bool silent = false}) async {
    setState(() => _locating = true);
    try {
      final pos = await LocationService.determinePosition();
      final short = await GeoNames.nameForPosition(pos.latitude, pos.longitude);
      Map<String, dynamic>? rev;
      try {
        rev = await GeoNames.reverse(pos.latitude, pos.longitude);
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _lat = pos.latitude;
        _lng = pos.longitude;
        _placeLabel = short;
        _placeDetail = (rev?['display'] as String?)?.trim();
        _locating = false;
      });
      if (!silent) {
        CenterToast.show(context, '已获取当前位置', icon: Icons.location_on);
      }
    } on LocationException catch (e) {
      if (mounted) setState(() => _locating = false);
      if (mounted) LocationPrompt.showError(context, e);
    } catch (_) {
      if (mounted) setState(() => _locating = false);
    }
  }

  // ───────────────────────── 媒体 ─────────────────────────

  Future<void> _takeWatermarkPhoto() async {
    if (_video != null) {
      CenterToast.show(context, '已选择视频，请先移除视频再加照片');
      return;
    }
    if (_images.length >= _maxMedia) {
      CenterToast.show(context, '最多只能添加 $_maxMedia 张');
      return;
    }
    final path = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => const WatermarkCameraScreen(
          returnResult: true,
          title: '记渔获',
        ),
      ),
    );
    if (!mounted || path == null || path.isEmpty) return;
    // 相机页长按录像是「视频」，要落到视频位（与照片互斥）
    final lower = path.toLowerCase();
    if (lower.endsWith('.mp4') || lower.endsWith('.mov')) {
      final hadPhotos = _images.isNotEmpty;
      setState(() {
        _video = path;
        _images.clear();
      });
      if (hadPhotos && mounted) {
        CenterToast.show(context, '已换成视频，之前的照片已移除（照片与视频不能混发）');
      }
      return;
    }
    setState(() => _images.add(path));
  }

  Future<void> _pickGallery() async {
    if (_video != null) {
      CenterToast.show(context, '已选择视频，请先移除视频再加照片');
      return;
    }
    final remain = _maxMedia - _images.length;
    if (remain <= 0) {
      CenterToast.show(context, '最多只能添加 $_maxMedia 张');
      return;
    }
    final picked =
        await _picker.pickMultiImage(maxWidth: 1600, limit: remain);
    if (!mounted) return;
    if (picked.isNotEmpty) {
      setState(() => _images.addAll(picked.map((x) => x.path)));
    }
  }

  Future<void> _pickVideo() async {
    if (_images.isNotEmpty) {
      CenterToast.show(context, '已添加照片，请先清空照片再选视频');
      return;
    }
    final x = await _picker.pickVideo(source: ImageSource.gallery);
    if (!mounted || x == null) return;
    try {
      final size = await File(x.path).length();
      if (size > 60 * 1024 * 1024) {
        if (mounted) CenterToast.show(context, '视频不能超过 60MB，请压缩后再选');
        return;
      }
    } catch (_) {}
    setState(() => _video = x.path);
  }

  void _openMediaSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined,
                  color: AppTheme.primary),
              title: const Text('拍照（带天气水印）'),
              subtitle: const Text('自动叠加时间·天气·温度·气压·钓点'),
              onTap: () {
                Navigator.pop(context);
                _takeWatermarkPhoto();
              },
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined,
                  color: AppTheme.primary),
              title: const Text('从相册选择'),
              subtitle: const Text('一次最多选 5 张'),
              onTap: () {
                Navigator.pop(context);
                _pickGallery();
              },
            ),
            if (!_editMode) ...[
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.videocam_outlined,
                    color: AppTheme.star),
                title: const Text('选择视频'),
                subtitle: const Text('单个 ≤60MB，与照片二选一'),
                onTap: () {
                  Navigator.pop(context);
                  _pickVideo();
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ───────────────────────── 鱼种 ─────────────────────────

  void _openSpeciesSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.62,
        maxChildSize: 0.92,
        builder: (_, ctrl) => ListView(
          controller: ctrl,
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
          children: [
            Row(
              children: [
                const Text('选择鱼种',
                    style: TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textPrimary)),
                const Spacer(),
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: const Icon(Icons.close,
                      size: 18, color: AppTheme.textSecondary),
                ),
              ],
            ),
            const SizedBox(height: 4),
            const Text('按钓法分类，点一下即加入本次渔获',
                style:
                    TextStyle(fontSize: 11.5, color: AppTheme.textSecondary)),
            const SizedBox(height: 12),
            for (final mode in FishingMode.all) ...[
              Padding(
                padding: const EdgeInsets.only(top: 6, bottom: 8),
                child: Row(
                  children: [
                    Container(
                      width: 3,
                      height: 13,
                      decoration: BoxDecoration(
                        color: AppTheme.primary,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(mode.name,
                        style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.primary)),
                  ],
                ),
              ),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: FishingSpecies.forMode(mode.name)
                    .map((s) => _speciesChip(s.name))
                    .toList(),
              ),
              const SizedBox(height: 8),
            ],
          ],
        ),
      ),
    );
  }

  Widget _speciesChip(String name) {
    final picked = _catches.any((c) => c.species == name);
    return GestureDetector(
      onTap: () {
        setState(() {
          final i = _catches.indexWhere((c) => c.species == name);
          if (i >= 0) {
            _catches[i].count += 1;
          } else {
            _catches.add(_CatchItem(name));
          }
        });
        Navigator.pop(context);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
        decoration: BoxDecoration(
          color: picked ? AppTheme.primaryLight : AppTheme.primarySoft,
          borderRadius: BorderRadius.circular(9),
          border: Border.all(
              color: picked ? AppTheme.primary : AppTheme.border),
        ),
        child: Text(name,
            style: TextStyle(
                fontSize: 12.5,
                color: picked ? AppTheme.primary : AppTheme.textSecondary,
                fontWeight: picked ? FontWeight.w600 : FontWeight.normal)),
      ),
    );
  }

  // ───────────────────────── 发布 ─────────────────────────

  String get _autoTitle {
    if (_catches.isEmpty) return '渔获分享';
    return _catches.map((c) => '${c.species}×${c.count}').join(' · ');
  }

  Future<void> _submit() async {
    final sp = Provider.of<SessionProvider>(context, listen: false);
    if (ApiConfig.enabled && !sp.isLoggedIn) {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const AuthScreen()),
      );
      return;
    }
    final story = _storyCtrl.text.trim();
    if (!_editMode && _images.isEmpty && _video == null) {
      CenterToast.show(context, '至少添加一张渔获照片或视频');
      return;
    }
    if (story.isEmpty && _catches.isEmpty) {
      CenterToast.show(context, '写点渔获故事或选择钓到的鱼');
      return;
    }
    setState(() => _submitting = true);
    try {
      if (_editMode) {
        // 编辑：本地新图上传后，与已有网络图合并；视频字段由后端保留原值
        final uploaded = _images.isEmpty
            ? <String>[]
            : await ApiClient.uploadImages(_images, watermark: true);
        final images = [..._existingImages, ...uploaded];
        await PostService.updatePost(
          widget.existing!.id,
          content: story.isEmpty ? null : story,
          images: images,
          locPublic: _locPublic,
          fish: _catches
              .map((c) => {'name': c.species, 'count': c.count})
              .toList(growable: false),
        );
        if (mounted) {
          RefreshBus.bumpFeed();
          CenterToast.show(context, '已保存', icon: Icons.check_circle_outline);
          Navigator.of(context).pop(true);
        }
      } else {
        await PostService.publish(
          title: _autoTitle,
          body: story.isEmpty ? null : story,
          imageFiles: _video == null ? _images : const [],
          videoFile: _video,
          category: 'post',
          locationName: _locPublic ? _placeLabel : null,
          lat: _locPublic ? _lat : null,
          lng: _locPublic ? _lng : null,
          locPublic: _locPublic,
          fish: _catches
              .map((c) => {'name': c.species, 'count': c.count})
              .toList(growable: false),
          city: await GeoNames.currentCity() ?? '',
          // 渔获照片上传时让后端叠加品牌水印（位置/大小/透明图由后台「图片水印」控制）
          markWatermark: true,
        );
        if (mounted) {
          RefreshBus.bumpFeed();
          CenterToast.show(context, '发布成功', icon: Icons.check_circle_outline);
          Navigator.of(context).pop(true);
        }
      }
    } catch (e) {
      if (mounted) {
        CenterToast.show(context, _editMode ? '保存失败：$e' : '发布失败：$e');
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _showPrivacy() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('隐私规范'),
        content: const SingleChildScrollView(
          child: Text(
            '1. 钓点位置默认公开，关闭后其他人看不到你发布的具体钓点与坐标；\n'
            '2. 照片上的时间、天气、气压等信息由打卡相机生成，仅用于展示渔获现场；\n'
            '3. 请勿发布涉及他人隐私、禁钓区或保护鱼种的内容；\n'
            '4. 违规内容管理员有权删除并封禁账号。',
            style: TextStyle(fontSize: 13, height: 1.6),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
  }

  // ───────────────────────── UI ─────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_editMode ? '编辑渔获' : '发布渔获'),
        actions: [
          TextButton(
            onPressed: _showPrivacy,
            child: const Text('隐私规范',
                style: TextStyle(color: Colors.white, fontSize: 13)),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 24),
        children: [
          _locationCard(),
          const SizedBox(height: 12),
          _mediaCard(),
          const SizedBox(height: 12),
          _storyCard(),
          const SizedBox(height: 12),
          _catchCard(),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 6, 14, 10),
          child: SizedBox(
            height: 48,
            child: ElevatedButton(
              onPressed: _submitting ? null : _submit,
              child: _submitting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Text('发布',
                      style: TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w700)),
            ),
          ),
        ),
      ),
    );
  }

  Widget _card({required Widget child}) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(AppTheme.radiusLg),
          border: Border.all(color: AppTheme.divider),
        ),
        child: child,
      );

  Widget _cardTitle(IconData icon, String title, {String? trailing}) => Row(
        children: [
          Icon(icon, size: 16, color: AppTheme.primary),
          const SizedBox(width: 6),
          Text(title,
              style: const TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textPrimary)),
          const Spacer(),
          if (trailing != null)
            Text(trailing,
                style: const TextStyle(
                    fontSize: 11.5, color: AppTheme.textSecondary)),
        ],
      );

  /// 钓点位置：自动定位 + 是否公开开关
  Widget _locationCard() {
    final hasPlace = _placeLabel != null && _placeLabel!.isNotEmpty;
    return _card(
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppTheme.primaryLight,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  _locating ? Icons.my_location : Icons.location_on,
                  size: 20,
                  color: AppTheme.primary,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Text('钓点位置',
                            style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: AppTheme.textPrimary)),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                            color: _locPublic
                                ? AppTheme.primaryLight
                                : const Color(0xFFEFEFEF),
                            borderRadius: BorderRadius.circular(5),
                          ),
                          child: Text(
                            _locPublic ? '公开' : '不公开',
                            style: TextStyle(
                                fontSize: 10,
                                color: _locPublic
                                    ? AppTheme.primary
                                    : AppTheme.textSecondary),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      _locating
                          ? '正在获取当前位置…'
                          : (hasPlace ? _placeLabel! : '未获取到定位，点右侧重试'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 12.5,
                          color: hasPlace
                              ? AppTheme.textPrimary
                              : AppTheme.textSecondary),
                    ),
                    if (!_locating && hasPlace && (_placeDetail ?? '').isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(_placeDetail!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 10.5,
                                color: AppTheme.textSecondary)),
                      ),
                  ],
                ),
              ),
              IconButton(
                onPressed: _locating ? null : () => _locate(),
                icon: const Icon(Icons.refresh, size: 18),
                color: AppTheme.primary,
                tooltip: '重新定位',
              ),
            ],
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 6),
            child: Divider(height: 1, color: AppTheme.divider),
          ),
          Row(
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('公开钓点位置',
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.textPrimary)),
                    SizedBox(height: 2),
                    Text('关闭后其他钓友看不到具体钓点，只显示「已隐藏」',
                        style: TextStyle(
                            fontSize: 10.5, color: AppTheme.textSecondary)),
                  ],
                ),
              ),
              Switch(
                value: _locPublic,
                activeColor: AppTheme.primary,
                onChanged: (v) => setState(() => _locPublic = v),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 渔获照片 / 视频
  Widget _mediaCard() {
    final total = _images.length + _existingImages.length;
    final count = _video != null ? 1 : total;
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _cardTitle(Icons.photo_camera_outlined, '渔获照片/视频',
              trailing: '$count/$_maxMedia'),
          const SizedBox(height: 10),
          if (_video != null)
            Stack(
              children: [
                Container(
                  height: 120,
                  width: 120,
                  decoration: BoxDecoration(
                    color: Colors.black,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.videocam, color: Colors.white, size: 30),
                      SizedBox(height: 6),
                      Text('已选择视频',
                          style:
                              TextStyle(color: Colors.white70, fontSize: 11)),
                    ],
                  ),
                ),
                Positioned(
                  right: 0,
                  top: 0,
                  child: GestureDetector(
                    onTap: () => setState(() => _video = null),
                    child: const CircleAvatar(
                      radius: 11,
                      backgroundColor: Colors.black54,
                      child:
                          Icon(Icons.close, size: 14, color: Colors.white),
                    ),
                  ),
                ),
              ],
            )
          else if (total == 0)
            InkWell(
              onTap: _openMediaSheet,
              borderRadius: BorderRadius.circular(12),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 26),
                decoration: BoxDecoration(
                  color: AppTheme.primarySoft,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: AppTheme.primaryBorder, style: BorderStyle.solid),
                ),
                child: const Column(
                  children: [
                    Icon(Icons.add_a_photo_outlined,
                        size: 28, color: AppTheme.primary),
                    SizedBox(height: 8),
                    Text('添加渔获照片',
                        style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.textPrimary)),
                    SizedBox(height: 3),
                    Text('拍摄时自动叠加时间·天气·温度·气压',
                        style: TextStyle(
                            fontSize: 11, color: AppTheme.textSecondary)),
                  ],
                ),
              ),
            )
          else
            GridView.count(
              crossAxisCount: 3,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              children: [
                ..._existingImages.asMap().entries.map((e) {
                  final url = e.value;
                  return Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: CachedNetworkImage(
                          imageUrl: url,
                          width: double.infinity,
                          height: double.infinity,
                          fit: BoxFit.cover,
                          fadeInDuration: const Duration(milliseconds: 180),
                          placeholder: (_, __) => Container(
                            color: AppTheme.primarySoft,
                            alignment: Alignment.center,
                            child: const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                  strokeWidth: 1.6,
                                  color: AppTheme.primaryBorder),
                            ),
                          ),
                          errorWidget: (_, __, ___) => Container(
                            color: AppTheme.primarySoft,
                            alignment: Alignment.center,
                            child: const Icon(Icons.broken_image_outlined,
                                size: 20, color: AppTheme.textSecondary),
                          ),
                        ),
                      ),
                      Positioned(
                        right: 0,
                        top: 0,
                        child: GestureDetector(
                          onTap: () =>
                              setState(() => _existingImages.remove(url)),
                          child: const CircleAvatar(
                            radius: 11,
                            backgroundColor: Colors.black54,
                            child: Icon(Icons.close,
                                size: 14, color: Colors.white),
                          ),
                        ),
                      ),
                    ],
                  );
                }),
                ..._images.asMap().entries.map((e) {
                  final p = e.value;
                  return Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.file(File(p),
                            width: double.infinity,
                            height: double.infinity,
                            fit: BoxFit.cover),
                      ),
                      Positioned(
                        right: 0,
                        top: 0,
                        child: GestureDetector(
                          onTap: () => setState(() => _images.remove(p)),
                          child: const CircleAvatar(
                            radius: 11,
                            backgroundColor: Colors.black54,
                            child: Icon(Icons.close,
                                size: 14, color: Colors.white),
                          ),
                        ),
                      ),
                    ],
                  );
                }),
                if (total < _maxMedia)
                  InkWell(
                    onTap: _openMediaSheet,
                    child: Container(
                      decoration: BoxDecoration(
                        color: AppTheme.primarySoft,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppTheme.primaryBorder),
                      ),
                      child: const Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.add, color: AppTheme.primary, size: 22),
                          SizedBox(height: 2),
                          Text('添加',
                              style: TextStyle(
                                  fontSize: 10, color: AppTheme.primary)),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          const SizedBox(height: 8),
          Text(_video != null
              ? '视频只能 1 个（≤60MB）'
              : '照片最多 5 张；视频只能 1 个（≤60MB），二者不能混发',
              style:
                  TextStyle(fontSize: 10.5, color: AppTheme.textSecondary)),
        ],
      ),
    );
  }

  /// 渔获故事
  Widget _storyCard() {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _cardTitle(Icons.edit_outlined, '渔获故事',
              trailing: '${_storyCtrl.text.length}/$_maxStory'),
          const SizedBox(height: 10),
          TextField(
            controller: _storyCtrl,
            maxLines: 5,
            maxLength: _maxStory,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: '分享钓法、饵料、当时的鱼情与环境\n优质内容更容易被推荐哦～',
              hintStyle:
                  TextStyle(fontSize: 12.5, color: AppTheme.textSecondary),
              counterText: '',
              fillColor: AppTheme.primarySoft,
              suffixIcon: IconButton(
                icon: const Icon(Icons.emoji_emotions_outlined,
                    size: 20, color: AppTheme.textSecondary),
                tooltip: '表情',
                onPressed: () => showEmojiSheet(context, _storyCtrl),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 钓到了什么
  Widget _catchCard() {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _cardTitle(Icons.phishing, '钓到了什么',
              trailing: _catches.isEmpty ? null : '${_catches.length} 种'),
          const SizedBox(height: 10),
          if (_catches.isEmpty)
            const Padding(
              padding: EdgeInsets.only(bottom: 10),
              child: Text('还没选鱼种，点下面按钮添加',
                  style: TextStyle(
                      fontSize: 11.5, color: AppTheme.textSecondary)),
            )
          else
            ..._catches.map((c) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppTheme.primarySoft,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppTheme.divider),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.set_meal,
                            size: 16, color: AppTheme.primary),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(c.species,
                              style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: AppTheme.textPrimary)),
                        ),
                        _stepBtn(Icons.remove, () {
                          setState(() {
                            if (c.count > 1) c.count -= 1;
                          });
                        }),
                        SizedBox(
                          width: 30,
                          child: Text('${c.count}',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                  fontSize: 13, fontWeight: FontWeight.w700)),
                        ),
                        _stepBtn(Icons.add, () {
                          setState(() => c.count += 1);
                        }),
                        const SizedBox(width: 6),
                        GestureDetector(
                          onTap: () =>
                              setState(() => _catches.remove(c)),
                          child: const Icon(Icons.close,
                              size: 16, color: AppTheme.textSecondary),
                        ),
                      ],
                    ),
                  ),
                )),
          const SizedBox(height: 2),
          InkWell(
            onTap: _openSpeciesSheet,
            borderRadius: BorderRadius.circular(10),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 11),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppTheme.primaryBorder),
                color: AppTheme.surface,
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.add, size: 16, color: AppTheme.primary),
                  SizedBox(width: 4),
                  Text('再加一种鱼',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.primary)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          const Text('按钓法分了台钓 / 路亚 / 海钓三组目标鱼，选错组别也能在列表里找到',
              style:
                  TextStyle(fontSize: 10.5, color: AppTheme.textSecondary)),
        ],
      ),
    );
  }

  Widget _stepBtn(IconData icon, VoidCallback onTap) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          width: 24,
          height: 24,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: AppTheme.border),
          ),
          child: Icon(icon, size: 14, color: AppTheme.textSecondary),
        ),
      );
}

/// 本次渔获单条：鱼种 + 尾数
class _CatchItem {
  final String species;
  int count = 1;
  _CatchItem(this.species);
}
