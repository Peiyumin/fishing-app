import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fishing_app/app_theme.dart';
import 'package:fishing_app/widgets/ui_kit.dart';

/// v2.1.59「全站视觉统一」的回归护栏
///
/// 这一版没有加功能，全是版式：顶栏从"一半黑一半白"统一成浅色、
/// 卡片圆角/分割线缩进/空状态/标签统一下来。这类改动最容易在后续
/// 迭代里被悄悄改回去（谁再写一个 `backgroundColor: Colors.white`
/// 或自己拼一套空状态），所以这里用测试钉住。
void main() {
  group('顶栏', () {
    test('主题就是浅色顶栏，只有一档标题样式', () {
      final ab = AppTheme.light.appBarTheme;
      expect(ab.backgroundColor, AppTheme.surface);
      expect(ab.foregroundColor, AppTheme.textPrimary);
      expect(ab.titleTextStyle, kAppBarTitle);
      expect(ab.elevation, 0);
      expect(ab.scrolledUnderElevation, 0);
      // 顶栏与内容用 1px 细线收边，不用阴影
      expect(ab.shape, isA<Border>());
    });

    test('页面不再自己写死顶栏底色/标题样式', () {
      // 允许的例外：沉浸页（相机、渔获 tab）用深色渐变 + 白前景
      final offenders = <String>[];
      for (final f in Directory('lib/screens').listSync().whereType<File>()) {
        if (!f.path.endsWith('.dart')) continue;
        final src = f.readAsStringSync();
        if (!src.contains('appBar: AppBar(')) continue;
        var i = 0;
        while (true) {
          i = src.indexOf('appBar: AppBar(', i);
          if (i < 0) break;
          final head = src.substring(i, i + 1200 > src.length ? src.length : i + 1200);
          final bodyAt = head.indexOf('body:');
          final part = bodyAt > 0 ? head.substring(0, bodyAt) : head;
          if (part.contains('backgroundColor: Colors.white')) {
            offenders.add('${f.path} → backgroundColor: Colors.white');
          }
          // 深色 Hero 顶栏（自己声明了白色前景）允许用大字号标题，
          // 其余页面的标题字号必须来自 kAppBarTitle
          final isDarkHero = part.contains('foregroundColor: Colors.white');
          if (!isDarkHero &&
              (part.contains('fontSize: 15') || part.contains('fontSize: 18'))) {
            offenders.add('${f.path} → 自写顶栏字号');
          }
          i += 10;
        }
      }
      expect(offenders, isEmpty,
          reason: '顶栏样式统一交给 AppBarTheme；要改只看 kAppBarTitle。'
              '发现问题：${offenders.join('、')}');
    });
  });

  group('空状态', () {
    testWidgets('渲染出图标 / 标题 / 说明 / 按钮四件', (tester) async {
      var tapped = false;
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: Center(
            child: UiEmptyState(
              icon: Icons.inbox_outlined,
              title: '还没有内容',
              desc: '下拉刷新试试',
              actionLabel: '去逛逛',
              onAction: () => tapped = true,
            ),
          ),
        ),
      ));
      expect(find.byIcon(Icons.inbox_outlined), findsOneWidget);
      expect(find.text('还没有内容'), findsOneWidget);
      expect(find.text('下拉刷新试试'), findsOneWidget);

      // 标题比说明重（层级：标题 w600 / 说明常规 + 次级灰）
      final title = tester.widget<Text>(find.text('还没有内容'));
      final desc = tester.widget<Text>(find.text('下拉刷新试试'));
      expect(title.style?.fontWeight, FontWeight.w600);
      expect(desc.style?.color, AppTheme.textSecondary);

      await tester.tap(find.text('去逛逛'));
      expect(tapped, isTrue);
    });

    testWidgets('没有说明和按钮时不留空位', (tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        home: const Scaffold(
          body: Center(
            child: UiEmptyState(icon: Icons.inbox_outlined, title: '空空如也'),
          ),
        ),
      ));
      expect(find.byType(ElevatedButton), findsNothing);
      expect(find.byType(Text), findsOneWidget);
    });

    testWidgets('compact 版更矮，能塞进卡片内部', (tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 340,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  UiCard(
                    padding: EdgeInsets.zero,
                    child: const UiEmptyState(
                      icon: Icons.receipt_long_outlined,
                      title: '暂无收支记录',
                      compact: true,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ));
      expect(tester.takeException(), isNull);
      final h = tester.getSize(find.byType(UiEmptyState)).height;
      expect(h, lessThan(160), reason: 'compact 版要能塞进一张普通卡片');
    });
  });

  group('标签', () {
    testWidgets('四种语气各用各的底色，中性是浅灰', (tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        home: const Scaffold(
          body: Column(children: [
            UiTag('推荐', tone: UiTagTone.accent),
            UiTag('路亚'),
            UiTag('热门', tone: UiTagTone.solid),
            UiTag('涨价', tone: UiTagTone.warn),
          ]),
        ),
      ));
      final boxes = tester
          .widgetList<Container>(find.descendant(
              of: find.byType(UiTag), matching: find.byType(Container)))
          .toList();
      final colors = boxes
          .map((c) => (c.decoration as BoxDecoration?)?.color)
          .whereType<Color>()
          .toList();
      expect(colors, containsAll(<Color>[
        AppTheme.accentLight,
        AppTheme.primarySoft,
        AppTheme.primary,
        AppTheme.warningLight,
      ]));
    });
  });
}
