import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../models/activity.dart';
import '../models/article.dart';
import '../services/content_service.dart';
import 'activity_detail_screen.dart';
import 'article_detail_screen.dart';

/// 我的发布（活动 + 文章投稿）
///
/// 投稿/发布都是一律进「待审核」，用户需要能回来看进度：
/// 待审核 / 已通过 / 未通过（带后台填的拒绝原因）。
class MySubmissionsScreen extends StatefulWidget {
  /// 0 = 活动，1 = 文章
  final int initialTab;
  const MySubmissionsScreen({super.key, this.initialTab = 0});

  @override
  State<MySubmissionsScreen> createState() => _MySubmissionsScreenState();
}

class _MySubmissionsScreenState extends State<MySubmissionsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab =
      TabController(length: 2, vsync: this, initialIndex: widget.initialTab);

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('我的发布'),
        bottom: TabBar(
          controller: _tab,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorColor: Colors.white,
          indicatorSize: TabBarIndicatorSize.label,
          labelStyle:
              const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          tabs: const [Tab(text: '我发布的活动'), Tab(text: '我投稿的文章')],
        ),
      ),
      body: TabBarView(
        controller: _tab,
        children: const [_MyActivitiesFeed(), _MyArticlesFeed()],
      ),
    );
  }
}

// ------------------------------------------------------------ 活动

class _MyActivitiesFeed extends StatefulWidget {
  const _MyActivitiesFeed();

  @override
  State<_MyActivitiesFeed> createState() => _MyActivitiesFeedState();
}

class _MyActivitiesFeedState extends State<_MyActivitiesFeed>
    with AutomaticKeepAliveClientMixin {
  List<Activity> _list = const [];
  bool _loading = true;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final list = await ContentService.fetchMyActivities();
    if (!mounted) return;
    setState(() {
      _list = list;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return _FeedShell(
      loading: _loading,
      empty: _list.isEmpty,
      emptyIcon: Icons.event_outlined,
      emptyTitle: '你还没有发布过活动',
      emptyHint: '在活动页右上角「发布」，提交后在这里看审核进度',
      onRefresh: _load,
      children: [
        for (final a in _list) ...[
          _SubmissionRow(
            title: a.title,
            status: a.status,
            statusLabel: a.statusLabel,
            rejectReason: a.rejectReason,
            meta: [a.rangeText, if (a.location.isNotEmpty) a.location]
                .where((e) => e.isNotEmpty)
                .join(' · '),
            tail: a.isApproved ? a.joinText : '',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                  builder: (_) => ActivityDetailScreen(activity: a)),
            ),
          ),
          const SizedBox(height: 10),
        ],
      ],
    );
  }
}

// ------------------------------------------------------------ 文章

class _MyArticlesFeed extends StatefulWidget {
  const _MyArticlesFeed();

  @override
  State<_MyArticlesFeed> createState() => _MyArticlesFeedState();
}

class _MyArticlesFeedState extends State<_MyArticlesFeed>
    with AutomaticKeepAliveClientMixin {
  List<Article> _list = const [];
  bool _loading = true;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final list = await ContentService.fetchMyArticles();
    if (!mounted) return;
    setState(() {
      _list = list;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return _FeedShell(
      loading: _loading,
      empty: _list.isEmpty,
      emptyIcon: Icons.menu_book_outlined,
      emptyTitle: '你还没有投过稿',
      emptyHint: '在技巧 / 路亚页右上角「投稿」，通过审核后会显示在列表里',
      onRefresh: _load,
      children: [
        for (final a in _list) ...[
          _SubmissionRow(
            title: a.title,
            status: a.status,
            statusLabel: a.statusLabel,
            rejectReason: a.rejectReason,
            meta: [a.categoryLabel, a.dateText]
                .where((e) => e.isNotEmpty)
                .join(' · '),
            tail: a.isApproved ? '${a.views} 次浏览' : '',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                  builder: (_) => ArticleDetailScreen(article: a)),
            ),
          ),
          const SizedBox(height: 10),
        ],
      ],
    );
  }
}

// ------------------------------------------------------------ 公共外壳

class _FeedShell extends StatelessWidget {
  final bool loading;
  final bool empty;
  final IconData emptyIcon;
  final String emptyTitle;
  final String emptyHint;
  final Future<void> Function() onRefresh;
  final List<Widget> children;

  const _FeedShell({
    required this.loading,
    required this.empty,
    required this.emptyIcon,
    required this.emptyTitle,
    required this.emptyHint,
    required this.onRefresh,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(strokeWidth: 2.2),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: empty
          ? ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                SizedBox(height: MediaQuery.of(context).size.height * 0.2),
                Icon(emptyIcon, size: 50, color: AppTheme.border),
                const SizedBox(height: 12),
                Center(
                  child: Text(emptyTitle,
                      style: const TextStyle(
                          fontSize: 14, color: AppTheme.textPrimary)),
                ),
                const SizedBox(height: 6),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Text(emptyHint,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontSize: 12,
                          height: 1.5,
                          color: AppTheme.textSecondary)),
                ),
              ],
            )
          : ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 24),
              children: children,
            ),
    );
  }
}

class _SubmissionRow extends StatelessWidget {
  final String title;
  final int status;
  final String statusLabel;
  final String rejectReason;
  final String meta;
  final String tail;
  final VoidCallback onTap;

  const _SubmissionRow({
    required this.title,
    required this.status,
    required this.statusLabel,
    required this.rejectReason,
    required this.meta,
    required this.tail,
    required this.onTap,
  });

  Color get _color {
    switch (status) {
      case 1:
        return AppTheme.primary;
      case 2:
        return AppTheme.danger;
      default:
        return AppTheme.warning;
    }
  }

  Color get _bg {
    switch (status) {
      case 1:
        return AppTheme.primaryLight;
      case 2:
        return AppTheme.dangerLight;
      default:
        return AppTheme.warningLight;
    }
  }

  String get _label {
    if (statusLabel.isNotEmpty) return statusLabel;
    switch (status) {
      case 1:
        return '已通过';
      case 2:
        return '未通过';
      default:
        return '待审核';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppTheme.surface,
      borderRadius: BorderRadius.circular(AppTheme.radiusMd),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppTheme.radiusMd),
            border: Border.all(color: AppTheme.divider),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 14.5,
                            height: 1.35,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.textPrimary)),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 1.5),
                    decoration: BoxDecoration(
                      color: _bg,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(_label,
                        style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: _color)),
                  ),
                ],
              ),
              if (meta.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(meta,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 11.5, color: AppTheme.textSecondary)),
              ],
              if (status == 2 && rejectReason.isNotEmpty) ...[
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppTheme.dangerLight,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text('未通过原因：$rejectReason',
                      style: const TextStyle(
                          fontSize: 11.5,
                          height: 1.4,
                          color: AppTheme.danger)),
                ),
              ],
              if (tail.isNotEmpty) ...[
                const SizedBox(height: 7),
                Row(
                  children: [
                    Icon(Icons.info_outline, size: 12, color: _color),
                    const SizedBox(width: 3),
                    Text(tail,
                        style: TextStyle(fontSize: 11, color: _color)),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
