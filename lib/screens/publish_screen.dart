import 'dart:io';

import 'package:flutter/material.dart';

import '../app_theme.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../services/location_service.dart';
import '../services/post_service.dart';
import '../services/refresh_bus.dart';
import '../services/session_provider.dart';
import '../services/api_config.dart';
import '../utils/geo_names.dart';
import 'auth_screen.dart';
import '../widgets/center_toast.dart';
import '../widgets/location_prompt.dart';

/// 发布页：支持 5 种类别（渔获 / 问答 / 说说 / 出售二手 / 求购二手）
/// - 图片多选（最多 9 张），视频单选（与图片二选一）
/// - 二手类别额外展示价格输入
class PublishScreen extends StatefulWidget {
  /// post 渔获 / ask 问答 / say 说说 / sell 出售 / buy 求购
  final String category;

  /// 预置的本地图片路径（水印相机「用这张发动态」带图进入）
  final String? initialImage;

  const PublishScreen({super.key, this.category = 'post', this.initialImage});

  @override
  State<PublishScreen> createState() => _PublishScreenState();
}

class _PublishScreenState extends State<PublishScreen> {
  final _titleCtrl = TextEditingController();
  final _bodyCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();
  final List<String> _images = []; // 本地图片路径（多选，最多 9 张）
  String? _video; // 本地视频路径（单选，与图片二选一）
  String? _locationName;
  double? _lat;
  double? _lng;
  bool _submitting = false;

  static const int _maxImages = 9;
  final _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    // 水印相机带图进入：预置第一张图
    final init = widget.initialImage;
    if (init != null && init.isNotEmpty && File(init).existsSync()) {
      _images.add(init);
    }
  }

  String get _category => widget.category;

  String get _pageTitle {
    switch (_category) {
      case 'ask':
        return '钓鱼问答';
      case 'say':
        return '随便说说';
      case 'sell':
        return '出售二手';
      case 'buy':
        return '求购二手';
      default:
        return '发布渔获';
    }
  }

  String get _titleHint {
    switch (_category) {
      case 'ask':
        return '例如：冬季野钓鲫鱼用什么饵？';
      case 'say':
        return '说点什么…';
      case 'sell':
        return '例如：9成新 达亿瓦黑蜘蛛水滴轮';
      case 'buy':
        return '例如：求购一把 5.4 米综合竿';
      default:
        return '今天爆护！XX钓点收获 XX';
    }
  }

  String get _bodyHint {
    switch (_category) {
      case 'ask':
        return '描述你的问题：鱼情、天气、已尝试的方法…';
      case 'say':
        return '分享此刻心情、钓后感…';
      case 'sell':
        return '成色、购买时间、配件、交易方式…';
      case 'buy':
        return '需求描述：型号、长度、预算、成色要求…';
      default:
        return '分享一下鱼情、饵料、钓法…';
    }
  }

  /// 相册多选图片（最多 9 张；与视频互斥）
  Future<void> _pickMultiImage() async {
    if (_video != null) {
      CenterToast.show(context, '已选择视频，请先移除视频再选图片');
      return;
    }
    final remain = _maxImages - _images.length;
    if (remain <= 0) {
      CenterToast.show(context, '最多只能选择 9 张图片');
      return;
    }
    final picked = await _picker.pickMultiImage(
        maxWidth: 1080, limit: remain);
    if (picked.isNotEmpty) {
      setState(() => _images.addAll(picked.map((x) => x.path)));
    }
  }

  /// 拍照（单张追加）
  Future<void> _takePhoto() async {
    if (_video != null) {
      CenterToast.show(context, '已选择视频，请先移除视频再选图片');
      return;
    }
    if (_images.length >= _maxImages) {
      CenterToast.show(context, '最多只能选择 9 张图片');
      return;
    }
    final x = await _picker.pickImage(source: ImageSource.camera, maxWidth: 1080);
    if (x != null) setState(() => _images.add(x.path));
  }

  /// 选择视频（仅相册；单选，与图片互斥，≤60MB）
  Future<void> _pickVideo() async {
    if (_images.isNotEmpty) {
      CenterToast.show(context, '已选择图片，请先清空图片再选视频');
      return;
    }
    final x = await _picker.pickVideo(source: ImageSource.gallery);
    if (x == null) return;
    try {
      final size = await File(x.path).length();
      if (size > 60 * 1024 * 1024) {
        if (mounted) {
          CenterToast.show(context, '视频不能超过 60MB，请压缩后再选');
        }
        return;
      }
    } catch (_) {/* 取大小失败时继续尝试上传，由后端校验*/}
    setState(() => _video = x.path);
  }

  Future<void> _getLocation() async {
    try {
      final pos = await LocationService.determinePosition();
      setState(() {
        _lat = pos.latitude;
        _lng = pos.longitude;
      });
      // 逆地编码成中文地名（先显示坐标，拿到城市名后替换）
      final name = await GeoNames.nameForPosition(pos.latitude, pos.longitude);
      if (!mounted) return;
      setState(() => _locationName = name);
    } on LocationException catch (e) {
      LocationPrompt.showError(context, e);
    } catch (_) {
      // 逆地编码失败：退回坐标，至少位置信息不丢
      if (!mounted) return;
      final pos = await LocationService.determinePosition();
      if (!mounted) return;
      setState(() {
        _lat = pos.latitude;
        _lng = pos.longitude;
        _locationName =
            '${pos.latitude.toStringAsFixed(3)}, ${pos.longitude.toStringAsFixed(3)}';
      });
    }
  }

  Future<void> _submit() async {
    final sp = Provider.of<SessionProvider>(context, listen: false);
    // 已配置后端时必须登录；演示模式（未配置）允许直接预览发布
    if (ApiConfig.enabled && !sp.isLoggedIn) {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const AuthScreen()),
      );
      return;
    }
    if (_titleCtrl.text.trim().isEmpty) {
      CenterToast.show(context, '请填写标题');
      return;
    }
    final price = _priceCtrl.text.trim();
    if ((_category == 'sell' || _category == 'buy') && price.isEmpty) {
      CenterToast.show(context, '请填写${_category == 'sell' ? '售价' : '预算'}');
      return;
    }
    setState(() => _submitting = true);
    try {
      await PostService.publish(
        title: _titleCtrl.text.trim(),
        body: _bodyCtrl.text.trim().isEmpty ? null : _bodyCtrl.text.trim(),
        imageFiles: _video == null ? _images : const [],
        videoFile: _video,
        category: _category,
        price: price,
        locationName: _locationName,
        lat: _lat,
        lng: _lng,
        city: await GeoNames.currentCity() ?? '', // 地级市（同城 Tab 依据）
      );
      if (mounted) {
      RefreshBus.bumpFeed();
        CenterToast.show(context, '发布成功', icon: Icons.check_circle_outline);
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        CenterToast.show(context, '发布失败：$e');
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _bodyCtrl.dispose();
    _priceCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isTrade = _category == 'sell' || _category == 'buy';
    return Scaffold(
      appBar: AppBar(
        title: Text(_pageTitle),
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // —— 内容卡片 ——
            Card(
              elevation: 1,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: _titleCtrl,
                      maxLength: 40,
                      decoration: InputDecoration(
                        labelText: '标题',
                        hintText: _titleHint,
                        border: const OutlineInputBorder(),
                        counterText: '',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _bodyCtrl,
                      maxLines: 4,
                      maxLength: 500,
                      decoration: InputDecoration(
                        labelText: '正文（选填）',
                        hintText: _bodyHint,
                        border: const OutlineInputBorder(),
                        counterText: '',
                      ),
                    ),
                    // 二手价格（仅出售/求购）
                    if (isTrade) ...[
                      const SizedBox(height: 12),
                      TextField(
                        controller: _priceCtrl,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: _category == 'sell' ? '售价（元）' : '预算（元）',
                          hintText: _category == 'sell' ? '例如：350' : '例如：500',
                          prefixText: '¥ ',
                          border: const OutlineInputBorder(),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            // —— 媒体卡片 ——
            Card(
              elevation: 1,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(_video != null ? '视频' : '图片',
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 15)),
                        const SizedBox(width: 8),
                        Text(
                          _video != null
                              ? '视频单选 · 与图片二选一'
                              : '最多 9 张 · ${_images.length}/$_maxImages',
                          style: const TextStyle(
                              fontSize: 11, color: Colors.grey),
                        ),
                        const Spacer(),
                        if (_images.isNotEmpty)
                          TextButton(
                            onPressed: () => setState(() => _images.clear()),
                            child: const Text('清空',
                                style: TextStyle(fontSize: 12)),
                          ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    if (_video != null)
                      // 已选视频预览（点击 × 移除后可改选图片）
                      Stack(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: Container(
                              width: 120,
                              height: 120,
                              color: Colors.black,
                              child: const Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.videocam,
                                      color: Colors.white, size: 34),
                                  SizedBox(height: 6),
                                  Text('已选择视频',
                                      style: TextStyle(
                                          color: Colors.white70, fontSize: 11)),
                                ],
                              ),
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
                                child: Icon(Icons.close,
                                    size: 14, color: Colors.white),
                              ),
                            ),
                          ),
                        ],
                      )
                    else
                      // 已选图片九宫格 + 添加按钮
                      GridView.count(
                        crossAxisCount: 3,
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        mainAxisSpacing: 8,
                        crossAxisSpacing: 8,
                        children: [
                          ..._images.asMap().entries.map((entry) {
                            final i = entry.key;
                            final p = entry.value;
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
                                  left: 4,
                                  bottom: 4,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 5, vertical: 1),
                                    decoration: BoxDecoration(
                                      color: Colors.black54,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text('${i + 1}',
                                        style: const TextStyle(
                                            color: Colors.white, fontSize: 10)),
                                  ),
                                ),
                                Positioned(
                                  right: 0,
                                  top: 0,
                                  child: GestureDetector(
                                    onTap: () =>
                                        setState(() => _images.remove(p)),
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
                          if (_images.length < _maxImages)
                            _mediaAddButton(),
                        ],
                      ),
                    const SizedBox(height: 8),
                    Text(
                      '图片一次最多选 9 张；视频只能选 1 个（≤60MB），二者不能混发',
                      style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            // —— 定位卡片 ——
            Card(
              elevation: 1,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
              child: ListTile(
                leading: const Icon(Icons.location_on,
                    color: AppTheme.accent),
                title: Text(_locationName ?? '添加定位（选填）',
                    style: TextStyle(
                        color: _locationName == null ? Colors.grey : null)),
                subtitle: const Text('发布后展示在动态卡片上',
                    style: TextStyle(fontSize: 11)),
                trailing: TextButton(
                  onPressed: _getLocation,
                  child: const Text('获取定位'),
                ),
              ),
            ),
            const SizedBox(height: 24),
            // —— 发布按钮 ——
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: _submitting ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: _submitting
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Text('发布',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 媒体添加按钮：弹出「选择视频 / 从相册选择 / 拍照」
  Widget _mediaAddButton() {
    return InkWell(
      onTap: () => showModalBottomSheet(
        context: context,
        builder: (_) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.videocam),
                title: const Text('选择视频'),
                subtitle: const Text('单个视频 ≤60MB，与图片二选一'),
                onTap: () {
                  Navigator.pop(context);
                  _pickVideo();
                },
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.photo_library),
                title: const Text('从相册选择'),
                subtitle: const Text('一次最多选 9 张'),
                onTap: () {
                  Navigator.pop(context);
                  _pickMultiImage();
                },
              ),
              ListTile(
                leading: const Icon(Icons.camera_alt),
                title: const Text('拍照'),
                onTap: () {
                  Navigator.pop(context);
                  _takePhoto();
                },
              ),
            ],
          ),
        ),
      ),
      child: Container(
        decoration: BoxDecoration(
          color: AppTheme.primarySoft,
          border: Border.all(color: AppTheme.primaryBorder),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.add, color: AppTheme.primary),
            SizedBox(height: 2),
            Text('添加',
                style:
                    TextStyle(fontSize: 10, color: AppTheme.primary)),
          ],
        ),
      ),
    );
  }
}
