import 'package:flutter/material.dart';

import '../services/spot_service.dart';
import '../app_theme.dart';

/// 地址解析结果（v45）
///
/// 三个添加页（野钓点 / 本地钓场 / 渔具店）共用一套语义：
///   · [ok]      —— 拿到街道级坐标，可以在地图上预览、可以保存
///   · [reason]  —— 为什么没解析出来（给用户看的人话）
///
/// 为什么要包一层：以前调用方只拿到 `null`，分不清「地址太短」「没登录」
/// 「后端三条通道全挂」，最后干脆拿当前定位顶上，才出了「填了地址却存在
/// 自己脚下」的事故。现在失败一定带原因，谁也糊弄不过去。
class AddressLookup {
  const AddressLookup._(this.point, this.reason);

  final GeoPoint? point;
  final String reason;

  bool get ok => point != null;
  double get lat => point?.lat ?? 0;
  double get lng => point?.lng ?? 0;

  /// 服务端规范化后的地址（比用户手打的更完整，可以回填地址框）
  String get formatted => point?.formatted ?? '';

  /// 「街道级（百度）」这类精度说明
  String get hint => point?.hint ?? '';

  factory AddressLookup.success(GeoPoint p) => AddressLookup._(p, '');

  factory AddressLookup.failure(String reason) =>
      AddressLookup._(null, reason.trim().isEmpty ? '没能解析成位置' : reason.trim());

  /// 解析一段文字地址（异步，可能走网络）
  static Future<AddressLookup> resolve(String address) async {
    final a = address.trim();
    if (a.length < 4) return AddressLookup.failure('地址太短，请写清省市区或乡镇');
    final g = await SpotService.geocodeAddress(a);
    if (g != null && g.valid) return AddressLookup.success(g);
    return AddressLookup.failure(SpotService.lastGeocodeError);
  }
}

/// 解析失败时的兜底选项
enum AddressFallbackAction {
  /// 回去改地址（最常见的诉求：少打了几个字）
  editAddress,

  /// 用当前定位（用户心里清楚「我就站在这儿」）
  useCurrentLocation,

  /// 在地图上点一下
  pickOnMap,
}

/// 地址解析失败 → 让用户自己选，**绝不默认拿当前定位顶上**
///
/// 返回 null 表示用户点了外面（等同于「先别提交」）。
Future<AddressFallbackAction?> showAddressFallbackSheet(
  BuildContext context, {
  required String address,
  required String reason,
}) {
  return showModalBottomSheet<AddressFallbackAction>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 18,
        bottom: 18 + MediaQuery.of(ctx).padding.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.location_off_outlined,
                  color: AppTheme.danger, size: 20),
              const SizedBox(width: 8),
              const Expanded(
                child: Text('这个地址没能解析成位置',
                    style: TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w600)),
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 20),
                tooltip: '关闭',
                onPressed: () => Navigator.of(ctx).pop(),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '「$address」',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
                fontSize: 13, color: AppTheme.textSecondary),
          ),
          if (reason.trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              reason,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontSize: 12, color: AppTheme.danger, height: 1.4),
            ),
          ],
          const SizedBox(height: 14),
          const Text(
            '选一个来定位置（不会自动用你当前的位置）：',
            style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 8),
          _FallbackOption(
            icon: Icons.edit_location_alt_outlined,
            title: '重新填地址',
            subtitle: '补上省市区 + 乡镇 / 水库名，更容易解析',
            onTap: () => Navigator.of(ctx).pop(AddressFallbackAction.editAddress),
          ),
          _FallbackOption(
            icon: Icons.my_location,
            title: '就用我当前的定位',
            subtitle: '你现在就在这个点位上，直接把脚下标成钓点',
            onTap: () =>
                Navigator.of(ctx).pop(AddressFallbackAction.useCurrentLocation),
          ),
          _FallbackOption(
            icon: Icons.touch_app_outlined,
            title: '在地图上点一下',
            subtitle: '知道大概位置，直接在地图上指出来',
            onTap: () => Navigator.of(ctx).pop(AddressFallbackAction.pickOnMap),
          ),
        ],
      ),
    ),
  );
}

class _FallbackOption extends StatelessWidget {
  const _FallbackOption({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: AppTheme.background,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Icon(icon, size: 22, color: AppTheme.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w500)),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: const TextStyle(
                          fontSize: 12, color: AppTheme.textSecondary)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right,
                size: 18, color: AppTheme.textSecondary),
          ],
        ),
      ),
    );
  }
}
