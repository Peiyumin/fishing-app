/// 协议文本排版：把后端下发的纯文本切成「标题 / 正文」段
///
/// 规则（后端 lib/settings.php 的 legal_docs() 就是这么生成的）：
///   · `## xxx`  → 小节标题
///   · 其它非空行 → 正文；正文之间不额外空行，靠行高区分
///   · 空行 → 段落间距
///
/// 抽成纯函数是为了能单测：协议页本身依赖网络，widget 测试里不好断言。
class LegalBlock {
  final bool isTitle;
  final String text;
  const LegalBlock({required this.isTitle, required this.text});

  @override
  String toString() => '${isTitle ? '#' : '-'} $text';
}

List<LegalBlock> parseLegalText(String content) {
  final out = <LegalBlock>[];
  for (final raw in content.split('\n')) {
    final line = raw.trim();
    if (line.isEmpty) continue;
    if (line.startsWith('##')) {
      final t = line.replaceFirst(RegExp(r'^#+\s*'), '').trim();
      if (t.isNotEmpty) out.add(LegalBlock(isTitle: true, text: t));
    } else {
      out.add(LegalBlock(isTitle: false, text: line));
    }
  }
  return out;
}
