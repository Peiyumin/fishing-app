import 'package:flutter/widgets.dart';

/// 全局路由观察者
///
/// 挂着它，页面才能用 `RouteAware.didPopNext` 知道「我从二级页回来了」。
/// 首页据此实现 v2.1.89 的新刷新策略：**取消下拉刷新，改成回来自动刷一次**。
///
/// 单独放一个文件而不是写在 main.dart 里，是为了避免
/// 「main → home_screen → main」这种环形 import。
final RouteObserver<ModalRoute<void>> routeObserver =
    RouteObserver<ModalRoute<void>>();
