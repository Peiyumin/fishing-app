import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../app_theme.dart';
import '../../services/net_diag.dart';
import '../../widgets/center_toast.dart';
import '../../widgets/net_fix_steps.dart';

/// 首次启动的权限引导（v2.1.46，v2.1.63 起含「网络」项）
///
/// 用户反馈：「装好后打开 App 应该把所有权限都问一遍，确认完系统里也要真的开上」。
///
/// 为什么必须**逐项**申请：
///   · 安卓 11+ 同时申请多个权限时，系统可能只弹一个就把其余的判成 denied；
///   · 相机与麦克风要挨着弹（录像要一起用），中间插别的权限会被系统合并掉；
///   · 每弹一次框，App 会短暂 inactive，必须等这一轮结束再请求下一项。
/// 所以这里严格串行：弹 → 等结果 → 回读系统状态 → 下一项。
///
/// 状态一律**回读系统**（`permission.status`），不拿 request 的返回值当真：
/// 用户在系统弹窗上点「仅本次允许」或「拒绝」时，返回值与最终设置并不总一致。
///
/// ── 关于「网络」这一项（v2.1.63）────────────────────────────────
/// 用户报：「权限全通过后，登录注册还是提示连接失败，清单里少了个网络权限」。
///
/// 事实是：**两个平台都没有可申请的「网络权限」**
///   · Android 的 `INTERNET` 是安装时自动授予的普通权限，没有弹窗，清单里也
///     不该出现（已用 aapt2 核对过安装包，INTERNET / ACCESS_NETWORK_STATE
///     都在，`usesCleartextTraffic=true` 也在 —— 不是打包丢了权限）；
///   · iOS 更没有「网络权限」这个条目，明文 HTTP 由 Info.plist 的 ATS 放行
///     （也核对过成品 ipa，`NSAllowsArbitraryLoads=true` 在）。
///
/// 真正卡住用户的是 **iOS 的「是否允许使用无线数据」系统弹窗**：它只在 App
/// 第一次真的发起网络请求时由系统弹出，**不在任何权限清单里**，也没法用
/// permission_handler 主动请求。老流程里第一个请求发生在「引导页点完 → 进首页」
/// 之后，用户根本不知道还有这么一个框，一旦错过或点错，之后每次登录都只看到
/// 一句「连不上服务器」—— 表现就是「少了网络权限」。
///
/// 所以这里把网络做成**清单里的第一项**，并且和其余五项**同一个样式、同一套
/// 交互**（v2.1.64 调整）：
///   1. 进页面时它是中性的「允许」态 —— 不再一进来就自动探测、然后红着脸
///      显示「未连通 / 去修复」。用户看到的是一张和下面完全一样的白卡；
///   2. 点「一键开启全部权限」→ 网络排**队列第一位**，先探一次：这一下就是
///      触发 iOS「是否允许使用无线数据」系统弹窗的钩子，把它在引导页内消化掉，
///      用户当场就能看到结果，而不是进登录页才发现点登录没反应；
///   3. 探测结果如实展示：已连通（绿勾）/ 连不上（红，带分平台修复指引）/
///      网络通但服务器接口异常（橙）。连不上时**不自动放行进首页**。
class PermissionOnboardScreen extends StatefulWidget {
  const PermissionOnboardScreen({
    super.key,
    required this.onDone,
    this.probeNet,
    this.debugGrantPerms,
  });

  /// 全部处理完（或用户点「以后再说」）后回调
  final VoidCallback onDone;

  /// 网络探测实现，默认走 [NetDiag.run]（TCP 连端口 + 取一次接口）。
  /// 抽成可注入是为了测试能给出确定结果，不打真实网络。
  final Future<NetDiagResult> Function()? probeNet;

  /// 测试用：强制五项系统权限的状态。
  ///
  /// null（默认）= 走系统回读，生产路径永远是它；
  /// true = 全当已授予；false = 全当被拒。
  /// 必须在测试里能注入，是因为 `permission_handler` 走平台通道，
  /// 在宿主机上跑 widget 测试时那个 Future 不会返回，页面会永远停在读取中。
  final bool? debugGrantPerms;

  @override
  State<PermissionOnboardScreen> createState() =>
      _PermissionOnboardScreenState();
}

class _PermRow {
  final Permission perm;
  final IconData icon;
  final String title;
  final String desc;

  const _PermRow(this.perm, this.icon, this.title, this.desc);
}

/// 网络自检的四种状态
enum _NetState {
  /// 还没开始
  idle,

  /// 正在探测
  checking,

  /// 端口通、接口回 200 —— 真的能上网
  ok,

  /// 端口通，但接口不是 200：网络没问题，是服务端的事
  serverIssue,

  /// 端口都连不上：没有出口 / 被系统禁止联网 / 端口被拦
  offline,
}

class _PermissionOnboardScreenState extends State<PermissionOnboardScreen> {
  /// 顺序即展示/申请顺序：通知 → 定位 → 相机 → 麦克风 → 相册
  static const List<_PermRow> _rows = [
    _PermRow(Permission.notification, Icons.notifications_active_outlined,
        '通知', '私信、评论、点赞、官方公告的提醒'),
    _PermRow(Permission.locationWhenInUse, Icons.location_on_outlined,
        '位置信息', '附近钓友、钓点导航、本地天气与渔获定位'),
    _PermRow(Permission.camera, Icons.camera_alt_outlined, '相机',
        '发布渔获时拍照、录像，拍钓点'),
    _PermRow(Permission.microphone, Icons.mic_none_outlined, '麦克风',
        '录像时录制现场声音（不开也能拍照）'),
    _PermRow(Permission.photos, Icons.photo_library_outlined, '照片与视频',
        '从相册选图发布动态、上传头像'),
  ];

  final Map<Permission, PermissionStatus> _status = {};
  bool _reading = true;
  bool _running = false;

  /// 已经放过行（防止「自动关闭」和用户手动点重复触发）
  bool _finished = false;

  /// 「全部已开启 → 自动进首页」只排一次
  bool _autoExit = false;

  /// 网络自检状态
  _NetState _net = _NetState.idle;
  NetDiagResult? _netResult;

  /// 「一键开启」队列里正在弹系统框的那一项（用来高亮，让逐项申请看得见）
  Permission? _activePerm;

  /// 探测只跑一次，重复调用复用同一个 Future（避免连点弹出多次请求）
  Future<void>? _probeFuture;

  @override
  void initState() {
    super.initState();
    // ★ 这里**故意不自动探测网络**。
    //
    // v2.1.63 是在 initState 里就 `_ensureProbed()`，结果是页面一打开，
    // 网络那一项 1 秒内就变成红底的「未连通 / 去修复」，而下面五项还是
    // 干干净净的「允许」—— 用户会觉得「怎么一上来就说我有毛病」。
    //
    // 而且 iOS 的「是否允许使用无线数据」弹窗跟着这一下一起弹出来，
    // 时机比权限清单还早，用户根本不知道那是在干嘛。
    //
    // 现在改成：网络项初始是中性「允许」态，等用户点「一键开启全部权限」
    // 时作为队列第一位去探测 —— 那时候用户的心理预期就是
    // 「点了会一个一个问我」，弹出来正合预期。
    _refresh();
  }

  /// 网络探测（结果缓存在 [_net] / [_netResult]）
  Future<void> _ensureProbed() =>
      _probeFuture ??= _doProbe();

  Future<void> _doProbe() async {
    if (mounted) setState(() => _net = _NetState.checking);
    NetDiagResult r;
    try {
      r = await (widget.probeNet ?? NetDiag.run)();
    } catch (e) {
      r = NetDiagResult(
        tcpOk: false,
        tcpMs: 0,
        tcpError: '探测本身出错：$e',
        httpStatus: 0,
        httpMs: 0,
        httpError: '',
      );
    }
    if (!mounted) return;
    setState(() {
      _netResult = r;
      // 三态而不是两态：端口通但接口没回 200 是「服务器的问题」，
      // 让用户去折腾 WiFi 只会白费功夫，必须分开说。
      if (!r.tcpOk) {
        _net = _NetState.offline;
      } else if (r.httpStatus == 200) {
        _net = _NetState.ok;
      } else {
        _net = _NetState.serverIssue;
      }
    });
    _maybeAutoExit();
  }

  /// 重新探测（用户点「重新检测」时用，强制重跑）
  Future<void> _reprobe() async {
    _probeFuture = null;
    await _ensureProbed();
  }

  Future<void> _refresh() async {
    final map = <Permission, PermissionStatus>{};
    final forced = widget.debugGrantPerms;
    for (final r in _rows) {
      if (forced != null) {
        map[r.perm] = forced ? PermissionStatus.granted : PermissionStatus.denied;
        continue;
      }
      try {
        map[r.perm] = await r.perm.status;
      } catch (_) {
        map[r.perm] = PermissionStatus.denied;
      }
    }
    if (!mounted) return;
    setState(() {
      _status
        ..clear()
        ..addAll(map);
      _reading = false;
    });
    _maybeAutoExit();
  }

  /// 权限全开 **且** 网络没问题 → 稍等一下自动进首页。
  ///
  /// 这里要同时照顾两种人：
  ///   · **新装用户**：五项权限还没给，`permsAll` 为 false，本函数直接返回 ——
  ///     页面上网络项保持中性的「允许」，不会被自动探测成红字；
  ///   · **从旧版升级的用户**：权限本来就全开，如果这时也直接放行，
  ///     v2.1.63 修的「网络没通却被放进去」就又回来了。所以先静默探一次
  ///     （他们本来 0.5 秒内就跳过这一页，看不到那个菊花），通了才走。
  void _maybeAutoExit() {
    if (_finished || _autoExit) return;
    if (_reading) return;
    if (_status.length < _rows.length) return;
    final permsAll = _rows.every((r) => _status[r.perm]?.isGranted == true);
    if (!permsAll) return;
    // 权限已齐但还没探过 → 探一次再决定（探测完会再进本函数）
    if (_net == _NetState.idle) {
      _ensureProbed();
      return;
    }
    // 正在检测中就再等等
    if (_net == _NetState.checking) return;
    // 明确连不上 → 停在本页，让用户先修网络
    if (_net == _NetState.offline) return;
    _autoExit = true;
    Future.delayed(const Duration(milliseconds: 450), () {
      if (mounted && !_finished) _done();
    });
  }

  /// 逐项申请（串行）。每一项都回读系统状态再继续。
  ///
  /// ★ 队列第 1 位是**网络**（v2.1.64）：它虽然不是系统权限，但用户眼里
  /// 它和下面五项是一类东西，点「一键开启」时理应从它开始过一遍。
  /// 这一下刚好也是 App 生命周期里第一次真正发请求 —— iOS 的
  /// 「是否允许使用无线数据」系统弹窗在这里弹出，正合「会一个一个问我」
  /// 的心理预期。
  Future<void> _requestAll() async {
    if (_running) return;
    setState(() => _running = true);

    // ── 第 1 项：网络 ──
    // 已经确认连通就不重复探（省一次往返，也不重复打扰系统弹窗）；
    // 之前失败或从没探过则重探 —— 用户可能刚去系统设置里开了无线数据。
    if (_net != _NetState.ok) {
      _probeFuture = null;
      await _ensureProbed();
      if (!mounted) return;
      // 留一点时间把结果画出来，再弹下一个系统框
      await Future.delayed(const Duration(milliseconds: 320));
      if (!mounted) return;
    }

    // ── 第 2~6 项：系统权限，严格串行 ──
    for (final r in _rows) {
      if (!mounted) return;
      var st = _status[r.perm];
      // 已授权 / 已被永久拒绝（系统不会再弹）→ 跳过，后面统一提示去设置
      if (st == null) continue;
      if (st.isGranted) continue;
      if (st == PermissionStatus.permanentlyDenied) continue;
      // 高亮当前这一项：让「一个一个问」这件事在界面上看得见
      setState(() => _activePerm = r.perm);
      try {
        await r.perm.request();
      } catch (_) {}
      // 等系统弹窗彻底收起，再问下一项（否则下一项会被吞掉）
      await Future.delayed(const Duration(milliseconds: 250));
      if (!mounted) return;
      // 回读系统真实状态（request 的返回值在「仅本次允许」等场景下不可靠）
      try {
        final after = await r.perm.status;
        if (!mounted) return;
        setState(() {
          _status[r.perm] = after;
          _activePerm = null;
        });
      } catch (_) {
        if (mounted) setState(() => _activePerm = null);
      }
    }
    if (!mounted) return;
    setState(() {
      _running = false;
      _activePerm = null;
    });
    await _refresh();

    final denied = _rows.where((r) {
      final s = _status[r.perm];
      return s != null && !s.isGranted;
    }).toList();
    if (!mounted) return;
    if (denied.isEmpty) {
      // 网络在队列开头已经探过，这里直接用结果判定
      if (_net == _NetState.offline) {
        CenterToast.show(
          context,
          '权限都开好了，但手机连不上服务器，点第一项查看怎么修',
          icon: Icons.wifi_off,
        );
        return;
      }
      CenterToast.show(context, '全部权限已开启，正在进入渔报',
          icon: Icons.check_circle);
      await Future.delayed(const Duration(milliseconds: 700));
      if (!mounted) return;
      await _done();
    } else {
      CenterToast.show(
        context,
        '还有 ${denied.length} 项未开启，可点对应项去系统设置里打开',
        icon: Icons.info_outline,
      );
    }
  }

  Future<void> _openSettings() async {
    await openAppSettings();
    // 从系统设置回来时刷新（用户可能刚打开某一项）
    await Future.delayed(const Duration(milliseconds: 400));
    if (mounted) await _refresh();
  }

  Future<void> _done() async {
    if (_finished) return;
    _finished = true;
    final prefs = await SharedPreferences.getInstance();
    // 只记「引导看过」；权限状态每次进来都重新读系统，不缓存
    await prefs.setBool(kPermOnboardDone, true);
    if (mounted) widget.onDone();
  }

  @override
  Widget build(BuildContext context) {
    final grantedPerms =
        _rows.where((r) => _status[r.perm]?.isGranted == true).length;
    // 「网络」也计入总数：它虽然不用点系统弹窗，但对用户来说就是一项能力，
    // 不计进去会出现「6 项全能用了却显示 5/5」的怪事。
    final netOk = _net == _NetState.ok;
    final total = _rows.length + 1;
    final grantedCount = grantedPerms + (netOk ? 1 : 0);
    final permsAll = grantedPerms == _rows.length;
    final allDone = permsAll && netOk;
    // 权限齐了但网络确实连不上 → 主按钮改成「去修」，别让用户空着点
    final netBlocked = permsAll && _net == _NetState.offline;

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: Column(
          children: [
            // ── 顶部品牌区 ──
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(22, 26, 22, 22),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [AppTheme.primaryDark, AppTheme.primary],
                ),
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(22),
                  bottomRight: Radius.circular(22),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('开启需要的权限',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 21,
                          fontWeight: FontWeight.w800)),
                  const SizedBox(height: 8),
                  Text(
                    '为了让渔报正常拍照、定位和提醒，\n请把这些权限都允许一下。系统会逐个弹窗确认。',
                    style: TextStyle(
                        color: Colors.white.withOpacity(0.9),
                        fontSize: 12.5,
                        height: 1.6),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Text('$grantedCount/$total',
                          style: const TextStyle(
                              color: AppTheme.star,
                              fontSize: 17,
                              fontWeight: FontWeight.w800)),
                      const SizedBox(width: 6),
                      Text('已开启',
                          style: TextStyle(
                              color: Colors.white.withOpacity(0.85),
                              fontSize: 12)),
                    ],
                  ),
                ],
              ),
            ),

            // ── 权限清单 ──
            Expanded(
              child: _reading
                  ? const Center(
                      child: CircularProgressIndicator(color: AppTheme.primary))
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
                      children: [
                        // 网络放第一项：它是登录/注册的前提，也是 iOS 那个
                        // 「是否允许使用无线数据」弹窗唯一能被触发的时机
                        _netTile(),
                        ..._rows.map(_tile),
                        const SizedBox(height: 2),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: Text(
                            '说明：点「一键开启全部权限」会从上往下一项一项问，'
                            '「网络」排在第一个。某行显示「去设置」表示之前拒绝过，'
                            '点它会跳到系统的「渔报」权限页。',
                            style: const TextStyle(
                                fontSize: 11.5,
                                height: 1.6,
                                color: AppTheme.textSecondary),
                          ),
                        ),
                      ],
                    ),
            ),

            // ── 底部按钮 ──
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: Column(
                children: [
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      onPressed: _running
                          ? null
                          : (allDone
                              ? _done
                              : (netBlocked ? _showNetHelp : _requestAll)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor:
                            netBlocked ? AppTheme.danger : AppTheme.primary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                            borderRadius:
                                BorderRadius.circular(AppTheme.radiusMd)),
                      ),
                      child: _running
                          // 用文字而不是转圈：这个按钮在「一键开启」期间要一直
                          // 显示进度，写清楚「正在开启第几项」比一个转圈更有用
                          ? const Text('正在开启…',
                              style: TextStyle(
                                  fontSize: 15, fontWeight: FontWeight.w700))
                          : Text(
                              allDone
                                  ? '进入渔报'
                                  : (netBlocked
                                      ? '网络未通，点这里修复'
                                      : '一键开启全部权限'),
                              style: const TextStyle(
                                  fontSize: 15, fontWeight: FontWeight.w700)),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextButton(
                          onPressed: _openSettings,
                          child: const Text('打开系统权限设置'),
                        ),
                      ),
                      Expanded(
                        child: TextButton(
                          // 网络确实不通时，文案改成「仍要先进入」：
                          // 不能因为网络问题把用户永久关在引导页里
                          onPressed: _done,
                          child: Text(allDone
                              ? '完成'
                              : (netBlocked ? '仍要先进入' : '以后再说')),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── 网络这一行 ────────────────────────────────────────────────

  /// 把底层英文异常压成半句话（完整堆栈留给修复弹窗里的「诊断详情」）
  String _shortNetReason() {
    final e = (_netResult?.tcpError ?? '').toLowerCase();
    if (e.contains('timed out') || e.contains('timeout')) {
      return '连接超时，多半是当前网络拦了端口';
    }
    if (e.contains('unreachable') || e.contains('no route')) {
      return '手机没有可用网络';
    }
    if (e.contains('refused')) return '服务器端口拒绝连接';
    if (e.contains('permission denied')) return '系统禁止了本 App 联网';
    if (e.contains('failed host lookup')) return '服务器地址解析失败';
    return '连不上服务器';
  }

  Widget _netTile() {
    final s = _net;
    final ok = s == _NetState.ok;
    final bad = s == _NetState.offline;
    final warn = s == _NetState.serverIssue;
    // idle 与 checking 都属于「还没结论」，视觉上必须和下面的权限项一模一样，
    // 不能一进页面就红着脸说用户网络有问题。
    final quiet = s == _NetState.idle || s == _NetState.checking;
    final checking = s == _NetState.checking;

    final Color tone = ok
        ? AppTheme.primary
        : bad
            ? AppTheme.danger
            : warn
                ? AppTheme.warning
                : AppTheme.textSecondary;
    final Color toneBg = ok
        ? AppTheme.primaryLight
        : bad
            ? AppTheme.dangerLight
            : warn
                ? AppTheme.warningLight
                : AppTheme.primarySoft;
    // 只有「探过且确实有问题」才换底色/描边，其余一律用和权限项相同的白卡
    final Color tileBg = bad
        ? AppTheme.dangerLight
        : warn
            ? AppTheme.warningLight
            : AppTheme.surface;
    final Color tileBorder = checking
        ? AppTheme.primary.withOpacity(0.45)
        : bad
            ? AppTheme.danger.withOpacity(0.35)
            : warn
                ? AppTheme.warning.withOpacity(0.35)
                : AppTheme.border;
    final IconData icon = ok
        ? Icons.wifi
        : bad
            ? Icons.wifi_off
            : warn
                ? Icons.dns_outlined
                : Icons.wifi;

    final String sub;
    if (checking) {
      sub = '正在检测能否连上服务器…';
    } else if (ok) {
      sub = '已连通 · ${_netResult?.tcpMs ?? 0} ms · 登录、钓点、天气都靠它';
    } else if (bad) {
      sub = _shortNetReason();
    } else if (warn) {
      sub = '网络已通，服务器接口异常（HTTP ${_netResult?.httpStatus ?? 0}）';
    } else {
      sub = '用于登录、注册、查看钓点与天气';
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 9),
      decoration: BoxDecoration(
        color: tileBg,
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        border: Border.all(color: tileBorder),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(AppTheme.radiusMd),
          // 空闲时整行也能点：等同点右侧「允许」
          onTap: checking
              ? null
              : (ok ? _reprobe : (quiet ? _requestNetOnly : _showNetHelp)),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: toneBg,
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Icon(icon, size: 20, color: tone),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Text('网络',
                              style: TextStyle(
                                  fontSize: 14.5, fontWeight: FontWeight.w700)),
                          if (bad || warn) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 5, vertical: 1),
                              decoration: BoxDecoration(
                                color: tone.withOpacity(0.12),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(bad ? '未连通' : '服务异常',
                                  style: TextStyle(
                                      fontSize: 9.5,
                                      fontWeight: FontWeight.w700,
                                      color: tone)),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(sub,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 11.5,
                              height: 1.35,
                              color: bad || warn ? tone : AppTheme.textSecondary)),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                // 右侧三态与权限项保持同一套语言：允许 → 检测中 → 打勾。
                // 这里用文字而不是小菊花：14px 的转圈在真机上一闪而过，
                // 静态截图里更是只剩一个点，用户根本看不出「正在检测」。
                if (checking)
                  const Text('检测中',
                      style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.primary))
                else if (ok && !_running)
                  const Icon(Icons.check_circle,
                      color: AppTheme.primary, size: 21)
                else if (quiet)
                  TextButton(
                    onPressed: _running ? null : _requestNetOnly,
                    style: TextButton.styleFrom(
                      foregroundColor: AppTheme.primary,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: const Text('允许',
                        style: TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w700)),
                  )
                else
                  TextButton(
                    onPressed: _showNetHelp,
                    style: TextButton.styleFrom(
                      foregroundColor: tone,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: const Text('去修复',
                        style: TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w700)),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 只处理网络这一项（用户单独点「允许」时用），不动其余权限
  Future<void> _requestNetOnly() async {
    if (_running) return;
    setState(() => _running = true);
    _probeFuture = null;
    await _ensureProbed();
    if (!mounted) return;
    setState(() => _running = false);
  }

  /// 网络连不上时给**能照着做**的路径，而不是一句「请检查网络」。
  ///
  /// iOS 的「无线数据」开关根本不在 App 自己的设置页里，所以必须把
  /// 「设置 → 蜂窝网络 → 渔报」这条路径写死在界面上。
  Future<void> _showNetHelp() async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTheme.radiusLg)),
        titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
        contentPadding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
        actionsPadding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
        title: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: AppTheme.dangerLight,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.wifi_off,
                  size: 18, color: AppTheme.danger),
            ),
            const SizedBox(width: 10),
            const Expanded(
              child: Text('网络连不上怎么办',
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.textPrimary)),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _net == _NetState.offline
                    ? '手机现在连不到服务器。按下面三步处理，多半能好：'
                    : '手机能上网，但服务器没正常回数据 —— 这不是你这边的网络问题，'
                        '可以先进入 App，稍后再试。',
                style: const TextStyle(
                    fontSize: 12.5, height: 1.6, color: AppTheme.textPrimary),
              ),
              const SizedBox(height: 12),
              const NetFixSteps(),
              // 诊断详情：折叠在下面，用户要发我截图时能直接复制
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppTheme.primarySoft,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppTheme.border),
                ),
                child: SelectableText(
                  _netResult?.summary ?? '尚未检测',
                  style: const TextStyle(
                      fontSize: 10.5, height: 1.5, color: AppTheme.textSecondary),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(
                  ClipboardData(text: _netResult?.summary ?? '尚未检测'));
              Navigator.of(ctx).pop();
              CenterToast.show(context, '诊断详情已复制');
            },
            child: const Text('复制诊断',
                style: TextStyle(fontSize: 13, color: AppTheme.textSecondary)),
          ),
          TextButton(
            onPressed: () async {
              Navigator.of(ctx).pop();
              await _openSettings();
              await _reprobe();
            },
            child: const Text('打开设置',
                style: TextStyle(fontSize: 13, color: AppTheme.textSecondary)),
          ),
          TextButton(
            onPressed: () async {
              Navigator.of(ctx).pop();
              await _reprobe();
            },
            child: const Text('重新检测',
                style: TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  Widget _tile(_PermRow r) {
    final st = _status[r.perm];
    final granted = st?.isGranted ?? false;
    final blocked = st == PermissionStatus.permanentlyDenied;
    // 队列正轮到这一项：淡主色底 + 主色描边，右侧换成菊花
    final active = _activePerm == r.perm;
    return Container(
      margin: const EdgeInsets.only(bottom: 9),
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
      decoration: BoxDecoration(
        color: active ? AppTheme.primarySoft : AppTheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        border: Border.all(
            color: active
                ? AppTheme.primary.withOpacity(0.45)
                : AppTheme.border),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: granted ? AppTheme.primaryLight : AppTheme.primarySoft,
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(r.icon,
                size: 20,
                color: granted ? AppTheme.primary : AppTheme.textSecondary),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(r.title,
                    style: const TextStyle(
                        fontSize: 14.5, fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(r.desc,
                    style: const TextStyle(
                        fontSize: 11.5, color: AppTheme.textSecondary)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (active)
            const Text('设置中',
                style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.primary))
          else if (granted)
            const Icon(Icons.check_circle,
                color: AppTheme.primary, size: 21)
          else
            TextButton(
                onPressed: (_running || _reading)
                    ? null
                    : () async {
                        if (blocked) {
                          await _openSettings();
                          return;
                        }
                        try {
                          await r.perm.request();
                        } catch (_) {}
                        if (mounted) await _refresh();
                      },
                style: TextButton.styleFrom(
                  foregroundColor:
                      blocked ? AppTheme.danger : AppTheme.primary,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(blocked ? '去设置' : '允许',
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w700)),
              ),
        ],
      ),
    );
  }
}

/// 首次启动的权限引导闸门：只在「本机第一次装好并打开」时出现一次。
///
/// 判定用 SharedPreferences 的布尔标记 —— 卸载重装会清掉，正好符合
/// 「每次安装后都要重新确认一遍权限」的预期。
///
/// ★ v2（v2.1.63）：key 从 `perm_onboard_done_v1` 升到 v2，**故意换名**。
///   原因是这一版才把「网络」加进清单，而已经在用 v2.1.62 的用户本地
///   早就写了 v1 标记 —— 不换名的话他们升级后根本看不到新的一项，
///   也就永远不知道连不上是「无线数据」被禁了。
///   代价是老用户升级后会再看一次这个页；但页面逻辑里「权限已全开 + 网络正常
///   → 450ms 自动跳过」，他们基本无感，代价可以接受。
const String kPermOnboardDone = 'perm_onboard_done_v2';

class FirstRunPermissionGate extends StatefulWidget {
  const FirstRunPermissionGate({super.key, required this.child});

  final Widget child;

  @override
  State<FirstRunPermissionGate> createState() => _FirstRunPermissionGateState();
}

class _FirstRunPermissionGateState extends State<FirstRunPermissionGate> {
  bool _checking = true;
  bool _needOnboard = false;

  @override
  void initState() {
    super.initState();
    _check();
  }

  /// 注意：必须等主界面挂载之后（postFrame）才读偏好，
  /// 否则会和启动帧抢平台通道，启动那一刻卡一下。
  Future<void> _check() async {
    var need = false;
    try {
      final prefs = await SharedPreferences.getInstance();
      need = !(prefs.getBool(kPermOnboardDone) ?? false);
    } catch (_) {
      need = false;
    }
    if (!mounted) return;
    setState(() {
      _needOnboard = need;
      _checking = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    // 判定「是不是第一次」这一两帧：先铺一个纯底色，**不要**先把主界面渲染出来。
    // 否则 MainShell 会先 build 一次、触发首页请求和定位权限弹窗，紧接着又被
    // 引导页替换掉 —— 用户会看到「首页闪一下 + 定位框先弹出来」。
    if (_checking) {
      return const ColoredBox(color: AppTheme.background);
    }
    if (_needOnboard) {
      return PermissionOnboardScreen(
        onDone: () => setState(() => _needOnboard = false),
      );
    }
    return widget.child;
  }
}
