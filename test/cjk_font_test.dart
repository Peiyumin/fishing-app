import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fishing_app/app_theme.dart';
import 'package:fishing_app/utils/text_safe.dart';

/// 乱码 / 小方块（tofu）回归护栏
///
/// 这三类东西都会让文字渲染成方块，用户看到的就是「乱码」：
///   ① 手写 `fontFamilyFallback` —— 列了某个平台才有的字体名，
///      在别家 ROM 上整条解析失败 → 全站中文 + emoji 全是方块
///   ② 半截字符（孤立代理项）—— `substring` 切碎 emoji 的产物
///   ③ U+FFFD（UTF-8 解码失败的替换符）—— 字形本身就是一个方块
///
/// 每条断言都对着「旧写法会失败」写的，不是空跑。

/// 判断字符串里有没有孤立代理项（= 被切断的 emoji / 生僻字）
bool _hasLoneSurrogate(String s) {
  for (var i = 0; i < s.length; i++) {
    final c = s.codeUnitAt(i);
    if (c >= 0xD800 && c <= 0xDBFF) {
      if (i + 1 >= s.length) return true;
      final n = s.codeUnitAt(i + 1);
      if (n < 0xDC00 || n > 0xDFFF) return true;
    } else if (c >= 0xDC00 && c <= 0xDFFF) {
      return true;
    }
  }
  return false;
}

/// 取源码里「非注释」的行
List<String> _codeLines(String path) {
  return File(path)
      .readAsLinesSync()
      .map((l) => l.trim())
      .where((l) => !l.startsWith('//') && !l.startsWith('///'))
      .toList();
}

/// pubspec.yaml `fonts:` 段里声明的**随包字体族**
///
/// 为什么要单独放行这一类：
///   `fontFamily:` 之所以被禁，是因为写的是**系统字体名**（'PingFang SC'、
///   'Microsoft YaHei'）—— 换个 ROM 就没有这个字体，整段文字退到
///   last-resort 字体，汉字全变方块。
///   而 `fonts:` 里声明的字体是 **asset，跟着安装包一起走**，
///   任何设备上都能解析到，不存在「这台机器没有」的问题。
///   所以判据从「出现 fontFamily 就算违规」收紧为
///   「fontFamily 的**值**必须是 pubspec 声明过的随包字体」。
Set<String> _bundledFamilies() {
  final fams = <String>{};
  for (final l in File('pubspec.yaml').readAsLinesSync()) {
    // 字体段长这样：  - family: YuBaoBrush
    final m = RegExp(r'''^\s*-\s*family:\s*["']?([A-Za-z0-9_ -]+)["']?\s*$''')
        .firstMatch(l);
    if (m != null) fams.add(m.group(1)!.trim());
  }
  return fams;
}

void main() {
  group('① 字体：不许手写中文回退栈', () {
    /// ThemeData 的 fontFamily / fontFamilyFallback 会被下发到
    /// textTheme 的每个 TextStyle 上，所以从 textTheme 侧取证。
    List<TextStyle?> _allStyles(TextTheme t) => <TextStyle?>[
          t.displayLarge,
          t.displayMedium,
          t.displaySmall,
          t.headlineLarge,
          t.headlineMedium,
          t.headlineSmall,
          t.titleLarge,
          t.titleMedium,
          t.titleSmall,
          t.bodyLarge,
          t.bodyMedium,
          t.bodySmall,
          t.labelLarge,
          t.labelMedium,
          t.labelSmall,
        ];

    test('textTheme 里不出现手写的中文回退栈', () {
      // 旧代码：fontFamilyFallback: cjkFallback
      // 那个列表里 PingFang SC 只有 iOS 有、Microsoft YaHei 只有 Windows 有、
      // Noto Sans SC 在多数 Android 上不是这个名字。三个都解析不到时，
      // Flutter 退到 last-resort 字体 → 每个汉字都是空心方块。
      //
      // ★ 只断言「这几个名字不许出现」，不断言 fontFamily == null：
      //   Material 的 Typography 本来就会给每个样式标 'Roboto'，
      //   那是 Flutter 自带元数据，不是我们写死的。
      const banned = {
        'PingFang SC',
        'Hiragino Sans GB',
        'Microsoft YaHei',
        'Noto Sans CJK SC',
        'Noto Sans SC',
      };
      for (final s in _allStyles(AppTheme.light.textTheme)) {
        final fb = s?.fontFamilyFallback;
        expect(banned.contains(s?.fontFamily), isFalse,
            reason: 'textTheme 里写死了 ${s?.fontFamily}，'
                '别的平台没有这个字体 → 中文变方块');
        for (final f in fb ?? const <String>[]) {
          expect(banned.contains(f), isFalse,
              reason: 'fontFamilyFallback 里出现了 $f —— '
                  '手写中文回退栈会切断系统自带的 emoji / 中日韩兜底');
        }
      }
    });

    test('文案样式里也不写死 fontFamily（随包字体除外）', () {
      final root = Directory('lib');
      final bundled = _bundledFamilies();
      final hits = <String>[];
      // 只认字面量：`fontFamily: 'YuBaoBrush'`
      final literal =
          RegExp(r'''\bfontFamily\s*:\s*["']([^"']+)["']''');
      final anyUse = RegExp(r'\bfontFamily\s*:');
      final fallback = RegExp(r'\bfontFamilyFallback\s*:');
      for (final f in root.listSync(recursive: true)) {
        if (f is! File || !f.path.endsWith('.dart')) continue;
        for (final l in _codeLines(f.path)) {
          // ① 回退栈一律禁：无论写的是系统字体还是随包字体，
          //    手写回退栈都会切断系统自带的 emoji / 生僻字兜底
          if (fallback.hasMatch(l)) {
            hits.add('${f.path}: $l  ← 不许手写 fontFamilyFallback');
            continue;
          }
          if (!anyUse.hasMatch(l)) continue;
          final m = literal.firstMatch(l);
          if (m == null) {
            hits.add('${f.path}: $l  ← fontFamily 的值不是字面量，无法核对');
          } else if (!bundled.contains(m.group(1)!)) {
            hits.add('${f.path}: $l  ← 「${m.group(1)}」不在 pubspec 的 fonts: 里'
                '（系统字体名换台机器就没有 → 汉字变方块）');
          }
        }
      }
      expect(hits, isEmpty,
          reason: '这些地方写死了字体族，真机没有该字体就会显示方块：\n'
              '${hits.join('\n')}\n'
              '唯一允许的写法：用 pubspec.yaml `fonts:` 里声明的随包字体族'
              '（目前是 YuBaoBrush，只有「渔报」两字的子集）。');
    });

    test('随包字体真的在包里：每个 family 的 asset 都存在且非空', () {
      final fams = _bundledFamilies();
      expect(fams, isNotEmpty,
          reason: 'pubspec 里一个 fonts: family 都没解析到 —— '
              '正则和 pubspec 结构脱节了');
      // 逐条核对 asset 路径存在、字节数 > 0（空文件 = 打进去也画不出字）
      String? current;
      for (final raw in File('pubspec.yaml').readAsLinesSync()) {
        final l = raw.trim();
        final fm = RegExp(r'''^-\s*family:\s*["']?([A-Za-z0-9_ -]+)''')
            .firstMatch(l);
        if (fm != null) {
          current = fm.group(1)!.trim();
          continue;
        }
        final am = RegExp(r'^-\s*asset:\s*(\S+)').firstMatch(l);
        if (am == null || current == null) continue;
        final path = am.group(1)!.replaceAll(RegExp(r'''["']'''), '');
        final f = File(path);
        expect(f.existsSync(), isTrue, reason: '$current 的 asset 不存在：$path');
        expect(f.lengthSync(), greaterThan(0),
            reason: '$current 的 asset 是空文件：$path');
      }
    });
  });

  group('② 截断：不许切碎 emoji', () {
    test('旧写法 substring 确实会切出半个 emoji（证明问题真实存在）', () {
      const name = '钓鱼佬🎣';
      final broken = name.substring(0, 4); // 切在 🎣 的高位代理之后
      expect(_hasLoneSurrogate(broken), isTrue,
          reason: '如果这条都不成立，说明测试字符串选错了');
    });

    test('clipGrapheme 按字素簇截断，不产生孤立代理项', () {
      const name = '钓鱼佬🎣';
      final out = clipGrapheme(name, 3);
      expect(out, '钓鱼佬…');
      expect(_hasLoneSurrogate(out), isFalse);
    });

    test('clipGrapheme 不超长时原样返回', () {
      expect(clipGrapheme('许昌·禹州市', 40), '许昌·禹州市');
      expect(clipGrapheme('', 10), '');
    });

    test('cutGrapheme 不加省略号', () {
      expect(cutGrapheme('一二三四五', 3), '一二三');
    });

    test('组合 emoji（ZWJ 系列）算一个字素簇', () {
      const family = '👨‍👩‍👧';
      expect(clipGrapheme(family, 1), family,
          reason: 'ZWJ 家庭 emoji 是 1 个字素簇，不该被当成 5 个');
    });
  });

  group('③ 净化：清掉解码残留', () {
    test('U+FFFD 替换字符被清掉', () {
      expect(safeText('禹州\uFFFD'), '禹州');
      expect(safeText('禹\uFFFD\uFFFD州'), '禹州');
    });

    test('孤立代理项被清掉，合法 emoji 保留', () {
      expect(safeText('钓鱼佬\uD83C'), '钓鱼佬');
      expect(safeText('\uDFA3钓鱼'), '钓鱼');
      // 合法代理对必须原样保留，不能「为了清方块把 emoji 全删了」
      expect(safeText('钓鱼佬🎣'), '钓鱼佬🎣');
      expect(safeText('👨‍👩‍👧一家人'), '👨‍👩‍👧一家人');
    });

    test('控制字符被清掉，换行保留', () {
      expect(safeText('第一行\n第二行'), '第一行\n第二行');
      expect(safeText('坏\u0000字'), '坏字');
      expect(safeText('响铃\u0007'), '响铃');
    });

    test('null / 空串 / 非字符串都安全', () {
      expect(safeText(null), '');
      expect(safeText(''), '');
      expect(safeText(123), '123');
    });

    test('sanitizeDeep 递归清洗整棵 JSON', () {
      final raw = <String, dynamic>{
        'nickname': '老王\uFFFD',
        'title': '钓鱼佬\uD83C',
        'ok_one': '🎣',
        'list': ['禹州\uFFFD', 1, true],
        'nested': {'address': '许昌\u0000市'},
      };
      final out = sanitizeDeep(raw) as Map<String, dynamic>;
      expect(out['nickname'], '老王');
      expect(out['title'], '钓鱼佬');
      expect(out['ok_one'], '🎣');
      expect((out['list'] as List)[0], '禹州');
      expect((out['list'] as List)[1], 1);
      expect((out['nested'] as Map)['address'], '许昌市');
    });
  });

  group('④ 地图：不许用 text-field（没 glyphs 服务 = 方块）', () {
    test('样式与图层里不出现 text-field / textField', () {
      final bad = <String>[];
      for (final p in [
        'lib/screens/spot_map_gl.dart',
        'lib/screens/spot_map_screen.dart',
      ]) {
        if (!File(p).existsSync()) continue;
        final lines = _codeLines(p);
        for (var i = 0; i < lines.length; i++) {
          final l = lines[i];
          if (RegExp(r"'text-field'|\btextField\s*:").hasMatch(l)) {
            bad.add('$p: ${l.trim()}');
          }
        }
      }
      expect(bad, isEmpty,
          reason: 'MapLibre 渲染 text-field 必须从样式的 glyphs 拉字形。'
              '本项目是纯栅格底图，没有 glyphs 服务，文字只能画成方块。\n'
              '${bad.join('\n')}');
    });
  });
}
