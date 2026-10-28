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

  /// 微信登录桥（v2.1.46）
  ///
  /// 当前版本**还没有集成微信 SDK**（缺开放平台的 AppID / AppSecret）。
  /// 这里先把 channel 注册上，明确回 `not_integrated`：
  ///   · 不注册的话 Dart 侧抛 `MissingPluginException`，会被误判成
  ///     「手机没装微信」，用户怎么修都修不好；
  ///   · 注册后提示准确（「当前版本未内置微信登录，请用手机号」），
  ///     而且 AppID 到位时**只改这个文件 + Info.plist**，Dart 侧一行不用动。
  private static let wechatChannelName = "fishing/wechat"
  private var wechatChannel: FlutterMethodChannel?

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

      // 微信登录：现在只回状态，等 SDK 接上再把 login 换成正真的 WXApi.send
      let wch = FlutterMethodChannel(name: AppDelegate.wechatChannelName,
                                     binaryMessenger: controller.binaryMessenger)
      wch.setMethodCallHandler { call, result in
        switch call.method {
        case "available":
          // 集成 SDK 后改成 WXApi.isWXAppInstalled()
          result(false)
        case "login":
          result(FlutterError(code: "not_integrated",
                              message: "当前版本未内置微信登录",
                              details: nil))
        default:
          result(FlutterMethodNotImplemented)
        }
      }
      wechatChannel = wch
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
