import 'package:characters/characters.dart';

/// 外部文本的「净化」与「安全截断」
///
/// 为什么需要这一层：
/// 1. **半个字符 = 一个小方块。** Dart 的 `String.substring` 按 UTF-16
///    code unit 切，而 emoji（🎣）、罕见汉字（𠮷）用 2 个 code unit
///    （代理对）。`'钓鱼佬🎣'.substring(0, 4)` 会把 🎣 的高位代理和低位
///    代理切开，剩下一个**孤立代理项** —— 渲染引擎找不到字形，就画成
///    豆腐块。用户看到的就是「名字里有乱码方块」。
///
/// 2. **解码残留也是方块。** 服务端若把 UTF-8 从中间截断，客户端解码会
///    得到 U+FFFD（替换字符），它的字形在很多字体里就是一个空心方块。
///
/// 3. 昵称、钓点名字、地址、城市名来自「用户输入 + 服务端 + 第三方地名接口」，
///    三条链路都可能带进上面的脏数据，所以统一在**数据入口**净化一次，
///    而不是在每个 `Text()` 前面各写一遍。
///
/// 会渲染成方块 / 豆腐块的字符：
/// - `U+FFFD` 替换字符（UTF-8 解码失败的产物，字形就是一个方块）
/// - `U+0000` / `U+FEFF`（NUL、BOM）
/// - C0 控制符（保留 `\t` `\n` `\r`）
///
/// ★ 故意**不**删 `U+200B~U+200F`：其中 `U+200D` 是 ZWJ，emoji 组合
///   （👨‍👩‍👧、🎣‍…）靠它拼合，删了会把一个表情拆成几个。
final RegExp _invisibleToFu = RegExp(
  '[\uFFFD\u0000\uFEFF\u0001-\u0008\u000B\u000C\u000E-\u001F\u007F]',
);

/// 把字符串里的**孤立代理项**丢掉（合法的代理对原样保留）
///
/// 不能用正则 `[\uD800-\uDFFF]` 来做：Dart 的 `String` 是 UTF-16，
/// 那个字符类会把 🎣 的高低位代理也当命中，等于删掉所有 emoji。
String _dropLoneSurrogates(String s) {
  StringBuffer? buf;

  /// 第一次需要改写时才建缓冲，并把「原串在当前位置之前的内容」一次性补进来
  void begin(int upTo) {
    if (buf != null) return;
    buf = StringBuffer();
    if (upTo > 0) buf!.write(s.substring(0, upTo));
  }

  for (var i = 0; i < s.length; i++) {
    final c = s.codeUnitAt(i);
    final isHigh = c >= 0xD800 && c <= 0xDBFF;
    final isLow = c >= 0xDC00 && c <= 0xDFFF;
    if (isHigh) {
      // 高位代理后面必须紧跟低位代理，否则就是被切断的半个字符
      if (i + 1 < s.length) {
        final n = s.codeUnitAt(i + 1);
        if (n >= 0xDC00 && n <= 0xDFFF) {
          begin(i);
          buf!
            ..writeCharCode(c)
            ..writeCharCode(n);
          i++;
          continue;
        }
      }
      begin(i); // 丢掉孤立高位
      continue;
    }
    if (isLow) {
      begin(i); // 走到这里说明它前面没有配对的高位代理 → 丢掉
      continue;
    }
    buf?.writeCharCode(c);
  }
  return buf?.toString() ?? s;
}

/// 净化任意外部字符串：清掉会显示成方块的字符，并去掉首尾空白
///
/// - `null` → `''`
/// - 非字符串用 `toString()`
/// - **内部换行原样保留**（正文分段要用）
String safeText(Object? v) {
  if (v == null) return '';
  var s = v is String ? v : v.toString();
  if (s.isEmpty) return '';
  final cleaned = _dropLoneSurrogates(s).replaceAll(_invisibleToFu, '');
  return cleaned.trim();
}

/// 递归净化 JSON 结构里的**所有字符串值**（键不动）
///
/// 挂在接口层用：一次覆盖全站所有页面，不用在每个 model 的 `fromJson`
/// 里重复调用。
dynamic sanitizeDeep(dynamic v) {
  if (v is String) return safeText(v);
  if (v is List) return v.map<dynamic>(sanitizeDeep).toList(growable: true);
  if (v is Map) {
    return v.map<String, dynamic>(
      (k, val) => MapEntry(k.toString(), sanitizeDeep(val)),
    );
  }
  return v;
}

/// 按**字素簇**截断（用户眼里的「一个字」），不会切碎 emoji 与组合字符
///
/// `clipGrapheme('钓鱼佬🎣', 3)` → `'钓鱼佬…'`
/// 旧的 `substring(0, 3)` 会切出半个 🎣 → 方块。
String clipGrapheme(String s, int max, {String ellipsis = '…'}) {
  if (s.isEmpty || max <= 0) return '';
  final cs = s.characters;
  if (cs.length <= max) return s;
  return '${cs.take(max)}$ellipsis';
}

/// 同 [clipGrapheme]，但超长时**不加省略号**（用于水印之类不需要提示的场合）
String cutGrapheme(String s, int max) {
  if (s.isEmpty || max <= 0) return '';
  final cs = s.characters;
  if (cs.length <= max) return s;
  return cs.take(max).toString();
}
