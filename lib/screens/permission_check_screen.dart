import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../app_theme.dart';
import '../widgets/center_toast.dart';

/// 权限自检页（v2.1.24）
///
/// 用户在「我的 → 通知设置 → 权限自检」进入。一次性展示 App 需要的几类系统权限
/// 当前状态，逐项可「去授权」或「被永久拒绝后跳系统设置」。
///
/// 背景：安卓/iOS 的相机、相册、通知权限都是「用到时才弹框」，且只在首次触发时弹一次；
/// 用户若在首屏只看到定位弹框，会以为其它权限没申请。这里把所有权限摆出来，
/// 让用户能主动检查、补齐，避免「装好后只有定位能弹窗」的困惑。
class PermissionCheckScreen extends StatefulWidget {
  const PermissionCheckScreen({super.key});

  @override
  State<PermissionCheckScreen> createState() => _PermissionCheckScreenState();
}

class _PermItem {
  final Permission permission;
  final IconData icon;
  final String title;
  final String desc;

  const _PermItem(this.permission, this.icon, this.title, this.desc);
}

class _PermissionCheckScreenState extends State<PermissionCheckScreen> {
  bool _loading = true;
  final Map<Permission, PermissionStatus> _status = {};

  final List<_PermItem> _items = const [
    _PermItem(Permission.locationWhenInUse, Icons.location_on_outlined, '定位',
        '附近钓友、钓点导航、本地天气与动态定位都需要它'),
    _PermItem(Permission.camera, Icons.camera_alt_outlined, '相机',
        '发布渔获、拍钓点、头像拍照时调用'),
    _PermItem(Permission.photos, Icons.photo_library_outlined, '相册',
        '从相册选择图片/视频发布动态、上传头像'),
    _PermItem(Permission.notification, Icons.notifications_outlined, '通知',
        '收到私信、评论、点赞与官方公告时提醒你'),
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final map = <Permission, PermissionStatus>{};
    for (final it in _items) {
      try {
        map[it.permission] = await it.permission.status;
      } catch (_) {
        map[it.permission] = PermissionStatus.denied;
      }
    }
    if (!mounted) return;
    setState(() {
      _status
        ..clear()
        ..addAll(map);
      _loading = false;
    });
  }

  Future<void> _request(_PermItem it) async {
    final st = _status[it.permission];
    if (st == PermissionStatus.granted) return;
    // 被永久拒绝（点了「不再询问」）：系统不再弹框，只能去系统设置开
    if (st == PermissionStatus.permanentlyDenied) {
      await openAppSettings();
      // 从设置回来后刷新一次状态
      await _load();
      return;
    }
    PermissionStatus res;
    try {
      res = await it.permission.request();
    } catch (_) {
      res = PermissionStatus.denied;
    }
    if (!mounted) return;
    setState(() => _status[it.permission] = res);
    if (res.isGranted) {
      CenterToast.show(context, '${it.title}权限已开启');
    } else if (res.isPermanentlyDenied) {
      CenterToast.show(context, '${it.title}权限被永久拒绝，请在系统设置中开启');
    }
  }

  String _statusText(PermissionStatus? s) {
    if (s == null) return '未知';
    if (s.isGranted) return '已授权';
    if (s.isPermanentlyDenied) return '已拒绝';
    return '未授权';
  }

  Color _statusColor(PermissionStatus? s) {
    if (s == null) return AppTheme.textSecondary;
    if (s.isGranted) return AppTheme.primary;
    if (s.isPermanentlyDenied) return AppTheme.danger;
    return AppTheme.warning;
  }

  @override
  Widget build(BuildContext context) {
    final allGranted =
        _status.values.every((s) => s.isGranted) && _status.isNotEmpty;
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('权限自检',
            style: TextStyle(fontWeight: FontWeight.w700)),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_outlined),
            tooltip: '刷新状态',
            onPressed: _load,
          ),
        ],
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: AppTheme.primary))
          : ListView(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
              children: [
                // 顶部说明
                Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(13),
                  decoration: BoxDecoration(
                    color: allGranted
                        ? AppTheme.primarySoft
                        : AppTheme.warningLight,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: allGranted
                            ? AppTheme.primaryBorder
                            : AppTheme.warning),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        allGranted
                            ? Icons.check_circle_outline
                            : Icons.info_outline,
                        size: 18,
                        color: allGranted
                            ? AppTheme.primary
                            : AppTheme.warning,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          allGranted
                              ? '所有需要的权限都已开启，App 功能可正常使用。'
                              : '网络权限在安装时已默认授予，无需单独开启；下面这几项可按需补齐。',
                          style: TextStyle(
                              fontSize: 12,
                              height: 1.6,
                              color: allGranted
                                  ? AppTheme.primaryDark
                                  : AppTheme.textSecondary),
                        ),
                      ),
                    ],
                  ),
                ),
                ..._items.map((it) => _card(it)),
                const SizedBox(height: 14),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 4),
                  child: Text(
                    '若某项显示「已拒绝」，点「去设置」后在本机系统设置里找到「垂钓圈」并手动开启；改完返回 App 点右上角刷新即可。',
                    style: TextStyle(
                        fontSize: 11.5,
                        height: 1.6,
                        color: AppTheme.textSecondary),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _card(_PermItem it) {
    final st = _status[it.permission];
    final granted = st?.isGranted ?? false;
    final permanent = st == PermissionStatus.permanentlyDenied;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: granted ? AppTheme.primaryLight : AppTheme.primarySoft,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(it.icon,
                size: 21,
                color: granted ? AppTheme.primary : AppTheme.textSecondary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(it.title,
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w700)),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 1),
                      decoration: BoxDecoration(
                        color: _statusColor(st).withOpacity(0.12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(_statusText(st),
                          style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700,
                              color: _statusColor(st))),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(it.desc,
                    style: const TextStyle(
                        fontSize: 11.5, color: AppTheme.textSecondary)),
              ],
            ),
          ),
          const SizedBox(width: 10),
          granted
              ? const Icon(Icons.check_circle, color: AppTheme.primary, size: 22)
              : TextButton(
                  onPressed: () => _request(it),
                  style: TextButton.styleFrom(
                    foregroundColor: AppTheme.primary,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text(permanent ? '去设置' : '去授权',
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w700)),
                ),
        ],
      ),
    );
  }
}
