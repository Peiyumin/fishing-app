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
      // 断网时也把任务列出来（都标未完成），点「去完成」照样能跳转，
      // 只是领奖要等联网 —— 比整块空白好
      tasks: const [
        DailyTask(
            key: 'publish_catch',
            title: '发布 1 条渔获',
            desc: '每日发布 1 条渔获贴',
            points: 5,
            icon: 'fish'),
        DailyTask(
            key: 'publish_post',
            title: '发布任意类型帖',
            desc: '每日首次发布帖子',
            points: 3,
            icon: 'edit'),
        DailyTask(
            key: 'comment_2',
            title: '发布 2 条评论',
            desc: '每日发布任意 2 条评论',
            points: 3,
            icon: 'comment',
            target: 2),
        DailyTask(
            key: 'follow_2',
            title: '关注 2 名钓友',
            desc: '每日新关注 2 名钓友',
            points: 3,
            icon: 'follow',
            target: 2),
        DailyTask(
            key: 'checkin',
            title: '今日签到打卡',
            desc: '每天签到 1 次即可领取',
            points: 2,
            icon: 'check'),
      ],
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
      // 签到接口会顺带返回最新任务列表（「今日签到打卡」会立刻变成已完成）
      tasks: s.tasks,
    );
    _cache['status'] = updated;
    return (status: updated, reward: reward, streak: streak);
  }

  /// 领取某个任务的积分
  ///
  /// 返回 (points 本次到账, total 当前总积分, tasks 最新任务列表, already 是否已领过)
  static Future<
      ({
        int points,
        int total,
        List<DailyTask> tasks,
        bool already,
        String msg,
      })> claimTask(String key) async {
    final data = await ApiClient.post('/signin/tasks', {'key': key}) as Map;
    final map = data.cast<String, dynamic>();
    final list = (map['tasks'] as List?) ?? const [];
    final tasks = list
        .map((r) => DailyTask.fromJson((r as Map).cast<String, dynamic>()))
        .toList();
    final s = _cache['status'];
    if (s != null) {
      _cache['status'] = s.copyWith(
        tasks: tasks,
        points: (map['total'] as num?)?.toInt() ?? s.points,
      );
    }
    return (
      points: (map['points'] as num?)?.toInt() ?? 0,
      total: (map['total'] as num?)?.toInt() ?? 0,
      tasks: tasks,
      already: (map['already'] as bool?) ?? false,
      msg: (map['msg'] as String?) ?? '',
    );
  }

  /// 只刷新任务列表（不发全量状态）
  static Future<List<DailyTask>> tasks() async {
    try {
      final data = await ApiClient.get('/signin/tasks') as Map;
      final list = (data['tasks'] as List?) ?? const [];
      return list
          .map((r) => DailyTask.fromJson((r as Map).cast<String, dynamic>()))
          .toList();
    } catch (_) {
      return _cache['status']?.tasks ?? const [];
    }
  }
}
