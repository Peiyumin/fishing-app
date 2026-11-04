import '../utils/json_num.dart';

/// 官方工作台（v40）的数据模型
///
/// 对应后端 `/official/*` 一组接口。四个对象都做了「字段缺失也不炸」的处理：
/// 老后端没有这些接口时，调用方拿到的是空列表 / 抛 ApiException，不会出现
/// 类型转换异常把整个页面打成红屏。

/// 工作台首页的统计数字
class OfficialOverview {
  final String nickname;
  final int noticeCount; // 我发的公告（未删除）
  final int postCount;   // 全站动态总数（未删除）
  final int todayCount;  // 今天新增动态
  final int userCount;   // 未被封禁的用户数
  final int bannedCount; // 封禁中的用户数

  const OfficialOverview({
    this.nickname = '',
    this.noticeCount = 0,
    this.postCount = 0,
    this.todayCount = 0,
    this.userCount = 0,
    this.bannedCount = 0,
  });

  factory OfficialOverview.fromJson(Map<String, dynamic> j) => OfficialOverview(
        nickname: (j['nickname'] ?? '').toString(),
        noticeCount: jsonInt(j['noticeCount']) ?? 0,
        postCount: jsonInt(j['postCount']) ?? 0,
        todayCount: jsonInt(j['todayCount']) ?? 0,
        userCount: jsonInt(j['userCount']) ?? 0,
        bannedCount: jsonInt(j['bannedCount']) ?? 0,
      );
}

/// 一条公告（本质是 notice=1 的帖子，所以能直接进信息流）
class OfficialNotice {
  final String id;
  final String title;
  final String content;
  final bool pinned;
  final DateTime createdAt;
  final String authorName;
  final bool isMine;

  const OfficialNotice({
    required this.id,
    required this.title,
    required this.content,
    this.pinned = false,
    required this.createdAt,
    this.authorName = '',
    this.isMine = false,
  });

  factory OfficialNotice.fromJson(Map<String, dynamic> j) => OfficialNotice(
        id: (j['id'] ?? '').toString(),
        title: (j['title'] ?? '').toString(),
        content: (j['content'] ?? '').toString(),
        pinned: jsonInt(j['pinned']) == 1,
        createdAt: jsonDateOrNow(j['createdAt']),
        authorName: (j['authorName'] ?? '').toString(),
        isMine: jsonBool(j['isMine']),
      );
}

/// 帖子管理列表里的一行
class OfficialPost {
  final String id;
  final String title;
  final String preview;
  final String? cover;
  final bool notice;
  final bool pinned;
  final bool deleted;
  final int likeCount;
  final int commentCount;
  final DateTime createdAt;
  final String authorName;
  final String authorId;
  final bool canManage;

  const OfficialPost({
    required this.id,
    required this.title,
    this.preview = '',
    this.cover,
    this.notice = false,
    this.pinned = false,
    this.deleted = false,
    this.likeCount = 0,
    this.commentCount = 0,
    required this.createdAt,
    this.authorName = '',
    this.authorId = '',
    this.canManage = true,
  });

  String get displayTitle => title.trim().isEmpty ? preview : title;

  factory OfficialPost.fromJson(Map<String, dynamic> j) => OfficialPost(
        id: (j['id'] ?? '').toString(),
        title: (j['title'] ?? '').toString(),
        preview: (j['preview'] ?? '').toString(),
        cover: _mediaUrl(j['cover']),
        notice: jsonInt(j['notice']) == 1,
        pinned: jsonInt(j['pinned']) == 1,
        deleted: jsonInt(j['deleted']) == 1,
        likeCount: jsonInt(j['likeCount']) ?? 0,
        commentCount: jsonInt(j['commentCount']) ?? 0,
        createdAt: jsonDateOrNow(j['createdAt']),
        authorName: (j['authorName'] ?? '').toString(),
        authorId: (j['authorId'] ?? '').toString(),
        canManage: jsonInt(j['canManage']) != 0,
      );
}

/// 用户管理列表里的一行
class OfficialUser {
  final String id;
  final String nickname;
  final String phoneMasked;
  final String? avatar;
  final bool official;
  final bool banned;
  final String bannedUntil;
  final String banReason;
  final int postCount;
  final DateTime createdAt;
  final bool canManage;

  const OfficialUser({
    required this.id,
    required this.nickname,
    this.phoneMasked = '',
    this.avatar,
    this.official = false,
    this.banned = false,
    this.bannedUntil = '',
    this.banReason = '',
    this.postCount = 0,
    required this.createdAt,
    this.canManage = true,
  });

  /// 封禁状态的说明文案（永久 / 到期时间 + 原因）
  String get banLabel {
    if (!banned) return '';
    final head = bannedUntil.isEmpty ? '已永久封禁' : '封禁至 ${officialDateTime(bannedUntil)}';
    return banReason.isEmpty ? head : '$head · $banReason';
  }

  factory OfficialUser.fromJson(Map<String, dynamic> j) => OfficialUser(
        id: (j['id'] ?? '').toString(),
        nickname: (j['nickname'] ?? '钓友').toString(),
        phoneMasked: (j['phone'] ?? '').toString(),
        avatar: _mediaUrl(j['avatar']),
        official: jsonInt(j['official']) == 1,
        banned: jsonInt(j['banned']) == 1,
        bannedUntil: (j['bannedUntil'] ?? '').toString(),
        banReason: (j['banReason'] ?? '').toString(),
        postCount: jsonInt(j['postCount']) ?? 0,
        createdAt: jsonDateOrNow(j['createdAt']),
        canManage: jsonInt(j['canManage']) != 0,
      );
}

/// 操作记录
class OfficialLog {
  final String actorName;
  final String action;
  final String note;
  final DateTime createdAt;

  const OfficialLog({
    required this.actorName,
    required this.action,
    this.note = '',
    required this.createdAt,
  });

  /// 动作码翻成人话（后端存的是 notice_new / ban_7d 这种稳定码，
  /// 文案只在前端翻，改文案不用动后端）
  String get actionLabel {
    switch (action) {
      case 'notice_new':
        return '发布公告';
      case 'notice_edit':
        return '修改公告';
      case 'notice_delete':
        return '撤回公告';
      case 'notice_pin':
        return '置顶公告';
      case 'notice_unpin':
        return '取消置顶';
      case 'post_delete':
        return '删除动态';
      case 'post_restore':
        return '恢复动态';
      case 'post_pin':
        return '置顶动态';
      case 'post_unpin':
        return '取消置顶';
      case 'ban_forever':
        return '永久封禁';
      case 'ban_1d':
        return '封禁 1 天';
      case 'ban_7d':
        return '封禁 7 天';
      case 'ban_30d':
        return '封禁 30 天';
      case 'unban':
        return '解除封禁';
      default:
        return action;
    }
  }

  factory OfficialLog.fromJson(Map<String, dynamic> j) => OfficialLog(
        actorName: (j['actorName'] ?? '').toString(),
        action: (j['action'] ?? '').toString(),
        note: (j['note'] ?? '').toString(),
        createdAt: jsonDateOrNow(j['createdAt']),
      );
}

/// 空串 / null 统一成 null，省得界面层到处判空
String? _mediaUrl(dynamic v) {
  final s = (v ?? '').toString().trim();
  return s.isEmpty ? null : s;
}

/// DateTime → 「11月4日 22:05」（一律按本地时区显示）
String officialTimeOf(DateTime t) {
  final l = t.toLocal();
  final hh = l.hour.toString().padLeft(2, '0');
  final mm = l.minute.toString().padLeft(2, '0');
  return '${l.month}月${l.day}日 $hh:$mm';
}

/// ISO 时间串 → 「11月4日 22:05」；解析不了就原样返回
String officialDateTime(String iso) {
  final t = jsonDate(iso);
  if (t == null) return iso;
  return officialTimeOf(t);
}
