import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fishing_app/models/message.dart';
import 'package:fishing_app/models/official.dart';
import 'package:fishing_app/screens/message_center_screen.dart';
import 'package:fishing_app/screens/notice_editor_screen.dart';
import 'package:fishing_app/screens/official_notice_screen.dart';
import 'package:fishing_app/screens/official_spots_screen.dart';
import 'package:fishing_app/services/message_service.dart';
import 'package:fishing_app/services/official_service.dart';

/// v2.1.73 · 公告改为「系统通知」+ 官方钓点编辑
///
/// 这一版最容易犯的错是「改完才发现公告又跑到信息流去了」，
/// 所以这里把三件关键的事情钉住：
///   ① 公告的数据形状（配图 / 作者头像 / 摘要）解析正确；
///   ② 系统通知列表里，官方公告带头像 + 「官方公告」标签，点开是公告详情；
///   ③ 钓点管理列表能出数据，编辑器和公告编辑器都能正常渲染（含配图格子）。
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() {
    OfficialService.testSpots = null;
    OfficialService.testSpotDraft = null;
    OfficialService.testNotices = null;
    MessageService.testNotices = null;
  });

  group('公告模型', () {
    test('解析配图 / 作者头像 / 摘要', () {
      final n = OfficialNotice.fromJson({
        'id': 'n1',
        'title': '系统维护通知',
        'content': '今晚 23:00 起维护，\n预计 30 分钟。',
        'images': ['https://cdn.test/a.jpg', 'https://cdn.test/b.jpg'],
        'pinned': 1,
        'createdAt': '2026-11-05T00:00:00.000Z',
        'authorName': '渔报官方',
        'authorAvatar': 'https://cdn.test/av.png',
      });
      expect(n.id, 'n1');
      expect(n.images.length, 2);
      expect(n.pinned, isTrue);
      expect(n.authorAvatar, 'https://cdn.test/av.png');
      // 列表摘要要把换行压平，否则卡片上会多出一段空白
      expect(n.summary.contains('\n'), isFalse);
      expect(n.summary, contains('今晚 23:00'));
    });

    test('images 缺失 / 传字符串都不会炸', () {
      final a = OfficialNotice.fromJson({'id': 'x', 'title': 't'});
      expect(a.images, isEmpty);
      final b = OfficialNotice.fromJson({'id': 'y', 'images': 'a.jpg'});
      expect(b.images, ['a.jpg']);
    });

    test('pinned 用 true 或 1 都认（后端历史上有过两种写法）', () {
      expect(OfficialNotice.fromJson({'pinned': true}).pinned, isTrue);
      expect(OfficialNotice.fromJson({'pinned': 1}).pinned, isTrue);
      expect(OfficialNotice.fromJson({'pinned': 0}).pinned, isFalse);
    });
  });

  group('通知条目', () {
    test('officialId 有值就算官方公告', () {
      final a = NoticeItem.fromJson({'id': 'n1', 'officialId': 'n1'});
      expect(a.isOfficial, isTrue);
      final b = NoticeItem.fromJson({'id': 's1', 'type': 'system'});
      expect(b.isOfficial, isFalse);
    });

    test('copyWithRead 保留所有字段（点过之后红点消除但内容不丢）', () {
      final a = NoticeItem.fromJson({
        'id': 'n1',
        'type': 'official',
        'officialId': 'n1',
        'title': '标题',
        'content': '摘要',
        'pinned': 1,
        'imageCount': 3,
        'fromName': '渔报官方',
        'createdAt': '2026-11-05T00:00:00.000Z',
      });
      final b = a.copyWithRead(true);
      expect(b.isRead, isTrue);
      expect(b.title, '标题');
      expect(b.officialId, 'n1');
      expect(b.imageCount, 3);
      expect(b.pinned, isTrue);
      expect(b.fromName, '渔报官方');
    });
  });

  group('钓点模型', () {
    test('列表行解析：坐标 / 状态 / 图片数', () {
      final s = OfficialSpot.fromJson({
        'id': 'sp1',
        'name': '许昌西湖黑坑',
        'kind': 'venue',
        'type': '黑坑',
        'status': 1,
        'statusLabel': '已上架',
        'address': '许昌市魏都区',
        'cover': 'https://cdn.test/c.jpg',
        'lat': 34.03,
        'lng': 113.85,
        'imageCount': 4,
        'createdAt': '2026-11-01T00:00:00.000Z',
      });
      expect(s.name, '许昌西湖黑坑');
      expect(s.kindLabel, '钓场');
      expect(s.hasLocation, isTrue);
      expect(s.lat, closeTo(34.03, 1e-6));
      expect(s.imageCount, 4);
    });

    test('没有坐标时 hasLocation=false（列表上要标「缺定位」）', () {
      final s = OfficialSpot.fromJson({'id': 'sp2', 'name': '某钓点'});
      expect(s.hasLocation, isFalse);
    });

    test('草稿 toJson 全字段都在（保存是全量覆盖，漏字段会清空数据）', () {
      final d = OfficialSpotDraft(
        id: 'sp1',
        name: '新名字',
        kind: 'wild',
        type: '野钓',
        description: '简介',
        address: '地址',
        fee: '免费',
        fish: '鲫鱼',
        tags: '夜钓',
        phone: '13800000000',
        lat: 34.1,
        lng: 113.9,
        rating: 4.5,
        images: const ['https://cdn.test/a.jpg'],
      );
      final j = d.toJson();
      expect(j['name'], '新名字');
      expect(j['kind'], 'wild');
      expect(j['lat'], 34.1);
      expect(j['lng'], 113.9);
      expect(j['images'], hasLength(1));
      // 关键：定位字段必须在，否则后端会因为「没传坐标」直接 400
      expect(j.containsKey('lat') && j.containsKey('lng'), isTrue);
    });

    test('copyWithFields 只覆盖传入的字段', () {
      final d = OfficialSpotDraft(id: 'sp1', name: '旧名', lat: 30.0, lng: 120.0);
      final e = d.copyWithFields(name: '新名');
      expect(e.name, '新名');
      expect(e.lat, 30.0);
      expect(e.id, 'sp1');
    });
  });

  group('钓点管理页', () {
    testWidgets('渲染列表：名称、状态、缺定位提示', (tester) async {
      OfficialService.testSpots = [
        OfficialSpot(
          id: 'sp1',
          name: '许昌西湖黑坑',
          kind: 'venue',
          type: '黑坑',
          status: 1,
          statusLabel: '已上架',
          address: '许昌市魏都区',
          lat: 34.03,
          lng: 113.85,
          imageCount: 4,
          createdAt: DateTime(2026, 11, 1),
        ),
        OfficialSpot(
          id: 'sp2',
          name: '没定位的钓点',
          status: 0,
          statusLabel: '待审核',
          createdAt: DateTime(2026, 11, 1),
        ),
      ];
      await tester.pumpWidget(
        const MaterialApp(home: OfficialSpotsScreen()),
      );
      await tester.pumpAndSettle();

      expect(find.text('钓点管理'), findsOneWidget);
      expect(find.text('许昌西湖黑坑'), findsOneWidget);
      expect(find.text('已上架'), findsWidgets);
      expect(find.text('待审核'), findsWidgets);
      expect(find.text('没定位的钓点'), findsOneWidget);
      // 第二个没坐标 → 必须提示「缺定位」
      expect(find.text('缺定位'), findsOneWidget);
    });
  });

  group('系统通知里的官方公告', () {
    NoticeItem officialItem() => NoticeItem.fromJson({
          'id': 'n1',
          'type': 'official',
          'officialId': 'n1',
          'typeTitle': '官方公告',
          'title': '渔报已完成升级',
          'content': '现在可以正常使用了',
          'pinned': 1,
          'imageCount': 2,
          'fromName': '渔报官方',
          'createdAt': '2026-11-05T00:00:00.000Z',
        });

    testWidgets('列表里带「官方公告」标签和标题', (tester) async {
      MessageService.testNotices = [officialItem()];
      await tester.pumpWidget(const MaterialApp(
        home: NoticeListScreen(type: 'system', title: '系统通知'),
      ));
      await tester.pumpAndSettle();

      expect(find.text('官方公告'), findsOneWidget);
      expect(find.text('渔报已完成升级'), findsOneWidget);
      expect(find.text('现在可以正常使用了'), findsOneWidget);
    });

    testWidgets('点一条官方公告 → 进公告详情页', (tester) async {
      MessageService.testNotices = [officialItem()];
      await tester.pumpWidget(const MaterialApp(
        home: NoticeListScreen(type: 'system', title: '系统通知'),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('渔报已完成升级'));
      await tester.pumpAndSettle();

      // 详情页会去拉正文（测试环境没有网），但页面本身必须已经推进去了
      expect(find.byType(OfficialNoticeScreen), findsOneWidget);
      // 用列表里带过来的标题先把内容顶上去，不能白屏
      expect(find.text('渔报已完成升级'), findsWidgets);
    });
  });

  group('公告编辑器', () {
    testWidgets('新建时能渲染配图区（0/9）', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: NoticeEditorScreen()));
      await tester.pumpAndSettle();

      expect(find.text('发布公告'), findsOneWidget);
      expect(find.text('配图'), findsOneWidget);
      expect(find.text('0/9'), findsOneWidget);
      expect(find.text('添加图片'), findsOneWidget);
    });

    testWidgets('编辑已有公告时把旧图带出来', (tester) async {
      final n = OfficialNotice(
        id: 'n1',
        title: '旧公告',
        content: '正文',
        images: const ['https://cdn.test/a.jpg', 'https://cdn.test/b.jpg'],
        createdAt: DateTime.now(),
      );
      await tester.pumpWidget(
        MaterialApp(home: NoticeEditorScreen(notice: n)),
      );
      await tester.pumpAndSettle();

      expect(find.text('编辑公告'), findsOneWidget);
      expect(find.text('2/9'), findsOneWidget);
    });
  });
}
