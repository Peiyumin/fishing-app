import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import '../app_theme.dart';
import '../widgets/emoji_panel.dart';
import '../models/catch_weather.dart';
import '../models/fishing_species.dart';
import '../models/post.dart';
import '../models/weather_forecast.dart';
import '../services/api_client.dart';
import '../services/api_config.dart';
import '../services/app_settings.dart';
import '../services/fish_service.dart';
import '../services/location_service.dart';
import '../services/post_service.dart';
import '../services/refresh_bus.dart';
import '../services/session_provider.dart';
import '../services/weather_service.dart';
import '../utils/geo_names.dart';
import '../utils/image_data_uri.dart';
import '../utils/watermark_stamp.dart';
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
  // 钓点位置是否公开：默认值取自「设置 - 鱼获隐私」（用户可在这里单条改）
  bool _locPublic = AppSettings.instance.catchPrivacy;

  final List<_CatchItem> _catches = [];
  bool _submitting = false;

  /// 渔获尺寸：体长(cm) / 重量(g)。AI 视觉估算预填，用户可改。
  final TextEditingController _lengthCtrl = TextEditingController();
  final TextEditingController _weightCtrl = TextEditingController();

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
    _lengthCtrl.dispose();
    _weightCtrl.dispose();
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

  /// 抓一次「渔获时天气」：有钓点坐标就按钓点抓，没有就用当前定位的缓存包
  Future<CatchWeather?> _catchWeatherSnapshot() async {
    try {
      WeatherBundle? b;
      final lat = _lat, lng = _lng;
      if (lat != null && lng != null) {
        b = await WeatherService.fetchForecast(lat, lng);
      } else {
        b = await WeatherService.readCachedForecast();
      }
      if (b == null) return null;
      return CatchWeather.fromBundle(b, DateTime.now());
    } catch (_) {
      return null;
    }
  }

  /// 把「渔报 · 时间 · 天气 · 渔况 · 钓点」盖到照片**左上角**
  ///
  /// - 相机拍的照片已经盖过一次（临时文件名以 fishing_wm_ 开头），这里跳过，避免叠两层；
  /// - 从相册选的图也统一盖一次 —— 用户要求成片上必须有这些信息，且必须在左上角；
  /// - 任何一步失败都回退原图，绝不因为加水印挡住发布。
  Future<List<String>> _stampImages(List<String> paths, CatchWeather? wx) async {
    if (paths.isEmpty) return paths;
    final out = <String>[];
    final dir = await getTemporaryDirectory();
    for (final p0 in paths) {
      final name = p0.split(RegExp(r'[\\/]')).last;
      if (name.startsWith('fishing_wm_')) {
        out.add(p0);
        continue;
      }
      try {
        final lines = <WatermarkLine>[
          const WatermarkLine(
              '渔报 · 钓鱼打卡', 12.5, FontWeight.w600, Color(0xE6FFFFFF)),
          WatermarkLine(
              DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now()),
              26,
              FontWeight.w700,
              const Color(0xFFFFFFFF),
              4),
        ];
        if (wx != null) {
          lines.add(WatermarkLine(
            '${wx.description} ${wx.temp.round()}℃ · 湿度${wx.humidity}%'
            ' · ${windLevelText(wx.windSpeed, wx.windDir)}'
            ' · 气压${wx.pressure.round()}hPa',
            12.5,
            FontWeight.w500,
            const Color(0xEBFFFFFF),
          ));
          lines.add(WatermarkLine(
              '钓况${wx.score.round()} · ${wx.fishIndex}',
              12.5,
              FontWeight.w600,
              AppTheme.star));
        }
        final place = (_placeLabel ?? '').trim();
        if (place.isNotEmpty) {
          lines.add(WatermarkLine(place, 12.5, FontWeight.w500,
              const Color(0xDBFFFFFF)));
        }
        final bytes = await File(p0).readAsBytes();
        final png = await stampWatermarkPng(bytes, lines);
        final f = File('${dir.path}/fishing_wm_'
            '${DateTime.now().millisecondsSinceEpoch}_${out.length}.png');
        await f.writeAsBytes(png, flush: true);
        out.add(f.path);
      } catch (_) {
        out.add(p0);
      }
    }
    return out;
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

    // 渔获照片核验（AI 视觉）：发布前扫描首图是否为真实鱼获
    if (!_editMode && _images.isNotEmpty) {
      final passed = await _verifyCatchPhoto(_images.first);
      if (!passed) return; // 核验未通过（已提示），不发布
    }

    final lengthCm = double.tryParse(_lengthCtrl.text.trim());
    final weightG = double.tryParse(_weightCtrl.text.trim());

    // 天气快照 + 图片水印都用「发布这一刻」的这一份，保证成片、详情页、池塘三处口径一致
    final wx = await _catchWeatherSnapshot();

    setState(() => _submitting = true);
    try {
      if (_editMode) {
        // 编辑：本地新图上传后，与已有网络图合并；视频字段由后端保留原值
        final stamped = await _stampImages(_images, wx);
        final uploaded = stamped.isEmpty
            ? <String>[]
            : await ApiClient.uploadImages(stamped, watermark: true);
        final images = [..._existingImages, ...uploaded];
        await PostService.updatePost(
          widget.existing!.id,
          content: story.isEmpty ? null : story,
          images: images,
          locPublic: _locPublic,
          fish: _catches
              .map((c) => {'name': c.species, 'count': c.count})
              .toList(growable: false),
          lengthCm: lengthCm,
          weightG: weightG,
          weather: wx,
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
          imageFiles: _video == null
              ? await _stampImages(_images, wx)
              : const <String>[],
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
          lengthCm: lengthCm,
          weightG: weightG,
          weather: wx,
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

  // ───────────────────────── 渔获照片核验 ─────────────────────────

  /// 发布前扫描首图是否为真实鱼获。
  /// 返回 true=可以发布；false=核验未通过（已提示，调用方应中止发布）。
  Future<bool> _verifyCatchPhoto(String path) async {
    String dataUri;
    try {
      dataUri = await fileToScaledDataUri(File(path), maxWidth: 448);
    } catch (_) {
      return true; // 读图/缩放失败不阻塞发布
    }
    try {
      final r = await FishService.recognize(dataUri);
      // 明确判定为「没有鱼」→ 直接拒绝
      if (r.hasFish == false) {
        if (mounted) {
          CenterToast.show(context, '这不是真实鱼获照片，请发布真实的渔获信息',
              icon: Icons.block);
        }
        return false;
      }
      // AI 未配置（needManual）→ 降级为人工确认
      if (r.hasFish == null) {
        final sure = await _confirmRealCatch();
        if (!sure) return false;
      }
      // 通过：用 AI 结果预填鱼种与尺寸（用户仍可改）
      if (mounted) {
        setState(() {
          if (_catches.isEmpty && r.matched.isNotEmpty) {
            _catches.add(_CatchItem(r.matched.first.name));
          }
          if (_lengthCtrl.text.trim().isEmpty && r.lengthCm != null) {
            _lengthCtrl.text = r.lengthCm!.toStringAsFixed(1);
          }
          if (_weightCtrl.text.trim().isEmpty && r.weightG != null) {
            _weightCtrl.text = r.weightG!.toStringAsFixed(0);
          }
        });
      }
      return true;
    } catch (_) {
      // AI 调用异常（网络/配额）→ 降级为人工确认，别把用户卡死
      final sure = await _confirmRealCatch();
      return sure;
    }
  }

  /// AI 不可用时的兜底：让用户确认照片是真实渔获
  Future<bool> _confirmRealCatch() async {
    if (!mounted) return false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('请确认渔获照片'),
        content: const Text('当前无法自动核验照片，请确认这张照片是真实的钓鱼渔获。'
            '发布非渔获内容将被管理员处理。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确认发布'),
          ),
        ],
      ),
    );
    return ok == true;
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
          const SizedBox(height: 12),
          _sizeCard(),
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

  /// 渔获尺寸：体长(cm) / 重量(g)。AI 核验后自动预填，用户可改。
  Widget _sizeCard() {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _cardTitle(Icons.straighten_outlined, '渔获尺寸',
              trailing: '用于池塘按比例缩放'),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _lengthCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  maxLength: 6,
                  buildCounter: (_,
                          {required currentLength, required maxLength, required isFocused}) =>
                      null,
                  decoration: InputDecoration(
                    hintText: '体长',
                    hintStyle: TextStyle(
                        fontSize: 12.5, color: AppTheme.textSecondary),
                    suffixText: 'cm',
                    filled: true,
                    fillColor: AppTheme.primarySoft,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _weightCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  maxLength: 8,
                  buildCounter: (_,
                          {required currentLength, required maxLength, required isFocused}) =>
                      null,
                  decoration: InputDecoration(
                    hintText: '重量',
                    hintStyle: TextStyle(
                        fontSize: 12.5, color: AppTheme.textSecondary),
                    suffixText: 'g',
                    filled: true,
                    fillColor: AppTheme.primarySoft,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text('尺寸真实填写后，池塘里的鱼会按真实大小 ×10 显示',
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
