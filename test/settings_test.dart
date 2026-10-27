import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fishing_app/models/post.dart';
import 'package:fishing_app/models/user_address.dart';
import 'package:fishing_app/services/account_history.dart';
import 'package:fishing_app/services/app_settings.dart';
import 'package:fishing_app/services/post_service.dart';
import 'package:fishing_app/utils/legal_text.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AppSettings 字体档位', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      await AppSettings.instance.load();
    });

    test('默认标准档，倍率 1.0（不改动任何现有版式）', () {
      expect(AppSettings.instance.fontLevel, AppSettings.fontStandard);
      expect(AppSettings.instance.fontScale, 1.0);
      expect(AppSettings.instance.fontLevelLabel, '标准');
    });

    test('大 / 特大 倍率与文案', () async {
      await AppSettings.instance.setFontLevel(AppSettings.fontLarge);
      expect(AppSettings.instance.fontScale, closeTo(1.15, 1e-9));
      expect(AppSettings.instance.fontLevelLabel, '大');

      await AppSettings.instance.setFontLevel(AppSettings.fontXLarge);
      expect(AppSettings.instance.fontScale, closeTo(1.30, 1e-9));
      expect(AppSettings.instance.fontLevelLabel, '特大');
    });

    test('字号落本地，重启后仍然生效', () async {
      await AppSettings.instance.setFontLevel(AppSettings.fontXLarge);
      // 模拟重启：重新从 prefs 读
      final p = await SharedPreferences.getInstance();
      expect(p.getString('app_font_scale'), AppSettings.fontXLarge);
      await AppSettings.instance.load();
      expect(AppSettings.instance.fontLevel, AppSettings.fontXLarge);
    });

    test('个性化推荐 / 鱼获隐私默认开启，关掉后持久化', () async {
      expect(AppSettings.instance.personalized, isTrue);
      expect(AppSettings.instance.catchPrivacy, isTrue);
      await AppSettings.instance.setPersonalized(false);
      await AppSettings.instance.setCatchPrivacy(false);
      final p = await SharedPreferences.getInstance();
      expect(p.getBool('app_personalized'), isFalse);
      expect(p.getBool('app_catch_privacy'), isFalse);
    });
  });

  group('历史账号', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    Map<String, dynamic> login({required String id, String phone = '13800001111'}) => {
          'id': id,
          'token': 'token-$id',
          'nickname': '钓友$id',
          'phone': phone,
          'vipLevel': 0,
          'vipName': '普通用户',
          'vipColor': '#90A4AE',
          'vipColor2': '#CFD8DC',
          'vipExpire': '',
        };

    test('登录后写入，最近登录排最前，同一账号只留一条', () async {
      await AccountHistoryStore.remember(login(id: 'a'));
      await AccountHistoryStore.remember(login(id: 'b'));
      await AccountHistoryStore.remember(login(id: 'a')); // 再登一次
      final list = await AccountHistoryStore.load();
      expect(list.length, 2);
      expect(list.first.userId, 'a');
      expect(list.first.token, 'token-a');
    });

    test('手机号打码', () async {
      await AccountHistoryStore.remember(login(id: 'a', phone: '13812345678'));
      final list = await AccountHistoryStore.load();
      expect(list.first.maskedPhone, '138****5678');
    });

    test('超过 30 天的记录自动过滤掉', () async {
      final old = login(id: 'old');
      await AccountHistoryStore.remember(old);
      // 手动把时间改成 31 天前
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('login_history_accounts')!;
      final patched = raw.replaceAll(
        RegExp(r'"at":"[^"]+"'),
        '"at":"${DateTime.now().subtract(const Duration(days: 31)).toIso8601String()}"',
      );
      await prefs.setString('login_history_accounts', patched);

      await AccountHistoryStore.remember(login(id: 'new'));
      final list = await AccountHistoryStore.load();
      expect(list.map((e) => e.userId), ['new']);
    });

    test('最多保留 6 个', () async {
      for (var i = 0; i < 9; i++) {
        await AccountHistoryStore.remember(login(id: 'u$i'));
      }
      final list = await AccountHistoryStore.load();
      expect(list.length, AccountHistoryStore.maxCount);
      expect(list.first.userId, 'u8');
    });

    test('移除记录', () async {
      await AccountHistoryStore.remember(login(id: 'a'));
      await AccountHistoryStore.remember(login(id: 'b'));
      await AccountHistoryStore.remove('a');
      final list = await AccountHistoryStore.load();
      expect(list.map((e) => e.userId), ['b']);
    });

    test('没有 token 的脏数据不会被读出来', () async {
      final bad = login(id: 'x')..['token'] = '';
      await AccountHistoryStore.remember(bad);
      expect(await AccountHistoryStore.load(), isEmpty);
    });
  });

  group('收货地址模型', () {
    test('解析后端字段（isDefault 兼容 true/1）', () {
      final a = UserAddress.fromJson({
        'id': '1',
        'name': '老王',
        'phone': '13812345678',
        'region': '浙江省杭州市西湖区',
        'detail': '文三路 100 号 3 幢 201',
        'isDefault': 1,
      });
      expect(a.isDefault, isTrue);
      expect(a.maskedPhone, '138****5678');
      expect(a.fullAddress, '浙江省杭州市西湖区 文三路 100 号 3 幢 201');
    });

    test('没有省市区时只显示详细地址', () {
      final a = UserAddress.fromJson({
        'id': '2',
        'name': '老王',
        'phone': '13812345678',
        'detail': '文三路 100 号',
      });
      expect(a.isDefault, isFalse);
      expect(a.fullAddress, '文三路 100 号');
    });
  });

  group('设置快照默认值', () {
    test('接口没返回时全部按开启处理（不要让用户莫名被关掉通知）', () {
      final s = SettingsSnapshot.fromJson({});
      expect(s.push, isTrue);
      expect(s.personalized, isTrue);
      expect(s.catchPrivacy, isTrue);
      expect(s.fontScale, 'standard');
      expect(s.support.phone, '');
    });

    test('解析客服信息', () {
      final s = SettingsSnapshot.fromJson({
        'support': {'phone': '400-1', 'wechat': 'wx1', 'hours': '9-21'},
      });
      expect(s.support.phone, '400-1');
      expect(s.support.wechat, 'wx1');
      expect(s.support.hours, '9-21');
    });
  });

  group('协议文本排版', () {
    test('## 开头的行是小节标题，其余是正文，空行忽略', () {
      final blocks = parseLegalText('## 一、服务说明\n渔报是…\n\n## 二、账号\n1. 手机号注册');
      expect(blocks.length, 4);
      expect(blocks[0].isTitle, isTrue);
      expect(blocks[0].text, '一、服务说明');
      expect(blocks[1].isTitle, isFalse);
      expect(blocks[1].text, '渔报是…');
      expect(blocks[2].text, '二、账号');
      expect(blocks[3].text, '1. 手机号注册');
    });

    test('空内容不会产出空段', () {
      expect(parseLegalText(''), isEmpty);
      expect(parseLegalText('\n\n  \n'), isEmpty);
    });
  });

  group('我的作品：解析真实后端行', () {
    // 这是 /posts 与 /posts/mine 真实返回的行结构（字段名和模型不一样）：
    //   user_nickname / content / images（JSON 字符串）/ is_me 是 1 而不是 true
    Map<String, dynamic> row({int isMe = 1}) => {
          'id': 'p1',
          'user_id': 'u1',
          'user_nickname': '老王爱钓鱼',
          'user_avatar': '/uploads/a.png',
          'title': '今日鱼获分享',
          'content': '气压稳，风小',
          // 后端 api_images_abs() 已经把 images 解成数组并补全地址，是 List 不是字符串
          'images': ['http://host/uploads/1.png', 'http://host/uploads/2.png'],
          'category': 'post',
          'location': '千岛湖中心渔场',
          'lat': 29.6,
          'lng': 119.0,
          'created_at': '2026-10-27T08:00:00.000Z',
          'like_count': 3,
          'comment_count': 1,
          'view_count': 12,
          'is_me': isMe,
          'loc_public': 1,
          'fish': '[{"name":"鲫鱼","count":2}]',
          'length_cm': 28.5,
        };

    test('is_me 给 1 也算「我的」', () {
      expect(PostService.mapApiRow(row()).isMe, isTrue);
      expect(PostService.mapApiRow(row(isMe: 0)).isMe, isFalse);
    });

    test('图片 / 正文 / 钓点 / 尺寸都能取到（不是一堆空格子）', () {
      final p = PostService.mapApiRow(row());
      expect(p.imageUrls.length, 2);
      expect(p.body, '气压稳，风小');
      expect(p.locationName, '千岛湖中心渔场');
      expect(p.username, '老王爱钓鱼');
      expect(p.lengthCm, closeTo(28.5, 1e-9));
      expect(p.fish.first['name'], '鲫鱼');
      expect(p.likeCount, 3);
    });

    test('容错布尔：true / 1 / "1" / 0 / null', () {
      expect(Post.truthy(true), isTrue);
      expect(Post.truthy(1), isTrue);
      expect(Post.truthy('1'), isTrue);
      expect(Post.truthy(0), isFalse);
      expect(Post.truthy(null), isFalse);
    });
  });

  group('我的作品不再回落到演示数据', () {
    test('未登录时返回空列表，而不是老钓翁/路亚小王那三条假数据', () async {
      SharedPreferences.setMockInitialValues({});
      final posts = await PostService.fetchMyPosts();
      expect(posts, isEmpty);
      // 演示数据的关键特征：id 是 d1/d2/d3，作者是这些名字
      expect(posts.any((p) => p.id == 'd1' || p.id == 'd2' || p.id == 'd3'), isFalse);
      expect(posts.any((p) => p.username == '老钓翁'), isFalse);
    });
  });
}
