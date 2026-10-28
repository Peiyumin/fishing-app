import 'package:latlong2/latlong.dart';
import '../utils/json_num.dart';

/// 禁钓区类型
enum ZoneKind {
  /// 长江十年禁捕（含大型通江湖泊、赤水河等）
  tenYear,

  /// 水生生物保护区 / 水产种质资源保护区（长期全面禁捕）
  reserve,

  /// 饮用水水源保护区（明确禁止垂钓）
  waterSource,

  /// 湖泊/水库禁渔期（时间性，休闲垂钓按规定执行）
  lakeBan,

  /// 地方划定的禁钓区（禁钓）
  noFishing,
}

/// 全国禁钓区 / 禁渔期（钓点地图 · 红色图层）
///
/// 政策数据整理自农业农村部及各省农业农村厅、生态环境部门公开发布的通告
/// （assets/data/no_fishing_zones.json 内置，后台「运营配置 → 禁钓区管理」可更新）。
class NoFishingZone {
  final String id;
  final String name;
  final String region;
  final ZoneKind kind;
  final String kindLabel;

  /// 禁钓/禁渔时间段说明（原文照录政府部门通告）
  final String period;

  /// 固定期限禁捕的起止（ISO 日期，可为空表示不适用）
  final DateTime? activeFrom;
  final DateTime? activeTo;

  /// 每年周期性禁渔窗口 [起始月, 起始日, 结束月, 结束日]，如 [3,1,6,30]
  final List<int>? mdWindow;

  /// 垂钓规定说明
  final String fishing;

  /// 法律/政策依据
  final String law;

  /// 来源链接
  final String source;

  /// 是否上图（文字规则类 Zone 只在名录中展示）
  final bool onMap;

  /// 多边形范围（WGS-84 闭合环列表）
  final List<List<LatLng>> rings;

  const NoFishingZone({
    required this.id,
    required this.name,
    required this.region,
    required this.kind,
    required this.kindLabel,
    required this.period,
    this.activeFrom,
    this.activeTo,
    this.mdWindow,
    required this.fishing,
    required this.law,
    required this.source,
    this.onMap = true,
    this.rings = const [],
  });

  factory NoFishingZone.fromJson(Map<String, dynamic> j) {
    ZoneKind kindOf(String? s) {
      switch (s) {
        case 'ten_year':
          return ZoneKind.tenYear;
        case 'reserve':
          return ZoneKind.reserve;
        case 'water_source':
          return ZoneKind.waterSource;
        case 'lake_ban':
          return ZoneKind.lakeBan;
        default:
          return ZoneKind.noFishing;
      }
    }

    List<int>? md;
    final rawMd = j['mdWindow'];
    if (rawMd is List && rawMd.length == 4) {
      // 元素可能是 "12" / null（后台改过字段类型），不能用 ! 断言：
      // 一个空元素就会让整份禁钓区数据解析失败，地图上一条禁钓区都不显示。
      md = rawMd.map((e) => jsonNum(e)?.toInt() ?? 0).toList();
    }
    DateTime? dt(dynamic v) =>
        v == null ? null : DateTime.tryParse(v.toString());

    final ringsRaw = j['rings'] as List? ?? const [];
    return NoFishingZone(
      id: j['id'] as String? ?? '',
      name: j['name'] as String? ?? '未命名禁钓区',
      region: j['region'] as String? ?? '',
      kind: kindOf(j['type'] as String?),
      kindLabel: j['typeLabel'] as String? ?? '禁钓区',
      period: j['period'] as String? ?? '',
      activeFrom: dt(j['activeFrom']),
      activeTo: dt(j['activeTo']),
      mdWindow: md,
      fishing: j['fishing'] as String? ?? '',
      law: j['law'] as String? ?? '',
      source: j['source'] as String? ?? '',
      onMap: (j['onMap'] is bool)
          ? (j['onMap'] as bool)
          : jsonInt(j['onMap']) == 1,
      rings: ringsRaw
          .whereType<List>()
          .map((ring) => ring
              .whereType<List>()
              // 坐标点必须是 [lng, lat] 两个数；少一个就跳过，别让整条环废掉
              .where((p) => p.length >= 2)
              .map((p) => LatLng(
                  jsonNum(p[0])?.toDouble() ?? 0, jsonNum(p[1])?.toDouble() ?? 0))
              .toList())
          .toList(),
    );
  }

  bool get isPermanentFishingBan =>
      kind == ZoneKind.waterSource || kind == ZoneKind.noFishing;

  /// 当前时刻的状态判定：
  ///  - 固定期限（十年禁捕/封湖育鱼）按 activeFrom~activeTo
  ///  - 年度周期（禁渔期）按月日窗口（支持跨年，如抚仙湖 12-31 → 次年 7-1）
  ///  - 都没有 → 长期有效
  ZoneStatus statusNow([DateTime? now]) {
    final t = now ?? DateTime.now();
    if (mdWindow != null) {
      final m1 = mdWindow![0], d1 = mdWindow![1], m2 = mdWindow![2], d2 = mdWindow![3];
      final cur = t.month * 100 + t.day;
      final s = m1 * 100 + d1;
      final e = m2 * 100 + d2;
      final inside = s <= e ? (cur >= s && cur <= e) : (cur >= s || cur <= e);
      return ZoneStatus(
          active: inside,
          label: inside ? '当前处于禁渔期' : '当前不在禁渔期',
          hint: inside ? '请遵守禁钓规定，暂停垂钓' : '禁渔期外按休闲垂钓规范执行');
    }
    if (activeFrom != null || activeTo != null) {
      final from = activeFrom ?? DateTime(2000);
      final to = activeTo ?? DateTime(2099, 12, 31);
      final inside = !t.isBefore(from) && !t.isAfter(to);
      return ZoneStatus(
          active: inside,
          label: inside ? '当前禁捕/禁钓期内' : '当前不在禁捕期限内',
          hint: inside ? '禁止生产性捕捞，垂钓按规定执行' : '以当地最新通告为准');
    }
    return const ZoneStatus(active: true, label: '长期有效', hint: '常年禁捕/禁钓');
  }

  LatLng? get center {
    if (rings.isEmpty) return null;
    final ring = rings.first;
    if (ring.isEmpty) return null;
    var la = 0.0, ln = 0.0;
    for (final p in ring) {
      la += p.latitude;
      ln += p.longitude;
    }
    return LatLng(la / ring.length, ln / ring.length);
  }
}

class ZoneStatus {
  final bool active;
  final String label;
  final String hint;
  const ZoneStatus(
      {required this.active, required this.label, required this.hint});
}

/// 禁渔期制度（时间规则，无地图范围）
class SeasonRule {
  final String id;
  final String scope;
  final String period;
  final String note;
  final String law;
  final String source;
  final List<int>? mdWindow;

  const SeasonRule({
    required this.id,
    required this.scope,
    required this.period,
    required this.note,
    required this.law,
    required this.source,
    this.mdWindow,
  });

  factory SeasonRule.fromJson(Map<String, dynamic> j) {
    List<int>? md;
    final rawMd = j['mdWindow'];
    if (rawMd is List && rawMd.length == 4) {
      // 元素可能是 "12" / null（后台改过字段类型），不能用 ! 断言：
      // 一个空元素就会让整份禁钓区数据解析失败，地图上一条禁钓区都不显示。
      md = rawMd.map((e) => jsonNum(e)?.toInt() ?? 0).toList();
    }
    return SeasonRule(
      id: j['id'] as String? ?? '',
      scope: j['scope'] as String? ?? '',
      period: j['period'] as String? ?? '',
      note: j['note'] as String? ?? '',
      law: j['law'] as String? ?? '',
      source: j['source'] as String? ?? '',
      mdWindow: md,
    );
  }

  bool get activeNow {
    if (mdWindow == null) return true;
    final t = DateTime.now();
    final cur = t.month * 100 + t.day;
    final s = mdWindow![0] * 100 + mdWindow![1];
    final e = mdWindow![2] * 100 + mdWindow![3];
    return s <= e ? (cur >= s && cur <= e) : (cur >= s || cur <= e);
  }
}

/// 禁钓区数据包（App 内置 + 后台下发合并后的结果）
class NoFishingData {
  final List<NoFishingZone> zones;
  final List<SeasonRule> seasonRules;
  final List<String> tips;
  final String updatedAt;

  /// server = 后台最新数据；bundled = App 内置数据
  final String origin;

  const NoFishingData({
    required this.zones,
    required this.seasonRules,
    required this.tips,
    required this.updatedAt,
    required this.origin,
  });

  static const NoFishingData empty = NoFishingData(
      zones: [], seasonRules: [], tips: [], updatedAt: '', origin: 'bundled');

  bool get isEmpty => zones.isEmpty;
}
