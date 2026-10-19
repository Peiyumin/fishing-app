import 'package:flutter/material.dart';

import '../app_theme.dart';

import '../models/post.dart';
import '../services/post_service.dart';
import '../widgets/post_card.dart';

/// 发现页：分类 Tab + 动态瀑布流（探索更多钓友内容）
class DiscoverScreen extends StatefulWidget {
  const DiscoverScreen({super.key});

  @override
  State<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends State<DiscoverScreen> {
  final List<String> _tabs = ['推荐', '同城', '热门', '关注'];
  int _tab = 0;
  List<Post> _posts = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final posts = await PostService.fetchFeed(limit: 30);
      if (mounted) setState(() => _posts = posts);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('加载失败：$e')));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('发现'),
        flexibleSpace: Container(
          decoration: const BoxDecoration(gradient: AppTheme.headerGradient),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(44),
          child: Container(
            color: Colors.white,
            child: Row(
              children: _tabs
                  .map((t) => Expanded(
                        child: InkWell(
                          onTap: () => setState(() => _tab = _tabs.indexOf(t)),
                          child: Center(
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 6),
                              decoration: BoxDecoration(
                                color: _tab == _tabs.indexOf(t)
                                    ? AppTheme.primaryLight
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(
                                    AppTheme.radiusPill),
                              ),
                              child: Text(
                                t,
                                style: TextStyle(
                                  fontSize: 14,
                                  color: _tab == _tabs.indexOf(t)
                                      ? AppTheme.primary
                                      : AppTheme.textSecondary,
                                  fontWeight: _tab == _tabs.indexOf(t)
                                      ? FontWeight.w700
                                      : FontWeight.w500,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ))
                  .toList(),
            ),
          ),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                children: _posts.map((p) => PostCard(post: p)).toList(),
              ),
            ),
    );
  }
}
