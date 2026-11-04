import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../models/official.dart';
import '../services/api_client.dart';
import '../services/official_service.dart';
import '../widgets/official_badge.dart';
import 'photo_viewer_screen.dart';

/// 官方公告详情（v41）
///
/// 用户从「消息 → 系统通知」点一条官方公告进来，看到的是：
/// 官方头像 + 昵称 + 「官方」徽标 + 发布时间 + 标题 + 正文 + 配图。
/// 它长得像一条通知，而不是一张帖子 —— 没有点赞、没有评论、没有作者主页，
/// 因为公告是平台单向告知，不是社交内容。
class OfficialNoticeScreen extends StatefulWidget {
  final String id;

  /// 列表里已经拿到的那条（有就先渲染，避免白屏等接口）
  final OfficialNotice? initial;

  const OfficialNoticeScreen({super.key, required this.id, this.initial});

  @override
  State<OfficialNoticeScreen> createState() => _OfficialNoticeScreenState();
}

class _OfficialNoticeScreenState extends State<OfficialNoticeScreen> {
  OfficialNotice? _notice;
  bool _loading = true;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _notice = widget.initial;
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      final n = await OfficialService.noticeDetail(widget.id);
      if (!mounted) return;
      setState(() {
        _notice = n;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      final net = ApiClient.asNetError(e);
      setState(() {
        _loading = false;
        _error = net != null
            ? '网络不太好，公告加载失败'
            : (e is ApiException ? e.message : '公告加载失败');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final n = _notice;
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(title: const Text('官方公告'), elevation: 0),
      body: _error.isNotEmpty && n == null
          ? _errorView()
          : n == null
              ? const Center(
                  child: CircularProgressIndicator(color: AppTheme.primary))
              : RefreshIndicator(
                  color: AppTheme.primary,
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 28),
                    children: [
                      if (_loading)
                        const Padding(
                          padding: EdgeInsets.only(bottom: 8),
                          child: LinearProgressIndicator(
                              minHeight: 2,
                              color: AppTheme.primary,
                              backgroundColor: AppTheme.divider),
                        ),
                      _card(n),
                    ],
                  ),
                ),
    );
  }

  Widget _errorView() => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.campaign_outlined,
                size: 46, color: AppTheme.textTertiary.withOpacity(0.7)),
            const SizedBox(height: 10),
            Text(_error,
                style: const TextStyle(
                    fontSize: 13, color: AppTheme.textSecondary)),
            const SizedBox(height: 12),
            TextButton(onPressed: _load, child: const Text('重新加载')),
          ],
        ),
      );

  Widget _card(OfficialNotice n) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _authorRow(n),
          const SizedBox(height: 14),
          Text(
            n.title,
            style: const TextStyle(
              fontSize: 19,
              height: 1.35,
              fontWeight: FontWeight.w800,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 10),
          if (n.content.trim().isNotEmpty)
            Text(
              n.content,
              style: const TextStyle(
                fontSize: 14,
                height: 1.75,
                color: AppTheme.textPrimary,
              ),
            ),
          if (n.images.isNotEmpty) ...[
            const SizedBox(height: 14),
            _images(n.images),
          ],
          const SizedBox(height: 18),
          const Divider(height: 1, color: AppTheme.divider),
          const SizedBox(height: 10),
          Row(
            children: [
              const Icon(Icons.campaign_outlined,
                  size: 13, color: AppTheme.textTertiary),
              const SizedBox(width: 5),
              Text(
                n.authorName.isEmpty ? '官方公告' : '由 ${n.authorName} 发布',
                style: const TextStyle(
                    fontSize: 11, color: AppTheme.textTertiary),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _authorRow(OfficialNotice n) {
    return Row(
      children: [
        _avatar(n),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      n.authorName.isEmpty ? '官方' : n.authorName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textPrimary),
                    ),
                  ),
                  const SizedBox(width: 5),
                  const OfficialBadge(height: 15),
                  if (n.pinned) ...[
                    const SizedBox(width: 5),
                    Container(
                      height: 15,
                      padding: const EdgeInsets.symmetric(horizontal: 5),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: AppTheme.dangerLight,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text('置顶',
                          style: TextStyle(
                              fontSize: 9.5,
                              height: 1.0,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.dangerDark)),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 3),
              Text(
                officialTimeOf(n.createdAt),
                style: const TextStyle(
                    fontSize: 11.5, color: AppTheme.textTertiary),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _avatar(OfficialNotice n) {
    const size = 40.0;
    if (n.authorAvatar.isEmpty) return const OfficialAvatarGlyph(size: size);
    return ClipOval(
      child: CachedNetworkImage(
        imageUrl: n.authorAvatar,
        width: size,
        height: size,
        fit: BoxFit.cover,
        placeholder: (_, __) =>
            const OfficialAvatarGlyph(size: size),
        errorWidget: (_, __, ___) => const OfficialAvatarGlyph(size: size),
      ),
    );
  }

  /// 一张配图：http(s) 走网络缓存，其余当本机文件（后台手滑填了相对路径
  /// 时至少不会白屏，也不至于把一段本地路径当域名去请求）
  Widget _image(String url, {required BoxFit fit}) {
    if (url.startsWith('http://') || url.startsWith('https://')) {
      return CachedNetworkImage(
        imageUrl: url,
        fit: fit,
        placeholder: (_, __) => Container(color: AppTheme.divider),
        errorWidget: (_, __, ___) => Container(
          color: AppTheme.divider,
          alignment: Alignment.center,
          child: const Icon(Icons.broken_image_outlined,
              size: 18, color: AppTheme.textTertiary),
        ),
      );
    }
    return Image.file(
      File(url),
      fit: fit,
      errorBuilder: (_, __, ___) => Container(
        color: AppTheme.divider,
        alignment: Alignment.center,
        child: const Icon(Icons.broken_image_outlined,
            size: 18, color: AppTheme.textTertiary),
      ),
    );
  }

  /// 配图：1 张走大图（公告配图通常是一张通知截图，缩成小格子看不清字），
  /// 2 张及以上走 3 列宫格。
  Widget _images(List<String> urls) {
    if (urls.length == 1) {
      return GestureDetector(
        onTap: () => PhotoViewerScreen.open(context, urls),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: AspectRatio(
            aspectRatio: 16 / 10,
            child: _image(urls.first, fit: BoxFit.cover),
          ),
        ),
      );
    }
    return GridView.count(
      crossAxisCount: 3,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 6,
      crossAxisSpacing: 6,
      children: [
        for (var i = 0; i < urls.length; i++)
          GestureDetector(
            onTap: () => PhotoViewerScreen.open(context, urls, index: i),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: _image(urls[i], fit: BoxFit.cover),
            ),
          ),
      ],
    );
  }
}
