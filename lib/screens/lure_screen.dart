import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../models/fishing_spot.dart';
import '../services/spot_service.dart';
import 'article_list_screen.dart' show ArticleFeed;
import 'publish_article_screen.dart';
import 'spot_detail_screen.dart';
import 'spots_screen.dart';
import '../widgets/app_refresh.dart';

/// 路亚专题
///
/// 四个页签：技巧 / 装备 / 评测 / 路亚钓点
///  - 前三页复用文章列表（category = lure_skill / lure_gear / lure_review），
///    后台发布 + 用户投稿审核通过后才会出现；
///  - 第四个页签只筛 `type=路亚` 的钓点，底部可跳到地图看全部路亚点位。
class LureScreen extends StatefulWidget {
  const LureScreen({super.key});

  @override
  State<LureScreen> createState() => _LureScreenState();
}

class _LureScreenState extends State<LureScreen>
    with SingleTickerProviderStateMixin {
  static const _tabs = <_LureTab>[
    _LureTab('技巧', 'lure_skill'),
    _LureTab('装备', 'lure_gear'),
    _LureTab('评测', 'lure_review'),
    _LureTab('路亚钓点', ''),
  ];

  late final TabController _tab = TabController(length: _tabs.length, vsync: this);

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  Future<void> _openPublish() async {
    final cur = _tabs[_tab.index.clamp(0, _tabs.length - 1)];
    final cat = cur.category.isEmpty ? 'lure_skill' : cur.category;
    final ok = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => PublishArticleScreen(defaultCategory: cat)),
    );
    if (ok == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已提交，审核通过后会显示在对应分类里')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('路亚'),
        actions: [
          TextButton.icon(
            onPressed: _openPublish,
            style: TextButton.styleFrom(foregroundColor: Colors.white),
            icon: const Icon(Icons.edit_outlined, size: 17),
            label: const Text('投稿', style: TextStyle(fontSize: 13.5)),
          ),
        ],
        bottom: TabBar(
          controller: _tab,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorColor: Colors.white,
          indicatorSize: TabBarIndicatorSize.label,
          labelStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          tabs: _tabs.map((t) => Tab(text: t.label)).toList(),
        ),
      ),
      body: TabBarView(
        controller: _tab,
        children: [
          for (final t in _tabs)
            t.category.isEmpty
                ? const LureSpotsFeed()
                : ArticleFeed(category: t.category),
        ],
      ),
    );
  }
}

class _LureTab {
  final String label;
  final String category;
  const _LureTab(this.label, this.category);
}

/// 路亚钓点列表：只筛 type=路亚，点击进钓点详情
class LureSpotsFeed extends StatefulWidget {
  const LureSpotsFeed({super.key});

  @override
  State<LureSpotsFeed> createState() => _LureSpotsFeedState();
}

class _LureSpotsFeedState extends State<LureSpotsFeed>
    with AutomaticKeepAliveClientMixin {
  List<FishingSpot> _list = const [];
  bool _loading = true;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final all = await SpotService.fetchSpots();
    if (!mounted) return;
    setState(() {
      _list = all.where((s) => s.type == '路亚').toList();
      _loading = false;
    });
  }

  void _openMap() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const SpotsScreen(initialType: '路亚')),
    );
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
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 24),
        children: [
          _mapEntry(),
          const SizedBox(height: 12),
          if (_list.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 50),
              child: Column(
                children: [
                  const Icon(Icons.place_outlined,
                      size: 50, color: AppTheme.border),
                  const SizedBox(height: 12),
                  const Text('还没有标记路亚钓点',
                      style: TextStyle(
                          fontSize: 14, color: AppTheme.textPrimary)),
                  const SizedBox(height: 6),
                  const Text('去地图上标一个，其他钓友也能看到',
                      style: TextStyle(
                          fontSize: 12, color: AppTheme.textSecondary)),
                  const SizedBox(height: 14),
                  OutlinedButton(
                    onPressed: _openMap,
                    child: const Text('去地图添加'),
                  ),
                ],
              ),
            )
          else
            for (final s in _list) ...[
              _LureSpotCard(
                spot: s,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => SpotDetailScreen(spot: s)),
                ),
              ),
              const SizedBox(height: 10),
            ],
        ],
      ),
    );
  }

  /// 顶部「在地图上找」入口条
  Widget _mapEntry() {
    return Material(
      color: AppTheme.primarySoft,
      borderRadius: BorderRadius.circular(AppTheme.radiusMd),
      child: InkWell(
        onTap: _openMap,
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: AppTheme.primaryLight,
                  borderRadius: BorderRadius.circular(11),
                ),
                child: const Icon(Icons.map_outlined,
                    size: 19, color: AppTheme.primary),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('在地图上找路亚点',
                        style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.textPrimary)),
                    SizedBox(height: 2),
                    Text('看水域形态、标点位置和到你的距离',
                        style: TextStyle(
                            fontSize: 11.5, color: AppTheme.textSecondary)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right,
                  size: 19, color: AppTheme.textSecondary),
            ],
          ),
        ),
      ),
    );
  }
}

class _LureSpotCard extends StatelessWidget {
  final FishingSpot spot;
  final VoidCallback onTap;
  const _LureSpotCard({required this.spot, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cover = spot.coverUrl;
    return Material(
      color: AppTheme.surface,
      borderRadius: BorderRadius.circular(AppTheme.radiusMd),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        child: Padding(
          padding: const EdgeInsets.all(11),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: (cover != null && cover.isNotEmpty)
                    ? Image.network(
                        cover,
                        width: 78,
                        height: 78,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => _holder(),
                      )
                    : _holder(),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(spot.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.textPrimary)),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(Icons.star_rounded,
                            size: 13, color: AppTheme.star),
                        const SizedBox(width: 2),
                        Text(spot.rating.toStringAsFixed(1),
                            style: const TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.star)),
                        const SizedBox(width: 8),
                        Text(spot.kindLabel,
                            style: const TextStyle(
                                fontSize: 11, color: AppTheme.textSecondary)),
                      ],
                    ),
                    if (spot.address.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Icon(Icons.place_outlined,
                              size: 12, color: AppTheme.textSecondary),
                          const SizedBox(width: 3),
                          Expanded(
                            child: Text(spot.address,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontSize: 11,
                                    color: AppTheme.textSecondary)),
                          ),
                        ],
                      ),
                    ],
                    if (spot.fish.isNotEmpty || spot.fee.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        [
                          if (spot.fish.isNotEmpty) '鱼种 ${spot.fish}',
                          if (spot.fee.isNotEmpty) spot.fee,
                        ].join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 11, color: AppTheme.textSecondary),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _holder() {
    return Container(
      width: 78,
      height: 78,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppTheme.primaryLight, AppTheme.primarySoft],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(10),
      ),
      child: const Icon(Icons.sports_handball_outlined,
          size: 24, color: AppTheme.primary),
    );
  }
}
