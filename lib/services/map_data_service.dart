import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

import '../models/no_fishing_zone.dart';
import '../models/water_body.dart';
import 'api_client.dart';
import 'api_config.dart';
import '../utils/json_num.dart';

/// 钓点地图数据服务
/// ------------------------------------------------------------
///  - 水域图层（江河/湖泊）：App 内置 assets/data/waters.json
///  - 禁钓区图层：优先拉后台 GET /fish/zones（后台可随时更新，不用发版），
///    失败时回落 App 内置 assets/data/no_fishing_zones.json
///  - 统计：GET /app/map-stats（钓点数 / 渔获数）
class MapDataService {
  MapDataService._();

  static List<WaterBody>? _waters;
  static NoFishingData? _zones;

  /// 水域图层（内置 JSON，只读一次）
  static Future<List<WaterBody>> waters() async {
    if (_waters != null) return _waters!;
    final doc = jsonDecode(
        await rootBundle.loadString('assets/data/waters.json')) as Map;
    final list = <WaterBody>[];
    for (final r in (doc['rivers'] as List? ?? const [])) {
      if (r is Map) {
        list.add(WaterBody.fromJson(
            Map<String, dynamic>.from(r), river: true));
      }
    }
    for (final l in (doc['lakes'] as List? ?? const [])) {
      if (l is Map) {
        list.add(WaterBody.fromJson(
            Map<String, dynamic>.from(l), river: false));
      }
    }
    _waters = list;
    return list;
  }

  /// 禁钓区数据（后台优先，内置兜底）
  static Future<NoFishingData> zones() async {
    if (_zones != null) return _zones!;
    if (ApiConfig.enabled) {
      try {
        final data = await ApiClient.get('/fish/zones') as Map?;
        if (data != null && data['ok'] == 1) {
          final zones = (data['zones'] as List? ?? const [])
              .whereType<Map>()
              .map((e) => NoFishingZone.fromJson(Map<String, dynamic>.from(e)))
              .toList();
          if (zones.isNotEmpty) {
            _zones = NoFishingData(
              zones: zones,
              seasonRules: (data['seasonRules'] as List? ?? const [])
                  .whereType<Map>()
                  .map((e) => SeasonRule.fromJson(Map<String, dynamic>.from(e)))
                  .toList(),
              tips: (data['tips'] as List? ?? const [])
                  .map((e) => e.toString())
                  .toList(),
              updatedAt: (data['updatedAt'] ?? '').toString(),
              origin: 'server',
            );
            return _zones!;
          }
        }
      } catch (_) {
        // 后台不可用 → 用内置数据
      }
    }
    final doc = jsonDecode(await rootBundle.loadString(
        'assets/data/no_fishing_zones.json')) as Map;
    _zones = NoFishingData(
      zones: (doc['zones'] as List? ?? const [])
          .whereType<Map>()
          .map((e) => NoFishingZone.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
      seasonRules: (doc['seasonRules'] as List? ?? const [])
          .whereType<Map>()
          .map((e) => SeasonRule.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
      tips: (doc['tips'] as List? ?? const [])
          .map((e) => e.toString())
          .toList(),
      updatedAt: (doc['updatedAt'] ?? '').toString(),
      origin: 'bundled',
    );
    return _zones!;
  }

  /// 统计数据（钓点数 / 渔获数）；失败返回 null，界面自行降级
  static Future<Map<String, int>?> stats() async {
    if (!ApiConfig.enabled) return null;
    try {
      final data = await ApiClient.get('/app/map-stats') as Map?;
      if (data != null && data['ok'] == 1) {
        return {
          'spots': (jsonNum(data['spots']) ?? 0).toInt(),
          'catches': (jsonNum(data['catches']) ?? 0).toInt(),
        };
      }
    } catch (_) {}
    return null;
  }
}
