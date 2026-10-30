import 'dart:async';

import 'package:flutter/foundation.dart';
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

/// 单次取位置的尝试参数
class _Attempt {
  final LocationAccuracy accuracy;
  final Duration timeLimit;

  /// 仅 Android：true = 用系统 LocationManager，false = 用 Google 融合定位
  final bool forceLocationManager;
  final String label;

  const _Attempt(
    this.accuracy,
    this.timeLimit,
    this.forceLocationManager,
    this.label,
  );
}

/// 统一定位入口。
///
/// 背景（Bug 修复 1）：geolocator 11.x 的 `getCurrentPosition` **不会自动弹权限框**，
/// 权限为 denied 时直接抛异常。原代码 9 处调用全部漏了权限申请，导致双端
/// 「打开 App 无法定位、点定位图标也失败」。
///
/// 修复 2（iOS 不弹权限框 / 点定位没反应）：
///   首页、天气、钓点页、发布页会在 App 启动时**同时**调用定位，
///   于是 `requestPermission()` 被并发触发 3~5 次。iOS 对同一个 App 只弹一次
///   系统权限框，其余并发调用会立刻拿到 denied —— 表现就是「iOS 从不弹定位
///   权限框」「点了定位按钮没反应」「打开 App 不会自动定位」。
///   现在用 [_permFuture] 把权限请求串行化：同一时刻只有一次真正请求，
///   其余调用复用同一个 Future，谁都不会拿到假的 denied。
///
/// ★ 修复 3（v2.1.46，安卓「发布渔获」定位一直超时）：
///   原来只有一条路径：`getCurrentPosition(desiredAccuracy: high, timeLimit: 15s)`。
///   在下列三种真机上必然超时，而且越点重试越失败：
///     1. **国产 ROM 无 GMS**：默认走 Google 融合定位（FusedLocationProvider），
///        没有 Google Play 服务时这个客户端拿不到任何回调 → 干等到超时。
///     2. **安卓 12+ 只给了「近似位置」**（只有 COARSE 没有 FINE）：
///        请求 high（PRIORITY_HIGH_ACCURACY）不会返回结果。
///     3. **室内 / 冷启动**：纯 GPS 首定位要 30~60s，15s 根本不够。
///   现在改成**多档降级**：融合定位(短促试探) → 系统 LocationManager(高精度)
///   → 中精度 → 低精度 → 系统缓存的最后一次定位。任一步成功即返回，
///   单步失败只降级不报错，全部失败才抛 [LocationException]。
///
/// 所有定位一律走 [determinePosition]：
///   1. 检查手机定位服务（GPS）是否开启
///   2. 检查/申请定位权限（denied → 自动弹框；deniedForever → 引导去设置）
///   3. 按 [determinePosition] 里的阶梯依次尝试，并带总时长保护
class LocationService {
  /// 单步超时：融合定位先短促试一下（GMS 正常时 2~3 秒就回来了，
  /// 8 秒还不动基本就是没有 GMS）
  static const Duration _fusedProbe = Duration(seconds: 8);

  /// 系统 LocationManager 高精度（GPS 冷启动，给足时间）
  static const Duration _managerHigh = Duration(seconds: 14);

  /// 降级到中/低精度（靠 WiFi/基站，室内也能出结果）
  static const Duration _relaxed = Duration(seconds: 10);

  /// 测试专用：非空时替代真实定位（避免测试环境 geolocator 平台通道
  /// 在 fake-async 下永不返回导致挂起）。生产代码默认 null。
  static Future<Position> Function({LocationAccuracy accuracy})?
      testDetermineOverride;

  /// 上一次定位结果是「系统缓存的旧位置」（不是当场实测）。
  /// UI 可据此提示「当前位置来自上次记录」。
  static bool lastFixWasCached = false;

  /// 上一次定位用的档位（排查用，也方便 toast 说明）
  static String lastFixSource = '';

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

  /// 是否**已经**拿到定位权限（只查，不弹系统授权框）
  ///
  /// 用于「顺手补一个地名」这种非必要场景：用户打开一篇文章就弹定位授权
  /// 太打扰，没授权就直接不显示地名。
  static Future<bool> hasPermission() async {
    try {
      final p = await Geolocator.checkPermission();
      return p == LocationPermission.always || p == LocationPermission.whileInUse;
    } catch (_) {
      return false;
    }
  }

  /// 取位置阶梯。Android 与 iOS 走的路径不同：
  /// - Android 先试融合定位，再退回系统 LocationManager（国产机没 GMS 的救命档）
  /// - iOS 只有 CoreLocation 一套，直接按高→中降级
  static List<_Attempt> _plan(LocationAccuracy accuracy) {
    final isAndroid =
        !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
    if (isAndroid) {
      return [
        // ① 融合定位短促试探：有 GMS 的机器 2~3 秒就出结果
        _Attempt(accuracy, _fusedProbe, false, '融合定位'),
        // ② 系统 LocationManager：没有 GMS 也能用，国产 ROM 的主力档
        _Attempt(accuracy, _managerHigh, true, '系统定位'),
        // ③ 降一档精度，走 WiFi/基站，室内也能出
        _Attempt(LocationAccuracy.medium, _relaxed, true, '中精度定位'),
        // ④ 再降一档（只给「近似位置」权限时靠这一档）
        _Attempt(LocationAccuracy.low, _relaxed, false, '低精度定位'),
      ];
    }
    return [
      _Attempt(accuracy, _managerHigh, false, '高精度定位'),
      _Attempt(LocationAccuracy.medium, _relaxed, false, '中精度定位'),
      _Attempt(LocationAccuracy.low, _relaxed, false, '低精度定位'),
    ];
  }

  /// 获取当前位置（WGS-84 坐标系）。
  /// 失败抛 [LocationException]，message 为可直接展示给用户的中文原因。
  static Future<Position> determinePosition({
    LocationAccuracy accuracy = LocationAccuracy.high,
  }) async {
    if (testDetermineOverride != null) {
      return testDetermineOverride!(accuracy: accuracy);
    }
    lastFixWasCached = false;
    lastFixSource = '';

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

    // 3. 按阶梯取位置：任一步成功即返回，失败只降级
    LocationException? lastError;
    Object? lastRaw;
    for (final a in _plan(accuracy)) {
      try {
        final pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: a.accuracy,
          forceAndroidLocationManager: a.forceLocationManager,
          timeLimit: a.timeLimit,
        );
        lastFixSource = a.label;
        return pos;
      } on TimeoutException catch (e) {
        lastError = const LocationException(
          '定位超时了，请到室外开阔处或检查网络后重试',
          LocationErrorType.timeout,
        );
        lastRaw = e;
      } on LocationServiceDisabledException catch (e) {
        lastError = const LocationException(
          '定位服务被关闭了，请先打开手机定位（GPS）',
          LocationErrorType.serviceDisabled,
        );
        lastRaw = e;
      } catch (e) {
        // 例如某个 provider 缺失（UnsupportedError / PlatformException）——
        // 换下一档继续，不要直接判定失败
        lastRaw = e;
        lastError ??= LocationException(
          '定位失败：$e',
          LocationErrorType.unknown,
        );
      }
    }

    // 4. 兜底：系统缓存的最后一次定位。
    //    钓鱼人往往就在上次钓点附近，缓存位置比「一点都拿不到」有用得多；
    //    只要不是太久以前（7 天内）就接受，并打上 lastFixWasCached 标记。
    try {
      final cached = await Geolocator.getLastKnownPosition();
      if (cached != null) {
        final age = DateTime.now().difference(cached.timestamp);
        if (age.inDays <= 7) {
          lastFixWasCached = true;
          lastFixSource = '上次定位记录';
          return cached;
        }
      }
    } catch (_) {
      // 缓存也拿不到就继续抛下面的错
    }

    if (lastError != null) throw lastError;
    throw LocationException(
      '定位失败：${lastRaw ?? '未知原因'}',
      LocationErrorType.unknown,
    );
  }

  /// 跳转系统设置页（用户去开定位权限/定位服务）
  static Future<void> openSettings() => Geolocator.openAppSettings();

  /// 跳转系统定位服务开关（Android 可直接拉起定位设置；iOS 与 openSettings 同）
  static Future<bool> openLocationSettings() => Geolocator.openLocationSettings();
}
