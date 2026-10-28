/// App 版本号（单一来源）
///
/// 为什么手写一份：`package_info_plus` 会多带一个原生插件，而版本号只有
/// 「设置 - 当前版本」和更新弹窗这两处要显示，不值得为它加依赖。
///
/// ★ 这里的值必须和 pubspec.yaml 的 `version:` 一致，
///   由 `test/version_consistency_test.dart` 守着 —— 只改一处会测试失败。
const String kAppVersion = '2.1.47';

/// 构建号（pubspec 里 `+` 后面的数字）
const int kAppBuild = 57;

/// 展示用：v2.1.47 (57)
String get kAppVersionText => 'v$kAppVersion ($kAppBuild)';
