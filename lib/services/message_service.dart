import '../models/message.dart';
import 'api_client.dart';

/// 消息中心：私信 + 通知
class MessageService {
  /// 未读汇总
  static Future<MsgSummary> summary() async {
    final data = await ApiClient.get('/messages/summary') as Map;
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
    final data = await ApiClient.get('/messages/feed', {
      if (since.isNotEmpty) 'since': since,
      'limit': '$limit',
    }) as Map;
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
    final data = await ApiClient.get('/messages/notices', {
      'page': '$page',
      if (type.isNotEmpty) 'type': type,
    }) as List;
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
    final data = await ApiClient.get('/messages/conversations') as List;
    return data
        .map((e) => Conversation.fromJson((e as Map).cast<String, dynamic>()))
        .toList();
  }

  /// 聊天记录
  static Future<({List<ChatMessage> messages, bool mutual})> chat(
      String peerId) async {
    final data = await ApiClient.get('/messages/chat/$peerId') as Map;
    final map = data.cast<String, dynamic>();
    final list = (map['messages'] as List?) ?? const [];
    return (
      messages: list
          .map((e) => ChatMessage.fromJson((e as Map).cast<String, dynamic>()))
          .toList(),
      mutual: (map['mutual'] as bool?) ?? false,
    );
  }

  /// 发送私信
  static Future<ChatMessage> send(String toId, String content) async {
    final data = await ApiClient.post('/messages/chat', {
      'toId': toId,
      'content': content,
    }) as Map;
    final raw = (data as Map)['message'];
    return ChatMessage.fromJson(
        (raw as Map?)?.cast<String, dynamic>() ?? data.cast<String, dynamic>());
  }

  /// 是否可与某人私信（互相关注）
  static Future<bool> canChat(String peerId) async {
    final data = await ApiClient.get('/messages/can-chat', {'peerId': peerId}) as Map;
    return (data['mutual'] as bool?) ?? false;
  }
}
