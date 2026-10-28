import '../utils/json_num.dart';

/// 钓点报错 数据模型（V2）
/// 用户发现某钓点坐标错误 / 已关闭 / 信息有误等时提交
class SpotReport {
  final String id;
  final String spotId;
  final String? spotName; // 冗余存一份名称，方便后台直接展示
  final String reason; // 坐标错误 / 已关闭 / 信息有误 / 已收费 / 其他
  final String? note; // 补充说明
  final String? userId;
  final DateTime createdAt;
  final bool resolved; // 后台是否已处理

  const SpotReport({
    required this.id,
    required this.spotId,
    this.spotName,
    required this.reason,
    this.note,
    this.userId,
    required this.createdAt,
    this.resolved = false,
  });

  /// 把 Supabase 返回的 JSON 转成 SpotReport
  factory SpotReport.fromJson(Map<String, dynamic> json) {
    final spot = json['spots'] as Map<String, dynamic>?;
    return SpotReport(
      id: (json['id'] ?? '').toString(),
      spotId: (json['spot_id'] ?? '').toString(),
      spotName: spot?['name'] as String?,
      reason: json['reason'] as String? ?? '其他',
      note: json['note'] as String?,
      userId: json['user_id'] as String?,
      createdAt: jsonDateOrNow(json['created_at']),
      resolved: jsonBool(json['resolved'], fallback: false),
    );
  }
}
