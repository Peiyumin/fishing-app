/// 文章（垂钓技巧 / 路亚技巧·装备·评测）
///
/// 后端 `articles` 表，靠 category 区分归属哪个频道：
///   skill       垂钓技巧（首页「技巧」）
///   lure_skill  路亚技巧（「路亚」页）
///   lure_gear   路亚装备
///   lure_review 路亚评测
class Article {
  final String id;
  final String title;
  final String cover;
  final String category;
  final String categoryLabel;
  final String summary;

  /// 发布城市（投稿时按定位自动带上；空 = 不显示）
  final String city;
  final String content;
  final String authorId;
  final String authorName;
  final String statusLabel;
  final String rejectReason;
  final String createdAt;
  final int status;
  final int views;
  final int likeCount;

  /// 当前用户是否已点赞（游客恒 false）
  final bool liked;
  final bool featured;

  const Article({
    required this.id,
    required this.title,
    required this.cover,
    required this.category,
    required this.categoryLabel,
    required this.summary,
    this.city = '',
    required this.content,
    required this.authorId,
    required this.authorName,
    required this.statusLabel,
    required this.rejectReason,
    required this.createdAt,
    required this.status,
    required this.views,
    required this.likeCount,
    this.liked = false,
    required this.featured,
  });

  bool get isApproved => status == 1;
  bool get isPending => status == 0;
  bool get isRejected => status == 2;

  /// 「10月25日」
  String get dateText {
    if (createdAt.trim().isEmpty) return '';
    final d = DateTime.tryParse(createdAt.replaceAll('/', '-'));
    if (d == null) return createdAt;
    return '${d.month}月${d.day}日';
  }

  /// 正文按空行切成段落（不需要富文本解析，纯文本也能读得舒服）
  List<String> get paragraphs => content
      .split(RegExp(r'\r?\n\s*\r?\n'))
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .toList();

  factory Article.fromJson(Map<String, dynamic> j) {
    int asInt(dynamic v) => v is num ? v.toInt() : (int.tryParse('$v') ?? 0);
    String asStr(dynamic v) => v == null ? '' : '$v';
    bool asBool(dynamic v) => v == true || v == 1 || '$v' == '1';
    return Article(
      id: asStr(j['id']),
      title: asStr(j['title']),
      cover: asStr(j['cover']),
      category: asStr(j['category']),
      categoryLabel: asStr(j['category_label']),
      summary: asStr(j['summary']),
      city: asStr(j['city']),
      content: asStr(j['content']),
      authorId: asStr(j['author_id']),
      authorName: asStr(j['author_name']),
      statusLabel: asStr(j['status_label']),
      rejectReason: asStr(j['reject_reason']),
      createdAt: asStr(j['created_at']),
      status: asInt(j['status']),
      views: asInt(j['views']),
      likeCount: asInt(j['like_count']),
      liked: asBool(j['liked']),
      featured: asBool(j['is_featured']),
    );
  }
}
