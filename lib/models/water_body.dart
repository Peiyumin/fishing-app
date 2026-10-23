import 'package:latlong2/latlong.dart';

/// 水域（钓点地图 · 蓝色图层）
///
///  - isRiver = true  ：江河，geometry 为折线（WGS-84 坐标，渲染前转 GCJ-02）
///  - isRiver = false ：湖泊/水库，geometry 为闭合环（首尾相接）
/// 数据来源：assets/data/waters.json（内置，随 App 版本更新）
class WaterBody {
  final String id;
  final String name;
  final bool isRiver;
  final int level; // 河流等级：1=大河 2=主要支流 3=其他
  final String basin; // 流域
  final String kindLabel; // 湖泊 / 水库
  final String area; // 面积
  final String desc; // 简介
  final List<LatLng> geometry;

  const WaterBody({
    required this.id,
    required this.name,
    required this.isRiver,
    this.level = 2,
    this.basin = '',
    this.kindLabel = '湖泊',
    this.area = '',
    this.desc = '',
    required this.geometry,
  });

  factory WaterBody.fromJson(Map<String, dynamic> j, {required bool river}) {
    final raw = (river ? j['points'] : j['ring']) as List? ?? const [];
    return WaterBody(
      id: j['id'] as String? ?? '',
      name: j['name'] as String? ?? '未名水域',
      isRiver: river,
      level: (j['level'] as num?)?.toInt() ?? 2,
      basin: j['basin'] as String? ?? '',
      kindLabel: j['kind'] as String? ?? '湖泊',
      area: j['area'] as String? ?? '',
      desc: j['desc'] as String? ?? '',
      geometry: raw
          .whereType<List>()
          .map((p) => LatLng((p[0] as num).toDouble(), (p[1] as num).toDouble()))
          .toList(),
    );
  }

  /// 几何中心（算术平均，用于定位/居中）
  LatLng get center {
    if (geometry.isEmpty) return const LatLng(35.0, 105.0);
    var la = 0.0, ln = 0.0;
    for (final p in geometry) {
      la += p.latitude;
      ln += p.longitude;
    }
    return LatLng(la / geometry.length, ln / geometry.length);
  }

  String get subLabel => isRiver ? basin : '$kindLabel · $area';

  /// 线宽/填充不透明度随等级变化（大河更醒目）
  double get strokeWidth => level <= 1 ? 4.5 : (level == 2 ? 3.2 : 2.2);
}
