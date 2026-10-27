import 'dart:io';

import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../widgets/emoji_panel.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong2.dart';
import 'package:provider/provider.dart';

import '../services/api_client.dart';
import '../services/refresh_bus.dart';
import '../services/location_service.dart';
import '../services/spot_service.dart';
import '../services/session_provider.dart';
import '../services/api_config.dart';
import '../utils/coord_transform.dart';
import '../utils/geo_names.dart';
import 'auth_screen.dart';
import '../widgets/center_toast.dart';
import '../widgets/location_prompt.dart';
import '../widgets/spot_map_marker.dart';

/// 钓场 / 渔具店提交表单（图4）
/// 填写后提交后台审核，通过后才对其他用户展示。
///   venue=本地钓场  shop=渔具店
class PublishVenueScreen extends StatefulWidget {
  final String kind;
  const PublishVenueScreen({super.key, this.kind = 'venue'});

  @override
  State<PublishVenueScreen> createState() => _PublishVenueScreenState();
}

class _PublishVenueScreenState extends State<PublishVenueScreen> {
  final _mapController = MapController();
  final _nameCtrl = TextEditingController();
  final _addrCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _feeCtrl = TextEditingController();
  final _fishCtrl = TextEditingController();
  final _descCtrl = TextEditingController();

  String _type = '黑坑';
  double _rating = 4.0;
  final Set<String> _tags = {}; // 推荐 / 黑坑 / 电话认证 …
  final List<String> _envFiles = []; // 环境展示图（本地路径，最多 9 张）
  bool _delivery = false; // 渔具店是否支持外送
  bool _locatingAddr = false; // 定位填址中
  bool _uploading = false;
  bool _submitting = false;

  LatLng? _picked; // WGS-84 坐标（存储用）
  LatLng? _myLocation; // 当前定位（GCJ-02 之上展示用，仅作「我在哪」指示）
  // 默认中心：杭州（GCJ-02，高德底图坐标系）
  final LatLng _defaultCenter = const LatLng(30.2741, 120.1551);

  bool get _isShop => widget.kind == 'shop';
  String get _pageTitle => _isShop ? '添加渔具店' : '添加本地钓场';

  // 「野钓场」已删：野钓点有独立的地理标注入口（钓点页「野钓钓点」Tab），
  // 本地钓场再留一个「野钓场」类型只会让两套数据混在一起。
  List<String> get _typeOptions =>
      _isShop ? const ['渔具店'] : const ['黑坑', '路亚', '海钓'];

  static const List<String> _tagOptions = ['推荐', '黑坑', '电话认证', '环境好', '停车方便'];

  @override
  void initState() {
    super.initState();
    _type = _typeOptions.first;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _addrCtrl.dispose();
    _phoneCtrl.dispose();
    _feeCtrl.dispose();
    _fishCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  /// 选环境展示图（多选，最多 9 张）
  Future<void> _pickEnvImages() async {
    final remain = 9 - _envFiles.length;
    if (remain <= 0) {
      CenterToast.show(context, '最多 9 张环境图');
      return;
    }
    final picked = await ImagePicker()
        .pickMultiImage(maxWidth: 1080, limit: remain);
    if (picked.isNotEmpty) {
      setState(() => _envFiles.addAll(picked.map((x) => x.path)));
    }
  }

  /// 定位填址：读取当前位置 → 移动地图并记下坐标 → 反查中文地址填入「详细地址」
  /// 这样点「获取定位」后，顶部地图会直接切到定位到的位置，而不是只填文字。
  Future<void> _fillAddressByLocation() async {
    if (_locatingAddr) return;
    setState(() => _locatingAddr = true);
    try {
      final pos = await LocationService.determinePosition();
      final p = LatLng(pos.latitude, pos.longitude); // WGS-84
      // 高德底图是 GCJ-02，居中时先转换
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
      final p = LatLng(pos.latitude, pos.longitude); // WGS-84
      // 高德底图是 GCJ-02，居中时先转换
      final g = CoordTransform.wgs84ToGcj02(pos.latitude, pos.longitude);
      _mapController.move(LatLng(g[0], g[1]), 15);
      if (!mounted) return;
      setState(() {
        _picked = p;
        _myLocation = LatLng(g[0], g[1]);
      });
    } on LocationException catch (e) {
      if (mounted) {
        LocationPrompt.showError(context, e);
      }
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
      CenterToast.show(context, '请填写名称');
      return;
    }
    if (_picked == null) {
      CenterToast.show(context, '请在地图上点选位置');
      return;
    }
    setState(() => _submitting = true);
    try {
      // 上传环境展示图（第一张兼作封面）
      var cover = '';
      final images = <String>[];
      if (_envFiles.isNotEmpty) {
        setState(() => _uploading = true);
        try {
          images.addAll(
              await ApiClient.uploadImages(_envFiles));
          if (images.isNotEmpty) cover = images.first;
        } catch (_) {/* 环境图上传失败不阻塞提交 */}
        if (mounted) setState(() => _uploading = false);
      }
      await SpotService.addSpot(
        name: _nameCtrl.text.trim(),
        type: _type,
        description: _descCtrl.text.trim(),
        lat: _picked!.latitude,
        lng: _picked!.longitude,
        kind: widget.kind,
        address: _addrCtrl.text.trim(),
        fee: _feeCtrl.text.trim(),
        fish: _fishCtrl.text.trim(),
        tags: _tags.join(','),
        cover: cover,
        images: images,
        phone: _phoneCtrl.text.trim(),
        rating: _rating,
        delivery: _isShop && _delivery,
      );
      if (mounted) {
        // 审核提示
        await showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('提交成功'),
            content: Text(
                '你提交的${_isShop ? '渔具店' : '钓场'}已进入审核，\n审核通过后将展示给所有钓友，\n请耐心等待。'),
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
      if (mounted) {
        CenterToast.show(context, '提交失败：$e');
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // 已选坐标转 GCJ-02，用于在高德底图上正确叠加
    final pickedGcj = _picked == null
        ? null
        : LatLng(
            CoordTransform.wgs84ToGcj02(
                _picked!.latitude, _picked!.longitude)[0],
            CoordTransform.wgs84ToGcj02(
                _picked!.latitude, _picked!.longitude)[1]);

    return Scaffold(
      appBar: AppBar(title: Text(_pageTitle)),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          // —— 位置选择（地图点选） ——
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
                      // 高德底图为 GCJ-02，点选后转回 WGS-84 存储
                      final w = CoordTransform.gcj02ToWgs84(
                          point.latitude, point.longitude);
                      setState(() => _picked = LatLng(w[0], w[1]));
                    },
                  ),
                  children: [
                    // 高德卫星影像
                    TileLayer(
                      urlTemplate:
                          'https://webst01.is.autonavi.com/appmaptile?x={x}&y={y}&z={z}&lang=zh_cn&size=1&scale=1&style=8',
                      userAgentPackageName: 'com.example.fishing_app',
                    ),
                    // 高德路网标注
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
                              label: '钓点',
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
                      // 去掉 👆：emoji 在没装彩色 emoji 字体的机器上是方块
                      _picked == null
                          ? '点击地图或点「获取定位」选择${_isShop ? '渔具店' : '钓点'}位置'
                          : '已选${_isShop ? '渔具店' : '钓点'}坐标（WGS84）：'
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
                // —— 环境展示图（最多 9 张，第一张兼作封面） ——
                const Text('环境展示图',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (var i = 0; i < _envFiles.length; i++)
                      Stack(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.file(File(_envFiles[i]),
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
                                  setState(() => _envFiles.removeAt(i)),
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
                    if (_envFiles.length < 9)
                      GestureDetector(
                        onTap: _pickEnvImages,
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
                Text('展示钓场环境实拍，最多 9 张，第一张将作为封面',
                    style: TextStyle(
                        fontSize: 11, color: Colors.grey.withOpacity(0.9))),
                const SizedBox(height: 16),
                // —— 名称 ——
                TextField(
                  controller: _nameCtrl,
                  decoration: InputDecoration(
                    labelText: _isShop ? '渔具店名称' : '钓场名称',
                    hintText: _isShop ? '例如：XX 路亚渔具店' : '例如：西溪路亚基地',
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                // —— 类型 ——
                DropdownButtonFormField<String>(
                  value: _type,
                  decoration: const InputDecoration(
                    labelText: '类型',
                    border: OutlineInputBorder(),
                  ),
                  items: _typeOptions
                      .map((t) =>
                          DropdownMenuItem(value: t, child: Text(t)))
                      .toList(),
                  onChanged: (v) => setState(() => _type = v!),
                ),
                const SizedBox(height: 12),
                // —— 标签（图4：推荐 / 黑坑 / 电话认证） ——
                const Text('标签（可多选）',
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
                // —— 星级 ——
                Row(
                  children: [
                    const Text('星级评分',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    const Spacer(),
                    Text(_rating.toStringAsFixed(1),
                        style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: AppTheme.star)),
                  ],
                ),
                Slider(
                  value: _rating,
                  min: 0,
                  max: 5,
                  divisions: 10,
                  activeColor: AppTheme.star,
                  onChanged: (v) => setState(() => _rating = v),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(
                      5,
                      (i) => Icon(
                            i < _rating.round()
                                ? Icons.star
                                : Icons.star_border,
                            color: AppTheme.star,
                            size: 22,
                          )),
                ),
                const SizedBox(height: 12),
                // —— 地址（可一键定位填址） ——
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
                // —— 收费 ——
                TextField(
                  controller: _feeCtrl,
                  decoration: InputDecoration(
                    labelText: _isShop ? '外送/运费说明（选填）' : '收费说明（选填）',
                    hintText: _isShop
                        ? '例如：3 公里内免运费，超出 5 元'
                        : '例如：正钓 200 元/4h，偷驴 100 元',
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                // —— 渔具店：是否支持外送 ——
                if (_isShop)
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
                              Text('支持外送',
                                  style: TextStyle(
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.w600)),
                              Text('同城可送货/闪送，详情页会给钓友标注',
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
                if (_isShop) const SizedBox(height: 12),
                // —— 鱼种（渔具店则改为经营范围） ——
                TextField(
                  controller: _fishCtrl,
                  decoration: InputDecoration(
                    labelText: _isShop ? '经营范围（选填）' : '主要鱼种（选填）',
                    hintText: _isShop ? '例如：竿、轮、饵料' : '例如：鲫鱼、鲤鱼、鲈鱼',
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                // —— 简介 ——
                TextField(
                  controller: _descCtrl,
                  maxLines: 3,
                  decoration: InputDecoration(
                    labelText: '简介（选填）',
                    hintText: '环境、钓法、注意事项…',
                    border: OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.emoji_emotions_outlined,
                          size: 20, color: AppTheme.textSecondary),
                      tooltip: '表情',
                      onPressed: () => showEmojiSheet(context, _descCtrl),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                // 审核提示
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppTheme.warningLight,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.info_outline,
                          size: 15, color: AppTheme.star),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '提交后需后台审核，通过才会展示给所有钓友',
                          style: TextStyle(
                              fontSize: 12, color: AppTheme.textSecondary),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                // —— 提交按钮 ——
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
                                const Text('上传封面中…',
                                    style: TextStyle(fontSize: 13)),
                              ],
                            ],
                          )
                        : const Text('提交审核',
                            style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold)),
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
