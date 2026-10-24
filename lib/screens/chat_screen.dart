import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_theme.dart';
import '../models/message.dart';
import '../models/user_profile.dart';
import '../services/follow_service.dart';
import '../services/message_service.dart';
import '../services/session_provider.dart';
import '../widgets/center_toast.dart';
import '../widgets/user_avatar.dart';

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

/// 私信对话
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

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final r = await MessageService.chat(widget.peerId);
      if (!mounted) return;
      setState(() {
        _messages
          ..clear()
          ..addAll(r.messages);
        _can = r.can;
        _truncated = r.truncated;
        _loading = false;
      });
      _toBottom();
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      CenterToast.show(context, e.toString().replaceAll('Exception: ', ''));
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

  void _toBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _sending || !_can.canSend) return;
    setState(() => _sending = true);
    try {
      final msg = await MessageService.send(widget.peerId, text);
      if (!mounted) return;
      _input.clear();
      setState(() => _messages.add(msg));
      await _load(); // 刷新 sentCount / 资格，及时反映单向 6 条上限
    } on ChatSendException catch (e) {
      if (!mounted) return;
      // 资格可能因服务端状态变化而失效，重新拉一次资格并提示
      await _load();
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
        CenterToast.show(context, '只有会员才能使用私信，请先开通会员');
        break;
      case 'need_follow':
        CenterToast.show(context, '请先关注对方后再私信');
        break;
      case 'oneway_limit':
        CenterToast.show(context, '单向关注最多 6 条，互相关注后可继续');
        break;
      default:
        CenterToast.show(context, '发送失败，请稍后再试');
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionProvider>();
    final meId = session.userId ?? '';
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: Text(widget.nickname.isEmpty ? '私信' : widget.nickname),
      ),
      body: Column(
        children: [
          ..._banners(),
          Expanded(
            child: _loading && _messages.isEmpty
                ? const Center(
                    child: CircularProgressIndicator(color: AppTheme.primary))
                : _messages.isEmpty
                    ? _emptyChat()
                    : ListView.builder(
                        controller: _scroll,
                        padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                        itemCount: _messages.length,
                        itemBuilder: (_, i) {
                          final m = _messages[i];
                          final mine = m.mine || m.fromId == meId;
                          return _bubble(m, mine);
                        },
                      ),
          ),
          _inputBar(),
        ],
      ),
    );
  }

  /// 顶部资格提示横幅（按当前私信资格展示不同引导）
  List<Widget> _banners() {
    final list = <Widget>[];
    if (_loading) return list;
    if (!_can.iMember) {
      list.add(_banner(
        Icons.lock_outline,
        '私信功能仅对会员开放',
        '去开通',
        () => Navigator.of(context).pushNamed('/member-center'),
      ));
    } else if (!_can.iFollow) {
      list.add(_banner(
        Icons.person_add_alt_1_outlined,
        '请先关注对方后再私信',
        _following ? '处理中…' : '关注',
        _following ? null : _toggleFollow,
      ));
    } else if (!_can.mutual && _can.sentCount >= _can.limit) {
      list.add(_banner(
        Icons.info_outline,
        '单向关注最多 ${_can.limit} 条，互相关注后可继续',
        '去互关',
        _following ? null : _toggleFollow,
      ));
    }
    if (_truncated) {
      list.add(_banner(
        Icons.lock_outline,
        '仅显示前 6 条消息，开通会员查看全部',
        '开通会员',
        () => Navigator.of(context).pushNamed('/member-center'),
      ));
    }
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

  Widget _inputBar() {
    final canSend = _can.canSend;
    final hint = !_can.iMember
        ? '开通会员后才能私信'
        : !_can.iFollow
            ? '关注对方后才能私信'
            : !_can.mutual && _can.sentCount >= _can.limit
                ? '互相关注后可继续私信'
                : '说点什么…';
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
        decoration: const BoxDecoration(
          color: AppTheme.surface,
          border: Border(top: BorderSide(color: AppTheme.divider)),
        ),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _input,
                minLines: 1,
                maxLines: 4,
                enabled: canSend,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _send(),
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
            const SizedBox(width: 8),
            GestureDetector(
              onTap: canSend ? _send : null,
              child: Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: canSend ? AppTheme.primary : AppTheme.border,
                  borderRadius: BorderRadius.circular(21),
                ),
                alignment: Alignment.center,
                child: _sending
                    ? const SizedBox(
                        width: 17,
                        height: 17,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.send, size: 19, color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _emptyChat() => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.chat_bubble_outline,
                size: 44, color: AppTheme.textSecondary.withOpacity(0.4)),
            const SizedBox(height: 10),
            const Text('还没有消息，打个招呼吧',
                style: TextStyle(
                    fontSize: 12.5, color: AppTheme.textSecondary)),
          ],
        ),
      );
}
