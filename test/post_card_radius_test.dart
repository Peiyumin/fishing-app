import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fishing_app/models/post.dart';
import 'package:fishing_app/services/session_provider.dart';
import 'package:fishing_app/widgets/post_card.dart';

/// 动态卡片图片圆角回归（v2.1.22）
///
/// 用户反馈：首页钓友动态里的图片「一边有圆角、一边没有」。
///
/// 根因不是圆角值写错，而是**裁剪框套错了层**：
/// 旧代码是 `ClipRRect(child: Align(child: SizedBox(图片)))`，
/// Align 会撑满整行宽度（≈ 屏幕宽 - 48），而图片只占左边一小段，
/// 于是裁剪只作用在整行的边缘 —— 图片左边两个角贴边被裁圆，
/// 右边两个角离裁剪边缘还远，保持直角。
///
/// 现在的结构是 `Align(child: SizedBox(child: ClipRRect(child: 图片)))`，
/// 裁剪框宽度必须等于图片宽度。
///
/// 判据：取圆角半径 6 的那个 ClipRRect（单图专用），
/// 它的宽度如果接近整行宽，就说明裁剪框又套回外层了。
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  /// 找到单图那层裁剪框（半径 = ClipRoundedRectangle.radius）
  Finder singleImageClip() => find.byWidgetPredicate(
        (w) =>
            w is ClipRRect &&
            w.borderRadius ==
                BorderRadius.circular(ClipRoundedRectangle.radius),
      );

  Future<void> pumpCard(WidgetTester tester, List<String> images) async {
    final post = Post(
      id: 'p_radius',
      userId: 'u1',
      username: '老王',
      title: '今天钓到一条大鲫鱼',
      body: '早上六点就来了，口不错。',
      imageUrls: images,
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
    // 图片会走网络（测试环境被 mock 成立即失败）→ 落到 errorWidget，
    // 布局尺寸不受影响，照样能量裁剪框
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets('单图：圆角裁剪框宽度必须等于图片宽度，不能是整行宽', (tester) async {
    await pumpCard(tester, const ['https://example.com/a.jpg']);

    final clip = singleImageClip();
    expect(clip, findsOneWidget, reason: '单图应该只有一层半径 6 的裁剪框');

    final clipSize = tester.getSize(clip);
    final cardWidth = tester.getSize(find.byType(PostCard)).width;
    // 卡片内边距 48（左右各 24），可用宽度
    final rowWidth = cardWidth - 48;

    expect(clipSize.height, closeTo(112, 0.5),
        reason: '单图缩略图高度是 112，裁剪框高度必须一致');

    // ★ 核心断言：裁剪框不能是整行宽
    expect(clipSize.width, lessThan(rowWidth * 0.8),
        reason: '裁剪框宽度 ${clipSize.width} 接近整行宽 $rowWidth —— '
            '说明 ClipRRect 又套在 Align 外面了，图片会出现"左圆右直"');

    // 而且宽度要在设计范围内（96 起，最宽不超过 62% 行宽）
    expect(clipSize.width, greaterThanOrEqualTo(96.0));
    expect(clipSize.width, lessThanOrEqualTo(rowWidth * 0.62 + 0.5));
  });

  testWidgets('九宫格：每张缩略图的裁剪框都是 88 见方', (tester) async {
    await pumpCard(tester, const [
      'https://example.com/1.jpg',
      'https://example.com/2.jpg',
      'https://example.com/3.jpg',
    ]);

    final clips = singleImageClip();
    expect(clips, findsNWidgets(3), reason: '三张图各一层裁剪框');
    for (var i = 0; i < 3; i++) {
      final s = tester.getSize(clips.at(i));
      expect(s.width, closeTo(88, 0.5));
      expect(s.height, closeTo(88, 0.5));
    }
  });

  testWidgets('圆角值必须是「一点点」（6），不能又回到大圆角', (tester) async {
    expect(ClipRoundedRectangle.radius, 6.0,
        reason: '用户明确说了圆角不要太大，改成 10 以上会显得像药丸');
  });
}
