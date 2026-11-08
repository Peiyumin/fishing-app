import '../models/fishing_spot.dart';

/// 把宿主页（钓点页）给的一批钓点，同步进地图当前持有的钓点集合
///
/// 纯函数，不碰 Flutter、不碰 MapLibre —— 地图的两个渲染内核
/// （原生 GL / flutter_map 兜底）都调它，逻辑只写一份，能被单测钉住。
///
/// 参数：
///   [current]    地图此刻手里的钓点（可能混着「地图自己拉的钓场/渔具店」）
///   [servedIds]  **上一轮**宿主页喂进来的那批 id
///   [incoming]   这一轮宿主页给的完整列表（不是增量）
///
/// 返回：合并后的新集合（保持 current 的顺序，新增的追加在后面）
///
/// ★ 为什么要 servedIds：
///   老写法是「以 current 为底、把 incoming 盖上去」，只增不删 ——
///   后台删掉一个钓点后，宿主页刷新拿到的新列表里已经没有它，
///   地图上却照旧长着那个点，点进去还能进详情（内容是上一版快照）。
///   用户看到的就是「后台删了，App 点刷新没反应」。
///   光有 incoming 没法判断「current 里哪些点是宿主页给的、哪些是地图
///   自己拉的」，所以要把上一轮的名单记下来：上一轮给过、这一轮没了
///   = 被后台删了，剔除；地图自己拉的（不在 servedIds 里）原样保留。
Map<String, FishingSpot> syncSpotMap({
  required Iterable<FishingSpot> current,
  required Set<String> servedIds,
  required Iterable<FishingSpot> incoming,
}) {
  // 坐标缺失的点画不上去，不算进「这一轮名单」：
  // 否则一个坐标是 0 的点会在「有 id / 无 id」之间反复触发增删
  final incomingIds = <String>{
    for (final s in incoming)
      if (s.lat != 0 || s.lng != 0) s.id,
  };

  final map = <String, FishingSpot>{};
  for (final s in current) {
    // 上一轮由宿主页喂进来、这一轮名单里没有了 → 后台已删/下架
    if (servedIds.contains(s.id) && !incomingIds.contains(s.id)) continue;
    map[s.id] = s;
  }
  for (final s in incoming) {
    if (s.lat == 0 && s.lng == 0) continue;
    // 覆盖成最新数据（名称 / 坐标 / 简介可能在后台改过）
    map[s.id] = s;
  }
  return map;
}

/// 从一批钓点里摘出「能在图上画的 id」（坐标非 0）
///
/// 给 [_mergeSpots] 与首屏加载共用：两处都要把「这一轮名单」记下来，
/// 口径必须是同一个，否则第一次刷新会把本该删掉的点留下。
Set<String> drawableSpotIds(Iterable<FishingSpot> spots) => {
      for (final s in spots)
        if (s.lat != 0 || s.lng != 0) s.id,
    };
