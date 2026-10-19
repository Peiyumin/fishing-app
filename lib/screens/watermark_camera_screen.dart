import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:gal/gal.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../app_theme.dart';
import '../models/weather_forecast.dart';
import '../services/weather_service.dart';
import '../utils/geo_names.dart';
import '../widgets/center_toast.dart';
import 'publish_screen.dart';

/// 水印相机：拍照后自动叠加
///   日期时间 + 实时天气（天气/温湿度/风/气压/钓况）+ 定位地址
///   支持保存到相册 / 一键带图发动态
class WatermarkCameraScreen extends StatefulWidget {
  const WatermarkCameraScreen({super.key});

  @override
  State<WatermarkCameraScreen> createState() => _WatermarkCameraScreenState();
}

class _WatermarkCameraScreenState extends State<WatermarkCameraScreen> {
  final _picker = ImagePicker();
  final GlobalKey _boundaryKey = GlobalKey();

  File? _photo; // 原始照片
  FishingWeather? _weather; // 实时天气
  String? _place; // 定位地址（城市 + 详细）
  bool _loadingInfo = false;
  bool _working = false; // 保存/合成中
  bool _shotOnce = false; // 进入后是否已自动拍过
  String? _cameraError; // 相机打开失败提示

  @override
  void initState() {
    super.initState();
    // 打开即自动调起相机
    WidgetsBinding.instance.addPostFrameCallback((_) => _shoot());
  }

  Future<void> _shoot() async {
    XFile? x;
    try {
      x = await _picker.pickImage(
        source: ImageSource.camera,
        maxWidth: 1600,
        imageQuality: 90,
      );
    } catch (e) {
      // 设备没有可用的相机 App（或权限被拒）：
      // 停留在本页，提供「重新打开相机 / 从相册选一张」两个入口
      if (!mounted) return;
      setState(() => _cameraError = '无法打开相机，可重试或从相册选一张');
      CenterToast.show(context, '无法打开相机，可从相册选一张');
      return;
    }
    if (!mounted) return;
    final picked = x;
    if (picked == null) {
      // 用户在相机里点返回：第一次自动拉起时直接退出本页
      if (!_shotOnce && Navigator.canPop(context)) Navigator.pop(context);
      return;
    }
    _shotOnce = true;
    setState(() {
      _photo = File(picked.path);
      _loadingInfo = true;
    });
    _loadInfo();
  }

  /// 从相册选图（无相机设备降级）
  Future<void> _pickFromGallery() async {
    try {
      final x = await _picker.pickImage(
          source: ImageSource.gallery, maxWidth: 1600, imageQuality: 90);
      if (!mounted) return;
      if (x == null) return;
      _shotOnce = true;
      setState(() {
        _photo = File(x.path);
        _loadingInfo = true;
      });
      _loadInfo();
    } catch (e) {
      if (mounted) CenterToast.show(context, '选择图片失败：$e');
    }
  }

  /// 并行取定位地址 + 天气（任一失败不影响拍照打卡，水印少显示一行而已）
  Future<void> _loadInfo() async {
    try {
      final pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high);
      final results = await Future.wait([
        GeoNames.reverse(pos.latitude, pos.longitude),
        WeatherService.fetch(pos.latitude, pos.longitude),
      ]);
      if (!mounted) return;
      final geo = results[0] as Map<String, dynamic>?;
      setState(() {
        _weather = results[1] as FishingWeather?;
        if (geo != null) {
          final city = (geo['city'] ?? '') as String;
          final display = (geo['display'] ?? '') as String;
          // 展示：地级市 + 去掉国名省名前缀的详细地址（太长截断）
          var detail = display;
          for (final prefix in ['中国, ', '中国,']) {
            if (detail.startsWith(prefix)) detail = detail.substring(prefix.length);
          }
          _place = detail.isEmpty
              ? city
              : (city.isNotEmpty && !detail.startsWith(city)
                  ? '$city · ${detail.length > 40 ? detail.substring(0, 40) : detail}'
                  : detail.length > 44
                      ? detail.substring(0, 44)
                      : detail);
        }
        _loadingInfo = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingInfo = false);
    }
  }

  /// 合成水印照片 → 临时文件路径
  Future<String> _composite() async {
    final boundary = _boundaryKey.currentContext?.findRenderObject()
        as RenderRepaintBoundary?;
    if (boundary == null) throw Exception('照片尚未就绪');
    final image = await boundary.toImage(pixelRatio: 2.5);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    if (bytes == null) throw Exception('照片处理失败');
    final dir = Directory.systemTemp;
    final name =
        'fishing_wm_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.png';
    final f = File('${dir.path}/$name');
    await f.writeAsBytes(bytes.buffer.asUint8List());
    return f.path;
  }

  /// 保存到系统相册
  Future<void> _save() async {
    if (_photo == null) return;
    setState(() => _working = true);
    try {
      if (!await Gal.hasAccess(toAlbum: true)) {
        await Gal.requestAccess(toAlbum: true);
      }
      final path = await _composite();
      await Gal.putImage(path);
      if (mounted) CenterToast.show(context, '已保存到相册', icon: Icons.check_circle);
    } on GalException catch (e) {
      if (mounted) CenterToast.show(context, '保存失败：${e.type.message}');
    } catch (e) {
      if (mounted) CenterToast.show(context, '保存失败：$e');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  /// 带图去发动态
  Future<void> _publish() async {
    if (_photo == null) return;
    setState(() => _working = true);
    try {
      final path = await _composite();
      if (!mounted) return;
      await Navigator.of(context).pushReplacement(MaterialPageRoute(
        builder: (_) => PublishScreen(category: 'post', initialImage: path),
      ));
    } catch (e) {
      if (mounted) CenterToast.show(context, '处理失败：$e');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('拍照打卡'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        flexibleSpace: null,
      ),
      body: _photo == null
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_cameraError != null) ...[
                    Icon(Icons.camera_alt_outlined,
                        size: 36, color: Colors.white54),
                    const SizedBox(height: 10),
                    Text(_cameraError!,
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 13)),
                    const SizedBox(height: 18),
                  ] else ...[
                    const CircularProgressIndicator(),
                    const SizedBox(height: 12),
                    const Text('正在打开相机…',
                        style: TextStyle(
                            color: Colors.white70, fontSize: 13)),
                    const SizedBox(height: 20),
                  ],
                  FilledButton.icon(
                    onPressed: _shoot,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.primary,
                    ),
                    icon: const Icon(Icons.camera_alt_outlined, size: 18),
                    label: const Text('打开相机拍照'),
                  ),
                  const SizedBox(height: 10),
                  // 无相机设备（模拟器/部分平板）的降级入口
                  OutlinedButton.icon(
                    onPressed: _pickFromGallery,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white70,
                      side: const BorderSide(color: Colors.white24),
                    ),
                    icon: const Icon(Icons.photo_outlined, size: 18),
                    label: const Text('从相册选一张'),
                  ),
                ],
              ),
            )
          : Column(
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: RepaintBoundary(
                        key: _boundaryKey,
                        child: AspectRatio(
                          aspectRatio: 3 / 4,
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              Image.file(_photo!, fit: BoxFit.cover),
                              // 底部信息水印
                              Positioned(
                                left: 0,
                                right: 0,
                                bottom: 0,
                                child: Container(
                                  padding: const EdgeInsets.fromLTRB(
                                      14, 40, 14, 14),
                                  decoration: const BoxDecoration(
                                    gradient: LinearGradient(
                                      begin: Alignment.bottomCenter,
                                      end: Alignment.topCenter,
                                      colors: [
                                        Colors.black87,
                                        Colors.transparent
                                      ],
                                    ),
                                  ),
                                  child: _watermark(),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                // 操作区
                SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                    child: Row(
                      children: [
                        OutlinedButton.icon(
                          onPressed: _working ? null : _shoot,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: const BorderSide(color: Colors.white38),
                          ),
                          icon: const Icon(Icons.camera_alt_outlined, size: 18),
                          label: const Text('重拍'),
                        ),
                        const Spacer(),
                        OutlinedButton.icon(
                          onPressed: _working ? null : _save,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: const BorderSide(color: Colors.white38),
                          ),
                          icon: const Icon(Icons.save_alt, size: 18),
                          label: const Text('存相册'),
                        ),
                        const SizedBox(width: 10),
                        FilledButton.icon(
                          onPressed: _working ? null : _publish,
                          style: FilledButton.styleFrom(
                            backgroundColor: AppTheme.primary,
                          ),
                          icon: _working
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2, color: Colors.white))
                              : const Icon(Icons.send_rounded, size: 17),
                          label: const Text('发动态'),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  /// 水印内容：品牌 + 时间 + 天气 + 钓况 + 位置
  Widget _watermark() {
    final now = DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now());
    final w = _weather;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            const Icon(Icons.phishing, color: Colors.white, size: 15),
            const SizedBox(width: 5),
            Text('垂钓圈 · 钓鱼打卡',
                style: TextStyle(
                    color: Colors.white.withOpacity(0.9),
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600)),
          ],
        ),
        const SizedBox(height: 6),
        Text(now,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5)),
        const SizedBox(height: 5),
        if (w != null) ...[
          Row(
            children: [
              Icon(Wmo.icon(w.weatherCode), color: Colors.white, size: 15),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  '${w.description} ${w.temperature.round()}℃'
                  ' · 湿度${w.humidity}% · 风${w.windSpeed.round()}km/h'
                  ' · 气压${w.pressure.round()}hPa',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: Colors.white.withOpacity(0.92), fontSize: 11.5),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text('钓况${w.fishIndex} · ${w.fishAdvice}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: AppTheme.star, fontSize: 11.5)),
          const SizedBox(height: 4),
        ] else if (_loadingInfo)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text('正在获取天气与位置…',
                style: TextStyle(
                    color: Colors.white.withOpacity(0.6), fontSize: 11)),
          ),
        if (_place != null && _place!.isNotEmpty)
          Row(
            children: [
              Icon(Icons.location_on_outlined,
                  color: Colors.white.withOpacity(0.85), size: 13),
              const SizedBox(width: 4),
              Flexible(
                child: Text(_place!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: Colors.white.withOpacity(0.85),
                        fontSize: 11.5)),
              ),
            ],
          ),
      ],
    );
  }
}
