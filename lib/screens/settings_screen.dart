import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_theme.dart';
import '../app_version.dart';
import '../models/user_address.dart';
import '../services/account_history.dart';
import '../services/app_settings.dart';
import '../services/cached_tile_provider.dart';
import '../services/notification_service.dart';
import '../services/session_provider.dart';
import '../services/settings_service.dart';
import '../widgets/center_toast.dart';
import '../widgets/ui_kit.dart';
import 'about_screen.dart';
import 'address_list_screen.dart';
import 'history_accounts_screen.dart';
import 'legal_doc_screen.dart';
import 'permission_check_screen.dart';

/// 设置页（我的 → 右上角齿轮）
///
/// 版式对齐参考稿：分组白卡 + 左侧圆角图标 + 右侧箭头/开关/数值，
/// 分组顺序「通用 → 账号 → 隐私与协议 → 关于」，最底部是退出登录。
///
/// 每一项都是真的做事，没有占位：
///   消息推送   → 控制本机通知（NotifyPrefs）+ 同步后端
///   个性化推荐 → 关掉后首页按时间倒序，不再按热度推荐（AppSettings）
///   字体大小   → 立即改变全站字号（AppSettings + MaterialApp.builder）
///   历史账号   → 本机 30 天内登录过的账号，可一键切换
///   收货地址   → 后端 user_addresses，增删改 + 默认地址
///   鱼获隐私   → 发布渔获时「钓点公开」的默认值
///   联系客服   → 后端配置的电话/微信，可直接拨号或复制
///   隐私协议   → 后端 /legal 文本（内置兜底）
///   个人信息与权限 → 系统权限自检页
///   注销账号   → 后端 /account/cancel，不可恢复
///   清除地图缓存 → 真的删 map_tiles 目录并刷新占用
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final AppSettings _settings = AppSettings.instance;

  bool _push = NotifyPrefs.enabled;
  bool _personalized = AppSettings.instance.personalized;
  bool _catchPrivacy = AppSettings.instance.catchPrivacy;
  int _cacheBytes = 0;
  SupportInfo _support = const SupportInfo();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    // 先拉服务端偏好（登录态才有），失败不影响本地值
    await _settings.syncFromServer();
    final support = await SettingsService.support();
    final bytes = await CachedTileProvider.cacheBytes();
    if (!mounted) return;
    setState(() {
      _push = NotifyPrefs.enabled;
      _personalized = _settings.personalized;
      _catchPrivacy = _settings.catchPrivacy;
      _support = support;
      _cacheBytes = bytes;
    });
  }

  // ---------------- 各项动作 ----------------

  Future<void> _togglePush(bool v) async {
    setState(() => _push = v);
    NotifyPrefs.enabled = v;
    await NotifyPrefs.save();
    if (v) {
      // 打开时才要权限：此刻用户意图明确，弹系统框不突兀
      final ok = await NotificationService.instance.ensurePermission();
      if (!mounted) return;
      setState(() {});
      if (!ok) {
        CenterToast.show(context, '系统通知权限未开启，请在系统设置中允许',
            icon: Icons.notifications_off_outlined);
      }
    }
    // 同步给后端（将来做服务端推送时按这个开关过滤）
    SettingsService.save(push: v).catchError((_) {});
  }

  Future<void> _togglePersonalized(bool v) async {
    setState(() => _personalized = v);
    await _settings.setPersonalized(v);
  }

  Future<void> _pickFont() async {
    final level = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppTheme.radiusLg)),
      ),
      builder: (_) => _FontSheet(current: _settings.fontLevel),
    );
    if (level == null || !mounted) return;
    await _settings.setFontLevel(level);
    if (mounted) setState(() {});
  }

  Future<void> _catchPrivacySheet() async {
    final v = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppTheme.radiusLg)),
      ),
      builder: (_) => _CatchPrivacySheet(current: _catchPrivacy),
    );
    if (v == null || !mounted) return;
    setState(() => _catchPrivacy = v);
    await _settings.setCatchPrivacy(v);
  }

  Future<void> _supportSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppTheme.radiusLg)),
      ),
      builder: (_) => _SupportSheet(info: _support),
    );
  }

  Future<void> _withdrawConsent() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('撤回隐私授权'),
        content: const Text(
            '撤回后将清除你在本机的授权记录，并退出当前登录。\n'
            '再次登录时会重新向你征求同意，未同意前无法发布内容与使用定位相关功能。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('确认撤回', style: TextStyle(color: AppTheme.danger)),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await SettingsService.consent(false);
      await _settings.setConsentAt('');
      final sp = Provider.of<SessionProvider>(context, listen: false);
      await sp.signOut();
      if (!mounted) return;
      CenterToast.show(context, '已撤回授权，请重新登录并同意协议',
          icon: Icons.verified_user_outlined);
      Navigator.of(context).popUntil((r) => r.isFirst);
    } catch (e) {
      if (mounted) CenterToast.show(context, '撤回失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _cancelAccount() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('注销账号'),
        content: const Text(
            '注销后账号无法恢复，请谨慎操作。\n\n'
            '· 你的渔获、动态、评论会保留，但作者显示为「已注销用户」\n'
            '· 手机号会被释放，可重新注册新账号\n'
            '· 积分、鱼币、会员权益、收货地址将全部清除，且不予退还'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('再想想')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('我已知晓，注销', style: TextStyle(color: AppTheme.danger)),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    // 二次确认：必须手动输入「注销」两个字，避免误触
    final word = await showDialog<String>(
      context: context,
      builder: (ctx) => _TypeToConfirmDialog(),
    );
    if (word != '注销' || !mounted) return;

    setState(() => _busy = true);
    try {
      await SettingsService.cancelAccount();
      final sp = Provider.of<SessionProvider>(context, listen: false);
      final uid = sp.userId;
      if (uid != null) await AccountHistoryStore.remove(uid);
      await sp.signOut();
      if (!mounted) return;
      CenterToast.show(context, '账号已注销', icon: Icons.check_circle_outline);
      Navigator.of(context).popUntil((r) => r.isFirst);
    } catch (e) {
      if (mounted) CenterToast.show(context, '注销失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _clearMapCache() async {
    final size = CachedTileProvider.formatBytes(_cacheBytes);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清除地图缓存'),
        content: Text('将删除已下载的地图瓦片（当前占用 $size）。\n'
            '清除后地图需要重新联网加载，不影响账号与发布内容。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('清除')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await CachedTileProvider.clearCache();
    final bytes = await CachedTileProvider.cacheBytes();
    if (!mounted) return;
    setState(() => _cacheBytes = bytes);
    CenterToast.show(context, '已清除地图缓存', icon: Icons.cleaning_services_outlined);
  }

  Future<void> _signOut() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('退出登录'),
        content: const Text('退出后需要重新登录才能发布与查看个人内容，确定退出吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('退出登录', style: TextStyle(color: AppTheme.danger)),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final sp = Provider.of<SessionProvider>(context, listen: false);
    await sp.signOut();
    _settings.setConsentAt('');
    if (!mounted) return;
    Navigator.of(context).popUntil((r) => r.isFirst);
    CenterToast.show(context, '已退出登录', icon: Icons.logout);
  }

  // ---------------- 版式 ----------------

  @override
  Widget build(BuildContext context) {
    final sp = Provider.of<SessionProvider>(context);
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('设置'),
        elevation: 0,
      ),
      body: AbsorbPointer(
        absorbing: _busy,
        child: ListView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(12, 14, 12, 30),
          children: [
            // ── 通用 ──
            const _GroupTitle('通用'),
            _card([
              _row(
                icon: Icons.notifications_none_rounded,
                title: '消息推送',
                trailing: _switch(_push, _togglePush),
              ),
              const SizedBox(
                      width: double.infinity,
                      child: Divider(height: 1, indent: 52)),
              _row(
                icon: Icons.auto_awesome_outlined,
                title: '个性化推荐',
                sub: '按你的搜索与浏览推荐内容',
                trailing: _switch(_personalized, _togglePersonalized),
              ),
              const SizedBox(
                      width: double.infinity,
                      child: Divider(height: 1, indent: 52)),
              _row(
                icon: Icons.format_size_rounded,
                title: '字体大小',
                trailing: _valueText(_settings.fontLevelLabel, chevron: true),
                onTap: _pickFont,
              ),
            ]),

            // ── 账号 ──
            const _GroupTitle('账号'),
            _card([
              _row(
                icon: Icons.history_rounded,
                title: '历史账号',
                sub: '本机 30 天内登录过的账号',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const HistoryAccountsScreen()),
                ),
              ),
              const SizedBox(
                      width: double.infinity,
                      child: Divider(height: 1, indent: 52)),
              _row(
                icon: Icons.location_on_outlined,
                title: '收货地址',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const AddressListScreen()),
                ),
              ),
              const SizedBox(
                      width: double.infinity,
                      child: Divider(height: 1, indent: 52)),
              _row(
                icon: Icons.visibility_off_outlined,
                title: '鱼获隐私',
                trailing: _valueText(_catchPrivacy ? '默认公开钓点' : '默认不公开',
                    chevron: true),
                onTap: _catchPrivacySheet,
              ),
              const SizedBox(
                      width: double.infinity,
                      child: Divider(height: 1, indent: 52)),
              _row(
                icon: Icons.headset_mic_outlined,
                title: '联系客服',
                onTap: _supportSheet,
              ),
            ]),

            // ── 隐私与协议 ──
            const _GroupTitle('隐私与协议'),
            _card([
              _legalRow('用户协议', 'terms', Icons.description_outlined),
              const SizedBox(
                      width: double.infinity,
                      child: Divider(height: 1, indent: 52)),
              _legalRow('隐私政策', 'privacy', Icons.shield_outlined),
              const SizedBox(
                      width: double.infinity,
                      child: Divider(height: 1, indent: 52)),
              _row(
                icon: Icons.undo_rounded,
                title: '撤回同意隐私',
                onTap: _withdrawConsent,
              ),
              const SizedBox(
                      width: double.infinity,
                      child: Divider(height: 1, indent: 52)),
              _row(
                icon: Icons.lock_outline_rounded,
                title: '个人信息与权限',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const PermissionCheckScreen()),
                ),
              ),
              const SizedBox(
                      width: double.infinity,
                      child: Divider(height: 1, indent: 52)),
              _legalRow('个人信息收集与使用清单', 'collect', Icons.list_alt_rounded),
              const SizedBox(
                      width: double.infinity,
                      child: Divider(height: 1, indent: 52)),
              _legalRow('第三方信息共享清单', 'third', Icons.ios_share_rounded),
              const SizedBox(
                      width: double.infinity,
                      child: Divider(height: 1, indent: 52)),
              _row(
                icon: Icons.person_remove_outlined,
                title: '注销账号',
                sub: '注销后账号无法恢复，请谨慎操作',
                danger: true,
                onTap: _cancelAccount,
              ),
            ]),

            // ── 关于 ──
            const _GroupTitle('关于'),
            _card([
              _row(
                icon: Icons.phone_iphone_rounded,
                title: '当前版本',
                trailing: _valueText(kAppVersion, chevron: true),
                onTap: () => CenterToast.show(context, '当前已是最新版本 $kAppVersion',
                    icon: Icons.verified_outlined),
              ),
              const SizedBox(
                      width: double.infinity,
                      child: Divider(height: 1, indent: 52)),
              _row(
                icon: Icons.delete_outline_rounded,
                title: '清除地图缓存',
                trailing: _valueText(CachedTileProvider.formatBytes(_cacheBytes),
                    chevron: true),
                onTap: _clearMapCache,
              ),
              const SizedBox(
                      width: double.infinity,
                      child: Divider(height: 1, indent: 52)),
              _row(
                icon: Icons.info_outline_rounded,
                title: '关于渔报',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const AboutScreen()),
                ),
              ),
            ]),

            const SizedBox(height: 18),
            if (sp.isLoggedIn)
              _card(
                [
                  InkWell(
                    onTap: _signOut,
                    borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                    child: const SizedBox(
                      height: 50,
                      child: Center(
                        child: Text('退出登录',
                            style: TextStyle(
                                fontSize: 15.5,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.danger)),
                      ),
                    ),
                  ),
                ],
                padV: 0,
              ),
          ],
        ),
      ),
    );
  }

  // v2.1.59：分组卡圆角与全站统一到 radiusLg，横向内边距 13→14，
  // 与消息页、我的页的卡片贴边位置对齐（都是 12 外边距 + 14 内边距）。
  Widget _card(List<Widget> children, {double padV = 2}) => Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(AppTheme.radiusLg),
          border: Border.all(color: AppTheme.border),
        ),
        padding: EdgeInsets.symmetric(horizontal: 14, vertical: padV),
        child: Column(mainAxisSize: MainAxisSize.min, children: children),
      );

  Widget _switch(bool value, ValueChanged<bool> onChanged) => Transform.scale(
        scale: 0.86,
        child: Switch(
          value: value,
          onChanged: onChanged,
          // 黑轨道 + 黄绿圆点，和品牌色一致（参考稿也是这个配色）
          activeTrackColor: AppTheme.primary,
          activeColor: AppTheme.accent,
          inactiveThumbColor: Colors.white,
          inactiveTrackColor: AppTheme.border,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      );

  Widget _valueText(String text, {bool chevron = false}) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(text,
              style: const TextStyle(fontSize: 12.5, color: AppTheme.textTertiary)),
          if (chevron) ...[
            const SizedBox(width: 2),
            const Icon(Icons.chevron_right_rounded,
                size: 19, color: AppTheme.textTertiary),
          ],
        ],
      );

  Widget _legalRow(String title, String key, IconData icon) => _row(
        icon: icon,
        title: title,
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => LegalDocScreen(docKey: key, title: title)),
        ),
      );

  Widget _row({
    required IconData icon,
    required String title,
    String? sub,
    Widget? trailing,
    VoidCallback? onTap,
    bool danger = false,
  }) {
    final color = danger ? AppTheme.danger : AppTheme.textPrimary;
    final content = Padding(
      padding: EdgeInsets.symmetric(vertical: sub == null ? 12 : 9),
      child: Row(
        children: [
          Container(
            width: 27,
            height: 27,
            decoration: BoxDecoration(
              color: danger ? AppTheme.dangerLight : AppTheme.primaryLight,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 16, color: color),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600,
                        color: danger ? AppTheme.danger : AppTheme.textPrimary)),
                if (sub != null) ...[
                  const SizedBox(height: 2),
                  Text(sub,
                      style: const TextStyle(
                          fontSize: 11.5, color: AppTheme.textTertiary)),
                ],
              ],
            ),
          ),
          if (trailing != null) trailing,
          if (onTap != null && trailing == null)
            const Icon(Icons.chevron_right_rounded,
                size: 20, color: AppTheme.textTertiary),
        ],
      ),
    );
    if (onTap == null) return content;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: content,
    );
  }
}

class _GroupTitle extends StatelessWidget {
  const _GroupTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) =>
      UiSectionTitle(text, padding: const EdgeInsets.fromLTRB(4, 18, 4, 8));
}

// ══════════════════════ 字体大小 ══════════════════════

class _FontSheet extends StatelessWidget {
  const _FontSheet({required this.current});
  final String current;

  @override
  Widget build(BuildContext context) {
    const items = [
      (AppSettings.fontStandard, '标准', 1.0),
      (AppSettings.fontLarge, '大', 1.15),
      (AppSettings.fontXLarge, '特大', 1.30),
    ];
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('字体大小',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            const Text('调整后全站文字立即生效，只影响本机',
                style: TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
            const SizedBox(height: 14),
            for (final it in items)
              InkWell(
                onTap: () => Navigator.pop(context, it.$1),
                borderRadius: BorderRadius.circular(10),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 11),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(it.$2,
                            style: TextStyle(
                                fontSize: 14.5 * (1 + (it.$3 - 1) * 0.5),
                                fontWeight: FontWeight.w600)),
                      ),
                      Text('${(it.$3 * 100).round()}%',
                          style: const TextStyle(
                              fontSize: 12, color: AppTheme.textTertiary)),
                      const SizedBox(width: 8),
                      Icon(
                        current == it.$1
                            ? Icons.radio_button_checked
                            : Icons.radio_button_unchecked,
                        size: 19,
                        color: current == it.$1
                            ? AppTheme.primary
                            : AppTheme.textTertiary,
                      ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 6),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.primarySoft,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppTheme.primaryBorder),
              ),
              child: Text(
                '预览：今天气压稳、风小，用红虫拉饵，狂口！',
                style: TextStyle(
                  fontSize: 14 * 1.0,
                  height: 1.5,
                  color: AppTheme.textSecondary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════ 鱼获隐私 ══════════════════════

class _CatchPrivacySheet extends StatefulWidget {
  const _CatchPrivacySheet({required this.current});
  final bool current;

  @override
  State<_CatchPrivacySheet> createState() => _CatchPrivacySheetState();
}

class _CatchPrivacySheetState extends State<_CatchPrivacySheet> {
  late bool _v = widget.current;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('鱼获隐私',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            Row(
              children: [
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('发布渔获时默认公开钓点',
                          style: TextStyle(
                              fontSize: 14.5, fontWeight: FontWeight.w600)),
                      SizedBox(height: 2),
                      Text('关闭后每次发布默认选「不公开」\n别人看不到你的具体钓点与坐标',
                          style: TextStyle(
                              fontSize: 11.5,
                              height: 1.5,
                              color: AppTheme.textTertiary)),
                    ],
                  ),
                ),
                Switch(
                  value: _v,
                  onChanged: (x) => setState(() => _v = x),
                  activeTrackColor: AppTheme.primary,
                  activeColor: AppTheme.accent,
                ),
              ],
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context, _v),
                child: const Text('保存'),
              ),
            ),
            const SizedBox(height: 6),
            const Text('这一项只改默认值，单条渔获发布时仍可以单独调整',
                style: TextStyle(fontSize: 11, color: AppTheme.textTertiary)),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════ 联系客服 ══════════════════════

class _SupportSheet extends StatelessWidget {
  const _SupportSheet({required this.info});
  final SupportInfo info;

  @override
  Widget build(BuildContext context) {
    final phone = info.phone.isEmpty ? '400-000-0000' : info.phone;
    final wechat = info.wechat.isEmpty ? 'yubao_kefu' : info.wechat;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('联系客服',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(
              info.hours.isEmpty ? '每日 09:00 - 21:00' : info.hours,
              style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 16),
            _line(
              context,
              icon: Icons.call_outlined,
              title: '客服电话',
              value: phone,
              onTap: () async {
                final uri = Uri.parse('tel:${phone.replaceAll('-', '')}');
                if (!await launchUrl(uri)) {
                  await Clipboard.setData(ClipboardData(text: phone));
                  if (context.mounted) {
                    CenterToast.show(context, '已复制客服电话：$phone');
                  }
                }
              },
            ),
            const SizedBox(height: 10),
            _line(
              context,
              icon: Icons.chat_outlined,
              title: '客服微信',
              value: wechat,
              onTap: () async {
                await Clipboard.setData(ClipboardData(text: wechat));
                if (context.mounted) {
                  CenterToast.show(context, '已复制微信号：$wechat，去微信添加好友',
                      icon: Icons.copy_rounded);
                }
              },
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.primarySoft,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppTheme.primaryBorder),
              ),
              child: const Text(
                '· 账号、支付、会员权益问题建议直接联系客服，处理更快\n'
                '· 反馈 Bug 时请说明机型与系统版本，方便定位',
                style: TextStyle(
                    fontSize: 11.5, height: 1.6, color: AppTheme.textSecondary),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _line(BuildContext context,
      {required IconData icon,
      required String title,
      required String value,
      required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppTheme.border),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: AppTheme.textPrimary),
            const SizedBox(width: 10),
            Text(title,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
            const Spacer(),
            Text(value,
                style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary)),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right_rounded,
                size: 18, color: AppTheme.textTertiary),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════ 输入「注销」二次确认 ══════════════════════

class _TypeToConfirmDialog extends StatefulWidget {
  @override
  State<_TypeToConfirmDialog> createState() => _TypeToConfirmDialogState();
}

class _TypeToConfirmDialogState extends State<_TypeToConfirmDialog> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ok = _ctrl.text.trim() == '注销';
    return AlertDialog(
      title: const Text('最后确认'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('请输入「注销」两个字以确认：',
              style: TextStyle(fontSize: 13.5, color: AppTheme.textSecondary)),
          const SizedBox(height: 10),
          TextField(
            controller: _ctrl,
            autofocus: true,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              hintText: '注销',
              isDense: true,
              border: OutlineInputBorder(),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
        TextButton(
          onPressed: ok ? () => Navigator.pop(context, '注销') : null,
          child: const Text('确认注销', style: TextStyle(color: AppTheme.danger)),
        ),
      ],
    );
  }
}
