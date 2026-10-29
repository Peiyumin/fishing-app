/// 渔获「尺寸 / 重量」的展示口径（v2.1.54）
///
/// 用户明确要求：**重量单位用 KG，数字要比单位大**。
/// 所以详情页/发布页都不能再写成「1.8kg」这种同字号文本，
/// 统一走 [WeightText]：数字 17~20sp 粗体，单位 9.5~11sp 弱化，按基线对齐。
///
/// 库里存的一直是**克**（posts.weight_g，v27 起就是），
/// 这里只负责换算与格式化，别在业务层各处自己 `/1000`。
library;

/// 一段可上屏的重量：「数字 + 单位」
class WeightText {
  /// 数字部分，例如 `1.8`
  final String number;

  /// 单位，固定 `KG`；没有重量时为空串
  final String unit;

  /// 是否有真实重量（决定要不要画单位）
  final bool hasValue;

  const WeightText(this.number, this.unit, this.hasValue);

  /// 没记录重量时的占位（只显示一个破折号，不画单位）
  static const empty = WeightText('—', '', false);

  @override
  String toString() => hasValue ? '$number$unit' : number;
}

/// 克 → 上屏文本
///
/// - null / 0 / 负数 / NaN / Infinity → [WeightText.empty]
/// - 1kg 以下保留两位（0.85），10kg 以下一位（1.8），再大取整（12）
///
/// 小鱼用克看更准，但单位仍是 KG —— 用户要求统一 KG，别换成 g。
WeightText weightText(double? grams) {
  if (grams == null || !grams.isFinite || grams <= 0) return WeightText.empty;
  return WeightText(formatKg(grams / 1000), 'KG', true);
}

/// 公斤数值 → 上屏数字串（不带单位）
String formatKg(double kg) {
  if (!kg.isFinite || kg <= 0) return '—';
  if (kg >= 100) return kg.toStringAsFixed(0);
  if (kg >= 10) return kg.toStringAsFixed(1);
  return _trimZeros(kg.toStringAsFixed(2));
}

/// 克 → 公斤输入框里的数字（发布页「重量(KG)」预填用）
String kgInputText(double? grams) {
  if (grams == null || !grams.isFinite || grams <= 0) return '';
  final kg = grams / 1000;
  // 输入框里的数要能再被 double.parse 回来，且不要出现 0.850 这种尾巴
  return _trimZeros(kg.toStringAsFixed(kg < 10 ? 2 : 1));
}

String _trimZeros(String s) {
  if (!s.contains('.')) return s;
  var out = s;
  while (out.endsWith('0')) {
    out = out.substring(0, out.length - 1);
  }
  if (out.endsWith('.')) out = out.substring(0, out.length - 1);
  return out.isEmpty ? '0' : out;
}

// ───────────────────────── 体长 → 重量估算 ─────────────────────────

/// 肥满度系数（W(g) = K × L(cm)³ ÷ 100）
///
/// AI 视觉估长比估重准得多（长度有参照物，重量只能靠体型换算），
/// 所以 AI 只给了体长、没给重量时，按这个系数补一个**标注为估算**的重量，
/// 免得详情页永远是「—」。用户仍可在发布页改。
///
/// 数值取自常见淡水鱼的经验肥满度，误差约 ±20%，够用于展示。
const Map<String, double> _finenessK = {
  '鲫鱼': 2.1,
  '鲤鱼': 2.0,
  '草鱼': 1.7,
  '青鱼': 1.8,
  '鲢鱼': 1.6,
  '鳙鱼': 1.6,
  '鲢鳙': 1.6,
  '鳊鱼': 2.0,
  '罗非': 2.4,
  '黑鱼': 1.1,
  '乌鳢': 1.1,
  '鲈鱼': 1.3,
  '海鲈': 1.3,
  '翘嘴': 0.85,
  '白条': 1.2,
  '黄颡': 1.4,
  '鲶鱼': 1.2,
  '鳜鱼': 1.8,
  '泥鳅': 0.9,
  '马口': 1.0,
  '溪石斑': 1.3,
};

/// 按鱼种取肥满度系数（认不出就按 1.6 的通用值）
double finenessFor(String species) {
  final s = species.trim();
  if (s.isEmpty) return 1.6;
  for (final e in _finenessK.entries) {
    if (s.contains(e.key) || e.key.contains(s)) return e.value;
  }
  // 「大板鲫」「小鲫瓜」这类俗名里没有完整的「鲫鱼」，退一步按单字核心名（鲫/鲤/草…）匹配
  for (final e in _finenessK.entries) {
    final core = e.key.replaceAll('鱼', '');
    if (core.length >= 1 && core != e.key && s.contains(core)) return e.value;
  }
  return 1.6;
}

/// 用体长估一个重量（克）；体长缺失/异常返回 null
double? estimateWeightG(double? lengthCm, String species) {
  if (lengthCm == null || !lengthCm.isFinite || lengthCm <= 0) return null;
  final k = finenessFor(species);
  final g = k * lengthCm * lengthCm * lengthCm / 100;
  if (!g.isFinite || g <= 0) return null;
  return g;
}
