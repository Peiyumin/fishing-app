// v2.1.59「我的」页重排的版面回归
//
// 钉的都是**几何关系**，不是像素值：
//   ① 昵称可用宽度要够（旧版只有 ~120pt，7 个字就被省略号吃掉）
//   ② 昵称要和头像顶部齐平（改版第一版把文字排到了头像下方，空一大块）
//   ③ 头像要压住封面下沿（有背景图时）
//   ④ 五列数据的数字用等宽数字，列间有竖线
//   ⑤ 徽章图标有 28×28 的容器承载（emoji 大小不一时靠容器对齐）
//   ⑥ 没有背景图时不出「换背景」按钮
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fishing_app/app_theme.dart';
import 'package:fishing_app/models/badge.dart';
import 'package:fishing_app/models/member.dart';
import 'package:fishing_app/models/user_profile.dart';
import 'package:fishing_app/screens/profile_screen.dart';
import 'package:fishing_app/services/session_provider.dart';

const _me = UserProfile(
  id: 'u1',
  userNo: 10,
  nickname: '老王爱钓鱼的人',
  bio: '',
  level: 3,
  regPlace: '河南省·禹州市',
  postCount: 1,
  likeCount: 1,
  followingCount: 2,
  followerCount: 1,
  points: 1134,
  pointsName: '鱼币',
  isMe: true,
  vip: MemberStyle(
    level: 1,
    name: '青铜会员',
    color: Color(0xFF9C7B4E),
    color2: Color(0xFFD8BC8A),
  ),
  badges: [
    BadgeItem(id: 'b1', name: '初钓'),
    BadgeItem(id: 'b2', name: '鲫鱼'),
    BadgeItem(id: 'b3', name: '连竿'),
    BadgeItem(id: 'b4', name: '夜钓'),
  ],
);

Future<SessionProvider> _pump(
  WidgetTester tester, {
  Widget? cover,
}) async {
  SharedPreferences.setMockInitialValues({
    'session_token': 't',
    'session_user_id': 'u1',
    'session_nickname': '老王爱钓鱼的人',
    'session_avatar': '',
    'session_cover': '',
    'session_bio': '',
  });
  tester.view.physicalSize = const Size(390 * 3, 1400 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);

  final sp = SessionProvider();
  await sp.restore();

  await tester.pumpWidget(
    ChangeNotifierProvider.value(
      value: sp,
      child: MaterialApp(
        theme: AppTheme.light,
        home: ProfileScreen(
          debugMe: _me,
          debugRegPlace: '河南省·禹州市',
          debugCover: cover,
        ),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 200));
  return sp;
}

void main() {
  const tag = '我的页 v2.1.59 版面';

  testWidgets('$tag：昵称可用宽度够，不再只剩「老王爱...」', (tester) async {
    await _pump(tester);
    final para = tester.renderObject<RenderParagraph>(
        find.text('老王爱钓鱼的人').first);
    // 名字 7 个汉字 @19pt ≈ 133；旧版被 LV/会员/编辑挤到 ~120 就出省略号
    expect(para.didExceedMaxLines, isFalse);
    expect(para.size.width, greaterThan(120));
  });

  testWidgets('$tag：昵称与头像顶部齐平（不许掉到头像下方）', (tester) async {
    await _pump(tester);
    final nameRect = tester.getRect(find.text('老王爱钓鱼的人').first);
    final avatarRect =
        tester.getRect(find.byType(ClipOval).first); // 头像图片/占位
    // 以头像的外圈（白底圆）为准更稳
    final avatarOuter = tester.getRect(find.byWidgetPredicate(
      (w) =>
          w is Container &&
          w.decoration is BoxDecoration &&
          (w.decoration as BoxDecoration).shape == BoxShape.circle,
    ).first);
    final base = avatarOuter.top <= avatarRect.top
        ? avatarOuter
        : avatarRect;
    // 昵称顶与头像顶相差不超过 12（行高留白），且昵称必须在头像右侧
    expect((nameRect.top - base.top).abs(), lessThan(12));
    expect(nameRect.left, greaterThan(base.right - 4));
  });

  testWidgets('$tag：没有背景图时不出「换背景」', (tester) async {
    await _pump(tester);
    expect(find.text('换背景'), findsNothing);
  });

  testWidgets('$tag：有背景图时头像压住封面下沿', (tester) async {
    final bytes = _coverPng;
    await _pump(tester, cover: Image.memory(bytes, fit: BoxFit.cover));

    expect(find.text('换背景'), findsOneWidget);

    final cover = tester.getRect(find.byType(Image).first);
    expect(cover.height, greaterThan(100));

    final avatarOuter = tester.getRect(find.byWidgetPredicate(
      (w) =>
          w is Container &&
          w.decoration is BoxDecoration &&
          (w.decoration as BoxDecoration).shape == BoxShape.circle,
    ).first);
    // 头像顶要落在封面内部（压边），而不是封面下方
    expect(avatarOuter.top, lessThan(cover.bottom));
    expect(avatarOuter.top, greaterThan(cover.top + 40));
  });

  testWidgets('$tag：五列数据用等宽数字 + 列间竖线', (tester) async {
    await _pump(tester);
    final n1 = tester.widget<Text>(find.text('1').first);
    expect(n1.style?.fontFeatures, contains(const FontFeature.tabularFigures()));

    // 4 条竖线（5 列之间有 4 个分隔）；档案卡里那条白 8% 分隔线不算
    final bars = find.byWidgetPredicate((w) =>
        w.key is ValueKey<String> &&
        (w.key as ValueKey<String>).value.startsWith('stats-sep'));
    expect(bars, findsNWidgets(4));
  });

  testWidgets('$tag：徽章每个都有 28×28 容器', (tester) async {
    await _pump(tester);
    final boxes = find.byWidgetPredicate((w) =>
        w is Container &&
        w.constraints?.maxWidth == 28 &&
        w.constraints?.maxHeight == 28 &&
        w.decoration is BoxDecoration);
    // 4 个徽章 + 1 个编辑方块（也是 28）
    expect(boxes.evaluate().length, greaterThanOrEqualTo(4));
  });

  testWidgets('$tag：定位与 ID 合并成一行', (tester) async {
    await _pump(tester);
    expect(find.text('河南省·禹州市 · ID 10'), findsOneWidget);
  });
}

/// 1×1 的透明 PNG（只用来占位，走 Image.memory 不碰网络）
final _coverPng = Uint8List.fromList(<int>[
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D,
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
  0x0A, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49,
  0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
]);
