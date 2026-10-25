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
  Future<void> _resolveAddress(double lat, double lng) async {
    if (mounted) setState(() => _resolvingAddress = true);
    try {
      final place = await GeoPlace.reverse(lat, lng);
      if (mounted) setState(() => _geoAddress = place);
    } catch (_) {
      // 地址反查失败不影响选点
    } finally {
      if (mounted) setState(() => _resolvingAddress = false);
    }
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
    if (_picked == null) {
      CenterToast.show(context, '请先定位或在地图上点选位置');
      return;
    }
    setState(() => _submitting = true);
    try {
      await SpotService.addSpot(
        name: _nameCtrl.text.trim(),
        type: '野钓',
        description: _descCtrl.text.trim(),
        lat: _picked!.latitude,
        lng: _picked!.longitude,
        kind: 'wild', // 野钓点：保存后直接对全员展示
        fish: _fishCtrl.text.trim(),
        address: _geoAddress?.bestAddress ?? '',
      );
      if (mounted) {
      RefreshBus.bumpFeed();
        CenterToast.show(context, '标记成功！所有钓友都能在卫星地图上看到');
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
                      setState(() => _picked = p);
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
                      _picked == null
                          ? _locating
                              ? '📍 正在读取当前位置…'
                              : '👆 点地图微调位置 · 蓝点=我的位置 · 红标=钓点'
                          : _geoAddress == null
                              ? _resolvingAddress
                                  ? '📍 已选钓点，正在解析地址…'
                                  : '📍 已选钓点：${_picked!.latitude.toStringAsFixed(4)}, '
                                      '${_picked!.longitude.toStringAsFixed(4)}'
                              : '📍 已选钓点：${_geoAddress!.bestAddress}',
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
                    foregroundColor: AppTheme.accent,
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
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white),
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
