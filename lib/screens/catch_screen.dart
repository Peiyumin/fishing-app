import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_theme.dart';
import '../models/post.dart';
import '../services/api_config.dart';
import '../services/post_service.dart';
import '../services/session_provider.dart';
import '../utils/geo_names.dart';
import '../widgets/center_toast.dart';
import '../widgets/post_card.dart';
import 'auth_screen.dart';
import 'publish_catch_screen.dart';
import '../widgets/app_refresh.dart';

/// 渔获频道：只展示「渔获」类动态（category=post）
/// 入口：首页宫格「渔获」/ 发布中心「发布渔获」发布成功后回流
class CatchScreen extends StatefulWidget {
  const CatchScreen({super.key});

  @override
  State<CatchScreen> createState() => _CatchScreenState();
}

class _CatchScreenState extends State<CatchScreen> {
  final List<String> _tabs = ['最新', '热门', '同城'];
  int _tab = 0;
  List<Post> _posts = [];
  bool _loading = true;
  String? _emptyHint;
  String? _city;

  @override
  void initState() {
    super.initState();
    _load();
  }

  String? get _tabKey => switch (_tabs[_tab]) {
        '热门' => 'hot',
        '同城' => 'city',
        _ => null,
      };

  Future<void> _load() async {
    setState(() {
      // 已有内容时刷新不再清空列表：否则 AppRefresh 被整块销毁 → 闪白 +
      // 滚动位置归零，提示条也没机会显示。只在「本来就没数据」时全屏转圈。
      _loading = _posts.isEmpty;
      _emptyHint = null;
    });
    try {
      final tab = _tabKey;
      String? city;
      if (tab == 'city') {
        city = _city ??= await GeoNames.currentCity();
        if (city == null || city.isEmpty) {
          if (mounted) {
            setState(() {
              _posts = [];
              _emptyHint = '未能获取定位城市，请允许定位后下拉刷新';
            });
          }
          return;
        }
      }
      final all = await PostService.fetchFeed(limit: 40, tab: tab, city: city);
      // 只保留渔获类动态（后端信息流里还有问答/说说/二手）
      var list = all.where((p) => p.category == 'post').toList();
      // 同城 tab：带上定位城市再兜底过滤一次（老后端会忽略 city 参数）
      if (tab == 'city' && city != null) {
        list = list.where((p) => p.city == city).toList();
      }
      if (list.isEmpty) {
        _emptyHint = tab == 'city'
            ? '当前城市（${city ?? '未知'}）还没有渔获分享'
            : '还没有渔获分享，点右下角发布第一条吧';
      }
      if (mounted) setState(() => _posts = list);
    } catch (e) {
      if (mounted) CenterToast.show(context, '加载失败：$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _publish() async {
    final sp = Provider.of<SessionProvider>(context, listen: false);
    if (ApiConfig.enabled && !sp.isLoggedIn) {
      CenterToast.show(context, '请先登录后再发布', icon: Icons.lock_outline);
      await Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => const AuthScreen()));
      return;
    }
    final ok = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const PublishCatchScreen()),
    );
    if (ok == true) {
      _tab = 0;
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('渔获'),
        // ★ 深色顶栏：AppBarTheme 默认是浅色，这里必须显式声明白色前景，
        //   否则返回箭头与标题会是近黑色压在近黑渐变上（等于消失）
        foregroundColor: Colors.white,
        titleTextStyle: kAppBarTitleOnDark,
        flexibleSpace: Container(
          decoration: const BoxDecoration(gradient: AppTheme.headerGradient),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(44),
          child: Container(
            color: Colors.white,
            child: Row(
              children: _tabs
                  .map((t) => Expanded(
                        child: InkWell(
                          onTap: () {
                            final i = _tabs.indexOf(t);
                            if (_tab == i) return;
                            setState(() => _tab = i);
                            _load();
                          },
                          child: Center(
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 6),
                              decoration: BoxDecoration(
                                color: _tab == _tabs.indexOf(t)
                                    ? AppTheme.primaryLight
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(
                                    AppTheme.radiusPill),
                              ),
                              child: Text(
                                t,
                                style: TextStyle(
                                  fontSize: 14,
                                  color: _tab == _tabs.indexOf(t)
                                      ? AppTheme.primary
                                      : AppTheme.textSecondary,
                                  fontWeight: _tab == _tabs.indexOf(t)
                                      ? FontWeight.w700
                                      : FontWeight.w500,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ))
                  .toList(),
            ),
          ),
        ),
      ),
      // ★ AppRefresh 永远挂在树上（刷新时不清空列表），只在其内部切换
      //   首屏转圈 / 空态 / 列表 —— 这样下拉刷新不会闪白、滚动位置不丢。
      body: AppRefresh(
        onRefresh: _load,
        child: _loading
            ? ListView(
                children: [
                  SizedBox(
                    height: MediaQuery.of(context).size.height * 0.55,
                    child: const Center(child: CircularProgressIndicator()),
                  ),
                ],
              )
            : _posts.isEmpty
                ? ListView(
                    children: [
                      SizedBox(
                        height: MediaQuery.of(context).size.height * 0.55,
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.phishing,
                                  size: 46,
                                  color: AppTheme.textTertiary.withOpacity(0.45)),
                              const SizedBox(height: 10),
                              Text(
                                _emptyHint ?? '这里还没有渔获，下拉刷新试试',
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                    fontSize: 14,
                                    color: AppTheme.textSecondary),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  )
                : ListView(
                    children: _posts.map((p) => PostCard(post: p)).toList(),
                  ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _publish,
        backgroundColor: AppTheme.primary,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_a_photo_outlined),
        label: const Text('发布渔获'),
      ),
    );
  }
}
