import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong2.dart';
import 'package:provider/provider.dart';

import '../app_theme.dart';
import '../services/api_client.dart';
import '../services/api_config.dart';
import '../services/location_service.dart';
import '../services/refresh_bus.dart';
import '../services/session_provider.dart';
import '../services/spot_service.dart';
import '../utils/coord_transform.dart';
import '../utils/geo_names.dart';
import '../widgets/center_toast.dart';
import '../widgets/emoji_panel.dart';
import '../widgets/location_prompt.dart';
import '../widgets/spot_map_marker.dart';
import 'auth_screen.dart';

/// 添加渔具店（独立页面）
///
/// 和「添加本地钓场」不是一张表：渔具店要的是
///   店名 / 门店或流动 / 卖什么（饵料·鱼竿·鱼线）/ 能不能配送 / 电话地址。
/// 所以单独一页，别把钓场那套「鱼种 / 收费」硬塞进来。
/// 提交后进后台审核，通过才展示在「钓具店」Tab。
class PublishShopScreen extends StatefulWidget {
  const PublishShopScreen({super.key});

  @override
  State<PublishShopScreen> createState() => _PublishShopScreenState();
}

class _PublishShopScreenState extends State<PublishShopScreen> {
  final _mapController = MapController();
  final _nameCtrl = TextEditingController();
  final _addrCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _shipCtrl = TextEditingController(); // 配送/运费说明
  final _descCtrl = TextEditingController();

  /// 门店 = 有固定铺面；流动 = 赶集/上门/路亚车
  String _type = '门店';

  /// 卖什么：饵料 / 鱼竿 / 鱼线 —— 默认全选（绝大多数渔具店都卖这三样）
  final Set<String> _tags = {'饵料', '鱼竿', '鱼线'};

  final List<String> _photos = []; // 门店照片（第一张作封面，最多 9 张）

  bool _delivery = false; // 是否可配送
  bool _locatingAddr = false;
  bool _uploading = false;
  bool _submitting = false;

  LatLng? _picked; // WGS-84 坐标（存储用）
  LatLng? _myLocation; // 当前定位（GCJ-02，仅作「我在哪」指示）
  final LatLng _defaultCenter = const LatLng(30.2741, 120.1551);

  static const List<String> _tagOptions = ['饵料', '鱼竿', '鱼线'];

  @override
  void dispose() {
    _nameCtrl.dispose();
    _addrCtrl.dispose();
    _phoneCtrl.dispose();
    _shipCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickPhotos() async {
    final remain = 9 - _photos.length;
    if (remain <= 0) {
      CenterToast.show(context, '最多 9 张门店照片');
      return;
    }
    final picked =
        await ImagePicker().pickMultiImage(maxWidth: 1080, limit: remain);
    if (picked.isNotEmpty) {
      setState(() => _photos.addAll(picked.map((x) => x.path)));
    }
  }

  /// 定位填址：读当前位置 → 地图居中 → 反查中文地址
  Future<void> _fillAddressByLocation() async {
    if (_locatingAddr) return;
    setState(() => _locatingAddr = true);
    try {
      final pos = await LocationService.determinePosition();
      final p = LatLng(pos.latitude, pos.longitude);
      final g = CoordTransform.wgs84ToGcj02(pos.latitude, pos.longitude);
      _mapController.move(LatLng(g[0], g[1]), 15);
      if (!mounted) return;
      setState(() {
        _picked = p;
        _myLocation = LatLng(g[0], g[1]);
      });
      final r = await GeoNames.reverse(pos.latitude, pos.longitude);
      if (!mounted) return;
      _addrCtrl.text = (r?['display'] as String?) ?? '';
      CenterToast.show(context, '已定位到当前位置');
    } on LocationException catch (e) {
      if (mounted) LocationPrompt.showError(context, e);
    } catch (_) {
      if (mounted) CenterToast.show(context, '定位失败，请手动填写地址');
    } finally {
      if (mounted) setState(() => _locatingAddr = false);
    }
  }

  Future<void> _useMyLocation() async {
    try {
      final pos = await LocationService.determinePosition();
      final p = LatLng(pos.latitude, pos.longitude);
      final g = CoordTransform.wgs84ToGcj02(pos.latitude, pos.longitude);
      _mapController.move(LatLng(g[0], g[1]), 15);
      if (!mounted) return;
      setState(() {
        _picked = p;
        _myLocation = LatLng(g[0], g[1]);
      });
    } on LocationException catch (e) {
      if (mounted) LocationPrompt.showError(context, e);
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
      CenterToast.show(context, '请填写渔具店名称');
      return;
    }
    if (_picked == null) {
      CenterToast.show(context, '请在地图上点选店铺位置');
      return;
    }
    if (_tags.isEmpty) {
      CenterToast.show(context, '请至少选择一个售卖品类');
      return;
    }
    setState(() => _submitting = true);
    try {
      var cover = '';
      final images = <String>[];
      if (_photos.isNotEmpty) {
        setState(() => _uploading = true);
        try {
          images.addAll(await ApiClient.uploadImages(_photos));
          if (images.isNotEmpty) cover = images.first;
        } catch (_) {/* 照片上传失败不阻塞提交 */}
        if (mounted) setState(() => _uploading = false);
      }
      await SpotService.addSpot(
        name: _nameCtrl.text.trim(),
        type: _type,
        description: _descCtrl.text.trim(),
        lat: _picked!.latitude,
        lng: _picked!.longitude,
        kind: 'shop',
        address: _addrCtrl.text.trim(),
        // 渔具店没有「收费」这个概念：这个字段留着放配送/运费说明
        fee: _shipCtrl.text.trim(),
        // 详情页「售卖种类」读的是 fish 字段，这里写选中的品类
        fish: _tags.join('、'),
        tags: _tags.join(','),
        cover: cover,
        images: images,
        phone: _phoneCtrl.text.trim(),
        delivery: _delivery,
      );
      if (mounted) {
        await showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('提交成功'),
            content: const Text('你提交的渔具店已进入审核，\n审核通过后将展示给所有钓友，\n请耐心等待。'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('知道了'),
              ),
            ],
          ),
        );
        RefreshBus.bumpSpots();
        if (mounted) Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) CenterToast.show(context, '提交失败：$e');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pickedGcj = _picked == null
        ? null
        : LatLng(
            CoordTransform.wgs84ToGcj02(
                _picked!.latitude, _picked!.longitude)[0],
            CoordTransform.wgs84ToGcj02(
                _picked!.latitude, _picked!.longitude)[1]);

    return Scaffold(
      appBar: AppBar(title: const Text('添加渔具店')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          // —— 位置选择 ——
          SizedBox(
            height: 200,
            child: Stack(
              children: [
                FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: _defaultCenter,
                    initialZoom: 8,
                    onTap: (_, point) {
                      final w = CoordTransform.gcj02ToWgs84(
                          point.latitude, point.longitude);
                      setState(() => _picked = LatLng(w[0], w[1]));
                    },
                  ),
                  children: [
                    TileLayer(
                      urlTemplate:
                          'https://webst01.is.autonavi.com/appmaptile?x={x}&y={y}&z={z}&lang=zh_cn&size=1&scale=1&style=8',
                      userAgentPackageName: 'com.example.fishing_app',
                    ),
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
                              color: AppTheme.primary,
                              label: '店铺',
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
                Positioned(
                  top: 10,
                  left: 12,
                  right: 12,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 7),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.92),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      _picked == null
                          ? '点击地图或点「获取定位」选择店铺位置'
                          : '已选店铺坐标（WGS84）：'
                              '${_picked!.latitude.toStringAsFixed(5)}, '
                              '${_picked!.longitude.toStringAsFixed(5)}',
                      style: const TextStyle(fontSize: 12.5),
                    ),
                  ),
                ),
                Positioned(
                  bottom: 10,
                  right: 12,
                  child: FloatingActionButton.small(
                    backgroundColor: Colors.white,
                    foregroundColor: AppTheme.primary,
                    tooltip: '使用我的位置',
                    onPressed: _useMyLocation,
                    child: const Icon(Icons.my_location),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // —— 门店照片 ——
                const Text('门店照片',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (var i = 0; i < _photos.length; i++)
                      Stack(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.file(File(_photos[i]),
                                width: 76, height: 76, fit: BoxFit.cover),
                          ),
                          Positioned(
                            right: -6,
                            top: -6,
                            child: IconButton(
                              visualDensity: VisualDensity.compact,
                              icon: const Icon(Icons.cancel,
                                  size: 20, color: Colors.black54),
                              onPressed: () =>
                                  setState(() => _photos.removeAt(i)),
                            ),
                          ),
                          if (i == 0)
                            const Positioned(
                              left: 4,
                              bottom: 4,
                              child: Text('封面',
                                  style: TextStyle(
                                      fontSize: 9,
                                      color: Colors.white,
                                      backgroundColor: Colors.black45)),
                            ),
                        ],
                      ),
                    if (_photos.length < 9)
                      GestureDetector(
                        onTap: _pickPhotos,
                        child: Container(
                          width: 76,
                          height: 76,
                          decoration: BoxDecoration(
                            color: AppTheme.primarySoft,
                            border:
                                Border.all(color: AppTheme.primaryBorder),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.add_photo_alternate_outlined,
                                  color: AppTheme.primary, size: 24),
                              SizedBox(height: 4),
                              Text('添加图片',
                                  style: TextStyle(
                                      fontSize: 10, color: Colors.grey)),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                Text('拍店面/货架，最多 9 张，第一张作为封面',
                    style: TextStyle(
                        fontSize: 11, color: Colors.grey.withOpacity(0.9))),
                const SizedBox(height: 16),

                // —— 店名 ——
                TextField(
                  controller: _nameCtrl,
                  decoration: const InputDecoration(
                    labelText: '渔具店名字',
                    hintText: '例如：老李渔具（城东店）',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),

                // —— 类型：门店 / 流动 ——
                DropdownButtonFormField<String>(
                  value: _type,
                  decoration: const InputDecoration(
                    labelText: '类型',
                    border: OutlineInputBorder(),
                  ),
                  items: const ['门店', '流动']
                      .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                      .toList(),
                  onChanged: (v) => setState(() => _type = v!),
                ),
                const SizedBox(height: 4),
                Text(_type == '门店' ? '有固定铺面，钓友可上门' : '赶集/上门送货/路亚车，无固定门面',
                    style: const TextStyle(
                        fontSize: 11, color: AppTheme.textSecondary)),
                const SizedBox(height: 14),

                // —— 标签：卖什么 ——
                const Text('标签（卖什么，可多选）',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: _tagOptions
                      .map((t) => FilterChip(
                            label: Text(t),
                            selected: _tags.contains(t),
                            onSelected: (v) => setState(() {
                              v ? _tags.add(t) : _tags.remove(t);
                            }),
                          ))
                      .toList(),
                ),
                const SizedBox(height: 14),

                // —— 是否可配送 ——
                Container(
                  padding: const EdgeInsets.fromLTRB(12, 2, 8, 2),
                  decoration: BoxDecoration(
                    color: _delivery
                        ? AppTheme.primaryLight
                        : AppTheme.primarySoft,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: _delivery
                          ? AppTheme.primary.withOpacity(.45)
                          : AppTheme.divider,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.delivery_dining,
                          size: 19,
                          color: _delivery
                              ? AppTheme.primary
                              : AppTheme.textSecondary),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('是否可配送',
                                style: TextStyle(
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w600)),
                            Text('同城送货/闪送，详情页会给钓友标注',
                                style: TextStyle(
                                    fontSize: 11,
                                    color: AppTheme.textSecondary)),
                          ],
                        ),
                      ),
                      Switch(
                        value: _delivery,
                        onChanged: (v) => setState(() => _delivery = v),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _shipCtrl,
                  decoration: const InputDecoration(
                    labelText: '配送说明（选填）',
                    hintText: '例如：3 公里内免运费，超出 5 元',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),

                // —— 地址 ——
                TextField(
                  controller: _addrCtrl,
                  decoration: InputDecoration(
                    labelText: '详细地址',
                    hintText: '例如：杭州市西湖区 XX 路 88 号',
                    border: const OutlineInputBorder(),
                    suffixIcon: _locatingAddr
                        ? const Padding(
                            padding: EdgeInsets.all(12),
                            child: SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2)),
                          )
                        : IconButton(
                            tooltip: '定位填址',
                            icon: const Icon(Icons.my_location,
                                color: AppTheme.primary, size: 22),
                            onPressed: _fillAddressByLocation,
                          ),
                  ),
                ),
                const SizedBox(height: 12),

                // —— 电话 ——
                TextField(
                  controller: _phoneCtrl,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: '联系电话（选填）',
                    hintText: '例如：13800001111',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),

                // —— 简介 ——
                TextField(
                  controller: _descCtrl,
                  maxLines: 3,
                  decoration: InputDecoration(
                    labelText: '店铺介绍（选填）',
                    hintText: '主营品牌、营业时间、有什么特色…',
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.emoji_emotions_outlined,
                          size: 20, color: AppTheme.textSecondary),
                      tooltip: '表情',
                      onPressed: () => showEmojiSheet(context, _descCtrl),
                    ),
                  ),
                ),
                const SizedBox(height: 10),

                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppTheme.warningLight,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.info_outline, size: 15, color: AppTheme.warning),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text('提交后需后台审核，通过才会展示给所有钓友',
                            style: TextStyle(
                                fontSize: 12,
                                color: AppTheme.textSecondary)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),

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
                        ? Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white),
                              ),
                              if (_uploading) ...[
                                const SizedBox(width: 10),
                                const Text('上传照片中…',
                                    style: TextStyle(fontSize: 13)),
                              ],
                            ],
                          )
                        : const Text('提交审核',
                            style: TextStyle(
                                fontSize: 16, fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
