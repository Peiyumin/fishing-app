import 'package:fishing_app/services/net_diag.dart';
import 'package:flutter_test/flutter_test.dart';

/// 网络自检的「结论文案」回归。
///
/// 这段的价值全在**结论要能指路**：同样叫「连不上」，超时要换网络、
/// 没有路由要去开权限、被拒绝是服务器的事。写错就等于没做。
void main() {
  NetDiagResult r({
    bool tcpOk = false,
    String tcpError = '',
    int status = 0,
    String httpError = '',
  }) =>
      NetDiagResult(
        tcpOk: tcpOk,
        tcpMs: 6000,
        tcpError: tcpError,
        httpStatus: status,
        httpMs: 6000,
        httpError: httpError,
      );

  group('端口都连不上时', () {
    test('超时 → 让用户换网络（端口被限）', () {
      final s = r(tcpError: 'SocketException: Connection timed out').summary;
      expect(s, contains('不通'));
      expect(s, contains('换一个网络'));
      expect(s, contains('未执行'), reason: '端口不通就别再看接口那一步了');
    });

    test('网络不可达 → 指到系统的联网开关，不能只说「手机没网」', () {
      final s = r(tcpError: 'SocketException: Network is unreachable').summary;
      // iOS 那个开关叫「无线数据」，安卓叫「流量使用」；文案按平台分叉，
      // 所以这里两者认一个（宿主测试机跑的是非 iOS 分支）。
      expect(s, anyOf(contains('无线数据'), contains('流量使用')));
      expect(s, contains('设置'));
    });

    test('被拒绝 → 明确说是服务器侧问题，别让用户折腾手机', () {
      final s = r(tcpError: 'SocketException: Connection refused').summary;
      expect(s, contains('服务器'));
      expect(s, contains('不是手机网络问题'));
    });

    test('未知原因也给一句可执行的话，不说「未知错误」', () {
      final s = r(tcpError: 'SocketException: 怪问题').summary;
      expect(s, contains('换网络'));
      expect(s.contains('未知'), isFalse);
    });
  });

  group('端口通、接口也要通', () {
    test('HTTP 200 → 明说网络没问题（剩下就是 App 侧）', () {
      final s = r(tcpOk: true, status: 200).summary;
      expect(s, contains('通'));
      expect(s, contains('HTTP 200'));
      expect(s, contains('网络和接口都正常'));
    });

    test('端口通但接口失败 → 指向后端', () {
      final s = r(
        tcpOk: true,
        httpError: 'HttpException: Connection closed before full header',
      ).summary;
      expect(s, contains('② 接口请求：失败'));
      expect(s, contains('后端'));
    });
  });

  test('自检本身绝不抛异常（真机上是长按触发的，抛了就白屏）', () async {
    final res = await NetDiag.run();
    expect(res, isA<NetDiagResult>());
    expect(res.summary, isNotEmpty);
  });
}
