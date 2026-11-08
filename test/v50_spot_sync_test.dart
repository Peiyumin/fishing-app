// v2.1.87 后台删除钓点后，App 地图不跟着消失
//
// 用户反馈（原话）：「后台钓点删除后，前端不会及时更新，点击刷新没反应」
//
// 查下来不是「刷新按钮没接上」，也不是接口没过滤（线上 /spots 只返回
// deleted=0 且 status=1 的最后 156 条），而是**地图合并时只增不删**：
//   宿主页刷新拿到的新列表里已经没有那个点，`didUpdateWidget` 也正常触发，
//   但合并逻辑是「以现有为底、把新数据盖上去」—— 旧点一直躺在 map 里，
//   地图上照旧长着它，点进去还能进详情（内容是上一版快照）。
//
// 这里钉的是 lib/utils/spot_sync.dart 的同步口径：
//   ① 上一轮宿主页给过、这一轮名单里没有 → 剔除（后台删了）
//   ② 上一轮没给过（地图自己拉的钓场/渔具店） → 即使不在 incoming 也保留
//   ③ 同名 id 用新数据覆盖（后台改了名字/坐标）
//   ④ 坐标是 0 的点不上图，也不进「这一轮名单」
import 'package:flutter_test/flutter_test.dart';

import 'package:fishing_app/models/fishing_spot.dart';
import 'package:fishing_app/utils/spot_sync.dart';

FishingSpot spot(String id, {double lat = 30.5, double lng = 114.3}) =>
    FishingSpot(
      id: id,
      name: '钓点$id',
      type: '野钓',
      kind: 'wild',
      lat: lat,
      lng: lng,
      rating: 4.0,
      description: '',
    );

void main() {
  group('① 后台删掉的点必须消失', () {
    test('上一轮给过 A/B/C，这一轮只剩 A → B、C 被剔除', () {
      final map = syncSpotMap(
        current: [spot('A'), spot('B'), spot('C')],
        servedIds: {'A', 'B', 'C'},
        incoming: [spot('A')],
      );
      expect(map.keys.toList(), ['A']);
    });

    test('这一轮是空列表 → 全清（后台把所有点都删了）', () {
      final map = syncSpotMap(
        current: [spot('A'), spot('B')],
        servedIds: {'A', 'B'},
        incoming: const [],
      );
      expect(map, isEmpty);
    });

    test('删一个、加一个（总数不变）也要换人', () {
      // 只比对「数量」的实现会在这里漏掉：数量一样，但成员换了
      final map = syncSpotMap(
        current: [spot('A'), spot('B')],
        servedIds: {'A', 'B'},
        incoming: [spot('A'), spot('C')],
      );
      expect(map.keys.toSet(), {'A', 'C'});
      expect(map.containsKey('B'), isFalse, reason: 'B 已被后台删除');
    });
  });

  group('② 地图自己拉的点不能误删', () {
    test('钓场/渔具店不在宿主页名单里，照旧保留', () {
      final map = syncSpotMap(
        current: [spot('venue-1'), spot('wild-1'), spot('wild-2')],
        // 宿主页只喂野钓点
        servedIds: {'wild-1', 'wild-2'},
        incoming: [spot('wild-1')],
      );
      expect(map.containsKey('venue-1'), isTrue,
          reason: '它从来不是宿主页给的，删不删跟它无关');
      expect(map.keys.toSet(), {'venue-1', 'wild-1'});
    });

    test('第一次同步（servedIds 为空）不会误删任何东西', () {
      final map = syncSpotMap(
        current: [spot('A'), spot('B')],
        servedIds: const {},
        incoming: [spot('C')],
      );
      expect(map.keys.toSet(), {'A', 'B', 'C'});
    });
  });

  group('③ 同名 id 用新数据覆盖', () {
    test('后台改了名字，地图上跟着改', () {
      final map = syncSpotMap(
        current: [spot('A')],
        servedIds: {'A'},
        incoming: [
          const FishingSpot(
            id: 'A',
            name: '改过的名字',
            type: '野钓',
            kind: 'wild',
            lat: 30.5,
            lng: 114.3,
            rating: 4.0,
            description: '',
          ),
        ],
      );
      expect(map['A']!.name, '改过的名字');
    });

    test('后台改了坐标，图上位置跟着动', () {
      final map = syncSpotMap(
        current: [spot('A', lat: 30.0, lng: 114.0)],
        servedIds: {'A'},
        incoming: [spot('A', lat: 31.0, lng: 115.0)],
      );
      expect(map['A']!.lat, 31.0);
      expect(map['A']!.lng, 115.0);
    });
  });

  group('④ 坐标缺失的点不上图', () {
    test('incoming 里坐标为 0 的点被丢掉，不进名单', () {
      final incoming = [spot('A', lat: 0, lng: 0), spot('B')];
      final map = syncSpotMap(
        current: const [],
        servedIds: const {},
        incoming: incoming,
      );
      expect(map.keys.toList(), ['B']);
      expect(drawableSpotIds(incoming), {'B'});
    });

    test('坐标从 0 变成有效：下一轮就能上图', () {
      final first = syncSpotMap(
        current: const [],
        servedIds: const {},
        incoming: [spot('A', lat: 0, lng: 0)],
      );
      expect(first, isEmpty);
      final second = syncSpotMap(
        current: const [],
        servedIds: drawableSpotIds([spot('A', lat: 0, lng: 0)]),
        incoming: [spot('A')],
      );
      expect(second.containsKey('A'), isTrue);
    });
  });
}
