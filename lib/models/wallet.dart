import '../services/api_config.dart';

/// 钱包总览（余额 + 积分 + 汇总）
class WalletInfo {
  final double balance;
  final int points;
  final String pointsName;
  final double totalIn;
  final double totalOut;
  final int totalPoints;

  const WalletInfo({
    this.balance = 0,
    this.points = 0,
    this.pointsName = '积分',
    this.totalIn = 0,
    this.totalOut = 0,
    this.totalPoints = 0,
  });

  factory WalletInfo.fromJson(Map<String, dynamic> j) {
    final s = (j['summary'] as Map?)?.cast<String, dynamic>() ?? const {};
    return WalletInfo(
      balance: (j['balance'] as num?)?.toDouble() ?? 0,
      points: (j['points'] as num?)?.toInt() ?? 0,
      pointsName: (j['pointsName'] as String?) ?? '积分',
      totalIn: (s['totalIn'] as num?)?.toDouble() ?? 0,
      totalOut: (s['totalOut'] as num?)?.toDouble() ?? 0,
      totalPoints: (s['totalPoints'] as num?)?.toInt() ?? 0,
    );
  }
}

/// 钱包流水
class WalletLog {
  final String id;
  final String type; // charge 充值 / consume 消费 / reward 奖励 / adjust 调整
  final double amount; // 正=入账，负=扣款
  final double balanceAfter;
  final int pointsDelta;
  final String title;
  final String remark;
  final String createdAt;

  const WalletLog({
    required this.id,
    this.type = 'adjust',
    this.amount = 0,
    this.balanceAfter = 0,
    this.pointsDelta = 0,
    this.title = '',
    this.remark = '',
    this.createdAt = '',
  });

  bool get isIncome => amount > 0;

  factory WalletLog.fromJson(Map<String, dynamic> j) => WalletLog(
        id: (j['id'] ?? '').toString(),
        type: (j['type'] ?? '').toString(),
        amount: (j['amount'] as num?)?.toDouble() ?? 0,
        balanceAfter: (j['balanceAfter'] as num?)?.toDouble() ?? 0,
        pointsDelta: (j['pointsDelta'] as num?)?.toInt() ?? 0,
        title: (j['title'] ?? '').toString(),
        remark: (j['remark'] ?? '').toString(),
        createdAt: (j['createdAt'] ?? '').toString(),
      );
}

/// 充值档位
class ChargePlan {
  final String id;
  final String title;
  final double amount;
  final double bonus;
  final int pointsBonus;

  const ChargePlan({
    required this.id,
    this.title = '',
    this.amount = 0,
    this.bonus = 0,
    this.pointsBonus = 0,
  });

  String get amountText => '¥${_trim(amount)}';
  String get bonusText => bonus > 0 ? '赠 ¥${_trim(bonus)}' : '';
  String get pointsBonusText => pointsBonus > 0 ? '赠 $pointsBonus 积分' : '';

  static String _trim(double v) {
    final s = v.toStringAsFixed(2);
    return s.endsWith('.00') ? s.substring(0, s.length - 3) : s;
  }

  factory ChargePlan.fromJson(Map<String, dynamic> j) => ChargePlan(
        id: (j['id'] ?? '').toString(),
        title: (j['title'] ?? '').toString(),
        amount: (j['amount'] as num?)?.toDouble() ?? 0,
        bonus: (j['bonus'] as num?)?.toDouble() ?? 0,
        pointsBonus: (j['pointsBonus'] as num?)?.toInt() ?? 0,
      );
}

/// 充值单
class ChargeOrder {
  final String id;
  final String title;
  final double amount;
  final double bonus;
  final int status; // 0 待确认 / 1 已到账 / 2 已取消
  final String createdAt;

  const ChargeOrder({
    required this.id,
    this.title = '',
    this.amount = 0,
    this.bonus = 0,
    this.status = 0,
    this.createdAt = '',
  });

  String get statusText =>
      status == 1 ? '已到账' : (status == 2 ? '已取消' : '待确认');

  factory ChargeOrder.fromJson(Map<String, dynamic> j) => ChargeOrder(
        id: (j['id'] ?? '').toString(),
        title: (j['title'] ?? '').toString(),
        amount: (j['amount'] as num?)?.toDouble() ?? 0,
        bonus: (j['bonus'] as num?)?.toDouble() ?? 0,
        status: (j['status'] as num?)?.toInt() ?? 0,
        createdAt: (j['createdAt'] ?? '').toString(),
      );
}

/// 头像 URL 工具（钱包/会员等页面复用）
String mediaUrlOf(String? raw) => ApiConfig.mediaUrl(raw) ?? '';
