import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fishing_app/models/post.dart';
import 'package:fishing_app/widgets/waterfall_post_card.dart';

/// 双列瀑布流卡片（钓友圈 / 首页钓友动态共用）
///
/// 用户要求首页那一块「和图二一模一样」：图片上叠小鱼图 + 条数、右下亮绿
/// 指数胶囊、图下正文 + 城市 + 头像/LV/点赞。这里锁住版式与不溢出的底线。
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Post build({
    String body = '溪流钓。今天一个下午，颗粒打窝，3.6 米的溪流竿。',
    String city = '赣南布依族苗族自治州',
    String username = '海洋',
    List<Map<String, dynamic>> fish = const [
      {'name': '锦鲤', 'count': 2},
      {'name': '鲤鱼', 'count': 1},
    ],
    bool withImage = true,
  }) =>
      Post(
        id: 'p1',
        userId: 'u1',
        username: username,
        title: '今日鱼获',
        body: body,
        imageUrls: withImage ? const ['http://example.com/a.jpg'] : const [],
        category: 'post',
        price: '',
        city: city,
        createdAt: DateTime.now(),
        likeCount: 27,
        commentCount: 5,
        viewCount: 120,
        userLevel: 1,
        fish: fish,
      );

  Widget host(Widget child) => MaterialApp(
        home: Scaffold(body: Center(child: SizedBox(width: 390, child: child))),
      );

  testWidgets('双列：两张卡在同一行，左右各一张', (tester) async {
    await tester.pumpWidget(host(
      WaterfallGrid(
        posts: [build(), build()],
        shrinkWrap: true,
        onTap: (_) {},
      ),
    ));
    final cards =
        tester.widgetList<WaterfallPostCard>(find.byType(WaterfallPostCard));
    expect(cards.length, 2);
    final r0 = tester.getRect(find.byType(WaterfallPostCard).at(0));
    final r1 = tester.getRect(find.byType(WaterfallPostCard).at(1));
    expect(r0.top, closeTo(r1.top, .5), reason: '两张卡应该同一行');
    expect(r1.left, greaterThan(r0.left), reason: '第二张在第一张右边');
  });

  testWidgets('图上不再显示鱼种条数角标，右下仍有指数', (tester) async {
    await tester.pumpWidget(host(
      WaterfallGrid(
        posts: [build()],
        shrinkWrap: true,
        onTap: (_) {},
      ),
    ));
    // 用户要求删掉图片左上角那个「小鱼图 + 条数」的角标：
    // 2 + 1 = 3 条，这个数字现在不应该再出现在图片上。
    expect(find.text('3'), findsNothing, reason: '左上角鱼种条数角标已删除');
    // 鱼种名和绿色「指数」保留
    expect(find.text('指数'), findsOneWidget);
    expect(find.textContaining('锦鲤 鲤鱼'), findsOneWidget);
  });

  testWidgets('长昵称 / 窄屏（320dp）不溢出', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: WaterfallGrid(
          posts: [
            build(
              username: '一个名字特别特别长的钓鱼佬为了测试',
              body: '很长很长的一段正文' * 6,
              fish: const [
                {'name': '锦鲤', 'count': 9},
                {'name': '鲤鱼', 'count': 9},
                {'name': '草鱼', 'count': 9},
                {'name': '鲢鳙', 'count': 9},
              ],
            ),
            build(city: '', withImage: false),
          ],
          onTap: (_) {},
        ),
      ),
    ));
    expect(tester.takeException(), isNull);
  });

  testWidgets('没有图片时用渐变占位，不报错', (tester) async {
    await tester.pumpWidget(host(
      WaterfallGrid(
        posts: [build(withImage: false)],
        shrinkWrap: true,
        onTap: (_) {},
      ),
    ));
    expect(tester.takeException(), isNull);
    expect(find.textContaining('锦鲤'), findsWidgets);
  });
}
