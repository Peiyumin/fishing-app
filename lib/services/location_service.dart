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
/// 第二轮修复（iOS 不弹权限框 / 点定位没反应）：
///   首页、天气、钓点页、发布页会在 App 启动时**同时**调用定位，
///   于是 `requestPermission()` 被并发触发 3~5 次。iOS 对同一个 App 只弹一次
///   系统权限框，其余并发调用会立刻拿到 denied —— 表现就是「iOS 从不弹定位
///   权限框」「点了定位按钮没反应」「打开 App 不会自动定位」。
///   现在用 [_permFuture] 把权限请求串行化：同一时刻只有一次真正请求，
///   其余调用复用同一个 Future，谁都不会拿到假的 denied。
///
/// 所有定位一律走 [determinePosition]：
///   1. 检查手机定位服务（GPS）是否开启
///   2. 检查/申请定位权限（denied → 自动弹框；deniedForever → 引导去设置）
///   3. 取当前位置（15 秒超时，防个别机型无限等待）
class LocationService {
  static const _timeout = Duration(seconds: 15);

  /// 正在进行的权限请求（保证全局同一时刻只有一次，避免并发把系统弹框顶掉）
  static Future<LocationPermission>? _permFuture;

  /// 申请定位权限（串行、去重）。
  ///
  /// 并发调用时只有第一个会真正调系统 API，其余复用同一个结果。
  static Future<LocationPermission> ensurePermission() {
    final pending = _permFuture;
    if (pending != null) return pending;

    final f = _requestPermission();
    _permFuture = f;
    // 结束后清空，下次调用重新走一次（例如用户去设置里授权后回到 App）
    f.whenComplete(() => _permFuture = null);
    return f;
  }

  static Future<LocationPermission> _requestPermission() async {
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      // 首次使用：弹出系统权限框请求用户授权
      permission = await Geolocator.requestPermission();
    }
    return permission;
  }

  /// 当前权限状态（不触发弹框）
  static Future<LocationPermission> currentPermission() =>
      Geolocator.checkPermission();

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

    // 2. 权限检查与申请（串行化，防止并发把 iOS 的系统弹框顶掉）
    try {
      final permission = await ensurePermission();
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

  /// 跳转系统定位服务开关（Android 可直接拉起定位设置；iOS 与 openSettings 同）
  static Future<bool> openLocationSettings() => Geolocator.openLocationSettings();
}
