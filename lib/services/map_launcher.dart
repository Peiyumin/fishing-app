import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_theme.dart';
import '../utils/coord_transform.dart';
import '../widgets/center_toast.dart';

/// 单个地图渠道：原生 scheme（已安装）+ 网页版兜底
class _MapOption {
  final String name;
  final String nativeUrl;
  final String webUrl;
  final Color color;
  final IconData icon;
  bool installed = false;

  _MapOption({
    required this.name,
    required this.nativeUrl,
    required this.webUrl,
    required this.color,
    required this.icon,
  });

  String get url => installed ? nativeUrl : webUrl;
  String get subtitle => installed ? '已安装 · 直接导航' : '网页版导航';
}

/// 第三方地图导航启动器
/// 点击「导航前往」列出高德 / 腾讯 / 百度三家：
///   · 手机装了对应 App → 用原生 scheme 唤起 App 直接驾车导航
///   · 没装 → 打开该地图网页版导航（浏览器里也能走）
///
/// 坐标系说明：库内存 WGS-84
///   高德 / 腾讯 → GCJ-02（先转换再传）
///   百度       → coord_type=wgs84 直传原始坐标
class MapLauncher {
  /// 一键直接调起本机地图 App 开始导航（不弹选择框）
  ///
  /// 说明：
  ///  · 目的地优先用**中文地址**（address 非空时），这样地图 App 的
  ///    「终点」栏里显示的是「河南省禹州市小刘垂钓园」而不是一串数字；
  ///  · Android 依次尝试 高德 → 百度 → 系统 geo:（geo: 会让系统自己选默认地图）；
  ///  · iOS 用 Apple 地图（maps://），同样把地址填进终点栏；
  ///  · 全部失败时退回原来的多地图选择面板，保证用户还能导。
  static Future<void> navigate(
    BuildContext context, {
    required double lat,
    required double lng,
    required String name,
    String address = '',
  }) async {
    final gcj = CoordTransform.wgs84ToGcj02(lat, lng);
    final dlat = gcj[0], dlng = gcj[1];
    final dest = address.trim().isNotEmpty ? address.trim() : name.trim();
    final destQ = Uri.encodeComponent(dest);
    final nameQ = Uri.encodeComponent(name.trim().isEmpty ? dest : name.trim());

    final candidates = <Uri>[];

    if (Platform.isIOS) {
      // Apple 地图：daddr 用地址，导航栏直接显示中文地址
      candidates.add(Uri.parse(
          'maps://?daddr=$destQ&dirflg=d&q=$nameQ'));
      candidates.add(Uri.parse(
          'http://maps.apple.com/?daddr=$destQ&dirflg=d'));
    } else if (Platform.isAndroid) {
      // 高德：dlat/dlon 精确定位 + destinationName 显示名称
      candidates.add(Uri.parse('amapuri://route/plan/?dlat=$dlat&dlon=$dlng'
          '&dev=0&t=2&destinationName=$nameQ&dname=$destQ'));
      // 百度：destination 用地址名（导航栏显示地址）
      candidates.add(Uri.parse('baidumap://map/direction?destination=$destQ'
          '&coord_type=gcj02&mode=driving&src=android.fishingapp'));
      // 系统地图选择器（装了腾讯/其他地图也能兜住）
      candidates.add(Uri.parse('geo:$lat,$lng?q=$lat,$lng($destQ)'));
    } else {
      candidates.add(Uri.parse('https://uri.amap.com/navigation?to=$dlng,$dlat,$nameQ'
          '&mode=car&src=fishing_app'));
    }

    for (final uri in candidates) {
      try {
        if (await canLaunchUrl(uri)) {
          final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
          if (ok) return;
        }
      } catch (_) {
        // 试下一个
      }
    }

    // 全部失败：退回多地图选择面板
    if (context.mounted) {
      await showNavSheet(context, lat: lat, lng: lng, name: name);
    }
  }

  static Future<void> showNavSheet(
    BuildContext context, {
    required double lat,
    required double lng,
    String name = '目的地',
  }) async {
    final gcj = CoordTransform.wgs84ToGcj02(lat, lng);
    final dlat = gcj[0], dlng = gcj[1];
    final q = Uri.encodeComponent(name);

    final options = await _buildOptions(lat, lng, dlat, dlng, q);
    if (!context.mounted) return;

    final picked = await showModalBottomSheet<_MapOption>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 14),
              child: Text('选择地图导航',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
            ...options.map((o) => ListTile(
                  leading: Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: o.color.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Icon(o.icon, size: 19, color: o.color),
                  ),
                  title: Text(o.name),
                  subtitle: Text(o.subtitle,
                      style: const TextStyle(fontSize: 11.5)),
                  trailing: const Icon(Icons.chevron_right, size: 18),
                  onTap: () => Navigator.pop(ctx, o),
                )),
            const Divider(height: 1),
            ListTile(
              leading: Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: AppTheme.primaryLight,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: const Icon(Icons.copy_rounded,
                    size: 18, color: AppTheme.primary),
              ),
              title: const Text('复制坐标'),
              subtitle: Text('${lat.toStringAsFixed(6)}, ${lng.toStringAsFixed(6)}',
                  style: const TextStyle(fontSize: 11.5)),
              onTap: () => Navigator.pop(ctx, null),
            ),
            const SizedBox(height: 6),
          ],
        ),
      ),
    );
    if (!context.mounted) return;

    if (picked == null) {
      await Clipboard.setData(ClipboardData(
          text: '${lat.toStringAsFixed(6)},${lng.toStringAsFixed(6)}'));
      if (context.mounted) CenterToast.show(context, '坐标已复制');
      return;
    }

    final uri = Uri.parse(picked.url);
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok && context.mounted) {
        CenterToast.show(context, '无法打开${picked.name}');
      }
    } catch (_) {
      if (context.mounted) {
        CenterToast.show(context, '无法打开${picked.name}');
      }
    }
  }

  /// 组装三家地图；用 canLaunchUrl 探测是否装了原生 App。
  static Future<List<_MapOption>> _buildOptions(
      double wgsLat, double wgsLng, double dlat, double dlng, String q) async {
    final list = <_MapOption>[
      _MapOption(
        name: '高德地图',
        nativeUrl: 'amapuri://route/plan/?dlat=$dlat&dlon=$dlng'
            '&dev=0&t=2&destinationName=$q',
        webUrl: 'https://uri.amap.com/navigation?to=$dlng,$dlat,$q'
            '&mode=car&src=fishing_app&callnative=0',
        color: const Color(0xFF1677FF),
        icon: Icons.navigation_rounded,
      ),
      _MapOption(
        name: '腾讯地图',
        nativeUrl: 'qqmap://map/routeplan?type=drive&to=$q'
            '&tocoord=$dlat,$dlng&policy=0',
        webUrl: 'https://apis.map.qq.com/uri/v1/routeplan?type=drive'
            '&to=$q&tocoord=$dlat,$dlng&policy=0&referer=fishingapp',
        color: const Color(0xFF07C160),
        icon: Icons.map_rounded,
      ),
      _MapOption(
        name: '百度地图',
        nativeUrl: 'baidumap://map/direction?destination=$wgsLat,$wgsLng'
            '&coord_type=wgs84&mode=driving',
        webUrl: 'https://api.map.baidu.com/direction?destination=latlng:'
            '$wgsLat,$wgsLng|name:$q&mode=driving&coord_type=wgs84'
            '&output=html&src=fishingapp',
        color: const Color(0xFFE64A3B),
        icon: Icons.directions_car_filled_rounded,
      ),
    ];

    if (Platform.isAndroid || Platform.isIOS) {
      for (final o in list) {
        try {
          o.installed = await canLaunchUrl(Uri.parse(o.nativeUrl));
        } catch (_) {
          o.installed = false;
        }
      }
    }
    return list;
  }
}
