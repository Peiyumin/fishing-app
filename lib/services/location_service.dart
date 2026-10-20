import 'dart:async';

import 'package:geolocator/geolocator.dart';

/// 定位失败类型（用于 UI 层决定提示方式）
enum LocationErrorType {
  /// 手机定位服务（GPS）没开
  serviceDisabled,

  /// 定位权限被拒绝（含永久拒绝）
  permissionDenied,

  /// 定位超时
  timeout,

  /// 其他
  unknown,
}

/// 带中文原因的定位异常
class LocationException implements Exception {
  final String message;
  final LocationErrorType type;
  const LocationException(this.message, this.type);

  @override
  String toString() => message;
}

/// 统一定位入口。
///
/// 背景（Bug 修复）：geolocator 11.x 的 `getCurrentPosition` **不会自动弹权限框**，
/// 权限为 denied 时直接抛异常。原代码 9 处调用全部漏了权限申请，导致双端
/// 「打开 App 无法定位、点定位图标也失败」。
///
/// 所有定位一律走 [determinePosition]：
///   1. 检查手机定位服务（GPS）是否开启
///   2. 检查/申请定位权限（denied → 自动弹框；deniedForever → 引导去设置）
///   3. 取当前位置（15 秒超时，防个别机型无限等待）
class LocationService {
  static const _timeout = Duration(seconds: 15);

  /// 获取当前位置（WGS-84 坐标系）。
  /// 失败抛 [LocationException]，message 为可直接展示给用户的中文原因。
  static Future<Position> determinePosition({
    LocationAccuracy accuracy = LocationAccuracy.high,
  }) async {
    // 1. 定位服务（GPS 总开关）
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        throw const LocationException(
          '请先打开手机定位服务（GPS），再下拉刷新试试',
          LocationErrorType.serviceDisabled,
        );
      }
    } on LocationException {
      rethrow;
    } catch (_) {
      // 检查本身失败时继续往下走，由取位置步骤兜底报错
    }

    // 2. 权限检查与申请（核心修复点）
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        // 首次使用：弹出系统权限框请求用户授权
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied) {
        throw const LocationException(
          '需要定位权限才能获取位置，请在弹窗中点击「允许」',
          LocationErrorType.permissionDenied,
        );
      }
      if (permission == LocationPermission.deniedForever) {
        throw const LocationException(
          '定位权限被拒绝了，请到系统「设置」里为本 App 开启定位权限',
          LocationErrorType.permissionDenied,
        );
      }
    } on LocationException {
      rethrow;
    } catch (_) {
      // 权限检查异常不阻塞，继续尝试取位置
    }

    // 3. 取位置（带超时）
    try {
      return await Geolocator.getCurrentPosition(
        desiredAccuracy: accuracy,
        timeLimit: _timeout,
      );
    } on TimeoutException {
      throw const LocationException(
        '定位超时了，请到室外开阔处或检查网络后重试',
        LocationErrorType.timeout,
      );
    } on LocationServiceDisabledException {
      throw const LocationException(
        '定位服务被关闭了，请先打开手机定位（GPS）',
        LocationErrorType.serviceDisabled,
      );
    } on PermissionDeniedException {
      throw const LocationException(
        '定位权限被拒绝，请到系统「设置」里开启后重试',
        LocationErrorType.permissionDenied,
      );
    } catch (e) {
      throw LocationException('定位失败：${e.toString()}', LocationErrorType.unknown);
    }
  }

  /// 跳转系统设置页（用户去开定位权限/定位服务）
  static Future<void> openSettings() => Geolocator.openAppSettings();
}
