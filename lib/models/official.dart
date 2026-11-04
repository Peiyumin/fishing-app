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

/// 一条公告
///
/// v41 起公告不再是帖子：它单独存在 official_notices 里，只在
/// 「消息 → 系统通知」以「官方公告」出现，绝不会进首页/发现的信息流。
/// 所以这里的字段比帖子窄 —— 没有点赞、没有评论，只有标题/正文/配图/时间/作者。
class OfficialNotice {
  final String id;
  final String title;
  final String content;

  /// 配图（最多 9 张，绝对地址）
  final List<String> images;
  final bool pinned;
  final DateTime createdAt;
  final String authorName;
  final String authorAvatar;
  final bool isMine;

  const OfficialNotice({
    required this.id,
    required this.title,
    required this.content,
    this.images = const [],
    this.pinned = false,
    required this.createdAt,
    this.authorName = '',
    this.authorAvatar = '',
    this.isMine = false,
  });

  factory OfficialNotice.fromJson(Map<String, dynamic> j) => OfficialNotice(
        id: (j['id'] ?? '').toString(),
        title: (j['title'] ?? '').toString(),
        content: (j['content'] ?? '').toString(),
        images: _stringList(j['images']),
        pinned: jsonInt(j['pinned']) == 1 || j['pinned'] == true,
        createdAt: jsonDateOrNow(j['createdAt']),
        authorName: (j['authorName'] ?? '').toString(),
        authorAvatar: _mediaUrl(j['authorAvatar']) ?? '',
        isMine: jsonBool(j['isMine']),
      );

  /// 列表里的一行摘要（换行压平成空格）
  String get summary =>
      content.replaceAll(RegExp(r'\s+'), ' ').trim();
}

/// 把后端返回的 images 字段读成字符串列表（数组 / 单个字符串都兼容）
List<String> _stringList(dynamic raw) {
  if (raw == null) return const [];
  if (raw is String) {
    final s = raw.trim();
    return s.isEmpty ? const [] : <String>[s];
  }
  if (raw is List) {
    return raw
        .map((e) => e?.toString().trim() ?? '')
        .where((e) => e.isNotEmpty)
        .toList();
  }
  return const [];
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
      case 'spot_edit':
        return '编辑钓点';
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

// ══════════════════ 钓点管理（v41） ══════════════════

/// 钓点管理列表里的一行（列表只带概要，点进去再取全字段）
class OfficialSpot {
  final String id;
  final String name;
  final String kind; // venue 钓场 / wild 野钓点 / shop 渔具店
  final String type; // 野钓 / 黑坑 / 路亚…
  final int status;  // 0 待审核 / 1 已上架 / 2 已下架
  final String statusLabel;
  final String address;
  final String? cover;
  final double? lat;
  final double? lng;
  final int imageCount;
  final int reportCount;
  final DateTime createdAt;

  const OfficialSpot({
    required this.id,
    required this.name,
    this.kind = 'venue',
    this.type = '',
    this.status = 1,
    this.statusLabel = '',
    this.address = '',
    this.cover,
    this.lat,
    this.lng,
    this.imageCount = 0,
    this.reportCount = 0,
    required this.createdAt,
  });

  String get kindLabel =>
      kind == 'venue' ? '钓场' : (kind == 'shop' ? '渔具店' : '野钓点');

  bool get hasLocation => lat != null && lng != null;

  factory OfficialSpot.fromJson(Map<String, dynamic> j) => OfficialSpot(
        id: (j['id'] ?? '').toString(),
        name: (j['name'] ?? '').toString(),
        kind: (j['kind'] ?? 'venue').toString(),
        type: (j['type'] ?? '').toString(),
        status: jsonInt(j['status']) ?? 1,
        statusLabel: (j['statusLabel'] ?? '').toString(),
        address: (j['address'] ?? '').toString(),
        cover: _mediaUrl(j['cover']),
        lat: jsonDouble(j['lat']),
        lng: jsonDouble(j['lng']),
        imageCount: jsonInt(j['imageCount']) ?? 0,
        reportCount: jsonInt(j['reportCount']) ?? 0,
        createdAt: jsonDateOrNow(j['createdAt']),
      );
}

/// 钓点编辑页的完整表单（和 /official/spot 一一对应）
///
/// 单独一个类而不是复用 FishingSpot：编辑页要能拿到 status（未上架的也要能进来改），
/// 而 FishingSpot 是「给用户看」的模型，不该背审核状态。
class OfficialSpotDraft {
  String id;
  String name;
  String kind;
  String type;
  int status;
  String description;
  String address;
  String fee;
  String fish;
  String tags;
  String cover;
  String phone;
  bool delivery;
  double lat;
  double lng;
  double rating;
  List<String> images;

  OfficialSpotDraft({
    this.id = '',
    this.name = '',
    this.kind = 'venue',
    this.type = '野钓',
    this.status = 1,
    this.description = '',
    this.address = '',
    this.fee = '',
    this.fish = '',
    this.tags = '',
    this.cover = '',
    this.phone = '',
    this.delivery = false,
    this.lat = 0,
    this.lng = 0,
    this.rating = 0,
    this.images = const [],
  });

  factory OfficialSpotDraft.fromJson(Map<String, dynamic> j) => OfficialSpotDraft(
        id: (j['id'] ?? '').toString(),
        name: (j['name'] ?? '').toString(),
        kind: (j['kind'] ?? 'venue').toString(),
        type: (j['type'] ?? '野钓').toString(),
        status: jsonInt(j['status']) ?? 1,
        description: (j['description'] ?? '').toString(),
        address: (j['address'] ?? '').toString(),
        fee: (j['fee'] ?? '').toString(),
        fish: (j['fish'] ?? '').toString(),
        tags: (j['tags'] ?? '').toString(),
        cover: (_mediaUrl(j['cover']) ?? ''),
        phone: (j['phone'] ?? '').toString(),
        delivery: (jsonInt(j['delivery']) ?? 0) == 1,
        lat: jsonDouble(j['lat']) ?? 0,
        lng: jsonDouble(j['lng']) ?? 0,
        rating: jsonDouble(j['rating']) ?? 0,
        images: _stringList(j['images']),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'kind': kind,
        'type': type,
        'status': status,
        'description': description,
        'address': address,
        'fee': fee,
        'fish': fish,
        'tags': tags,
        'cover': cover,
        'phone': phone,
        'delivery': delivery,
        'lat': lat,
        'lng': lng,
        'rating': rating,
        'images': images,
      };

  /// 用编辑页上的最新值覆盖（保存时是全字段覆盖，不做 diff）
  OfficialSpotDraft copyWithFields({
    String? name,
    String? kind,
    String? type,
    int? status,
    String? description,
    String? address,
    String? fee,
    String? fish,
    String? tags,
    String? cover,
    String? phone,
    bool? delivery,
    double? lat,
    double? lng,
    double? rating,
    List<String>? images,
  }) =>
      OfficialSpotDraft(
        id: id,
        name: name ?? this.name,
        kind: kind ?? this.kind,
        type: type ?? this.type,
        status: status ?? this.status,
        description: description ?? this.description,
        address: address ?? this.address,
        fee: fee ?? this.fee,
        fish: fish ?? this.fish,
        tags: tags ?? this.tags,
        cover: cover ?? this.cover,
        phone: phone ?? this.phone,
        delivery: delivery ?? this.delivery,
        lat: lat ?? this.lat,
        lng: lng ?? this.lng,
        rating: rating ?? this.rating,
        images: images ?? this.images,
      );
}
