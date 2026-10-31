import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../services/notification_service.dart';
import '../widgets/center_toast.dart';

/// 通知设置
///
/// 三类通知分开控制（私信 / 互动 / 官方公告），开关状态存在本地：
/// 关掉只是不弹提醒，消息中心的未读数照样统计 —— 不会「漏消息」。
class NotifySettingsScreen extends StatefulWidget {
  const NotifySettingsScreen({super.key});

  @override
  State<NotifySettingsScreen> createState() => _NotifySettingsScreenState();
}

class _NotifySettingsScreenState extends State<NotifySettingsScreen> {
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    NotificationService.instance.checkPermission().then((_) {
      if (mounted) setState(() {});
    });
  }

  Future<void> _save() async {
    await NotifyPrefs.save();
    if (mounted) setState(() {});
  }

  Future<void> _toggleMaster(bool v) async {
    NotifyPrefs.enabled = v;
    await _save();
    if (v) {
      // 打开通知时顺便要权限（此时用户预期明确，弹系统框不突兀）
      final ok = await NotificationService.instance.ensurePermission();
      if (mounted) {
        setState(() {});
        if (!ok) {
          CenterToast.show(context, '系统通知权限未开启，请在系统设置中允许',
              icon: Icons.notifications_off_outlined);
        }
      }
    }
  }

  Future<void> _test() async {
    if (_busy) return;
    setState(() => _busy = true);
    final ok = await NotificationService.instance.showTest();
    if (!mounted) return;
    setState(() => _busy = false);
    CenterToast.show(
      context,
      ok ? '已发送，看看通知栏' : '发送失败：请先在系统设置里允许通知',
      icon: ok ? Icons.notifications_active_outlined : Icons.error_outline,
    );
  }

  @override
  Widget build(BuildContext context) {
    final granted = NotifyPrefs.osGranted;
    return Scaffold(
      backgroundColor: AppTheme.background,
      // 顶栏样式全部交给 AppBarTheme（v2.1.59 起主题就是浅色 + 近黑标题）
      appBar: AppBar(title: const Text('通知设置')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 28),
        children: [
          _card(children: [
            SwitchListTile(
              value: NotifyPrefs.enabled,
              onChanged: _toggleMaster,
              activeColor: AppTheme.primary,
              contentPadding: EdgeInsets.zero,
              title: const Text('接收通知',
                  style:
                      TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
              subtitle: const Text('有新私信、评论、点赞和官方公告时提醒我',
                  style:
                      TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
            ),
          ]),
          const SizedBox(height: 10),

          // 分类开关：总开关关掉时整块置灰但保留可见（用户知道有哪些类型）
          Opacity(
            opacity: NotifyPrefs.enabled ? 1 : 0.45,
            child: IgnorePointer(
              ignoring: !NotifyPrefs.enabled,
              child: _card(children: [
                _row(
                  icon: Icons.mail_outline,
                  color: AppTheme.primary,
                  title: '私信消息',
                  sub: '互相关注的钓友发来的私信',
                  value: NotifyPrefs.chat,
                  onChanged: (v) async {
                    NotifyPrefs.chat = v;
                    await _save();
                  },
                ),
                const Divider(height: 1, indent: 52),
                _row(
                  icon: Icons.favorite_border,
                  color: AppTheme.danger,
                  title: '互动提醒',
                  sub: '动态被评论、被点赞，评论被回复',
                  value: NotifyPrefs.interact,
                  onChanged: (v) async {
                    NotifyPrefs.interact = v;
                    await _save();
                  },
                ),
                const Divider(height: 1, indent: 52),
                _row(
                  icon: Icons.campaign_outlined,
                  color: AppTheme.warning,
                  title: '官方公告',
                  sub: '活动通知、版本更新、账号提醒',
                  value: NotifyPrefs.system,
                  onChanged: (v) async {
                    NotifyPrefs.system = v;
                    await _save();
                  },
                ),
              ]),
            ),
          ),
          const SizedBox(height: 10),

          // 系统权限状态
          _card(children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: granted ? AppTheme.primaryLight : AppTheme.warningLight,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  granted
                      ? Icons.notifications_active
                      : Icons.notifications_off_outlined,
                  size: 19,
                  color: granted ? AppTheme.primary : AppTheme.warning,
                ),
              ),
              title: Text(
                granted ? '系统通知已开启' : '系统通知未开启',
                style: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w600),
              ),
              subtitle: Text(
                granted
                    ? '消息会显示在手机通知栏与通知中心'
                    : '手机没有允许本 App 发通知，开启后才能收到提醒',
                style: const TextStyle(
                    fontSize: 12, color: AppTheme.textSecondary),
              ),
              trailing: granted
                  ? null
                  : TextButton(
                      onPressed: () async {
                        await NotificationService.instance.ensurePermission();
                        if (mounted) setState(() {});
                      },
                      child: const Text('去开启'),
                    ),
            ),
            const SizedBox(height: 4),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _busy ? null : _test,
                icon: _busy
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.send_outlined, size: 17),
                label: const Text('发送一条测试通知'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.primary,
                  side: const BorderSide(color: AppTheme.primaryBorder),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ]),
          const SizedBox(height: 14),

          // 权限自检入口：定位 / 相机 / 相册 / 通知 一站式检查与补齐
          _card(children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppTheme.primaryLight,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.verified_user_outlined,
                    size: 19, color: AppTheme.primary),
              ),
              title: const Text('应用权限自检',
                  style:
                      TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              subtitle: const Text('检查定位、相机、相册、通知授权并一键补齐',
                  style:
                      TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
              trailing: const Icon(Icons.chevron_right,
                  size: 18, color: AppTheme.textSecondary),
              onTap: () => Navigator.of(context)
                  .pushNamed('/permission-check'),
            ),
          ]),
          const SizedBox(height: 14),

          // 说明（正面表述 + 事实交代）
          Container(
            padding: const EdgeInsets.all(13),
            decoration: BoxDecoration(
              color: AppTheme.primarySoft,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.primaryBorder),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Icon(Icons.info_outline, size: 15, color: AppTheme.primary),
                  SizedBox(width: 5),
                  Text('关于提醒方式',
                      style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.primaryDark)),
                ]),
                SizedBox(height: 6),
                Text(
                  '· App 打开或刚切回前台时，新消息会即时弹出提醒，并同步显示在通知栏。\n'
                  '· App 关闭期间的消息不会丢，下次打开会在消息中心按未读补齐。\n'
                  '· 后续上架 App Store 后可开启「锁屏也能收到」的离线推送。',
                  style: TextStyle(
                      fontSize: 11.5,
                      height: 1.6,
                      color: AppTheme.textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _card({required List<Widget> children}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(AppTheme.radiusMd),
          border: Border.all(color: AppTheme.border),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: children),
      );

  Widget _row({
    required IconData icon,
    required Color color,
    required String title,
    required String sub,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return SwitchListTile(
      value: value,
      onChanged: onChanged,
      activeColor: AppTheme.primary,
      contentPadding: EdgeInsets.zero,
      secondary: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, size: 19, color: color),
      ),
      title: Text(title,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
      subtitle: Text(sub,
          style: const TextStyle(fontSize: 11.5, color: AppTheme.textSecondary)),
    );
  }
}
