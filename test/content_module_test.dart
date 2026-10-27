// 活动 / 文章模块的模型与页面冒烟测试
//
// 这两块都是「用户投稿 → 后台审核 → 前端可见」的流程，
// 时间格式化错了会导致列表和详情显示不一致，所以在模型层就锁住。
import 'package:fishing_app/models/activity.dart';
import 'package:fishing_app/models/article.dart';
import 'package:fishing_app/screens/activity_list_screen.dart';
import 'package:fishing_app/screens/lure_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Activity _act({
  String startAt = '2026-10-25 14:00:00',
  String endAt = '',
  int maxJoin = 0,
  int joinCount = 0,
  int status = 1,
  bool joined = false,
  String content = '',
}) {
  return Activity.fromJson({
    'id': 'act_1',
    'title': '周末水库野钓局',
    'cover': '',
    'summary': '',
    'content': content,
    'start_at': startAt,
    'end_at': endAt,
    'location': '南岸停车场',
    'fee': 'AA',
    'contact': '',
    'author_id': 'u1',
    'author_name': '老王',
    'status_label': '已通过',
    'reject_reason': '',
    'created_at': '2026-10-01 09:00:00',
    'max_join': maxJoin,
    'join_count': joinCount,
    'status': status,
    'full': false,
    'joined': joined,
  });
}

void main() {
  group('Activity 时间文案', () {
    test('开始时间带星期和时刻', () {
      final a = _act();
      // 2026-10-25 是周日
      expect(a.timeText, '10月25日 周日 14:00');
      expect(a.monthText, '10月');
      expect(a.dayText, '25');
    });

    test('同一天的活动合并成区间', () {
      final a = _act(endAt: '2026-10-25 18:30:00');
      expect(a.rangeText, '10月25日 周日 14:00 — 18:30');
    });

    test('跨天只标「起」', () {
      final a = _act(endAt: '2026-10-26 12:00:00');
      expect(a.rangeText, '10月25日 周日 14:00 起');
    });

    test('没有结束时间就用开始时间', () {
      expect(_act().rangeText, _act().timeText);
    });
  });

  group('Activity 报名文案与状态', () {
    test('不限名额', () {
      expect(_act().joinText, '不限名额');
    });

    test('有名额上限', () {
      expect(_act(maxJoin: 20, joinCount: 3).joinText, '3 / 20 人');
    });

    test('没人报名时直接说不限名额', () {
      expect(_act(joinCount: 0).joinText, '不限名额');
    });

    test('审核状态判定', () {
      expect(_act(status: 1).isApproved, isTrue);
      expect(_act(status: 0).isPending, isTrue);
      expect(_act(status: 2).isRejected, isTrue);
    });
  });

  test('活动正文按空行分段', () {
    final a = _act(content: '第一段\n\n第二段\n\n\n第三段');
    expect(a.paragraphs, ['第一段', '第二段', '第三段']);
  });

  test('文章正文按空行分段', () {
    final art = Article.fromJson({
      'id': 'a1',
      'title': '路亚抛投入门',
      'category': 'lure_skill',
      'category_label': '路亚技巧',
      'content': '站姿\n\n手腕发力\n\n收线节奏',
      'status': 1,
    });
    expect(art.paragraphs, ['站姿', '手腕发力', '收线节奏']);
    expect(art.categoryLabel, '路亚技巧');
  });

  testWidgets('活动页能渲染出来且不抛异常', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: ActivityListScreen()));
    await tester.pump();
    expect(find.text('活动'), findsOneWidget);

    // 接口在测试环境拿不到数据，1 秒内应该落到空态（不能一直转圈）
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    expect(tester.takeException(), isNull);
    expect(find.text('近期还没有活动'), findsOneWidget);
  });

  testWidgets('路亚页四个页签齐备', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: LureScreen()));
    await tester.pump();

    for (final label in ['技巧', '装备', '评测', '路亚钓点']) {
      expect(find.text(label), findsOneWidget);
    }
    await tester.pump(const Duration(seconds: 1));
    expect(tester.takeException(), isNull);
  });
}
