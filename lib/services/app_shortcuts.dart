import 'package:flutter/services.dart';

/// 长按 App 图标的快捷入口（v2.1.44）
///
/// 三个入口在两端都做了声明：
///   · iOS：`Info.plist` 的 `UIApplicationShortcutItems`（系统图标无法自定义）；
///   · Android：`res/xml/shortcuts.xml` + manifest 的 `android.app.shortcuts`。
///
/// 原生侧通过同一个 channel `fishing/shortcuts` 通信：
///   · `consume`：Dart 主动取「冷启动待处理」的快捷项（取完即清）；
///   · `shortcut`：热启动（App 在后台）时原生主动推过来。
///
/// ★ 冷启动时 Navigator 还没建，直接跳必然失败 —— 所以冷启动的项先攒在
///   [_pending] 里，等主界面挂载后由 [flushPending] 补跳（main.dart 调用）。
class AppShortcuts {
  static const MethodChannel _ch = MethodChannel('fishing/shortcuts');

  /// 收到快捷项后的处理逻辑（由 main 注入：等 navigator 就绪再 push）
  static void Function(String type)? onAction;

  static String? _pending;

  /// 类型 → 路由（与 Info.plist / shortcuts.xml 里的值一一对应）
  static const String guide = 'fish_guide';
  static const String tank = 'fish_tank';
  static const String catchFish = 'catch';

  /// 中文名（跳转失败或埋点时用）
  static String label(String type) => switch (type) {
        guide => '我的图鉴',
        tank => '赛博鱼缸',
        catchFish => '记渔获',
        _ => '',
      };

  static Future<void> init() async {
    _ch.setMethodCallHandler((call) async {
      if (call.method == 'shortcut') {
        final t = (call.arguments ?? '').toString();
        if (t.isNotEmpty) _deliver(t);
      }
      return null;
    });
    try {
      final t = await _ch.invokeMethod<String>('consume');
      if (t != null && t.isNotEmpty) _pending = t;
    } catch (_) {
      // 平台没实现（测试环境 / 桌面）或 channel 还没建好：忽略
    }
  }

  /// 主界面挂载后调用：把冷启动攒下的那一项补跳
  static void flushPending() {
    final t = _pending;
    _pending = null;
    if (t != null && t.isNotEmpty) _deliver(t);
  }

  static void _deliver(String type) => onAction?.call(type);
}
