import 'package:flutter/material.dart';

/// 首页宫格的「图标 key → 图标」映射
///
/// ★ 后台 `lib/home_layout.php` 里的 `home_icon_catalog()` 必须和这张表一一对应：
///   后台存的是字符串 key，App 只认这里列出来的名字。后台加了一个新 key 而
///   这里没加，用户看到的就是右下角那个兜底图标（不会崩，但会显得串味）。
///
/// 全部用 Material 的 outline 线性图标：首页宫格底色是浅灰，
/// 实心图标在小尺寸下会糊成一团，线性图标在 22~24dp 上更清楚。
const Map<String, IconData> kHomeIcons = {
  'weather': Icons.wb_sunny_outlined,
  'spot': Icons.place_outlined,
  'catch': Icons.catching_pokemon_outlined,
  'lure': Icons.sports_handball_outlined,
  'blackpit': Icons.water_drop_outlined,
  'gear': Icons.shopping_bag_outlined,
  'skill': Icons.menu_book_outlined,
  'event': Icons.event_outlined,
  'shop': Icons.storefront_outlined,
  'live': Icons.live_tv_outlined,
  'pond': Icons.waves_outlined,
  'guide': Icons.auto_stories_outlined,
  'member': Icons.workspace_premium_outlined,
  'signin': Icons.task_alt_outlined,
  'nearby': Icons.explore_outlined,
  'boat': Icons.sailing_outlined,
  'hook': Icons.set_meal_outlined,
  'trophy': Icons.emoji_events_outlined,
  'gift': Icons.card_giftcard_outlined,
  'chat': Icons.forum_outlined,
};

/// 兜底图标：后台填了表里没有的 key 时用
const IconData kHomeIconFallback = Icons.apps_outlined;

IconData homeIconOf(String key) => kHomeIcons[key] ?? kHomeIconFallback;
