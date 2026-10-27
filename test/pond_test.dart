import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fishing_app/data/fish_assets.dart';
import 'package:fishing_app/screens/pond_screen.dart';

/// 池塘（v2.1.29 从「鱼缸」改成真实池塘）回归
///
/// 这里只测**不依赖动画与 GPU** 的部分：
///   - 本地存档往返（换机/重启不能丢鱼）
///   - 46 种鱼的素材映射（有一个查不到就会出现一张空白格）
///   - 水面椭圆参数必须落在图片范围里（否则鱼会游到岸上）
///   - 页面能打开不抛异常
/// 画面本身（游动/跃水/焦散）靠真机看，不在单测里断言像素。
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('池塘存档', () {
    test('存进去能原样读回来', () async {
      const f = PondFish(
          id: 'sp1', name: '鲫鱼', water: 'fresh', rarity: 'common');
      final back = PondFish.fromJson(f.toJson());
      expect(back.id, 'sp1');
      expect(back.name, '鲫鱼');
      expect(back.water, 'fresh');
      expect(back.rarity, 'common');
    });

    test('保存后重新读取，条数与顺序不变', () async {
      final fish = [
        const PondFish(id: 'a', name: '鲤鱼', water: 'fresh', rarity: 'rare'),
        const PondFish(id: 'b', name: '鲈鱼', water: 'fresh', rarity: 'common'),
        const PondFish(id: 'a', name: '鲤鱼', water: 'fresh', rarity: 'rare'),
      ];
      await PondStore.save(fish);
      final back = await PondStore.load();
      expect(back.length, 3);
      expect(back.map((e) => e.name).toList(), ['鲤鱼', '鲈鱼', '鲤鱼']);
    });

    test('空存档 / 脏数据都当成空池子，不崩', () async {
      expect(await PondStore.load(), isEmpty);
      SharedPreferences.setMockInitialValues(
          {'tank_fish_v1': '{不是 json'});
      expect(await PondStore.load(), isEmpty);
      SharedPreferences.setMockInitialValues(
          {'tank_fish_v1': '[{"id":""},{"name":"没有 id"}]'});
      expect(await PondStore.load(), isEmpty);
    });

    test('沿用旧存档键：老用户升级后缸里的鱼还在', () async {
      SharedPreferences.setMockInitialValues({
        'tank_fish_v1':
            '[{"id":"x1","name":"草鱼","water":"fresh","rarity":"common"}]'
      });
      final back = await PondStore.load();
      expect(back.length, 1);
      expect(back.first.name, '草鱼');
    });

    test('从渔获记录生成池塘鱼（fish 是数组取第一条，image 单张）', () {
      final p = PondFish.fromCatch({
        'id': 'c9',
        'fish': ['鳜鱼', '鲫鱼'],
        'lengthCm': 38.5,
        'weightG': 1250,
        'createdAt': '2026-10-20 08:30:00',
        'location': '千岛湖',
        'image': 'https://x/y.jpg',
      });
      expect(p.id, 'c9');
      expect(p.name, '鳜鱼');
      expect(p.rarity, '');
      expect(p.lengthCm, 38.5);
      expect(p.weightG, 1250);
      expect(p.caughtAt, '2026-10-20 08:30:00');
      expect(p.location, '千岛湖');
      expect(p.photo, 'https://x/y.jpg');
    });

    test('渔获记录缺尺寸 / 空图时字段为 null，不崩', () {
      final p = PondFish.fromCatch({
        'id': 'c10',
        'fish': '草鱼',
        'createdAt': '2026-10-20 08:30:00',
        'image': '',
      });
      expect(p.name, '草鱼');
      expect(p.lengthCm, isNull);
      expect(p.weightG, isNull);
      expect(p.photo, isNull);
    });

    test('尺寸字段带进存档能原样读回', () async {
      const f = PondFish(
        id: 'c11',
        name: '鲤鱼',
        water: 'fresh',
        lengthCm: 42,
        weightG: 2100,
        caughtAt: '2026-10-21 09:15:00',
        location: '太湖',
        photo: 'https://x/z.jpg',
      );
      await PondStore.save([f]);
      final back = await PondStore.load();
      expect(back.length, 1);
      expect(back.first.lengthCm, 42);
      expect(back.first.weightG, 2100);
      expect(back.first.caughtAt, '2026-10-21 09:15:00');
      expect(back.first.location, '太湖');
      expect(back.first.photo, 'https://x/z.jpg');
    });
  });

  group('真实鱼素材映射', () {
    test('词库里的 46 种鱼都能找到自己的图', () {
      const names = [
        '鲫鱼', '鲤鱼', '草鱼', '鲢鱼', '鳙鱼', '青鱼', '罗非鱼', '翘嘴鲌',
        '鲮鱼', '黄颡鱼', '鲇鱼', '鳊鱼', '马口鱼', '麦穗鱼', '白条', '黑鱼',
        '鲈鱼', '鳜鱼', '鲟鱼', '鳡鱼', '大银鱼', '胭脂鱼', '江雪',
        '海鲈鱼', '大黄鱼', '小黄鱼', '带鱼', '鲅鱼', '鲷鱼', '石斑鱼',
        '黑鲷', '真鲷', '比目鱼', '鲐鱼', '鲻鱼', '海鳗', '鱿鱼', '章鱼',
        '海鲫鱼', '六线鱼', '黑头鱼', '金枪鱼', '旗鱼', '剑鱼', '石鲷', '翻车鱼',
      ];
      expect(names.length, 46);
      for (final n in names) {
        expect(FishAssets.has(n), isTrue, reason: '「$n」没有对应素材');
        expect(FishAssets.pathOf(n), 'assets/fish/${FishAssets.slugOf(n)}.png');
      }
    });

    test('俗称 / 别名也能对上标准鱼（鲶鱼→鲇鱼、胖头鱼→鳙鱼）', () {
      expect(FishAssets.slugOf('鲶鱼'), FishAssets.slugOf('鲇鱼'));
      expect(FishAssets.slugOf('胖头鱼'), FishAssets.slugOf('鳙鱼'));
      expect(FishAssets.slugOf('翘嘴'), FishAssets.slugOf('翘嘴鲌'));
      expect(FishAssets.slugOf('黄辣丁'), FishAssets.slugOf('黄颡鱼'));
    });

    test('完全不认识的鱼按水类型兜底，不会出现空白格', () {
      expect(FishAssets.pathOrFallback('不存在的鱼'), 'assets/fish/caoyu.png');
      expect(FishAssets.pathOrFallback('不存在的鱼', waterType: 'salt'),
          'assets/fish/diaoyu.png');
    });
  });

  group('池塘几何', () {
    test('水面椭圆在图片范围内，且不贴边（鱼不会游到岸上）', () {
      expect(PondSpec.cx - PondSpec.rx, greaterThan(0.05));
      expect(PondSpec.cx + PondSpec.rx, lessThan(0.95));
      expect(PondSpec.cy - PondSpec.ry, greaterThan(0.05));
      expect(PondSpec.cy + PondSpec.ry, lessThan(0.95));
      expect(PondSpec.rx, greaterThan(0.1), reason: '池塘要占住画面主体');
    });
  });

  group('按真实体长 ×10 缩放', () {
    test('不同鱼之间的比例严格等于真实体长比例', () {
      // 60cm 的鱼正好是 30cm 的两倍；45cm 是 30cm 的 1.5 倍
      expect(pondSizeFraction(60), closeTo(pondSizeFraction(30) * 2, 1e-9));
      expect(pondSizeFraction(45), closeTo(pondSizeFraction(30) * 1.5, 1e-9));
    });

    test('30cm 的鱼约占水宽 13.8%', () {
      expect(pondSizeFraction(30), closeTo(0.138, 1e-9));
    });

    test('没填长度按 25cm 估算', () {
      expect(pondSizeFraction(null), closeTo(pondSizeFraction(25), 1e-9));
      expect(pondSizeFraction(null), closeTo(0.115, 1e-9));
    });

    test('过大 / 过小都夹在可看范围（5%~46% 水宽）', () {
      expect(pondSizeFraction(300), 0.46);
      expect(pondSizeFraction(3), 0.05);
    });
  });

  testWidgets('池塘页能打开，不抛异常', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const MaterialApp(home: PondScreen()));
    await tester.pump(); // 首帧
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.byType(Scaffold), findsWidgets);
    expect(find.text('我的池塘'), findsOneWidget);
    // 底部一定有「放鱼」入口
    expect(find.text('放鱼'), findsOneWidget);
    // 水面动画在跑，别在测试里无限 pumpAndSettle
    await tester.pump(const Duration(seconds: 1));
  });
}
