package com.example.fishing.fishing_app

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * 长按图标的快捷入口（v2.1.44）
 *
 * res/xml/shortcuts.xml 里每个快捷项都往 intent 塞 shortcut=<type>：
 *   · 冷启动：Activity 由这个 intent 创建，取值后缓存起来等 Dart 调 consume；
 *   · 热启动：走 onNewIntent，直接 channel 推给 Dart。
 * Dart 侧统一在 AppShortcuts 里处理（等 navigator 就绪再跳）。
 */
class MainActivity : FlutterActivity() {
    private var pendingShortcut: String? = null
    private var channel: MethodChannel? = null
    private var wechatChannel: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val ch = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "fishing/shortcuts")
        channel = ch
        ch.setMethodCallHandler { call, result ->
            if (call.method == "consume") {
                val v = pendingShortcut ?: intent?.getStringExtra("shortcut") ?: ""
                pendingShortcut = null
                intent?.removeExtra("shortcut")
                result.success(v)
            } else {
                result.notImplemented()
            }
        }
        readShortcut(intent, notifyDart = false)

        // 微信登录桥（v2.1.46）：与 iOS AppDelegate 保持一致。
        // 当前版本还没集成微信 SDK，明确回 not_integrated —— 不注册的话
        // Dart 侧会抛 MissingPluginException，被误判成「手机没装微信」。
        val wx = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "fishing/wechat")
        wechatChannel = wx
        wx.setMethodCallHandler { call, result ->
            when (call.method) {
                "available" -> result.success(false)
                "login" -> result.error(
                    "not_integrated", "当前版本未内置微信登录", null
                )
                else -> result.notImplemented()
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        readShortcut(intent, notifyDart = true)
    }

    private fun readShortcut(intent: Intent?, notifyDart: Boolean) {
        val t = intent?.getStringExtra("shortcut") ?: return
        pendingShortcut = t
        intent.removeExtra("shortcut")
        if (notifyDart) channel?.invokeMethod("shortcut", t)
    }
}
