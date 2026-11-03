import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../models/fishing_spot.dart';

/// 钓点标记的三类身份 —— 地图上用颜色区分（v2.1.69）
///
/// 用户要求：野钓点绿 / 黑坑·鱼塘·收费的红 / 渔具店蓝，图标统一改成小房子。
/// 分类只认「这条钓点到底是什么」，不看它被谁发布：
///   · shop            → 渔具店（蓝）
///   · venue           → 本地钓场，一律收费类（红）
///   · fee / type 命中  → 收费（红），比如野钓点但标了「50 元/天」
///   · 其余 wild       → 野钓点（绿）
enum SpotMarkerRole { wild, paid, shop }

class SpotMarkerStyle {
  const SpotMarkerStyle._();

  /// 野钓点：绿
  static const Color wildColor = AppTheme.spotWild;

  /// 黑坑 / 鱼塘 / 收费：红
  static const Color paidColor = AppTheme.spotPaid;

  /// 渔具店：蓝
  static const Color shopColor = AppTheme.spotShop;

  static SpotMarkerRole roleOf(FishingSpot s) {
    if (s.kind == 'shop') return SpotMarkerRole.shop;
    if (s.kind == 'venue' || _looksPaid(s)) return SpotMarkerRole.paid;
    return SpotMarkerRole.wild;
  }

  static Color colorOfRole(SpotMarkerRole role) {
    switch (role) {
      case SpotMarkerRole.wild:
        return wildColor;
      case SpotMarkerRole.paid:
        return paidColor;
      case SpotMarkerRole.shop:
        return shopColor;
    }
  }

  static Color colorOf(FishingSpot s) => colorOfRole(roleOf(s));

  /// 原生地图内核里每类一张 PNG（`addImage` 的名字）
  static String iconIdOfRole(SpotMarkerRole role) => 'spot-pin-${role.name}';

  /// 图例 / 无障碍文案
  static String labelOfRole(SpotMarkerRole role) {
    switch (role) {
      case SpotMarkerRole.wild:
        return '野钓点';
      case SpotMarkerRole.paid:
        return '收费钓场';
      case SpotMarkerRole.shop:
        return '渔具店';
    }
  }

  /// 判断「这条是不是收费的」
  ///
  /// 导入的高德黑坑数据里，`type` 有「黑坑 / 鱼塘」，`fee` 有「正钓 200/4h」
  /// 「偷驴 100」这类写法；也有野钓点被标成「免费」。所以先看关键词，
  /// 再看收费文本里到底有没有价格数字 —— 「免费停车」不该算收费。
  static bool _looksPaid(FishingSpot s) {
    final text = '${s.type} ${s.fee}'.trim();
    if (text.isEmpty) return false;
    if (RegExp(r'黑坑|鱼塘|斤塘|收费|门票|年卡|练竿').hasMatch(text)) return true;
    final fee = s.fee.trim();
    if (fee.isEmpty) return false;
    if (RegExp(r'免费|不收费|无').hasMatch(fee) && !RegExp(r'\d').hasMatch(fee)) {
      return false;
    }
    return RegExp(r'[¥￥\d]').hasMatch(fee);
  }
}
