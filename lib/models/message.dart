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

/// 增量消息流条目（`GET /messages/feed` 返回的一条）
///
/// 与 [NoticeItem] 的区别：这是「通知推送」用的统一模型，
/// 私信与系统通知混在同一个流里，带发送者昵称/头像，可直接拼成通知栏文案。
class FeedItem {
  /// notice = 系统通知/评论/点赞/回复；chat = 私信
  final String kind;
  final String id;

  /// system / comment / reply / like / chat
  final String type;
  final String typeTitle;
  final String title;
  final String content;

  /// 通知关联对象：评论/点赞是 postId
  final String refId;

  /// 私信对端 userId
  final String peerId;
  final String fromId;
  final String fromName;
  final String fromAvatar;
  final bool isRead;
  final String createdAt;

  const FeedItem({
    required this.id,
    this.kind = 'notice',
    this.type = 'system',
    this.typeTitle = '',
    this.title = '',
    this.content = '',
    this.refId = '',
    this.peerId = '',
    this.fromId = '',
    this.fromName = '',
    this.fromAvatar = '',
    this.isRead = false,
    this.createdAt = '',
  });

  factory FeedItem.fromJson(Map<String, dynamic> j) => FeedItem(
        id: (j['id'] ?? '').toString(),
        kind: (j['kind'] ?? 'notice').toString(),
        type: (j['type'] ?? 'system').toString(),
        typeTitle: (j['typeTitle'] ?? '').toString(),
        title: (j['title'] ?? '').toString(),
        content: (j['content'] ?? '').toString(),
        refId: (j['refId'] ?? '').toString(),
        peerId: (j['peerId'] ?? '').toString(),
        fromId: (j['fromId'] ?? '').toString(),
        fromName: (j['fromName'] ?? '').toString(),
        fromAvatar: (j['fromAvatar'] ?? '').toString(),
        isRead: (j['isRead'] as bool?) ?? false,
        createdAt: (j['createdAt'] ?? '').toString(),
      );

  bool get isChat => kind == 'chat';

  /// 官方公告（后台「群发系统通知」type=system）
  bool get isSystem => type == 'system';

  /// 互动类：评论 / 回复 / 点赞
  bool get isInteract =>
      type == 'comment' || type == 'reply' || type == 'like';

  /// 通知栏标题
  String get pushTitle {
    if (isChat) return fromName.isEmpty ? '新私信' : fromName;
    switch (type) {
      case 'comment':
        return fromName.isEmpty ? '你的动态有新评论' : '$fromName 评论了你的动态';
      case 'reply':
        return fromName.isEmpty ? '你的评论有新回复' : '$fromName 回复了你';
      case 'like':
        return fromName.isEmpty ? '有人赞了你的动态' : '$fromName 赞了你的动态';
      case 'system':
        return title.isEmpty ? '官方公告' : title;
      default:
        return title.isEmpty ? '新通知' : title;
    }
  }

  /// 通知栏正文
  String get pushBody {
    if (isChat) return content;
    if (isSystem) return content.isEmpty ? title : content;
    return content.isEmpty ? title : content;
  }

  /// 点击后跳转用的 payload
  ///
  /// 带上 fromName：点私信通知进聊天页时，标题栏直接显示对方昵称，
  /// 不用等接口回来才从「钓友」变成真名。
  Map<String, dynamic> toPayload() => {
        'kind': kind,
        'type': type,
        'id': id,
        'refId': refId,
        'peerId': peerId,
        'fromName': fromName,
      };
}
