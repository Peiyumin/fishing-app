import '../models/post.dart';
import 'api_client.dart';
import 'api_config.dart';

/// 动态（渔获）相关的所有后端操作
/// 对接自建后端 /api/posts；后端不可用或未配置时自动走「演示模式」
class PostService {
  // ---------- 演示模式：后端未配置/不可达时使用 ----------
  static final List<Post> _demoPosts = [
    Post(
      id: 'd1',
      userId: 'u1',
      username: '老钓翁',
      title: '千岛湖爆护！一上午连杆大板鲫',
      body: '今天气压稳，风小，用红虫拉饵，狂口！',
      imageUrls: const [
        'https://picsum.photos/seed/fish1/600/400',
        'https://picsum.photos/seed/fish2/600/400',
      ],
      locationName: '千岛湖中心渔场',
      createdAt: DateTime.now().subtract(const Duration(hours: 2)),
      likeCount: 128,
      commentCount: 23,
    ),
    Post(
      id: 'd2',
      userId: 'u2',
      username: '路亚小王',
      title: '西溪路亚基地擒获米级鲈鱼',
      body: '亮片慢收，咬口超凶，手感拉满。',
      imageUrls: const ['https://picsum.photos/seed/fish3/600/400'],
      locationName: '西溪路亚基地',
      createdAt: DateTime.now().subtract(const Duration(hours: 5)),
      likeCount: 86,
      commentCount: 12,
    ),
    Post(
      id: 'd3',
      userId: 'u3',
      username: '野钓阿强',
      title: '富春江走水也能钓鳊鱼',
      body: '跑铅到底，玉米打窝玉米钓，连杆黄尾。',
      imageUrls: const [
        'https://picsum.photos/seed/fish4/600/400',
        'https://picsum.photos/seed/fish5/600/400',
        'https://picsum.photos/seed/fish6/600/400',
      ],
      locationName: '富春江野钓点',
      createdAt: DateTime.now().subtract(const Duration(hours: 9)),
      likeCount: 54,
      commentCount: 7,
    ),
    Post(
      id: 'd4',
      userId: 'u4',
      username: '黑坑老炮',
      title: '太湖湾正钓连杆，回鱼 8 块爽翻',
      body: '今天偷驴口爆，饵料用腥香，连杆到手软。',
      imageUrls: const ['https://picsum.photos/seed/fish7/600/400'],
      locationName: '太湖湾黑坑塘',
      createdAt: DateTime.now().subtract(const Duration(hours: 14)),
      likeCount: 73,
      commentCount: 15,
    ),
    Post(
      id: 'd5',
      userId: 'u5',
      username: '路亚阿杰',
      title: '金海湖翘嘴窗口期，米翘上岸',
      body: '清晨微风，铁板慢搜中层，一口秒切。',
      imageUrls: const [
        'https://picsum.photos/seed/fish8/600/400',
        'https://picsum.photos/seed/fish9/600/400',
      ],
      locationName: '金海湖路亚场',
      createdAt: DateTime.now().subtract(const Duration(hours: 20)),
      likeCount: 102,
      commentCount: 19,
    ),
    Post(
      id: 'd6',
      userId: 'u6',
      username: '东湖钓友',
      title: '东湖绿道休闲钓，鲫鱼连杆',
      body: '周末带娃出钓，拉饵搞定，收货满满。',
      imageUrls: const [],
      locationName: '东湖绿道野钓区',
      createdAt: DateTime.now().subtract(const Duration(hours: 28)),
      likeCount: 41,
      commentCount: 6,
    ),
  ];

  static bool get _demo => !ApiConfig.enabled;

  /// 演示模式下的示例动态（供「我的」页展示）
  static List<Post> get demoPosts => List<Post>.from(_demoPosts);

  /// 把后端 JSON 行映射为 Post 模型
  static Post _fromApi(Map row) {
    return Post(
      id: row['id'] as String,
      userId: (row['user_id'] ?? '') as String,
      username: row['user_nickname'] as String?,
      avatarUrl: ApiConfig.mediaUrl(row['user_avatar'] as String?),
      title: (row['title'] as String?) ?? '无标题',
      body: row['content'] as String?,
      imageUrls: ApiConfig.mediaList(row['images']),
      videoUrl: ApiConfig.mediaUrl(
          (row['video'] as String?)?.isNotEmpty == true
              ? row['video'] as String
              : null),
      category: (row['category'] as String?)?.isNotEmpty == true
          ? row['category'] as String
          : 'post',
      price: (row['price'] as String?) ?? '',
      locationName: row['location'] as String?,
      lat: (row['lat'] as num?)?.toDouble(),
      lng: (row['lng'] as num?)?.toDouble(),
      createdAt: DateTime.tryParse((row['created_at'] ?? '') as String) ??
          DateTime.now(),
      likeCount: (row['like_count'] as num?)?.toInt() ?? 0,
      commentCount: (row['comment_count'] as num?)?.toInt() ?? 0,
    );
  }

  /// 拉取动态信息流（置顶优先 + 时间倒序）
  static Future<List<Post>> fetchFeed({int limit = 20, int offset = 0}) async {
    if (_demo) {
      await Future.delayed(const Duration(milliseconds: 300));
      return List<Post>.from(_demoPosts);
    }
    try {
      final data = await ApiClient.get('/posts', {
        'page': '${offset ~/ limit + 1}',
        'size': '$limit',
      }) as List;
      return data.map((row) => _fromApi(row as Map)).toList();
    } catch (_) {
      // 后端不可达：回落到演示数据，保证 App 始终可用
      return List<Post>.from(_demoPosts);
    }
  }

  /// 发布动态：先上传图片（或单个视频），再写入动态
  /// 图片与视频二选一（后端同样限制不能混传）
  /// category: post 渔获 / ask 问答 / say 说说 / sell 出售 / buy 求购
  /// price: 仅 sell/buy 使用（售价 / 预算）
  static Future<void> publish({
    required String title,
    String? body,
    required List<String> imageFiles, // 本地图片路径
    String? videoFile, // 本地视频路径（与 imageFiles 二选一）
    String category = 'post',
    String price = '',
    String? locationName,
    double? lat,
    double? lng,
  }) async {
    if (_demo) {
      _demoPosts.insert(
        0,
        Post(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          userId: 'demo',
          username: '我（演示）',
          title: title,
          body: body,
          imageUrls: const [],
          videoUrl: videoFile,
          category: category,
          price: price,
          locationName: locationName,
          lat: lat,
          lng: lng,
          createdAt: DateTime.now(),
        ),
      );
      return;
    }
    if (ApiClient.token == null) throw Exception('请先登录');
    if (videoFile != null && imageFiles.isNotEmpty) {
      throw Exception('图片和视频不能一起发布，请分开发布');
    }
    String? videoUrl;
    if (videoFile != null) {
      final ext = videoFile.split('.').last.toLowerCase();
      final contentType = switch (ext) {
        'mov' => 'video/quicktime',
        'webm' => 'video/webm',
        _ => 'video/mp4',
      };
      videoUrl = await ApiClient.uploadFile(videoFile, contentType: contentType);
    }
    final images =
        imageFiles.isEmpty ? <String>[] : await ApiClient.uploadImages(imageFiles);
    await ApiClient.post('/posts', {
      'title': title,
      'content': body,
      'images': images,
      if (videoUrl != null) 'video': videoUrl,
      'category': category,
      if (price.isNotEmpty) 'price': price,
      'location': locationName,
      'lat': lat,
      'lng': lng,
    });
  }

  /// 点赞 / 取消点赞，返回新的点赞状态
  static Future<bool> toggleLike(String postId, bool currentlyLiked) async {
    if (_demo) return !currentlyLiked; // 演示模式：仅本地切换高亮
    final data = await ApiClient.post('/posts/$postId/like') as Map;
    return (data['liked'] as bool?) ?? !currentlyLiked;
  }

  /// 评论
  static Future<void> addComment(String postId, String content) async {
    if (_demo) return; // 演示模式：不持久化
    if (ApiClient.token == null) throw Exception('请先登录');
    await ApiClient.post('/posts/$postId/comment', {'content': content});
  }

  /// 评论列表（键：user_nickname / content / created_at）
  static Future<List<Map<String, dynamic>>> fetchComments(String postId) async {
    if (_demo) return [];
    final data = await ApiClient.get('/posts/$postId/comments') as List;
    return List<Map<String, dynamic>>.from(data);
  }
}
