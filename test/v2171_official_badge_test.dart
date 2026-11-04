import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fishing_app/app_theme.dart';
import 'package:fishing_app/models/post.dart';
import 'package:fishing_app/models/user_profile.dart';
import 'package:fishing_app/widgets/official_badge.dart';
import 'package:fishing_app/widgets/user_avatar.dart';

/// v2.1.71 官方账号（后台设一个官方账号，前端带图标发公告）
///
/// 需求：后台能把账号设为官方 → App 里昵称旁出现「官方」金色徽标，
/// 没上传头像时头像位置显示内置官方图标。三条底线：
///   ① 老后端不下发 user_official 时，一律按普通用户处理（不能白屏/报错）；
///   ② 官方标记只影响展示，不参与会员框、等级、关注等既有逻辑；
///   ③ 头像 / 昵称 / 评论 / 个人主页四个位置都要认这个标记。
void main() {
  group('模型解析（老后端兼容）', () {
    Map<String, dynamic> postJson(Map<String, dynamic> extra) => {
          'id': 'p1',
          'user_id': 'u1',
          'title': '服务器恢复公告',
          'created_at': '2026-11-04T08:00:00.000Z',
          ...extra,
        };

    test('user_official=1 → authorOfficial=true', () {
      final p = Post.fromJson(postJson({'user_official': 1}));
      expect(p.authorOfficial, isTrue);
    });

    test('user_official=0 → false', () {
      final p = Post.fromJson(postJson({'user_official': 0}));
      expect(p.authorOfficial, isFalse);
    });

    test('老后端完全没有这个字段 → false（不抛异常）', () {
      final p = Post.fromJson(postJson({}));
      expect(p.authorOfficial, isFalse);
    });

    test('字符串 "1" / true 也认（不同后端序列化风格）', () {
      expect(Post.fromJson(postJson({'user_official': '1'})).authorOfficial,
          isTrue);
      expect(Post.fromJson(postJson({'user_official': true})).authorOfficial,
          isTrue);
    });

    test('UserProfile 读 official', () {
      final u = UserProfile.fromJson({'id': 'u1', 'nickname': '渔报官方'});
      expect(u.official, isFalse, reason: '没这个字段时必须是普通用户');
      final o = UserProfile.fromJson(
          {'id': 'u1', 'nickname': '渔报官方', 'official': 1});
      expect(o.official, isTrue);
    });

    test('copyWith 能保留官方标记', () {
      final p = Post.fromJson(postJson({'user_official': 1}));
      expect(p.copyWith(likeCount: 3).authorOfficial, isTrue);
    });
  });

  group('徽标渲染', () {
    testWidgets('胶囊有「官方」二字 + 对勾图标', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: Center(child: OfficialBadge(height: 16))),
      ));
      expect(find.text('官方'), findsOneWidget);
      expect(find.byIcon(Icons.verified), findsOneWidget);

      final box = tester.getSize(find.byType(Container).first);
      expect(box.height, 16);
      expect(box.width, greaterThan(30), reason: '要能装下两个字 + 图标');
    });

    testWidgets('iconOnly 只画对勾，不给「官方」二字留位置', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: Center(child: OfficialBadge(height: 11, iconOnly: true)),
        ),
      ));
      expect(find.text('官方'), findsNothing);
      expect(find.byIcon(Icons.verified), findsOneWidget);
      expect(tester.getSize(find.byType(Icon)).width, 11);
    });

    testWidgets('徽标配色走色板（金底 + 近黑字），不是写死的其他颜色',
        (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: Center(child: OfficialBadge())),
      ));
      final decor = tester
          .widget<Container>(find.byType(Container).first)
          .decoration as BoxDecoration;
      expect(decor.color, AppTheme.star);
      final text = tester.widget<Text>(find.text('官方'));
      expect(text.style!.color, AppTheme.primary);
    });

    testWidgets('默认头像是无图时的官方图标', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: Center(child: OfficialAvatarGlyph(size: 40))),
      ));
      final box = tester.getSize(find.byType(Container).first);
      expect(box.width, 40);
      expect(find.byIcon(Icons.verified), findsOneWidget);
    });

    testWidgets('有自定义头像时的角标是金色圆 + 白边', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: Center(child: OfficialAvatarMark(size: 14))),
      ));
      final decor = tester
          .widget<Container>(find.byType(Container).first)
          .decoration as BoxDecoration;
      expect(decor.color, AppTheme.star);
      expect(decor.shape, BoxShape.circle);
    });
  });

  group('头像接线', () {
    testWidgets('official + 没头像 → 内置官方图标（不再画人像占位）',
        (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: Center(
            child: UserAvatar(url: null, userId: 'u1', radius: 20, official: true),
          ),
        ),
      ));
      expect(find.byType(OfficialAvatarGlyph), findsOneWidget);
      expect(find.byIcon(Icons.person), findsNothing);
      expect(find.byType(OfficialAvatarMark), findsNothing,
          reason: '头像本身就是官方图标，不要再挂一个小角标，重复');
    });

    testWidgets('普通用户不受影响（仍是人像占位）', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: Center(
            child: UserAvatar(url: null, userId: 'u2', radius: 20),
          ),
        ),
      ));
      expect(find.byType(OfficialAvatarGlyph), findsNothing);
      expect(find.byIcon(Icons.person), findsOneWidget);
    });
  });

  group('源码护栏（四个展示位都认官方标记）', () {
    String read(String p) => File(p).readAsStringSync();

    test('信息流卡片：头像 + 昵称旁徽标', () {
      final s = read('lib/widgets/post_card.dart');
      expect(s.contains('official: _post.authorOfficial'), isTrue,
          reason: '卡片头像要传 official，否则官方账号还是普通人像');
      expect(s.contains('if (_post.authorOfficial)'), isTrue,
          reason: '昵称旁要出徽标');
      expect(s.contains('OfficialBadge'), isTrue);
    });

    test('瀑布流卡片：窄卡片用 iconOnly，别把昵称挤没', () {
      final s = read('lib/widgets/waterfall_post_card.dart');
      expect(s.contains('official: post.authorOfficial'), isTrue);
      expect(s.contains('iconOnly: true'), isTrue,
          reason: '双列卡片宽度不够放「官方」两个字');
    });

    test('详情页：顶栏 + 作者卡 + 评论都认', () {
      final s = read('lib/screens/post_detail_screen.dart');
      expect(s.contains('_post.authorOfficial'), isTrue);
      expect(s.contains("c['user_official']"), isTrue,
          reason: '评论里的官方回复也要带标');
      expect(s.split('OfficialBadge').length - 1, greaterThanOrEqualTo(3),
          reason: '顶栏 / 作者卡 / 评论三处');
    });

    test('个人主页 + 我的页', () {
      expect(read('lib/screens/user_profile_screen.dart')
          .contains('official: p?.official ?? false'), isTrue);
      expect(read('lib/screens/profile_screen.dart')
          .contains('_me?.official ?? false'), isTrue);
    });

    test('UserAvatar 的官方分支：无图走图标、有图走角标', () {
      final s = read('lib/widgets/user_avatar.dart');
      expect(s.contains('final showGlyph = official && !hasImage;'), isTrue);
      expect(s.contains('final showMark = official && hasImage;'), isTrue);
    });
  });

  group('色板', () {
    test('官方徽标只用琥珀系 token，没有新色相', () {
      final s = File('lib/widgets/official_badge.dart').readAsStringSync();
      expect(s.contains('Color(0x'), isFalse,
          reason: '全部走 AppTheme.star / starLight / starDark，别写死颜色');
      expect(s.contains('AppTheme.star'), isTrue);
    });
  });
}
