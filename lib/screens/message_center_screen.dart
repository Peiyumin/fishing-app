import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../models/message.dart';
import '../services/message_poller.dart';
import '../services/message_service.dart';
import '../widgets/center_toast.dart';
import 'chat_screen.dart';

/// 消息中心（v27）
/// - 顶部「私信」黑卡入口：与钓友和客服的对话（需互相关注才能发消息）
/// - 下方通知四类：系统通知 / 评论 / 回复 / 点赞
class MessageCenterScreen extends StatefulWidget {
  const MessageCenterScreen({super.key});

  @override
  State<MessageCenterScreen> createState() => _MessageCenterScreenState();
}

class _MessageCenterScreenState extends State<MessageCenterScreen> {
  MsgSummary _summary = const MsgSummary();
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
    // 全局轮询未读数变化时，实时刷新本页红点（跨页面生效）
    MessagePoller.instance.unread.addListener(_onUnread);
  }

  @override
  void dispose() {
    MessagePoller.instance.unread.removeListener(_onUnread);
    super.dispose();
  }

  void _onUnread() {
    if (mounted) _refreshSummary();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final s = await MessageService.summary();
      if (!mounted) return;
      setState(() {
        _summary = s;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      CenterToast.show(context, e.toString().replaceAll('Exception: ', ''));
    }
  }

  /// 仅刷新汇总（不显示 loading 条），供轮询驱动调用
  Future<void> _refreshSummary() async {
    try {
      final s = await MessageService.summary();
      if (!mounted) return;
      setState(() => _summary = s);
    } catch (_) {}
  }

  Future<void> _markAllRead() async {
    try {
      await MessageService.markRead();
      if (!mounted) return;
      setState(() => _summary = const MsgSummary());
      CenterToast.show(context, '已全部标记为已读');
    } catch (e) {
      if (mounted) {
        CenterToast.show(context, e.toString().replaceAll('Exception: ', ''));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('消息',
            style: TextStyle(fontWeight: FontWeight.w700, color: Colors.white)),
        centerTitle: true,
        flexibleSpace: Container(
          decoration: const BoxDecoration(gradient: AppTheme.headerGradient),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications_none, color: Colors.white),
            tooltip: '通知设置',
            onPressed: () => Navigator.of(context).pushNamed('/notify-settings'),
          ),
          TextButton(
            onPressed: _markAllRead,
            child: const Text(
              '全部已读',
              style: TextStyle(
                  fontSize: 12.5,
                  color: Colors.white,
                  fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
      body: RefreshIndicator(
        color: AppTheme.primary,
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
          children: [
            if (_loading) _loadingBar(),
            _chatCard(),
            const SizedBox(height: 18),
            _noticeSection(),
          ],
        ),
      ),
    );
  }

  Widget _loadingBar() => const Padding(
        padding: EdgeInsets.only(bottom: 10),
        child: LinearProgressIndicator(
            minHeight: 2, color: AppTheme.primary, backgroundColor: AppTheme.divider),
      );

  /// 私信入口（黑卡）
  Widget _chatCard() {
    final unread = _summary.chat;
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppTheme.primary, AppTheme.primaryDark],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        onTap: () async {
          await Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => const ConversationListScreen(),
          ));
          _load();
        },
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
          ),
          alignment: Alignment.center,
          child: const Icon(Icons.forum_outlined,
              color: AppTheme.primary, size: 22),
        ),
        title: Row(
          children: [
            const Text('私信',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w800)),
            const SizedBox(width: 6),
            Text('MESSAGES',
                style: TextStyle(
                    color: Colors.white.withOpacity(0.5),
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1)),
            const Spacer(),
            if (unread > 0) _badge(unread),
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 3),
          child: Text('与钓友和客服的对话',
              style: TextStyle(
                  color: Colors.white.withOpacity(0.65), fontSize: 12)),
        ),
        trailing: const Icon(Icons.chevron_right, color: Colors.white54),
      ),
    );
  }

  Widget _badge(int n) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(
          color: AppTheme.danger,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(n > 99 ? '99+' : '$n',
            style: const TextStyle(
                color: Colors.white,
                fontSize: 10.5,
                fontWeight: FontWeight.w700)),
      );

  Widget _noticeSection() {
    final items = <({String key, String title, String desc, IconData icon, int unread})>[
      (key: 'system', title: '系统通知', desc: '活动、版本更新、账号提醒', icon: Icons.campaign_outlined, unread: _summary.system),
      (key: 'comment', title: '评论', desc: '帖子收到的新评论', icon: Icons.chat_bubble_outline, unread: _summary.comment),
      (key: 'reply', title: '回复', desc: '你的评论收到了回复', icon: Icons.reply_outlined, unread: _summary.reply),
      (key: 'like', title: '点赞', desc: '有人给你点了赞', icon: Icons.thumb_up_outlined, unread: _summary.like),
    ];
    // 通知四类（点赞用普通拇指图标，避免依赖高版本图标常量）
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('通知',
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.textPrimary)),
            const SizedBox(width: 6),
            Text('NOTICES',
                style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1,
                    color: AppTheme.textSecondary)),
          ],
        ),
        const SizedBox(height: 10),
        for (final it in items)
          _noticeTile(it.key, it.title, it.desc, it.icon, it.unread),
      ],
    );
  }

  Widget _noticeTile(
      String type, String title, String desc, IconData icon, int unread) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        border: Border.all(color: AppTheme.border),
      ),
      child: ListTile(
        onTap: () async {
          await Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => NoticeListScreen(type: type, title: title),
          ));
          _load();
        },
        leading: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: AppTheme.primaryLight,
            borderRadius: BorderRadius.circular(11),
          ),
          alignment: Alignment.center,
          child: Icon(icon, color: AppTheme.primary, size: 21),
        ),
        title: Text(title,
            style: const TextStyle(
                fontSize: 14.5, fontWeight: FontWeight.w700)),
        subtitle: Text(desc,
            style: const TextStyle(
                fontSize: 11.5, color: AppTheme.textSecondary)),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (unread > 0) _badge(unread),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right,
                size: 18, color: AppTheme.textSecondary),
          ],
        ),
      ),
    );
  }
}

/// 通知列表（某一类）
class NoticeListScreen extends StatefulWidget {
  final String type;
  final String title;
  const NoticeListScreen({super.key, required this.type, required this.title});

  @override
  State<NoticeListScreen> createState() => _NoticeListScreenState();
}

class _NoticeListScreenState extends State<NoticeListScreen> {
  final List<NoticeItem> _items = [];
  bool _loading = true;
  int _page = 1;

  @override
  void initState() {
    super.initState();
    _load();
    // 轮询未读数变化时，实时刷新本类通知列表（停留期间也能看到新评论/点赞）
    MessagePoller.instance.unread.addListener(_onUnread);
  }

  @override
  void dispose() {
    MessagePoller.instance.unread.removeListener(_onUnread);
    super.dispose();
  }

  void _onUnread() {
    if (mounted) _refresh();
  }

  /// 重新拉第一页；仅在内容确有变化时更新，避免无谓刷新导致列表跳动
  Future<void> _refresh() async {
    try {
      final list = await MessageService.notices(type: widget.type, page: 1);
      if (!mounted) return;
      final changed = _items.length != list.length ||
          (_items.isNotEmpty &&
              list.isNotEmpty &&
              _items.first.id != list.first.id);
      if (changed) {
        setState(() {
          _items
            ..clear()
            ..addAll(list);
          _page = 1;
        });
      }
    } catch (_) {}
  }

  Future<void> _load({bool more = false}) async {
    setState(() => _loading = true);
    try {
      final list = await MessageService.notices(
          type: widget.type, page: more ? _page + 1 : 1);
      if (!mounted) return;
      setState(() {
        if (more) {
          _page++;
          _items.addAll(list);
        } else {
          _items
            ..clear()
            ..addAll(list);
        }
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      CenterToast.show(context, e.toString().replaceAll('Exception: ', ''));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(title: Text(widget.title)),
      body: _loading && _items.isEmpty
          ? const Center(
              child: CircularProgressIndicator(color: AppTheme.primary))
          : _items.isEmpty
              ? _empty()
              : RefreshIndicator(
                  color: AppTheme.primary,
                  onRefresh: () => _load(),
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
                    itemCount: _items.length + 1,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (_, i) {
                      if (i == _items.length) {
                        return Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: TextButton(
                            onPressed: () => _load(more: true),
                            child: const Text('加载更多',
                                style: TextStyle(
                                    fontSize: 12.5,
                                    color: AppTheme.textSecondary)),
                          ),
                        );
                      }
                      final n = _items[i];
                      return Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppTheme.surface,
                          borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                          border: Border.all(color: AppTheme.border),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 6,
                              height: 6,
                              margin: const EdgeInsets.only(top: 6, right: 8),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: n.isRead
                                    ? Colors.transparent
                                    : AppTheme.danger,
                              ),
                            ),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(n.title,
                                      style: const TextStyle(
                                          fontSize: 13.5,
                                          fontWeight: FontWeight.w700)),
                                  if (n.content.isNotEmpty) ...[
                                    const SizedBox(height: 3),
                                    Text(n.content,
                                        style: const TextStyle(
                                            fontSize: 12,
                                            color: AppTheme.textSecondary,
                                            height: 1.4)),
                                  ],
                                  const SizedBox(height: 4),
                                  Text(_fmt(n.createdAt),
                                      style: const TextStyle(
                                          fontSize: 10.5,
                                          color: AppTheme.textSecondary)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
    );
  }

  Widget _empty() => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.notifications_none,
                size: 46, color: AppTheme.textSecondary.withOpacity(0.4)),
            const SizedBox(height: 10),
            const Text('暂无消息',
                style: TextStyle(
                    fontSize: 13, color: AppTheme.textSecondary)),
          ],
        ),
      );

  static String _fmt(String iso) {
    if (iso.isEmpty) return '';
    final d = DateTime.tryParse(iso);
    if (d == null) return iso;
    return '${d.year}-${_p(d.month)}-${_p(d.day)} ${_p(d.hour)}:${_p(d.minute)}';
  }

  static String _p(int v) => v.toString().padLeft(2, '0');
}
