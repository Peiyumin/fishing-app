import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../models/official.dart';
import '../services/api_client.dart';
import '../services/official_service.dart';
import '../widgets/center_toast.dart';
import '../widgets/official_badge.dart';
import '../widgets/user_avatar.dart';

/// 用户管理（官方工作台）
///
/// 必须先搜索再操作 —— 不做「全站用户列表」：官方账号用来处理具体举报，
/// 不需要把所有人的手机号翻一遍（后端也只会回脱敏后的号码）。
///
/// 封禁是写 users.banned + 到期时间 + 原因，和后台「禁用账号」同一组字段：
/// 后台解封这里立刻生效，反之亦然。封禁成功会顺手删掉该用户的登录 token，
/// 他手上的旧 token 立刻失效，不能继续发帖。
class OfficialUsersScreen extends StatefulWidget {
  const OfficialUsersScreen({super.key});

  @override
  State<OfficialUsersScreen> createState() => _OfficialUsersScreenState();
}

class _OfficialUsersScreenState extends State<OfficialUsersScreen> {
  final TextEditingController _kw = TextEditingController();
  List<OfficialUser> _list = [];
  bool _loading = false;
  bool _searched = false;
  String? _error;

  @override
  void dispose() {
    _kw.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final kw = _kw.text.trim();
    if (kw.isEmpty) {
      CenterToast.show(context, '请输入昵称、手机号或用户 ID', icon: Icons.search);
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await OfficialService.users(kw);
      if (!mounted) return;
      setState(() {
        _list = list;
        _searched = true;
      });
    } catch (e) {
      if (!mounted) return;
      final net = ApiClient.asNetError(e);
      setState(() => _error = net != null
          ? '网络不太好，请稍后再试'
          : (e is ApiException ? e.message : '搜索失败：$e'));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _ban(OfficialUser u) async {
    final picked = await showModalBottomSheet<_BanPick>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppTheme.radiusLg)),
      ),
      builder: (_) => _BanSheet(user: u),
    );
    if (picked == null) return;
    try {
      await OfficialService.ban(u.id, days: picked.days, reason: picked.reason);
      if (!mounted) return;
      CenterToast.show(context,
          picked.days == 0 ? '已永久封禁「${u.nickname}」' : '已封禁 ${picked.days} 天',
          icon: Icons.check_circle_outline);
      _search();
    } catch (e) {
      if (!mounted) return;
      final net = ApiClient.asNetError(e);
      CenterToast.show(context,
          net != null ? '网络不太好，请稍后再试' : (e is ApiException ? e.message : '封禁失败'));
    }
  }

  Future<void> _unban(OfficialUser u) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('解除封禁？'),
        content: Text('「${u.nickname}」可以立刻重新登录并发布内容。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('解除封禁'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await OfficialService.unban(u.id);
      if (!mounted) return;
      CenterToast.show(context, '已解除封禁', icon: Icons.check_circle_outline);
      _search();
    } catch (e) {
      if (!mounted) return;
      final net = ApiClient.asNetError(e);
      CenterToast.show(context,
          net != null ? '网络不太好，请稍后再试' : (e is ApiException ? e.message : '解封失败'));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(title: const Text('用户管理'), elevation: 0),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    height: 40,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: AppTheme.surface,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: AppTheme.lightShadow,
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.search, size: 17, color: AppTheme.textTertiary),
                        const SizedBox(width: 6),
                        Expanded(
                          child: TextField(
                            controller: _kw,
                            textInputAction: TextInputAction.search,
                            onSubmitted: (_) => _search(),
                            style: const TextStyle(fontSize: 13),
                            decoration: const InputDecoration(
                              isDense: true,
                              hintText: '昵称 / 手机号 / 用户 ID',
                              hintStyle:
                                  TextStyle(fontSize: 12.5, color: AppTheme.textTertiary),
                              border: InputBorder.none,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  height: 40,
                  child: ElevatedButton(
                    onPressed: _loading ? null : _search,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 18),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20)),
                    ),
                    child: _loading
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Text('搜索', style: TextStyle(fontSize: 13)),
                  ),
                ),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Row(
              children: [
                Icon(Icons.info_outline, size: 13, color: AppTheme.textTertiary),
                SizedBox(width: 5),
                Expanded(
                  child: Text(
                    '封禁后该用户立刻掉线，登录会被拦下并看到封禁原因；到期自动解封。',
                    style: TextStyle(fontSize: 11, color: AppTheme.textTertiary),
                  ),
                ),
              ],
            ),
          ),
          Expanded(child: _body()),
        ],
      ),
    );
  }

  Widget _body() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 30),
          child: Text(_error!,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12.5, color: AppTheme.danger)),
        ),
      );
    }
    if (!_searched) {
      return const Center(
        child: Text('输入昵称、手机号或用户 ID 后搜索',
            style: TextStyle(fontSize: 12.5, color: AppTheme.textTertiary)),
      );
    }
    if (_list.isEmpty) {
      return const Center(
        child: Text('没找到这个用户',
            style: TextStyle(fontSize: 12.5, color: AppTheme.textTertiary)),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
      itemCount: _list.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) => _card(_list[i]),
    );
  }

  Widget _card(OfficialUser u) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        boxShadow: AppTheme.lightShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              UserAvatar(
                url: u.avatar,
                userId: u.id,
                radius: 17,
                official: u.official,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(u.nickname,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 13.5, fontWeight: FontWeight.w700)),
                        ),
                        if (u.official) ...[
                          const SizedBox(width: 4),
                          const OfficialBadge(height: 13),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${u.phoneMasked.isEmpty ? '未绑定手机号' : u.phoneMasked}'
                      ' · ${u.postCount} 条动态 · 注册于 ${officialTimeOf(u.createdAt)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          const TextStyle(fontSize: 10.5, color: AppTheme.textTertiary),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _actionButton(u),
            ],
          ),
          if (u.banned) ...[
            const SizedBox(height: 9),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
              decoration: BoxDecoration(
                color: AppTheme.dangerLight,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.block, size: 13, color: AppTheme.danger),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(u.banLabel,
                        style: const TextStyle(
                            fontSize: 11, color: AppTheme.dangerDark, height: 1.3)),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _actionButton(OfficialUser u) {
    if (!u.canManage) {
      return const Text('不可操作',
          style: TextStyle(fontSize: 11, color: AppTheme.textTertiary));
    }
    final banning = !u.banned;
    return SizedBox(
      height: 30,
      child: OutlinedButton(
        onPressed: () => banning ? _ban(u) : _unban(u),
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          foregroundColor: banning ? AppTheme.danger : AppTheme.primary,
          side: BorderSide(
              color: banning ? AppTheme.danger.withOpacity(0.4) : AppTheme.border),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        ),
        child: Text(banning ? '封禁' : '解封', style: const TextStyle(fontSize: 12)),
      ),
    );
  }
}

/// 封禁弹窗选出的结果
class _BanPick {
  final int days; // 0 = 永久
  final String reason;
  const _BanPick(this.days, this.reason);
}

/// 封禁底部弹窗：选时长 + 填原因，两个都填了才能提交
class _BanSheet extends StatefulWidget {
  final OfficialUser user;
  const _BanSheet({required this.user});

  @override
  State<_BanSheet> createState() => _BanSheetState();
}

class _BanSheetState extends State<_BanSheet> {
  final TextEditingController _reason = TextEditingController();
  int _days = 7;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  void _submit() {
    final reason = _reason.text.trim();
    if (reason.isEmpty) {
      CenterToast.show(context, '请填写封禁原因，用户会看到这句话', icon: Icons.edit_outlined);
      return;
    }
    Navigator.of(context).pop(_BanPick(_days, reason));
  }

  @override
  Widget build(BuildContext context) {
    const options = [
      (1, '1 天'),
      (7, '7 天'),
      (30, '30 天'),
      (0, '永久'),
    ];
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('封禁「${widget.user.nickname}」',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 18),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text('封禁后该用户立刻掉线，登录时会被拦下并看到下面的原因。',
              style: TextStyle(fontSize: 11.5, color: AppTheme.textSecondary)),
          const SizedBox(height: 14),
          const Text('封禁时长', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              for (final o in options)
                GestureDetector(
                  onTap: () => setState(() => _days = o.$1),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
                    decoration: BoxDecoration(
                      color: _days == o.$1 ? AppTheme.primary : AppTheme.primarySoft,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      o.$2,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: _days == o.$1 ? Colors.white : AppTheme.textSecondary,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          const Text('封禁原因', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          TextField(
            controller: _reason,
            maxLength: 60,
            maxLines: 2,
            minLines: 1,
            style: const TextStyle(fontSize: 13),
            decoration: InputDecoration(
              hintText: '例如：多次发布广告 / 恶意刷屏',
              hintStyle: const TextStyle(fontSize: 12.5, color: AppTheme.textTertiary),
              filled: true,
              fillColor: AppTheme.primarySoft,
              counterStyle:
                  const TextStyle(fontSize: 10.5, color: AppTheme.textTertiary),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            height: 44,
            child: ElevatedButton(
              onPressed: _submit,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.danger,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: Text(_days == 0 ? '永久封禁' : '封禁 $_days 天',
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
    );
  }
}
