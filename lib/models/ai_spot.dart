/// AI 找钓点 · 推荐结果
///
/// 后端 POST /fish/spot-ai 返回：把附近水域 + 当前逐时天气交给大模型，
/// 由模型按鱼种习性（适温/气压/水氧）给出「现在最值得去」的水域排序。
import '../utils/json_num.dart';

class AiSpotRec {
  final bool ok;
  final String summary; // 总体形势一句话
  final List<AiSpotItem> items;

  const AiSpotRec(
      {required this.ok, required this.summary, required this.items});

  static const AiSpotRec empty =
      AiSpotRec(ok: false, summary: '', items: []);

  factory AiSpotRec.fromJson(Map<String, dynamic> j) {
    return AiSpotRec(
      ok: j['ok'] == 1 || j['ok'] == true,
      summary: (j['summary'] ?? '').toString(),
      items: (j['recommendations'] as List? ?? const [])
          .whereType<Map>()
          .map((e) => AiSpotItem.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
    );
  }
}

class AiSpotItem {
  final String name; // 水域名（与入参 waters 对应）
  final double score; // 0-100 推荐分
  final String reason; // 推荐理由
  final String bait; // 建议用饵/钓法（模型给）

  const AiSpotItem(
      {required this.name,
      required this.score,
      required this.reason,
      required this.bait});

  factory AiSpotItem.fromJson(Map<String, dynamic> j) {
    return AiSpotItem(
      name: (j['name'] ?? '').toString(),
      score: (jsonNum(j['score']) ?? 0).toDouble(),
      reason: (j['reason'] ?? '').toString(),
      bait: (j['bait'] ?? '').toString(),
    );
  }
}
