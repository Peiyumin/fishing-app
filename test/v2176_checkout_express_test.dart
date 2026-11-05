import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:fishing_app/models/my_order.dart';
import 'package:fishing_app/services/shop_service.dart';

/// v2.1.76：积分兑换填收货地址 + 订单快递信息
///
/// 两个需求的护栏：
///   ① 兑换前必须填地址（收货人 / 手机号 / 详细地址），保存的地址写进
///      user_addresses ——「设置 → 收货地址」里要能同时看到；
///   ② 兑换成功后发系统通知；「我的订单」里显示快递公司与单号 + 物流动态。
///
/// 测试环境没有登录态，createOrder 会在最后一步抛「请先登录」，
/// 但请求体在抛异常之前就拼好并记进 testLastOrderBody 了 —— 正是要验的东西。
void main() {
  String read(String p) => File(p).readAsStringSync();

  setUp(() => ShopService.testLastOrderBody = null);

  Future<Map<String, dynamic>?> order({
    required bool usePoints,
    String name = '',
    String phone = '',
    String region = '',
    String detail = '',
  }) async {
    try {
      await ShopService.createOrder(
        productId: 'p1',
        usePoints: usePoints,
        recvName: name,
        recvPhone: phone,
        recvRegion: region,
        recvDetail: detail,
      );
    } catch (_) {
      // 没登录必抛，忽略；body 已经记录
    }
    return ShopService.testLastOrderBody;
  }

  group('兑换请求体带收货地址', () {
    test('四个字段都传进去', () async {
      final b = await order(
        usePoints: true,
        name: '张三',
        phone: '13800138000',
        region: '浙江省杭州市余杭区',
        detail: '文一西路 123 号 5 幢 601',
      );
      expect(b, isNotNull);
      expect(b!['recv_name'], '张三');
      expect(b['recv_phone'], '13800138000');
      expect(b['recv_region'], '浙江省杭州市余杭区');
      expect(b['recv_detail'], '文一西路 123 号 5 幢 601');
      expect(b['type'], 'points');
      expect(b['product_id'], 'p1');
    });

    test('所在地区选填，不填就不带这个键', () async {
      final b = await order(
        usePoints: true,
        name: '李四',
        phone: '13900139000',
        detail: '某某路 1 号',
      );
      expect(b!.containsKey('recv_region'), isFalse);
      expect(b['recv_detail'], '某某路 1 号');
    });

    test('完全没填地址时一个 recv_ 键都不出现（老流程兜底）', () async {
      final b = await order(usePoints: false);
      expect(b, isNotNull);
      expect(b!.keys.where((k) => k.startsWith('recv_')), isEmpty);
      expect(b['type'], 'cash');
    });
  });

  group('订单模型解析快递与收货信息', () {
    Map<String, dynamic> row([Map<String, dynamic> extra = const {}]) => {
          'id': 'o1',
          'product_id': 'p1',
          'product_name': '抄网',
          'product_image': '',
          'type': 'points',
          'amount': '1200',
          'quantity': 1,
          'status': 1,
          'status_label': '已发货',
          'remark': '',
          'created_at': '2026-11-05T10:20:30.000Z',
          'recv_name': '王五',
          'recv_phone': '13700137000',
          'recv_region': '江苏省南京市',
          'recv_detail': '中山路 8 号',
          'express_company': '中通快递',
          'express_no': '78123456789',
          'express_status': '运输中',
          'shipped_at': '2026-11-05T18:00:00.000Z',
          ...extra,
        };

    test('fromJson 读全字段', () {
      final o = MyOrder.fromJson(row());
      expect(o.recvName, '王五');
      expect(o.recvPhone, '13700137000');
      expect(o.expressCompany, '中通快递');
      expect(o.expressNo, '78123456789');
      expect(o.expressStatus, '运输中');
      expect(o.hasExpress, isTrue);
    });

    test('老后端没有这些列时全部退化成空串，不抛异常', () {
      final o = MyOrder.fromJson({
        'id': 'o2',
        'product_name': '鱼线',
        'type': 'cash',
        'amount': '19.9',
        'quantity': 1,
        'status': 0,
        'created_at': '2026-11-05T10:20:30.000Z',
      });
      expect(o.recvName, '');
      expect(o.expressNo, '');
      expect(o.hasExpress, isFalse);
      expect(o.expressText, '');
      expect(o.recvText, '');
      expect(o.expressLogs, isEmpty);
    });

    test('快递文案：公司 + 单号 / 只有单号 / 只有公司', () {
      expect(MyOrder.fromJson(row()).expressText, '中通快递 78123456789');
      expect(MyOrder.fromJson(row({'express_company': ''})).expressText,
          '78123456789');
      expect(MyOrder.fromJson(row({'express_no': ''})).expressText, '中通快递');
    });

    test('收货信息文案：姓名电话换行地址', () {
      expect(MyOrder.fromJson(row()).recvText, '王五 13700137000\n江苏省南京市 中山路 8 号');
      // 没有地区时不出现多余空格
      expect(MyOrder.fromJson(row({'recv_region': ''})).recvText,
          '王五 13700137000\n中山路 8 号');
    });

    test('物流轨迹按后端顺序解析，时间不做时区换算', () {
      final o = MyOrder.fromJson(row({
        'express_logs': [
          {
            'status': '运输中',
            'content': '快件已到达【杭州转运中心】',
            'created_at': '2026-11-05T19:30:00.000Z',
          },
          {
            'status': '已揽收',
            'content': '快递员已揽收',
            'created_at': '2026-11-05T18:00:00.000Z',
          },
        ],
      }));
      expect(o.expressLogs.length, 2);
      expect(o.expressLogs.first.status, '运输中');
      // ★ 后端给的是本地时间却带 Z，不能 DateTime.parse（会凭空 +8 小时）
      expect(o.expressLogs.first.timeText, '2026-11-05 19:30');
    });

    test('express_logs 不是数组时不崩', () {
      final o = MyOrder.fromJson(row({'express_logs': 'oops'}));
      expect(o.expressLogs, isEmpty);
    });
  });

  group('兑换弹层源码护栏', () {
    final detail = read('lib/screens/product_detail_screen.dart');

    test('有地址弹层', () {
      expect(detail.contains('class _CheckoutSheet'), isTrue);
      expect(detail.contains('showModalBottomSheet<UserAddress>'), isTrue);
      // 用户取消/关闭弹层就不下单
      expect(detail.contains('if (picked == null) return;'), isTrue);
    });

    test('表单字段就是收货人 / 手机号 / 详细地址（地区选填）', () {
      expect(detail.contains("'收货人'"), isTrue);
      expect(detail.contains("'手机号'"), isTrue);
      expect(detail.contains("'详细地址'"), isTrue);
      expect(detail.contains("'所在地区'"), isTrue);
      expect(detail.contains('省 / 市 / 区（选填）'), isTrue);
    });

    test('保存地址走 SettingsService.saveAddress（与设置页同一张表）', () {
      expect(detail.contains('SettingsService.saveAddress('), isTrue);
      expect(detail.contains('isDefault: _list.isEmpty'), isTrue);
    });

    test('弹层只负责选地址，不负责扣积分', () {
      expect(detail.contains('保存并使用这个地址'), isTrue);
      expect(detail.contains("'使用这个地址'"), isTrue);
      // 老文案「确认兑换 · 消耗 N 积分」不能再出现在弹层按钮上
      expect(detail.contains('确认兑换 · 消耗'), isFalse);
      expect(detail.contains('点下一步才确认兑换、才扣积分'), isTrue);
      expect(detail.contains('同步到「设置 → 收货地址」'), isTrue);
    });

    test('兑换请求把地址带给后端', () {
      expect(detail.contains('recvName: addr?.name'), isTrue);
      expect(detail.contains('recvDetail: addr?.detail'), isTrue);
    });
  });

  // v2.1.77：用户指出顺序错了 —— 必须先确认兑换，再去查地址
  group('兑换流程顺序（先确认 → 再地址 → 再确认）', () {
    final src = read('lib/screens/product_detail_screen.dart');

    test('「确认积分兑换」弹窗在地址弹层之前', () {
      final iConfirm = src.indexOf('确认积分兑换');
      final iSheet = src.indexOf('_CheckoutSheet(');
      expect(iConfirm, greaterThan(0));
      expect(iSheet, greaterThan(0));
      expect(iConfirm, lessThan(iSheet));
    });

    test('先确认弹窗的按钮是「再想想 / 继续选择地址」，不是直接扣分', () {
      expect(src.contains("child: const Text('再想想')"), isTrue);
      expect(src.contains("child: const Text('继续选择地址')"), isTrue);
    });

    test('确认地址后还有一次最终确认，带地址摘要', () {
      expect(src.contains("title: const Text('确认兑换')"), isTrue);
      expect(src.contains("_confirmRow('收货人'"), isTrue);
      expect(src.contains("_confirmRow('寄送到'"), isTrue);
      expect(src.contains("child: const Text('修改地址')"), isTrue);
    });

    test('最终确认点「修改地址」会回到地址弹层重新选', () {
      // while(true) 循环包住「弹层 → 最终确认」
      expect(src.contains('while (true) {'), isTrue);
      expect(src.contains('if (done) {'), isTrue);
      expect(src.contains('// 点了「修改地址」→ 回到地址弹层重新选'), isTrue);
    });

    test('最终确认不可点外部关闭，避免误触直接扣分', () {
      expect(src.contains('barrierDismissible: false'), isTrue);
    });

    test('有地址走选择列表 / 没地址直接进表单', () {
      expect(src.contains('_formMode = list.isEmpty'), isTrue);
      expect(src.contains("'选择收货地址'"), isTrue);
      expect(src.contains("'添加收货地址'"), isTrue);
    });
  });

  group('商品详情图无缝拼接', () {
    final p = read('lib/screens/product_detail_screen.dart');

    test('连续详情图之间不留间距、不留圆角', () {
      // 上一张也是图 → 上边圆角 0；下一张也是图 → 下边不留白、圆角 0
      expect(p.contains('final prevImg = isImgAt(i - 1);'), isTrue);
      expect(p.contains('final nextImg = isImgAt(i + 1);'), isTrue);
      expect(p.contains('padding: EdgeInsets.only(bottom: nextImg ? 0 : 10)'),
          isTrue);
      expect(p.contains('topLeft: Radius.circular(prevImg ? 0 : r)'), isTrue);
      expect(p.contains('bottomLeft: Radius.circular(nextImg ? 0 : r)'), isTrue);
    });

    test('用 fitWidth 而不是 cover，避免接缝处半像素白线', () {
      expect(p.contains('BoxFit.fitWidth'), isTrue);
    });
  });

  group('我的订单源码护栏', () {
    final orders = read('lib/screens/my_orders_screen.dart');

    test('卡片显示快递公司 + 单号 + 当前状态', () {
      expect(orders.contains('order.expressText'), isTrue);
      expect(orders.contains('order.expressStatus'), isTrue);
      expect(orders.contains('Icons.local_shipping_outlined'), isTrue);
    });

    test('详情里有物流动态时间线（单独拉详情接口）', () {
      expect(orders.contains('class _ExpressSection'), isTrue);
      expect(orders.contains('物流动态'), isTrue);
      expect(orders.contains('ShopService.fetchOrderDetail'), isTrue);
      expect(orders.contains('IntrinsicHeight'), isTrue); // 时间线的连接竖线
    });

    test('详情内容可滚动，轨迹多也不溢出', () {
      expect(orders.contains('SingleChildScrollView'), isTrue);
      expect(orders.contains('maxHeight: MediaQuery.of(context).size.height * 0.86'),
          isTrue);
    });
  });
}
