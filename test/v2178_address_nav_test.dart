// v2.1.78：地址文字输入 + 按地址导航 护栏
//
// 需求（用户原话）：
//   「地址可以使用文字输入也可以获取当前位置，输入文字地址，位置添加成功后在
//     详情页点击导航前往后，选择导航App后直接在目的地输入文字地址导航
//     有精确坐标的按照坐标导航，没有精确坐标的按文字地址导航」
//
// 这里守住三件事：
//   1. 三个添加页都有「详细地址」输入框，且能手打、能定位
//   2. 手改地址后坐标标记降级（否则会拿旧坐标当新地址的位置）
//   3. 导航 URL：有坐标带经纬度、没坐标只带地址文字
import 'dart:io';

import 'package:fishing_app/models/fishing_spot.dart';
import 'package:fishing_app/services/map_launcher.dart';
import 'package:fishing_app/services/spot_service.dart';
import 'package:flutter_test/flutter_test.dart';

String read(String rel) => File(rel).readAsStringSync();

FishingSpot spot({
  double lat = 34.14488,
  double lng = 113.46309,
  bool precise = true,
  String address = '河南省许昌市禹州市夏都街道',
}) =>
    FishingSpot(
      id: 'sp1',
      name: '青龙湖野钓点',
      type: '野钓',
      lat: lat,
      lng: lng,
      rating: 4.0,
      description: '',
      address: address,
      coordPrecise: precise,
    );

void main() {
  group('坐标可信度判定', () {
    test('精确坐标 + 有效经纬度 → 按坐标导航', () {
      expect(spot().canNavigateByCoord, isTrue);
    });

    test('标记不精确 → 按地址导航', () {
      expect(spot(precise: false).canNavigateByCoord, isFalse);
    });

    test('坐标是 0 → 按地址导航（0 是「没有坐标」的约定）', () {
      expect(spot(lat: 0, lng: 0).canNavigateByCoord, isFalse);
      expect(spot(lat: 0, lng: 113.4).canNavigateByCoord, isFalse);
    });

    test('默认构造就是精确（老数据不会被误判成地址点）', () {
      final s = FishingSpot(
        id: 'x',
        name: 'x',
        type: '野钓',
        lat: 30.1,
        lng: 120.1,
        rating: 0,
        description: '',
      );
      expect(s.coordPrecise, isTrue);
    });

    test('接口返回 coord_precise=0 时解析成 false', () {
      final s = SpotService.mapApiRow({
        'id': 'a', 'name': 'b', 'lat': 34.1, 'lng': 113.4,
        'coord_precise': 0,
      });
      expect(s.coordPrecise, isFalse);
      expect(s.canNavigateByCoord, isFalse);
    });

    test('接口返回 coord_precise=1 时解析成 true', () {
      final s = SpotService.mapApiRow({
        'id': 'a', 'name': 'b', 'lat': 34.1, 'lng': 113.4,
        'coord_precise': 1,
      });
      expect(s.coordPrecise, isTrue);
    });

    test('后端没这个字段（老版本）时按精确处理', () {
      final s = SpotService.mapApiRow({
        'id': 'a', 'name': 'b', 'lat': 34.1, 'lng': 113.4,
      });
      expect(s.coordPrecise, isTrue);
    });
  });

  group('导航 URL：有坐标 vs 没坐标', () {
    final addr = '河南省许昌市禹州市夏都街道';
    final addrQ = Uri.encodeComponent(addr);

    List<NavTarget> android({required bool hasCoord}) => MapLauncher.buildTargets(
          isAndroid: true,
          isIOS: false,
          hasCoord: hasCoord,
          dlat: 34.144880,
          dlng: 113.463090,
          coord: '34.144880,113.463090',
          destQ: addrQ,
          nameQ: Uri.encodeComponent('青龙湖野钓点'),
        );

    List<NavTarget> ios({required bool hasCoord}) => MapLauncher.buildTargets(
          isAndroid: false,
          isIOS: true,
          hasCoord: hasCoord,
          dlat: 34.144880,
          dlng: 113.463090,
          coord: '34.144880,113.463090',
          destQ: addrQ,
          nameQ: Uri.encodeComponent('青龙湖野钓点'),
        );

    test('安卓出三个地图，iOS 出四个（含苹果地图）', () {
      expect(android(hasCoord: true).length, 3);
      expect(ios(hasCoord: true).length, 4);
      expect(ios(hasCoord: true).map((t) => t.name), contains('苹果地图'));
    });

    test('有坐标：高德带 dlat/dlon', () {
      final amap = android(hasCoord: true).first;
      expect(amap.nativeUrl.contains('dlat=34.144880'), isTrue);
      expect(amap.nativeUrl.contains('dlon=113.463090'), isTrue);
      expect(amap.nativeUrl.startsWith('amapuri://'), isTrue);
    });

    test('有坐标：腾讯带 tocoord、百度带 latlng:', () {
      final list = android(hasCoord: true);
      final qq = list.firstWhere((t) => t.name == '腾讯地图');
      final bd = list.firstWhere((t) => t.name == '百度地图');
      expect(qq.nativeUrl.contains('tocoord=34.144880,113.463090'), isTrue);
      expect(bd.nativeUrl.contains('latlng:34.144880,113.463090'), isTrue);
      expect(bd.nativeUrl.contains('coord_type=gcj02'), isTrue);
    });

    test('没坐标：一个经纬度都不许带', () {
      for (final t in android(hasCoord: false)) {
        expect(t.nativeUrl.contains('dlat='), isFalse, reason: t.name);
        expect(t.nativeUrl.contains('tocoord='), isFalse, reason: t.name);
        expect(t.nativeUrl.contains('latlng:'), isFalse, reason: t.name);
      }
      for (final t in ios(hasCoord: false)) {
        expect(t.nativeUrl.contains('dlat='), isFalse, reason: t.name);
        expect(t.nativeUrl.contains('tocoord='), isFalse, reason: t.name);
      }
    });

    test('没坐标：完整地址进各 App 的搜索参数', () {
      final amap = android(hasCoord: false).first;
      // 高德 route/plan 只认 dlat/dlon，没坐标必须换 keywordNavi，否则没有终点
      expect(amap.nativeUrl.contains('keyword=$addrQ'), isTrue);
      expect(amap.nativeUrl.contains('keywordNavi'), isTrue);
      final qq = android(hasCoord: false).firstWhere((t) => t.name == '腾讯地图');
      expect(qq.nativeUrl.contains('keyword=$addrQ'), isTrue);
      expect(qq.nativeUrl.contains('/search'), isTrue);
      final bd = android(hasCoord: false).firstWhere((t) => t.name == '百度地图');
      expect(bd.nativeUrl.contains('destination=$addrQ'), isTrue);
    });

    test('苹果地图：有坐标走 daddr=经纬度，没坐标走 daddr=地址', () {
      final okMap = ios(hasCoord: true).firstWhere((t) => t.name == '苹果地图');
      expect(okMap.nativeUrl, 'maps://?daddr=34.144880,113.463090&dirflg=d');
      final addrMap = ios(hasCoord: false).firstWhere((t) => t.name == '苹果地图');
      expect(addrMap.nativeUrl, 'maps://?daddr=$addrQ&dirflg=d');
    });

    test('中文地址做了 URL 编码（原样塞进去会被截断）', () {
      final amap = android(hasCoord: false).first;
      expect(amap.nativeUrl.contains('河南省'), isFalse);
      expect(amap.nativeUrl.contains('%E6%B2%B3%E5%8D%97'), isTrue);
    });
  });

  group('三个添加页的地址交互', () {
    final wild = read('lib/screens/publish_spot_screen.dart');
    final venue = read('lib/screens/publish_venue_screen.dart');
    final shop = read('lib/screens/publish_shop_screen.dart');

    test('野钓点页补了「详细地址」输入框（原来只能在图上点）', () {
      expect(wild.contains("ValueKey('spot_addr')"), isTrue);
      expect(wild.contains("labelText: '详细地址'"), isTrue);
      expect(wild.contains('用当前位置'), isTrue);
    });

    test('钓场 / 渔具店页地址框有定位按钮和辅助说明', () {
      for (final f in [venue, shop]) {
        expect(f.contains("labelText: '详细地址'"), isTrue);
        expect(f.contains('helperText: _addrHint'), isTrue);
        expect(f.contains('_fillAddressByLocation'), isTrue);
      }
    });

    test('手改地址后坐标可信度降级（这是导航导错的根因）', () {
      for (final f in [wild, venue, shop]) {
        expect(f.contains('if (_precise) setState(() => _precise = false);'),
            isTrue);
      }
    });

    test('定位 / 地图点选后标记为精确', () {
      for (final f in [wild, venue, shop]) {
        expect(f.contains('_precise = true'), isTrue);
      }
    });

    test('提交时按地址重新解析坐标', () {
      // v45：解析入口收敛到 AddressLookup（带失败原因），页面不再直接调服务
      for (final f in [wild, venue, shop]) {
        expect(f.contains('AddressLookup.resolve(addrText)'), isTrue);
        expect(f.contains('coordPrecise: precise'), isTrue);
      }
    });

    test('地址解析不出时弹选择层，绝不默认用当前定位', () {
      for (final f in [wild, venue, shop]) {
        expect(f.contains('showAddressFallbackSheet'), isTrue);
        // 老代码有一条「解析失败就照常提交旧坐标」的静默分支，必须删掉
        expect(f.contains('有之前的坐标但地址解析失败'), isFalse);
      }
    });
  });

  group('详情页导航分流', () {
    final detail = read('lib/screens/spot_detail_screen.dart');
    final shopDetail = read('lib/screens/shop_detail_screen.dart');

    test('钓点详情直接把经纬度交给地图 App（v46：有坐标就按坐标导）', () {
      expect(detail.contains('lat: s.lat'), isTrue);
      expect(detail.contains('lng: s.lng'), isTrue);
      // v46 删掉了 precise 开关，详情页不许再按 coordPrecise 降级成文字搜索
      expect(detail.contains('precise:'), isFalse);
    });

    test('渔具店详情同样不按 coordPrecise 降级', () {
      expect(shopDetail.contains('lat: _s.lat'), isTrue);
      expect(shopDetail.contains('precise:'), isFalse);
    });

    test('地址卡只提示精度，不再说「导航会按地址搜索」', () {
      expect(detail.contains('这个点只有文字地址，导航会按地址搜索'), isFalse);
      expect(detail.contains('位置按地址定位'), isTrue);
    });
  });

  group('服务层契约', () {
    final svc = read('lib/services/spot_service.dart');

    test('addSpot 把 coord_precise 传给后端', () {
      expect(svc.contains("'coord_precise': coordPrecise ? 1 : 0"), isTrue);
    });

    test('地址解析走自家 /geo/forward（高德 Key 不能放客户端）', () {
      expect(svc.contains("ApiClient.post('/geo/forward'"), isTrue);
      expect(svc.contains('geocodeAddress'), isTrue);
    });

    test('地址太短不调接口（省一次外部请求）', () {
      expect(svc.contains('if (addr.length < 4)'), isTrue);
    });
  });
}
