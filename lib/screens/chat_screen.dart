import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_theme.dart';
import '../models/message.dart';
import '../models/user_profile.dart';
import '../services/api_client.dart';
import '../services/follow_service.dart';
import '../services/message_poller.dart';
import '../services/message_service.dart';
import '../services/session_provider.dart';
import '../widgets/center_toast.dart';
import '../widgets/emoji_panel.dart';
import '../widgets/user_avatar.dart';
import 'user_profile_screen.dart';

/// 私信会话列表
class ConversationListScreen extends StatefulWidget {
  const ConversationListScreen({super.key});

  @override
  State<ConversationListScreen> createState() => _ConversationListScreenState();
}

class _ConversationListScreenState extends State<ConversationListScreen> {
  final List<Conversation> _convs = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final list = await MessageService.conversations();
      if (!mounted) return;
      setState(() {
        _convs
          ..clear()
          ..addAll(list);
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
      appBar: AppBar(title: const Text('私信')),
      body: _loading && _convs.isEmpty
          ? const Center(
              child: CircularProgressIndicator(color: AppTheme.primary))
          : _convs.isEmpty
              ? _empty()
              : RefreshIndicator(
                  color: AppTheme.primary,
                  onRefresh: _load,
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
                    itemCount: _convs.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (_, i) {
                      final c = _convs[i];
                      return Container(
                        decoration: BoxDecoration(
                          color: AppTheme.surface,
                          borderRadius:
                              BorderRadius.circular(AppTheme.radiusSm),
                          border: Border.all(color: AppTheme.border),
                        ),
                        child: ListTile(
                          onTap: () async {
                            await Navigator.of(context).push(MaterialPageRoute(
                              builder: (_) => ChatScreen(
                                  peerId: c.peerId, nickname: c.nickname),
                            ));
                            _load();
                          },
                          leading: UserAvatar(
                            url: c.avatar,
                            userId: c.peerId,
                            vipLevel: c.vipLevel,
                            radius: 22,
                          ),
                          title: Text(c.nickname.isEmpty ? '钓友' : c.nickname,
                              style: const TextStyle(
                                  fontSize: 14, fontWeight: FontWeight.w700)),
                          subtitle: Text(
                            c.lastMessage.isEmpty ? '开始聊天吧' : c.lastMessage,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 12, color: AppTheme.textSecondary),
                          ),
                          trailing: c.unread > 0
                              ? Container(
                                  padding: const EdgeInsets.all(6),
                                  decoration: const BoxDecoration(
                                      color: AppTheme.danger,
                                      shape: BoxShape.circle),
                                  child: Text(c.unread > 99 ? '99+' : '${c.unread}',
                                      style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 10,
                                          fontWeight: FontWeight.w700)),
                                )
                              : const Icon(Icons.chevron_right,
                                  size: 18, color: AppTheme.textSecondary),
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
            Icon(Icons.mark_unread_chat_alt_outlined,
                size: 46, color: AppTheme.textSecondary.withOpacity(0.4)),
            const SizedBox(height: 10),
            const Text('还没有私信',
                style: TextStyle(
                    fontSize: 13, color: AppTheme.textSecondary)),
            const SizedBox(height: 4),
            const Text('与钓友互相关注后即可发消息',
                style: TextStyle(
                    fontSize: 11.5, color: AppTheme.textSecondary)),
          ],
        ),
      );
}

/// 私信对话（v2.1.25 改版）
///
///   · 参考主流 IM 的陌生人会话页：顶部头像+昵称+关注+更多，
///     列表头部是对方「资料卡」（大头像/昵称/签名/安全提示/确认聊天）；
///   · 打开期间 3 秒增量轮询：对方发来的消息立即上屏（纯拉模式做到近实时）；
///   · 底部快捷表情短语栏（早上好/比心/困/捂脸/赞，点击即发送）+ 表情面板；
///   · 会员/关注/单向 6 条上限的资格提示保留在列表上方。
class ChatScreen extends StatefulWidget {
  final String peerId;
  final String nickname;
  const ChatScreen({super.key, required this.peerId, required this.nickname});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final List<ChatMessage> _messages = [];
  final _input = TextEditingController();
  final _scroll = ScrollController();
  bool _loading = true;
  ChatCan _can = const ChatCan();
  bool _truncated = false;
  bool _following = false; // 正在执行关注/取关
  bool _sending = false;
  bool _emojiOpen = false;

  /// 已上屏的消息 id（增量轮询对比用）
  Set<String> _knownIds = {};

  /// 该会话未读数（AppBar 角标）
  int _convUnread = 0;

  /// 对方资料（资料卡用）
  String _peerAvatar = '';
  String _peerBio = '';

  /// 实时轮询（打开聊天页期间 3 秒一次）
  Timer? _pollTimer;

  /// 是否停在列表底部（在底部才自动滚动，上翻看历史不打扰）
  bool _atBottom = true;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _load();
    _pollTimer = Timer.periodic(
        const Duration(seconds: 3), (_) => _pollNew());
    // 聊天页打开期间，全局轮询切到「快速+静默」：新消息由本页自己上屏，
    // 不再由全局轮询弹系统通知（用户正盯着这个会话，弹通知是打扰）。
    MessagePoller.instance.setFastMode(true);
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _scroll.removeListener(_onScroll);
    _input.dispose();
    _scroll.dispose();
    MessagePoller.instance.setFastMode(false);
    super.dispose();
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    final atBottom =
        _scroll.position.pixels >= _scroll.position.maxScrollExtent - 30;
    if (atBottom != _atBottom) _atBottom = atBottom;
  }

  Future<Map<String, dynamic>> _peerProfile() async {
    try {
      final data = await ApiClient.get('/users/${widget.peerId}') as Map;
      return data.cast<String, dynamic>();
    } catch (_) {
      return const {};
    }
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final r = await MessageService.chat(widget.peerId);
      Map<String, dynamic> prof = const {};
      List<Conversation> convs = const [];
      try {
        prof = await _peerProfile();
        convs = await MessageService.conversations();
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _messages
          ..clear()
          ..addAll(r.messages);
        _knownIds = {for (final m in r.messages) m.id};
        _can = r.can;
        _truncated = r.truncated;
        _convUnread = convs
            .where((c) => c.peerId == widget.peerId)
            .fold(0, (p, c) => p + c.unread);
        _peerAvatar = (prof['avatar'] ?? '').toString();
        _peerBio = (prof['bio'] ?? '').toString();
        _loading = false;
      });
      _toBottom(force: true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      CenterToast.show(context, e.toString().replaceAll('Exception: ', ''));
    }
  }

  /// 增量轮询：只把对方新发来的消息追加进去，顺带刷新资格
  Future<void> _pollNew() async {
    if (_sending) return; // 自己正在发，等发送流程自己收尾，避免竞态重复上屏
    try {
      final r = await MessageService.chat(widget.peerId);
      if (!mounted) return;
      final hasNew = r.messages.any((m) => !_knownIds.contains(m.id));
      final canChanged = r.can.canSend != _can.canSend ||
          r.can.sentCount != _can.sentCount ||
          r.can.iFollow != _can.iFollow ||
          r.can.mutual != _can.mutual ||
          r.can.iMember != _can.iMember;
      if (!hasNew && !canChanged && r.truncated == _truncated) return;
      setState(() {
        _messages
          ..clear()
          ..addAll(r.messages);
        _knownIds = {for (final m in r.messages) m.id};
        _can = r.can;
        _truncated = r.truncated;
      });
      if (hasNew && _atBottom) _toBottom();
    } catch (_) {
      // 网络抖动：静默，下一轮再试
    }
  }

  /// 关注 / 取消关注对方，成功后刷新私信资格
  Future<void> _toggleFollow() async {
    if (_following) return;
    setState(() => _following = true);
    try {
      await FollowService.toggleFollow(widget.peerId, _can.iFollow);
      if (mounted) await _load();
    } on FollowNotAvailableException {
      if (mounted) {
        CenterToast.show(context, '关注功能需升级后端后启用');
      }
    } catch (e) {
      if (mounted) {
        CenterToast.show(context, e.toString().replaceAll('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _following = false);
    }
  }

  void _toBottom({bool force = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients && (force || _atBottom)) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
  }

  Future<void> _sendText(String raw) async {
    final text = raw.trim();
    if (text.isEmpty || _sending) return;
    if (!_can.canSend) {
      _showGateHint(_can.reason.isEmpty ? 'need_member' : _can.reason);
      return;
    }
    setState(() => _sending = true);
    try {
      final msg = await MessageService.send(widget.peerId, text);
      if (!mounted) return;
      _input.clear();
      setState(() {
        _messages.add(msg);
        _knownIds.add(msg.id);
      });
      _toBottom(force: true);
      // 立即刷新资格（单向关注发送后 sentCount 会变，可能到达 6 条上限）
      try {
        final can = await MessageService.canChat(widget.peerId);
        if (mounted) setState(() => _can = can);
      } catch (_) {}
    } on ChatSendException catch (e) {
      if (!mounted) return;
      // 资格可能因服务端状态变化而失效，重新拉一次资格并提示
      await _pollNew();
      _showGateHint(e.code);
    } catch (e) {
      if (mounted) {
        CenterToast.show(context, e.toString().replaceAll('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  /// 发送被拒时，按原因给出对应引导
  void _showGateHint(String code) {
    switch (code) {
      case 'need_member':
        // 非会员条数用尽：弹窗引导，点「去开通」直接进会员中心
        _showMemberDialog('非会员对同一个人最多发送 ${_can.limit} 条消息，开通会员后不限条数。');
        break;
      case 'need_follow':
        CenterToast.show(context, '请先关注对方后再私信');
        break;
      // 兼容旧版服务端返回（新规则下已不再出现）
      case 'oneway_limit':
        _showMemberDialog('已达到当前的发送上限，开通会员后不限条数。');
        break;
      default:
        CenterToast.show(context, '发送失败，请稍后再试');
    }
  }

  /// 开通会员引导弹窗：确认后跳转会员中心，返回时立刻刷新资格
  /// （否则刚开通完还是旧状态，会再弹一次窗）
  void _showMemberDialog(String message) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('开通会员'),
        content: Text(message, style: const TextStyle(height: 1.5)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('暂不'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              _openMemberCenter();
            },
            child: const Text('去开通'),
          ),
        ],
      ),
    );
  }

  /// 进会员中心，返回后刷新发送资格
  Future<void> _openMemberCenter() async {
    await Navigator.of(context).pushNamed('/member-center');
    if (!mounted) return;
    try {
      final can = await MessageService.canChat(widget.peerId);
      if (mounted) setState(() => _can = can);
    } catch (_) {}
  }

  /// 「5/31 上午10:39」格式
  String _fmtTime(String iso) {
    if (iso.isEmpty) return '';
    final t = DateTime.tryParse(iso);
    if (t == null) return '';
    final h = t.hour;
    final ap = h < 12 ? '上午' : '下午';
    final h12 = h == 0 ? 12 : (h > 12 ? h - 12 : h);
    return '${t.month}/${t.day} $ap$h12:${t.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionProvider>();
    final meId = session.userId ?? '';
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        titleSpacing: 4,
        leadingWidth: 30,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, size: 20),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Row(
          children: [
            UserAvatar(
              url: _peerAvatar,
              userId: widget.peerId,
              radius: 15,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                widget.nickname.isEmpty ? '私信' : widget.nickname,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w700),
              ),
            ),
            if (_convUnread > 0)
              Container(
                margin: const EdgeInsets.only(left: 6),
                padding: const EdgeInsets.all(5),
                decoration: const BoxDecoration(
                    color: AppTheme.danger, shape: BoxShape.circle),
                child: Text(_convUnread > 99 ? '99+' : '$_convUnread',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 9.5,
                        fontWeight: FontWeight.w700)),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: _following ? null : _toggleFollow,
            child: Text(
              _can.iFollow ? '已关注' : '关注',
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
                color: _can.iFollow
                    ? AppTheme.textSecondary
                    : AppTheme.primary,
              ),
            ),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_horiz, size: 20),
            onSelected: (v) {
              if (v == 'profile') {
                Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => UserProfileScreen(userId: widget.peerId),
                ));
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'profile', child: Text('查看资料')),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          ..._banners(),
          Expanded(
            child: _loading && _messages.isEmpty
                ? const Center(
                    child: CircularProgressIndicator(color: AppTheme.primary))
                : ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                    itemCount: _messages.length + 1,
                    itemBuilder: (_, i) {
                      if (i == 0) return _profileHeader();
                      final m = _messages[i - 1];
                      final mine = m.mine || m.fromId == meId;
                      return _bubble(m, mine);
                    },
                  ),
          ),
          _inputArea(),
        ],
      ),
    );
  }

  /// 列表头部：对方资料卡（参考主流 IM 的陌生人会话首屏）
  Widget _profileHeader() {
    final time = _messages.isNotEmpty
        ? _fmtTime(_messages.last.createdAt)
        : _fmtTime(DateTime.now().toIso8601String());
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 22, 24, 8),
      child: Column(
        children: [
          UserAvatar(
            url: _peerAvatar,
            userId: widget.peerId,
            radius: 32,
          ),
          const SizedBox(height: 10),
          Text(
            widget.nickname.isEmpty ? '钓友' : widget.nickname,
            style: const TextStyle(
                fontSize: 17, fontWeight: FontWeight.w800),
          ),
          if (_peerBio.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(_peerBio,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 12.5, color: AppTheme.textSecondary)),
          ],
          const SizedBox(height: 14),
          const Text(
            '为保障用户沟通安全，未互相关注的陌生人违规消息可能会被处理，请遵守法律法规和社区规范',
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 11, color: AppTheme.textSecondary, height: 1.6),
          ),
          const SizedBox(height: 10),
          if (time.isNotEmpty)
            Text(time,
                style: const TextStyle(
                    fontSize: 12, color: AppTheme.textSecondary)),
          const SizedBox(height: 8),
          const Text('对方已确认聊天，可继续发送消息',
              style: TextStyle(
                  fontSize: 12, color: AppTheme.textSecondary)),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  /// 顶部资格提示横幅（按当前私信资格展示不同引导）
  List<Widget> _banners() {
    final list = <Widget>[];
    if (_loading) return list;
    // ① 未关注：关注是私信的前置门槛（免费，点一下即可）
    if (!_can.iFollow) {
      list.add(_banner(
        Icons.person_add_alt_1_outlined,
        '关注对方后才能私信',
        _following ? '处理中…' : '关注',
        _following ? null : _toggleFollow,
      ));
    } else if (!_can.iMember) {
      // ② 非会员：每个聊天对象 6 条配额，剩几条明确告知，用完引导开通
      final left = _can.limit - _can.sentCount;
      list.add(_banner(
        Icons.lock_outline,
        left > 0
            ? '非会员对同一个人最多 ${_can.limit} 条，还可发 $left 条'
            : '已发满 ${_can.limit} 条，开通会员后不限条数',
        '开通会员',
        _openMemberCenter,
      ));
    }
    // ★ 不再单独提示「非会员仅显示最近 6 条」。
    //   上面那条「还可发 N 条 / 已发满 N 条」已经把非会员限制讲完了，
    //   两条横幅上下叠在一起纯属重复，反而把真正的聊天内容挤到屏幕下方
    //   （用户截图反馈：进会话先看到两行黄条，看不到消息）。
    //   后端返回的 truncated 字段保留，仍参与轮询变更判定，只是不再展示。
    return list;
  }

  Widget _banner(IconData icon, String text, String action, VoidCallback? onTap) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: AppTheme.warningLight,
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
      ),
      child: Row(
        children: [
          Icon(icon, size: 15, color: AppTheme.warning),
          const SizedBox(width: 6),
          Expanded(
            child: Text(text,
                style: const TextStyle(
                    fontSize: 11.5, color: AppTheme.warning, height: 1.3)),
          ),
          if (onTap != null)
            GestureDetector(
              onTap: onTap,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.primary,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(action,
                    style: const TextStyle(
                        fontSize: 11.5,
                        color: Colors.white,
                        fontWeight: FontWeight.w700)),
              ),
            ),
        ],
      ),
    );
  }

  Widget _bubble(ChatMessage m, bool mine) {
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.72),
        decoration: BoxDecoration(
          color: mine ? AppTheme.primary : AppTheme.surface,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(14),
            topRight: const Radius.circular(14),
            bottomLeft: Radius.circular(mine ? 14 : 4),
            bottomRight: Radius.circular(mine ? 4 : 14),
          ),
          border: mine ? null : Border.all(color: AppTheme.border),
        ),
        child: Text(
          m.content,
          style: TextStyle(
            fontSize: 13.5,
            height: 1.4,
            color: mine ? Colors.white : AppTheme.textPrimary,
          ),
        ),
      ),
    );
  }

  /// 底部区域：快捷表情短语 + （展开时）表情面板 + 输入行
  Widget _inputArea() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_emojiOpen)
          EmojiPanel(
            height: 236,
            onPick: (e) => insertAtCursor(_input, e),
            onBackspace: () => backspaceAtCursor(_input),
          )
        else
          QuickEmojiBar(onPick: _sendText),
        _inputBar(),
      ],
    );
  }

  Widget _inputBar() {
    final left = _can.limit - _can.sentCount;
    final hint = !_can.iFollow
        ? '关注对方后才能私信'
        : !_can.iMember
            ? (left > 0
                ? '非会员还可发 $left 条，开通会员不限条数'
                : '已发满 ${_can.limit} 条，开通会员后不限条数')
            : '说点什么…';
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(8, 8, 10, 8),
        decoration: const BoxDecoration(
          color: AppTheme.surface,
          border: Border(top: BorderSide(color: AppTheme.divider)),
        ),
        child: Row(
          children: [
            // 表情面板开关
            IconButton(
              onPressed: () => setState(() => _emojiOpen = !_emojiOpen),
              icon: Icon(
                _emojiOpen
                    ? Icons.keyboard_outlined
                    : Icons.emoji_emotions_outlined,
                size: 22,
                color: _emojiOpen ? AppTheme.primary : AppTheme.textSecondary,
              ),
              splashRadius: 20,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            ),
            Expanded(
              child: TextField(
                controller: _input,
                minLines: 1,
                maxLines: 4,
                // 不做 disabled：未关注/发满时仍允许输入，点发送再弹窗引导，
                // 否则用户点了没反应会以为 App 卡住（_sendText 内部做拦截）
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _sendText(_input.text),
                decoration: InputDecoration(
                  hintText: hint,
                  hintStyle: const TextStyle(
                      fontSize: 13, color: AppTheme.textSecondary),
                  filled: true,
                  fillColor: AppTheme.primarySoft,
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 9),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(20),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 6),
            GestureDetector(
              // 始终可点：资格不足时由 _sendText 弹窗说明原因
              onTap: _sending ? null : () => _sendText(_input.text),
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: _sending ? AppTheme.border : AppTheme.primary,
                  borderRadius: BorderRadius.circular(20),
                ),
                alignment: Alignment.center,
                child: _sending
                    ? const SizedBox(
                        width: 17,
                        height: 17,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.send, size: 18, color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
