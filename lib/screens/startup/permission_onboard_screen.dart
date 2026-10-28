import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../app_theme.dart';
import '../../widgets/center_toast.dart';

/// 首次启动的权限引导（v2.1.46）
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
class PermissionOnboardScreen extends StatefulWidget {
  const PermissionOnboardScreen({super.key, required this.onDone});

  /// 全部处理完（或用户点「以后再说」）后回调
  final VoidCallback onDone;

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

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final map = <Permission, PermissionStatus>{};
    for (final r in _rows) {
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
  }

  /// 逐项申请（串行）。每一项都回读系统状态再继续。
  Future<void> _requestAll() async {
    if (_running) return;
    setState(() => _running = true);
    for (final r in _rows) {
      if (!mounted) return;
      var st = _status[r.perm];
      // 已授权 / 已被永久拒绝（系统不会再弹）→ 跳过，后面统一提示去设置
      if (st == null) continue;
      if (st.isGranted) continue;
      if (st == PermissionStatus.permanentlyDenied) continue;
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
        setState(() => _status[r.perm] = after);
      } catch (_) {}
    }
    if (!mounted) return;
    setState(() => _running = false);
    await _refresh();

    final denied = _rows.where((r) {
      final s = _status[r.perm];
      return s != null && !s.isGranted;
    }).toList();
    if (!mounted) return;
    if (denied.isEmpty) {
      CenterToast.show(context, '全部权限已开启', icon: Icons.check_circle);
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
    final prefs = await SharedPreferences.getInstance();
    // 只记「引导看过」；权限状态每次进来都重新读系统，不缓存
    await prefs.setBool(kPermOnboardDone, true);
    if (mounted) widget.onDone();
  }

  @override
  Widget build(BuildContext context) {
    final grantedCount = _rows
        .where((r) => _status[r.perm]?.isGranted == true)
        .length;
    final allDone = grantedCount == _rows.length;

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
                      Text('$grantedCount/${_rows.length}',
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
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                      children: [
                        ..._rows.map(_tile),
                        const SizedBox(height: 4),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: Text(
                            '说明：显示「已拒绝」表示系统里没有开启，点这一项会跳到本机系统的「渔报」权限页，'
                            '手动打开后返回即可。所有权限都可以稍后在「我的 → 通知设置 → 权限自检」里再改。',
                            style: const TextStyle(
                                fontSize: 11.5,
                                height: 1.65,
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
                      onPressed: _running ? null : _requestAll,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                            borderRadius:
                                BorderRadius.circular(AppTheme.radiusMd)),
                      ),
                      child: _running
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                  color: Colors.white, strokeWidth: 2.2))
                          : Text(allDone ? '重新检查一遍' : '一键开启全部权限',
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
                          onPressed: _done,
                          child: Text(allDone ? '完成' : '以后再说'),
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

  Widget _tile(_PermRow r) {
    final st = _status[r.perm];
    final granted = st?.isGranted ?? false;
    final blocked = st == PermissionStatus.permanentlyDenied;
    return Container(
      margin: const EdgeInsets.only(bottom: 9),
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        border: Border.all(color: AppTheme.border),
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
          granted
              ? const Icon(Icons.check_circle,
                  color: AppTheme.primary, size: 21)
              : TextButton(
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
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
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
const String kPermOnboardDone = 'perm_onboard_done_v1';

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
