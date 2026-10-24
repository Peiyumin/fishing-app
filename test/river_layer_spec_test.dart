import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 河道图层规格回归（v2.1.22）
///
/// 背景：用户连续截图反馈「浅蓝水面下面压着一根很粗的蓝色」。
/// 根因是 `hydro-river-line` 这一层在 z14 画 16px、z17 画 30px 的实心线，
/// 而 OSM 里 river/canal 在 z11 以上本来就有水面多边形，
/// 水面（0.5 透明的浅蓝）被一条 30px 不透明的线劈成两半。
///
/// 修法是按 class 拆层：
///   · hydro-river-major —— 河/运河，只在低缩放（z6~10）画，撑出河道走向；
///   · hydro-river-line  —— 溪流/沟渠/排水沟，无水面面，细线，全缩放保留。
///
/// 这几条断言不是"文档"，是防回归闸门：谁再把宽线档位加回来，
/// 这个测试会直接红。地图层是 Dart 数据在 build 期拼出来的，
/// 没有可断言的运行时对象，所以这里对源码做结构断言。
void main() {
  late String src;

  setUpAll(() {
    final f = File('lib/screens/spot_map_gl.dart');
    expect(f.existsSync(), isTrue, reason: '找不到 spot_map_gl.dart');
    src = f.readAsStringSync();
  });

  /// 截出某个 `_safeLayer('hydro', '<id>', ... )` 的完整实参片段
  ///
  /// 注意不能直接 `indexOf("'<id>'")`：图层 id 在 _bizLayers 清单里先出现一次，
  /// 而且 `_safeLayer(` 在 id **前面**，必须用正则锚住 `_safeLayer('hydro', '<id>'`
  /// 这一对，再截到下一个 `_safeLayer(` 为止。
  String layerBlock(String id) {
    final m = RegExp("_safeLayer\\(\\s*'hydro',\\s*'$id'").firstMatch(src);
    expect(m, isNotNull, reason: '找不到 _safeLayer 定义：$id（图层被误删？）');
    var end = src.indexOf('_safeLayer(', m!.end);
    if (end < 0) end = src.length;
    return src.substring(m.start, end);
  }

  group('大河中心线只在低缩放出现', () {
    test('hydro-river-major 必须设置 maxzoom 且 <= 11', () {
      final block = layerBlock('hydro-river-major');
      expect(block.contains('maxzoom:'), isTrue,
          reason: '没有 maxzoom 就意味着高缩放会继续画粗线 —— 正是用户截图里的粗蓝带');
      final m = RegExp(r'maxzoom:\s*([0-9.]+)').firstMatch(block);
      expect(m, isNotNull, reason: 'maxzoom 必须是数字字面量');
      expect(double.parse(m!.group(1)!), lessThanOrEqualTo(11.0),
          reason: 'z11 起水面多边形已经能表达河道宽度，粗线必须退场');
    });

    test('hydro-river-major 只画 river / canal', () {
      final block = layerBlock('hydro-river-major');
      expect(block.contains('river'), isTrue);
      expect(block.contains('canal'), isTrue);
      // 溪流不该进这一层（它有自己的细线层）
      expect(block.contains("'stream'"), isFalse,
          reason: 'stream 属于 hydro-river-line，混进来会让窄河也变粗');
    });
  });

  group('窄河线必须细', () {
    test('hydro-river-line 只画 stream / ditch / drain', () {
      final block = layerBlock('hydro-river-line');
      for (final cls in ['stream', 'ditch', 'drain']) {
        expect(block.contains("'$cls'"), isTrue,
            reason: '窄河层必须覆盖 class=$cls（OSM 里它们通常没有水面多边形）');
      }
      expect(block.contains("'river'"), isFalse,
          reason: 'river 必须走 hydro-river-major，否则又会在水面上画粗线');
    });

    test('hydro-river-line 的宽度全部 <= 2px', () {
      final block = layerBlock('hydro-river-line');
      final nums = RegExp(r'[0-9]+\.[0-9]+')
          .allMatches(block)
          .map((m) => double.parse(m.group(0)!))
          .where((v) => v > 2.0)
          .toList();
      expect(nums, isEmpty,
          reason: '窄河层出现了 > 2px 的宽度档（$nums）：它会盖在浅蓝水面上变成粗蓝带');
    });
  });

  group('本地兜底河流也必须是细线', () {
    test('rivers-line 不再有 16 / 30 这种巨值宽度', () {
      final idx = src.indexOf("'rivers-line'");
      expect(idx, greaterThan(0));
      final block = src.substring(idx, idx + 700);
      final wide = RegExp(r'(1[2-9]|[2-9][0-9])\.[0-9]')
          .allMatches(block)
          .map((m) => m.group(0)!)
          .toList();
      expect(wide, isEmpty,
          reason: '本地河流线出现了宽档 $wide —— 它会在没有水面填充时画成一根粗色块');
    });

    test('图层清单里包含新增的 hydro-river-major', () {
      final i = src.indexOf('_bizLayers');
      expect(i, greaterThan(0));
      final block = src.substring(i, i + 1400);
      expect(block.contains("'hydro-river-major'"), isTrue,
          reason: '新图层必须进 _bizLayers，否则「加层回读校验」会认为它没加上');
    });
  });
}
