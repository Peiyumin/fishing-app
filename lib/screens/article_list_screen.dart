import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../models/article.dart';
import '../services/content_service.dart';
import 'article_detail_screen.dart';
import 'my_submissions_screen.dart';
import 'publish_article_screen.dart';
import '../widgets/app_refresh.dart';

/// 文章频道定义
class ArticleTab {
  final String label;
  final String category;
  const ArticleTab(this.label, this.category);
}

/// 文章列表页（首页「技巧」入口，也供「路亚」页内嵌复用）
///
/// 单分类时直接铺列表；多分类时顶部出现页签。
/// 顶部右上角可投稿，投稿后进后台审核，通过才出现在这里。
class ArticleListScreen extends StatefulWidget {
  final String title;
  final List<ArticleTab> tabs;
  final bool allowPublish;

  const ArticleListScreen({
    super.key,
    required this.title,
    required this.tabs,
    this.allowPublish = true,
  });

  @override
  State<ArticleListScreen> createState() => _ArticleListScreenState();
}

class _ArticleListScreenState extends State<ArticleListScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab =
      TabController(length: widget.tabs.length, vsync: this);

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  Future<void> _openPublish() async {
    final cat = widget.tabs[_tab.index.clamp(0, widget.tabs.length - 1)].category;
    final ok = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
          builder: (_) => PublishArticleScreen(defaultCategory: cat)),
    );
    if (ok == true && mounted) {
      // 提交成功：回列表刷新，让用户看到「待审核」提示后仍能继续浏览
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final multi = widget.tabs.length > 1;
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          IconButton(
            tooltip: '我的投稿',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                  builder: (_) => const MySubmissionsScreen(initialTab: 1)),
            ),
            icon: const Icon(Icons.assignment_outlined, size: 21),
          ),
          if (widget.allowPublish)
            TextButton.icon(
              onPressed: _openPublish,
              style: TextButton.styleFrom(foregroundColor: Colors.white),
              icon: const Icon(Icons.edit_outlined, size: 18),
              label: const Text('投稿', style: TextStyle(fontSize: 13.5)),
            ),
        ],
        bottom: multi
            ? TabBar(
                controller: _tab,
                labelColor: AppTheme.primary,
                unselectedLabelColor: AppTheme.textSecondary,
                indicatorColor: AppTheme.primary,
                indicatorSize: TabBarIndicatorSize.label,
                labelStyle: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w600),
                tabs: widget.tabs.map((t) => Tab(text: t.label)).toList(),
              )
            : null,
      ),
      body: multi
          ? TabBarView(
              controller: _tab,
              children: widget.tabs
                  .map((t) => ArticleFeed(category: t.category))
                  .toList(),
            )
          : ArticleFeed(category: widget.tabs.first.category),
    );
  }
}

/// 某个分类下的文章列表（独立组件，路亚页也直接用它）
class ArticleFeed extends StatefulWidget {
  final String category;
  const ArticleFeed({super.key, required this.category});

  @override
  State<ArticleFeed> createState() => _ArticleFeedState();
}

class _ArticleFeedState extends State<ArticleFeed>
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
    // 已有文章时刷新不清空列表，避免整块消失闪白
    if (mounted) setState(() => _loading = _list.isEmpty);
    final list = await ContentService.fetchArticles(category: widget.category);
    if (!mounted) return;
    setState(() {
      _list = list;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_loading) {
      return const Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(strokeWidth: 2.2),
        ),
      );
    }
    return AppRefresh(
      onRefresh: _load,
      child: _list.isEmpty
          ? ListView(
              // 必须能滚动，否则下拉刷新在空列表上无效
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                SizedBox(height: MediaQuery.of(context).size.height * 0.22),
                const _EmptyTips(),
              ],
            )
          : ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 24),
              itemCount: _list.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (_, i) => _ArticleCard(
                article: _list[i],
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                      builder: (_) => ArticleDetailScreen(article: _list[i])),
                ),
              ),
            ),
    );
  }
}

class _EmptyTips extends StatelessWidget {
  const _EmptyTips();

  @override
  Widget build(BuildContext context) {
    return const Column(
      children: [
        Icon(Icons.menu_book_outlined, size: 52, color: AppTheme.border),
        SizedBox(height: 12),
        Text('这里还没有文章',
            style: TextStyle(fontSize: 14, color: AppTheme.textPrimary)),
        SizedBox(height: 6),
        Text('后台发布或用户投稿通过审核后会出现在这里',
            style: TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
      ],
    );
  }
}

class _ArticleCard extends StatelessWidget {
  final Article article;
  final VoidCallback onTap;
  const _ArticleCard({required this.article, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final hasCover = article.cover.isNotEmpty;
    return Material(
      color: AppTheme.surface,
      borderRadius: BorderRadius.circular(AppTheme.radiusMd),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (hasCover) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.network(
                    article.cover,
                    width: 96,
                    height: 72,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => _coverHolder(),
                  ),
                ),
                const SizedBox(width: 11),
              ] else ...[
                _coverHolder(),
                const SizedBox(width: 11),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        if (article.featured) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(
                              color: AppTheme.warningLight,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text('置顶',
                                style: TextStyle(
                                    fontSize: 9.5,
                                    color: AppTheme.warning,
                                    fontWeight: FontWeight.w700)),
                          ),
                          const SizedBox(width: 5),
                        ],
                        Expanded(
                          child: Text(article.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 14.5,
                                  height: 1.35,
                                  fontWeight: FontWeight.w600,
                                  color: AppTheme.textPrimary)),
                        ),
                      ],
                    ),
                    if (article.summary.isNotEmpty) ...[
                      const SizedBox(height: 5),
                      Text(article.summary,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 12,
                              height: 1.4,
                              color: AppTheme.textSecondary)),
                    ],
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 1.5),
                          decoration: BoxDecoration(
                            color: AppTheme.primaryLight,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(article.categoryLabel,
                              style: const TextStyle(
                                  fontSize: 9.5,
                                  color: AppTheme.primary,
                                  fontWeight: FontWeight.w600)),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            [
                              if (article.authorName.isNotEmpty)
                                article.authorName,
                              article.dateText,
                            ].join(' · '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 10.5, color: AppTheme.textSecondary),
                          ),
                        ),
                        const Icon(Icons.visibility_outlined,
                            size: 12, color: AppTheme.textSecondary),
                        const SizedBox(width: 2),
                        Text('${article.views}',
                            style: const TextStyle(
                                fontSize: 10.5, color: AppTheme.textSecondary)),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _coverHolder() {
    return Container(
      width: 96,
      height: 72,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppTheme.primaryLight, AppTheme.primarySoft],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(10),
      ),
      child: const Icon(Icons.menu_book_outlined,
          size: 24, color: AppTheme.primary),
    );
  }
}
