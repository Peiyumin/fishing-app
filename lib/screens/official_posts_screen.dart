import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../models/official.dart';
import '../services/api_client.dart';
import '../services/official_service.dart';
import '../widgets/app_refresh.dart';
import '../widgets/center_toast.dart';

/// 帖子管理（官方工作台）
///
/// 和后台「动态审核」用同一套字段：deleted 软删除（作者和用户都看不到，
/// 后台还能恢复）、pinned 置顶。官方账号在这里能做的三件事就是
/// 删除 / 恢复 / 置顶 —— 不能动其他官方账号和管理员发的内容，
/// 这种行 [OfficialPost.canManage] 是 false，菜单直接不画。
class OfficialPostsScreen extends StatefulWidget {
  const OfficialPostsScreen({super.key});

  @override
  State<OfficialPostsScreen> createState() => _OfficialPostsScreenState();
}

class _OfficialPostsScreenState extends State<OfficialPostsScreen> {
  final TextEditingController _kw = TextEditingController();
  List<OfficialPost> _list = [];
  String _show = 'normal';
  int _page = 1;
  bool _loading = true;
  bool _loadingMore = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _kw.dispose();
    super.dispose();
  }

  Future<void> _load({bool more = false}) async {
    if (more) {
      setState(() => _loadingMore = true);
    } else {
      setState(() {
        _page = 1;
        _loading = _list.isEmpty;
      });
    }
    try {
      final list = await OfficialService.posts(
        keyword: _kw.text.trim(),
        show: _show,
        page: more ? _page + 1 : 1,
      );
      if (!mounted) return;
      setState(() {
        if (more) {
          _page += 1;
          _list = [..._list, ...list];
        } else {
          _list = list;
        }
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      final net = ApiClient.asNetError(e);
      setState(() => _error = net != null
          ? '网络不太好，请稍后再试'
          : (e is ApiException ? e.message : '加载失败：$e'));
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _loadingMore = false;
        });
      }
    }
  }

  Future<void> _act(OfficialPost p, String action) async {
    final label = switch (action) {
      'delete' => '删除',
      'restore' => '恢复',
      'pin' => '置顶',
      _ => '取消置顶',
    };
    if (action == 'delete') {
      final ok = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('删除这条动态？'),
          content: Text('「${p.displayTitle}」会被下架，作者和所有用户都看不到了；'
              '误删可以在这里的「已删除」里恢复。'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('删除', style: TextStyle(color: AppTheme.danger)),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }
    try {
      await OfficialService.postAction(p.id, action);
      if (!mounted) return;
      CenterToast.show(context, '已$label', icon: Icons.check_circle_outline);
      _load();
    } catch (e) {
      if (!mounted) return;
      final net = ApiClient.asNetError(e);
      CenterToast.show(context,
          net != null ? '网络不太好，请稍后再试' : (e is ApiException ? e.message : '操作失败'));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(title: const Text('帖子管理'), elevation: 0),
      body: Column(
        children: [
          _searchBar(),
          _filterBar(),
          Expanded(
            child: AppRefresh(
              onRefresh: _load,
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
                      itemCount: _list.length + 1,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (_, i) {
                        if (i == _list.length) return _footer();
                        return _card(_list[i]);
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _searchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
      child: Container(
        height: 38,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(19),
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
                onSubmitted: (_) => _load(),
                style: const TextStyle(fontSize: 13),
                decoration: const InputDecoration(
                  isDense: true,
                  hintText: '搜标题、正文或作者昵称',
                  hintStyle: TextStyle(fontSize: 12.5, color: AppTheme.textTertiary),
                  border: InputBorder.none,
                ),
              ),
            ),
            if (_kw.text.isNotEmpty)
              GestureDetector(
                onTap: () {
                  _kw.clear();
                  _load();
                },
                child: const Icon(Icons.close, size: 15, color: AppTheme.textTertiary),
              ),
          ],
        ),
      ),
    );
  }

  Widget _filterBar() {
    final chips = [
      ('normal', '正常'),
      ('deleted', '已删除'),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 2, 12, 8),
      child: Row(
        children: [
          for (final c in chips)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: GestureDetector(
                onTap: () {
                  if (_show == c.$1) return;
                  setState(() => _show = c.$1);
                  _load();
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 6),
                  decoration: BoxDecoration(
                    color: _show == c.$1 ? AppTheme.primary : AppTheme.surface,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(
                    c.$2,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: _show == c.$1 ? Colors.white : AppTheme.textSecondary,
                    ),
                  ),
                ),
              ),
            ),
          const Spacer(),
          Text('${_list.length} 条',
              style: const TextStyle(fontSize: 11, color: AppTheme.textTertiary)),
        ],
      ),
    );
  }

  Widget _card(OfficialPost p) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 10, 6, 10),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        boxShadow: AppTheme.lightShadow,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _thumb(p),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (p.notice) ...[
                      _tag('公告', AppTheme.starLight, AppTheme.starDark),
                      const SizedBox(width: 5),
                    ],
                    if (p.pinned && !p.notice) ...[
                      _tag('置顶', AppTheme.accentLight, AppTheme.accentDark),
                      const SizedBox(width: 5),
                    ],
                    if (p.deleted) _tag('已删除', AppTheme.dangerLight, AppTheme.dangerDark),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  p.displayTitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    height: 1.35,
                    color: p.deleted ? AppTheme.textTertiary : AppTheme.textPrimary,
                    decoration: p.deleted ? TextDecoration.lineThrough : null,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  '${p.authorName} · ${officialTimeOf(p.createdAt)} · '
                  '${p.likeCount} 赞 ${p.commentCount} 评论',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 10.5, color: AppTheme.textTertiary),
                ),
              ],
            ),
          ),
          _menu(p),
        ],
      ),
    );
  }

  Widget _thumb(OfficialPost p) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 58,
        height: 58,
        color: AppTheme.primarySoft,
        child: p.cover == null
            ? const Icon(Icons.image_outlined, size: 20, color: AppTheme.textTertiary)
            : Image.network(
                p.cover!,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) =>
                    const Icon(Icons.broken_image, size: 18, color: AppTheme.textTertiary),
              ),
      ),
    );
  }

  Widget _tag(String text, Color bg, Color fg) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(4)),
        child: Text(text,
            style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700, color: fg)),
      );

  Widget _menu(OfficialPost p) {
    if (!p.canManage) {
      return const Padding(
        padding: EdgeInsets.only(right: 6, top: 4),
        child: Text('无权限',
            style: TextStyle(fontSize: 10.5, color: AppTheme.textTertiary)),
      );
    }
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert, size: 18, color: AppTheme.textTertiary),
      padding: EdgeInsets.zero,
      onSelected: (v) => _act(p, v),
      itemBuilder: (_) => [
        if (p.deleted)
          const PopupMenuItem(value: 'restore', height: 40, child: Text('恢复这条动态', style: TextStyle(fontSize: 13)))
        else ...[
          PopupMenuItem(
            value: p.pinned ? 'unpin' : 'pin',
            height: 40,
            child: Text(p.pinned ? '取消置顶' : '置顶',
                style: const TextStyle(fontSize: 13)),
          ),
          const PopupMenuItem(
            value: 'delete',
            height: 40,
            child: Text('删除',
                style: TextStyle(fontSize: 13, color: AppTheme.danger)),
          ),
        ],
      ],
    );
  }

  Widget _footer() {
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 18),
        child: Center(
          child: Text(_error!,
              style: const TextStyle(fontSize: 12, color: AppTheme.danger)),
        ),
      );
    }
    if (_loadingMore) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 18),
        child: Center(
          child: SizedBox(
              width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
        ),
      );
    }
    // 一次 20 条：刚好满 20 说明后面可能还有，给一个「继续加载」
    if (_list.length >= 20) {
      return TextButton(
        onPressed: () => _load(more: true),
        child: const Text('加载更多', style: TextStyle(fontSize: 12.5)),
      );
    }
    if (_list.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 40),
        child: Center(
          child: Text('没有符合条件的动态',
              style: TextStyle(fontSize: 12.5, color: AppTheme.textTertiary)),
        ),
      );
    }
    return const SizedBox(height: 8);
  }
}
