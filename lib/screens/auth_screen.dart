import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../app_theme.dart';
import '../services/auth_config.dart';
import '../services/builtin_avatars.dart';
import '../services/session_provider.dart';
import '../widgets/center_toast.dart';

/// 登录 / 注册（v2.1.46 重做）
///
/// 显示哪些方式**完全由后台「运营配置 → 注册与登录方式」决定**：
///   · 仅手机号 → 只出现手机号 + 短信验证码，微信按钮不渲染；
///   · 仅微信   → 只出现微信登录，手机号输入区不渲染；
///   · 都开放   → 两个都在，用户自己挑。
/// 配置每次进页面都拉一次（[AuthConfig.load]），后台改完不用发版。
///
/// 手机号走「验证码」而不是密码：**没注册过的号码输完验证码就直接建号并登录**，
/// 不需要用户先点「注册」再来一遍。原「手机号 + 密码」保留为备用入口
/// （老用户已经有密码，后台也可以整体关掉）。
class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key, this.hint});

  /// 从长按快捷入口等地方进来时，可以带一句「登录后继续…」
  final String? hint;

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  AuthConfig _cfg = AuthConfig.current;
  bool _cfgLoading = true;

  /// 手机号验证码模式
  final _phone = TextEditingController();
  final _code = TextEditingController();
  final _name = TextEditingController(); // 注册时可选昵称
  bool _registerTab = false;

  /// 密码模式（老用户 / 后台保留时）
  bool _pwdMode = false;
  final _pwd = TextEditingController();

  bool _busy = false;
  int _countdown = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _loadCfg();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _phone.dispose();
    _code.dispose();
    _name.dispose();
    _pwd.dispose();
    super.dispose();
  }

  /// 本机能不能真的走微信登录（原生 SDK 是否集成 + 是否装了微信）
  ///
  /// 原生端（iOS AppDelegate / Android MainActivity）都注册了 `fishing/wechat`，
  /// 当前版本回 false；SDK 接上后改成 `WXApi.isWXAppInstalled()`。
  Future<bool> _wechatAvailable() async {
    try {
      const ch = MethodChannel('fishing/wechat');
      final v = await ch.invokeMethod<bool>('available');
      return v == true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _loadCfg() async {
    var c = await AuthConfig.load();
    // ★ 兜底：后台配成「只开放微信」但本机走不了微信（没集成 SDK / 没装微信）时，
    //   页面上就只剩一个点了必失败的按钮，用户彻底无路可走 —— 连后台都救不回来
    //   （他得先能登进来才能改配置）。所以这里本地放开手机号登录。
    if (c.allowWechat && !c.allowPhone) {
      final ok = await _wechatAvailable();
      if (!ok) c = c.copyWith(allowPhone: true);
    }
    if (!mounted) return;
    setState(() {
      _cfg = c;
      _cfgLoading = false;
    });
  }

  // ───────────────────────── 发验证码 ─────────────────────────

  void _startCountdown() {
    _timer?.cancel();
    setState(() => _countdown = 60);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() => _countdown--);
      if (_countdown <= 0) t.cancel();
    });
  }

  Future<void> _sendCode() async {
    final phone = _phone.text.trim();
    if (!RegExp(r'^1[3-9]\d{9}$').hasMatch(phone)) {
      CenterToast.show(context, '请填写正确的 11 位手机号');
      return;
    }
    if (_countdown > 0 || _busy) return;
    setState(() => _busy = true);
    try {
      final sp = Provider.of<SessionProvider>(context, listen: false);
      final data = await sp.sendSmsCode(phone);
      if (!mounted) return;
      _startCountdown();
      // 调试模式（后台没接真实短信通道）下后端会把验证码一起返回，
      // 直接填进输入框，省得测试时到处找。
      final dbg = (data['debugCode'] ?? '').toString();
      if (dbg.isNotEmpty) {
        _code.text = dbg;
        CenterToast.show(context, '测试模式验证码：$dbg（已自动填入）');
      } else {
        CenterToast.show(context, '验证码已发送，5 分钟内有效');
      }
    } catch (e) {
      if (mounted) CenterToast.show(context, _errText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ───────────────────────── 提交 ─────────────────────────

  /// 把后端/网络异常翻成能看懂的中文
  String _errText(Object e) {
    var s = e.toString();
    s = s.replaceAll('Exception: ', '').replaceAll('ApiException: ', '');
    if (s.contains('SocketException') || s.contains('Connection')) {
      return '连不上服务器，请检查网络后重试';
    }
    return s.isEmpty ? '操作失败，请稍后重试' : s;
  }

  Future<void> _submitSms() async {
    final phone = _phone.text.trim();
    final code = _code.text.trim();
    if (!RegExp(r'^1[3-9]\d{9}$').hasMatch(phone)) {
      CenterToast.show(context, '请填写正确的 11 位手机号');
      return;
    }
    if (code.length < 4) {
      CenterToast.show(context, '请填写短信验证码');
      return;
    }
    setState(() => _busy = true);
    try {
      final sp = Provider.of<SessionProvider>(context, listen: false);
      final isNew = await sp.signInBySms(
        phone,
        code,
        nickname: _registerTab ? _name.text : null,
      );
      // 新用户分配一个内置头像（失败不影响登录）
      if (isNew) {
        try {
          final avatar = await BuiltinAvatars.uploadRandom();
          if (avatar != null) await sp.updateProfile(avatar: avatar);
        } catch (_) {}
      }
      if (!mounted) return;
      CenterToast.show(context, isNew ? '注册成功，已登录' : '登录成功');
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) CenterToast.show(context, _errText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _submitPassword() async {
    if (_phone.text.isEmpty || _pwd.text.isEmpty) {
      CenterToast.show(context, '请填写手机号和密码');
      return;
    }
    setState(() => _busy = true);
    try {
      final sp = Provider.of<SessionProvider>(context, listen: false);
      if (_registerTab) {
        if (_name.text.trim().isEmpty) {
          CenterToast.show(context, '请填写昵称');
          return;
        }
        await sp.signUp(_phone.text.trim(), _pwd.text, _name.text.trim());
        try {
          final avatar = await BuiltinAvatars.uploadRandom();
          if (avatar != null) await sp.updateProfile(avatar: avatar);
        } catch (_) {}
      } else {
        await sp.signIn(_phone.text.trim(), _pwd.text);
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) CenterToast.show(context, _errText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// 微信登录：本地通过原生 SDK 拿 code，再交给后端换 openid
  ///
  /// iOS / Android 两端原生都注册了 `fishing/wechat` 通道。当前版本还没集成
  /// 微信 SDK，原生会回 `not_integrated` —— 必须和历史文案区分开：以前一律提示
  /// 「需要先装微信客户端」，用户明明装了微信，怎么弄都login不进去。
  Future<void> _submitWechat() async {
    setState(() => _busy = true);
    try {
      const ch = MethodChannel('fishing/wechat');
      String? code;
      try {
        code = await ch.invokeMethod<String>('login');
      } on MissingPluginException {
        // 原生通道都没注册（理论上不会发生）：同样按「未内置」处理
        code = null;
        if (mounted) CenterToast.show(context, _wechatHint('not_integrated'));
        return;
      } on PlatformException catch (e) {
        if (mounted) CenterToast.show(context, _wechatHint(e.code, e.message));
        return;
      } catch (_) {
        code = null;
      }
      if (code == null || code.isEmpty) {
        if (mounted) CenterToast.show(context, _wechatHint('not_integrated'));
        return;
      }
      if (!mounted) return;
      final sp = Provider.of<SessionProvider>(context, listen: false);
      final isNew = await sp.signInByWechat(code);
      if (!mounted) return;
      CenterToast.show(context, isNew ? '注册成功，已登录' : '登录成功');
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) CenterToast.show(context, _errText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// 微信登录失败原因 → 用户能看懂、并且知道下一步该干什么的话
  String _wechatHint(String? code, [String? msg]) {
    switch (code) {
      case 'not_integrated':
        return '当前版本未内置微信登录，请用手机号验证码登录（新号自动注册）';
      case 'not_configured':
        return '后台还没填微信 AppID / AppSecret，请先改用手机号登录';
      case 'not_installed':
        return '这台手机没装微信，请改用手机号登录';
      case 'cancel':
        return '已取消微信授权';
      case 'auth_denied':
        return '微信授权被拒绝，请重试或改用手机号登录';
      default:
        return '微信登录失败${msg == null || msg.isEmpty ? '' : '：$msg'}';
    }
  }

  // ───────────────────────── UI ─────────────────────────

  @override
  Widget build(BuildContext context) {
    final showPhone = _cfg.allowPhone;
    final showWechat = _cfg.allowWechat;
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: Text(_registerTab ? '注册' : '登录',
            style: const TextStyle(fontWeight: FontWeight.w700)),
        centerTitle: true,
      ),
      body: _cfgLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppTheme.primary))
          : AutofillGroup(child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
              children: [
                const SizedBox(height: 10),
                const Icon(Icons.phishing, size: 58, color: AppTheme.primary),
                const SizedBox(height: 8),
                const Center(
                  child: Text('渔报',
                      style: TextStyle(
                          fontSize: 20, fontWeight: FontWeight.w800)),
                ),
                const SizedBox(height: 4),
                Center(
                  child: Text(
                    widget.hint ?? '登录后同步你的渔获、图鉴与池塘',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 12, color: AppTheme.textSecondary),
                  ),
                ),
                const SizedBox(height: 20),

                // 手机号登录 / 注册（后台关了手机号方式就整块不渲染）
                if (showPhone) ..._phoneBlock(),

                // 微信登录
                if (showWechat) ..._wechatBlock(),

                // 两种都没开（后台误配）：给个明确说法，别留空白页
                if (!showPhone && !showWechat)
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppTheme.surface,
                      borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                      border: Border.all(color: AppTheme.border),
                    ),
                    child: const Text(
                      '当前没有开放任何登录方式，请联系客服处理。',
                      style: TextStyle(fontSize: 13),
                    ),
                  ),
              ],
            )),
    );
  }

  List<Widget> _phoneBlock() {
    return [
      // 登录 / 注册 切换（验证码模式两者是同一接口，这里只是文案与昵称字段的差别）
      Row(
        children: [
          _tabBtn('登录', !_registerTab, () {
            setState(() {
              _registerTab = false;
              _pwdMode = false;
            });
          }),
          const SizedBox(width: 8),
          _tabBtn('注册', _registerTab, () {
            setState(() {
              _registerTab = true;
              _pwdMode = false;
            });
          }),
        ],
      ),
      const SizedBox(height: 16),

      TextField(
        controller: _phone,
        keyboardType: TextInputType.phone,
        maxLength: 11,
        // iOS：让系统把手机号当「电话号」填（短信 App 里点号码能直接跳过来）
        autofillHints: const [AutofillHints.telephoneNumber],
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: const InputDecoration(
          labelText: '手机号',
          counterText: '',
          prefixIcon: Icon(Icons.phone_iphone, size: 20),
          border: OutlineInputBorder(),
        ),
      ),
      const SizedBox(height: 12),

      if (!_pwdMode) ...[
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _code,
                keyboardType: TextInputType.number,
                maxLength: 6,
                // iOS：短信验证码自动填充（系统键盘上方直接给「从短信填充」）
                autofillHints: const [AutofillHints.oneTimeCode],
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                  labelText: '短信验证码',
                  counterText: '',
                  prefixIcon: Icon(Icons.sms_outlined, size: 20),
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(
              height: 46,
              width: 108,
              child: OutlinedButton(
                onPressed: (_busy || _countdown > 0) ? null : _sendCode,
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.primary,
                  side: const BorderSide(color: AppTheme.primary),
                  padding: EdgeInsets.zero,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
                child: Text(
                  _countdown > 0 ? '${_countdown}s' : '获取验证码',
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ],
        ),
        if (_registerTab) ...[
          const SizedBox(height: 12),
          TextField(
            controller: _name,
            maxLength: 16,
            decoration: const InputDecoration(
              labelText: '昵称（不填自动生成）',
              counterText: '',
              prefixIcon: Icon(Icons.badge_outlined, size: 20),
              border: OutlineInputBorder(),
            ),
          ),
        ],
        const SizedBox(height: 18),
        SizedBox(
          height: 48,
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _busy ? null : _submitSms,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppTheme.radiusMd)),
            ),
            child: _busy
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2.2))
                : Text(_registerTab ? '注册并登录' : '登录',
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w700)),
          ),
        ),
        const SizedBox(height: 6),
        Center(
          child: Text(
            _registerTab
                ? '手机号没注册过？填完验证码就直接帮你注册'
                : '新手机号会自动注册并登录',
            style:
                const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
          ),
        ),
      ] else ...[
        TextField(
          controller: _pwd,
          obscureText: true,
          decoration: const InputDecoration(
            labelText: '密码',
            prefixIcon: Icon(Icons.lock_outline, size: 20),
            border: OutlineInputBorder(),
          ),
        ),
        if (_registerTab) ...[
          const SizedBox(height: 12),
          TextField(
            controller: _name,
            decoration: const InputDecoration(
              labelText: '昵称',
              prefixIcon: Icon(Icons.badge_outlined, size: 20),
              border: OutlineInputBorder(),
            ),
          ),
        ],
        const SizedBox(height: 18),
        SizedBox(
          height: 48,
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _busy ? null : _submitPassword,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppTheme.radiusMd)),
            ),
            child: _busy
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2.2))
                : Text(_registerTab ? '注册' : '登录',
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w700)),
          ),
        ),
      ],

      // 密码方式切换（后台关了「保留密码登录」就不显示）
      if (_cfg.passwordLogin)
        Center(
          child: TextButton(
            onPressed: () => setState(() => _pwdMode = !_pwdMode),
            child: Text(_pwdMode ? '改用短信验证码登录' : '用密码登录（老用户）',
                style: const TextStyle(fontSize: 12.5)),
          ),
        ),
    ];
  }

  List<Widget> _wechatBlock() {
    return [
      if (_cfg.allowPhone) ...[
        const SizedBox(height: 6),
        Row(
          children: [
            const Expanded(child: Divider()),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Text('或',
                  style: TextStyle(
                      fontSize: 11.5, color: AppTheme.textSecondary)),
            ),
            const Expanded(child: Divider()),
          ],
        ),
        const SizedBox(height: 14),
      ],
      SizedBox(
        height: 48,
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: (_busy || !_cfg.wechatReady) ? null : _submitWechat,
          icon: const Icon(Icons.wechat, color: Color(0xFF07C160), size: 21),
          label: Text(
            _cfg.wechatReady ? '微信登录' : '微信登录（未配置）',
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
          ),
          style: OutlinedButton.styleFrom(
            foregroundColor: const Color(0xFF07C160),
            side: const BorderSide(color: Color(0xFF07C160)),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppTheme.radiusMd)),
          ),
        ),
      ),
      if (_cfg.wechatReady)
        const Padding(
          padding: EdgeInsets.only(top: 8),
          child: Text(
            '微信首次登录会自动注册，不用另外填资料',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11, color: AppTheme.textSecondary),
          ),
        ),
      if (!_cfg.wechatReady)
        const Padding(
          padding: EdgeInsets.only(top: 6),
          child: Text(
            '管理员还没填微信 AppID / AppSecret，暂时用手机号登录',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11, color: AppTheme.textSecondary),
          ),
        ),
    ];
  }

  Widget _tabBtn(String label, bool active, VoidCallback onTap) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          height: 38,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: active ? AppTheme.primary : AppTheme.surface,
            borderRadius: BorderRadius.circular(9),
            border: Border.all(
                color: active ? AppTheme.primary : AppTheme.border),
          ),
          child: Text(label,
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: active ? Colors.white : AppTheme.textSecondary)),
        ),
      ),
    );
  }
}
