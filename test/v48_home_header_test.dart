// v2.1.84 首页顶栏回归护栏
//
// 对应需求（用户原话）：
//   「首页渔报标题下面不要分割线不要那一条白线，把渔报标题位置改到左上角，
//     把字体改大一点，字体样式气势磅礴，笔锋犀利点」
//
// 四条各自钉一条断言，每条都对着「旧写法会失败」写的：
//   ① 白线   —— 它来自 `AppBarTheme.shape` 的 1px 底边，不是 Divider
//   ② 位置   —— 以前 centerTitle: true + Stack 居中
//   ③ 字号   —— 以前 18
//   ④ 字体   —— 以前系统黑体 w700
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fishing_app/app_theme.dart';
import 'package:fishing_app/widgets/home_top_bar.dart';
import 'package:fishing_app/widgets/mode_tabs.dart';

/// pubspec.yaml `fonts:` 段声明的随包字体族（与 lib 代码里的 fontFamily 对齐）
Set<String> bundledFamilies() {
  final fams = <String>{};
  for (final l in File('pubspec.yaml').readAsLinesSync()) {
    final m = RegExp(r'''^\s*-\s*family:\s*["']?([A-Za-z0-9_ -]+)["']?\s*$''')
        .firstMatch(l);
    if (m != null) fams.add(m.group(1)!.trim());
  }
  return fams;
}

Widget wrap() => MaterialApp(
      theme: AppTheme.light,
      home: const Scaffold(appBar: HomeTopBar(), body: SizedBox.expand()),
    );

void main() {
  group('① 标题下面没有那条白线', () {
    testWidgets('AppBar 的 shape 四边都是 none（盖掉主题的 1px 底边）', (t) async {
      await t.pumpWidget(wrap());
      final bar = t.widget<AppBar>(find.byType(AppBar));

      // 前提：主题确实给所有二级页画了 1px 底边（否则这条测试没有意义）
      final themed = AppTheme.light.appBarTheme.shape as Border?;
      expect(themed?.bottom.width, 1,
          reason: '主题的 1px 收边线没有了？那「首页要盖掉它」这件事也得跟着改');

      expect(bar.shape, isA<Border>(),
          reason: '首页 AppBar 必须显式传 shape: Border()，'
              '否则会继承主题那条 1px 浅灰底边，在近黑顶栏上就是一条白线');
      final b = bar.shape as Border;
      expect(b.bottom.width, 0, reason: '底边还在画 → 标题下面会有一条白线');
      expect(b.top.width, 0);
      expect(b.left.width, 0);
      expect(b.right.width, 0);
    });

    testWidgets('顶栏内部没有自己再画一条 Divider / 1px 横线', (t) async {
      await t.pumpWidget(wrap());
      // 只看 AppBar 子树：页面别处的分割线（列表分隔等）不算
      expect(
        find.descendant(
            of: find.byType(AppBar), matching: find.byType(Divider)),
        findsNothing,
        reason: '白线的另一种来法：AppBar 里塞了 Divider',
      );
    });
  });

  group('②③④ 标题：左上角 / 字号加大 / 毛笔字体', () {
    testWidgets('「渔报」贴着左边，不是居中', (t) async {
      await t.pumpWidget(wrap());
      final r = t.getRect(find.text('渔报'));
      final w = t.getSize(find.byType(AppBar)).width;
      // 居中会落在 (w - 标题宽) / 2 ≈ 350 附近；左上角是 18 的 titleSpacing
      expect(r.left, lessThan(60),
          reason: '标题 left=${r.left}，说明还居中着（主题 centerTitle: true，'
              '必须在 AppBar 上显式写 false）');
      expect(r.left, greaterThan(8), reason: '贴边太近，titleSpacing 没了');
      // 右侧留白必须够：标题不能顶到铃铛下面
      expect(r.right, lessThan(w * 0.6));
    });

    testWidgets('字号 ≥ 32（旧版 18 → v2.1.84 30 → v2.1.85 34）', (t) async {
      await t.pumpWidget(wrap());
      final style = t.widget<Text>(find.text('渔报')).style!;
      expect(style.fontSize, greaterThanOrEqualTo(32),
          reason: '旧版 18pt，用户两次要求「改大一点」，毛笔字字面小，'
              '低于 32 气势出不来');
      expect(style.fontWeight, anyOf(isNull, FontWeight.w400),
          reason: '毛笔字体只有一个字重，写 w700 会被合成加粗（笔画糊成一团），'
              '用户还专门要求「笔画细一点」，更不能合成加粗');
      expect(style.color, Colors.white, reason: '近黑顶栏上必须是白字');
    });

    testWidgets('字体族是 pubspec 里声明过的随包毛笔字，且真的能加载', (t) async {
      await t.pumpWidget(wrap());
      final style = t.widget<Text>(find.text('渔报')).style!;

      expect(style.fontFamily, 'YuBaoBrush');
      expect(bundledFamilies(), contains(style.fontFamily),
          reason: 'fontFamily 必须在 pubspec.yaml 的 fonts: 里声明，'
              '否则 Flutter 静默回落系统字体（不报错，只是字不像毛笔）');

      // 字面量为 '渔报' 以外的字在这份子集里没有字形 —— 防止有人把标题
      // 换成「渔报 · 钓鱼社区」之类的多字文案，那几个字会变成另一种字体
      expect(t.widget<Text>(find.text('渔报')).data, '渔报');
    });
  });

  group('布局：铃铛在右、顶栏高度够放 30pt 毛笔字', () {
    testWidgets('铃铛靠右，且与标题不重叠', (t) async {
      await t.pumpWidget(wrap());
      final w = t.getSize(find.byType(AppBar)).width;
      final bell = t.getRect(find.byIcon(Icons.notifications_none));
      final title = t.getRect(find.text('渔报'));
      expect(bell.center.dx, greaterThan(w * 0.85));
      expect(bell.left, greaterThan(title.right));
    });

    testWidgets('preferredSize = 工具栏 + 分类条，标题垂直居中且不溢出', (t) async {
      await t.pumpWidget(wrap());
      const bar = HomeTopBar();
      // v2.1.86：标题下面多了一条钓法分类（台钓/路亚/钓场/海钓）
      expect(bar.preferredSize.height, HomeTopBar.barHeight + ModeTabs.height);
      final h = t.getSize(find.byType(AppBar)).height;
      expect(h, HomeTopBar.barHeight + ModeTabs.height);

      // 标题整体落在工具栏内部（上下各留一点），没有被裁
      final r = t.getRect(find.text('渔报'));
      final barRect = t.getRect(find.byType(AppBar));
      expect(r.top, greaterThan(barRect.top));
      expect(r.bottom, lessThan(barRect.bottom));
      // 30pt 的毛笔字 + 1.1 行高 ≈ 33 高，62 的栏里必须留得出上下各 10px
      expect(r.height, greaterThan(28));
    });
  });
}
