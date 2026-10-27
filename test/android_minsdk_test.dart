// 安卓最低系统版本的护栏测试
//
// 起因（v2.1.23）：用户手机是 Android 5.1.1（API 22），装包时系统提示
// 「安装包已损坏」。包本身是好的 —— 是 android/app/build.gradle 里
// minSdk = 23 让系统直接拒装（INSTALL_FAILED_OLDER_SDK），各家 ROM
// 把这个错误翻译成了「解析包出错 / 安装包已损坏」。
//
// 这套断言不是「测代码逻辑」，而是防回退：谁再顺手把 minSdk 改回 23，
// `flutter test` 立刻红，不会等到用户装不上了才发现。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String relative) {
  final f = File(relative);
  expect(f.existsSync(), isTrue, reason: '找不到文件：$relative（工作目录不对？）');
  return f.readAsStringSync();
}

void main() {
  group('安卓打包配置', () {
    late String gradle;

    setUp(() => gradle = _read('android/app/build.gradle'));

    test('minSdk 必须 <= 22，否则 Android 5.x 装不上', () {
      // 只认 defaultConfig 里真正的赋值，不认注释里的同名字样
      final m = RegExp(r'^\s*minSdk\s*=\s*(\d+)\s*$', multiLine: true)
          .firstMatch(gradle);
      expect(m, isNotNull, reason: 'build.gradle 里找不到 minSdk = N 的赋值');

      final value = int.parse(m!.group(1)!);
      expect(
        value,
        lessThanOrEqualTo(22),
        reason: 'minSdk=$value 会把 Android 5.0/5.1 的手机挡在门外，'
            '系统提示的是「安装包已损坏」，用户根本看不出是版本问题',
      );
      // 依赖链（maplibre_gl / geolocator / camera / video_player）地板值都是 21，
      // 再往下 lib 合并会失败 —— 所以 21 就是这套依赖能压到的最低点。
      expect(value, greaterThanOrEqualTo(21),
          reason: 'minSdk 低于 21 时地图/相机/定位插件无法合并，出不了包');
    });

    test('保留脱糖开关（java.time 在 Android 5.x/6.x 上要靠它）', () {
      expect(gradle.contains('coreLibraryDesugaringEnabled true'), isTrue);
      expect(gradle.contains('desugar_jdk_libs'), isTrue,
          reason: '开了脱糖就必须带 desugar_jdk_libs 依赖，否则编译期报错');
    });

    test('包名不能改（改了老用户就无法覆盖升级）', () {
      expect(gradle.contains('applicationId = "com.example.fishing.fishing_app"'),
          isTrue,
          reason: 'applicationId 一变，就是另一个 App，老用户得卸载重装并且丢数据');
    });
  });

  group('版本号', () {
    test('pubspec 版本号与 versionCode 同步递增', () {
      final pubspec = _read('pubspec.yaml');
      final m = RegExp(r'^version:\s*([\d.]+)\+(\d+)\s*$', multiLine: true)
          .firstMatch(pubspec);
      expect(m, isNotNull, reason: 'pubspec.yaml 的 version 行格式应为 1.2.3+45');

      final code = int.parse(m!.group(2)!);
      // v2.1.23 的 versionCode 是 33；这里只做下界，不锁死具体值，
      // 否则每次发版都要改测试。
      expect(code, greaterThanOrEqualTo(33),
          reason: 'versionCode 必须比线上包大，安卓才会认作升级（同号会拒装）');
    });
  });
}
