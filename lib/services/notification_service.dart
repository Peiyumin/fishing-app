import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/message.dart';

/// 通知偏好（本地持久化，默认全开）
///
/// 为什么存本地而不是服务端：开关只影响「这台机器要不要弹」，
/// 关掉通知不应该影响未读数的统计（消息中心照样能看到）。
class NotifyPrefs {
  static const _kEnabled = 'notify_enabled';
  static const _kChat = 'notify_chat';
  static const _kInteract = 'notify_interact';
  static const _kSystem = 'notify_system';
  static const _kAsked = 'notify_perm_asked';

  /// 总开关
  static bool enabled = true;

  /// 私信
  static bool chat = true;

  /// 互动（评论 / 回复 / 点赞）
  static bool interact = true;

  /// 官方公告 / 系统通知
  static bool system = true;

  /// 是否已经问过一次系统权限（避免每次启动都弹）
  static bool permAsked = false;

  /// 系统级通知权限是否已授予（运行时探测，不持久化）
  static bool osGranted = false;

  static Future<void> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      enabled = p.getBool(_kEnabled) ?? true;
      chat = p.getBool(_kChat) ?? true;
      interact = p.getBool(_kInteract) ?? true;
      system = p.getBool(_kSystem) ?? true;
      permAsked = p.getBool(_kAsked) ?? false;
    } catch (_) {}
  }

  static Future<void> save() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setBool(_kEnabled, enabled);
      await p.setBool(_kChat, chat);
      await p.setBool(_kInteract, interact);
      await p.setBool(_kSystem, system);
      await p.setBool(_kAsked, permAsked);
    } catch (_) {}
  }

  /// 这一条是否允许弹通知
  static bool allows(FeedItem n) {
    if (!enabled) return false;
    if (n.isChat) return chat;
    if (n.isSystem) return system;
    if (n.isInteract) return interact;
    return true;
  }
}

/// 系统通知服务（Android 通知栏 / iOS 通知中心横幅）
///
/// 三条 Android 渠道分开建，用户可以在系统设置里单独关掉某一类：
///   fishing_chat     私信消息
///   fishing_interact 评论 / 回复 / 点赞
///   fishing_system   官方公告
///
/// ★ 说明（关于「离线推送」）：
///   本服务是**本地通知**，由 App 内的消息轮询触发。所以：
///     · App 在前台 / 刚切回前台 → 立刻能收到（本服务负责）；
///     · App 被系统彻底杀掉 → 收不到（需要 APNs / FCM 服务端推送，
///       要求正式签名的开发者证书与推送证书，与当前未签名分发方式不兼容）。
///   为了覆盖「杀掉后也想看到」，消息中心 + 未读红点会保留全部历史，
///   下次打开 App 时一次性补齐（见 MessagePoller 的 catch-up 逻辑）。
class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _inited = false;
  int _seq = 0;

  /// 用户点了通知（payload 是 [FeedItem.toPayload] 的 JSON 串）
  void Function(Map<String, dynamic> payload)? onTap;

  /// App 冷启动时由「点击通知」带进来的 payload，等 UI 就绪后消费
  Map<String, dynamic>? pendingPayload;

  bool get supported => !kIsWeb;

  static const _icStat = '@drawable/ic_stat_notify';

  static const _chChat = AndroidNotificationChannel(
    'fishing_chat',
    '私信消息',
    description: '钓友给你发来的私信',
    importance: Importance.high,
  );
  static const _chInteract = AndroidNotificationChannel(
    'fishing_interact',
    '互动提醒',
    description: '动态被评论、被点赞、评论被回复',
    importance: Importance.high,
  );
  static const _chSystem = AndroidNotificationChannel(
    'fishing_system',
    '官方公告',
    description: '活动通知、版本更新、账号提醒',
    importance: Importance.high,
  );

  Future<void> init() async {
    if (_inited || !supported) return;
    _inited = true;
    try {
      await NotifyPrefs.load();
      await _plugin.initialize(
        const InitializationSettings(
          android: AndroidInitializationSettings(_icStat),
          // 启动时不主动弹权限框：等用户真的打开通知开关 / 首次轮询到新消息时再问，
          // 冷启动就弹权限框是 iOS 审核明确不推荐的做法。
          iOS: DarwinInitializationSettings(
            requestAlertPermission: false,
            requestBadgePermission: false,
            requestSoundPermission: false,
          ),
        ),
        onDidReceiveNotificationResponse: (resp) {
          final p = _decode(resp.payload);
          if (p != null) onTap?.call(p);
        },
        onDidReceiveBackgroundNotificationResponse: null,
      );

      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      if (android != null) {
        await android.createNotificationChannel(_chChat);
        await android.createNotificationChannel(_chInteract);
        await android.createNotificationChannel(_chSystem);
      }

      // 冷启动：App 是被「点通知」拉起来的
      final launch = await _plugin.getNotificationAppLaunchDetails();
      if (launch != null && launch.didNotificationLaunchApp) {
        pendingPayload = _decode(launch.notificationResponse?.payload);
      }
    } catch (e) {
      debugPrint('[Notify] init failed: $e');
    }
  }

  Map<String, dynamic>? _decode(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final v = jsonDecode(raw);
      if (v is Map) return v.cast<String, dynamic>();
    } catch (_) {}
    return null;
  }

  /// 请求系统通知权限（Android 13+ / iOS 都需要）
  ///
  /// 返回是否已授权。用户点「不再询问」后只能去系统设置里开，这里返回 false。
  Future<bool> ensurePermission() async {
    if (!supported) return false;
    await init();
    try {
      if (defaultTargetPlatform == TargetPlatform.android) {
        final p = _plugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
        final ok = await p?.requestNotificationsPermission();
        NotifyPrefs.osGranted = ok ?? false;
      } else if (defaultTargetPlatform == TargetPlatform.iOS) {
        final p = _plugin.resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>();
        final ok = await p?.requestPermissions(
            alert: true, badge: true, sound: true);
        NotifyPrefs.osGranted = ok ?? false;
      } else {
        NotifyPrefs.osGranted = false;
      }
    } catch (_) {
      NotifyPrefs.osGranted = false;
    }
    NotifyPrefs.permAsked = true;
    await NotifyPrefs.save();
    return NotifyPrefs.osGranted;
  }

  /// 探测当前是否已授权（不弹框）
  Future<bool> checkPermission() async {
    if (!supported) return false;
    await init();
    try {
      if (defaultTargetPlatform == TargetPlatform.android) {
        final p = _plugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
        // 低版本 Android 没有这个接口，返回 null 视为可用
        final ok = await p?.areNotificationsEnabled();
        NotifyPrefs.osGranted = ok ?? true;
      } else if (defaultTargetPlatform == TargetPlatform.iOS) {
        final p = _plugin.resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>();
        final opts = await p?.checkPermissions();
        NotifyPrefs.osGranted = (opts?.isEnabled ?? false);
      }
    } catch (_) {}
    return NotifyPrefs.osGranted;
  }

  AndroidNotificationChannel _channelOf(FeedItem n) {
    if (n.isChat) return _chChat;
    if (n.isSystem) return _chSystem;
    return _chInteract;
  }

  /// 解析某条通知应该用的 channelId（给应用内「通知设置」展示用）
  static String channelIdOf(String type) {
    if (type == 'chat') return 'fishing_chat';
    if (type == 'system') return 'fishing_system';
    return 'fishing_interact';
  }

  /// 弹一条系统通知
  ///
  /// 返回是否真的弹出去了：没有系统权限 / 平台不支持时返回 false，
  /// 上层据此决定要不要退回「应用内横幅」兜底提醒。
  Future<bool> show(FeedItem n) async {
    if (!supported) return false;
    if (!NotifyPrefs.allows(n)) return false;
    await init();
    final ch = _channelOf(n);
    final body = n.pushBody;
    try {
      await _plugin.show(
        // 用自增序号做通知 id：保证每条都能弹出来（Android 会排队而不是覆盖）
        (++_seq) & 0x7fffffff,
        n.pushTitle,
        body.length > 120 ? '${body.substring(0, 120)}…' : body,
        NotificationDetails(
          android: AndroidNotificationDetails(
            ch.id,
            ch.name,
            channelDescription: ch.description,
            importance: Importance.high,
            priority: Priority.high,
            icon: _icStat,
            // 长文本展开后可看全文（评论内容经常超过一行）
            styleInformation: BigTextStyleInformation(body),
            autoCancel: true,
            enableVibration: true,
            category: AndroidNotificationCategory.message,
          ),
          iOS: const DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
          ),
        ),
        payload: jsonEncode(n.toPayload()),
      );
      return true;
    } catch (e) {
      debugPrint('[Notify] show failed: $e');
      return false;
    }
  }

  /// 一组通知聚合成一条（多条点赞/评论不刷屏）
  ///
  /// [items] 至少 1 条；标题取聚合文案，正文取最新一条的内容。
  Future<bool> showGrouped({
    required String title,
    required String body,
    required String type,
    String refId = '',
    String peerId = '',
  }) async {
    final n = FeedItem(
      id: 'g${DateTime.now().millisecondsSinceEpoch}',
      kind: type == 'chat' ? 'chat' : 'notice',
      type: type,
      title: title,
      content: body,
      refId: refId,
      peerId: peerId,
    );
    return show(n);
  }

  /// 自检：设置页「发一条测试通知」用
  Future<bool> showTest() async {
    if (!supported) return false;
    final ok = await ensurePermission();
    if (!ok) return false;
    await show(const FeedItem(
      id: 'test',
      kind: 'notice',
      type: 'system',
      title: '通知已开启',
      content: '之后有新私信、评论、点赞和官方公告，都会在这里提醒你。',
    ));
    return true;
  }
}
