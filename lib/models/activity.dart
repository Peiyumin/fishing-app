/// 活动
///
/// 对应后端 `activities` 表。用户投稿的活动 status=0（待审核），
/// 后台通过后 status=1 才会出现在活动列表里。
class Activity {
  final String id;
  final String title;
  final String cover;
  final String summary;
  final String content;
  final String startAt;
  final String endAt;
  final String location;
  final String fee;
  final String contact;
  final String authorId;
  final String authorName;
  final String statusLabel;
  final String rejectReason;
  final String createdAt;
  final int maxJoin;
  final int joinCount;
  final int status;
  final bool full;
  final bool joined;

  const Activity({
    required this.id,
    required this.title,
    required this.cover,
    required this.summary,
    required this.content,
    required this.startAt,
    required this.endAt,
    required this.location,
    required this.fee,
    required this.contact,
    required this.authorId,
    required this.authorName,
    required this.statusLabel,
    required this.rejectReason,
    required this.createdAt,
    required this.maxJoin,
    required this.joinCount,
    required this.status,
    required this.full,
    required this.joined,
  });

  bool get isApproved => status == 1;
  bool get isPending => status == 0;
  bool get isRejected => status == 2;

  /// 报名状态文案
  String get joinText {
    if (maxJoin > 0) return '$joinCount / $maxJoin 人';
    return joinCount > 0 ? '$joinCount 人已报名' : '不限名额';
  }

  /// 开始时间格式化：「10月25日 周六 14:00」
  String get timeText => _fmt(startAt, withTime: true);

  /// 结束时间（只到点，不重复星期）
  String get endText => _fmt(endAt, withTime: true);

  /// 列表卡片左侧日期牌：上行「10月」
  String get monthText {
    final d = _parse(startAt);
    return d == null ? '' : '${d.month}月';
  }

  /// 列表卡片左侧日期牌：下行「25」
  String get dayText {
    final d = _parse(startAt);
    return d == null ? '' : '${d.day}';
  }

  /// 时间区间文案：同一天只写一次日期
  String get rangeText {
    if (endAt.trim().isEmpty) return timeText;
    final s = _parse(startAt);
    final e = _parse(endAt);
    if (s == null || e == null) return timeText;
    final sameDay = s.year == e.year && s.month == e.month && s.day == e.day;
    if (sameDay) {
      final hh = e.hour.toString().padLeft(2, '0');
      final mm = e.minute.toString().padLeft(2, '0');
      return '$timeText — $hh:$mm';
    }
    return '$timeText 起';
  }

  /// 正文按空行切成段落
  List<String> get paragraphs => content
      .split(RegExp(r'\r?\n\s*\r?\n'))
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .toList();

  static DateTime? _parse(String raw) {
    if (raw.trim().isEmpty) return null;
    return DateTime.tryParse(raw.replaceAll('/', '-'));
  }

  static const List<String> _week = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];

  static String _fmt(String raw, {bool withTime = false}) {
    if (raw.trim().isEmpty) return '';
    final d = DateTime.tryParse(raw.replaceAll('/', '-'));
    if (d == null) return raw;
    final md = '${d.month}月${d.day}日';
    final w = _week[(d.weekday - 1).clamp(0, 6)];
    if (!withTime) return '$md $w';
    final hh = d.hour.toString().padLeft(2, '0');
    final mm = d.minute.toString().padLeft(2, '0');
    return '$md $w $hh:$mm';
  }

  factory Activity.fromJson(Map<String, dynamic> j) {
    int asInt(dynamic v) => v is num ? v.toInt() : (int.tryParse('$v') ?? 0);
    String asStr(dynamic v) => v == null ? '' : '$v';
    bool asBool(dynamic v) => v == true || v == 1 || '$v' == '1' || '$v' == 'true';
    return Activity(
      id: asStr(j['id']),
      title: asStr(j['title']),
      cover: asStr(j['cover']),
      summary: asStr(j['summary']),
      content: asStr(j['content']),
      startAt: asStr(j['start_at']),
      endAt: asStr(j['end_at']),
      location: asStr(j['location']),
      fee: asStr(j['fee']),
      contact: asStr(j['contact']),
      authorId: asStr(j['author_id']),
      authorName: asStr(j['author_name']),
      statusLabel: asStr(j['status_label']),
      rejectReason: asStr(j['reject_reason']),
      createdAt: asStr(j['created_at']),
      maxJoin: asInt(j['max_join']),
      joinCount: asInt(j['join_count']),
      status: asInt(j['status']),
      full: asBool(j['full']),
      joined: asBool(j['joined']),
    );
  }
}
