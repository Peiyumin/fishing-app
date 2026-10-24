import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../models/article.dart';
import '../services/content_service.dart';
import 'publish_article_screen.dart';

/// 文章详情
///
/// 列表接口不返回正文（避免列表响应变大），这里按 id 再拉一次拿 content。
/// 自己投稿且还在审核中的文章也能打开，顶部会显示审核状态。
class ArticleDetailScreen extends StatefulWidget {
  final Article article;
  const ArticleDetailScreen({super.key, required this.article});

  @override
  State<ArticleDetailScreen> createState() => _ArticleDetailScreenState();
}

class _ArticleDetailScreenState extends State<ArticleDetailScreen> {
  late Article _a = widget.article;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final full = await ContentService.fetchArticle(widget.article.id);
    if (!mounted) return;
    setState(() {
      if (full != null) _a = full;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final paras = _a.paragraphs;
    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: AppBar(title: const Text('文章详情')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 40),
        children: [
          if (_a.isPending || _a.isRejected) _statusBanner(),

          Text(_a.title,
              style: const TextStyle(
                  fontSize: 21,
                  height: 1.35,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textPrimary)),
          const SizedBox(height: 12),
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: AppTheme.primaryLight,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(_a.categoryLabel,
                    style: const TextStyle(
                        fontSize: 10.5,
                        color: AppTheme.primary,
                        fontWeight: FontWeight.w600)),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  [
                    if (_a.authorName.isNotEmpty) _a.authorName,
                    _a.dateText,
                    '${_a.views} 次浏览',
                  ].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 11.5, color: AppTheme.textSecondary),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          if (_a.cover.isNotEmpty) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.network(
                _a.cover,
                width: double.infinity,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              ),
            ),
            const SizedBox(height: 16),
          ],

          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 30),
              child: Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else if (paras.isEmpty)
            const Text('这篇还没有正文',
                style: TextStyle(fontSize: 13, color: AppTheme.textSecondary))
          else
            ...paras.map((p) => Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: Text(p,
                      style: const TextStyle(
                          fontSize: 15,
                          height: 1.75,
                          color: AppTheme.textPrimary)),
                )),

          const SizedBox(height: 20),
          const Divider(color: AppTheme.divider),
          const SizedBox(height: 14),
          Center(
            child: TextButton.icon(
              onPressed: () async {
                final messenger = ScaffoldMessenger.of(context);
                final navigator = Navigator.of(context);
                final ok = await navigator.push<bool>(
                  MaterialPageRoute(
                      builder: (_) => PublishArticleScreen(
                          defaultCategory: _a.category)),
                );
                if (ok == true) {
                  messenger.showSnackBar(
                    const SnackBar(content: Text('已提交，审核通过后会显示在列表里')),
                  );
                }
              },
              icon: const Icon(Icons.edit_outlined, size: 17),
              label: const Text('我也要投稿', style: TextStyle(fontSize: 13.5)),
            ),
          ),
        ],
      ),
    );
  }

  /// 自己投稿时的审核状态提示
  Widget _statusBanner() {
    final rejected = _a.isRejected;
    final color = rejected ? AppTheme.danger : AppTheme.warning;
    final bg = rejected ? AppTheme.dangerLight : AppTheme.warningLight;
    final text = rejected
        ? '这篇没有通过审核${_a.rejectReason.isNotEmpty ? "：${_a.rejectReason}" : ""}'
        : '这篇还在审核中，通过后才会出现在列表里';
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(rejected ? Icons.error_outline : Icons.schedule,
              size: 15, color: color),
          const SizedBox(width: 7),
          Expanded(
            child: Text(text,
                style: TextStyle(fontSize: 12, color: color, height: 1.4)),
          ),
        ],
      ),
    );
  }
}
