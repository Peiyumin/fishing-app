import '../models/fish.dart';
import 'api_client.dart';
import 'api_config.dart';

/// 鱼种图鉴
class FishService {
  static FishGuide? _cache;

  static FishGuide get fallback => const FishGuide(level: FishLevel());

  /// 图鉴数据
  static Future<FishGuide> guide() async {
    if (!ApiConfig.enabled) return _cache ?? fallback;
    try {
      final data = await ApiClient.get('/fish/guide') as Map;
      final g = FishGuide.fromJson(data.cast<String, dynamic>());
      _cache = g;
      return g;
    } catch (_) {
      return _cache ?? fallback;
    }
  }

  /// 手动激活鱼种
  static Future<FishGuide> unlock(String speciesId, {String image = ''}) async {
    final data = await ApiClient.post('/fish/unlock', {
      'speciesId': speciesId,
      if (image.isNotEmpty) 'image': image,
    }) as Map;
    final g = FishGuide.fromJson(
        (data['guide'] as Map?)?.cast<String, dynamic>() ?? const {});
    _cache = g;
    return g;
  }

  /// AI 识别（未配置 AI 时 needManual = true）
  static Future<FishRecognize> recognize(String imageUrl) async {
    final data = await ApiClient.post('/fish/recognize', {'image': imageUrl}) as Map;
    return FishRecognize.fromJson(data.cast<String, dynamic>());
  }

  /// AI 大模型鱼口判断：把逐时天气 + 鱼种习性交给大模型。
  /// 后端未配置 AI 时 ok=false（App 回退本地规则引擎）；网络异常抛错由调用方兜底。
  static Future<AiBite> biteAi(Map<String, dynamic> payload) async {
    final data = await ApiClient.post('/fish/bite-ai', payload) as Map;
    return AiBite.fromJson(data.cast<String, dynamic>());
  }
}
