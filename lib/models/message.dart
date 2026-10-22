/// 私信会话
class Conversation {
  final String convId;
  final String peerId;
  final String nickname;
  final String avatar;
  final int vipLevel;
  final String lastMessage;
  final String lastAt;
  final int unread;

  const Conversation({
    required this.convId,
    this.peerId = '',
    this.nickname = '',
    this.avatar = '',
    this.vipLevel = 0,
    this.lastMessage = '',
    this.lastAt = '',
    this.unread = 0,
  });

  factory Conversation.fromJson(Map<String, dynamic> j) => Conversation(
        convId: (j['convId'] ?? '').toString(),
        peerId: (j['peerId'] ?? '').toString(),
        nickname: (j['nickname'] ?? '').toString(),
        avatar: (j['avatar'] ?? '').toString(),
        vipLevel: (j['vipLevel'] as num?)?.toInt() ?? 0,
        lastMessage: (j['lastMessage'] ?? '').toString(),
        lastAt: (j['lastAt'] ?? '').toString(),
        unread: (j['unread'] as num?)?.toInt() ?? 0,
      );
}

/// 私信消息
class ChatMessage {
  final String id;
  final String fromId;
  final String toId;
  final String content;
  final String type;
  final String createdAt;
  final bool mine;

  const ChatMessage({
    required this.id,
    this.fromId = '',
    this.toId = '',
    this.content = '',
    this.type = 'text',
    this.createdAt = '',
    this.mine = false,
  });

  factory ChatMessage.fromJson(Map<String, dynamic> j) => ChatMessage(
        id: (j['id'] ?? '').toString(),
        fromId: (j['fromId'] ?? '').toString(),
        toId: (j['toId'] ?? '').toString(),
        content: (j['content'] ?? '').toString(),
        type: (j['type'] ?? 'text').toString(),
        createdAt: (j['createdAt'] ?? '').toString(),
        mine: (j['mine'] as bool?) ?? false,
      );
}

/// 通知（系统 / 评论 / 回复 / 点赞）
class NoticeItem {
  final String id;
  final String type;
  final String typeTitle;
  final String title;
  final String content;
  final String refId;
  final bool isRead;
  final String createdAt;

  const NoticeItem({
    required this.id,
    this.type = 'system',
    this.typeTitle = '',
    this.title = '',
    this.content = '',
    this.refId = '',
    this.isRead = false,
    this.createdAt = '',
  });

  factory NoticeItem.fromJson(Map<String, dynamic> j) => NoticeItem(
        id: (j['id'] ?? '').toString(),
        type: (j['type'] ?? '').toString(),
        typeTitle: (j['typeTitle'] ?? '').toString(),
        title: (j['title'] ?? '').toString(),
        content: (j['content'] ?? '').toString(),
        refId: (j['refId'] ?? '').toString(),
        isRead: (j['isRead'] as bool?) ?? false,
        createdAt: (j['createdAt'] ?? '').toString(),
      );
}

/// 消息中心未读汇总
class MsgSummary {
  final int chat;
  final int system;
  final int comment;
  final int reply;
  final int like;
  final int total;

  const MsgSummary({
    this.chat = 0,
    this.system = 0,
    this.comment = 0,
    this.reply = 0,
    this.like = 0,
    this.total = 0,
  });

  factory MsgSummary.fromJson(Map<String, dynamic> j) => MsgSummary(
        chat: (j['chat'] as num?)?.toInt() ?? 0,
        system: (j['system'] as num?)?.toInt() ?? 0,
        comment: (j['comment'] as num?)?.toInt() ?? 0,
        reply: (j['reply'] as num?)?.toInt() ?? 0,
        like: (j['like'] as num?)?.toInt() ?? 0,
        total: (j['total'] as num?)?.toInt() ?? 0,
      );
}
