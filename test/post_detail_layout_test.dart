// 渔获详情页版式护栏：390dp / 320dp 两种宽度下都不许出现布局溢出。
//
// 这一版（v2.1.34）把详情页整页重做了，卡片多、Row 多，最容易在窄屏上
// 出现 RenderFlex overflow。测试环境的中文字形是「全角方块」，宽度不输
// 真实中文，所以这里能挡住绝大部分横向溢出。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fishing_app/app_theme.dart';
import 'package:fishing_app/models/post.dart';
import 'package:fishing_app/screens/post_detail_screen.dart';

Post _sample({bool withFish = true, bool withSpot = true}) => Post(
      id: 'p1',
      userId: 'u1',
      username: '钓鱼佬',
      title: '今日鱼获分享',
      body: '风雨越大鱼口越炸，鲈鱼连杆，还偶遇一条老黑，小鲈鱼已放流，长大了再来咬钩 😊',
      category: 'post',
      createdAt: DateTime.now().subtract(const Duration(hours: 4)),
      likeCount: 2222,
      commentCount: 999,
      viewCount: 12888,
      city: withSpot ? '长沙市' : '',
      locationName: withSpot ? '西二环绿道梅溪湖公园' : null,
      lat: withSpot ? 28.19 : null,
      lng: withSpot ? 112.93 : null,
      userLevel: 12,
      fish: withFish
          ? const [
              {'name': '大口黑鲈', 'count': 3},
              {'name': '翘嘴', 'count': 1},
            ]
          : const [],
    );

Future<void> _pumpAt(WidgetTester tester, double w, double h, Post p) async {
  tester.view.physicalSize = Size(w * 3, h * 3);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.light,
    home: PostDetailScreen(post: p),
  ));
  await tester.pump(const Duration(milliseconds: 200));
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('390dp：完整渔获无布局溢出', (tester) async {
    await _pumpAt(tester, 390, 844, _sample());
    expect(tester.takeException(), isNull);
    // 关键区块都渲染出来了
    expect(find.text('大口黑鲈'), findsWidgets);
    expect(find.text('CATCH INDEX'), findsOneWidget);
    expect(find.text('导航'), findsOneWidget);
  });

  testWidgets('320dp 小屏：完整渔获无布局溢出', (tester) async {
    await _pumpAt(tester, 320, 700, _sample());
    expect(tester.takeException(), isNull);
  });

  testWidgets('没有鱼种 / 没有钓点时也不崩', (tester) async {
    await _pumpAt(
        tester, 390, 844, _sample(withFish: false, withSpot: false));
    expect(tester.takeException(), isNull);
    expect(find.text('CATCH INDEX'), findsOneWidget);
  });
}
