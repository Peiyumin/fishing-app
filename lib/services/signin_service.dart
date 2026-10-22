import '../models/signin.dart';
import 'api_client.dart';
import 'api_config.dart';

/// 每日签到
class SigninService {
  static const _cache = <String, SigninStatus>{};

  /// 本地默认状态（后端不可用时兜底，保证签到页能打开）
  static SigninStatus get fallback {
    final rewards = List<SigninReward>.generate(
      7,
      (i) => SigninReward(
        points: i == 6 ? 30 : (i >= 4 ? 15 : (i >= 2 ? 10 : 5)),
      ),
    );
    return SigninStatus(
      rewards: rewards,
      rules: '每日可签到 1 次；连续签到 7 天为一个周期，中断后从第 1 天重新开始。',
    );
  }

  /// 拉取签到状态
  static Future<SigninStatus> status() async {
    if (!ApiConfig.enabled) return fallback;
    try {
      final data = await ApiClient.get('/signin') as Map;
      final s = SigninStatus.fromJson(data.cast<String, dynamic>());
      _cache['status'] = s;
      return s;
    } catch (_) {
      return _cache['status'] ?? fallback;
    }
  }

  /// 执行签到，返回最新状态与本次奖励
  static Future<({SigninStatus status, SigninReward reward, int streak})> checkin() async {
    final data = await ApiClient.post('/signin', {}) as Map;
    final map = data.cast<String, dynamic>();
    final reward = SigninReward.fromJson(
        (map['reward'] as Map?)?.cast<String, dynamic>() ?? const {});
    final streak = (map['streak'] as num?)?.toInt() ?? 0;
    final s = await status();
    final updated = SigninStatus(
      enabled: s.enabled,
      autoPopup: s.autoPopup,
      signedToday: true,
      streak: streak,
      total: s.total + 1,
      dayIndex: s.dayIndex,
      points: s.points + reward.points,
      balance: s.balance + reward.balance,
      pointsName: s.pointsName,
      rules: s.rules,
      rewards: s.rewards,
    );
    _cache['status'] = updated;
    return (status: updated, reward: reward, streak: streak);
  }
}
