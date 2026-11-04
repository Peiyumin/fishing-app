import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';

import '../app_theme.dart';
import '../models/official.dart';
import '../services/api_client.dart';
import '../services/geo_place.dart';
import '../services/location_service.dart';
import '../services/official_service.dart';
import '../utils/coord_transform.dart';
import '../widgets/center_toast.dart';
import '../widgets/location_prompt.dart';
import '../widgets/spot_map_marker.dart';

/// 钓点编辑（v41 · 官方工作台）
///
/// 批量导入的钓点最常见的三个毛病，这里都能就地改掉：
///   · 名字打错 / 分类错 —— 直接改文本；
///   · 定位偏到隔壁村 —— 地图上点一下，坐标跟着走，地址也能按坐标反查补上；
///   · 一张图都没有 —— 相册选图（最多 9 张），提交时上传后一起存。
///
/// 保存是**全字段覆盖**：页面上看到的每个值都会写回库，
/// 所以「只改名字」也得把所有字段一起带上（不能只发 diff，
/// 否则后端拿不到 lat/lng 会把定位清空 —— 那正是这类工具最容易闯的祸）。
class OfficialSpotEditScreen extends StatefulWidget {
  final String id;

  /// 列表里已有的那条，用来先把标题画出来（不全，全字段走接口取）
  final OfficialSpot? initial;

  const OfficialSpotEditScreen({super.key, required this.id, this.initial});

  @override
  State<OfficialSpotEditScreen> createState() => _OfficialSpotEditScreenState();
}

/// 编辑器里的一张图：本机文件（提交前上传）或已存在的远程地址
class _DraftImage {
  final String path;
  final bool local;
  _DraftImage(this.path, {required this.local});
}

/// 是不是已经在服务器上的图片地址（非 http 一律当本机文件）
bool _isRemote(String p) =>
    p.startsWith('http://') || p.startsWith('https://');

class _OfficialSpotEditScreenState extends State<OfficialSpotEditScreen> {
  final _mapController = MapController();
  final _picker = ImagePicker();

  final _nameCtrl = TextEditingController();
  final _typeCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _feeCtrl = TextEditingController();
  final _fishCtrl = TextEditingController();
  final _tagsCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();

  OfficialSpotDraft? _draft;
  List<_DraftImage> _images = [];
  String _kind = 'venue';
  int _status = 1;
  double _rating = 0;
  double _lat = 0;
  double _lng = 0;
  bool _delivery = false;

  bool _loading = true;
  bool _saving = false;
  bool _locating = false;
  String? _error;

  static const _defaultCenter = LatLng(30.2741, 120.1551);
  static const int _imageMax = 9;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _typeCtrl.dispose();
    _descCtrl.dispose();
    _addressCtrl.dispose();
    _feeCtrl.dispose();
    _fishCtrl.dispose();
    _tagsCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final d = await OfficialService.spot(widget.id);
      if (!mounted) return;
      setState(() {
        _draft = d;
        _nameCtrl.text = d.name;
        _typeCtrl.text = d.type;
        _descCtrl.text = d.description;
        _addressCtrl.text = d.address;
        _feeCtrl.text = d.fee;
        _fishCtrl.text = d.fish;
        _tagsCtrl.text = d.tags;
        _phoneCtrl.text = d.phone;
        _kind = d.kind;
        _status = d.status;
        _rating = d.rating;
        _lat = d.lat;
        _lng = d.lng;
        _delivery = d.delivery;
        _images = d.images
            .map((u) => _DraftImage(u, local: !_isRemote(u)))
            .toList();
        _loading = false;
      });
      // 有坐标就把地图挪过去（库里存 WGS-84，底图要 GCJ-02）
      if (d.lat != 0 && d.lng != 0) {
        final g = CoordTransform.wgs84ToGcj02(d.lat, d.lng);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          try {
            _mapController.move(LatLng(g[0], g[1]), 15);
          } catch (_) {
            // 地图还没挂载好时忽略，用户手动拖也能改
          }
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = _humanError(e);
      });
    }
  }

  String _humanError(Object e) {
    if (ApiClient.asNetError(e) != null) return '网络不太好，请稍后再试';
    if (e is ApiException) {
      if (e.status == 404) return '钓点不存在，可能已被删除';
      return e.message;
    }
    return '加载失败：$e';
  }

  /// 地图点选：底图 GCJ-02 → 存 WGS-84
  void _pickPoint(LatLng p) {
    final w = CoordTransform.gcj02ToWgs84(p.latitude, p.longitude);
    setState(() {
      _lat = w[0];
      _lng = w[1];
    });
  }

  Future<void> _useMyLocation() async {
    setState(() => _locating = true);
    try {
      final pos = await LocationService.determinePosition();
      final g = CoordTransform.wgs84ToGcj02(pos.latitude, pos.longitude);
      try {
        _mapController.move(LatLng(g[0], g[1]), 15);
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _lat = pos.latitude;
        _lng = pos.longitude;
      });
    } on LocationException catch (e) {
      if (mounted) LocationPrompt.showError(context, e);
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  /// 按当前坐标反查中文地址（只在地址为空时填充，不覆盖人工改过的）
  Future<void> _fillAddress() async {
    if (_lat == 0 && _lng == 0) {
      CenterToast.show(context, '请先在地图上选点');
      return;
    }
    try {
      final place = await GeoPlace.reverse(_lat, _lng);
      if (!mounted) return;
      final addr = place?.bestAddress ?? '';
      if (addr.isEmpty) {
        CenterToast.show(context, '没能解析出地址，可以手动填写');
        return;
      }
      setState(() => _addressCtrl.text = addr);
      CenterToast.show(context, '地址已按坐标补全');
    } catch (_) {
      if (mounted) CenterToast.show(context, '地址解析失败，可以手动填写');
    }
  }

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
    } catch (_) {
      if (mounted) CenterToast.show(context, '选图失败，请检查相册权限');
    }
  }

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
    } catch (_) {
      if (mounted) CenterToast.show(context, '拍照失败，请检查相机权限');
    }
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      CenterToast.show(context, '钓点名称不能为空');
      return;
    }
    if (_lat == 0 && _lng == 0) {
      CenterToast.show(context, '请在地图上选择钓点位置');
      return;
    }
    setState(() => _saving = true);
    try {
      final locals = _images.where((e) => e.local).map((e) => e.path).toList();
      List<String> uploaded = const [];
      if (locals.isNotEmpty) {
        uploaded = await ApiClient.uploadImages(locals, watermark: true);
        if (uploaded.length != locals.length) {
          throw const ApiException('图片上传没有全部成功，请重试');
        }
      }
      var cursor = 0;
      final urls = <String>[];
      for (final img in _images) {
        if (img.local) {
          urls.add(uploaded[cursor++]);
        } else {
          urls.add(img.path);
        }
      }

      final draft = (_draft ?? OfficialSpotDraft()).copyWithFields(
        name: name,
        kind: _kind,
        type: _typeCtrl.text.trim().isEmpty ? '野钓' : _typeCtrl.text.trim(),
        status: _status,
        description: _descCtrl.text.trim(),
        address: _addressCtrl.text.trim(),
        fee: _feeCtrl.text.trim(),
        fish: _fishCtrl.text.trim(),
        tags: _tagsCtrl.text.trim(),
        phone: _phoneCtrl.text.trim(),
        delivery: _delivery,
        lat: _lat,
        lng: _lng,
        rating: _rating,
        images: urls,
      );
      await OfficialService.saveSpot(draft);
      if (!mounted) return;
      CenterToast.show(context, '已保存', icon: Icons.check_circle_outline);
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      CenterToast.show(context, _humanError(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = _draft?.name.isNotEmpty == true
        ? _draft!.name
        : (widget.initial?.name ?? '钓点');
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
        elevation: 0,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
          : _error != null
              ? _errorView()
              : ListView(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
                  children: [
                    _mapCard(),
                    const SizedBox(height: 10),
                    _basicCard(),
                    const SizedBox(height: 10),
                    _contactCard(),
                    const SizedBox(height: 10),
                    _imageCard(),
                    const SizedBox(height: 10),
                    _statusCard(),
                  ],
                ),
      bottomNavigationBar: _loading || _error != null
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
                child: SizedBox(
                  height: 46,
                  child: ElevatedButton(
                    onPressed: _saving ? null : _save,
                    child: _saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : const Text('保存修改'),
                  ),
                ),
              ),
            ),
    );
  }

  Widget _errorView() => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline,
                size: 40, color: AppTheme.textTertiary),
            const SizedBox(height: 10),
            Text(_error ?? '',
                style: const TextStyle(
                    fontSize: 12.5, color: AppTheme.textSecondary)),
            const SizedBox(height: 10),
            TextButton(onPressed: _load, child: const Text('重新加载')),
          ],
        ),
      );

  Widget _card({required Widget child, EdgeInsets? padding}) => Container(
        padding: padding ?? const EdgeInsets.fromLTRB(14, 12, 14, 14),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(AppTheme.radiusMd),
          boxShadow: AppTheme.lightShadow,
        ),
        child: child,
      );

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(text,
            style: const TextStyle(
                fontSize: 12, fontWeight: FontWeight.w700, color: AppTheme.textSecondary)),
      );

  Widget _field(
    TextEditingController c, {
    String? hint,
    int maxLines = 1,
    int? maxLength,
    TextInputType? keyboard,
  }) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: TextField(
          controller: c,
          maxLines: maxLines,
          maxLength: maxLength,
          keyboardType: keyboard,
          style: const TextStyle(fontSize: 13.5),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle:
                const TextStyle(fontSize: 12.5, color: AppTheme.textTertiary),
            isDense: true,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            filled: true,
            fillColor: AppTheme.background,
            counterStyle:
                const TextStyle(fontSize: 10, color: AppTheme.textTertiary),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide.none,
            ),
          ),
        ),
      );

  /// 地图选点：点一下就把坐标挪过去，蓝点是我的位置
  Widget _mapCard() {
    final hasPoint = _lat != 0 || _lng != 0;
    final gcj = hasPoint
        ? CoordTransform.wgs84ToGcj02(_lat, _lng)
        : null;
    return _card(
      padding: const EdgeInsets.all(0),
      child: Column(
        children: [
          SizedBox(
            height: 190,
            child: ClipRRect(
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(AppTheme.radiusMd)),
              child: Stack(
                children: [
                  FlutterMap(
                    mapController: _mapController,
                    options: MapOptions(
                      initialCenter: gcj != null
                          ? LatLng(gcj[0], gcj[1])
                          : _defaultCenter,
                      initialZoom: hasPoint ? 15 : 8,
                      onTap: (_, point) => _pickPoint(point),
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
                      if (gcj != null)
                        MarkerLayer(
                          markers: [
                            Marker(
                              point: LatLng(gcj[0], gcj[1]),
                              width: 76,
                              height: 64,
                              alignment: Alignment.center,
                              child: const SpotMapMarker(
                                  color: AppTheme.danger, label: '钓点'),
                            ),
                          ],
                        ),
                    ],
                  ),
                  Positioned(
                    left: 10,
                    top: 10,
                    right: 10,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 7),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.93),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        hasPoint
                            ? '已选位置：${_lat.toStringAsFixed(5)}, ${_lng.toStringAsFixed(5)}　点地图可微调'
                            : '点地图选择钓点位置（必填）',
                        style: const TextStyle(fontSize: 11.5),
                      ),
                    ),
                  ),
                  Positioned(
                    right: 10,
                    bottom: 10,
                    child: FloatingActionButton.small(
                      heroTag: 'spot-edit-locate',
                      backgroundColor: Colors.white,
                      foregroundColor: AppTheme.primary,
                      onPressed: _locating ? null : _useMyLocation,
                      tooltip: '使用我的位置',
                      child: _locating
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.my_location, size: 20),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 6, 10, 8),
            child: Row(
              children: [
                const Icon(Icons.info_outline,
                    size: 13, color: AppTheme.textTertiary),
                const SizedBox(width: 5),
                const Expanded(
                  child: Text('改了定位，附近钓点和地图上的位置会立刻跟着变',
                      style: TextStyle(
                          fontSize: 10.5, color: AppTheme.textTertiary)),
                ),
                TextButton(
                  onPressed: _fillAddress,
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: const Size(0, 28),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text('按坐标补地址',
                      style: TextStyle(fontSize: 11.5)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _basicCard() {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('基本信息',
              style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          _label('名称'),
          _field(_nameCtrl, hint: '例如：许昌西湖黑坑', maxLength: 60),
          _label('类型'),
          Row(
            children: [
              for (final k in const [
                ('venue', '钓场'),
                ('wild', '野钓点'),
                ('shop', '渔具店'),
              ]) ...[
                _pill(k.$2, _kind == k.$1, () => setState(() => _kind = k.$1)),
                const SizedBox(width: 8),
              ],
            ],
          ),
          const SizedBox(height: 10),
          _label('钓法分类（用户搜索和筛选按它走）'),
          _field(_typeCtrl, hint: '野钓 / 黑坑 / 路亚 / 海钓'),
          _label('简介'),
          _field(_descCtrl,
              hint: '水情、鱼情、注意事项', maxLines: 4, maxLength: 1000),
        ],
      ),
    );
  }

  Widget _contactCard() {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('地址与联系',
              style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          _label('详细地址'),
          _field(_addressCtrl, hint: '县区 + 街道，能定位到门口最好'),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _label('收费'),
                    _field(_feeCtrl, hint: '如：正钓 200/4h'),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _label('电话'),
                    _field(_phoneCtrl,
                        hint: '选填', keyboard: TextInputType.phone),
                  ],
                ),
              ),
            ],
          ),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _label('主要鱼种'),
                    _field(_fishCtrl, hint: '鲫鱼、鲤鱼、草鱼'),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _label('标签'),
                    _field(_tagsCtrl, hint: '推荐、夜钓、免费'),
                  ],
                ),
              ),
            ],
          ),
          if (_kind == 'shop')
            SwitchListTile.adaptive(
              value: _delivery,
              onChanged: (v) => setState(() => _delivery = v),
              contentPadding: EdgeInsets.zero,
              activeColor: AppTheme.primary,
              title: const Text('支持外送',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              subtitle: const Text('渔具店专用；其他类型不显示这一项',
                  style: TextStyle(fontSize: 10.5, color: AppTheme.textTertiary)),
            ),
        ],
      ),
    );
  }

  Widget _imageCard() {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('图片',
                  style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
              const SizedBox(width: 6),
              Text('${_images.length}/$_imageMax',
                  style: const TextStyle(
                      fontSize: 11, color: AppTheme.textTertiary)),
              const Spacer(),
              TextButton.icon(
                onPressed: _images.length >= _imageMax ? null : _pickImages,
                icon: const Icon(Icons.add_photo_alternate_outlined, size: 17),
                label: const Text('添加', style: TextStyle(fontSize: 12)),
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
          const Text('第一张同时当封面；详情页顶部图集按这个顺序展示',
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
                    size: 18, color: AppTheme.textTertiary),
              ),
            ),
          if (index == 0)
            Positioned(
              left: 3,
              top: 3,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(3),
                ),
                child: const Text('封面',
                    style: TextStyle(
                        fontSize: 8.5, height: 1.2, color: Colors.white)),
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
                    color: Colors.black54, shape: BoxShape.circle),
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
              leading: const Icon(Icons.photo_camera_outlined,
                  color: AppTheme.primary),
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

  Widget _statusCard() {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('上架状态',
              style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          const Text('已上架才会出现在用户的地图和搜索结果里',
              style: TextStyle(fontSize: 10.5, color: AppTheme.textTertiary)),
          const SizedBox(height: 10),
          Row(
            children: [
              for (final st in const [
                (1, '已上架'),
                (0, '待审核'),
                (2, '已下架'),
              ]) ...[
                _pill(st.$2, _status == st.$1,
                    () => setState(() => _status = st.$1)),
                const SizedBox(width: 8),
              ],
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _label('评分'),
              const SizedBox(width: 6),
              Text(_rating.toStringAsFixed(1),
                  style: const TextStyle(
                      fontSize: 12.5, fontWeight: FontWeight.w700)),
            ],
          ),
          Slider(
            value: _rating.clamp(0, 5),
            max: 5,
            divisions: 10,
            activeColor: AppTheme.star,
            label: _rating.toStringAsFixed(1),
            onChanged: (v) => setState(() => _rating = v),
          ),
        ],
      ),
    );
  }

  Widget _pill(String text, bool on, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 28,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: on ? AppTheme.primaryLight : AppTheme.background,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: on ? AppTheme.primary : AppTheme.border),
        ),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 12,
            fontWeight: on ? FontWeight.w700 : FontWeight.w500,
            color: on ? AppTheme.primaryDark : AppTheme.textSecondary,
          ),
        ),
      ),
    );
  }
}
