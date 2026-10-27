import 'package:fishing_app/models/message.dart';
import 'package:flutter_test/flutter_test.dart';

/// 私信规则（v2.1.26）：会员不限条数；非会员每个聊天对象 6 条；先关注才能私信。
/// 这几个断言锁住界面判定依赖的字段，避免后端/前端口径再次跑偏。
void main() {
  test('未关注 → need_follow，不允许发送', () {
    final can = ChatCan.fromJson({
      'iFollow': false,
      'iMember': false,
      'canSend': false,
      'reason': 'need_follow',
      'sentCount': 0,
      'limit': 6,
      'remaining': 6,
      'unlimited': false,
    });
    expect(can.iFollow, isFalse);
    expect(can.canSend, isFalse);
    expect(can.reason, 'need_follow');
    expect(can.unlimited, isFalse);
  });

  test('非会员已关注但未满 6 条 → 可发送，剩余条数正确', () {
    final can = ChatCan.fromJson({
      'iFollow': true,
      'iMember': false,
      'canSend': true,
      'reason': '',
      'sentCount': 4,
      'limit': 6,
      'remaining': 2,
      'unlimited': false,
    });
    expect(can.canSend, isTrue);
    expect(can.sentCount, 4);
    expect(can.limit, 6);
    expect(can.remaining, 2);
    expect(can.limitHint, contains('4/6'));
  });

  test('非会员发满 6 条 → need_member，剩余 0', () {
    final can = ChatCan.fromJson({
      'iFollow': true,
      'iMember': false,
      'canSend': false,
      'reason': 'need_member',
      'sentCount': 6,
      'limit': 6,
      'remaining': 0,
      'unlimited': false,
    });
    expect(can.canSend, isFalse);
    expect(can.reason, 'need_member');
    expect(can.remaining, 0);
  });

  test('会员 → 不限条数，即使发了很多条也能发', () {
    final can = ChatCan.fromJson({
      'iFollow': true,
      'iMember': true,
      'canSend': true,
      'reason': '',
      'sentCount': 99,
      'limit': 6,
      'remaining': -1,
      'unlimited': true,
    });
    expect(can.canSend, isTrue);
    expect(can.unlimited, isTrue);
    expect(can.remaining, -1);
    expect(can.limitHint, contains('不限'));
  });

  test('会员未关注对方仍需先关注（关注是前置门槛）', () {
    final can = ChatCan.fromJson({
      'iFollow': false,
      'iMember': true,
      'canSend': false,
      'reason': 'need_follow',
      'sentCount': 0,
      'limit': 6,
      'remaining': -1,
      'unlimited': true,
    });
    expect(can.iMember, isTrue);
    expect(can.canSend, isFalse);
    expect(can.reason, 'need_follow');
  });

  test('字段缺失时用安全默认值（老服务端不会崩）', () {
    final can = ChatCan.fromJson({'iFollow': true});
    expect(can.limit, 6);
    expect(can.sentCount, 0);
    expect(can.remaining, 0);
    expect(can.unlimited, isFalse);
    expect(can.canSend, isFalse);
  });
}
