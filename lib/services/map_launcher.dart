import 'dart:io';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_theme.dart';
import '../utils/coord_transform.dart';
import '../widgets/center_toast.dart';

/// 一个可导航的地图 App（已安装才会出现在选择列表里）
class _NavTarget {
  final String name;
  final String nativeUrl; // 原生 scheme，直接唤起 App 并进入导航
  final Color color;
  final IconData icon;

  const _NavTarget({
    required this.name,
    required this.nativeUrl,
    required this.color,
    required this.icon,
  });
}

/// 第三方地图导航启动器
///
/// 交互设计（v17）：**先检测、再让用户选**
///   1. 点「导航前往」后，用 canLaunchUrl 探测手机上真正装了哪些地图 App；
///   2. 弹窗只列出「已安装」的地图（高德 / 腾讯 / 百度 / 苹果地图），
///      没装的一律不显示，也不会偷偷跳到网页版；
///   3. 用户点哪个就用原生 scheme 唤起那个 App，并把**中文地址**填进终点栏；
///   4. 一个都没装时，明确提示「请先安装地图 App」，网页版只作为用户主动选择的兜底。
///
/// 坐标系：库内存 WGS-84
///   高德 / 腾讯 / 百度 → GCJ-02（先转换）
class MapLauncher {
  /// 让用户选一个已安装的地图 App 去导航
  static Future<void> navigate(
    BuildContext context, {
    required double lat,
    required double lng,
    required String name,
    String address = '',
  }) async {
    final gcj = CoordTransform.wgs84ToGcj02(lat, lng);
    final dlat = gcj[0], dlng = gcj[1];

    // 终点优先用中文地址，让地图 App 的终点栏显示地名而不是一串数字
    final dest = address.trim().isNotEmpty ? address.trim() : name.trim();
    final destQ = Uri.encodeComponent(dest);
    final nameQ = Uri.encodeComponent(name.trim().isEmpty ? dest : name.trim());
    final coord = '${dlat.toStringAsFixed(6)},${dlng.toStringAsFixed(6)}';

    final targets = <_NavTarget>[];

    if (Platform.isAndroid) {
      targets.addAll([
        _NavTarget(
          name: '高德地图',
          nativeUrl: 'amapuri://route/plan/?dlat=${dlat.toStringAsFixed(6)}'
              '&dlon=${dlng.toStringAsFixed(6)}&dname=$nameQ'
              '&dev=0&t=0&sourceApplication=fishing_app',
          color: const Color(0xFF1677FF),
          icon: Icons.navigation_rounded,
        ),
        _NavTarget(
          name: '腾讯地图',
          nativeUrl: 'qqmap://map/routeplan?type=drive&to=$destQ'
              '&tocoord=$coord&policy=0&referer=fishingapp',
          color: const Color(0xFF07C160),
          icon: Icons.map_rounded,
        ),
        _NavTarget(
          name: '百度地图',
          nativeUrl: 'baidumap://map/direction?destination=latlng:$coord'
              '|name:$destQ&coord_type=gcj02&mode=driving'
              '&src=android.fishingapp',
          color: const Color(0xFFE64A3B),
          icon: Icons.directions_car_filled_rounded,
        ),
      ]);
    } else if (Platform.isIOS) {
      targets.addAll([
        _NavTarget(
          name: '高德地图',
          nativeUrl: 'iosamap://path?sourceApplication=fishing_app'
              '&dlat=${dlat.toStringAsFixed(6)}&dlon=${dlng.toStringAsFixed(6)}'
              '&dname=$nameQ&dev=0&t=0',
          color: const Color(0xFF1677FF),
          icon: Icons.navigation_rounded,
        ),
        _NavTarget(
          name: '腾讯地图',
          nativeUrl: 'qqmap://map/routeplan?type=drive&to=$destQ'
              '&tocoord=$coord&policy=0&referer=fishingapp',
          color: const Color(0xFF07C160),
          icon: Icons.map_rounded,
        ),
        _NavTarget(
          name: '百度地图',
          nativeUrl: 'baidumap://map/direction?destination=latlng:$coord'
              '|name:$destQ&coord_type=gcj02&mode=driving'
              '&src=ios.fishingapp',
          color: const Color(0xFFE64A3B),
          icon: Icons.directions_car_filled_rounded,
        ),
        // 苹果自带地图：iOS 一定存在，保证任何情况下都有 App 可用
        _NavTarget(
          name: '苹果地图',
          nativeUrl: 'maps://?daddr=$destQ&dirflg=d',
          color: const Color(0xFF3B82F6),
          icon: Icons.explore_rounded,
        ),
      ]);
    }

    // —— 1. 检测真正装了哪些 ——
    final installed = <_NavTarget>[];
    for (final t in targets) {
      var ok = false;
      try {
        ok = await canLaunchUrl(Uri.parse(t.nativeUrl));
      } catch (_) {
        ok = false;
      }
      if (ok) installed.add(t);
    }

    if (!context.mounted) return;

    // —— 2. 一个都没装：明确提示，而不是偷偷开网页版 ——
    if (installed.isEmpty) {
      await _showNoMapDialog(context,
          dlat: dlat, dlng: dlng, dest: dest, name: name);
      return;
    }

    // —— 3. 只列出已安装的，让用户选 ——
    final picked = await showModalBottomSheet<_NavTarget>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 16, 20, 4),
              child: Row(
                children: [
                  Icon(Icons.navigation_rounded,
                      size: 18, color: AppTheme.primary),
                  SizedBox(width: 6),
                  Text('选择地图 App 导航',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '已检测到 ${installed.length} 个已安装地图',
                  style: const TextStyle(
                      fontSize: 12, color: AppTheme.textSecondary),
                ),
              ),
            ),
            const Divider(height: 1),
            ...installed.map((t) => ListTile(
                  leading: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: t.color.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(t.icon, size: 20, color: t.color),
                  ),
                  title: Text(t.name,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: const Text('已安装 · 直接打开导航',
                      style: TextStyle(fontSize: 11.5)),
                  trailing: const Icon(Icons.chevron_right, size: 18),
                  onTap: () => Navigator.pop(ctx, t),
                )),
            const SizedBox(height: 6),
          ],
        ),
      ),
    );

    if (picked == null || !context.mounted) return;

    try {
      final ok = await launchUrl(Uri.parse(picked.nativeUrl),
          mode: LaunchMode.externalApplication);
      if (!ok && context.mounted) {
        CenterToast.show(context, '无法打开${picked.name}');
      }
    } catch (_) {
      if (context.mounted) CenterToast.show(context, '无法打开${picked.name}');
    }
  }

  /// 没检测到任何地图 App 时的提示（网页版只是用户主动选择的兜底）
  static Future<void> _showNoMapDialog(
    BuildContext context, {
    required double dlat,
    required double dlng,
    required String dest,
    required String name,
  }) async {
    final goWeb = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('未检测到地图 App'),
        content: const Text(
          '手机上还没有安装可导航的地图应用。\n\n'
          '请先安装「高德地图」「腾讯地图」或「百度地图」，'
          '再回到这里点「导航前往」，就能直接唤起 App 导航。',
          style: TextStyle(fontSize: 13.5, height: 1.6),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('知道了'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('用网页版导航'),
          ),
        ],
      ),
    );

    if (goWeb != true || !context.mounted) return;

    // 用户明确选择网页版才打开（高德 URI API：to=经度,纬度,名称）
    final url = 'https://uri.amap.com/navigation'
        '?to=${dlng.toStringAsFixed(6)},${dlat.toStringAsFixed(6)},'
        '${Uri.encodeComponent(dest)}'
        '&mode=car&src=fishing_app&callnative=0';
    try {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (_) {
      if (context.mounted) CenterToast.show(context, '无法打开网页版地图');
    }
    if (context.mounted) {
      CenterToast.show(context, '目的地：$name');
    }
  }

  /// 兼容旧调用：等价于 navigate（同样先检测再让用户选）
  static Future<void> showNavSheet(
    BuildContext context, {
    required double lat,
    required double lng,
    String name = '目的地',
    String address = '',
  }) =>
      navigate(context, lat: lat, lng: lng, name: name, address: address);
}
