import 'package:flutter/material.dart';

import '../models/post.dart';
import '../services/post_service.dart';
import '../services/refresh_bus.dart';
import '../widgets/center_toast.dart';
import '../widgets/ui_kit.dart';
import '../widgets/post_card.dart';
import 'publish_catch_screen.dart';
import '../widgets/app_refresh.dart';

/// 我的作品（独立页）：展示当前登录用户自己的全部发布，
/// 支持编辑（渔获类）与删除。从「我的」页「作品」统计项进入。
class MyPostsScreen extends StatefulWidget {
  const MyPostsScreen({super.key});

  @override
  State<MyPostsScreen> createState() => _MyPostsScreenState();
}

class _MyPostsScreenState extends State<MyPostsScreen> {
  List<Post> _posts = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    // 已有作品时刷新不清空列表，避免整块消失闪白
    setState(() => _loading = _posts.isEmpty);
    try {
      final posts = await PostService.fetchMyPosts();
      if (mounted) setState(() => _posts = posts);
    } catch (e) {
      if (mounted) CenterToast.show(context, '加载失败：$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _deletePost(Post post) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('删除动态'),
        content: const Text('确定删除这条动态吗？删除后他人与自己的列表都不再显示，且无法恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await PostService.deletePost(post.id);
      if (!mounted) return;
      setState(() => _posts.removeWhere((p) => p.id == post.id));
      RefreshBus.bumpFeed();
      CenterToast.show(context, '已删除');
    } catch (e) {
      if (mounted) CenterToast.show(context, '删除失败：$e');
    }
  }

  Future<void> _editPost(Post post) async {
    if (post.category != 'post') {
      CenterToast.show(context, '该类型动态暂不支持编辑');
      return;
    }
    final updated = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => PublishCatchScreen(existing: post)),
    );
    if (updated == true && mounted) {
      RefreshBus.bumpFeed();
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('我的作品')),
      body: AppRefresh(
        onRefresh: _load,
        child: _loading
            ? ListView(
                children: [
                  SizedBox(
                    height: MediaQuery.of(context).size.height * 0.55,
                    child: const Center(child: CircularProgressIndicator()),
                  ),
                ],
              )
            : _posts.isEmpty
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    // v2.1.59：原来是一个 120pt 留白 + 一行灰字，整页空得像加载失败；
                    // 换成统一空状态（图标 + 标题 + 一句怎么做的说明），并垂直居中
                    children: [
                      SizedBox(
                        height: MediaQuery.of(context).size.height * 0.55,
                        child: const Center(
                          child: UiEmptyState(
                            icon: Icons.edit_note_outlined,
                            title: '还没有发布',
                            desc: '去首页点底部「+」，发布你的第一条渔获或动态',
                          ),
                        ),
                      ),
                    ],
                  )
                : ListView.separated(
                    padding: const EdgeInsets.only(bottom: 24, top: 8),
                    itemCount: _posts.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (_, i) => PostCard(
                      post: _posts[i],
                      onEdit: _editPost,
                      onDelete: _deletePost,
                    ),
                  ),
      ),
    );
  }
}
