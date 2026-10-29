import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../app_theme.dart';
import '../services/auth_config.dart';
import '../services/builtin_avatars.dart';
import '../services/net_diag.dart';
import '../services/onekey_login.dart';
import '../services/session_provider.dart';
import '../utils/net_error_text.dart';
import '../widgets/center_toast.dart';
import '../widgets/debug_code_hint.dart';
import 'legal_doc_screen.dart';

/// 登录页（v2.1.48 按设计稿重做：深色 + 荧光绿）
///
/// 两种形态，共用一张卡片：
///   · [AuthMode.sms]    —— 手机号 + 短信验证码（「其他手机号登录」）
///   · [AuthMode.onekey] —— 本机号码一键登录（大号脱敏号码 + 认证服务文案）
/// 首屏默认进哪一种，由「原生能不能取号」决定：能取号就直接进一键态，
/// 取不到就进短信态，且底部保留「本机号码一键登录」入口供用户手动切。
///
/// 显示哪些方式**完全由后台「运营配置 → 注册与登录方式」决定**：
///   · 仅手机号 → 微信按钮不渲染；
///   · 仅微信   → 手机号区块不渲染（但本机走不了微信时会本地放开手机号，
///                否则用户会被锁死在登录页，连后台都改不回来）；
///   · 都开放   → 都显示。
///
/// 手机号走「验证码」而不是密码：**没注册过的号码输完验证码就直接建号并登录**。
class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key, this.hint, this.onSkip, this.barrier = false});

  /// 从长按快捷入口等地方进来时，可以带一句「登录后继续…」
  final String? hint;

  /// 点右上角「随便看看」。
  ///   · 从别处 push 进来 → 传 null，内部直接 pop；
  ///   · 作为启动首屏 → 传回调，由外层切换到首页。
  final VoidCallback? onSkip;

  /// 作为浮层压在内容上时（true）不画「随便看看」，只留关闭
  final bool barrier;

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

enum AuthMode { sms, onekey }

class _AuthScreenState extends State<AuthScreen>
    with SingleTickerProviderStateMixin {
  // ── 设计稿色板（深色）──────────────────────────────────────
  static const Color _bg = Color(0xFF07080C); // 近黑底
  static const Color _card = Color(0xFF15181E); // 卡片
  static const Color _fieldBg = Color(0xFF1C2027); // 输入框
  static const Color _line = Color(0xFF262A31); // 描边/分隔
  static const Color _sub = Color(0xFF8A9099); // 次要文字
  static const Color _hi = Color(0xFFF2F4F7); // 主文字

  AuthConfig _cfg = AuthConfig.current;
  bool _cfgLoading = true;

  /// 调试模式下最近一次拿到的临时验证码（后端未接真实短信通道时才有）。
  /// 拿它做成页面上常驻的一行 —— 只弹 toast 的话两秒就没了，而且正好
  /// 压在验证码输入框上，用户既看不清也没处再找（就是被反馈的那个现象）。
  String? _dbgCode;

  AuthMode _mode = AuthMode.sms;
  OneKeyProbe _ok = OneKeyProbe.none;

  final _phone = TextEditingController();
  final _code = TextEditingController();

  /// 网络自检进行中（防止连点长按弹出两个框）
  bool _diagRunning = false;

  bool _busy = false;
  bool _agree = false;
  int _countdown = 0;
  Timer? _timer;

  /// 协议未勾选时按钮抖一下，比只弹 toast 直观
  late final AnimationController _shake;
  late final Animation<double> _shakeX;

  @override
  void initState() {
    super.initState();
    _shake = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
    );
    _shakeX = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0, end: -7), weight: 1),
      TweenSequenceItem(tween: Tween(begin: -7, end: 7), weight: 1),
      TweenSequenceItem(tween: Tween(begin: 7, end: -5), weight: 1),
      TweenSequenceItem(tween: Tween(begin: -5, end: 0), weight: 1),
    ]).animate(CurvedAnimation(parent: _shake, curve: Curves.easeOut));
    _boot();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _shake.dispose();
    _phone.dispose();
    _code.dispose();
    super.dispose();
  }

  // ─────────────────────── 初始化 ───────────────────────

  /// 拉后台配置 + 探本机取号能力，两件事并行，谁也别挡谁
  Future<void> _boot() async {
    final cfgF = _loadCfg();
    final probeF = OneKeyLoginService.probe();
    final cfg = await cfgF;
    final probe = await probeF;
    if (!mounted) return;
    setState(() {
      _cfg = cfg;
      _ok = probe;
      // 能真取号 → 首屏直接进一键态（设计稿第二张）
      _mode = (cfg.allowOneKey && probe.available) ? AuthMode.onekey : AuthMode.sms;
      // 读到 SIM 号就预填，省得用户手打
      if (probe.hasPhone && _phone.text.isEmpty) _phone.text = probe.phone;
      _cfgLoading = false;
    });
  }

  /// 本机能不能真的走微信登录（原生 SDK 是否集成 + 是否装了微信）
  ///
  /// ★ 必须带超时：原生通道要是**既不返回也不报错**，登录页会一直停在转圈上，
  ///   比微信登录不可用更糟。800ms 收不到就当不可用。
  Future<bool> _wechatAvailable() async {
    try {
      const ch = MethodChannel('fishing/wechat');
      final v = await ch
          .invokeMethod<bool>('available')
          .timeout(const Duration(milliseconds: 800));
      return v == true;
    } catch (_) {
      return false;
    }
  }

  Future<AuthConfig> _loadCfg() async {
    var c = await AuthConfig.load();
    // ★ 兜底：后台配成「只开放微信」但本机走不了微信时，页面上只剩一个
    //   点了必失败的按钮，用户连后台都救不回来。这里本地放开手机号登录。
    if (c.allowWechat && !c.allowPhone) {
      final ok = await _wechatAvailable();
      if (!ok) c = c.copyWith(allowPhone: true);
    }
    return c;
  }

  // ─────────────────────── 协议 ───────────────────────

  /// 登录前必须勾协议（合规硬要求），没勾就抖一下并提示
  bool _checkAgree() {
    if (_agree) return true;
    _shake.forward(from: 0);
    CenterToast.show(context, '请先阅读并同意《用户协议》和《隐私政策》');
    return false;
  }

  void _openDoc(String key, String title) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => LegalDocScreen(docKey: key, title: title),
      ),
    );
  }

  // ─────────────────────── 发码 / 登录 ───────────────────────

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

  /// 把异常翻译成用户能看懂、且**不误导**的一句话。
  ///
  /// 归类规则全在 [describeError]（纯函数，有单测），这里只负责把文案
  /// 交给 toast。★ v2.1.53 起登录页**不再**显示那条红色「重连」横条：
  /// 连不上时本来就没有可点的东西，多一块横条只会让页面更慌。
  String _errText(Object e) => describeError(e).text;

  /// 把 [_errText] 的结果弹出来的统一入口
  void _showErr(Object e) {
    if (!mounted) return;
    CenterToast.show(context, _errText(e));
  }

  /// 长按图标 → 网络自检。
  ///
  /// 分两步跑：先纯 TCP 连服务器端口，再请求一次 /auth/config。
  /// 两步的结论一起摆出来，就能分清是「网络到不了服务器」还是
  /// 「到了但接口出错」—— 这两种的处理方式完全不同，界面上一句话分不出来。
  Future<void> _runNetDiag() async {
    if (_diagRunning) return;
    _diagRunning = true;
    CenterToast.show(context, '正在自检网络…');
    NetDiagResult r;
    try {
      r = await NetDiag.run();
    } catch (e) {
      r = NetDiagResult(
        tcpOk: false,
        tcpMs: 0,
        tcpError: '自检本身出错：$e',
        httpStatus: 0,
        httpMs: 0,
        httpError: '',
      );
    }
    _diagRunning = false;
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _card,
        title: const Text('网络自检',
            style: TextStyle(fontSize: 16, color: _hi)),
        content: SingleChildScrollView(
          child: SelectableText(
            r.summary,
            style: const TextStyle(fontSize: 12.5, color: _hi, height: 1.6),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: r.summary));
              Navigator.of(ctx).pop();
              CenterToast.show(context, '自检结果已复制');
            },
            child: const Text('复制', style: TextStyle(color: AppTheme.accent)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('关闭', style: TextStyle(color: _sub)),
          ),
        ],
      ),
    );
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
      final dbg = (data['debugCode'] ?? '').toString();
      setState(() => _dbgCode = dbg.isEmpty ? null : dbg);
      if (dbg.isNotEmpty) {
        _code.text = dbg;
        CenterToast.show(context, '调试注册 · 验证码 $dbg，已自动填入');
      } else {
        CenterToast.show(context, '验证码已发送，5 分钟内有效');
      }
    } catch (e) {
      _showErr(e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _submitSms() async {
    if (!_checkAgree()) return;
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
      final isNew = await sp.signInBySms(phone, code);
      await _afterLogin(sp, isNew);
    } catch (e) {
      _showErr(e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// 一键登录：原生取号 token → 后端换真实号码 → 建号 / 登录
  Future<void> _submitOneKey() async {
    if (!_checkAgree()) return;

    // ① 没集成运营商取号：如果读到了 SIM 号，就降级成「用这个号码收验证码」
    if (!_ok.available) {
      if (_ok.hasPhone) {
        setState(() {
          _phone.text = _ok.phone;
          _mode = AuthMode.sms;
        });
        CenterToast.show(context, '已填入本机号码，请点「获取验证码」完成登录');
      } else {
        CenterToast.show(context, OneKeyLoginService.hint(_ok.reason));
      }
      return;
    }
    if (!_cfg.oneKeyReady) {
      CenterToast.show(context, '后台还没配置运营商取号服务，请用短信验证码登录');
      return;
    }

    setState(() => _busy = true);
    try {
      final token = await OneKeyLoginService.fetchToken();
      if (token.isEmpty) throw const OneKeyException('error', '没拿到取号凭证');
      if (!mounted) return;
      final sp = Provider.of<SessionProvider>(context, listen: false);
      final isNew = await sp.signInByOneKey(token);
      await _afterLogin(sp, isNew);
    } on OneKeyException catch (e) {
      if (mounted) CenterToast.show(context, OneKeyLoginService.hint(e.code));
    } catch (e) {
      _showErr(e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _afterLogin(SessionProvider sp, bool isNew) async {
    if (isNew) {
      // 新用户分配一个内置头像（失败不影响登录）
      try {
        final avatar = await BuiltinAvatars.uploadRandom();
        if (avatar != null) await sp.updateProfile(avatar: avatar);
      } catch (_) {}
    }
    if (!mounted) return;
    CenterToast.show(context, isNew ? '注册成功，已登录' : '登录成功');
    _finish(true);
  }

  /// 微信登录：本地通过原生 SDK 拿 code，再交给后端换 openid
  Future<void> _submitWechat() async {
    if (!_checkAgree()) return;
    if (!_cfg.wechatReady) {
      CenterToast.show(context, _wechatHint('not_configured'));
      return;
    }
    setState(() => _busy = true);
    try {
      const ch = MethodChannel('fishing/wechat');
      String? code;
      try {
        code = await ch
            .invokeMethod<String>('login')
            .timeout(const Duration(seconds: 15));
      } on MissingPluginException {
        if (mounted) CenterToast.show(context, _wechatHint('not_integrated'));
        return;
      } on PlatformException catch (e) {
        if (mounted) CenterToast.show(context, _wechatHint(e.code, e.message));
        return;
      } on TimeoutException {
        if (mounted) CenterToast.show(context, _wechatHint('timeout'));
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
      await _afterLogin(sp, isNew);
    } catch (e) {
      _showErr(e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

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
      case 'timeout':
        return '微信授权超时，请重试或改用手机号登录';
      case 'auth_denied':
        return '微信授权被拒绝，请重试或改用手机号登录';
      default:
        return '微信登录失败${msg == null || msg.isEmpty ? '' : '：$msg'}';
    }
  }

  void _appleHint() {
    CenterToast.show(context, 'Apple 登录需要开发者账号审核通过后开启，请先用手机号登录');
  }

  /// 关闭登录页：pop 或交给外层切换（启动首屏）
  void _finish(bool ok) {
    if (widget.onSkip != null) {
      // 作为首屏时没有可 pop 的路由，交给外层决定去哪
      if (ok) {
        widget.onSkip!();
      } else {
        widget.onSkip!();
      }
      return;
    }
    final nav = Navigator.of(context);
    if (nav.canPop()) nav.pop(ok);
  }

  // ─────────────────────── UI ───────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      // 键盘顶上来时整页可滚，不遮输入框
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                _topBar(),
                Expanded(
                  child: _cfgLoading
                      ? const Center(
                          child: CircularProgressIndicator(
                              color: AppTheme.accent, strokeWidth: 2.4),
                        )
                      : AutofillGroup(
                          child: SingleChildScrollView(
                          keyboardDismissBehavior:
                              ScrollViewKeyboardDismissBehavior.onDrag,
                          padding: const EdgeInsets.fromLTRB(22, 4, 22, 28),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const SizedBox(height: 6),
                              // ★ 长按图标 = 网络自检（隐藏入口，不占版面）。
                              //   用户报「连不上服务器」时，隔着屏幕没法看日志，
                              //   这个能一次说清是端口不通、没网，还是接口出错。
                              Center(
                                child: GestureDetector(
                                  key: const Key('auth-logo-diag'),
                                  behavior: HitTestBehavior.opaque,
                                  onLongPress: _runNetDiag,
                                  child: _logo(),
                                ),
                              ),
                              const SizedBox(height: 16),
                              Center(child: _brand()),
                              const SizedBox(height: 24),
                              _cardBlock(),
                              const SizedBox(height: 16),
                              _agreeRow(),
                              const SizedBox(height: 24),
                              _otherWays(),
                              const SizedBox(height: 18),
                            ],
                          ),
                        )),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _topBar() {
    return SizedBox(
      height: 46,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          TextButton(
            onPressed: () => _finish(false),
            style: TextButton.styleFrom(
              foregroundColor: _sub,
              padding: const EdgeInsets.symmetric(horizontal: 16),
            ),
            child: Text(
              widget.barrier ? '关闭' : '随便看看',
              style: const TextStyle(fontSize: 13.5),
            ),
          ),
        ],
      ),
    );
  }

  Widget _logo() {
    return Container(
      width: 88,
      height: 88,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        boxShadow: [
          BoxShadow(
            color: AppTheme.accent.withOpacity(0.22),
            blurRadius: 30,
            spreadRadius: 2,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(26),
        child: Image.asset(
          'assets/branding/app_icon.png',
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => Container(
            color: AppTheme.accent,
            alignment: Alignment.center,
            child: const Icon(Icons.phishing, size: 44, color: _bg),
          ),
        ),
      ),
    );
  }

  Widget _brand() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '渔报',
          style: TextStyle(
            fontSize: 32,
            fontWeight: FontWeight.w800,
            color: _hi,
            letterSpacing: 6,
            height: 1.1,
          ),
        ),
        const SizedBox(width: 2),
        Container(
          margin: const EdgeInsets.only(top: 4),
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
          decoration: BoxDecoration(
            color: AppTheme.accent,
            borderRadius: BorderRadius.circular(4),
          ),
          child: const Text(
            'APP',
            style: TextStyle(
              fontSize: 8,
              fontWeight: FontWeight.w900,
              color: _bg,
              letterSpacing: .3,
            ),
          ),
        ),
      ],
    );
  }

  Widget _cardBlock() {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 20, 18, 16),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: _line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            widget.hint ?? '登录后，渔获、图鉴和池塘跟着账号走，换手机也不丢',
            textAlign: TextAlign.center,
            style: const TextStyle(
                fontSize: 12.5, color: _sub, height: 1.6),
          ),
          const SizedBox(height: 18),
          if (_mode == AuthMode.onekey)
            ..._oneKeyBody()
          else if (_cfg.allowPhone)
            ..._smsBody()
          else
            // 后台只开放微信：这里不留空白卡片，明确告诉用户去哪登录
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 10),
              child: Text(
                '请使用下方的微信登录',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13.5, color: _hi),
              ),
            ),
        ],
      ),
    );
  }

  // ── 形态一：手机号 + 验证码 ──

  List<Widget> _smsBody() {
    return [
      // 手机号
      _field(
        key: const Key('auth-phone-field'),
        controller: _phone,
        hint: '请输入手机号',
        keyboardType: TextInputType.phone,
        digits: true,
        maxLength: 11,
        autofill: const [AutofillHints.telephoneNumber],
        prefix: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('+86',
                style: TextStyle(
                    fontSize: 15, color: _hi, fontWeight: FontWeight.w600)),
            Container(
              width: 1,
              height: 18,
              margin: const EdgeInsets.symmetric(horizontal: 10),
              color: _line,
            ),
          ],
        ),
      ),
      const SizedBox(height: 12),
      // 验证码
      _field(
        key: const Key('auth-code-field'),
        controller: _code,
        hint: '请输入验证码',
        keyboardType: TextInputType.number,
        digits: true,
        maxLength: 6,
        autofill: const [AutofillHints.oneTimeCode],
        suffix: TextButton(
          key: const Key('auth-send-code'),
          onPressed: (_busy || _countdown > 0) ? null : _sendCode,
          style: TextButton.styleFrom(
            foregroundColor: AppTheme.accent,
            disabledForegroundColor: _sub,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            minimumSize: const Size(0, 34),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: Text(
            _countdown > 0 ? '${_countdown}s 后重发' : '获取验证码',
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
          ),
        ),
      ),
      // 调试模式下把临时验证码摆在这里（后台切到正式短信通道后自动消失）
      DebugCodeHint(
        visible: _cfg.smsDebug,
        code: _dbgCode,
        onCopy: (c) => CenterToast.show(context, '已复制验证码 $c'),
      ),
      const SizedBox(height: 18),
      _primaryBtn(
        key: const Key('auth-login-btn'),
        label: '登录',
        onTap: _busy ? null : _submitSms,
      ),
      const SizedBox(height: 6),
      // 一键登录入口（后台关掉就不显示）
      if (_cfg.allowOneKey)
        Center(
          child: TextButton(
            key: const Key('auth-onekey-switch'),
            onPressed: _busy ? null : _switchToOneKey,
            style: TextButton.styleFrom(
              foregroundColor: _hi,
              padding: const EdgeInsets.symmetric(vertical: 10),
              minimumSize: const Size(0, 40),
            ),
            child: const Text('本机号码一键登录',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
          ),
        ),
    ];
  }

  // ── 形态二：本机号码一键登录 ──

  List<Widget> _oneKeyBody() {
    final masked = _ok.masked.isNotEmpty ? _ok.masked : _maskOf(_phone.text);
    final carrier = _cfg.oneKeyCarrier.isNotEmpty
        ? _cfg.oneKeyCarrier
        : '运营商账号提供认证服务';
    // 能不能真一键？只有「原生取号可用 + 后台密钥/网关齐全」才算。
    // 否则按钮不做成「点了报错」，而是直接变成下一步该做的事 ——
    // 用户永远有一条能走通的路。
    final canOneKey = _ok.available && _cfg.oneKeyReady;
    final canPrefill = !canOneKey && _ok.hasPhone;
    final String btnLabel = canOneKey
        ? '本机号码一键登录'
        : (canPrefill ? '用本机号码接收验证码' : '用短信验证码登录');
    return [
      const SizedBox(height: 4),
      if (masked.isNotEmpty)
        Text(
          masked,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 30,
            fontWeight: FontWeight.w800,
            color: _hi,
            letterSpacing: 1.2,
            height: 1.2,
          ),
        )
      else
        const Text(
          '本机号码',
          textAlign: TextAlign.center,
          style: TextStyle(
              fontSize: 26, fontWeight: FontWeight.w800, color: _hi),
        ),
      const SizedBox(height: 8),
      Text(carrier,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 11.5, color: _sub)),
      const SizedBox(height: 6),
      Center(
        child: TextButton(
          onPressed: () => _openDoc('terms', '$carrier与隐私协议'),
          style: TextButton.styleFrom(
            foregroundColor: AppTheme.accent,
            minimumSize: const Size(0, 26),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: Text('《${carrier}与隐私协议》',
              style: const TextStyle(fontSize: 11.5)),
        ),
      ),
      const SizedBox(height: 14),
      _primaryBtn(
        key: const Key('auth-onekey-btn'),
        label: btnLabel,
        onTap: _busy
            ? null
            : (canOneKey || canPrefill
                ? _submitOneKey
                : () => setState(() => _mode = AuthMode.sms)),
      ),
      const SizedBox(height: 2),
      // 一键态下「其他手机号登录」＝回短信表单；
      // 已经是短信表单的降级态时，这行改成说明文案，别给两个一样的入口
      if (canOneKey || canPrefill)
        Center(
          child: TextButton(
            key: const Key('auth-switch-sms'),
            onPressed: _busy ? null : () => setState(() => _mode = AuthMode.sms),
            style: TextButton.styleFrom(
              foregroundColor: _hi,
              minimumSize: const Size(0, 40),
            ),
            child: const Text('其他手机号登录',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
          ),
        )
      else
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            OneKeyLoginService.hint(_ok.reason),
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 11.5, color: _sub, height: 1.5),
          ),
        ),
    ];
  }

  /// 切到一键态。
  ///
  /// 取不到号时**不弹「失败」**：一键态里会直接写清原因，并把主按钮换成
  /// 「用短信验证码登录」，用户不会走进死路。
  void _switchToOneKey() {
    if (!_cfg.allowOneKey) {
      CenterToast.show(context, '后台还没开放本机号码一键登录');
      return;
    }
    setState(() => _mode = AuthMode.onekey);
  }

  String _maskOf(String phone) {
    final p = phone.replaceAll(RegExp(r'\D'), '');
    if (p.length != 11) return '';
    return '${p.substring(0, 3)}****${p.substring(7)}';
  }

  // ── 通用控件 ──

  Widget _field({
    Key? key,
    required TextEditingController controller,
    required String hint,
    TextInputType? keyboardType,
    bool digits = false,
    int? maxLength,
    bool obscure = false,
    List<String>? autofill,
    Widget? prefix,
    Widget? suffix,
  }) {
    return Container(
      height: 54,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: _fieldBg,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          if (prefix != null) prefix,
          Expanded(
            child: TextField(
              key: key,
              controller: controller,
              keyboardType: keyboardType,
              obscureText: obscure,
              maxLength: maxLength,
              autofillHints: autofill,
              inputFormatters: digits
                  ? [FilteringTextInputFormatter.digitsOnly]
                  : null,
              cursorColor: AppTheme.accent,
              style: const TextStyle(
                  fontSize: 15.5, color: _hi, fontWeight: FontWeight.w500),
              decoration: InputDecoration(
                hintText: hint,
                counterText: '',
                isDense: true,
                // ★ 必须显式 filled:false —— 全局 InputDecorationTheme 是白底填充，
                //   深色卡片里会露出两个白框，看着像没做完。
                filled: false,
                fillColor: Colors.transparent,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                hintStyle: const TextStyle(fontSize: 15, color: _sub),
                contentPadding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
          ),
          if (suffix != null) suffix,
        ],
      ),
    );
  }

  Widget _primaryBtn({
    Key? key,
    required String label,
    required VoidCallback? onTap,
  }) {
    final enabled = onTap != null;
    return AnimatedBuilder(
      animation: _shakeX,
      builder: (context, child) => Transform.translate(
        offset: Offset(_shakeX.value, 0),
        child: child,
      ),
      child: SizedBox(
        height: 52,
        child: Material(
          color: enabled ? AppTheme.accent : AppTheme.accent.withOpacity(0.45),
          borderRadius: BorderRadius.circular(26),
          child: InkWell(
            key: key,
            borderRadius: BorderRadius.circular(26),
            onTap: onTap,
            child: Center(
              child: _busy
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          color: _bg, strokeWidth: 2.2),
                    )
                  : Text(
                      label,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: _bg,
                        letterSpacing: .5,
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _agreeRow() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        GestureDetector(
          key: const Key('auth-agree'),
          onTap: () => setState(() => _agree = !_agree),
          behavior: HitTestBehavior.opaque,
          child: Padding(
            padding: const EdgeInsets.only(right: 9, top: 4, bottom: 4),
            child: Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _agree ? AppTheme.accent : Colors.transparent,
                border: Border.all(
                  color: _agree ? AppTheme.accent : const Color(0xFF4A5058),
                  width: 1.4,
                ),
              ),
              child: _agree
                  ? const Icon(Icons.check, size: 13, color: _bg)
                  : null,
            ),
          ),
        ),
        Expanded(
          child: Text.rich(
            TextSpan(
              children: [
                const TextSpan(
                    text: '我已阅读并同意',
                    style: TextStyle(fontSize: 12, color: _sub)),
                WidgetSpan(
                  alignment: PlaceholderAlignment.baseline,
                  baseline: TextBaseline.alphabetic,
                  child: GestureDetector(
                    onTap: () => _openDoc('terms', '用户协议'),
                    child: const Text('《用户协议》',
                        style: TextStyle(fontSize: 12, color: _hi)),
                  ),
                ),
                WidgetSpan(
                  alignment: PlaceholderAlignment.baseline,
                  baseline: TextBaseline.alphabetic,
                  child: GestureDetector(
                    onTap: () => _openDoc('privacy', '隐私政策'),
                    child: const Text('《隐私政策》',
                        style: TextStyle(fontSize: 12, color: _hi)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _otherWays() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Expanded(child: Divider(color: _line, height: 1)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text('其他方式',
                  style: TextStyle(fontSize: 11.5, color: _sub)),
            ),
            const Expanded(child: Divider(color: _line, height: 1)),
          ],
        ),
        const SizedBox(height: 18),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (_cfg.allowWechat) _circleBtn(
              key: const Key('auth-wechat-btn'),
              icon: Icons.wechat,
              color: const Color(0xFF07C160),
              onTap: _busy ? null : _submitWechat,
            ),
            if (_cfg.allowWechat && _cfg.allowApple)
              const SizedBox(width: 26),
            if (_cfg.allowApple) _circleBtn(
              key: const Key('auth-apple-btn'),
              icon: Icons.apple,
              color: _hi,
              onTap: _appleHint,
            ),
          ],
        ),
      ],
    );
  }

  Widget _circleBtn({
    Key? key,
    required IconData icon,
    required Color color,
    required VoidCallback? onTap,
  }) {
    return GestureDetector(
      key: key,
      onTap: onTap,
      child: Container(
        width: 54,
        height: 54,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: _card,
          border: Border.all(color: _line),
        ),
        child: Icon(icon, size: 27, color: color),
      ),
    );
  }
}
