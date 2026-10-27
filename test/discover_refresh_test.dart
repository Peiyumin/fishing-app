import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fishing_app/screens/discover_screen.dart';
import 'package:fishing_app/widgets/app_refresh.dart';
import 'package:fishing_app/widgets/waterfall_post_card.dart';

/// 发现页刷新的行为护栏
///
/// 用户录屏里的现象：在「推荐」上什么都没点，内容每 0.3~0.7 秒整个消失闪白
/// 一次，闪完还跳回顶部；切 tab 也一样闪。
///
/// 根因是 `_load()` 一进来就无条件 `_loading = true`，把内容区连同外层
/// `AppRefresh`（里面的 `RefreshIndicator`）一起换成一个小转圈：
///   · 列表被销毁 → 闪白 + 滚动位置归零，刚翻到的位置跳回顶部；
///   · `RefreshIndicator` 被销毁后立刻重建，手指还在屏幕上就会被再判成一次
///     下拉 → 又刷新 → 0.3~0.7 秒闪一次的自激循环；
///   · 「渔报 为您玩命加载…」提示条刚滑出就被销毁，从来没显示过。
///
/// ★ 这里用一个「第一次请求失败、之后永久挂起」的假 HttpClient：
///   第一次失败会让 fetchFeed 回落到演示数据（有卡片可看），
///   之后的刷新永远停在「加载中」，这样「刷新进行中」这一帧才抓得到。
///   直接 drag 触发在测试环境里不可靠，会变成假通过。
void main() {
  final client = _PhaseClient();

  setUpAll(() => HttpOverrides.global = _FakeOverrides(client));
  tearDownAll(() => HttpOverrides.global = null);
  setUp(() {
    client.calls = 0;
    client.hang = true;
    SharedPreferences.setMockInitialValues({});
  });

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: DiscoverScreen()));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
  }

  /// 是不是「整屏只有一个居中转圈」的状态
  bool fullscreenSpinner() {
    for (final e in find.byType(CircularProgressIndicator).evaluate()) {
      final box = e.renderObject;
      if (box is RenderBox && box.hasSize && box.size.width >= 8) return true;
    }
    return false;
  }

  testWidgets('首屏能出卡片（后面用例的前提）', (tester) async {
    await pump(tester);
    expect(find.byType(WaterfallPostCard), findsWidgets,
        reason: '首屏没数据，后面的用例就没有意义了');
  });

  testWidgets('刷新进行中：卡片不能消失，也不能整屏转圈', (tester) async {
    await pump(tester);
    expect(find.byType(WaterfallPostCard), findsWidgets);

    // 第二次请求会永久挂起，正好停在「刷新进行中」
    final refresh = tester.widget<AppRefresh>(find.byType(AppRefresh));
    unawaited(refresh.onRefresh());
    await tester.pump();

    expect(find.byType(WaterfallPostCard), findsWidgets,
        reason: '刷新一开始卡片就全没了 —— 这就是用户看到的闪白');
    expect(fullscreenSpinner(), isFalse,
        reason: '刷新时不该用整屏转圈顶掉列表');

    // 再推进几帧，仍然是卡片（旧写法会一直转圈直到请求回来）
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
    expect(find.byType(WaterfallPostCard), findsWidgets);
    expect(fullscreenSpinner(), isFalse);
  });

  testWidgets('切到热门再切回推荐：有缓存就直接显示，不再整屏转圈', (tester) async {
    client.hang = false; // 每个 tab 都能拿到演示数据
    await pump(tester);
    expect(find.byType(WaterfallPostCard), findsWidgets);

    await tester.tap(find.text('热门'));
    await tester.pump();
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
    expect(find.byType(WaterfallPostCard), findsWidgets);

    // 切回推荐：缓存里已有数据，第一帧就该是卡片
    await tester.tap(find.text('推荐'));
    await tester.pump();
    expect(find.byType(WaterfallPostCard), findsWidgets,
        reason: '切回已看过的 tab 又整块消失了');
    expect(fullscreenSpinner(), isFalse);
  });
}

/// 第一次 getUrl 立即失败（触发演示数据回落），之后按 [hang] 决定：
/// hang=true 时永久挂起（模拟慢网络，用于抓「刷新进行中」那一帧），
/// hang=false 时每次都失败（每个 tab 都能拿到演示数据）。
class _PhaseClient implements HttpClient {
  int calls = 0;
  bool hang = true;

  @override
  Future<HttpClientRequest> getUrl(Uri url) {
    calls++;
    if (!hang || calls == 1) {
      return Future<HttpClientRequest>.error(
          const SocketException('no network in test'));
    }
    return Completer<HttpClientRequest>().future; // 永不完成
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeOverrides extends HttpOverrides {
  _FakeOverrides(this.client);
  final _PhaseClient client;

  @override
  HttpClient createHttpClient(SecurityContext? context) => client;
}
