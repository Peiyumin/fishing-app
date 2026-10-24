/// 我的订单（商城：积分兑换 / 现金登记）
///
/// 状态与后台一致：
///   0 = 待处理（待发货）  1 = 已发货  2 = 已完成  3 = 已取消
class MyOrder {
  final String id;
  final String productId;
  final String productName;
  final String productImage; // 绝对地址，空串表示商品已下架或无图
  final String type; // points | cash
  final String amount; // 合计（积分或元，字符串）
  final double unitAmount; // 单价
  final int quantity;
  final int status;
  final String statusLabel;
  final String remark;
  final String createdAt; // 后端返回 2026-10-24T13:20:05.123Z（其实是本地时间）

  const MyOrder({
    required this.id,
    required this.productId,
    required this.productName,
    required this.productImage,
    required this.type,
    required this.amount,
    required this.unitAmount,
    required this.quantity,
    required this.status,
    required this.statusLabel,
    required this.remark,
    required this.createdAt,
  });

  factory MyOrder.fromJson(Map<String, dynamic> m) {
    final qty = (m['quantity'] as num?)?.toInt() ?? 1;
    final amt = double.tryParse((m['amount'] ?? '0').toString()) ?? 0;
    return MyOrder(
      id: (m['id'] ?? '').toString(),
      productId: (m['product_id'] ?? '').toString(),
      productName: (m['product_name'] ?? '商品').toString(),
      productImage: (m['product_image'] ?? '').toString(),
      type: (m['type'] ?? 'points').toString(),
      amount: (m['amount'] ?? '0').toString(),
      unitAmount: (m['unit_amount'] as num?)?.toDouble() ??
          (qty > 0 ? amt / qty : amt),
      quantity: qty <= 0 ? 1 : qty,
      status: (m['status'] as num?)?.toInt() ?? 0,
      statusLabel: (m['status_label'] ?? '').toString(),
      remark: (m['remark'] ?? '').toString(),
      createdAt: (m['created_at'] ?? '').toString(),
    );
  }

  bool get isPoints => type == 'points';

  /// 待处理 / 待发货
  bool get canCancel => status == 0;

  /// 已发货才能确认收货
  bool get canConfirm => status == 1;

  bool get isDone => status == 2;
  bool get isCancelled => status == 3;

  /// 能不能从列表里删掉
  ///
  /// 只允许已完成 / 已取消的订单删除：待发货的必须走「取消订单」
  /// （要退积分、恢复库存），不能直接抹掉，否则账对不上。
  bool get canDelete => status == 2 || status == 3;

  String get typeLabel => isPoints ? '积分兑换' : '现金购买';

  /// 金额展示：积分单显示「1200 积分」，现金单显示「¥19.90」
  String get amountText {
    if (isPoints) return '$amount 积分';
    final v = double.tryParse(amount) ?? 0;
    return '¥${v.toStringAsFixed(2)}';
  }

  String get unitText {
    if (isPoints) return '${unitAmount.toStringAsFixed(0)} 积分';
    return '¥${unitAmount.toStringAsFixed(2)}';
  }

  String get label {
    if (statusLabel.isNotEmpty) return statusLabel;
    const map = {0: '待处理', 1: '已发货', 2: '已完成', 3: '已取消'};
    return map[status] ?? '待处理';
  }

  /// 下单时间：后端给的是「本地时间却带 Z 后缀」的 ISO 串，
  /// 直接 DateTime.parse 会被当 UTC 再转本地，凭空多出 8 小时。
  /// 这里按字符串取 YYYY-MM-DD HH:mm，不参与时区换算。
  String get createdAtText {
    final s = createdAt;
    if (s.length < 16) return s;
    final d = s.substring(0, 10);
    final t = s.substring(11, 16);
    return '$d $t';
  }

  MyOrder copyWith({
    int? status,
    String? statusLabel,
  }) =>
      MyOrder(
        id: id,
        productId: productId,
        productName: productName,
        productImage: productImage,
        type: type,
        amount: amount,
        unitAmount: unitAmount,
        quantity: quantity,
        status: status ?? this.status,
        statusLabel: statusLabel ?? this.statusLabel,
        remark: remark,
        createdAt: createdAt,
      );
}
