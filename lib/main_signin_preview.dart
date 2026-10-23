import 'package:flutter/material.dart';

import 'app_theme.dart';
import 'models/signin.dart';
import 'screens/signin_screen.dart';

/// 仅用于本地 web 预览 / 截图验收的入口，不参与正式包。
///
/// 用一份"混合状态"的假数据把签到页渲染出来，专门看三件事：
///   ① 今天这一格（以前白底白字，看起来整格是空的）
///   ② 已完成待领取 / 已领取 / 去完成 三种按钮形态
///   ③ 5 条任务 + 规则卡在小屏下有没有溢出
void main() {
  final rewards = List<SigninReward>.generate(
    7,
    (i) => SigninReward(points: i == 6 ? 30 : (i >= 4 ? 15 : (i >= 2 ? 10 : 5))),
  );

  SigninScreen.debugStatus = SigninStatus(
    signedToday: false,
    streak: 2,
    total: 9,
    dayIndex: 3,
    points: 128,
    balance: 12.5,
    pointsName: '积分',
    rules: '每日可签到 1 次；连续签到 7 天为一个周期，中断后从第 1 天重新开始。',
    rewards: rewards,
    tasks: const [
      DailyTask(
          key: 'publish_catch',
          title: '发布 1 条渔获',
          desc: '每日发布 1 条渔获贴',
          points: 5,
          icon: 'fish',
          progress: 1,
          done: true),
      DailyTask(
          key: 'publish_post',
          title: '发布任意类型帖',
          desc: '每日首次发布帖子',
          points: 3,
          icon: 'edit',
          progress: 1,
          done: true,
          claimed: true),
      DailyTask(
          key: 'comment_2',
          title: '发布 2 条评论',
          desc: '每日发布任意 2 条评论',
          points: 3,
          icon: 'comment',
          target: 2,
          progress: 1),
      DailyTask(
          key: 'follow_2',
          title: '关注 2 名钓友',
          desc: '每日新关注 2 名钓友',
          points: 3,
          icon: 'follow',
          target: 2),
      DailyTask(
          key: 'checkin',
          title: '今日签到打卡',
          desc: '每天签到 1 次即可领取',
          points: 2,
          icon: 'check'),
    ],
  );

  runApp(MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: AppTheme.light,
    home: const SigninScreen(),
  ));
}
