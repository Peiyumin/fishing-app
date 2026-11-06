import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../widgets/emoji_panel.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong2.dart';
import 'package:provider/provider.dart';

import '../services/location_service.dart';
import '../services/refresh_bus.dart';
import '../services/spot_service.dart';
import '../services/session_provider.dart';
import '../services/api_config.dart';
import '../services/geo_place.dart';
import '../utils/coord_transform.dart';
import 'auth_screen.dart';
import '../widgets/center_toast.dart';
import '../widgets/location_prompt.dart';
import '../widgets/spot_map_marker.dart';

/// 标记野钓点（kind=wild）
/// 流程：打开自动读取当前位置 → 可在地图上拖动/点选微调 →
/// 填写名称/鱼种/说明 → 保存后全员实时可见（无需审核）。
class PublishSpotScreen extends StatefulWidget {
  const PublishSpotScreen({super.key});

  @override
  State<PublishSpotScreen> createState() => _PublishSpotScreenState();
}

class _PublishSpotScreenState extends State<PublishSpotScreen> {
  final _mapController = MapController();
  final _nameCtrl = TextEditingController();
  final _fishCtrl = TextEditingController();
  final _descCtrl = TextEditingController();

  LatLng? _picked; // WGS-84 坐标（存储用）
  LatLng? _myLocation; // 当前定位（GCJ-02，仅作「我在哪」指示，与钓点区分）
  bool _submitting = false;
  bool _locating = false;

  // 选中位置的中文地址（由坐标反查得到，用于顶部提示）
  GeoPlace? _geoAddress;
  bool _resolvingAddress = false;

  // ── v44：地址输入 + 坐标可信度 ──────────────────────────────
  // 以前这页只能在卫星图上点一下，地址是反查出来的、改不了。
  // 现在补一个「详细地址」输入框：可以直接打字（给外地的钓点用），
  // 也可以点右边的准星读当前位置。
  final _addrCtrl = TextEditingController();

  /// 坐标是否「实测精确」：
  ///   true  = 刚点过定位 / 刚在图上点过 → 坐标就是钓位
  ///   false = 用户手改了地址文字 → 旧坐标已经对不上这句话了
  bool _precise = false;

  /// 地址解析中（提交时按地址换坐标）
  bool _geocoding = false;

  // 默认中心：杭州（GCJ-02）
  final LatLng _defaultCenter = const LatLng(30.2741, 120.1551);

  @override
  void initState() {
    super.initState();
    // 打开页面即自动读取当前位置
    WidgetsBinding.instance.addPostFrameCallback((_) => _useMyLocation());
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _fishCtrl.dispose();
    _descCtrl.dispose();
    _addrCtrl.dispose();
    super.dispose();
  }

  /// 读取当前位置（WGS-84）并在地图上居中
  Future<void> _useMyLocation() async {
    setState(() => _locating = true);
    try {
      final pos = await LocationService.determinePosition();
      final p = LatLng(pos.latitude, pos.longitude); // WGS-84
      final g = CoordTransform.wgs84ToGcj02(pos.latitude, pos.longitude);
      _mapController.move(LatLng(g[0], g[1]), 15);
      if (mounted) {
        setState(() {
          _picked = p;
          _myLocation = LatLng(g[0], g[1]);
          _precise = true; // GPS 拿到的点就是钓位
        });
        _resolveAddress(p.latitude, p.longitude);
      }
    } on LocationException catch (e) {
      if (mounted) {
        LocationPrompt.showError(context, e);
      }
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  /// 反查选中坐标的中文地址，结果写入 [_geoAddress]
  ///
  /// 只有在 [_precise] 为 true（刚定位/刚点图）时才回填到地址输入框：
  /// 用户手改了地址之后 [_precise] 会变 false，这时不能拿旧坐标的反查结果
  /// 去覆盖他刚打的字。
  Future<void> _resolveAddress(double lat, double lng) async {
    if (mounted) setState(() => _resolvingAddress = true);
    try {
      final place = await GeoPlace.reverse(lat, lng);
      if (!mounted) return;
      setState(() {
        _geoAddress = place;
        final best = place?.bestAddress ?? '';
        if (_precise && best.isNotEmpty) _addrCtrl.text = best;
      });
    } catch (_) {
      // 地址反查失败不影响选点
    } finally {
      if (mounted) setState(() => _resolvingAddress = false);
    }
  }

  /// 地址框下面那行小字：直白告诉用户当前坐标到底可不可信
  String get _addrHint {
    final t = _addrCtrl.text.trim();
    if (t.isEmpty) return '可以打字填地址，也可以点右边的准星读当前位置';
    if (_geocoding) return '正在把你填的地址解析成位置…';
    if (_precise) return '已按当前位置定位，导航会直接按坐标走';
    return '导航时会按这段地址搜索（之前点选的坐标不再使用）';
  }

  Future<void> _submit() async {
    final sp = Provider.of<SessionProvider>(context, listen: false);
    if (ApiConfig.enabled && !sp.isLoggedIn) {
      Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => const AuthScreen()));
      return;
    }
    if (_nameCtrl.text.trim().isEmpty) {
      CenterToast.show(context, '请填写野钓点名称');
      return;
    }

    final addrText = _addrCtrl.text.trim();

    // —— 位置来源优先级 ——
    //   1. 刚定位 / 刚在地图上点过（_precise=true）：坐标就是钓位，直接用
    //   2. 用户手打了地址（_precise=false）：先把文字地址送去后端解析成坐标，
    //      解析出来的只到街道级，所以 coord_precise 记 0，详情页导航会改用地址搜
    //   3. 既没点位置、地址也解析不出来：拦下来让用户点一下地图
    double? lat = _picked?.latitude;
    double? lng = _picked?.longitude;
    bool precise = _precise;

    if (addrText.isNotEmpty && !_precise) {
      if (mounted) setState(() => _geocoding = true);
      final g = await SpotService.geocodeAddress(addrText);
      if (mounted) setState(() => _geocoding = false);
      if (!mounted) return;
      if (g != null && g.valid) {
        lat = g.lat;
        lng = g.lng;
        precise = false; // 地址解析 = 街道级，不算精确坐标
      } else if (lat == null) {
        CenterToast.show(
            context, '这个地址没能解析成位置，请点「用当前位置」或在地图上点一下');
        return;
      } else {
        // 有之前的坐标但地址解析失败：照常提交，只是标记为不精确，
        // 导航时会用文字地址而不是这个旧坐标
        precise = false;
      }
    }

    if (lat == null || lng == null) {
      CenterToast.show(context, '请填写详细地址，或在地图上点选位置');
      return;
    }

    setState(() => _submitting = true);
    try {
      await SpotService.addSpot(
        name: _nameCtrl.text.trim(),
        type: '野钓',
        description: _descCtrl.text.trim(),
        lat: lat,
        lng: lng,
        kind: 'wild', // 野钓点：保存后直接对全员展示
        fish: _fishCtrl.text.trim(),
        address: addrText.isNotEmpty ? addrText : (_geoAddress?.bestAddress ?? ''),
        coordPrecise: precise,
      );
      if (mounted) {
        RefreshBus.bumpFeed();
        CenterToast.show(
          context,
          precise
              ? '标记成功！所有钓友都能在卫星地图上看到'
              : '标记成功！已按你填的地址定位（导航时会按地址搜索）',
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        CenterToast.show(context, '保存失败：$e');
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // 已选坐标转 GCJ-02 用于在高德卫星图上展示
    final pickedGcj = _picked == null
        ? null
        : LatLng(CoordTransform.wgs84ToGcj02(_picked!.latitude,
                _picked!.longitude)[0],
            CoordTransform.wgs84ToGcj02(
                _picked!.latitude, _picked!.longitude)[1]);

    return Scaffold(
      appBar: AppBar(title: const Text('标记野钓点')),
      body: Column(
        children: [
          // —— 卫星地图（点选微调位置） ——
          Expanded(
            flex: 5,
            child: Stack(
              children: [
                FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: _defaultCenter,
                    initialZoom: 8,
                    onTap: (_, point) {
                      // 高德底图是 GCJ-02，点选后转回 WGS-84 存储
                      final w = CoordTransform.gcj02ToWgs84(
                          point.latitude, point.longitude);
                      final p = LatLng(w[0], w[1]);
                      setState(() {
                        _picked = p;
                        _precise = true; // 用户亲手点的位置，可信
                      });
                      _resolveAddress(p.latitude, p.longitude);
                    },
                  ),
                  children: [
                    // 高德卫星影像
                    TileLayer(
                      urlTemplate:
                          'https://webst01.is.autonavi.com/appmaptile?x={x}&y={y}&z={z}&lang=zh_cn&size=1&scale=1&style=8',
                      userAgentPackageName: 'com.example.fishing_app',
                    ),
                    // 高德路网标注（半透明叠加）
                    TileLayer(
                      urlTemplate:
                          'https://webst01.is.autonavi.com/appmaptile?x={x}&y={y}&z={z}&lang=zh_cn&size=1&scale=1&style=6',
                      userAgentPackageName: 'com.example.fishing_app',
                    ),
                    if (pickedGcj != null)
                      MarkerLayer(
                        markers: [
                          if (_myLocation != null)
                            Marker(
                              point: _myLocation!,
                              width: 24,
                              height: 24,
                              alignment: Alignment.center,
                              child: const MyLocationMarker(),
                            ),
                          Marker(
                            point: pickedGcj,
                            width: 72,
                            height: 60,
                            alignment: Alignment.center,
                            child: const SpotMapMarker(
                              color: AppTheme.danger,
                              label: '钓点',
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
                // 顶部提示
                Positioned(
                  top: 12,
                  left: 12,
                  right: 12,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.92),
                      borderRadius: BorderRadius.circular(8),
                      boxShadow: const [
                        BoxShadow(
                            color: Colors.black12,
                            blurRadius: 4,
                            offset: Offset(0, 2))
                      ],
                    ),
                    child: Text(
                      // ★ 这里原来用「📍 / 👆」当项目符号。emoji 依赖系统的
                      //   NotoColorEmoji 字体，ROM 精简过或老 Android 上直接
                      //   渲染成小方块 —— 用户看到的就是「定位那行有乱码」。
                      //   App 自己的文案一律不用 emoji，要图形就用 Icon。
                      _picked == null
                          ? _locating
                              ? '正在读取当前位置…'
                              : '点地图微调位置 · 蓝点=我的位置 · 红标=钓点'
                          : _geoAddress == null
                              ? _resolvingAddress
                                  ? '已选钓点，正在解析地址…'
                                  : '已选钓点：${_picked!.latitude.toStringAsFixed(4)}, '
                                      '${_picked!.longitude.toStringAsFixed(4)}'
                              : '已选钓点：${_geoAddress!.bestAddress}',
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                ),
                // 重新定位按钮
                Positioned(
                  bottom: 12,
                  right: 12,
                  child: FloatingActionButton.small(
                    backgroundColor: Colors.white,
                    foregroundColor: AppTheme.primary,
                    onPressed: _locating ? null : _useMyLocation,
                    tooltip: '使用我的位置',
                    child: _locating
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.my_location),
                  ),
                ),
              ],
            ),
          ),
          // —— 表单 ——
          Expanded(
            flex: 6,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: _nameCtrl,
                    decoration: const InputDecoration(
                      labelText: '野钓点名称',
                      hintText: '例如：富春江第三个洄湾',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  // v44：地址可以直接打字（给外地钓点用），也可以点准星读当前位置
                  TextField(
                    key: const ValueKey('spot_addr'),
                    controller: _addrCtrl,
                    // 用户一改地址，之前点选的坐标就不再对应这句话了，
                    // 必须降级成「不精确」，提交时按地址重新解析
                    onChanged: (_) {
                      if (_precise) setState(() => _precise = false);
                    },
                    decoration: InputDecoration(
                      labelText: '详细地址',
                      hintText: '省市区 + 乡镇 / 水库名，例如「河南省许昌市禹州市夏都街道」',
                      helperText: _addrHint,
                      helperMaxLines: 2,
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        tooltip: '用当前位置',
                        onPressed: _locating ? null : _useMyLocation,
                        icon: _locating
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.my_location, size: 20),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _fishCtrl,
                    decoration: const InputDecoration(
                      labelText: '主要鱼种（选填）',
                      hintText: '例如：鲫鱼、黄尾、鳊鱼',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _descCtrl,
                    maxLines: 3,
                    decoration: InputDecoration(
                      labelText: '说明（选填）',
                      hintText: '钓法、水深、注意事项…',
                      border: OutlineInputBorder(),
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.emoji_emotions_outlined,
                            size: 20, color: AppTheme.textSecondary),
                        tooltip: '表情',
                        onPressed: () =>
                            showEmojiSheet(context, _descCtrl),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  // 实时可见提示
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppTheme.dangerLight,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.visibility_outlined,
                            size: 15, color: AppTheme.danger),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '保存后立即展示给所有钓友，无需审核',
                            style: TextStyle(
                                fontSize: 12, color: AppTheme.dangerDark),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    height: 46,
                    child: ElevatedButton(
                      onPressed: _submitting ? null : _submit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.danger,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      child: _submitting
                          ? Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2, color: Colors.white),
                                ),
                                if (_geocoding) ...[
                                  const SizedBox(width: 10),
                                  const Text('正在解析地址…',
                                      style: TextStyle(
                                          fontSize: 14, color: Colors.white)),
                                ],
                              ],
                            )
                          : const Text('保存标记',
                              style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
