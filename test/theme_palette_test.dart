// 全局配色护栏（v2.1.36「所有页面统一配色」）
//
// 为什么需要一条**扫源码**的测试：
//   配色不统一不是某一次改错，而是每次加页面时"顺手写死一个颜色"累积出来的。
//   这次统一前后对比：硬编码颜色 239 处 / 164 个不同值 → 收敛到 21 个，
//   其中一半是插画和水印的颜料。靠人眼 review 抓不住 —— 谁也不会为了
//   `#1677FF` 和 `#46A0FB` 差多少去逐行看 diff。
//
// 三条规矩：
//   ① 色板外的颜色只允许出现在白名单文件里（插画 / 照片 / 第三方品牌色）；
//   ② 纯黑、纯白（含 alpha 变体）随时可以用 —— 它们是中性值，不是"色相"；
//   ③ maplibre 只吃 '#RRGGBB' 字符串，spot_map_gl 的 _Hex 必须逐条等于 AppTheme。
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fishing_app/app_theme.dart';

/// 允许出现任意颜色的文件（每条都有理由，不是"懒得改"）
const _paintWhitelist = <String>{
  // 色板本体
  'lib/app_theme.dart',
  // 鱼的手绘插画（鱼身花纹、鳞片高光）—— 不是 UI 色，按色板改会让鱼变塑料
  'lib/widgets/fish_art.dart',
  'lib/widgets/fish_top_view.dart',
  // 池塘场景：水体、水草、岸线的层次色
  'lib/screens/pond_screen.dart',
  // 第三方导航 App 的品牌色（高德蓝/微信绿/苹果蓝），用户靠颜色认 App
  'lib/services/map_launcher.dart',
  // 首页样张预览脚本，不进产品流程
  'lib/main_stamp_preview.dart',
  // 启动页：底色是设计稿（渔报海报）本身，胶囊由 Flutter 重绘以承载进度，
  // 重绘用的青绿/黄绿是从底图上取样得到的，必须和图片严丝合缝 ——
  // 换成 AppTheme 的 accent(#C6FF3D) 会和底图的鱼身/水波纹对不上。
  // 这几个值集中在 `_SplashColors` 里，只服务于这一张图。
  'lib/screens/startup/splash_screen.dart',
};

/// 色板里所有可用的 RGB（不含 alpha）
Map<String, Color> get _palette => {
      'primary': AppTheme.primary,
      'primaryLight': AppTheme.primaryLight,
      'primarySoft': AppTheme.primarySoft,
      'primaryBorder': AppTheme.primaryBorder,
      'accent': AppTheme.accent,
      'accentDark': AppTheme.accentDark,
      'accentLight': AppTheme.accentLight,
      'accentMid': AppTheme.accentMid,
      'water': AppTheme.water,
      'waterDeep': AppTheme.waterDeep,
      'star': AppTheme.star,
      'starLight': AppTheme.starLight,
      'starDark': AppTheme.starDark,
      'skyLight': AppTheme.skyLight,
      'sky': AppTheme.sky,
      'skyDeep': AppTheme.skyDeep,
      'danger': AppTheme.danger,
      'dangerDark': AppTheme.dangerDark,
      'dangerLight': AppTheme.dangerLight,
      'warning': AppTheme.warning,
      'warningLight': AppTheme.warningLight,
      'violet': AppTheme.violet,
      'background': AppTheme.background,
      'surface': AppTheme.surface,
      'textPrimary': AppTheme.textPrimary,
      'textSecondary': AppTheme.textSecondary,
      'textTertiary': AppTheme.textTertiary,
      'divider': AppTheme.divider,
      'border': AppTheme.border,
      'inkBg': AppTheme.inkBg,
      'inkSurface': AppTheme.inkSurface,
      'inkSurfaceAlt': AppTheme.inkSurfaceAlt,
      'inkLine': AppTheme.inkLine,
      'inkHead': AppTheme.inkHead,
      'inkText': AppTheme.inkText,
      'inkMuted': AppTheme.inkMuted,
      'headerGrad1': Color(0xFF161B22),
      'brandGrad2': Color(0xFF1D242E),
      'accentGrad2': Color(0xFFA8E52B),
    };

/// 取 RGB 三元组（丢掉 alpha）
(int, int, int) _rgb(Color c) {
  final v = c.value;
  return ((v >> 16) & 0xFF, (v >> 8) & 0xFF, v & 0xFF);
}

String _hex(Color c) => c.value.toRadixString(16).substring(2).toUpperCase();

void main() {
  test('UI 代码里不再出现色板外的硬编码颜色', () {
    final allowed = _palette.values.map(_rgb).toSet();
    final offenders = <String>[];
    final re = RegExp(r'Color\(0x([0-9A-Fa-f]{8})\)');

    for (final f in Directory('lib').listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart')) continue;
      final p = f.path.replaceAll('\\', '/');
      if (_paintWhitelist.contains(p)) continue;

      final lines = f.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        for (final m in re.allMatches(lines[i])) {
          final hex = m.group(1)!.toUpperCase();
          final rgb = (
            int.parse(hex.substring(2, 4), radix: 16),
            int.parse(hex.substring(4, 6), radix: 16),
            int.parse(hex.substring(6, 8), radix: 16),
          );
          final isNeutral = (rgb.$1 == rgb.$2 && rgb.$2 == rgb.$3) ||
              (rgb.$1 == 255 && rgb.$2 == 255 && rgb.$3 == 255) ||
              (rgb.$1 == 0 && rgb.$2 == 0 && rgb.$3 == 0);
          if (isNeutral || allowed.contains(rgb)) continue;
          offenders.add('$p:${i + 1}  #${hex.substring(2)}  '
              '${lines[i].trim()}');
        }
      }
    }

    expect(offenders, isEmpty,
        reason: '这些颜色不在 AppTheme 色板里。改法二选一：\n'
            '  · 换成语义 token（如 AppTheme.water / textSecondary）\n'
            '  · 如果确实是插画或第三方品牌色，把文件加进 _paintWhitelist 并写清理由\n'
            '命中：\n${offenders.join('\n')}');
  });

  test('地图图层的十六进制色板与 AppTheme 逐条一致', () {
    // maplibre 的图层属性写在 const 里，只能放 '#RRGGBB' 字符串，
    // 没法直接引用 Color —— 所以只能靠这条测试把它们钉在一起，
    // 否则以后调色板，地图上的水和 App 的水又变成两个蓝。
    final src = File('lib/screens/spot_map_gl.dart').readAsStringSync();
    final re = RegExp(r"static const (\w+) = '#([0-9A-Fa-f]{6})';");
    final found = <String, String>{
      for (final m in re.allMatches(src)) m.group(1)!: m.group(2)!.toUpperCase()
    };

    expect(found, isNotEmpty, reason: '没解析到 _Hex 常量，正则或代码结构变了');

    final expected = {
      'background': _hex(AppTheme.background),
      'water': _hex(AppTheme.water),
      'waterDeep': _hex(AppTheme.waterDeep),
      'danger': _hex(AppTheme.danger),
      'dangerDark': _hex(AppTheme.dangerDark),
      'accent': _hex(AppTheme.accent),
      'white': 'FFFFFF',
    };

    for (final e in expected.entries) {
      expect(found[e.key], e.value,
          reason: '地图色 _Hex.${e.key} 与 AppTheme 不一致'
              '（地图 ${found[e.key]} vs 色板 ${e.value}）');
    }
  });

  test('色板只允许 5 个色相族（黑灰 / 黄绿 / 蓝 / 红 / 琥珀）', () {
    // 这一条不是数"有几个彩色"，而是看**色相**：
    //   · 黄绿 60~100°（accent 系）
    //   · 蓝   185~240°（water / sky 系）
    //   · 红   335~15°（danger 系，跨 0° 两侧）
    //   · 琥珀  18~55°（star / warning 系）
    //   再加一个「黑灰」豁免（饱和度 <15%）。
    // 一旦有人往色板里加个紫色（原来雷暴图标那个 #8E7CC3，色相 251°）、
    // 或者加个绿（池塘那种 #1E6B52，色相 150°），这里立刻会红。
    const ranges = <(double, double)>[
      (60, 100),
      (185, 240),
      (335, 360),
      (0, 15),
      (18, 55),
    ];

    final bad = <String>[];
    _palette.forEach((name, c) {
      final hsl = HSLColor.fromColor(c);
      // 近黑/近白/纯灰不参与色相判定：它们的色相是算出来的噪声
      if (hsl.saturation < .15 || hsl.lightness < .10 || hsl.lightness > .95) {
        return;
      }
      final hue = hsl.hue;
      final ok = ranges.any((r) => hue >= r.$1 && hue <= r.$2);
      if (!ok) {
        bad.add('$name  #${_hex(c)}  hue=${hue.toStringAsFixed(0)}°  '
            '(s=${(hsl.saturation * 100).round()}% l=${(hsl.lightness * 100).round()}%)');
      }
    });

    expect(bad, isEmpty,
        reason: '色板里出现了色相族以外的颜色：\n${bad.join('\n')}\n'
            '允许的只有：黄绿 60~100°、蓝 185~240°、红 335~15°、琥珀 18~55°、'
            '以及无彩色的黑灰。');
  });

  test('地图以外不许用 #RRGGBB 字符串写死颜色', () {
    // 地图那套是因为 maplibre 只吃字符串，其它地方没有理由这么写。
    // 一旦有人在别的页面写 '#1677FF'，色板护栏（只看 Color(0x) ）是抓不到的。
    final re = RegExp(r"'#[0-9A-Fa-f]{6}'");
    final offenders = <String>[];
    for (final f in Directory('lib').listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart')) continue;
      final p = f.path.replaceAll('\\', '/');
      if (p == 'lib/screens/spot_map_gl.dart') continue;
      if (_paintWhitelist.contains(p)) continue;
      final lines = f.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (re.hasMatch(lines[i])) {
          offenders.add('$p:${i + 1}  ${lines[i].trim()}');
        }
      }
    }
    expect(offenders, isEmpty,
        reason: '用十六进制字符串写死颜色只有地图图层需要（maplibre 限制），'
            '其它地方请用 AppTheme token：\n${offenders.join('\n')}');
  });
}
