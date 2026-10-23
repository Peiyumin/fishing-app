/// 每日签到状态
class SigninStatus {
  final bool enabled;
  final bool autoPopup;
  final bool signedToday;
  final int streak; // 当前连续天数
  final int total; // 累计签到天数
  final int dayIndex; // 下一次签到拿第几天奖励（1~7）
  final int points;
  final double balance;
  final String pointsName;
  final String rules;
  final List<SigninReward> rewards;

  /// 每日任务（后端按当天真实行为统计，v2.1.16）
  final List<DailyTask> tasks;

  const SigninStatus({
    this.enabled = true,
    this.autoPopup = true,
    this.signedToday = false,
    this.streak = 0,
    this.total = 0,
    this.dayIndex = 1,
    this.points = 0,
    this.balance = 0,
    this.pointsName = '积分',
    this.rules = '',
    this.rewards = const [],
    this.tasks = const [],
  });

  factory SigninStatus.fromJson(Map<String, dynamic> j) {
    final list = (j['rewards'] as List?) ?? const [];
    final t = (j['tasks'] as List?) ?? const [];
    return SigninStatus(
      enabled: (j['enabled'] as num?)?.toInt() == 1,
      autoPopup: (j['autoPopup'] as num?)?.toInt() == 1,
      signedToday: (j['signedToday'] as bool?) ?? false,
      streak: (j['streak'] as num?)?.toInt() ?? 0,
      total: (j['total'] as num?)?.toInt() ?? 0,
      dayIndex: (j['dayIndex'] as num?)?.toInt() ?? 1,
      points: (j['points'] as num?)?.toInt() ?? 0,
      balance: (j['balance'] as num?)?.toDouble() ?? 0,
      pointsName: (j['pointsName'] as String?) ?? '积分',
      rules: (j['rules'] as String?) ?? '',
      rewards: list
          .map((r) => SigninReward.fromJson((r as Map).cast<String, dynamic>()))
          .toList(),
      tasks: t
          .map((r) => DailyTask.fromJson((r as Map).cast<String, dynamic>()))
          .toList(),
    );
  }

  /// 换一份任务列表（领奖 / 签到后局部更新，不整页重拉）
  SigninStatus copyWith({
    List<DailyTask>? tasks,
    int? points,
    bool? signedToday,
    int? streak,
    int? total,
  }) =>
      SigninStatus(
        enabled: enabled,
        autoPopup: autoPopup,
        signedToday: signedToday ?? this.signedToday,
        streak: streak ?? this.streak,
        total: total ?? this.total,
        dayIndex: dayIndex,
        points: points ?? this.points,
        balance: balance,
        pointsName: pointsName,
        rules: rules,
        rewards: rewards,
        tasks: tasks ?? this.tasks,
      );
}

/// 一条每日任务
class DailyTask {
  final String key;
  final String title;
  final String desc;
  final int points;
  final String icon;
  final int target;
  final int progress;
  final bool done;
  final bool claimed;

  const DailyTask({
    required this.key,
    required this.title,
    required this.desc,
    this.points = 0,
    this.icon = '',
    this.target = 1,
    this.progress = 0,
    this.done = false,
    this.claimed = false,
  });

  factory DailyTask.fromJson(Map<String, dynamic> j) => DailyTask(
        key: (j['key'] as String?) ?? '',
        title: (j['title'] as String?) ?? '',
        desc: (j['desc'] as String?) ?? '',
        points: (j['points'] as num?)?.toInt() ?? 0,
        icon: (j['icon'] as String?) ?? '',
        target: (j['target'] as num?)?.toInt() ?? 1,
        progress: (j['progress'] as num?)?.toInt() ?? 0,
        done: (j['done'] as bool?) ?? false,
        claimed: (j['claimed'] as bool?) ?? false,
      );
}

/// 单日签到奖励
class SigninReward {
  final int points;
  final double balance;

  const SigninReward({this.points = 0, this.balance = 0});

  bool get isEmpty => points <= 0 && balance <= 0;

  String describe(String pointsName) {
    final parts = <String>[];
    if (points > 0) parts.add('$points $pointsName');
    if (balance > 0) parts.add('¥${_trim(balance)}');
    return parts.isEmpty ? '无奖励' : parts.join(' + ');
  }

  static String _trim(double v) {
    final s = v.toStringAsFixed(2);
    return s.endsWith('.00') ? s.substring(0, s.length - 3) : s;
  }

  factory SigninReward.fromJson(Map<String, dynamic> j) => SigninReward(
        points: (j['points'] as num?)?.toInt() ?? 0,
        balance: (j['balance'] as num?)?.toDouble() ?? 0,
      );
}
