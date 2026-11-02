import 'dart:io' show Platform;

import 'package:flutter/material.dart';

import '../app_theme.dart';

/// 「连不上服务器」时给用户的分平台修复步骤。
///
/// 为什么单独抽出来：权限引导页和登录页都要给这套指引，
/// 两处各写一份必然走样（历史上「连不上」的文案就在两个页面各说过一套，
/// 一个说「网络异常」一个说「检查网络」，用户被指去换 WiFi 白折腾）。
///
/// 步骤必须**具体到菜单路径**。iOS 的「无线数据」开关根本不在 App 自己的
/// 设置页里，写「请检查网络设置」等于什么都没说。
List<String> netFixSteps() {
  if (Platform.isIOS) {
    return const [
      '设置 → 渔报 → 无线数据 → 选「无线局域网与蜂窝网络」',
      '也可以走 设置 → 蜂窝网络 → 渔报，把开关打开',
      '如果开了 VPN / 代理，先关掉再试（本站是 8801 非标准端口，容易被拦）',
      '换一个网络再检测：WiFi 与移动数据互换',
    ];
  }
  return const [
    '设置 → 应用 → 渔报 → 流量使用情况 → 允许后台数据',
    '关掉「流量节省程序」或安全软件对渔报的联网限制',
    '换一个网络再检测：WiFi 与移动数据互换',
  ];
}

/// 编号步骤列表。[dark] = 登录页那种近黑底。
class NetFixSteps extends StatelessWidget {
  const NetFixSteps({super.key, this.dark = false});

  final bool dark;

  @override
  Widget build(BuildContext context) {
    final Color numBg = dark ? Colors.white.withOpacity(0.10) : AppTheme.primaryLight;
    final Color numFg = dark ? Colors.white : AppTheme.textPrimary;
    final Color txt = dark ? Colors.white.withOpacity(0.86) : AppTheme.textPrimary;

    final steps = netFixSteps();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: List.generate(steps.length, (i) {
        return Padding(
          padding: EdgeInsets.only(bottom: i == steps.length - 1 ? 0 : 9),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 17,
                height: 17,
                margin: const EdgeInsets.only(top: 1),
                alignment: Alignment.center,
                decoration: BoxDecoration(color: numBg, shape: BoxShape.circle),
                child: Text('${i + 1}',
                    style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        color: numFg)),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(steps[i],
                    style: TextStyle(fontSize: 12.5, height: 1.55, color: txt)),
              ),
            ],
          ),
        );
      }),
    );
  }
}
