import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';

import '../app_theme.dart';
import '../models/weather_forecast.dart';
import '../services/location_service.dart';
import '../services/weather_service.dart';
import '../utils/geo_names.dart';
import '../utils/text_safe.dart';
import '../utils/watermark_stamp.dart';
import '../widgets/center_toast.dart';
import 'publish_catch_screen.dart';

/// 渔获拍照（水印相机 · App 内全屏取景）
///
/// 布局参照主流短视频/记录类 App 的拍照页：
///   顶部：标题 + 「发动态」+ 前后摄切换
///   中间：四角取景框 + 「把鱼放在框内，整条鱼都拍进来」
///   底部：关闭 / 彩虹环快门（轻触拍照、长按录像）/ 相册
///
/// 拍下的照片会**当场合成**时间·天气·温度·湿度·气压·钓况·钓点水印
/// （dart:ui 直接画到像素上，不依赖控件树截图，尺寸稳定、速度快）。
class WatermarkCameraScreen extends StatefulWidget {
  /// true：拍完把水印图路径 pop 回调用页（渔获发布页用）
  /// false：拍完直接跳「发动态」页（老的打卡流程）
  final bool returnResult;

  /// 顶部标题
  final String title;

  const WatermarkCameraScreen({
    super.key,
    this.returnResult = false,
    this.title = '记渔获',
  });

  @override
  State<WatermarkCameraScreen> createState() => _WatermarkCameraScreenState();
}

class _WatermarkCameraScreenState extends State<WatermarkCameraScreen>
    with WidgetsBindingObserver {
  final _picker = ImagePicker();

  List<CameraDescription> _cameras = const [];
  int _camIndex = 0;
  CameraController? _cam;

  bool _opening = true; // 相机初始化中
  String? _error; // 相机不可用时的提示
  bool _busy = false; // 拍照/合成中
  bool _audioEnabled = true; // 麦克风被拒时降级为无声录像

  bool _recording = false;
  int _recSecs = 0;
  Timer? _recTimer;
  static const int _maxRecSecs = 15;

  FishingWeather? _weather;
  String? _place;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _openCamera();
    // 天气/位置单独取，取不到就不显示那一行，不影响拍照
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadInfo());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _recTimer?.cancel();
    final c = _cam;
    _cam = null;
    c?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // 从后台/别的 App 回来：控制器已经被释放过，重新打开
      if (_cam == null && !_opening) _openCamera(index: _camIndex);
      return;
    }
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      final c = _cam;
      if (c == null) return;
      _recTimer?.cancel();
      _recTimer = null;
      setState(() {
        _cam = null;
        _recording = false;
      });
      // 注意：这里不要 await，避免平台通道在后台卡住
      c.dispose();
    }
  }

  // ───────────────────────── 相机 ─────────────────────────

  Future<void> _openCamera({int? index}) async {
    if (!mounted) return;
    setState(() {
      _opening = true;
      _error = null;
    });
    try {
      if (_cameras.isEmpty) _cameras = await availableCameras();
    } catch (e) {
      _fail('无法访问摄像头：${_brief(e)}');
      return;
    }
    if (_cameras.isEmpty) {
      _fail('这台设备没有找到可用的摄像头');
      return;
    }

    final target = (index ?? _camIndex).clamp(0, _cameras.length - 1);
    final desc = _cameras[target];

    // 先带声音初始化（录像要有声音）；麦克风被拒时降级为无声，照片照常拍
    CameraController? c;
    var audio = true;
    for (final tryAudio in const [true, false]) {
      audio = tryAudio;
      final candidate = CameraController(
        desc,
        ResolutionPreset.veryHigh,
        enableAudio: tryAudio,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );
      try {
        await candidate.initialize();
        c = candidate;
        break;
      } on CameraException catch (e) {
        await candidate.dispose();
        // 只有麦克风权限被拒才值得降级重试，其它错误直接报
        if (tryAudio && _isAudioDenied(e)) continue;
        _fail(_describe(e));
        return;
      } catch (e) {
        await candidate.dispose();
        _fail('相机启动失败:${_brief(e)}');
        return;
      }
    }
    if (c == null) {
      _fail('相机启动失败，请检查权限后重试');
      return;
    }
    if (!mounted) {
      await c.dispose();
      return;
    }
    final old = _cam;
    setState(() {
      _cam = c;
      _camIndex = target;
      _audioEnabled = audio;
      _opening = false;
    });
    await old?.dispose();
  }

  bool _isAudioDenied(CameraException e) {
    final code = e.code.toLowerCase();
    return code.contains('audio') || code.contains('microphone');
  }

  String _describe(CameraException e) {
    final code = e.code.toLowerCase();
    if (code.contains('cameraaccessdenied') ||
        code.contains('permission') ||
        code.contains('denied')) {
      return '相机权限没开，去「设置 → 垂钓圈 → 相机」打开后再进来';
    }
    if (code.contains('audiodenied') || code.contains('microphone')) {
      return '麦克风权限没开，录像会没有声音';
    }
    if (code.contains('cameraunavailable') || code.contains('inuse')) {
      return '摄像头被其它 App 占用了，关掉那个 App 再试';
    }
    return (e.description ?? '').trim().isEmpty ? e.code : e.description!;
  }

  void _fail(String msg) {
    if (!mounted) return;
    setState(() {
      _opening = false;
      _error = msg;
    });
  }

  Future<void> _flip() async {
    if (_cameras.length < 2 || _busy || _recording || _opening) return;
    await _openCamera(index: (_camIndex + 1) % _cameras.length);
  }

  // ───────────────────────── 天气 / 位置 ─────────────────────────

  Future<void> _loadInfo() async {
    try {
      final pos = await LocationService.determinePosition();
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
          var detail = display;
          for (final prefix in ['中国, ', '中国,']) {
            if (detail.startsWith(prefix)) {
              detail = detail.substring(prefix.length);
            }
          }
          // 水印地址：地级市 + 详细地址（太长截断）
          // ★ 用 cutGrapheme 而不是 substring：地址里可能带 emoji 或罕见字，
          //   按 code unit 切会切出孤立代理项 → 水印上印一个方块。
          _place = detail.isEmpty
              ? city
              : (city.isNotEmpty && !detail.startsWith(city)
                  ? '$city · ${cutGrapheme(detail, 40)}'
                  : cutGrapheme(detail, 44));
        }
      });
    } on LocationException {
      // 相机页不弹权限引导：发布页进来前已经申请过，
      // 这里拒绝就安静跳过，水印少一行地址而已，别打断取景。
    } catch (_) {
      // 天气/地址失败只是水印少一行，不打扰用户
    }
  }

  // ───────────────────────── 拍摄 ─────────────────────────

  Future<void> _shoot() async {
    final c = _cam;
    if (c == null || !c.value.isInitialized || _busy || _recording) return;
    setState(() => _busy = true);
    try {
      final shot = await c.takePicture();
      final path = await _stampOrRaw(shot.path);
      if (!mounted) return;
      Navigator.of(context).pop(path);
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        CenterToast.show(context, '拍照失败：${_brief(e)}');
      }
    }
  }

  /// 顶部「发动态」：直接进「发布渔获」页，**不拍照**
  ///
  /// 之前这里接的是「先拍一张、再带着照片进发布页」，于是在相机页点
  /// 「发动态」的表现就是"咔"一下拍张照，和按钮文字完全不符。
  /// 现在按语义来：发动态 = 直接去发布页，拍不拍照由用户自己决定
  /// （发布页里有「拍照（带天气水印）」入口，点它才会再次进相机）。
  Future<void> _goPublish() async {
    if (_busy || _recording) return;
    await Navigator.of(context).pushReplacement(MaterialPageRoute(
      builder: (_) => const PublishCatchScreen(),
    ));
  }

  /// 从相册选一张（原图直接回传，不伪造拍摄时间水印）
  Future<void> _fromGallery() async {
    if (_busy || _recording) return;
    try {
      final x = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1600,
        imageQuality: 90,
      );
      if (!mounted || x == null) return;
      Navigator.of(context).pop(x.path);
    } catch (e) {
      if (mounted) CenterToast.show(context, '选择图片失败：${_brief(e)}');
    }
  }

  Future<void> _startRecord() async {
    final c = _cam;
    if (c == null || !c.value.isInitialized || _busy || _recording) return;
    if (!_audioEnabled) {
      CenterToast.show(context, '麦克风没开，这段视频会没有声音',
          icon: Icons.mic_off);
    }
    try {
      await c.startVideoRecording();
    } catch (e) {
      if (mounted) CenterToast.show(context, '无法开始录像：${_brief(e)}');
      return;
    }
    if (!mounted) return;
    setState(() {
      _recording = true;
      _recSecs = 0;
    });
    _recTimer?.cancel();
    _recTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() => _recSecs++);
      if (_recSecs >= _maxRecSecs) _stopRecord(); // 到点自动停
    });
  }

  Future<void> _stopRecord({bool discard = false}) async {
    if (!_recording) return;
    _recTimer?.cancel();
    _recTimer = null;
    setState(() => _recording = false);
    final c = _cam;
    if (c == null) return;
    try {
      final f = await c.stopVideoRecording();
      // 取不到大小就当通过，别因为查体积把整段视频丢掉
      var size = 0;
      try {
        size = await File(f.path).length();
      } catch (_) {}
      if (discard) {
        try {
          await File(f.path).delete();
        } catch (_) {}
        if (mounted) Navigator.of(context).pop();
        return;
      }
      if (size > 60 * 1024 * 1024) {
        try {
          await File(f.path).delete();
        } catch (_) {}
        if (mounted) CenterToast.show(context, '视频超过 60MB，请缩短录制时长');
        return;
      }
      if (!mounted) return;
      Navigator.of(context).pop(f.path);
    } catch (e) {
      if (mounted) CenterToast.show(context, '录像失败：${_brief(e)}');
    }
  }

  void _close() {
    if (_recording) {
      _stopRecord(discard: true);
      return;
    }
    Navigator.of(context).pop();
  }

  String _brief(Object e) {
    if (e is CameraException) {
      final d = (e.description ?? '').trim();
      return d.isEmpty ? e.code : d;
    }
    return '$e';
  }

  // ───────────────────────── 水印合成 ─────────────────────────

  /// 合成水印；万一合成失败也要把原图交给用户，不能因为水印挡住发布
  Future<String> _stampOrRaw(String srcPath) async {
    try {
      return await _stampToFile(srcPath);
    } catch (_) {
      return srcPath;
    }
  }

  Future<String> _stampToFile(String srcPath) async {
    final src = await File(srcPath).readAsBytes();
    final png = await stampWatermarkPng(src, _watermarkLines());
    final dir = await getTemporaryDirectory();
    final name =
        'fishing_wm_${DateFormat('yyyyMMdd_HHmmss_SSS').format(DateTime.now())}.png';
    final f = File('${dir.path}/$name');
    await f.writeAsBytes(png, flush: true);
    return f.path;
  }

  /// 这次要盖到照片上的水印内容
  List<WatermarkLine> _watermarkLines() {
    final lines = <WatermarkLine>[
      const WatermarkLine(
          '垂钓圈 · 钓鱼打卡', 12.5, FontWeight.w600, Color(0xE6FFFFFF)),
      WatermarkLine(DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now()), 26,
          FontWeight.w700, const Color(0xFFFFFFFF), 4),
    ];
    final wx = _weather;
    if (wx != null) {
      lines.add(WatermarkLine(
        '${wx.description} ${wx.temperature.round()}℃ · 湿度${wx.humidity}%'
        ' · ${windLevelText(wx.windSpeed, wx.windDir)}'
        ' · 气压${wx.pressure.round()}hPa',
        12.5,
        FontWeight.w500,
        const Color(0xEBFFFFFF),
      ));
      lines.add(WatermarkLine('钓况${wx.fishIndex} · ${wx.fishAdvice}', 12.5,
          FontWeight.w600, AppTheme.star));
    }
    final place = _place;
    if (place != null && place.isNotEmpty) {
      lines.add(WatermarkLine(
          place, 12.5, FontWeight.w500, const Color(0xDBFFFFFF)));
    }
    return lines;
  }

  // ───────────────────────── UI ─────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          _previewLayer(),
          if (_cam != null && _error == null) ...[
            const _Vignette(),
            _frameLayer(),
            _topBar(),
            _bottomBar(),
          ],
          if (_opening && _error == null) _loadingLayer(),
          if (_error != null) _errorLayer(_error!),
          if (_busy) _busyLayer(),
        ],
      ),
    );
  }

  Widget _previewLayer() {
    final c = _cam;
    if (c == null || !c.value.isInitialized) {
      return const ColoredBox(color: Colors.black);
    }
    // previewSize 是横屏尺寸（宽>高），这里换算成竖屏再按 cover 铺满
    final size = c.value.previewSize;
    final double pw = (size?.height ?? 0) > 0 ? size!.height : 9;
    final double ph = (size?.width ?? 0) > 0 ? size!.width : 16;
    return SizedBox.expand(
      child: FittedBox(
        fit: BoxFit.cover,
        clipBehavior: Clip.hardEdge,
        child: SizedBox(
          width: pw,
          height: ph,
          child: CameraPreview(c),
        ),
      ),
    );
  }

  Widget _loadingLayer() => const ColoredBox(
        color: Colors.black,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 26,
                height: 26,
                child: CircularProgressIndicator(
                    strokeWidth: 2.2, color: Colors.white70),
              ),
              SizedBox(height: 14),
              Text('正在打开相机…',
                  style: TextStyle(color: Colors.white70, fontSize: 13)),
            ],
          ),
        ),
      );

  Widget _busyLayer() => ColoredBox(
        color: Colors.black54,
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.62),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
                ),
                SizedBox(width: 12),
                Text('正在合成水印…',
                    style: TextStyle(color: Colors.white, fontSize: 13.5)),
              ],
            ),
          ),
        ),
      );

  Widget _errorLayer(String msg) => Container(
        color: Colors.black,
        padding: const EdgeInsets.symmetric(horizontal: 30),
        child: SafeArea(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.camera_alt_outlined,
                  size: 40, color: Colors.white54),
              const SizedBox(height: 14),
              Text(
                msg,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: Colors.white70, fontSize: 13.5, height: 1.6),
              ),
              const SizedBox(height: 22),
              SizedBox(
                height: 44,
                width: 190,
                child: ElevatedButton(
                  onPressed: _openCamera,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('重试打开相机'),
                ),
              ),
              const SizedBox(height: 10),
              TextButton.icon(
                onPressed: _fromGallery,
                icon: const Icon(Icons.photo_outlined,
                    size: 18, color: Colors.white70),
                label: const Text('从相册选一张',
                    style: TextStyle(color: Colors.white70, fontSize: 13.5)),
              ),
              const SizedBox(height: 6),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('先不拍',
                    style: TextStyle(color: Colors.white38, fontSize: 13)),
              ),
            ],
          ),
        ),
      );

  /// 顶部：标题 · 发动态 · 前后摄切换
  Widget _topBar() {
    return Positioned(
      left: 0,
      right: 0,
      top: 0,
      child: Container(
        padding: const EdgeInsets.only(bottom: 18),
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0x8C000000), Color(0x00000000)],
          ),
        ),
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 8, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      widget.title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5,
                        shadows: [
                          Shadow(color: Color(0x66000000), blurRadius: 8),
                        ],
                      ),
                    ),
                    const Spacer(),
                    _pill('发动态', _goPublish),
                    const SizedBox(width: 10),
                    _roundBtn(
                      Icons.flip_camera_ios_outlined,
                      _flip,
                      enabled: _cameras.length > 1 && !_flipping,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                _infoChip(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  bool get _flipping => _opening;

  /// 顶部左侧的天气/地点小胶囊（也是「这张图会盖什么水印」的预告）
  Widget _infoChip() {
    final wx = _weather;
    final place = _place;
    if (wx == null && (place == null || place.isEmpty)) {
      return const SizedBox(height: 22);
    }
    final parts = <String>[
      if (wx != null) '${wx.description} ${wx.temperature.round()}℃',
      if (place != null && place.isNotEmpty) place,
    ];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.34),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            wx != null ? Wmo.icon(wx.weatherCode) : Icons.location_on_outlined,
            size: 12.5,
            color: Colors.white.withOpacity(0.9),
          ),
          const SizedBox(width: 5),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 250),
            child: Text(
              parts.join(' · '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white.withOpacity(0.9),
                fontSize: 11.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _pill(String text, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        height: 34,
        padding: const EdgeInsets.symmetric(horizontal: 15),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.4),
          borderRadius: BorderRadius.circular(17),
        ),
        child: Text(
          text,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 13.5,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _roundBtn(IconData icon, VoidCallback onTap, {bool enabled = true}) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 36,
        height: 36,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.4),
          shape: BoxShape.circle,
        ),
        child: Icon(
          icon,
          size: 19,
          color: enabled ? Colors.white : Colors.white38,
        ),
      ),
    );
  }

  /// 取景框 + 两行提示
  Widget _frameLayer() {
    return LayoutBuilder(builder: (context, cons) {
      // 横屏（高度不够）时用紧凑版：框更小、只留一行提示，别和快门叠在一起
      final compact = cons.maxHeight < 520;
      // 宽度优先，但不能超过屏幕高度的一部分（横屏/小平板时按高度反算宽度）
      var fw = math.min(cons.maxWidth - 54, 420.0);
      var fh = fw * 1.19;
      final maxH = cons.maxHeight * (compact ? 0.40 : 0.56);
      if (fh > maxH) {
        fh = maxH;
        fw = fh / 1.19;
      }
      return Align(
        alignment: Alignment(0, compact ? -0.13 : -0.07),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: fw,
              height: fh,
              child: const CustomPaint(painter: _BracketPainter()),
            ),
            SizedBox(height: compact ? 12 : 20),
            Text(
              _recording ? '松手结束录制' : '把鱼放在框内，整条鱼都拍进来',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: compact ? 13 : 14.5,
                fontWeight: FontWeight.w500,
                shadows: const [
                  Shadow(color: Color(0x99000000), blurRadius: 8)
                ],
              ),
            ),
            if (compact && _recording) ...[
              const SizedBox(height: 5),
              Text(
                '已录 ${_fmtSec(_recSecs)} / ${_fmtSec(_maxRecSecs)}',
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ],
            if (!compact) ...[
            const SizedBox(height: 7),
            Text(
              _recording
                  ? '已录 ${_fmtSec(_recSecs)} / ${_fmtSec(_maxRecSecs)}'
                  : '轻触拍照，长按录像',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withOpacity(_recording ? 0.92 : 0.62),
                fontSize: 12.5,
                shadows: const [
                  Shadow(color: Color(0x99000000), blurRadius: 8),
                ],
              ),
            ),
            ],
          ],
        ),
      );
    });
  }

  String _fmtSec(int s) =>
      '${(s ~/ 60).toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}';

  /// 底部：关闭 · 快门 · 相册
  Widget _bottomBar() {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: Container(
        padding: const EdgeInsets.only(top: 40),
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [Color(0xA6000000), Color(0x00000000)],
          ),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
            child: Row(
              children: [
                Expanded(
                  child: Center(
                    child: _roundAction(
                      icon: Icons.close,
                      size: 56,
                      onTap: _close,
                    ),
                  ),
                ),
                Expanded(
                  child: Center(child: _shutter()),
                ),
                Expanded(
                  child: Center(
                    child: _roundAction(
                      icon: Icons.photo_library_outlined,
                      size: 56,
                      onTap: _fromGallery,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _roundAction({
    required IconData icon,
    required double size,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: _busy ? null : onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.42),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white.withOpacity(0.14)),
        ),
        child: Icon(icon, size: size * 0.44, color: Colors.white),
      ),
    );
  }

  /// 彩虹环快门：轻触拍照，长按录像
  Widget _shutter() {
    const double ring = 84; // 彩虹环直径
    const double inner = 72; // 白色内圆（环宽 6）
    return GestureDetector(
      onTap: _busy ? null : _shoot,
      onLongPressStart: (_) => _startRecord(),
      onLongPressEnd: (_) => _stopRecord(),
      onLongPressCancel: () => _stopRecord(discard: true),
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: ring,
        height: ring,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // 彩虹环
            Container(
              width: ring,
              height: ring,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: SweepGradient(
                  colors: _recording
                      ? const [AppTheme.danger, AppTheme.danger]
                      // 原来是一圈彩虹（蓝/绿/黄/粉/紫）—— 全站唯一的彩虹，
                      // 和「近黑 + 冷灰 + 荧光黄绿」完全无关。改成黄绿同色相
                      // 的明暗扫掠：仍有"在动"的感觉，但跑不出色板。
                      : const [
                          AppTheme.accent,
                          AppTheme.accentDark,
                          AppTheme.accent,
                        ],
                ),
              ),
            ),
            // 白色内圆
            AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              curve: Curves.easeOut,
              width: inner,
              height: inner,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white,
              ),
            ),
            // 录像时中间压一个红色方块（松开即停）
            if (_recording)
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: AppTheme.danger,
                  borderRadius: BorderRadius.circular(9),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 四角取景框
class _BracketPainter extends CustomPainter {
  const _BracketPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final len = math.min(size.width, size.height) * 0.09;
    final p = Paint()
      ..color = Colors.white.withOpacity(0.95)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;

    final w = size.width;
    final h = size.height;
    // 左上
    canvas.drawLine(Offset(0, len), Offset.zero, p);
    canvas.drawLine(Offset.zero, Offset(len, 0), p);
    // 右上
    canvas.drawLine(Offset(w - len, 0), Offset(w, 0), p);
    canvas.drawLine(Offset(w, 0), Offset(w, len), p);
    // 左下
    canvas.drawLine(Offset(0, h - len), Offset(0, h), p);
    canvas.drawLine(Offset(0, h), Offset(len, h), p);
    // 右下
    canvas.drawLine(Offset(w - len, h), Offset(w, h), p);
    canvas.drawLine(Offset(w, h), Offset(w, h - len), p);
  }

  @override
  bool shouldRepaint(covariant _BracketPainter oldDelegate) => false;
}

/// 四周轻微压暗，让白字更清楚
class _Vignette extends StatelessWidget {
  const _Vignette();

  @override
  Widget build(BuildContext context) {
    return const IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            radius: 1.1,
            colors: [Color(0x00000000), Color(0x59000000)],
            stops: [0.55, 1.0],
          ),
        ),
      ),
    );
  }
}
