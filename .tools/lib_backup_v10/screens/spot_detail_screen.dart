import 'package:flutter/material.dart';

import '../app_theme.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong2.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/fishing_spot.dart';
import '../services/spot_service.dart';
import '../utils/coord_transform.dart';

/// 钓点详情页
/// 展示地图预览、精确坐标、评分、标签、地址/收费/鱼种/电话、描述，
/// 并提供「导航前往」与「报错」。野钓点使用卫星地图。
class SpotDetailScreen extends StatefulWidget {
  final FishingSpot spot;
  const SpotDetailScreen({super.key, required this.spot});

  @override
  State<SpotDetailScreen> createState() => _SpotDetailScreenState();
}

class _SpotDetailScreenState extends State<SpotDetailScreen> {
  late int _reportCount;

  @override
  void initState() {
    super.initState();
    _reportCount = widget.spot.reportCount;
  }

  Future<void> _report() async {
    String reason = '坐标错误';
    final noteCtrl = TextEditingController();
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setSt) => Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 16,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('钓点报错',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              const Text('选择原因', style: TextStyle(color: Colors.grey)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: ['坐标错误', '已关闭', '信息有误', '已收费', '其他']
                    .map((r) => ChoiceChip(
                          label: Text(r),
                          selected: reason == r,
                          onSelected: (_) => setSt(() => reason = r),
                        ))
                    .toList(),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: noteCtrl,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: '补充说明（选填）',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 44,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.danger,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('提交报错'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (ok != true) return;

    try {
      await SpotService.reportSpot(
        spotId: widget.spot.id,
        spotName: widget.spot.name,
        reason: reason,
        note: noteCtrl.text.trim().isEmpty ? null : noteCtrl.text.trim(),
      );
      if (mounted) {
        setState(() => _reportCount += 1);
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('已提交报错，感谢反馈！')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('报错失败：$e')));
      }
    }
  }

  /// 拨打电话
  Future<void> _call(String phone) async {
    final uri = Uri.parse('tel:$phone');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('无法拨打电话')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.spot;
    // 数据库存 WGS-84，高德底图（卫星/路网）为 GCJ-02，展示前统一转换
    final mapLatLng = (() {
      final g = CoordTransform.wgs84ToGcj02(s.lat, s.lng);
      return LatLng(g[0], g[1]);
    })();
    final tags = s.tags
        .split(',')
        .map((t) => t.trim())
        .where((t) => t.isNotEmpty)
        .toList();

    return Scaffold(
      appBar: AppBar(title: Text(s.name)),
      body: ListView(
        children: [
          // 地图预览
          SizedBox(
            height: 220,
            child: FlutterMap(
              options: MapOptions(
                initialCenter: mapLatLng,
                initialZoom: 13,
                interactionOptions: const InteractionOptions(
                  flags: InteractiveFlag.none,
                ),
              ),
              children: [
                if (s.kind == 'wild') ...[
                  // 野钓点：卫星影像
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
                ] else
                  // 钓场/渔具店：矢量路网
                  TileLayer(
                    urlTemplate:
                        'https://webst01.is.autonavi.com/appmaptile?x={x}&y={y}&z={z}&lang=zh_cn&size=1&scale=1&style=7',
                    userAgentPackageName: 'com.example.fishing_app',
                  ),
                MarkerLayer(
                  markers: [
                    Marker(
                      point: mapLatLng,
                      width: 40,
                      height: 40,
                      child: Icon(Icons.place,
                          color: s.kind == 'wild'
                              ? AppTheme.danger
                              : AppTheme.primary,
                          size: 38),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 类型 + 核实 + 星级
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: s.kind == 'wild'
                            ? AppTheme.dangerLight
                            : AppTheme.primaryLight,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text('${s.kindLabel} · ${s.type}',
                          style: TextStyle(
                              fontSize: 13,
                              color: s.kind == 'wild'
                                  ? AppTheme.danger
                                  : AppTheme.primary)),
                    ),
                    if (s.verified) ...[
                      const SizedBox(width: 8),
                      const Icon(Icons.verified,
                          size: 16, color: AppTheme.accent),
                      const SizedBox(width: 4),
                      const Text('官方核实',
                          style: TextStyle(
                              fontSize: 12, color: AppTheme.accent)),
                    ],
                    const Spacer(),
                    const Icon(Icons.star, size: 16, color: AppTheme.star),
                    const SizedBox(width: 4),
                    Text(s.rating.toString(),
                        style: const TextStyle(fontSize: 14)),
                  ],
                ),
                // 标签
                if (tags.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: tags
                        .map((t) => Chip(
                              label: Text(t),
                              visualDensity: VisualDensity.compact,
                              backgroundColor: AppTheme.primarySoft,
                              labelStyle: const TextStyle(fontSize: 11),
                            ))
                        .toList(),
                  ),
                ],
                const SizedBox(height: 12),
                // 地址 / 收费 / 鱼种 / 电话
                if (s.address.isNotEmpty) _infoRow(Icons.location_on_outlined, s.address),
                if (s.fee.isNotEmpty)
                  _infoRow(Icons.payments_outlined, '收费：${s.fee}'),
                if (s.fish.isNotEmpty)
                  _infoRow(Icons.set_meal_outlined, '鱼种：${s.fish}'),
                if (s.phone.isNotEmpty)
                  _infoRow(Icons.phone_outlined, s.phone, onTap: () => _call(s.phone)),
                if (s.commentCount > 0)
                  _infoRow(Icons.chat_bubble_outline, '${s.commentCount} 条评论'),
                const SizedBox(height: 8),
                // 描述
                Text(s.description.isEmpty ? '钓友暂未填写说明' : s.description,
                    style: const TextStyle(fontSize: 15, height: 1.5)),
                const SizedBox(height: 12),
                // 精确坐标
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppTheme.accentLight,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '精确坐标（WGS84）：\n'
                    '纬度 ${s.lat.toStringAsFixed(6)}\n'
                    '经度 ${s.lng.toStringAsFixed(6)}',
                    style: const TextStyle(
                        fontSize: 13, color: AppTheme.accentDark),
                  ),
                ),
                const SizedBox(height: 10),
                // 报错数
                Row(
                  children: [
                    const Icon(Icons.report_problem_outlined,
                        size: 16, color: AppTheme.danger),
                    const SizedBox(width: 6),
                    Text('该钓点已被报错 $_reportCount 次',
                        style: const TextStyle(
                            fontSize: 13, color: AppTheme.danger)),
                  ],
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content: Text('已复制坐标，可粘贴到地图App导航')),
                          );
                        },
                        icon: const Icon(Icons.directions),
                        label: const Text('导航前往'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _report,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.danger,
                          foregroundColor: Colors.white,
                        ),
                        icon: const Icon(Icons.report_problem),
                        label: const Text('报错'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoRow(IconData icon, String text, {VoidCallback? onTap}) {
    final row = Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 15, color: Colors.grey),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text,
                style: const TextStyle(fontSize: 13.5, color: Colors.black87)),
          ),
        ],
      ),
    );
    if (onTap == null) return row;
    return InkWell(onTap: onTap, child: row);
  }
}
