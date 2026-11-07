// v46 导航分流：有坐标就按坐标导，没坐标才把完整文字地址交给地图 App 搜
//
// 背景（v2.1.79 线上实际表现）：
//   1. 高德那条「没坐标」的链接是 `amapuri://route/plan/?dname=地址`，
//      而高德的 route/plan **必须有 dlat/dlon** 才算得出一条路线 ——
//      只给 dname 时它打开的是一个没有终点的路线页，用户以为点了没反应。
//   2. 详情页把 `coordPrecise=0` 的点全都推去「按地址搜」，
//      可这些点的坐标本来就是那句地址解析出来的位置，放着坐标不用反而容易搜偏。
// 这两个坑都在这组测试里钉住。

import 'dart:io';

import 'package:fishing_app/services/map_launcher.dart';
import 'package:flutter_test/flutter_test.dart';

String read(String p) => File(p).readAsStringSync();

void main() {
  const addr = '河南省许昌市禹州市夏都街道';
  final addrQ = Uri.encodeComponent(addr);
  const lat = 34.144880;
  const lng = 113.463090;
  const coord = '34.144880,113.463090';

  List<NavTarget> android({required bool hasCoord}) => MapLauncher.buildTargets(
        isAndroid: true,
        isIOS: false,
        hasCoord: hasCoord,
        dlat: lat,
        dlng: lng,
        coord: coord,
        destQ: addrQ,
        nameQ: Uri.encodeComponent('青龙湖野钓点'),
      );

  List<NavTarget> ios({required bool hasCoord}) => MapLauncher.buildTargets(
        isAndroid: false,
        isIOS: true,
        hasCoord: hasCoord,
        dlat: lat,
        dlng: lng,
        coord: coord,
        destQ: addrQ,
        nameQ: Uri.encodeComponent('青龙湖野钓点'),
      );

  group('有坐标：一律按坐标导航', () {
    test('安卓三个地图全部带坐标', () {
      for (final t in android(hasCoord: true)) {
        final u = t.nativeUrl;
        final has = u.contains('dlat=$lat') ||
            u.contains('tocoord=$coord') ||
            u.contains('latlng:$coord');
        expect(has, isTrue, reason: '${t.name} 没带坐标：$u');
      }
    });

    test('iOS 四个地图全部带坐标（含苹果地图 daddr=经纬度）', () {
      for (final t in ios(hasCoord: true)) {
        final u = t.nativeUrl;
        final has = u.contains('dlat=$lat') ||
            u.contains('tocoord=$coord') ||
            u.contains('latlng:$coord') ||
            u.contains('daddr=$coord');
        expect(has, isTrue, reason: '${t.name} 没带坐标：$u');
      }
    });

    test('终点名显示的是完整地址（不是只有钓点名）', () {
      final amap = android(hasCoord: true).first;
      expect(amap.nativeUrl.contains('dname=$addrQ'), isTrue);
    });

    test('坐标保留 6 位小数，别被 toString 抹成 34.14488', () {
      expect(android(hasCoord: true).first.nativeUrl.contains('dlat=34.144880'),
          isTrue);
    });
  });

  group('没坐标：完整文字地址进搜索参数', () {
    test('高德必须走 keywordNavi（route/plan 没坐标会没有终点）', () {
      final amap = android(hasCoord: false).first;
      expect(amap.nativeUrl.startsWith('androidamap://keywordNavi'), isTrue);
      expect(amap.nativeUrl.contains('keyword=$addrQ'), isTrue);
      expect(amap.nativeUrl.contains('route/plan'), isFalse);
      expect(amap.nativeUrl.contains('dname='), isFalse);
    });

    test('iOS 高德同样走 keywordNavi', () {
      final amap = ios(hasCoord: false).first;
      expect(amap.nativeUrl.startsWith('iosamap://keywordNavi'), isTrue);
      expect(amap.nativeUrl.contains('keyword=$addrQ'), isTrue);
    });

    test('腾讯改走地点搜索（routeplan 缺 tocoord 规划不出来）', () {
      final qq = android(hasCoord: false).firstWhere((t) => t.name == '腾讯地图');
      expect(qq.nativeUrl.contains('qqmap://map/search'), isTrue);
      expect(qq.nativeUrl.contains('keyword=$addrQ'), isTrue);
      expect(qq.nativeUrl.contains('tocoord='), isFalse);
      expect(qq.nativeUrl.contains('routeplan'), isFalse);
    });

    test('百度把完整地址塞进 destination', () {
      final bd = android(hasCoord: false).firstWhere((t) => t.name == '百度地图');
      expect(bd.nativeUrl.contains('destination=$addrQ'), isTrue);
      expect(bd.nativeUrl.contains('mode=driving'), isTrue);
    });

    test('苹果地图 daddr=完整地址', () {
      final m = ios(hasCoord: false).firstWhere((t) => t.name == '苹果地图');
      expect(m.nativeUrl, 'maps://?daddr=$addrQ&dirflg=d');
    });

    test('一个经纬度参数都不许出现', () {
      for (final t in [...android(hasCoord: false), ...ios(hasCoord: false)]) {
        final u = t.nativeUrl;
        for (final bad in ['dlat=', 'dlon=', 'tocoord=', 'latlng=', 'daddr=34']) {
          expect(u.contains(bad), isFalse, reason: '${t.name} 带了 $bad：$u');
        }
      }
    });
  });

  group('URL 本身要能唤起 App', () {
    test('每个链接都是合法 URI 且 scheme 正确', () {
      const schemes = {
        '高德地图': ['amapuri', 'androidamap', 'iosamap'],
        '腾讯地图': ['qqmap'],
        '百度地图': ['baidumap'],
        '苹果地图': ['maps'],
      };
      for (final list in [android(hasCoord: true), android(hasCoord: false),
                          ios(hasCoord: true), ios(hasCoord: false)]) {
        for (final t in list) {
          final uri = Uri.parse(t.nativeUrl);
          expect(schemes[t.name]!.contains(uri.scheme), isTrue,
              reason: '${t.name} scheme 不对：${uri.scheme}');
          // 苹果地图是 `maps://?daddr=` 这种没有 host 的写法（Apple 官方格式），
          // 其余三家都必须有 host，否则 App 收不到路由
          if (uri.scheme != 'maps') {
            expect(uri.host, isNotEmpty, reason: '${t.name} 没有 host');
          }
        }
      }
    });

    test('中文地址解码后与原文完全一致（没被截断）', () {
      final amap = android(hasCoord: false).first;
      final uri = Uri.parse(amap.nativeUrl);
      expect(uri.queryParameters['keyword'], addr);
      expect(uri.queryParameters['keyword']!.length, addr.length);
    });

    test('没有双重编码（%25 说明编了两次，地图 App 会搜不到）', () {
      for (final list in [android(hasCoord: true), ios(hasCoord: false)]) {
        for (final t in list) {
          expect(t.nativeUrl.contains('%25'), isFalse, reason: t.nativeUrl);
        }
      }
    });
  });

  group('地址清洗', () {
    test('换行、制表、全角空格、连写空格都被压成一个空格', () {
      expect(MapLauncher.tidy('河南省许昌市\r\n禹州市\t夏都街道'),
          '河南省许昌市 禹州市 夏都街道');
      expect(MapLauncher.tidy('  河南省　禹州市  '), '河南省 禹州市');
      expect(MapLauncher.tidy('河南省   禹州市'), '河南省 禹州市');
    });

    test('中文地址里夹杂换行也能被正确编码（换行会把关键词截成两半）', () {
      final t = MapLauncher.tidy('河南省许昌市\n禹州市夏都街道');
      expect(t.contains('\n'), isFalse);
      final q = Uri.encodeComponent(t);
      expect(Uri.parse('androidamap://keywordNavi?keyword=$q')
          .queryParameters['keyword'], '河南省许昌市 禹州市夏都街道');
    });
  });

  group('调用方：不许再按 coordPrecise 降级', () {
    test('navigate 已经没有 precise 参数', () {
      final src = read('lib/services/map_launcher.dart');
      expect(src.contains('bool precise'), isFalse);
      expect(src.contains('precise:'), isFalse);
    });

    test('四个详情入口都直接把经纬度传进去', () {
      final spot = read('lib/screens/spot_detail_screen.dart');
      final shop = read('lib/screens/shop_detail_screen.dart');
      final ai = read('lib/screens/ai_spot_detail_screen.dart');
      final post = read('lib/screens/post_detail_screen.dart');
      expect(spot.contains('MapLauncher.navigate('), isTrue);
      expect(spot.contains('lat: s.lat'), isTrue);
      expect(shop.contains('lat: _s.lat'), isTrue);
      expect(ai.contains('lat: widget.spot.lat'), isTrue);
      expect(post.contains('MapLauncher.navigate('), isTrue);
    });

    test('详情页不再出现「导航会按地址搜索」这种旧说法', () {
      final spot = read('lib/screens/spot_detail_screen.dart');
      expect(spot.contains('导航会按地址搜索'), isFalse);
    });
  });
}
