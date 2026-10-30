/// 定位文案：只显示到「县级市 / 区 / 县」这一级
///
/// 用户要求（v2.1.56）：文章详情作者名下面的定位要「当前用户的真实定位，
/// 定位只到县级市」。原来这里直接回退成了**分类名**（如「垂钓技巧」），
/// 看上去像地址其实是栏目，属于明显的错位。
///
/// 规则（按中国行政区划的实际写法）：
///   禹州市（县级市）+ 许昌市 → 「禹州市」      （县级市自成一格，不带地级市）
///   南山区 + 深圳市           → 「深圳市南山区」 （市辖区带上地级市更清楚）
///   只有区县没有地级市         → 「南山区」
///   只有地级市                → 「深圳市」
/// 直辖市（city == district）不重复输出。
///
/// v2.1.57：加 [withProvince] —— 用户要求「河南省·禹州市」这种带省的写法。
/// 只在需要「一眼看出在哪个省」的地方打开（个人主页注册地、文章作者定位、
/// AI 报告地址），列表里的短标签仍然用不带省的形式，免得一行挤爆。
String countyLabel({
  String city = '',
  String district = '',
  String province = '',
  bool withProvince = false,
}) {
  final c = city.trim();
  final d = district.trim();
  final p = province.trim();

  final base = _countyCore(c: c, d: d, p: p);
  if (!withProvince || p.isEmpty) return base;
  // 已经是「北京市朝阳区」这种自带省的写法，别再拼一遍
  if (base.startsWith(p)) return base;
  if (base.isEmpty) return p;
  return '$p·$base';
}

String _countyCore({required String c, required String d, required String p}) {
  if (d.isEmpty && c.isEmpty) return p;
  if (d.isEmpty) return c;
  if (c.isEmpty) return d;
  if (c == d) return c;

  // 县级市（xx市）本身就是县级，前缀地级市会变成「许昌市禹州市」，啰嗦
  if (d.endsWith('市')) return d;
  // 市辖区/县：去掉地级市末尾的「市」再接区县，读起来是「深圳南山区」还是
  // 「深圳市南山区」？后者更符合导航软件的写法，这里保留「市」。
  return '$c$d';
}

/// 从一个「完整地址」里截到县级（后端/第三方有时只给了 display 长串）
///
/// 例：湖北省武汉市洪山区狮子山街道 → 武汉市洪山区
String countyFromDisplay(String display) {
  final s = display.trim();
  if (s.isEmpty) return '';
  // 先按「市」切：省 + 市 + 剩余
  final m = RegExp(r'^(.*?[省市自治区]{1,3})(.*?[市])?(.*)$').firstMatch(s);
  if (m == null) return s;
  final cityPart = (m.group(2) ?? '').trim();
  final rest = (m.group(3) ?? '').trim();
  if (cityPart.isEmpty) {
    // 没有地级市（直辖市/海外）：取前两个行政段
    return rest.isEmpty ? s : rest;
  }
  if (rest.isEmpty) return cityPart;
  // 剩余部分取第一个区县段（区/县/县级市/旗）
  final d = RegExp(r'^(.{1,8}?(?:区|县|市|旗))').firstMatch(rest);
  return d == null ? cityPart : '$cityPart${d.group(1)}';
}
