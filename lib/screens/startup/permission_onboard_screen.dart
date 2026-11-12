import 'dart:async';
import 'dart:io' show Platform;

// CupertinoAlertDialog 只用来画「系统权限框同款」的网络授权框（见 _askNetIntro）
import 'package:flutter/cupertino.dart'
    show
        CupertinoAlertDialog,
        CupertinoColors,
        CupertinoDialogAction,
        CupertinoTheme;
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
    this.debugSkipAutoExit = false,
    this.debugNetWait = const Duration(seconds: 40),
    this.debugNetPollGap = const Duration(milliseconds: 1000),
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

  /// 测试用：关掉「权限齐了就自动放行」。
  ///
  /// 「设置完成」那一页只有在队列真正跑完时才会出现，而 `debugGrantPerms`
  /// 全授予的瞬间就会触发自动放行 —— 两者撞在一起，那一页根本来不及被断言。
  /// 生产路径永远传默认值 false。
  final bool debugSkipAutoExit;

  /// 「网络」这一项一次最多等多久（默认 40 秒）。
  ///
  /// ★ 这不是「一次请求的超时」，而是**整个网络步骤的预算**：
  ///   iOS 的「无线数据」弹窗挂着的时候，socket 并不会傻等，而是**立刻**
  ///   返回 `Network is unreachable` —— 所以「等一下再判」这件事只能靠
  ///   反复重试来做，单次超时设多长都没用（v2.1.67 的真实教训）。
  ///   测试里把它调小，才不用真的等 40 秒。
  final Duration debugNetWait;

  /// 每次重试之间隔多久（默认 1 秒）。同上，只为测试可调。
  final Duration debugNetPollGap;

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

class _PermissionOnboardScreenState extends State<PermissionOnboardScreen>
    with WidgetsBindingObserver {
  /// 顺序即展示/申请顺序：通知 → 定位 → 相机 → 麦克风 → 相册
  static const List<_PermRow> _rows = [
    _PermRow(Permission.notification, Icons.notifications_active_outlined, '通知',
        '私信、评论、点赞、官方公告的提醒'),
    _PermRow(Permission.locationWhenInUse, Icons.location_on_outlined, '位置信息',
        '附近钓友、钓点导航、本地天气与渔获定位'),
    _PermRow(
        Permission.camera, Icons.camera_alt_outlined, '相机', '发布渔获时拍照、录像，拍钓点'),
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

  /// 六项全部就绪 → 整页切到「设置完成」，让用户看清结果再进下一步。
  ///
  /// 原来只弹一个 700ms 的 toast「全部权限已开启，正在进入渔报」，
  /// 用户刚在系统弹窗之间来回切，回来只看到页面已经被换掉，
  /// 感受上像「跳了一下」而不是「设置好了」。现在给一个明确的落点。
  bool _allSet = false;

  /// 探测只跑一次，重复调用复用同一个 Future（避免连点弹出多次请求）
  Future<void>? _probeFuture;

  /// 引导页里每一次网络探测最多等多久。
  ///
  /// ★ v2.1.66 曾把这里从 6 秒加到 15 秒，以为「等久一点用户就点得到」——
  /// 实测不成立：iOS 的「是否允许使用无线数据」弹窗挂着时，`Socket.connect`
  /// **不会挂住**，而是立刻抛 `Network is unreachable`。所以真正要改的不是
  /// 单次超时，而是「失败之后继续重试，直到拿到结果」。
  static const Duration _probeAttemptTimeout = Duration(seconds: 6);

  /// 按钮上「正在开启第几项」的文案（null 用 [_idleRunningLabel]）
  static const String _idleRunningLabel = '正在开启…';
  String _runningLabel = _idleRunningLabel;

  /// 本轮网络步骤已经重试了几次（只用于把说法从「请点允许」切到「还在等」）
  int _netAttempts = 0;

  /// 用来「立刻打断两次重试之间的等待」：用户从系统设置切回来时不必再等一秒
  Completer<void>? _pollKick;

  /// 系统授权框（相机 / 通知 / 以及 iOS 的「允许使用无线数据」）盖上来时，
  /// App 会先被置成 `inactive` —— 这是**唯一**能"看见"系统弹窗的信号。
  ///
  /// ★ v2.1.68 用它把两种长得一模一样的失败分开：
  ///   · 见过 inactive → 用户正在看那个框，**一直等到他点**，绝不抢先判红；
  ///   · 没见过 → 系统压根不会弹（iOS 一个 App 只问一次，记成「不允许」后
  ///     不再问），再等一百年也是同一个结果，必须立刻给 App 侧的授权框。
  ///   v2.1.67 只有"一直等"这一条路，于是用户在「请求中」里干等到 40 秒，
  ///   既看不到系统框也看不到任何可操作的东西 —— 就是这一版要修的。
  bool _promptSeen = false;

  /// 本轮已经用 App 自己的框补过「无线数据」这一课，避免收尾时再弹一遍
  bool _netDialogShown = false;

  /// ★ v2.1.92：首次安装点「一键开启」时，网络这一项先弹的**授权确认框**
  /// 是否已经弹过（一次引导只弹一次，避免反复打断）
  bool _netIntroShown = false;

  /// 用户在授权框里点了「不允许」→ 不算「被系统挡住」，
  /// 文案也不能说成"连不上服务器"
  bool _netDeclined = false;

  /// 等用户从系统设置回到前台（用 completer 而不是死等固定时长）
  Completer<void>? _foregroundWait;

  /// 打开设置后 App 是否真的退到过后台 —— 决定要不要一直等到 resumed，
  /// 免得某些机型「设置」没跳出去、这边死等两分钟。
  bool _leftForeground = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
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

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (!(_pollKick?.isCompleted ?? true)) _pollKick!.complete();
    _pollKick = null;
    if (!(_foregroundWait?.isCompleted ?? true)) _foregroundWait!.complete();
    _foregroundWait = null;
    super.dispose();
  }

  /// 生命周期是判断「系统到底弹没弹框」的唯一依据。
  ///
  /// 从系统设置 / 系统弹窗切回来时立刻补探一次，不用再干等下一拍。
  ///
  /// 典型路径：网络项红了 → 点「去打开设置」→ 在设置里把「无线数据」打开 →
  /// 切回 App。没有这一下，要等满 1 秒的轮询间隔才动；有了它，回来即刷新。
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // ★ 系统授权框一盖上来，App 立刻转 inactive，框收起后回到 resumed。
    //   等「允许使用无线数据」的时候把这个记号留下，用来区分
    //   「用户在读框」和「系统根本不会弹」（见 [_promptSeen]）。
    if (state == AppLifecycleState.inactive) {
      _leftForeground = true;
      if (_running && _net == _NetState.checking && !_promptSeen) {
        setState(() => _promptSeen = true);
      }
      return;
    }
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _leftForeground = true;
      return;
    }
    if (state != AppLifecycleState.resumed) return;
    if (!mounted) return;
    // 有人在等「用户从设置回来」→ 先把他叫醒
    final fw = _foregroundWait;
    if (fw != null && !fw.isCompleted) fw.complete();
    final c = _pollKick;
    if (c != null && !c.isCompleted) {
      c.complete();
      return;
    }
    if (_running) return;
    if (_net == _NetState.offline) {
      // 只是回来看一眼：不去抢「一键开启」的队列，只安静地重探一次
      _reprobe();
    }
  }

  /// 网络探测（结果缓存在 [_net] / [_netResult]）
  ///
  /// [timeout] 为空时用 NetDiag 的默认 6 秒（静默自检、权限已全开的升级用户）；
  /// 用户主动点「允许 / 一键开启」时传 [_probeAttemptTimeout]。
  /// [holdOnTimeout]：超时先不下结论，交给 [_waitNetReady] 决定要不要重试。
  Future<void> _ensureProbed({Duration? timeout, bool holdOnTimeout = false}) =>
      _probeFuture ??= _doProbe(timeout, holdOnTimeout: holdOnTimeout);

  static bool _isTimeoutError(String e) {
    final s = e.toLowerCase();
    return s.contains('timed out') || s.contains('timeout');
  }

  Future<void> _doProbe(Duration? timeout, {bool holdOnTimeout = false}) async {
    if (mounted) setState(() => _net = _NetState.checking);
    NetDiagResult r;
    try {
      final t = timeout;
      r = await (widget.probeNet ??
          () => t == null
              ? NetDiag.run()
              : NetDiag.run(
                  tcpTimeout: t,
                  httpTimeout: t,
                ))();
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
        // 超时大概率是「系统弹窗还挂着，用户正在看」：先留在「请求中」，
        // 等 [_waitNetReady] 重试一轮再下结论。直接挂红脸会出现
        // 「红 1 秒 → 绿」的闪动，用户还以为刚才那次失败是要自己处理的。
        _net = holdOnTimeout && _isTimeoutError(r.tcpError)
            ? _NetState.checking
            : _NetState.offline;
      } else if (r.httpStatus == 200) {
        _net = _NetState.ok;
      } else {
        _net = _NetState.serverIssue;
      }
    });
    _maybeAutoExit();
  }

  /// 重新探测（用户点「重新检测」/ 整行时用，强制重跑）
  Future<void> _reprobe() async {
    if (_running) return;
    setState(() {
      _running = true;
      _runningLabel = '正在检测网络…';
    });
    await _waitNetReady();
    if (!mounted) return;
    setState(() {
      _running = false;
      _runningLabel = _idleRunningLabel;
    });
  }

  /// 这次失败是不是「等回应等超时」——只用于弹窗说法的措辞。
  bool get _netMaybeWaiting => _isTimeoutError(_netResult?.tcpError ?? '');

  /// 等到网络真的通，或者等够预算为止。**返回这一次到底通没通。**
  ///
  /// ★ v2.1.67 的核心修复（用户原话：「点了无线数据之后应该显示已完成，
  ///   然后进行下一项的权限开启，现在直接说网络被挡住了」）：
  ///
  ///   iOS 的「允许使用无线数据」弹窗**挂着**的时候，`Socket.connect` 不会
  ///   一直等 —— 它立刻抛 `Network is unreachable`。所以：
  ///     · 把单次超时从 6 秒加到 15 秒（v2.1.66 的做法）**根本没用**，
  ///       因为失败不是超时，是秒失败；
  ///     · 「失败就补探一次」也不够，用户从看到弹窗到点下去常常超过两次重试；
  ///
  ///   现在的做法：失败**不下结论**，停在「请求中」按 [_netPollGap] 反复重试，
  ///   直到通了（→ 这一项打勾「已完成」，队列自动走下一项）或者用光
  ///   [debugNetWait] 的预算（→ 才如实标红并给修复路径）。
  ///   这条路径对「去设置里打开开关再切回来」同样成立（resumed 会立刻打断等待）。
  Future<bool> _waitNetReady() async {
    final sw = Stopwatch()..start();
    _netAttempts = 0;
    _promptSeen = false;
    // 预算换算成「最多重试几轮」。两个上限同时生效：
    //   · 轮数 —— 保证界面不会无限转（也保证 widget 测试能停在确定的一拍上）；
    //   · 墙钟 —— 防止每次都卡满单次超时（6 秒）时把 40 秒拖成好几分钟。
    final gapMs = widget.debugNetPollGap.inMilliseconds;
    final waitMs = widget.debugNetWait.inMilliseconds;
    final maxAttempts =
        gapMs <= 0 ? 1 : ((waitMs / gapMs).ceil()).clamp(1, 1000);
    // 已经「等」了多久：按轮询间隔累加。
    // 不能只靠 Stopwatch —— widget 测试里时钟是假的，Stopwatch 走的仍是真实时间，
    // 那样「2 秒收手」这条规则在测试里永远不成立（也就守不住）。
    var waitedMs = 0;
    while (mounted) {
      _netAttempts++;
      _probeFuture = null;
      await _ensureProbed(
        timeout: _probeAttemptTimeout,
        holdOnTimeout: true,
      );
      if (!mounted) return false;
      // 通了（端口通就算通，接口 500 是服务端的事，不该拦用户）→ 收工
      if (_net == _NetState.ok || _net == _NetState.serverIssue) return true;
      // 还没通：**先别落红**。系统弹窗很可能还挂在屏幕上等着被点，
      // 这时候把「未连通」挂出来，用户一点「允许」就会看到一张红脸 —— 那正是
      // 他报的那个 bug。停在「请求中」，等下一拍再说。
      setState(() => _net = _NetState.checking);
      if (sw.elapsed >= widget.debugNetWait || _netAttempts >= maxAttempts) {
        break;
      }
      // ★ 早退：系统授权框**一次都没出现过**，而且连接是「秒失败」。
      //
      //   两条同时成立意味着系统压根不打算问了（iOS 的「无线数据」一个 App
      //   只问一次，之前选过「不允许」就不再问）。这时再等 40 秒，用户看到的
      //   就是「一直请求中、什么都不弹」—— 正是这次报的问题。
      //
      //   为什么必须排除「卡满超时」：如果 connect 是挂满 6 秒才失败，那更像是
      //   系统弹窗把连接攥在手里、用户正在看框（只是我们的 inactive 没收到），
      //   这种情况必须继续等，不能抢先判死。
      final bool instantFail = !_isTimeoutError(_netResult?.tcpError ?? '');
      final bool gaveUp = !_promptSeen &&
          instantFail &&
          _netAttempts >= 3 &&
          (waitedMs >= 1200 ||
              sw.elapsed >= const Duration(milliseconds: 1200));
      if (gaveUp) break;
      await _pollGap(widget.debugNetPollGap);
      waitedMs += gapMs;
      if (!mounted) return false;
    }
    if (!mounted) return false;
    // 预算用光了还是不通：这才落定「未连通」。
    setState(() => _net = _NetState.offline);
    return false;
  }

  /// 两次重试之间的等待，可被 [_kickPoll] 提前打断（切回前台 / 页面销毁）。
  Future<void> _pollGap(Duration gap) async {
    final c = Completer<void>();
    _pollKick = c;
    final timer = Timer(gap, () {
      if (!c.isCompleted) c.complete();
    });
    try {
      await c.future;
    } finally {
      timer.cancel();
      if (identical(_pollKick, c)) _pollKick = null;
    }
  }

  Future<void> _refresh() async {
    final map = <Permission, PermissionStatus>{};
    final forced = widget.debugGrantPerms;
    for (final r in _rows) {
      if (forced != null) {
        map[r.perm] =
            forced ? PermissionStatus.granted : PermissionStatus.denied;
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
    if (widget.debugSkipAutoExit) return;
    if (_finished || _autoExit) return;
    // 一键开启进行中 / 已经进了完成态：收尾交给 _requestAll，
    // 这条「静默放行」的路不能再插一脚，否则完成页会被顶掉。
    if (_running || _allSet) return;
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
    setState(() {
      _running = true;
      _runningLabel = _idleRunningLabel;
    });

    // ── 第 1 项：网络 ──
    // 已经确认连通就不重复探（省一次往返，也不重复打扰系统弹窗）；
    // 之前失败或从没探过则重探 —— 用户可能刚去系统设置里开了无线数据。
    setState(() => _runningLabel = '正在开启 1/${_rows.length + 1}：网络');
    var netOk = true;
    // ★ v2.1.92：网络也走一次「授权框」。
    //
    //   用户反馈（截图）：相机、通知都会弹系统框，唯独网络那一项直接变成
    //   「已完成」—— 看起来像漏了一步，「是不是没真的开」。
    //
    //   事实是网络没有可申请的系统权限（Android 的 INTERNET 安装即授予，
    //   iOS 只有「是否允许使用无线数据」这个不可主动请求的框），所以这里
    //   补一个 App 侧的确认框，把「这一项也要你点头」这件事做实：
    //   点「允许」→ 立刻探一次（顺势触发 iOS 那个系统框）；
    //   点「不允许」→ 如实标成未允许，队列继续问后面五项。
    //
    // ★ v2.1.93：触发条件去掉了 `_net == _NetState.idle`。
    //
    //   进这个页时后台已经在探网络（[_probe]），用户点按钮时 `_net` 通常已经是
    //   `checking` / `offline` 了 —— 旧条件于是直接跳过授权框，紧接着
    //   `_waitNetReady()` 失败、弹出「无线数据还没有授权」那个修复框。
    //   用户看到的就是「首次安装没有授权框，只有一张报错卡」（图二）。
    //   现在只要本轮没问过、也没被拒过，就先问这一下。
    if (!_netIntroShown && !_netDeclined) {
      final allow = await _askNetIntro();
      if (!mounted) return;
      if (!allow) {
        setState(() {
          _net = _NetState.offline;
          _netDeclined = true;
        });
        // 已经在框里把话说清楚了，收尾时就别再弹一次修复框
        _netDialogShown = true;
        netOk = false;
      }
    }
    if (netOk && _net != _NetState.ok) {
      netOk = await _waitNetReady();
      if (!mounted) return;
      // ★ v2.1.93：**不再**在这里自动弹「无线数据还没有授权」的修复框。
      //
      //   首次安装时那个框会在用户刚点完「允许」之后立刻盖上来，说的却是
      //   「系统没有弹出授权框，你之前选了不允许」—— 用户刚点完允许，
      //   等于当面说他说谎（用户截图图二就是这么来的，明确要求去掉）。
      //   网络没通就如实标「未连通」，右侧留「去修复」按钮让用户自己决定
      //   要不要看排查步骤；队列继续往下问，不打断。
    }
    if (netOk) {
      // ★ 用户要的正是这一拍：「点完系统弹窗 → 这一项显示已完成 → 再问下一项」。
      //   所以在这里把「已完成」明明白白停一下，而不是通了之后立刻跳去弹通知框。
      setState(() => _runningLabel = '网络已完成 · 1/${_rows.length + 1}');
      await Future.delayed(const Duration(milliseconds: 560));
      if (!mounted) return;
    } else {
      // 还没通。**不在这里再弹一次框打断队列**：先让剩下五项照常问完，
      // 队列末尾再统一处理网络（那时系统弹窗早就收起了，判断才可信）。
      await Future.delayed(const Duration(milliseconds: 360));
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
      setState(() {
        _activePerm = r.perm;
        final i = _rows.indexOf(r);
        _runningLabel = '正在开启 ${i + 2}/${_rows.length + 1}：${r.title}';
      });
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

    // 队列跑完，先算出还差哪几项（状态在循环里已经逐个回读过，是最新的）
    final denied = _rows.where((r) {
      final s = _status[r.perm];
      return s != null && !s.isGranted;
    }).toList();

    // ★ 全部就绪 → 先立「设置完成」态，**再** refresh。
    //
    //   顺序不能反：`_refresh()` 内部会调 `_maybeAutoExit()`，那条路径会在
    //   450ms 后直接 `_done()`，把刚画出来的完成页顶掉 —— 用户只会看到
    //   页面闪一下就被换成登录页。先立 `_allSet`，自动退出那条路就自动让位。
    if (denied.isEmpty && _net != _NetState.offline) {
      setState(() {
        _running = false;
        _activePerm = null;
        _runningLabel = _idleRunningLabel;
        _allSet = true;
      });
      await _refresh();
      if (!mounted) return;
      // 停一下再进登录/首页：用户刚连续点完五六个系统弹窗，需要一个明确的
      // 「办完了」的落点，而不是页面直接跳走。
      await Future.delayed(const Duration(milliseconds: 1200));
      if (!mounted) return;
      await _done();
      return;
    }

    setState(() {
      _running = false;
      _activePerm = null;
      _runningLabel = _idleRunningLabel;
    });
    await _refresh();
    if (!mounted) return;

    if (denied.isEmpty) {
      // 只剩「权限都开了但网络确实连不上」这一种。
      // 到这一步五项系统弹窗都问完了，用户交互过五六次，系统那个「无线数据」
      // 弹窗早就收起 —— 此时再说「被挡住了」不会冤枉人，也给得出下一步。
      //
      // v2.1.68：网络那一步已经用 App 的框说过一次（[_netDialogShown]），
      // 就别在收尾时再弹一遍同样的内容，否则连着两个框只会让人烦。
      if (!_netDialogShown) await _promptNetBlocked();
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
    // 六项全部就绪 → 「设置完成」整页态（停 1.2 秒再进登录/首页）
    if (_allSet) return _doneView();

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
                            '「网络」排在第一个。iOS 的「允许使用无线数据」就在'
                            '那一下弹出；如果没弹（之前选过「不允许」，系统只问'
                            '一次），会直接给出打开设置的入口。',
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
                        // 「正在开启 2/6：通知」这类进度文本必须看得清：
                        // 默认的 disabled 前景是灰的，压在深底上几乎读不出来。
                        disabledBackgroundColor:
                            (netBlocked ? AppTheme.danger : AppTheme.primary)
                                .withOpacity(0.72),
                        disabledForegroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                            borderRadius:
                                BorderRadius.circular(AppTheme.radiusMd)),
                      ),
                      child: _running
                          // 用文字而不是转圈：这个按钮在「一键开启」期间要一直
                          // 显示进度，写清「正在开启第几项 · 哪一项」比一个转圈
                          // 有用得多 —— 用户就知道此刻弹出来的框是第几项。
                          ? Text(_runningLabel,
                              style: const TextStyle(
                                  fontSize: 15, fontWeight: FontWeight.w700))
                          : Text(
                              allDone
                                  ? '进入渔报'
                                  : (netBlocked ? '网络未通，点这里修复' : '一键开启全部权限'),
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
                          child: Text(
                              allDone ? '完成' : (netBlocked ? '仍要先进入' : '以后再说')),
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

  // ── 设置完成态 ────────────────────────────────────────────────

  /// 六项全部开启后的落点页。
  ///
  /// 用户要求的完整顺序是：启动页 → 权限清单 → 点「一键开启全部权限」→
  /// 一项项弹系统框 → **显示设置完成** → 进登录注册页。这一页就是那个
  /// 「设置完成」，它必须自己占满一屏、有明显的成功标志，不能只是一条
  /// 一闪而过的 toast。
  Widget _doneView() {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 用品牌青柠色打底、黑勾，和启动页那张「鱼跃」是同一套色：
              // 这是整条流程里唯一的成功态，值得让它一眼就「亮」起来，
              // 而不是一张灰白圆片上画一个近黑的勾（截图里几乎看不出是绿的）。
              Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  color: AppTheme.accent,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: AppTheme.accent.withOpacity(.45),
                      blurRadius: 26,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: const Icon(Icons.check_rounded,
                    size: 54, color: AppTheme.primary),
              ),
              const SizedBox(height: 26),
              const Text('设置完成',
                  style: TextStyle(
                      fontSize: 23,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.textPrimary)),
              const SizedBox(height: 12),
              Text(
                '${_rows.length + 1} 项权限已全部开启',
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 13.5, height: 1.7, color: AppTheme.textSecondary),
              ),
              const SizedBox(height: 10),
              // 不用转圈：这一页只停 1.2 秒，转圈既看不清，还会在
              // widget 测试收尾时留下一个仍在跑的 ticker（测试直接失败）。
              const Text('正在进入渔报…',
                  style:
                      TextStyle(fontSize: 12.5, color: AppTheme.textSecondary)),
            ],
          ),
        ),
      ),
    );
  }

  // ── 网络这一行 ────────────────────────────────────────────────

  /// 把底层英文异常压成半句话（完整堆栈留给修复弹窗里的「诊断详情」）
  String _shortNetReason() {
    // 用户自己在授权框里点了「不允许」：这不是故障，别拿网络异常的说法糊弄
    if (_netDeclined) return '你选择了不允许 · 登录需要联网';
    final e = (_netResult?.tcpError ?? '').toLowerCase();
    // ENETUNREACH / no route：iOS 关掉本 App 的「无线数据」就是这个表现。
    // 说成「手机没有可用网络」会把人指去重启路由器 —— 全错。
    if (e.contains('unreachable') ||
        e.contains('no route') ||
        e.contains('permission denied')) {
      // ★ 这里的路径必须分平台：iOS 那个开关在 App 自己的设置页里叫
      //   「无线数据」，安卓叫「流量使用」，写错一条就等于把人指进死胡同。
      return Platform.isIOS ? '被系统禁网：设置 → 渔报 → 无线数据' : '被系统限网：设置 → 应用 → 渔报';
    }
    if (e.contains('timed out') || e.contains('timeout')) {
      return '连接超时，当前网络可能拦了端口';
    }
    if (e.contains('refused')) return '服务器端口拒绝连接';
    if (e.contains('failed host lookup')) return '服务器地址解析失败';
    return '连不上服务器，点右侧「去修复」';
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
      // ★ 用户主动点「一键开启 / 允许」时，这一下就是 iOS 弹「是否允许使用
      //   无线数据」的时刻。必须在这里把话说出来 —— 否则弹窗被点掉了，
      //   用户也不知道刚才那是网络授权，只会看到下面紧接着弹通知框。
      if (!_running) {
        sub = '正在检测能否连上服务器…';
      } else if (_promptSeen) {
        // 系统框确实弹出来了（App 被压成 inactive，见 [_promptSeen]）
        sub = '系统弹窗已弹出：请点「无线局域网与蜂窝网络」';
      } else if (_netAttempts <= 1) {
        sub = '正在发起联网请求：弹出「允许使用无线数据」请点允许';
      } else {
        // 没收到任何「系统弹了个框」的信号：不骗人，直说在确认
        sub = '系统没有弹授权框，正在确认…';
      }
    } else if (ok) {
      // 通了以后只留事实（耗时）。原来还挂着「登录、钓点、天气都靠它」，
      // 在 320dp 窄屏上会被折成「登 / 录…」这种断词，右侧又多了「已完成」，
      // 反而更挤 —— 用途说明放在还没开启时的中性态里就够了。
      sub = '已连通 · ${_netResult?.tcpMs ?? 0} ms';
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
          // 空闲时整行也能点：等同点右侧「允许」。
          // 一键开启进行中一律锁住，否则会在队列外插一次探测。
          onTap: (_running || checking)
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
                              color:
                                  bad || warn ? tone : AppTheme.textSecondary)),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                // 右侧三态与权限项保持同一套语言：允许 → 检测中 → 打勾。
                // 这里用文字而不是小菊花：14px 的转圈在真机上一闪而过，
                // 静态截图里更是只剩一个点，用户根本看不出「正在检测」。
                if (checking)
                  Text(_running ? (_promptSeen ? '请点允许' : '请求中') : '检测中',
                      style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.primary))
                else if (ok)
                  // 已连通就一律「已完成」—— 包括「一键开启」正进行到后面几项时。
                  // 原来这里带 !_running，导致网络已经通了、右侧却还写着
                  // 「去修复」（截图核对时发现的），像在报错。
                  // v2.1.67 起把「完成」两个字写出来：用户对这一步的预期
                  // 就是「点完系统弹窗，这一项变成已完成」，一个光秃秃的勾
                  // 不够明确。
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      Icon(Icons.check_circle,
                          color: AppTheme.primary, size: 19),
                      SizedBox(width: 4),
                      Text('已完成',
                          style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.primary)),
                    ],
                  )
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
    // 重新点「允许」= 推翻上一次的「不允许」
    if (_netDeclined) {
      setState(() {
        _netDeclined = false;
        _net = _NetState.idle;
      });
    }
    setState(() {
      _running = true;
      _runningLabel = '正在请求网络权限…';
    });
    await _waitNetReady();
    if (!mounted) return;
    // ★ v2.1.93：不再自动弹「无线数据还没有授权」的修复框（用户明确要求去掉）。
    //   没通就如实标「未连通」，右侧留「去修复」让用户自己点。
    setState(() {
      _running = false;
      _runningLabel = _idleRunningLabel;
    });
  }

  /// 「网络」这一项的**授权框**（首次安装点「一键开启」时第一个出现）
  ///
  /// ★ v2.1.93：改成和系统权限框**同一个样子**。
  ///
  ///   用户原话：「我要图三那样的」——图三是 iOS 相机那个系统框：白底圆角、
  ///   标题加粗居中、一句说明、下面一条细分割线、左右两个蓝色按钮
  ///   「不允许 / 允许」。所以这里不用 App 自己的卡片式样式（那看着像
  ///   「出错了」的提示），直接用 CupertinoAlertDialog 画一个同款。
  ///
  ///   网络本身没有可申请的系统权限（安卓 INTERNET 安装即授予，iOS 的
  ///   「允许使用无线数据」由系统在 App 首次联网时自己决定弹不弹、
  ///   一个 App 只问一次），所以这一框由 App 代劳 —— 但样式、文案、按钮
  ///   顺序都跟系统一致，用户不会觉得「这里少了一步」。
  ///
  /// 返回值：true = 允许联网（继续探测）；false = 用户选了不允许。
  Future<bool> _askNetIntro() async {
    _netIntroShown = true;
    final ios = Theme.of(context).platform == TargetPlatform.iOS;
    final allow = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        if (ios) {
          // iOS：系统同款。标题 17pt 半粗、正文 13pt、按钮蓝色，
          // 全部由 CupertinoAlertDialog 自己按 HIG 给，不要覆盖。
          //
          //  ★ 必须把 primaryColor 钉成 iOS 系统蓝：
          //    这个 App 的品牌主色是近黑（AppTheme.primary = #07080C），
          //    MaterialApp 会把它塞进 CupertinoTheme 的 primaryColor，
          //    CupertinoDialogAction 的按钮于是变黑 —— 和系统框差得远。
          return CupertinoTheme(
            data: CupertinoTheme.of(ctx)
                .copyWith(primaryColor: CupertinoColors.activeBlue),
            child: CupertinoAlertDialog(
              title: const Text('“渔报”想使用无线数据'),
              content: const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Text('用于登录注册、查看附近钓场和实时渔情天气。'),
              ),
              actions: [
                CupertinoDialogAction(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child: const Text('不允许'),
                ),
                CupertinoDialogAction(
                  key: const ValueKey('net-allow'),
                  isDefaultAction: true,
                  onPressed: () => Navigator.of(ctx).pop(true),
                  child: const Text('允许'),
                ),
              ],
            ),
          );
        }
        // 安卓：保持 Material，但按钮文案与顺序跟系统一致
        return AlertDialog(
          backgroundColor: AppTheme.surface,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppTheme.radiusLg)),
          titlePadding: const EdgeInsets.fromLTRB(22, 22, 22, 0),
          contentPadding: const EdgeInsets.fromLTRB(22, 10, 22, 0),
          actionsPadding: const EdgeInsets.fromLTRB(10, 4, 10, 8),
          title: const Text('“渔报”想使用无线数据',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 16.5,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textPrimary)),
          content: const Text('用于登录注册、查看附近钓场和实时渔情天气。',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 13, height: 1.5, color: AppTheme.textPrimary)),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('不允许',
                  style:
                      TextStyle(fontSize: 14, color: AppTheme.textSecondary)),
            ),
            TextButton(
              key: const ValueKey('net-allow'),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('允许',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
            ),
          ],
        );
      },
    );
    if (!mounted) return false;
    return allow ?? false;
  }

  /// 打开系统设置，**等用户回来**再往下走。
  ///
  /// 不能像 [_openSettings] 那样只 `await` 一个固定时长就冲去重探：
  /// 用户还在设置里翻菜单，我们在后台探一万次也都是失败，回头还得再弹一次框。
  /// 所以这里盯 `resumed`：他真的切回来了，才继续。
  Future<void> _openSettingsThenWait() async {
    _leftForeground = false;
    final c = Completer<void>();
    _foregroundWait = c;
    final guard = Timer(const Duration(seconds: 120), () {
      if (!c.isCompleted) c.complete();
    });
    try {
      // 打不开设置也不能把整条队列带崩（桌面端 / 极少数机型会失败）。
      // 加超时：某些环境这个 channel 永远不回，会把整条队列吊死在这里。
      try {
        await openAppSettings().timeout(const Duration(milliseconds: 1000));
      } catch (_) {}
      // 给 `paused` 一拍时间落地：`openAppSettings()` 一返回、系统还没把
      // App 压到后台的那几十毫秒里，`_leftForeground` 还是 false。
      await Future<void>.delayed(const Duration(milliseconds: 600));
      // 真的退到后台了 → 一直等他回来（resumed 会唤醒这个 completer）
      if (_leftForeground && !c.isCompleted) {
        try {
          await c.future.timeout(const Duration(seconds: 120));
        } catch (_) {}
      }
    } finally {
      guard.cancel();
      if (identical(_foregroundWait, c)) _foregroundWait = null;
    }
    // 刚切回来那一两秒链路还没重建，立刻探必然失败，先缓一下
    await Future<void>.delayed(const Duration(milliseconds: 500));
    if (mounted) await _refresh();
  }

  /// 队列跑完、五项系统权限都过了，只剩网络没通时给的框。
  ///
  /// 为什么不用系统框：iOS 的「允许使用无线数据」由系统在 App 第一次联网时
  /// 自己决定要不要问，一个 App **只问一次**；问过并被记成「不允许」之后，
  /// App 没有任何 API 能让它再弹一次。安卓的联网权限是安装即授予、没有弹窗。
  /// 系统弹不出来，就用 App 自己的框把这一步说清楚。
  ///
  /// ★ v2.1.67：这个框**只在队列末尾**出现。原来它挂在「网络那一步失败」
  ///   的位置，于是用户刚点完系统弹窗的「允许」，就被这个框告知「被系统挡住了」
  ///   —— 冤枉人。现在网络那一步失败只会安静地转到下一项，等到全部问完再来
  ///   说这件事，那时系统弹窗早已收起，判断才可信。
  Future<void> _promptNetBlocked() async {
    final bool waiting = _netMaybeWaiting;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTheme.radiusLg)),
        titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
        contentPadding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
        actionsPadding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
        title: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: AppTheme.dangerLight,
                borderRadius: BorderRadius.circular(10),
              ),
              child:
                  const Icon(Icons.wifi_off, size: 18, color: AppTheme.danger),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(waiting ? '网络还没连上' : '网络被系统挡住了',
                  style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.textPrimary)),
            ),
          ],
        ),
        content: Text(
          waiting
              ? '其余 ${_rows.length} 项都开好了，只剩「网络」：请求一直没等到回应。'
                  '可以再检测一次，或先去系统设置里看看。'
              : '其余 ${_rows.length} 项都开好了，只剩「网络」：手机的「无线数据 / 流量」'
                  '开关把「渔报」关掉了。系统不会再自己弹窗，需要去设置里手动打开。',
          style: const TextStyle(
              fontSize: 12.5, height: 1.65, color: AppTheme.textPrimary),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              Navigator.of(ctx).pop();
              await _reprobe();
            },
            child: const Text('重新检测',
                style: TextStyle(fontSize: 13, color: AppTheme.textSecondary)),
          ),
          TextButton(
            onPressed: () async {
              Navigator.of(ctx).pop();
              await _openSettings();
              if (mounted) await _reprobe();
            },
            child: const Text('去打开设置',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  /// 网络连不上时给**能照着做**的路径，而不是一句「请检查网络」。
  ///
  /// iOS 的「无线数据」开关根本不在 App 自己的设置页里，所以必须把
  /// 「设置 → 蜂窝网络 → 渔报」这条路径写死在界面上。
  Future<void> _showNetHelp() async {
    final bool waiting = _netMaybeWaiting;
    final String title = _net == _NetState.offline
        ? (waiting ? '网络连不上怎么办' : '网络被系统挡住了')
        : '服务器没有回数据';
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
              child:
                  const Icon(Icons.wifi_off, size: 18, color: AppTheme.danger),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(title,
                  style: const TextStyle(
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
                    ? (waiting
                        ? '刚才的授权可能还没处理完。如果弹出过「允许使用无线数据」'
                            '而你没点，按下面几步再走一遍：'
                        // ★ 用户最需要的一句真话：这类授权弹窗一个 App 只会问
                        //   一次，点过「不允许」就再也不弹 —— 在 App 里点一万次
                        //   「允许」也弹不出来，只能去系统设置里打开。
                        : 'App 第一次联网时系统会问一次是否允许。点过「不允许」之后'
                            '系统不会再弹，只能在这里手动打开：')
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
                      fontSize: 10.5,
                      height: 1.5,
                      color: AppTheme.textSecondary),
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
              // 等用户真的从设置切回来再重探：只睡固定时长的话，
              // 他还在菜单里翻，我们在后台探多少次都是失败。
              await _openSettingsThenWait();
              await _reprobe();
            },
            child: const Text('去系统设置',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
          ),
          TextButton(
            onPressed: () async {
              Navigator.of(ctx).pop();
              await _reprobe();
            },
            child: const Text('重新检测',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
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
            color:
                active ? AppTheme.primary.withOpacity(0.45) : AppTheme.border),
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
            const Icon(Icons.check_circle, color: AppTheme.primary, size: 21)
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
                foregroundColor: blocked ? AppTheme.danger : AppTheme.primary,
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
  const FirstRunPermissionGate({
    super.key,
    required this.child,
    this.knownNeedOnboard,
  });

  final Widget child;

  /// 上层（启动门）已经读过偏好并判定「确实要引导」时传 true。
  ///
  /// 有了它就能跳过 [_checking] 那一两帧的纯底色 —— 启动页刚淡出、
  /// 引导页立刻接上，中间不闪一块空白。
  final bool? knownNeedOnboard;

  @override
  State<FirstRunPermissionGate> createState() => _FirstRunPermissionGateState();
}

class _FirstRunPermissionGateState extends State<FirstRunPermissionGate> {
  bool _checking = true;
  bool _needOnboard = false;

  @override
  void initState() {
    super.initState();
    final known = widget.knownNeedOnboard;
    if (known != null) {
      _needOnboard = known;
      _checking = false;
    } else {
      _check();
    }
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
