import 'package:flutter/foundation.dart' show visibleForTesting;

import '../models/catch_weather.dart';
import '../models/post.dart';
import 'api_client.dart';
import 'api_config.dart';
import '../utils/json_num.dart';

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
      viewCount: 320,
      city: '武汉市',
    ),
  ];

  static bool get _demo => !ApiConfig.enabled;

  /// 演示模式下的示例动态（供「我的」页展示）
  static List<Post> get demoPosts => List<Post>.from(_demoPosts);

  /// 把后端 JSON 行映射为 Post 模型
  /// 对外暴露一层的映射（只给测试用）：后端 /posts 行的字段名与模型不完全一致
  /// （user_nickname / content / images / is_me=1），这里保证只有一份解析逻辑
  @visibleForTesting
  static Post mapApiRow(Map row) => _fromApi(row);

  static Post _fromApi(Map row) {
    return Post(
      id: (row['id'] ?? '').toString(),
      userId: (row['user_id'] ?? '').toString(),
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
      lat: jsonDouble(row['lat']),
      lng: jsonDouble(row['lng']),
      createdAt: jsonDateOrNow(row['created_at']),
      likeCount: jsonInt(row['like_count']) ?? 0,
      commentCount: jsonInt(row['comment_count']) ?? 0,
      viewCount: jsonInt(row['view_count']) ?? 0,
      city: (row['city'] as String?) ?? '',
      authorVip: jsonInt(row['user_vip']) ?? 0,
      // ★ is_me 后端给的是 1/0（PHP 里赋值 `$r['is_me'] = 1`），JSON 里是数字不是
      //   true/false —— 用 `as bool?` 会拿到 null，「我的作品」兜底里按 isMe 过滤
      //   就会一条都筛不出来。统一走容错解析。
      isMe: Post.truthy(row['is_me']),
      isFollowing: Post.truthy(row['is_following']),
      userLevel: jsonInt(row['user_level']) ?? 1,
      fish: Post.parseFish(row['fish']),
      locPublic: row['loc_public'] == null
          ? true
          : Post.truthy(row['loc_public']),
      lengthCm: jsonDouble(row['length_cm']),
      weightG: jsonDouble(row['weight_g']),
      weather: Post.parseWeather(row['weather'] ?? row['weather_json']),
    );
  }

  /// 拉取动态信息流
  /// tab:
  ///   null      默认（置顶优先 + 时间倒序，首页信息流）
  ///   recommend 推荐：浏览 + 点赞×3 + 评论×5 综合热度排序
  ///   hot       热门：按浏览人数取前 50 随机打乱（服务端打乱）
  ///   city      同城：city 地级市精确过滤
  ///   follow    关注：只看已关注用户（需登录）
  /// 仅测试用：非 null 时 [fetchFeed] 直接返回它，不碰网络。
  ///
  /// v2.1.49 去掉了「接口失败回落演示数据」之后，发现页的刷新测试没法再靠
  /// 「假 HttpClient 请求失败」拿到首屏数据了（那正是我们要禁掉的行为）。
  /// 给它一个显式注入口，比在测试里伪造一整套 HTTP 响应干净。
  @visibleForTesting
  static List<Post>? debugFeedOverride;

  static Future<List<Post>> fetchFeed({
    int limit = 20,
    int offset = 0,
    String? tab,
    String? city,
    String? keyword,
  }) async {
    final injected = debugFeedOverride;
    if (injected != null) return List<Post>.from(injected);
    if (_demo) {
      await Future.delayed(const Duration(milliseconds: 300));
      var list = List<Post>.from(_demoPosts);
      switch (tab) {
        case 'recommend':
          list.sort((a, b) =>
              (b.viewCount + b.likeCount * 3 + b.commentCount * 5)
                  .compareTo(a.viewCount + a.likeCount * 3 + a.commentCount * 5));
          break;
        case 'hot':
          list.sort((a, b) => b.viewCount.compareTo(a.viewCount));
          list = list.take(10).toList()..shuffle();
          break;
        case 'city':
          list = city == null
              ? []
              : list.where((p) => p.city == city).toList();
          break;
        case 'follow':
          list = []; // 演示模式：无关注数据
          break;
      }
      return list;
    }
    try {
      final data = jsonList(await ApiClient.get('/posts', {
        'page': '${offset ~/ limit + 1}',
        'size': '$limit',
        if (tab != null) 'tab': tab,
        if (city != null && city.isNotEmpty) 'city': city,
        // 后端 /posts 支持 keyword：按 标题 / 正文 模糊匹配
        if (keyword != null && keyword.isNotEmpty) 'keyword': keyword,
      }));
      var list = data.map((row) => _fromApi(row as Map)).toList();
      // 本地兜底过滤：老后端（未部署 Phase G）会忽略 tab/city 参数返回全量，
      // 客户端再过滤一次，保证「同城」「关注」语义始终正确
      if (tab == 'city' && city != null && city.isNotEmpty) {
        list = list.where((p) => p.city == city).toList();
      }
      // 推荐：浏览 + 点赞×3 + 评论×5 综合分倒序
      if (tab == 'recommend' && list.length > 1) {
        list.sort((a, b) {
          int score(Post p) =>
              p.viewCount + p.likeCount * 3 + p.commentCount * 5;
          return score(b).compareTo(score(a));
        });
      }
      // 热门：先按浏览人数取前 10，再随机打散（每次进入顺序不同）
      if (tab == 'hot' && list.length > 1) {
        list.sort((a, b) => b.viewCount.compareTo(a.viewCount));
        if (list.length > 10) list = list.take(10).toList();
        list.shuffle();
      }
      return list;
    } catch (_) {
      // ★★ v2.1.49：生产模式下**绝不能**回落演示数据。
      //
      //   以前这里无条件 `return _demoPosts`，接口只要超时一次，首页就会冒出
      //   「老钓翁 / 路亚阿杰 / 野钓阿强」这些内置假帖子。用户点进去看得到
      //   （详情是本地对象，不发请求），一评论就 POST /posts/d5/comment ——
      //   服务端根本没有 d5 这个 id → 返回 404 → nginx 的 fastcgi_intercept_errors
      //   把 404 换成静态 HTML 页 → App 端 jsonDecode 抛
      //   `FormatException: Unexpected character (at character 1) <html>`。
      //   用户看到的就是「评论失败：<html>」。
      //
      //   宁可让首页显示「动态加载失败，下拉重试」，也不能喂假数据 ——
      //   假数据的每一个交互都会失败，而且失败信息完全看不懂。
      if (_demo) return List<Post>.from(_demoPosts);
      rethrow;
    }
  }

  /// 按 id 拉单条动态（通知点击直达详情用）
  ///
  /// 通知里只有 postId，没有列表中的完整 Post 对象，必须能单独取一次。
  /// 帖子已被删除时返回 null（调用方提示「动态已删除」而不是白屏）。
  static Future<Post?> fetchById(String id) async {
    if (id.isEmpty) return null;
    if (_demo) {
      for (final p in _demoPosts) {
        if (p.id == id) return p;
      }
      return null;
    }
    try {
      final data = await ApiClient.get('/posts/$id');
      if (data is Map) return _fromApi(data);
    } catch (_) {}
    return null;
  }

  /// 发布动态：先上传图片（或单个视频），再写入动态
  /// 图片与视频二选一（后端同样限制不能混传）
  /// category: post 渔获 / ask 问答 / say 说说 / sell 出售 / buy 求购
  /// price: 仅 sell/buy 使用（售价 / 预算）
  /// fish: 渔获页「钓到了什么」[{'name':'鲫鱼','count':2}]
  /// locPublic: 钓点位置是否公开（false 时后端对其他人隐藏位置与坐标）
  /// markWatermark: 图片上传时让后端叠加水印（渔获照片走水印相机时通常已有前端水印）
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
    String city = '', // 地级市（App 定位反查后传入，同城 Tab 依据）
    List<Map<String, dynamic>> fish = const [],
    bool locPublic = true,
    bool markWatermark = false,
    double? lengthCm, // 渔获体长(cm)：AI 估算或用户手填
    double? weightG, // 渔获重量(g)
    CatchWeather? weather, // 渔获时天气快照（发布那一刻抓，之后详情页不再重算）
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
          fish: fish,
          locPublic: locPublic,
          lengthCm: lengthCm,
          weightG: weightG,
          weather: weather,
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
    final images = imageFiles.isEmpty
        ? <String>[]
        : await ApiClient.uploadImages(imageFiles, watermark: markWatermark);
    await ApiClient.post('/posts', {
      'title': title,
      'content': body,
      'images': images,
      if (videoUrl != null) 'video': videoUrl,
      'category': category,
      if (price.isNotEmpty) 'price': price,
      'location': locationName,
      'city': city,
      'lat': lat,
      'lng': lng,
      'fish': fish,
      'locPublic': locPublic,
      if (lengthCm != null) 'lengthCm': lengthCm,
      if (weightG != null) 'weightG': weightG,
      if (weather != null) 'weather': weather.toJson(),
    });
  }

  /// 我的渔获记录（池塘「按渔获投放」数据源）。
  /// 返回 [{id, fish, lengthCm, weightG, location, lat, lng, createdAt, image}]
  static Future<List<Map<String, dynamic>>> fetchMyCatches() async {
    if (_demo) return [];
    if (ApiClient.token == null) return [];
    try {
      // ★ v2.1.50 修：后端这个路由挂在 posts 块里（`$r1 === 'catch' && $r2 === 'mine'`），
      //   真实路径是 `/posts/catch/mine`。以前写 `/catch/mine`，顶层没有 catch 块，
      //   直接落到 404 → 池塘「按渔获投放」永远只能看到内置鱼，用户自己发的渔获进不来。
      final data = await ApiClient.get('/posts/catch/mine');
      if (data is List) {
        return data
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      }
    } catch (_) {}
    return [];
  }

  /// 浏览量 +1：进入动态详情时调用（失败静默，不影响浏览）
  static Future<void> trackView(String postId) async {
    if (_demo) return;
    try {
      await ApiClient.post('/posts/$postId/view');
    } catch (_) {}
  }

  /// 点赞 / 取消点赞，返回新的点赞状态
  static Future<bool> toggleLike(String postId, bool currentlyLiked) async {
    if (_demo) return !currentlyLiked; // 演示模式：仅本地切换高亮
    final data = jsonMap(await ApiClient.post('/posts/$postId/like'));
    return jsonBool(data['liked'], fallback: !currentlyLiked);
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
    final data = jsonList(await ApiClient.get('/posts/$postId/comments'));
    return List<Map<String, dynamic>>.from(data);
  }

  /// 我的发布列表（按当前登录用户查询自己的全部未删除动态）
  /// 用 Post.fromJson 解析，带上 is_me 标记，确保「我的发布」页完整且可编辑/删除
  ///
  /// ★ 这里**绝不能**回落到 _demoPosts：那三条（老钓翁/路亚小王/野钓阿强）是
  ///   内置演示数据，不是当前用户发的，一旦接口出错就会在「我的作品」里
  ///   冒出一堆别人的帖子（用户实测截图就是这么来的）。
  ///   - 未登录 → 空列表（页面会提示去登录）
  ///   - /posts/mine 失败（老后端把 mine 当成 post id 查了）→ 用公开列表
  ///     翻几页、按 is_me 过滤兜底，保证仍能看到自己的作品
  static Future<List<Post>> fetchMyPosts() async {
    if (_demo) return List<Post>.from(_demoPosts);
    if (ApiClient.token == null) return const [];
    try {
      final data = jsonList(await ApiClient.get('/posts/mine'));
      return data.map((row) => _fromApi(row as Map)).toList();
    } catch (_) {
      return _fetchMyPostsByScan();
    }
  }

  /// 兜底：翻公开列表，挑出 is_me 的（最多翻 3 页 / 150 条）
  static Future<List<Post>> _fetchMyPostsByScan() async {
    const pageSize = 50;
    final mine = <Post>[];
    try {
      for (var page = 1; page <= 3; page++) {
        final data = jsonList(await ApiClient.get('/posts', {
          'page': '$page',
          'size': '$pageSize',
        }));
        if (data.isEmpty) break;
        for (final row in data) {
          final p = _fromApi(row as Map);
          if (p.isMe) mine.add(p);
        }
        if (data.length < pageSize) break;
      }
    } catch (_) {
      // 连公开列表都取不到：返回已经拿到的部分（可能为空），由页面提示重试
    }
    mine.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return mine;
  }

  /// 删除自己发布的动态（仅作者，后端二次校验）
  static Future<void> deletePost(String postId) async {
    if (_demo) {
      _demoPosts.removeWhere((p) => p.id == postId);
      return;
    }
    if (ApiClient.token == null) throw Exception('请先登录');
    await ApiClient.post('/posts/$postId/delete', {});
  }

  /// 编辑自己发布的动态（仅作者，后端二次校验）
  /// [images] 为「最终要保留的图片 URL 列表」（已存在的网络图 + 本次新上传的图）
  /// 视频字段由后端保留原值，不在此更新
  static Future<void> updatePost(
    String postId, {
    required String? content,
    required List<String> images,
    bool locPublic = true,
    List<Map<String, dynamic>> fish = const [],
    double? lengthCm,
    double? weightG,
    CatchWeather? weather,
  }) async {
    if (_demo) return;
    if (ApiClient.token == null) throw Exception('请先登录');
    await ApiClient.post('/posts/$postId/update', {
      'content': content,
      'images': images,
      'locPublic': locPublic,
      'fish': fish,
      if (lengthCm != null) 'lengthCm': lengthCm,
      if (weightG != null) 'weightG': weightG,
      // 编辑时一般不改天气；传了才覆盖，没传后端保留原快照
      if (weather != null) 'weather': weather.toJson(),
    });
  }
}
