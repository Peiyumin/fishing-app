/// 我的订单（商城：积分兑换 / 现金登记）
///
/// 状态与后台一致：
///   0 = 待处理（待发货）  1 = 已发货  2 = 已完成  3 = 已取消
import '../utils/json_num.dart';

/// 一条物流动态（v43）
///
/// 后端 shop_order_express_logs，App 只读。列表接口不返回，
/// 只有「订单详情」接口才带 express_logs（倒序，最新在最上面）。
class OrderExpressLog {
  final String status;
  final String content;
  final String createdAt;

  const OrderExpressLog({
    required this.status,
    required this.content,
    required this.createdAt,
  });

  factory OrderExpressLog.fromJson(Map<String, dynamic> m) => OrderExpressLog(
        status: (m['status'] ?? '').toString(),
        content: (m['content'] ?? '').toString(),
        createdAt: (m['created_at'] ?? '').toString(),
      );

  /// 与 MyOrder.createdAtText 同一套处理：后端是「本地时间带 Z」，不能走时区换算
  String get timeText {
    final s = createdAt;
    if (s.length < 16) return s;
    return '${s.substring(0, 10)} ${s.substring(11, 16)}';
  }
}

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

  // ---- v43：收货信息快照 + 快递 ----
  final String recvName;
  final String recvPhone;
  final String recvRegion;
  final String recvDetail;
  final String expressCompany;
  final String expressNo;
  final String expressStatus; // 当前物流状态（已揽收 / 运输中 / 派送中 / 已签收）
  final String shippedAt;
  final List<OrderExpressLog> expressLogs; // 仅详情接口有值

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
    this.recvName = '',
    this.recvPhone = '',
    this.recvRegion = '',
    this.recvDetail = '',
    this.expressCompany = '',
    this.expressNo = '',
    this.expressStatus = '',
    this.shippedAt = '',
    this.expressLogs = const [],
  });

  factory MyOrder.fromJson(Map<String, dynamic> m) {
    final qty = jsonInt(m['quantity']) ?? 1;
    final amt = double.tryParse((m['amount'] ?? '0').toString()) ?? 0;
    return MyOrder(
      id: (m['id'] ?? '').toString(),
      productId: (m['product_id'] ?? '').toString(),
      productName: (m['product_name'] ?? '商品').toString(),
      productImage: (m['product_image'] ?? '').toString(),
      type: (m['type'] ?? 'points').toString(),
      amount: (m['amount'] ?? '0').toString(),
      unitAmount: jsonDouble(m['unit_amount']) ??
          (qty > 0 ? amt / qty : amt),
      quantity: qty <= 0 ? 1 : qty,
      status: jsonInt(m['status']) ?? 0,
      statusLabel: (m['status_label'] ?? '').toString(),
      remark: (m['remark'] ?? '').toString(),
      createdAt: (m['created_at'] ?? '').toString(),
      recvName: (m['recv_name'] ?? '').toString(),
      recvPhone: (m['recv_phone'] ?? '').toString(),
      recvRegion: (m['recv_region'] ?? '').toString(),
      recvDetail: (m['recv_detail'] ?? '').toString(),
      expressCompany: (m['express_company'] ?? '').toString(),
      expressNo: (m['express_no'] ?? '').toString(),
      expressStatus: (m['express_status'] ?? '').toString(),
      shippedAt: (m['shipped_at'] ?? '').toString(),
      expressLogs: (m['express_logs'] is List)
          ? (m['express_logs'] as List)
              .whereType<Map>()
              .map((e) => OrderExpressLog.fromJson(Map<String, dynamic>.from(e)))
              .toList()
          : const [],
    );
  }

  bool get isPoints => type == 'points';

  /// 有没有快递单号（后台填过才为 true）
  bool get hasExpress => expressNo.isNotEmpty;

  /// 快递一行文案：「中通快递 78123456789」，只有单号时退化成单号
  String get expressText {
    if (expressNo.isEmpty) return expressCompany;
    if (expressCompany.isEmpty) return expressNo;
    return '$expressCompany $expressNo';
  }

  /// 收货信息一行文案（详情页「收货地址」）
  String get recvText {
    if (recvName.isEmpty && recvDetail.isEmpty) return '';
    final region = recvRegion.trim();
    final detail = recvDetail.trim();
    final addr = region.isEmpty ? detail : '$region $detail';
    final who = recvPhone.isEmpty ? recvName : '$recvName $recvPhone';
    return addr.isEmpty ? who : '$who\n$addr';
  }

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
    List<OrderExpressLog>? expressLogs,
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
        recvName: recvName,
        recvPhone: recvPhone,
        recvRegion: recvRegion,
        recvDetail: recvDetail,
        expressCompany: expressCompany,
        expressNo: expressNo,
        expressStatus: expressStatus,
        shippedAt: shippedAt,
        expressLogs: expressLogs ?? this.expressLogs,
      );
}
