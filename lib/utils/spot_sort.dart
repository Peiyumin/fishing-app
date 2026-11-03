import '../models/fishing_spot.dart';
import 'coord_transform.dart';

/// 坐标是否可用
///
/// 后台/批量导入的数据里偶尔会有 0,0（没填坐标）或越界值。这类点如果直接
/// 参与距离计算，会被算成「距我几千公里」，看着像排序坏了 —— 统一判定为
/// 「无坐标」，排序时沉到末尾。
bool spotHasUsableCoord(double lat, double lng) {
  if (lat == 0 && lng == 0) return false;
  if (lat.abs() > 90 || lng.abs() > 180) return false;
  return true;
}

/// 钓点按「距我」由近到远排序
///
/// 为什么必须放在客户端：后端 `/spots` 只有 `ORDER BY created_at DESC`
/// （谁后入库谁在前）。一次批量导入几十上百条时，入库时间只差几毫秒，
/// 大量记录 created_at 完全相同 → 顺序由存储引擎决定，看起来就是「乱排」。
/// 而卡片上显示的「1.2km」本来就是客户端按 [CoordTransform] 算的，
/// 排序必须与它同源，否则会出现「显示 800m 的排在 1.2km 下面」。
///
/// · [lat]/[lng] 为空（没给定位权限）→ 原样返回，保持后端顺序；
/// · 无坐标（0,0 / 越界）→ 一律沉底；
/// · 距离相同 → 按名称、id 定序，保证每次重建顺序稳定、不跳动。
List<FishingSpot> sortSpotsByDistance(
    List<FishingSpot> list, double? lat, double? lng) {
  if (lat == null || lng == null || list.length < 2) return list;

  // 每个点只算一次距离（51 条 × 每次 build 也只算一遍）
  final cache = <String, double>{};
  double distOf(FishingSpot s) {
    final key = s.id.isNotEmpty ? s.id : '${s.name}|${s.lat}|${s.lng}';
    return cache.putIfAbsent(key, () {
      if (!spotHasUsableCoord(s.lat, s.lng)) return double.infinity;
      return CoordTransform.distanceMeters(lat, lng, s.lat, s.lng);
    });
  }

  final copy = List<FishingSpot>.from(list);
  copy.sort((a, b) {
    final da = distOf(a);
    final db = distOf(b);
    if (da != db) return da.compareTo(db);
    final byName = a.name.compareTo(b.name);
    if (byName != 0) return byName;
    return a.id.compareTo(b.id);
  });
  return copy;
}
