/// 鱼种 → App 内置真实鱼图（assets/fish/*.png）
///
/// 素材是 46 种鱼的实拍风格侧身照，抠成透明 PNG 打包在安装包里，
/// **不走网络**：图鉴、钓鱼档案、池塘里的鱼共用同一套，断网也在。
/// 加上别名表是因为后台词库里同一个鱼有不同写法（鲇鱼/鲶鱼、翘嘴鲌/翘嘴）。
class FishAssets {
  FishAssets._();

  /// 中文鱼名 → 文件名（不含目录与扩展名）
  static const Map<String, String> _map = {
    // ── 淡水 23 种 ──
    '鲫鱼': 'jiyu',
    '鲤鱼': 'liyu',
    '草鱼': 'caoyu',
    '鲢鱼': 'lianyu',
    '鳙鱼': 'yongyu',
    '青鱼': 'qingyu',
    '罗非鱼': 'luofeiyu',
    '翘嘴鲌': 'qiaozui',
    '鲮鱼': 'lingyu',
    '黄颡鱼': 'huangsang',
    '鲇鱼': 'nianyu',
    '鳊鱼': 'bianyu',
    '马口鱼': 'makou',
    '麦穗鱼': 'maisui',
    '白条': 'baitiao',
    '黑鱼': 'heiyu',
    '鲈鱼': 'luyu',
    '鳜鱼': 'guiyu',
    '鲟鱼': 'xunyu',
    '鳡鱼': 'ganyu',
    '大银鱼': 'dayinyu',
    '胭脂鱼': 'yanzhiyu',
    '江雪': 'jiangxue',
    // ── 海水 23 种 ──
    '海鲈鱼': 'hailuyu',
    '大黄鱼': 'dahuangyu',
    '小黄鱼': 'xiaohuangyu',
    '带鱼': 'daiyu',
    '鲅鱼': 'bayu',
    '鲷鱼': 'diaoyu',
    '石斑鱼': 'shibanyu',
    '黑鲷': 'heidiao',
    '真鲷': 'zhendiao',
    '比目鱼': 'bimu',
    '鲐鱼': 'taiyu',
    '鲻鱼': 'ziyu',
    '海鳗': 'haiman',
    '鱿鱼': 'youyu',
    '章鱼': 'zhangyu',
    '海鲫鱼': 'haijiyu',
    '六线鱼': 'liuxianyu',
    '黑头鱼': 'heitouyu',
    '金枪鱼': 'jinqiangyu',
    '旗鱼': 'qiyu',
    '剑鱼': 'jianyu',
    '石鲷': 'shidiaoyu',
    '翻车鱼': 'fancheyu',
  };

  /// 常见别名 / 俗称 → 标准名
  static const Map<String, String> _alias = {
    '鲶鱼': '鲇鱼',
    '塘虱': '鲇鱼',
    '翘嘴': '翘嘴鲌',
    '大白鱼': '翘嘴鲌',
    '鲫瓜子': '鲫鱼',
    '鲤拐子': '鲤鱼',
    '白鲢': '鲢鱼',
    '鲢子': '鲢鱼',
    '花鲢': '鳙鱼',
    '胖头鱼': '鳙鱼',
    '螺蛳青': '青鱼',
    '青混': '青鱼',
    '黑鱼': '黑鱼',
    '乌鳢': '黑鱼',
    '桂花鱼': '鳜鱼',
    '季花鱼': '鳜鱼',
    '鲈板': '鲈鱼',
    '鲈子': '鲈鱼',
    '黄辣丁': '黄颡鱼',
    '昂刺鱼': '黄颡鱼',
    '嘎鱼': '黄颡鱼',
    '长春鳊': '鳊鱼',
    '草鳊': '鳊鱼',
    '参鱼': '白条',
    '餐条': '白条',
    '白鲦': '白条',
    '土鲮': '鲮鱼',
    '鲮公': '鲮鱼',
    '红眼鱼': '鲻鱼',
    '鮸鱼': '大黄鱼',
    '花鲈': '海鲈鱼',
    '寨花': '海鲈鱼',
    '多宝鱼': '比目鱼',
    '偏口': '比目鱼',
    '鲅': '鲅鱼',
    '马鲛': '鲅鱼',
    '秋刀': '鲐鱼',
    '青花鱼': '鲐鱼',
    '鲳鱼': '鲷鱼',
    '加吉鱼': '真鲷',
    '黑加吉': '黑鲷',
    '海鲋': '黑鲷',
    '石斑': '石斑鱼',
    '大眼': '黑头鱼',
    '黑石鲈': '黑头鱼',
    '黄鸡鱼': '六线鱼',
    '鲈鳗': '海鳗',
    '枪鱼': '旗鱼',
    '马林鱼': '旗鱼',
  };

  /// 每条鱼的宽高比（宽 / 高），打包时就量好了。
  /// 只给高度不给宽度时，用它算宽度 —— 否则带鱼这种 3.3:1 的长条鱼
  /// 会按原始尺寸撑满一行，把格子和按钮顶破。
  static const Map<String, double> _aspect = {
    'baitiao': 3.333,
    'bayu': 3.711,
    'bianyu': 1.579,
    'bimu': 1.682,
    'caoyu': 3.429,
    'dahuangyu': 3.913,
    'daiyu': 4.615,
    'dayinyu': 2.857,
    'diaoyu': 2.466,
    'fancheyu': 1.143,
    'ganyu': 4.337,
    'guiyu': 1.978,
    'haijiyu': 2.250,
    'hailuyu': 1.519,
    'haiman': 2.011,
    'heidiao': 1.338,
    'heitouyu': 1.773,
    'heiyu': 2.951,
    'huangsang': 3.051,
    'jiangxue': 4.186,
    'jianyu': 1.572,
    'jinqiangyu': 2.791,
    'jiyu': 2.182,
    'lianyu': 2.384,
    'lingyu': 2.975,
    'liuxianyu': 2.835,
    'liyu': 2.156,
    'luofeiyu': 2.384,
    'luyu': 2.236,
    'maisui': 2.590,
    'makou': 3.243,
    'nianyu': 1.538,
    'qiaozui': 2.500,
    'qingyu': 2.748,
    'qiyu': 1.791,
    'shibanyu': 2.182,
    'shidiaoyu': 2.209,
    'taiyu': 3.529,
    'xiaohuangyu': 3.130,
    'xunyu': 4.337,
    'yanzhiyu': 1.818,
    'yongyu': 2.156,
    'youyu': 3.600,
    'zhangyu': 1.600,
    'zhendiao': 1.622,
    'ziyu': 3.333,
  };

  /// 素材宽高比；查不到按 2.6:1 估（大多数淡水鱼的侧面比例）
  static double aspectOf(String name) {
    final slug = slugOf(name);
    if (slug == null) return 2.6;
    return _aspect[slug] ?? 2.6;
  }

  /// 查不到时按水类型兜底，避免露出一个空白格
  static const String _freshFallback = 'caoyu';
  static const String _saltFallback = 'diaoyu';

  static String? slugOf(String name) {
    final n = name.trim();
    if (n.isEmpty) return null;
    final std = _alias[n] ?? n;
    final direct = _map[std];
    if (direct != null) return direct;
    // 名字里带「鱼」之外的后缀（如「小黄鱼苗」）做一次包含匹配
    for (final e in _map.entries) {
      if (n.contains(e.key) || e.key.contains(n)) return e.value;
    }
    return null;
  }

  /// 素材相对路径；查不到返回 null（调用方自己决定怎么兜底）
  static String? pathOf(String name) {
    final slug = slugOf(name);
    return slug == null ? null : 'assets/fish/$slug.png';
  }

  /// 一定会返回一个可用素材：查不到就按水类型给一张同水体代表鱼
  static String pathOrFallback(String name, {String waterType = 'fresh'}) {
    return pathOf(name) ??
        'assets/fish/${waterType == 'salt' ? _saltFallback : _freshFallback}.png';
  }

  static bool has(String name) => slugOf(name) != null;
}
