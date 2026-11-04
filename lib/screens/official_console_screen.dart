import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../models/official.dart';
import '../services/api_client.dart';
import '../services/official_service.dart';
import '../widgets/app_refresh.dart';
import '../widgets/center_toast.dart';
import '../widgets/official_badge.dart';
import 'notice_editor_screen.dart';
import 'official_posts_screen.dart';
import 'official_spots_screen.dart';
import 'official_users_screen.dart';

/// 官方工作台（v40 起，v41 加了钓点管理）
///
/// 只有被后台设为「官方」的账号能从「我的」页进来。进来之后四件事都在这里：
///   ① 发公告 —— 进「消息 → 系统通知」，不再占信息流，可配 9 张图；
///   ② 管帖子 —— 删除 / 恢复 / 置顶别人的动态；
///   ③ 管钓点 —— 全站钓点都能改：名称、类型、简介、地址、鱼种、标签、电话、
///              经纬度（地图重选）、封面与图集、上架/下架；
///   ④ 封账号 —— 1 天 / 7 天 / 30 天 / 永久，必须写原因。
///
/// 权限全部由后端判定，这里只负责「把不能做的按钮画灰」——
/// 就算有人改了包，接口那一层也会拒。
class OfficialConsoleScreen extends StatefulWidget {
  const OfficialConsoleScreen({super.key});

  @override
  State<OfficialConsoleScreen> createState() => _OfficialConsoleScreenState();
}

class _OfficialConsoleScreenState extends State<OfficialConsoleScreen> {
  OfficialOverview _overview = const OfficialOverview();
  List<OfficialNotice> _notices = [];
  List<OfficialLog> _logs = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = _notices.isEmpty && _overview.postCount == 0);
    try {
      final results = await Future.wait([
        OfficialService.overview(),
        OfficialService.notices(),
        OfficialService.logs(),
      ]);
      if (!mounted) return;
      setState(() {
        _overview = results[0] as OfficialOverview;
        _notices = results[1] as List<OfficialNotice>;
        _logs = results[2] as List<OfficialLog>;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = _humanError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// 把异常翻成人话。404 单独处理：那不是网络问题，是后台还没传 v40 升级包。
  String _humanError(Object e) {
    if (ApiClient.asNetError(e) != null) return '网络不太好，请稍后再试';
    if (e is ApiException) {
      if (e.status == 404) return '后台还没升级到 v40，官方工作台的接口还不存在';
      return e.message;
    }
    return '加载失败：$e';
  }

  Future<void> _openEditor([OfficialNotice? notice]) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => NoticeEditorScreen(notice: notice)),
    );
    if (saved == true && mounted) _load();
  }

  Future<void> _deleteNotice(OfficialNotice n) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('撤回这条公告？'),
        content: Text('「${n.title}」会从所有用户的列表里消失，后台仍可恢复。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('再想想')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('撤回', style: TextStyle(color: AppTheme.danger)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await OfficialService.deleteNotice(n.id);
      if (!mounted) return;
      CenterToast.show(context, '已撤回', icon: Icons.check_circle_outline);
      _load();
    } catch (e) {
      if (mounted) CenterToast.show(context, _humanError(e));
    }
  }

  Future<void> _togglePin(OfficialNotice n) async {
    try {
      await OfficialService.pinNotice(n.id, pinned: !n.pinned);
      if (!mounted) return;
      CenterToast.show(context, n.pinned ? '已取消置顶' : '已置顶');
      _load();
    } catch (e) {
      if (mounted) CenterToast.show(context, _humanError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('官方工作台'),
        elevation: 0,
        actions: [
          IconButton(
            tooltip: '刷新',
            icon: const Icon(Icons.refresh, size: 20),
            onPressed: _load,
          ),
        ],
      ),
      body: AppRefresh(
        onRefresh: _load,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 28),
                children: [
                  if (_error != null) _errorCard(_error!),
                  _statCard(),
                  const SizedBox(height: 10),
                  _publishCard(),
                  const SizedBox(height: 10),
                  _entryRow(),
                  const SizedBox(height: 10),
                  _spotEntry(),
                  const SizedBox(height: 10),
                  _noticeSection(),
                  const SizedBox(height: 10),
                  _logSection(),
                ],
              ),
      ),
    );
  }

  Widget _errorCard(String msg) => Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppTheme.dangerLight,
          borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        ),
        child: Row(
          children: [
            const Icon(Icons.error_outline, size: 18, color: AppTheme.danger),
            const SizedBox(width: 8),
            Expanded(
              child: Text(msg,
                  style: const TextStyle(fontSize: 12.5, color: AppTheme.dangerDark)),
            ),
          ],
        ),
      );

  Widget _statCard() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
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
              const OfficialAvatarGlyph(size: 34),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            _overview.nickname.isEmpty ? '官方账号' : _overview.nickname,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 15.5, fontWeight: FontWeight.w700),
                          ),
                        ),
                        const SizedBox(width: 5),
                        const OfficialBadge(height: 15),
                      ],
                    ),
                    const SizedBox(height: 3),
                    const Text('你发的公告、处理过的帖子都会留痕，操作记录互相可见',
                        style: TextStyle(fontSize: 11, color: AppTheme.textSecondary)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _statCell('${_overview.noticeCount}', '我的公告'),
              _statCell('${_overview.todayCount}', '今日动态'),
              _statCell('${_overview.postCount}', '全站动态'),
              _statCell('${_overview.bannedCount}', '封禁中'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statCell(String value, String label) => Expanded(
        child: Column(
          children: [
            Text(value,
                style: const TextStyle(
                    fontSize: 19, fontWeight: FontWeight.w800, height: 1.1)),
            const SizedBox(height: 3),
            Text(label,
                style: const TextStyle(fontSize: 10.5, color: AppTheme.textSecondary)),
          ],
        ),
      );

  Widget _publishCard() {
    return InkWell(
      onTap: () => _openEditor(),
      borderRadius: BorderRadius.circular(AppTheme.radiusMd),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 13, 12, 13),
        decoration: BoxDecoration(
          color: AppTheme.primary,
          borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        ),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: AppTheme.accent.withOpacity(0.18),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.campaign_outlined, size: 19, color: AppTheme.accent),
            ),
            const SizedBox(width: 10),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('发布公告',
                      style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700,
                          color: Colors.white)),
                  SizedBox(height: 2),
                  Text('发到「消息-系统通知」，不进钓友动态；可配 9 张图',
                      style: TextStyle(fontSize: 11, color: Colors.white70)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, size: 18, color: Colors.white54),
          ],
        ),
      ),
    );
  }

  /// 钓点管理入口（v41）
  ///
  /// 单独一整行而不是挤进上面那两格：批量导入的钓点量最大（线上 155 条），
  /// 官方最常要改的就是它 —— 名字打错、定位偏了、一张图都没有。
  Widget _spotEntry() {
    return InkWell(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const OfficialSpotsScreen()),
      ),
      borderRadius: BorderRadius.circular(AppTheme.radiusMd),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 13, 12, 13),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(AppTheme.radiusMd),
          boxShadow: AppTheme.lightShadow,
        ),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: AppTheme.primaryLight,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.place_outlined,
                  size: 19, color: AppTheme.primary),
            ),
            const SizedBox(width: 10),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('钓点管理',
                      style: TextStyle(
                          fontSize: 13.5, fontWeight: FontWeight.w700)),
                  SizedBox(height: 2),
                  Text('改名称 · 加图片 · 重新定位 · 上架下架',
                      style: TextStyle(
                          fontSize: 10.5, color: AppTheme.textSecondary)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, size: 17, color: AppTheme.textTertiary),
          ],
        ),
      ),
    );
  }

  Widget _entryRow() {
    return Row(
      children: [
        Expanded(
          child: _entry(
            icon: Icons.article_outlined,
            title: '帖子管理',
            subtitle: '删除 · 恢复 · 置顶',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const OfficialPostsScreen()),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _entry(
            icon: Icons.person_off_outlined,
            title: '用户管理',
            subtitle: '搜索 · 封禁 · 解封',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const OfficialUsersScreen()),
            ),
          ),
        ),
      ],
    );
  }

  Widget _entry({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppTheme.radiusMd),
      child: Container(
        padding: const EdgeInsets.fromLTRB(13, 13, 13, 13),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(AppTheme.radiusMd),
          boxShadow: AppTheme.lightShadow,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 20, color: AppTheme.primary),
            const SizedBox(height: 9),
            Text(title,
                style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
            const SizedBox(height: 3),
            Text(subtitle,
                style: const TextStyle(fontSize: 10.5, color: AppTheme.textSecondary)),
          ],
        ),
      ),
    );
  }

  Widget _noticeSection() {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 13, 14, 6),
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
              const Text('公告',
                  style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
              const SizedBox(width: 6),
              Text('${_notices.length} 条',
                  style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary)),
              const Spacer(),
              TextButton(
                onPressed: () => _openEditor(),
                style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    minimumSize: const Size(0, 28)),
                child: const Text('写一条', style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
          if (_notices.isEmpty)
            const Padding(
              padding: EdgeInsets.only(bottom: 12, top: 2),
              child: Text('还没有发布过公告。服务器维护、规则调整这类事情，用公告说最直接。',
                  style: TextStyle(fontSize: 11.5, color: AppTheme.textSecondary)),
            )
          else
            ..._notices.take(4).map(_noticeRow),
        ],
      ),
    );
  }

  Widget _noticeRow(OfficialNotice n) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (n.pinned) ...[
                const Icon(Icons.push_pin, size: 12, color: AppTheme.starDark),
                const SizedBox(width: 3),
              ],
              Expanded(
                child: Text(n.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
              ),
              if (n.isMine) ...[
                IconButton(
                  tooltip: n.pinned ? '取消置顶' : '置顶',
                  visualDensity: VisualDensity.compact,
                  constraints: const BoxConstraints(minWidth: 30, minHeight: 28),
                  padding: EdgeInsets.zero,
                  icon: Icon(
                    n.pinned ? Icons.push_pin : Icons.push_pin_outlined,
                    size: 15,
                    color: AppTheme.textTertiary,
                  ),
                  onPressed: () => _togglePin(n),
                ),
                IconButton(
                  tooltip: '撤回',
                  visualDensity: VisualDensity.compact,
                  constraints: const BoxConstraints(minWidth: 30, minHeight: 28),
                  padding: EdgeInsets.zero,
                  icon: const Icon(Icons.delete_outline,
                      size: 16, color: AppTheme.textTertiary),
                  onPressed: () => _deleteNotice(n),
                ),
              ],
            ],
          ),
          const SizedBox(height: 2),
          Row(
            children: [
              Flexible(
                child: Text('${n.authorName} · ${officialTimeOf(n.createdAt)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 10.5, color: AppTheme.textTertiary)),
              ),
              if (n.images.isNotEmpty) ...[
                const SizedBox(width: 6),
                const Icon(Icons.image_outlined,
                    size: 11, color: AppTheme.textTertiary),
                const SizedBox(width: 2),
                Text('${n.images.length}',
                    style: const TextStyle(
                        fontSize: 10.5, color: AppTheme.textTertiary)),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _logSection() {
    final shown = _logs.take(6).toList();
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 13, 14, 12),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        boxShadow: AppTheme.lightShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('操作记录',
              style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          if (shown.isEmpty)
            const Text('还没有操作记录。',
                style: TextStyle(fontSize: 11.5, color: AppTheme.textSecondary))
          else
            for (final l in shown)
              Padding(
                padding: const EdgeInsets.only(bottom: 7),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      margin: const EdgeInsets.only(top: 5),
                      width: 5,
                      height: 5,
                      decoration: const BoxDecoration(
                          color: AppTheme.textTertiary, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      // 用 Text.rich 而不是 RichText：前者会合并 DefaultTextStyle
                      // （字体、行高、无障碍字号缩放都跟着主题走）
                      child: Text.rich(
                        TextSpan(
                          style: const TextStyle(
                              fontSize: 11.5, color: AppTheme.textSecondary, height: 1.35),
                          children: [
                            TextSpan(
                              text: l.actorName.isEmpty ? '官方' : l.actorName,
                              style: const TextStyle(
                                  color: AppTheme.textPrimary,
                                  fontWeight: FontWeight.w600),
                            ),
                            TextSpan(text: ' ${l.actionLabel}'),
                            if (l.note.isNotEmpty)
                              TextSpan(
                                text: '：${l.note}',
                                style: const TextStyle(color: AppTheme.textTertiary),
                              ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(officialTimeOf(l.createdAt),
                        style: const TextStyle(
                            fontSize: 10, color: AppTheme.textTertiary)),
                  ],
                ),
              ),
        ],
      ),
    );
  }
}
