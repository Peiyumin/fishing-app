import 'dart:io';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_theme.dart';
import '../utils/coord_transform.dart';
import '../widgets/center_toast.dart';

/// 一个可导航的地图 App（已安装才会出现在选择列表里）
///
/// v44 起改成 public（原来叫 `NavTarget`）：[MapLauncher.buildTargets] 是
/// 纯函数、单测要直接断言它生成的 URL，返回私有类型会触发
/// `library_private_types_in_public_api`。
class NavTarget {
  final String name;
  final String nativeUrl; // 原生 scheme，直接唤起 App 并进入导航
  final Color color;
  final IconData icon;

  const NavTarget({
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
/// 导航方式（v44 分两种）：
///   · 坐标精确（GPS / 地图点选）→ 把经纬度交给地图 App，直接精准导航到钓位
///   · 坐标不精确（用户只填了文字地址）→ **只把文字地址**填进目的地栏，
///     让地图 App 自己去搜。因为地址解析出来的粗坐标可能偏几百米，
///     拿它当终点会把人导到村口。
///
/// 坐标系：库内存 WGS-84
///   高德 / 腾讯 / 百度 → GCJ-02（先转换）
class MapLauncher {
  /// 让用户选一个已安装的地图 App 去导航
  ///
  /// [precise] 为 false（或 [lat]/[lng] 为空）时走「文字地址导航」：
  /// 不传坐标，只把 [address] 作为目的地关键词。
  static Future<void> navigate(
    BuildContext context, {
    required String name,
    String address = '',
    double? lat,
    double? lng,
    bool precise = true,
  }) async {
    // 坐标有效 = 标记为精确 + 经纬度都是真实值（0 是「没有坐标」的约定）
    final hasCoord = precise &&
        lat != null &&
        lng != null &&
        lat.abs() > 0.0001 &&
        lng.abs() > 0.0001;

    final dest = (address.trim().isNotEmpty ? address.trim() : name.trim());
    final destQ = Uri.encodeComponent(dest);
    final nameQ =
        Uri.encodeComponent(name.trim().isEmpty ? dest : name.trim());

    double dlat = 0, dlng = 0;
    String coord = '';
    if (hasCoord) {
      final gcj = CoordTransform.wgs84ToGcj02(lat, lng);
      dlat = gcj[0];
      dlng = gcj[1];
      coord = '${dlat.toStringAsFixed(6)},${dlng.toStringAsFixed(6)}';
    }

    final targets = buildTargets(
      isAndroid: Platform.isAndroid,
      isIOS: Platform.isIOS,
      hasCoord: hasCoord,
      dlat: dlat,
      dlng: dlng,
      coord: coord,
      destQ: destQ,
      nameQ: nameQ,
    );

    // —— 1. 检测真正装了哪些 ——
    final installed = <NavTarget>[];
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
          dlat: dlat,
          dlng: dlng,
          dest: dest,
          name: name,
          hasCoord: hasCoord);
      return;
    }

    // —— 3. 只列出已安装的，让用户选 ——
    final picked = await showModalBottomSheet<NavTarget>(
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
                  hasCoord
                      ? '已检测到 ${installed.length} 个已安装地图 · 按坐标导航'
                      : '已检测到 ${installed.length} 个已安装地图 · 按地址搜索「$dest」',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
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
                  subtitle: Text(
                      hasCoord ? '已安装 · 直接打开导航' : '已安装 · 打开后按地址搜索',
                      style: const TextStyle(fontSize: 11.5)),
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

  /// 生成各地图 App 的唤起 URL（纯函数，单测直接调）
  ///
  /// [hasCoord] 决定用「坐标导航」还是「文字地址导航」——
  /// 文字模式下**一律不带坐标参数**：带了地图 App 就会优先用那个粗坐标，
  /// 等于把「按地址搜」又变回「导到村口」。
  static List<NavTarget> buildTargets({
    required bool isAndroid,
    required bool isIOS,
    required bool hasCoord,
    required double dlat,
    required double dlng,
    required String coord,
    required String destQ,
    required String nameQ,
  }) {
    final targets = <NavTarget>[];
    final latS = dlat.toStringAsFixed(6);
    final lngS = dlng.toStringAsFixed(6);

    if (isAndroid) {
      targets.addAll([
        NavTarget(
          name: '高德地图',
          nativeUrl: hasCoord
              ? 'amapuri://route/plan/?dlat=$latS&dlon=$lngS&dname=$nameQ'
                  '&dev=0&t=0&sourceApplication=fishing_app'
              // 只给 dname，不给 dlat/dlon：高德会自己去搜这个地名
              : 'amapuri://route/plan/?dname=$destQ'
                  '&dev=0&t=0&sourceApplication=fishing_app',
          color: const Color(0xFF1677FF),
          icon: Icons.navigation_rounded,
        ),
        NavTarget(
          name: '腾讯地图',
          nativeUrl: hasCoord
              ? 'qqmap://map/routeplan?type=drive&to=$destQ'
                  '&tocoord=$coord&policy=0&referer=fishingapp'
              : 'qqmap://map/routeplan?type=drive&to=$destQ'
                  '&policy=0&referer=fishingapp',
          color: const Color(0xFF07C160),
          icon: Icons.map_rounded,
        ),
        NavTarget(
          name: '百度地图',
          nativeUrl: hasCoord
              ? 'baidumap://map/direction?destination=latlng:$coord'
                  '|name:$destQ&coord_type=gcj02&mode=driving'
                  '&src=android.fishingapp'
              : 'baidumap://map/direction?destination=$destQ'
                  '&mode=driving&src=android.fishingapp',
          color: const Color(0xFFE64A3B),
          icon: Icons.directions_car_filled_rounded,
        ),
      ]);
    } else if (isIOS) {
      targets.addAll([
        NavTarget(
          name: '高德地图',
          nativeUrl: hasCoord
              ? 'iosamap://path?sourceApplication=fishing_app'
                  '&dlat=$latS&dlon=$lngS&dname=$nameQ&dev=0&t=0'
              : 'iosamap://path?sourceApplication=fishing_app'
                  '&dname=$destQ&dev=0&t=0',
          color: const Color(0xFF1677FF),
          icon: Icons.navigation_rounded,
        ),
        NavTarget(
          name: '腾讯地图',
          nativeUrl: hasCoord
              ? 'qqmap://map/routeplan?type=drive&to=$destQ'
                  '&tocoord=$coord&policy=0&referer=fishingapp'
              : 'qqmap://map/routeplan?type=drive&to=$destQ'
                  '&policy=0&referer=fishingapp',
          color: const Color(0xFF07C160),
          icon: Icons.map_rounded,
        ),
        NavTarget(
          name: '百度地图',
          nativeUrl: hasCoord
              ? 'baidumap://map/direction?destination=latlng:$coord'
                  '|name:$destQ&coord_type=gcj02&mode=driving'
                  '&src=ios.fishingapp'
              : 'baidumap://map/direction?destination=$destQ'
                  '&mode=driving&src=ios.fishingapp',
          color: const Color(0xFFE64A3B),
          icon: Icons.directions_car_filled_rounded,
        ),
        // 苹果自带地图：iOS 一定存在，保证任何情况下都有 App 可用
        NavTarget(
          name: '苹果地图',
          nativeUrl: hasCoord ? 'maps://?daddr=$coord&dirflg=d' : 'maps://?daddr=$destQ&dirflg=d',
          color: const Color(0xFF3B82F6),
          icon: Icons.explore_rounded,
        ),
      ]);
    }
    return targets;
  }

  /// 没检测到任何地图 App 时的提示（网页版只是用户主动选择的兜底）
  static Future<void> _showNoMapDialog(
    BuildContext context, {
    required double dlat,
    required double dlng,
    required String dest,
    required String name,
    bool hasCoord = true,
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

    // 用户明确选择网页版才打开
    //   有坐标：高德 URI API 的导航页（to=经度,纬度,名称）
    //   没坐标：只能走搜索页，把文字地址当关键词
    final url = hasCoord
        ? 'https://uri.amap.com/navigation'
            '?to=${dlng.toStringAsFixed(6)},${dlat.toStringAsFixed(6)},'
            '${Uri.encodeComponent(dest)}'
            '&mode=car&src=fishing_app&callnative=0'
        : 'https://uri.amap.com/search'
            '?keyword=${Uri.encodeComponent(dest)}'
            '&src=fishing_app&callnative=0';
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
  ///
  /// v44 起 lat/lng 可空、[precise] 可关：钓点详情页遇到「只填了文字地址」的点
  /// 会传 `precise: false`，让地图 App 按地址自己搜。
  static Future<void> showNavSheet(
    BuildContext context, {
    double? lat,
    double? lng,
    String name = '目的地',
    String address = '',
    bool precise = true,
  }) =>
      navigate(context,
          lat: lat, lng: lng, name: name, address: address, precise: precise);
}
