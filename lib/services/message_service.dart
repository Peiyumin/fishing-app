import '../models/message.dart';
import 'api_client.dart';
import '../utils/json_num.dart';

/// 消息中心：私信 + 通知
class MessageService {
  /// 未读汇总
  static Future<MsgSummary> summary() async {
    final data = jsonMap(await ApiClient.get('/messages/summary'));
    return MsgSummary.fromJson(data.cast<String, dynamic>());
  }

  /// 增量消息流：拉 since 之后的新通知 + 新私信（通知轮询用）
  ///
  /// 返回的 `serverTime` 要原样回传给下一次调用，作为新的游标 ——
  /// 用服务端时间而不是本机时间，避免手机时钟不准导致漏消息或重复弹通知。
  static Future<
      ({
        String serverTime,
        MsgSummary summary,
        List<FeedItem> items,
      })> feed({String since = '', int limit = 20}) async {
    final data = jsonMap(await ApiClient.get('/messages/feed', {
      if (since.isNotEmpty) 'since': since,
      'limit': '$limit',
    }));
    final m = data.cast<String, dynamic>();
    final raw = (m['items'] as List?) ?? const [];
    return (
      serverTime: (m['serverTime'] ?? '').toString(),
      summary: MsgSummary.fromJson(
          ((m['summary'] as Map?) ?? const <String, dynamic>{})
              .cast<String, dynamic>()),
      items: raw
          .whereType<Map>()
          .map((e) => FeedItem.fromJson(e.cast<String, dynamic>()))
          .toList(),
    );
  }

  /// 通知列表（type 空 = 全部）
  static Future<List<NoticeItem>> notices({String type = '', int page = 1}) async {
    final data = jsonList(await ApiClient.get('/messages/notices', {
      'page': '$page',
      if (type.isNotEmpty) 'type': type,
    }));
    return data
        .map((e) => NoticeItem.fromJson((e as Map).cast<String, dynamic>()))
        .toList();
  }

  /// 标记已读（id 空 = 全部已读）
  static Future<void> markRead({String id = ''}) async {
    await ApiClient.post('/messages/notices/read', {'id': id});
  }

  /// 会话列表
  static Future<List<Conversation>> conversations() async {
    final data = jsonList(await ApiClient.get('/messages/conversations'));
    return data
        .map((e) => Conversation.fromJson((e as Map).cast<String, dynamic>()))
        .toList();
  }

  /// 聊天记录（含会员截断标记 + 私信资格）
  static Future<({List<ChatMessage> messages, bool truncated, ChatCan can})> chat(
      String peerId) async {
    final data = jsonMap(await ApiClient.get('/messages/chat/$peerId'));
    final map = data.cast<String, dynamic>();
    final list = (map['messages'] as List?) ?? const [];
    final canMap = (map['can'] as Map?) ?? const {};
    return (
      messages: list
          .map((e) => ChatMessage.fromJson((e as Map).cast<String, dynamic>()))
          .toList(),
      truncated: jsonBool(map['truncated'], fallback: false),
      can: ChatCan.fromJson(canMap.cast<String, dynamic>()),
    );
  }

  /// 发送私信（失败时抛出 [ChatSendException]，含业务 code）
  static Future<ChatMessage> send(String toId, String content) async {
    final json =
        await ApiClient.postRaw('/messages/chat', {'toId': toId, 'content': content});
    if (json['ok'] != true) {
      throw ChatSendException(
        (json['code'] ?? 'error').toString(),
        (json['error'] ?? '发送失败').toString(),
      );
    }
    final raw = json['message'];
    return ChatMessage.fromJson(
        (raw as Map?)?.cast<String, dynamic>() ?? const <String, dynamic>{});
  }

  /// 查询与某人的私信资格（会员/关注/单向上限）
  static Future<ChatCan> canChat(String peerId) async {
    final data =
        jsonMap(await ApiClient.get('/messages/can-chat', {'peerId': peerId}));
    return ChatCan.fromJson(data.cast<String, dynamic>());
  }
}
