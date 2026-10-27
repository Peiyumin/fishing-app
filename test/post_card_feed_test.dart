import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fishing_app/models/badge.dart';
import 'package:fishing_app/models/post.dart';
import 'package:fishing_app/services/badge_hub.dart';
import 'package:fishing_app/services/session_provider.dart';
import 'package:fishing_app/widgets/post_card.dart';
import 'package:fishing_app/widgets/user_avatar.dart';

/// 信息流卡片（v2.1.29 还原成原布局之后）
///
/// 这一轮用户的要求：
///   1. 内容排版回到原来的样子（头像 + 昵称 + 关注 + 时间，标题带类别标签，
///      正文 2 行，底部定位 / 评论 / 点赞）；
///   2. 头像后面显示已获得的徽章，没拿到就不显示；
///   3. 图片：1 张就是一张、2 张中间分开一边一张、3 张左大右两小。
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    BadgeHub.resetForTest();
  });

  Finder clips() => find.byWidgetPredicate(
        (w) =>
            w is ClipRRect &&
            w.borderRadius ==
                BorderRadius.circular(ClipRoundedRectangle.radius),
      );

  Future<void> pumpCard(
    WidgetTester tester,
    List<String> images, {
    Size size = const Size(390, 844),
    String author = 'u1',
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final post = Post(
      id: 'p1',
      userId: author,
      username: '老王',
      title: '今天钓到一条大鲫鱼',
      body: '早上六点就来了，口不错。',
      imageUrls: images,
      locationName: '小刘垂钓园',
      createdAt: DateTime.now(),
    );
    await tester.pumpWidget(ChangeNotifierProvider<SessionProvider>(
      create: (_) => SessionProvider(),
      child: MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(child: PostCard(post: post)),
        ),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
  }

  group('原布局还在', () {
    testWidgets('作者行：昵称 + 相对时间都在', (tester) async {
      await pumpCard(tester, const ['https://example.com/a.jpg']);
      expect(find.text('老王'), findsOneWidget);
      expect(find.text('刚刚'), findsOneWidget);
      expect(find.text('今天钓到一条大鲫鱼'), findsOneWidget);
    });

    testWidgets('底部有评论数 / 点赞数 / 钓点位置', (tester) async {
      await pumpCard(tester, const []);
      expect(find.text('小刘垂钓园'), findsOneWidget);
      expect(find.byIcon(Icons.chat_bubble_outline), findsOneWidget);
      expect(find.byIcon(Icons.favorite_border), findsOneWidget);
    });
  });

  group('头像后面的徽章', () {
    testWidgets('拿到徽章就显示在头像后面', (tester) async {
      BadgeHub.debugPut('u1', const [
        BadgeItem(id: 'b1', name: '初出茅庐', icon: '🎣'),
        BadgeItem(id: 'b2', name: '百发百中', icon: '🏆'),
      ]);
      await pumpCard(tester, const []);
      expect(find.text('🎣'), findsOneWidget, reason: '第一枚徽章要出现在头像后面');
      expect(find.text('🏆'), findsOneWidget);
    });

    testWidgets('没有徽章时不占位（版式与原来一致）', (tester) async {
      await pumpCard(tester, const []);
      expect(find.byTooltip('初出茅庐'), findsNothing);
      // 昵称要紧跟头像，不该被撑开
      final nickname = tester.getTopLeft(find.text('老王'));
      expect(nickname.dx, lessThan(90), reason: '没徽章时昵称应贴着头像（约 56~70）');
    });

    testWidgets('最多只显示 3 枚，第 4 枚不挤进作者行', (tester) async {
      BadgeHub.debugPut('u1', const [
        BadgeItem(id: '1', name: 'A', icon: '1️⃣'),
        BadgeItem(id: '2', name: 'B', icon: '2️⃣'),
        BadgeItem(id: '3', name: 'C', icon: '3️⃣'),
        BadgeItem(id: '4', name: 'D', icon: '4️⃣'),
      ]);
      await pumpCard(tester, const []);
      expect(find.text('3️⃣'), findsOneWidget);
      expect(find.text('4️⃣'), findsNothing);
    });
  });

  group('图片排版', () {
    testWidgets('1 张：就是一张小图（高 112，最宽不超过卡片 62%）', (tester) async {
      await pumpCard(tester, const ['https://example.com/1.jpg']);
      final c = clips();
      expect(c, findsOneWidget);
      final size = tester.getSize(c);
      expect(size.height, closeTo(112, 0.5));
      final contentWidth = tester.getSize(find.byType(PostCard)).width - 32;
      expect(size.width, lessThanOrEqualTo(contentWidth * 0.62 + 0.5));
    });

    testWidgets('2 张：中间分开，左右各一张，等宽等高', (tester) async {
      await pumpCard(
          tester, const ['https://example.com/1.jpg', 'https://example.com/2.jpg']);
      final c = clips();
      expect(c, findsNWidgets(2));
      final a = tester.getSize(c.at(0));
      final b = tester.getSize(c.at(1));
      expect(a.width, closeTo(b.width, 0.5), reason: '两张等宽');
      expect(a.height, closeTo(b.height, 0.5), reason: '两张等高');
      // 同一行：顶边对齐，且中间留了间隙
      final ra = tester.getRect(c.at(0));
      final rb = tester.getRect(c.at(1));
      expect(ra.top, closeTo(rb.top, 0.5));
      expect(rb.left - ra.right, closeTo(6, 0.5), reason: '中间间隙 6');
    });

    testWidgets('3 张：左边一张大图占满高度，右边两张小的上下叠', (tester) async {
      await pumpCard(tester, const [
        'https://example.com/1.jpg',
        'https://example.com/2.jpg',
        'https://example.com/3.jpg',
      ]);
      final c = clips();
      expect(c, findsNWidgets(3));
      final left = tester.getRect(c.at(0));
      final rt = tester.getRect(c.at(1));
      final rb = tester.getRect(c.at(2));

      expect(left.width, greaterThan(rt.width * 1.4),
          reason: '左图要明显更宽（左大右小）');
      expect(left.height, greaterThan(rt.height),
          reason: '左图要占满整高，比右侧单张高');
      expect(rt.height, closeTo(rb.height, 0.5), reason: '右侧两张等高');
      expect(rt.height + rb.height + 6, closeTo(left.height, 1.0),
          reason: '右侧两张叠起来 + 间隙 == 左图高度');
      expect(rt.left, closeTo(rb.left, 0.5), reason: '右侧两张左对齐');
    });

    testWidgets('4 张以上：三张方图，第三张角上标 +N', (tester) async {
      await pumpCard(tester, const [
        'https://example.com/1.jpg',
        'https://example.com/2.jpg',
        'https://example.com/3.jpg',
        'https://example.com/4.jpg',
        'https://example.com/5.jpg',
      ]);
      expect(clips(), findsNWidgets(3));
      expect(find.text('+2'), findsOneWidget);
    });
  });

  test('圆角仍然是一点点（8），不是药丸', () {
    expect(ClipRoundedRectangle.radius, 8.0);
    expect(ClipRoundedRectangle.radius, lessThan(10.0));
  });

  testWidgets('徽章挂在昵称后面，不在头像后面', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final post = Post(
      id: 'p9',
      userId: 'u9',
      username: '老王',
      title: '今天钓到一条大鲫鱼',
      createdAt: DateTime.now(),
      badges: const [
        BadgeItem(id: 'b1', name: '钓神', icon: '🏆', color: '#FFB300'),
      ],
    );
    await tester.pumpWidget(ChangeNotifierProvider<SessionProvider>(
      create: (_) => SessionProvider(),
      child: MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(child: PostCard(post: post)),
        ),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 300));

    final nameRect = tester.getRect(find.text('老王'));
    final badge = find.byTooltip('钓神');
    expect(badge, findsOneWidget, reason: '有徽章时应显示出来');

    final badgeRect = tester.getRect(badge);
    expect(badgeRect.left, greaterThanOrEqualTo(nameRect.right - 1),
        reason: '徽章必须排在昵称右侧，而不是头像和昵称之间');

    // 头像在昵称左边：徽章不能贴着头像
    final avatar = find.byType(UserAvatar);
    expect(avatar, findsOneWidget);
    expect(badgeRect.left, greaterThan(tester.getRect(avatar).right + 2),
        reason: '徽章不应该出现在头像后面');
  });
}
