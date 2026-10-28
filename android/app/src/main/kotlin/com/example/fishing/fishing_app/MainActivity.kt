package com.example.fishing.fishing_app

import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.telephony.TelephonyManager
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
    private var oneKeyChannel: MethodChannel? = null

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

        // ── 本机号码一键登录桥（v2.1.48）────────────────────────────
        //
        // 真正的「一键登录」必须靠运营商网关取号（蜂窝网络下由运营商侧识别
        // 本机号码，下发一次性 token，再由服务端去服务商换号码）。
        //
        // 这里**不伪造**取号能力：没集成运营商 SDK 就明确告诉 Dart 端
        // not_integrated，界面会自动降级到短信验证码。
        // 也刻意不申请 READ_PHONE_STATE —— getLine1Number() 在国产 ROM 上
        // 基本都是空，为一个大概率拿不到的值让全体用户多一个「电话」权限
        // 不划算；真接了运营商 SDK 反而一个权限都不用要。
        val ok = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "fishing/onekey")
        oneKeyChannel = ok
        ok.setMethodCallHandler { call, result ->
            when (call.method) {
                "probe" -> result.success(probeOneKey())
                "token" -> result.error(
                    "not_integrated", "当前版本未内置运营商取号服务", null
                )
                else -> result.notImplemented()
            }
        }
    }

    /**
     * 探测本机能力。
     * available 恒为 false（未接 SDK）；phone 只在「恰好有电话权限」时才尝试读，
     * 读到就交给 Dart 去预填手机号，读不到不影响任何流程。
     */
    private fun probeOneKey(): Map<String, Any> {
        val out = HashMap<String, Any>()
        out["available"] = false
        var phone = ""
        var reason = "not_integrated"
        try {
            val canRead = if (Build.VERSION.SDK_INT >= 26) {
                checkSelfPermission(android.Manifest.permission.READ_PHONE_NUMBERS) ==
                    PackageManager.PERMISSION_GRANTED
            } else {
                checkSelfPermission(android.Manifest.permission.READ_PHONE_STATE) ==
                    PackageManager.PERMISSION_GRANTED
            }
            if (canRead) {
                val tm = getSystemService(Context.TELEPHONY_SERVICE) as? TelephonyManager
                val raw = tm?.line1Number ?: ""
                phone = raw.replace(Regex("[^0-9]"), "")
                if (phone.length == 11) {
                    reason = "ok"
                } else {
                    phone = ""
                    reason = "no_sim"
                }
            }
        } catch (e: Exception) {
            phone = ""
            reason = "error"
        }
        out["phone"] = phone
        out["masked"] = if (phone.length == 11) {
            phone.substring(0, 3) + "****" + phone.substring(7)
        } else ""
        out["reason"] = reason
        return out
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
