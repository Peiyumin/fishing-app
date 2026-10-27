import 'package:fishing_app/models/signin.dart';
import 'package:fishing_app/screens/signin_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 每日任务列表的三态标识（v2.1.27）
///
/// 用户反馈两点：
///   ① 完成任务后「缺少任务标识」——只有按钮文字变了，扫列表看不出哪行做完了；
///   ② 领取按钮上写着「领取 +2」，加号后面的积分是多余的（奖励值在副标题已有）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    SigninScreen.debugStatus = const SigninStatus(
      signedToday: true,
      streak: 4,
      dayIndex: 5,
      points: 1034,
      balance: 3000,
      tasks: [
        // 已完成、还没领 → 应有「已完成」标识 + 按钮「领取」
        DailyTask(
          key: 'checkin',
          title: '今日签到打卡',
          desc: '每天签到 1 次即可领取',
          points: 2,
          icon: 'check',
          done: true,
        ),
        // 已完成且已领取 → 按钮「已领取」
        DailyTask(
          key: 'publish_catch',
          title: '发布 1 条渔获帖',
          desc: '每日发布 1 条渔获贴',
          points: 5,
          icon: 'fish',
          done: true,
          claimed: true,
        ),
        // 未完成 → 「去完成」，不应带「已完成」标识
        DailyTask(
          key: 'comment_2',
          title: '发布 2 条评论',
          desc: '每日发布任意 2 条评论',
          points: 3,
          icon: 'comment',
          target: 2,
          progress: 1,
        ),
      ],
    );
  });

  tearDown(() => SigninScreen.debugStatus = null);

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: SigninScreen()));
    await tester.pump();
  }

  testWidgets('已完成待领取的任务显示「已完成」标识', (tester) async {
    await pump(tester);
    expect(find.text('已完成'), findsOneWidget);
  });

  testWidgets('已领取 / 未完成的任务不显示「已完成」标识', (tester) async {
    await pump(tester);
    // 三条任务只应出现一次（只有「签到打卡」是 done 且未 claimed）
    expect(find.text('已完成'), findsOneWidget);
    expect(find.text('已领取'), findsOneWidget);
    expect(find.text('去完成'), findsOneWidget);
  });

  testWidgets('领取按钮只写「领取」，不再带 +N 积分', (tester) async {
    await pump(tester);
    expect(find.text('领取'), findsOneWidget);
    expect(find.text('领取 +2'), findsNothing);
  });

  testWidgets('积分值仍在副标题展示（奖励信息不丢）', (tester) async {
    await pump(tester);
    expect(find.text('+2'), findsOneWidget);
    expect(find.text('+5'), findsOneWidget);
    expect(find.text('+3'), findsOneWidget);
  });
}
