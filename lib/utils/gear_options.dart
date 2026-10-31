/// 渔获「装备与钓点」的固定选项（v2.1.58）
///
/// 用户要求（图一）：发布渔获时要能填 **饵料**、选 **鱼竿长度**、选 **钓点类型**。
/// 长度是他自己列的清单（3.0 / 3.2 / 3.6 / 3.9 / 4 / 4.5 / 4.8 / 5.4 / 5.7 /
/// 6.3 / 7.2 / 8.1 / 9 / 10），统一按「米」展示成一位小数。
///
/// ★ 这些值要落库（posts.rod_length / posts.water_type / posts.bait），
///   所以**只放字符串常量**：别在这里做本地化，也别塞入长度单位，
///   库里存 "3.6"，展示时才拼「3.6 米」。否则以后统计「多少米的竿上鱼多」
///   会被 "3.6 米" 这种带单位的脏值卡住。
library;

/// 鱼竿长度（米）：展示与存储都用这一份，顺序即用户给的顺序
const List<String> kRodLengths = <String>[
  '3.0',
  '3.2',
  '3.6',
  '3.9',
  '4.0',
  '4.5',
  '4.8',
  '5.4',
  '5.7',
  '6.3',
  '7.2',
  '8.1',
  '9.0',
  '10.0',
];

/// 钓点（水体）类型：与地图水系的叫法保持一致（江河 / 湖泊 / 水库 / 池塘），
/// 另外补上钓友口头常用的「坑塘」「溪流」「海钓」。
const List<String> kWaterTypes = <String>[
  '坑塘',
  '江河',
  '水库',
  '湖泊',
  '溪流',
  '海钓',
];

/// 常用饵料：只是「点一下帮你填」的快捷词，不是封闭选项
/// （饵料组合千变万化，必须允许自己写）
const List<String> kBaitQuickPicks = <String>[
  '蚯蚓',
  '红虫',
  '玉米',
  '腥香拉饵',
  '麦粒',
  '商品饵',
  '路亚假饵',
];

/// 「3.6」→「3.6 米」；空值返回空串
String rodLengthText(String raw) {
  final v = raw.trim();
  return v.isEmpty ? '' : '$v 米';
}

/// 装备是否填过任何一项（详情页据此决定显示「还没填」还是内容）
bool hasGearInfo({String bait = '', String rod = '', String water = '', String note = ''}) =>
    bait.trim().isNotEmpty ||
    rod.trim().isNotEmpty ||
    water.trim().isNotEmpty ||
    note.trim().isNotEmpty;
