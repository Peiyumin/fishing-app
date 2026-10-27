import 'package:flutter_test/flutter_test.dart';

import 'package:fishing_app/models/message.dart';
import 'package:fishing_app/services/message_poller.dart';
import 'package:fishing_app/services/notification_service.dart';

/// 通知功能的纯逻辑测试
///
/// 覆盖三件事（都是真机上很难复现、但错了体验立刻崩的）：
///   1. 服务端 feed 返回的 JSON 能不能正确解析成 [FeedItem]；
///   2. 通知栏文案有没有把「谁、做了什么」说清楚（不是干巴巴的「你有新消息」）；
///   3. 一批消息的分组/聚合规则 —— 一次轮询带回十几条不能弹十几个通知。
void main() {
  FeedItem item({
    String id = 'n1',
    String kind = 'notice',
    String type = 'comment',
    String refId = 'p1',
    String peerId = '',
    String fromName = '老张',
    String content = '这鱼真肥',
  }) =>
      FeedItem(
        id: id,
        kind: kind,
        type: type,
        refId: refId,
        peerId: peerId,
        fromName: fromName,
        content: content,
      );

  group('FeedItem 解析', () {
    test('完整字段解析', () {
      final f = FeedItem.fromJson({
        'kind': 'chat',
        'id': 'm1',
        'type': 'chat',
        'typeTitle': '私信',
        'title': '老张',
        'content': '明天去不去水库',
        'refId': '',
        'peerId': 'u2',
        'fromId': 'u2',
        'fromName': '老张',
        'fromAvatar': 'http://x/a.png',
        'isRead': false,
        'createdAt': '2026-10-23T15:00:00.000Z',
      });
      expect(f.isChat, isTrue);
      expect(f.peerId, 'u2');
      expect(f.fromName, '老张');
      expect(f.createdAt, '2026-10-23T15:00:00.000Z');
      expect(f.isRead, isFalse);
    });

    test('字段缺失时给安全默认值（老后端兼容）', () {
      final f = FeedItem.fromJson({'id': 'x'});
      expect(f.kind, 'notice');
      expect(f.type, 'system');
      expect(f.content, '');
      expect(f.isRead, isFalse);
    });
  });

  group('通知栏文案', () {
    test('评论：带评论者昵称', () {
      final f = item(type: 'comment', fromName: '老张', content: '这鲫鱼不错');
      expect(f.pushTitle, '老张 评论了你的动态');
      expect(f.pushBody, '这鲫鱼不错');
    });

    test('点赞：带点赞者昵称', () {
      final f = item(type: 'like', fromName: '小李');
      expect(f.pushTitle, '小李 赞了你的动态');
    });

    test('官方公告：标题用公告标题而不是「官方公告」', () {
      // item() 默认 title 为空 → 兜底成「官方公告」
      final f = item(type: 'system', fromName: '', content: '本周末举办路亚比赛');
      expect(f.pushTitle, '官方公告');
      expect(f.pushBody, '本周末举办路亚比赛');

      // 有 title 时必须用 title
      final g = FeedItem.fromJson({
        'kind': 'notice',
        'type': 'system',
        'title': '周末渔获征集',
        'content': '上传渔获即可参与抽奖',
      });
      expect(g.pushTitle, '周末渔获征集');
      expect(g.pushBody, '上传渔获即可参与抽奖');
    });

    test('私信：标题是发件人，正文是内容', () {
      final f = item(kind: 'chat', type: 'chat', fromName: '王哥', content: '在吗');
      expect(f.pushTitle, '王哥');
      expect(f.pushBody, '在吗');
    });

    test('昵称为空时不出现「 评论了你的动态」这种怪文案', () {
      final f = item(type: 'comment', fromName: '');
      expect(f.pushTitle, '你的动态有新评论');
    });
  });

  group('通知分类过滤', () {
    setUp(() {
      NotifyPrefs.enabled = true;
      NotifyPrefs.chat = true;
      NotifyPrefs.interact = true;
      NotifyPrefs.system = true;
    });

    test('总开关关掉后一条都不许弹', () {
      NotifyPrefs.enabled = false;
      expect(NotifyPrefs.allows(item(kind: 'chat', type: 'chat')), isFalse);
      expect(NotifyPrefs.allows(item(type: 'system')), isFalse);
    });

    test('关掉互动不影响私信与公告', () {
      NotifyPrefs.interact = false;
      expect(NotifyPrefs.allows(item(type: 'comment')), isFalse);
      expect(NotifyPrefs.allows(item(type: 'like')), isFalse);
      expect(NotifyPrefs.allows(item(kind: 'chat', type: 'chat')), isTrue);
      expect(NotifyPrefs.allows(item(type: 'system')), isTrue);
    });

    test('关掉公告不影响评论', () {
      NotifyPrefs.system = false;
      expect(NotifyPrefs.allows(item(type: 'system')), isFalse);
      expect(NotifyPrefs.allows(item(type: 'comment')), isTrue);
    });
  });

  group('分组聚合', () {
    test('私信按人分组，同一个人合并', () {
      final g = groupFeed([
        item(id: 'c1', kind: 'chat', type: 'chat', peerId: 'u2', content: '在吗'),
        item(id: 'c2', kind: 'chat', type: 'chat', peerId: 'u2', content: '钓到没'),
        item(id: 'c3', kind: 'chat', type: 'chat', peerId: 'u3', content: '走起'),
      ]);
      expect(g.chats.length, 2);
      expect(g.chats['u2']!.length, 2);
      expect(g.chats['u2']!.last.content, '钓到没');
      expect(g.chats['u3']!.length, 1);
    });

    test('点赞与评论分开，公告单独一类', () {
      final g = groupFeed([
        item(id: '1', type: 'like'),
        item(id: '2', type: 'like'),
        item(id: '3', type: 'comment'),
        item(id: '4', type: 'reply'),
        item(id: '5', type: 'system'),
        item(id: '6', kind: 'chat', type: 'chat', peerId: 'u9'),
      ]);
      expect(g.likes.length, 2);
      // 评论 + 回复都算「互动」，合并成一条
      expect(g.comments.length, 2);
      expect(g.systems.length, 1);
      expect(g.chats.length, 1);
    });

    test('空列表不炸', () {
      final g = groupFeed(const []);
      expect(g.chats, isEmpty);
      expect(g.likes, isEmpty);
      expect(g.comments, isEmpty);
      expect(g.systems, isEmpty);
    });
  });

  group('点击跳转 payload', () {
    test('私信带 peerId，互动带 refId', () {
      expect(item(kind: 'chat', type: 'chat', peerId: 'u2').toPayload()['peerId'],
          'u2');
      expect(item(type: 'like', refId: 'post-9').toPayload()['refId'], 'post-9');
      expect(item(type: 'system').toPayload()['type'], 'system');
    });
  });
}
