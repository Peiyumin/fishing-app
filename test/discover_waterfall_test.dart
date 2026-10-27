import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fishing_app/models/post.dart';
import 'package:fishing_app/widgets/waterfall_post_card.dart';

/// 发现页（钓友圈）双列瀑布流
///
/// 用户这一轮的要求：发现页布局改成参考图那样 —— 双列卡片、图片上角标、
/// 图上叠鱼种名与绿色「指数」、下面正文 + 作者行。
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Post build({List<Map<String, dynamic>> fish = const []}) => Post(
        id: 'p1',
        userId: 'u1',
        username: '老王',
        title: '溪流钓',
        body: '溪流钓。今天一个下午，颗粒打窝，3.6米的溪流竿。',
        imageUrls: const ['https://example.com/a.jpg'],
        createdAt: DateTime.now(),
        city: '许昌市',
        likeCount: 27,
        commentCount: 5,
        viewCount: 320,
        fish: fish,
      );

  Future<void> pumpCard(WidgetTester tester, Post post, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: (size.width - 24 - 10) / 2,
          height: 340,
          child: WaterfallPostCard(post: post, onTap: () {}),
        ),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 200));
  }

  testWidgets('卡片显示鱼种名与指数，窄屏不溢出', (tester) async {
    await pumpCard(
      tester,
      build(fish: const [
        {'name': '锦鲤', 'count': 1},
        {'name': '鲤鱼', 'count': 1},
        {'name': '草鱼', 'count': 2},
      ]),
      const Size(320, 640),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('锦鲤 鲤鱼 +1 种'), findsOneWidget);
    expect(find.textContaining('指数'), findsOneWidget);
    expect(find.text('老王'), findsOneWidget);
  });

  testWidgets('没有图片时用渐变占位，依然显示鱼种', (tester) async {
    final post = Post(
      id: 'p2',
      userId: 'u2',
      username: '小李',
      title: '随便说说',
      body: '今天风太大',
      createdAt: DateTime.now(),
      fish: const [
        {'name': '鲫鱼', 'count': 2},
      ],
    );
    await pumpCard(tester, post, const Size(390, 844));
    expect(tester.takeException(), isNull);
    expect(find.text('鲫鱼'), findsWidgets);
  });

  testWidgets('长昵称 + 大字数不溢出（390dp）', (tester) async {
    final post = Post(
      id: 'p3',
      userId: 'u3',
      username: '名字特别特别长的钓友啊啊啊啊',
      title: '标题',
      body: '正文' * 40,
      imageUrls: const ['https://example.com/b.jpg'],
      createdAt: DateTime.now(),
      city: '黔南布依族苗族自治州',
      likeCount: 1234,
      userLevel: 27,
      fish: const [
        {'name': '鳙鱼', 'count': 3},
      ],
    );
    await pumpCard(tester, post, const Size(390, 844));
    expect(tester.takeException(), isNull);
  });
}
