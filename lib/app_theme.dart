import 'package:flutter/material.dart';

/// 全局设计系统：极简黑 · 荧光黄绿（按设计稿 1:1 取色）
///
/// 设计语言（从 5 张设计稿逐像素取样得出）：
///  - 主色 = 近黑 #07080C：所有「重量」都由黑色承担（主按钮、选中态、标题、
///    顶部 Hero），不用彩色抢注意力；
///  - 强调色 = 荧光黄绿 #C6FF3D：整个 App 只有一个彩色，只出现在
///    ① 深底上的文字/图标 ② 填充色块（配黑字）③ 选中指示条。
///    **它不能当白底上的文字**（对比度 1.1:1，等于看不见），白底要文字
///    就用 accentDark；
///  - 中性色 = 冷灰蓝（#EDF1F6 页面底 / #FFFFFF 卡片 / #7D8694 次要文字），
///    不用带绿调的灰 —— 带绿调的灰和荧光黄绿并置会显脏；
///  - 形状 = 大圆角 + 细描边，不用重阴影；
///  - 数据可视化保留功能色：高温红 #F44336 / 低温蓝 #46A0FB。
class AppTheme {
  // ───────────────────────── 品牌主色（近黑） ─────────────────────────
  /// 主色：近黑。按钮、选中态、标题、深色 Hero
  static const Color primary = Color(0xFF07080C);
  static const Color primaryDark = Color(0xFF000000);
  /// 主色的浅色底（选中芯片底、图标容器）：中性冷灰，不带色相
  static const Color primaryLight = Color(0xFFEFF2F7);
  /// 极浅冷灰（占位背景、轻表面）
  static const Color primarySoft = Color(0xFFF7F9FC);
  /// 主色描边（虚线框、图标描边）
  static const Color primaryBorder = Color(0xFFDDE4EE);

  // ───────────────────────── 强调色（荧光黄绿） ─────────────────────────
  /// 品牌强调：荧光黄绿。
  /// **只用于深底文字/图标、填充色块（配黑字）、选中指示条、数据高亮**。
  static const Color accent = Color(0xFFC6FF3D);
  /// 强调色的深阶：白底上唯一可读的「黄绿系」文字色（对比度 4.6:1）
  static const Color accentDark = Color(0xFF5C7800);
  /// 强调色的极浅底（图表填充、选中行底）
  static const Color accentLight = Color(0xFFF4FFD9);
  /// 强调色的中间档：「三段进度 / 刻度条」里代表「半满」的那一格。
  /// 淡灰 → accentMid → accent，越满越亮，天气页刻度条与详情页 CATCH INDEX
  /// 共用同一档，两边才像同一套语言。
  static const Color accentMid = Color(0xFF8FAF5A);

  /// 与 [accent] 同值的别名，语义更直白的地方用它
  static const Color lime = accent;
  /// 白底上的黄绿文字（= accentDark），可读性优先的地方用它
  static const Color limeInk = accentDark;

  /// 水面蓝（地图水域图层、水位图）：设计稿里的数据蓝
  static const Color water = Color(0xFF46A0FB);
  /// 水蓝的深阶：浅底上的**水色文字/描边**（water 在白底只够做填充，
  /// 直接当 11px 标签字读不清），地图里的水体名称、水域描边走这一档
  static const Color waterDeep = Color(0xFF1E5FA8);

  // ───────────────────────── 语义 / 点缀色 ─────────────────────────
  /// 星标 / 评分 / 晴天：暖黄（设计稿里天气图标就是这一档暖黄）
  static const Color star = Color(0xFFF5B942);
  static const Color starLight = Color(0xFFFFF5DF);
  /// 暖黄在白底上的文字版本（对比度够了才用）
  static const Color starDark = Color(0xFF9A6B00);
  /// 天气图标的冷蓝三档（设计稿取样：云是冷蓝白，不是灰、更不是灰绿）。
  /// 浅云 / 多云 / 阴，只在 [Wmo.color] 里用，别拿去当 UI 强调色。
  static const Color skyLight = Color(0xFFAFC3E2);
  static const Color sky = Color(0xFF9BB4D6);
  static const Color skyDeep = Color(0xFF7E9BC2);
  /// 危险 / 删除 / 高温
  static const Color danger = Color(0xFFF44336);
  static const Color dangerDark = Color(0xFFC62828);
  static const Color dangerLight = Color(0xFFFDECEA);
  /// 警示 / 审核中 / 低温（降一档的橙）
  static const Color warning = Color(0xFFE8973A);
  static const Color warningLight = Color(0xFFFBF1E3);
  /// 以下三档原为紫/靛/深橙的「分类装饰色」。
  /// 设计稿只有黑、白、冷灰 + 一个荧光黄绿，所以这里全部退成冷灰阶，
  /// 靠图标 + 文字区分，不再靠色相 —— 一屏四五个高饱和色是「不协调」的根源。
  static const Color violet = Color(0xFF5B6472);
  static const Color violetLight = Color(0xFFEFF2F7);
  static const Color indigo = Color(0xFF5B6472);
  static const Color indigoLight = Color(0xFFEFF2F7);
  static const Color deepOrange = Color(0xFF5B6472);
  static const Color deepOrangeLight = Color(0xFFEFF2F7);

  // ───────────────────────── 表面 / 文字 / 线条 ─────────────────────────
  /// 页面背景：冷灰蓝（设计稿 #EDF1F6）
  static const Color background = Color(0xFFEDF1F6);
  /// 卡片 / 浮层表面
  static const Color surface = Colors.white;
  static const Color textPrimary = Color(0xFF07080C);
  static const Color textSecondary = Color(0xFF7D8694);
  /// 第三级文字（城市·时间、计数、说明）
  static const Color textTertiary = Color(0xFF8B94A3);
  static const Color divider = Color(0xFFEBEFF5);
  static const Color border = Color(0xFFE2E8F0);
  /// 「今天」列的高亮底（天气页 7 天条、逐时表）：设计稿的淡蓝，
  /// 比 primaryLight 多一点蓝，用来和"不是今天"的列区分开
  static const Color todayTint = Color(0xFFE9F2FE);

  // ─────────────── 深色面板（沉浸页专用：天气 / 地图 / 池塘） ───────────────
  //
  // 深底统一走**近黑**（不是深墨绿、也不是深蓝），与首页 Hero 同一档，
  // 这样从首页进天气页不会像换了个 App。
  //
  // 层级固定 6 档 + 1 个高亮：
  //   inkBg(底) < inkSurfaceAlt(交替行) < inkSurface(卡面) < inkLine(分隔线)
  //   inkText(主文字) / inkMuted(次要文字) / inkHi(高亮)
  static const Color inkBg = Color(0xFF07080C);
  static const Color inkSurface = Color(0xFF12151B);
  static const Color inkSurfaceAlt = Color(0xFF0C0F14);
  static const Color inkLine = Color(0xFF232A34);
  /// 表头 / 略微提起的一条带
  static const Color inkHead = Color(0xFF111620);
  static const Color inkText = Color(0xFFF2F5F9);
  static const Color inkMuted = Color(0xFF8B94A3);

  /// 深底高亮：荧光黄绿。全站唯一的高饱和色，深底上一律用它。
  static const Color inkHi = accent;

  // ───────────────────────── 形状 / 间距 / 字阶 ─────────────────────────
  /// 设计稿的卡片圆角更大，24 是主档
  static const double radiusLg = 24;
  static const double radiusMd = 16;
  static const double radiusSm = 12;
  static const double radiusPill = 999;

  static const double sp1 = 4;
  static const double sp2 = 8;
  static const double sp3 = 12;
  static const double sp4 = 16;
  static const double sp5 = 20;
  static const double sp6 = 24;
  static const double sp8 = 32;

  /// 卡片之间的纵向间距（列表页统一用这一档，别一处 10 一处 12）
  static const double cardGap = 12;

  static const double fsCaption = 12;
  static const double fsBody = 14;
  static const double fsTitle = 16;
  static const double fsHeadline = 18;
  static const double fsDisplay = 22;

  // ───────────────────────── 渐变 ─────────────────────────
  /// 顶部 Hero 渐变：近黑 → 略提亮的一档黑（保留极轻的层次，不用纯色块）
  static const Gradient headerGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF07080C), Color(0xFF161B22)],
  );
  /// 品牌块渐变（深黑 → 石墨灰），用于商城横幅等大色块
  static const Gradient brandGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF07080C), Color(0xFF1D242E)],
  );
  /// 强调渐变（黄绿 → 略深），只用于深底上的填充色块
  static const Gradient accentGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFC6FF3D), Color(0xFFA8E52B)],
  );

  /// 柔和阴影（取代硬 elevation，卡片/浮层通用）
  /// 冷灰底上阴影要更淡，否则卡片边缘发脏
  static List<BoxShadow> get softShadow => const [
        BoxShadow(
          color: Color(0x0F0B1220),
          blurRadius: 16,
          offset: Offset(0, 6),
        ),
      ];

  /// 更轻的阴影（小浮层 / 横向卡片）
  static List<BoxShadow> get lightShadow => const [
        BoxShadow(
          color: Color(0x0A0B1220),
          blurRadius: 10,
          offset: Offset(0, 3),
        ),
      ];

  /// ★★ 历史遗留坑（v2.1.36 已拆除）：曾经有过
  /// `fontFamilyFallback: ['PingFang SC', 'Hiragino Sans GB',
  /// 'Microsoft YaHei', 'Noto Sans CJK SC', 'Noto Sans SC']`。
  ///
  /// 这里列的全是「某个平台才有」的字体名 —— `PingFang SC` / `Hiragino Sans GB`
  /// 只有 iOS/macOS 有，`Microsoft YaHei` 只有 Windows 有，`Noto Sans SC`
  /// 在多数 Android 上不是这个名字。一旦某个机型的系统字体被 ROM 换掉
  /// （MIUI 的 MiSans、ColorOS 的 OPPO Sans、鸿蒙的 HarmonyOS Sans），
  /// 这条链**整条解析失败**，Flutter 只能退到 last-resort 字体，
  /// 结果就是全站中文和 emoji 都渲染成空心方块（豆腐块）。
  ///
  /// 正确做法是**什么都不指定**：Android 的 fontconfig 会给出
  /// Roboto → Noto Sans CJK → Noto Color Emoji 的完整兜底，
  /// iOS 会给 San Francisco → PingFang SC → Apple Color Emoji。
  /// 官方默认链比手写列表覆盖得更全，手写只会把兜底切断。
  /// 回归护栏见 `test/cjk_font_test.dart`。

  /// 类别语义色（与发布中心、信息流标签、钓点筛选统一）
  /// 设计稿是单色系：除「二手交易」保留红（功能性警示）外，其余统一近黑。
  static Color categoryColor(String cat) {
    switch (cat) {
      case 'sell':
        return danger;
      default:
        return textPrimary;
    }
  }

  /// 类别浅色底（标签 / 图标容器底色）
  static Color categorySoft(String cat) {
    switch (cat) {
      case 'sell':
        return dangerLight;
      default:
        return primaryLight;
    }
  }

  static final ThemeData light = ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    primaryColor: primary,
    scaffoldBackgroundColor: background,
    // ★ 这里**故意不设** fontFamily / fontFamilyFallback —— 见上方
    //   「历史遗留坑」的注释：手写中文回退栈会在部分 ROM 上整条解析
    //   失败，全站中文和 emoji 变方块。交给平台的系统字体链，覆盖最全。
    //   `test/cjk_font_test.dart` 钉住了这一点，防止以后有人再塞回来。
    colorScheme: const ColorScheme.light(
      primary: primary,
      onPrimary: Colors.white,
      primaryContainer: primaryLight,
      secondary: accent,
      onSecondary: textPrimary,
      secondaryContainer: accentLight,
      onSecondaryContainer: accentDark,
      surface: surface,
      onSurface: textPrimary,
      outline: border,
      error: danger,
    ),
    // ★ v2.1.59：二级页顶栏统一为**浅色**。
    //
    // 旧版走主题近黑：全站 44 个页面里有 33 个是「浅灰页面 + 一整块纯黑顶栏」，
    // 一进设置/消息/订单就先撞一大块黑，视觉上又沉又割裂；另有 11 个页面
    // 自己写了白底，于是同一层级的页面顶栏一半黑一半白。
    // 现在统一成「白底 + 近黑标题 + 1px 细线收边」，与卡片同一材质，
    // 页面从顶部到内容是一整片浅色，才是「干净、一眼清新」。
    //
    // 沉浸页（天气 / 地图 / 池塘 / AI 雷达 / 渔获详情等深色头）
    // **必须自己写 foregroundColor: Colors.white**，否则黑图标压在深底上会消失。
    // 回归护栏见 test/v2159_shell_test.dart。
    appBarTheme: AppBarTheme(
      backgroundColor: surface,
      foregroundColor: textPrimary,
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      centerTitle: true,
      titleTextStyle: kAppBarTitle,
      // 顶栏与内容的界线用 1px 细线，不用阴影 —— 阴影会让页面显得脏
      shape: const Border(bottom: BorderSide(color: divider, width: 1)),
      // 不再写死 iconTheme 的白色：写死之后，页面把 AppBar 换成浅底、
      // 只设 foregroundColor 是**管不到图标的**，返回箭头/动作图标
      // 会白字白底直接消失（天气页、通知设置页都踩过）。
      // 留空则自动跟随 foregroundColor：深色顶栏仍是白色图标。
    ),
    cardTheme: CardTheme(
      color: surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radiusLg),
        side: const BorderSide(color: divider, width: 1),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: primary,
        foregroundColor: Colors.white,
        elevation: 0,
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusMd),
        ),
        textStyle: const TextStyle(
          fontSize: fsBody,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: primary,
        side: const BorderSide(color: primary),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusMd),
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: accentDark,
        textStyle: const TextStyle(
          fontSize: fsCaption,
          fontWeight: FontWeight.w500,
        ),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: surface,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radiusMd),
        borderSide: const BorderSide(color: border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radiusMd),
        borderSide: const BorderSide(color: border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radiusMd),
        borderSide: const BorderSide(color: primary, width: 1.5),
      ),
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    ),
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: surface,
      selectedItemColor: primary,
      unselectedItemColor: textTertiary,
      selectedLabelStyle:
          TextStyle(fontSize: fsCaption, fontWeight: FontWeight.w700),
      unselectedLabelStyle: TextStyle(fontSize: fsCaption),
      elevation: 8,
    ),
    dividerTheme: const DividerThemeData(
      color: divider,
      thickness: 1,
      space: 1,
    ),
    // 未选中：白底 + 灰字 + 细描边；选中：黑底 + 荧光黄绿字（设计稿的胶囊）
    chipTheme: ChipThemeData(
      backgroundColor: surface,
      selectedColor: primary,
      labelStyle: const TextStyle(color: textSecondary, fontSize: fsCaption),
      secondaryLabelStyle: const TextStyle(
        color: accent,
        fontSize: fsCaption,
        fontWeight: FontWeight.w700,
      ),
      checkmarkColor: accent,
      side: const BorderSide(color: border),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radiusPill),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    ),
  );
}

/// 二级页顶栏标题样式（全站唯一一档）。
///
/// 改造前 44 个页面各自写了 15 / 16 / 17 / 18 / 19 五档字号、两种颜色，
/// 于是同一层级的页面标题看着大小不一。现在只认这一个常量。
const TextStyle kAppBarTitle = TextStyle(
  fontSize: 17,
  fontWeight: FontWeight.w700,
  color: AppTheme.textPrimary,
  letterSpacing: 0.2,
);

/// 沉浸页（深色顶栏）用的标题样式：白字
const TextStyle kAppBarTitleOnDark = TextStyle(
  fontSize: 17,
  fontWeight: FontWeight.w700,
  color: Colors.white,
  letterSpacing: 0.2,
);
