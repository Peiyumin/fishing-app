import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fishing_app/app_theme.dart';
import 'package:fishing_app/models/official.dart';
import 'package:fishing_app/models/post.dart';
import 'package:fishing_app/widgets/official_badge.dart';

/// v2.1.72 官方工作台（官方账号在 App 里发公告 / 管帖子 / 封账号）
///
/// 这一版最怕的不是「功能没做出来」，而是「权限漏了」：
///   · 普通账号能看到入口、点进去还能操作 → 灾难；
///   · 官方账号能封另一个官方 / 管理员 / 自己 → 内部互杀；
///   · 老后端没有 /official/* 时页面红屏 → 用户以为 App 坏了。
/// 所以测试一半在验数据解析，一半在验这几条护栏写死在了源码里。
void main() {
  group('模型解析', () {
    test('概览：字段缺失按 0 处理，不抛异常', () {
      final o = OfficialOverview.fromJson(const {});
      expect(o.noticeCount, 0);
      expect(o.postCount, 0);
      expect(o.bannedCount, 0);
      expect(o.nickname, '');
    });

    test('概览：完整字段', () {
      final o = OfficialOverview.fromJson(const {
        'nickname': '渔报官方',
        'noticeCount': 3,
        'postCount': 128,
        'todayCount': 9,
        'userCount': 1024,
        'bannedCount': 2,
      });
      expect(o.nickname, '渔报官方');
      expect(o.noticeCount, 3);
      expect(o.postCount, 128);
      expect(o.bannedCount, 2);
    });

    test('帖子：canManage / deleted / notice 三个开关都要读对', () {
      final p = OfficialPost.fromJson(const {
        'id': 'p1',
        'title': '违规广告',
        'preview': '加微信 xxx',
        'deleted': 1,
        'notice': 0,
        'canManage': 0,
        'createdAt': '2026-11-04T10:00:00.000Z',
      });
      expect(p.deleted, isTrue);
      expect(p.notice, isFalse);
      expect(p.canManage, isFalse);
      expect(p.displayTitle, '违规广告');
    });

    test('帖子：标题为空时退化成正文预览', () {
      final p = OfficialPost.fromJson(const {
        'id': 'p2',
        'title': '',
        'preview': '今天在沙河钓了三条鲫鱼',
        'createdAt': '2026-11-04T10:00:00.000Z',
      });
      expect(p.displayTitle, '今天在沙河钓了三条鲫鱼');
    });

    test('用户：永久封禁的文案', () {
      final u = OfficialUser.fromJson(const {
        'id': 'u1',
        'nickname': '刷屏号',
        'banned': 1,
        'bannedUntil': '',
        'banReason': '多次发广告',
        'canManage': 1,
      });
      expect(u.banned, isTrue);
      expect(u.banLabel, contains('永久'));
      expect(u.banLabel, contains('多次发广告'));
    });

    test('用户：临时封禁的文案带到期时间', () {
      final u = OfficialUser.fromJson(const {
        'id': 'u2',
        'nickname': '新人',
        'banned': 1,
        'bannedUntil': '2026-11-11T10:00:00.000Z',
        'banReason': '刷屏',
      });
      expect(u.banLabel, contains('封禁至'));
      expect(u.banLabel, contains('刷屏'));
    });

    test('用户：没被封禁时没有封禁文案', () {
      final u = OfficialUser.fromJson(const {'id': 'u3', 'nickname': '正常用户'});
      expect(u.banned, isFalse);
      expect(u.banLabel, '');
    });

    test('操作记录：动作码翻成人话', () {
      expect(
          OfficialLog.fromJson(const {'action': 'notice_new'}).actionLabel, '发布公告');
      expect(OfficialLog.fromJson(const {'action': 'ban_7d'}).actionLabel, '封禁 7 天');
      expect(OfficialLog.fromJson(const {'action': 'ban_forever'}).actionLabel,
          '永久封禁');
      expect(OfficialLog.fromJson(const {'action': 'unban'}).actionLabel, '解除封禁');
      expect(OfficialLog.fromJson(const {'action': 'post_delete'}).actionLabel,
          '删除动态');
    });

    test('时间格式化：11月4日 22:05', () {
      final t = DateTime(2026, 11, 4, 22, 5);
      expect(officialTimeOf(t), '11月4日 22:05');
    });
  });

  group('公告在信息流里的标识', () {
    test('notice=1 → Post.isNotice=true', () {
      final p = Post.fromJson(const {
        'id': 'p1',
        'user_id': 'u1',
        'title': '渔报恢复使用公告',
        'notice': 1,
        'created_at': '2026-11-04T08:00:00.000Z',
      });
      expect(p.isNotice, isTrue);
    });

    test('老后端没有 notice 字段 → 按普通帖子处理', () {
      final p = Post.fromJson(const {
        'id': 'p2',
        'user_id': 'u1',
        'title': '今天的鱼获',
        'created_at': '2026-11-04T08:00:00.000Z',
      });
      expect(p.isNotice, isFalse);
    });

    testWidgets('NoticeTag 画的是红色「公告」', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: Center(child: NoticeTag(height: 17))),
      ));
      expect(find.text('公告'), findsOneWidget);
      final box = tester.widget<Container>(
        find.descendant(of: find.byType(NoticeTag), matching: find.byType(Container)),
      );
      final deco = box.decoration as BoxDecoration;
      expect(deco.color, AppTheme.danger);
    });
  });

  group('源码护栏：权限不能漏', () {
    String read(String p) => File(p).readAsStringSync();

    test('工作台入口只在官方账号下出现', () {
      final src = read('lib/screens/profile_screen.dart');
      expect(src.contains('if (_me?.official == true) _officialEntry()'), isTrue);
      // 不能写成无条件出现
      expect(RegExp(r'^\s*_officialEntry\(\),\s*$', multiLine: true).hasMatch(src),
          isFalse);
    });

    test('工作台三个功能都在', () {
      final src = read('lib/screens/official_console_screen.dart');
      expect(src.contains('发布公告'), isTrue);
      expect(src.contains('帖子管理'), isTrue);
      expect(src.contains('用户管理'), isTrue);
      expect(src.contains('操作记录'), isTrue);
    });

    test('封禁时长只有 1 / 7 / 30 / 永久四档', () {
      final src = read('lib/screens/official_users_screen.dart');
      expect(src.contains("(1, '1 天')"), isTrue);
      expect(src.contains("(7, '7 天')"), isTrue);
      expect(src.contains("(30, '30 天')"), isTrue);
      expect(src.contains("(0, '永久')"), isTrue);
    });

    test('封禁必须填原因（空原因直接打回）', () {
      final src = read('lib/screens/official_users_screen.dart');
      expect(src.contains("if (reason.isEmpty)"), isTrue);
      expect(src.contains('请填写封禁原因'), isTrue);
    });

    test('无权限的帖子不画操作菜单', () {
      final src = read('lib/screens/official_posts_screen.dart');
      expect(src.contains('if (!p.canManage)'), isTrue);
      expect(src.contains('无权限'), isTrue);
    });

    test('用户管理必须先搜索，不给全量列表', () {
      final src = read('lib/screens/official_users_screen.dart');
      expect(src.contains('if (kw.isEmpty)'), isTrue);
      expect(src.contains('输入昵称、手机号或用户 ID 后搜索'), isTrue);
    });

    test('接口路径都在 /official/ 下', () {
      final src = read('lib/services/official_service.dart');
      for (final p in [
        '/official/overview',
        '/official/notices',
        '/official/notice',
        '/official/posts',
        '/official/post',
        '/official/users',
        '/official/user/ban',
        '/official/user/unban',
        '/official/logs',
      ]) {
        expect(src.contains(p), isTrue, reason: '缺少接口 $p');
      }
    });

    test('工作台页面把 404 翻成「后台没升级」，不甩英文异常', () {
      final src = read('lib/screens/official_console_screen.dart');
      expect(src.contains('e.status == 404'), isTrue);
      expect(src.contains('后台还没升级到 v40'), isTrue);
    });
  });
}
