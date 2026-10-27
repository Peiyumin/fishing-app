import UIKit
import Flutter

/// 长按 App 图标的快捷入口（v2.1.44）
///
/// 三个快捷项在 Info.plist 的 `UIApplicationShortcutItems` 里静态声明
/// （我的图鉴 / 赛博鱼缸 / 记渔获）。点击后分两种情况：
///   · **冷启动**：App 没在跑，shortcutItem 在 launchOptions 里 —— 先写进
///     UserDefaults，等 Dart 侧启动完调 `consume` 取走（此时 Navigator 还没建，
///     直接跳转必然失败）；
///   · **热启动**：App 在后台，走 `performActionFor`，直接通过 channel 推给 Dart。
@UIApplicationMain
@objc class AppDelegate: FlutterAppDelegate {
  private static let channelName = "fishing/shortcuts"
  private static let pendingKey = "pending_shortcut"

  private var shortcutChannel: FlutterMethodChannel?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)

    if let controller = window?.rootViewController as? FlutterViewController {
      let channel = FlutterMethodChannel(name: AppDelegate.channelName,
                                         binaryMessenger: controller.binaryMessenger)
      channel.setMethodCallHandler { call, result in
        if call.method == "consume" {
          result(AppDelegate.takePending())
        } else {
          result(FlutterMethodNotImplemented)
        }
      }
      shortcutChannel = channel
    }

    // 冷启动：用户是长按图标点快捷项把 App 拉起来的
    if let item = launchOptions?[.shortcutItem] as? UIApplicationShortcutItem {
      UserDefaults.standard.set(item.type, forKey: AppDelegate.pendingKey)
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  override func application(
    _ application: UIApplication,
    performActionFor shortcutItem: UIApplicationShortcutItem,
    completionHandler: @escaping (Bool) -> Void
  ) {
    // 热启动：App 已在后台，直接推给 Flutter（Dart 侧会等 navigator 就绪再跳）
    shortcutChannel?.invokeMethod("shortcut", arguments: shortcutItem.type)
    completionHandler(true)
  }

  private static func takePending() -> String {
    let v = UserDefaults.standard.string(forKey: pendingKey) ?? ""
    if !v.isEmpty {
      UserDefaults.standard.removeObject(forKey: pendingKey)
    }
    return v
  }
}
