import '../models/ai_spot.dart';
import '../models/fish.dart';
import 'api_client.dart';
import 'api_config.dart';
import '../utils/json_num.dart';

/// 鱼种图鉴
class FishService {
  static FishGuide? _cache;

  /// 登录态变化（登录 / 退出 / 换账号）时必须清掉：
  /// 图鉴是**按账号统计**的，缓存不清就会出现「换了账号还是上一个号的数据」
  /// 或「退出登录后还显示之前的解锁进度」。
  static void clearCache() => _cache = null;

  static FishGuide get fallback => const FishGuide(level: FishLevel());

  /// 图鉴数据
  static Future<FishGuide> guide() async {
    if (!ApiConfig.enabled) return _cache ?? fallback;
    try {
      final data = jsonMap(await ApiClient.get('/fish/guide'));
      final g = FishGuide.fromJson(data.cast<String, dynamic>());
      _cache = g;
      return g;
    } catch (_) {
      return _cache ?? fallback;
    }
  }

  /// 手动激活鱼种
  static Future<FishGuide> unlock(String speciesId, {String image = ''}) async {
    final data = jsonMap(await ApiClient.post('/fish/unlock', {
      'speciesId': speciesId,
      if (image.isNotEmpty) 'image': image,
    }));
    final g = FishGuide.fromJson(
        (data['guide'] as Map?)?.cast<String, dynamic>() ?? const {});
    _cache = g;
    return g;
  }

  /// AI 识别（未配置 AI 时 needManual = true）
  static Future<FishRecognize> recognize(String imageUrl) async {
    final data = jsonMap(await ApiClient.post('/fish/recognize', {'image': imageUrl}));
    return FishRecognize.fromJson(data.cast<String, dynamic>());
  }

  /// AI 大模型鱼口判断：把逐时天气 + 鱼种习性交给大模型。
  /// 后端未配置 AI 时 ok=false（App 回退本地规则引擎）；网络异常抛错由调用方兜底。
  static Future<AiBite> biteAi(Map<String, dynamic> payload) async {
    final data = jsonMap(await ApiClient.post('/fish/bite-ai', payload));
    return AiBite.fromJson(data.cast<String, dynamic>());
  }

  /// AI 找钓点：附近水域 + 当前天气 → 大模型推荐现在最值得去的水域。
  /// 后端未配置 AI 时 ok=false。
  static Future<AiSpotRec> spotAi(Map<String, dynamic> payload) async {
    final data = jsonMap(await ApiClient.post('/fish/spot-ai', payload));
    return AiSpotRec.fromJson(data.cast<String, dynamic>());
  }
}
