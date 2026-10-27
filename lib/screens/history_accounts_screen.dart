import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_theme.dart';
import '../services/account_history.dart';
import '../services/api_client.dart';
import '../services/api_config.dart';
import '../services/session_provider.dart';
import '../widgets/center_toast.dart';
import '../widgets/user_avatar.dart';

/// 历史账号（设置 - 历史账号）
///
/// 「本机 30 天内登录过的账号」：数据只存在本机，不上服务器。
/// 存了登录时拿到的 token，所以点「切换」不用再输密码；
/// token 过期（90 天）时提示重新登录，不会把当前账号踢掉。
class HistoryAccountsScreen extends StatefulWidget {
  const HistoryAccountsScreen({super.key});

  @override
  State<HistoryAccountsScreen> createState() => _HistoryAccountsScreenState();
}

class _HistoryAccountsScreenState extends State<HistoryAccountsScreen> {
  List<AccountHistory> _list = [];
  bool _loading = true;
  String? _switching;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final list = await AccountHistoryStore.load();
    if (!mounted) return;
    setState(() {
      _list = list;
      _loading = false;
    });
  }

  Future<void> _switchTo(AccountHistory a) async {
    final sp = Provider.of<SessionProvider>(context, listen: false);
    if (sp.userId == a.userId) {
      CenterToast.show(context, '当前已登录该账号');
      return;
    }
    if (_switching != null) return;
    setState(() => _switching = a.userId);

    // 先用这个账号的 token 探一次：过期就提示重新登录，不动当前登录态
    final oldToken = ApiClient.token;
    ApiClient.setToken(a.token);
    var ok = false;
    try {
      if (!ApiConfig.enabled) {
        ok = true;
      } else {
        await ApiClient.get('/users/me');
        ok = true;
      }
    } catch (_) {
      ok = false;
    } finally {
      if (!ok) ApiClient.setToken(oldToken);
    }

    if (!mounted) return;
    if (!ok) {
      setState(() => _switching = null);
      CenterToast.show(context, '该账号登录已过期，请重新登录',
          icon: Icons.error_outline);
      return;
    }

    await sp.switchAccount(a.data);
    await AccountHistoryStore.remember(a.data);
    if (!mounted) return;
    setState(() => _switching = null);
    CenterToast.show(context, '已切换到 ${a.nickname}', icon: Icons.check_circle_outline);
    Navigator.of(context).popUntil((r) => r.isFirst);
  }

  Future<void> _remove(AccountHistory a) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('移除账号'),
        content: Text('从本机移除「${a.nickname}」的登录记录？\n'
            '只是不再显示在列表里，不影响账号本身。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('移除', style: TextStyle(color: AppTheme.danger)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await AccountHistoryStore.remove(a.userId);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final sp = Provider.of<SessionProvider>(context);
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('历史账号'),
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: AppTheme.textPrimary,
        titleTextStyle: const TextStyle(
            fontSize: 17, fontWeight: FontWeight.w700, color: AppTheme.textPrimary),
        iconTheme: const IconThemeData(color: AppTheme.textPrimary),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
              children: [
                if (_list.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 100),
                    child: Column(
                      children: const [
                        Icon(Icons.history_toggle_off_rounded,
                            size: 54, color: AppTheme.textTertiary),
                        SizedBox(height: 12),
                        Text('本机还没有登录记录',
                            style: TextStyle(
                                fontSize: 14, color: AppTheme.textSecondary)),
                        SizedBox(height: 6),
                        Text('登录过的账号会在这里保留 30 天，方便快速切换',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                fontSize: 12, color: AppTheme.textTertiary)),
                      ],
                    ),
                  )
                else ...[
                  for (final a in _list) ...[
                    _card(a, current: sp.userId == a.userId),
                    const SizedBox(height: 10),
                  ],
                  const Padding(
                    padding: EdgeInsets.fromLTRB(6, 6, 6, 0),
                    child: Text(
                      '· 记录只保存在本机，不会上传服务器\n'
                      '· 超过 30 天未登录的账号会自动从列表移除\n'
                      '· 移除记录不会退出该账号，也不会删除账号数据',
                      style: TextStyle(
                          fontSize: 11.5, height: 1.7, color: AppTheme.textTertiary),
                    ),
                  ),
                ],
              ],
            ),
    );
  }

  Widget _card(AccountHistory a, {required bool current}) {
    final busy = _switching == a.userId;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 11, 8, 11),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        border: Border.all(
            color: current ? AppTheme.primary : AppTheme.divider,
            width: current ? 1.4 : 1),
      ),
      child: Row(
        children: [
          UserAvatar(
            url: ApiConfig.mediaUrl(a.avatar),
            userId: a.userId,
            radius: 21,
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(a.nickname,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 14.5, fontWeight: FontWeight.w700)),
                    ),
                    if (current) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppTheme.accentLight,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text('当前',
                            style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: AppTheme.accentDark)),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 3),
                Text('${a.maskedPhone} · ${a.lastText}',
                    style: const TextStyle(
                        fontSize: 11.5, color: AppTheme.textTertiary)),
              ],
            ),
          ),
          if (busy)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 14),
              child: SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else if (!current)
            TextButton(
              onPressed: () => _switchTo(a),
              style: TextButton.styleFrom(
                  minimumSize: const Size(0, 34),
                  padding: const EdgeInsets.symmetric(horizontal: 8)),
              child: const Text('切换', style: TextStyle(fontSize: 13)),
            ),
          IconButton(
            onPressed: () => _remove(a),
            icon: const Icon(Icons.close_rounded, size: 17),
            color: AppTheme.textTertiary,
            tooltip: '移除记录',
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }
}
