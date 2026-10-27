import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fishing_app/app_version.dart';

/// 版本号单一来源校验
///
/// 「设置 - 当前版本」显示的是 lib/app_version.dart 里的常量，
/// 而安装包真正带的是 pubspec.yaml 的 version。两处不一致时用户会看到
/// 「设置里写 2.1.41，应用商店/安装包却是别的版本」，排查版本相关问题会被带偏。
void main() {
  test('lib/app_version.dart 与 pubspec.yaml 的版本号一致', () {
    final yaml = File('pubspec.yaml').readAsStringSync();
    final m = RegExp(r'^version:\s*([0-9.]+)\+(\d+)', multiLine: true)
        .firstMatch(yaml);
    expect(m, isNotNull, reason: 'pubspec.yaml 里找不到 version: x.y.z+n');
    final name = m!.group(1)!;
    final build = int.parse(m.group(2)!);
    expect(kAppVersion, name,
        reason: '改了 pubspec 版本号后，记得同步 lib/app_version.dart');
    expect(kAppBuild, build,
        reason: '构建号（+ 后面那个数字）也要同步');
  });

  test('版本号展示格式', () {
    expect(kAppVersionText, 'v$kAppVersion ($kAppBuild)');
  });
}
