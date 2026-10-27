/// 鱼种（图鉴词库中的一种鱼）
class FishSpecies {
  final String id;
  final String name;
  final String alias;
  final String waterType; // fresh 淡水 / salt 海水
  final String rarity; // common 常见 / rare 稀有 / legend 传说
  final String image;
  final String intro;
  final bool unlocked;
  final int count;
  final String catchImg;
  final String firstAt;

  const FishSpecies({
    required this.id,
    this.name = '',
    this.alias = '',
    this.waterType = 'fresh',
    this.rarity = 'common',
    this.image = '',
    this.intro = '',
    this.unlocked = false,
    this.count = 0,
    this.catchImg = '',
    this.firstAt = '',
  });

  bool get isFresh => waterType == 'fresh';
  String get rarityText =>
      rarity == 'legend' ? '传说' : (rarity == 'rare' ? '稀有' : '常见');

  factory FishSpecies.fromJson(Map<String, dynamic> j) => FishSpecies(
        id: (j['id'] ?? '').toString(),
        name: (j['name'] ?? '').toString(),
        alias: (j['alias'] ?? '').toString(),
        waterType: (j['waterType'] ?? 'fresh').toString(),
        rarity: (j['rarity'] ?? 'common').toString(),
        image: (j['image'] ?? '').toString(),
        intro: (j['intro'] ?? '').toString(),
        unlocked: (j['unlocked'] as bool?) ?? false,
        count: (j['count'] as num?)?.toInt() ?? 0,
        catchImg: (j['catchImg'] ?? '').toString(),
        firstAt: (j['firstAt'] ?? '').toString(),
      );
}

/// 图鉴等级
class FishLevel {
  final int level;
  final String name;
  final String nextName;
  final int nextNeed;

  const FishLevel({
    this.level = 0,
    this.name = '临渊羡鱼',
    this.nextName = '',
    this.nextNeed = 0,
  });

  factory FishLevel.fromJson(Map<String, dynamic> j) => FishLevel(
        level: (j['level'] as num?)?.toInt() ?? 0,
        name: (j['name'] ?? '临渊羡鱼').toString(),
        nextName: (j['nextName'] ?? '').toString(),
        nextNeed: (j['nextNeed'] as num?)?.toInt() ?? 0,
      );
}

/// 图鉴总览
class FishGuide {
  final FishLevel level;
  final int unlockedCount;
  final int totalCount;
  final List<FishSpecies> fresh;
  final List<FishSpecies> salt;

  const FishGuide({
    required this.level,
    this.unlockedCount = 0,
    this.totalCount = 0,
    this.fresh = const [],
    this.salt = const [],
  });

  factory FishGuide.fromJson(Map<String, dynamic> j) {
    final fresh = (j['fresh'] as List?) ?? const [];
    final salt = (j['salt'] as List?) ?? const [];
    return FishGuide(
      level: FishLevel.fromJson(
          (j['level'] as Map?)?.cast<String, dynamic>() ?? const {}),
      unlockedCount: (j['unlockedCount'] as num?)?.toInt() ?? 0,
      totalCount: (j['totalCount'] as num?)?.toInt() ?? 0,
      fresh: fresh
          .map((f) => FishSpecies.fromJson((f as Map).cast<String, dynamic>()))
          .toList(),
      salt: salt
          .map((f) => FishSpecies.fromJson((f as Map).cast<String, dynamic>()))
          .toList(),
    );
  }
}

/// AI 识别结果中的候选鱼种
class FishMatch {
  final String id;
  final String name;
  final String waterType;
  final String rarity;

  const FishMatch({
    required this.id,
    this.name = '',
    this.waterType = 'fresh',
    this.rarity = 'common',
  });

  factory FishMatch.fromJson(Map<String, dynamic> j) => FishMatch(
        id: (j['id'] ?? '').toString(),
        name: (j['name'] ?? '').toString(),
        waterType: (j['waterType'] ?? 'fresh').toString(),
        rarity: (j['rarity'] ?? 'common').toString(),
      );
}

/// AI 识别结果
class FishRecognize {
  final bool ok;
  final bool needManual;
  /// 照片里是否有鱼：true=有鱼 / false=无鱼(应拒绝发布) / null=AI 未配置(走人工确认)
  final bool? hasFish;
  final List<String> names;
  final List<FishMatch> matched;
  final String msg;
  /// AI 估算的体长(cm) / 重量(g)，null=未返回
  final double? lengthCm;
  final double? weightG;
  final double? confidence;

  const FishRecognize({
    this.ok = false,
    this.needManual = true,
    this.hasFish,
    this.names = const [],
    this.matched = const [],
    this.msg = '',
    this.lengthCm,
    this.weightG,
    this.confidence,
  });

  factory FishRecognize.fromJson(Map<String, dynamic> j) {
    final names = (j['names'] as List?) ?? const [];
    final matched = (j['matched'] as List?) ?? const [];
    final hf = j['hasFish'];
    return FishRecognize(
      ok: (j['ok'] as bool?) ?? false,
      needManual: (j['needManual'] as bool?) ?? true,
      hasFish: hf is bool ? hf : null,
      names: names.map((e) => e.toString()).toList(),
      matched: matched
          .map((e) => FishMatch.fromJson((e as Map).cast<String, dynamic>()))
          .toList(),
      msg: (j['msg'] ?? '').toString(),
      lengthCm: (j['lengthCm'] as num?)?.toDouble(),
      weightG: (j['weightG'] as num?)?.toDouble(),
      confidence: (j['confidence'] as num?)?.toDouble(),
    );
  }
}

/// AI 大模型鱼口判断结果（/fish/bite-ai）
class AiBite {
  final bool ok;
  final String msg;
  final int? score;
  final String grade;
  final String summary;
  final List<String> positives;
  final List<String> negatives;
  final String advice;
  final String model;

  const AiBite({
    this.ok = false,
    this.msg = '',
    this.score,
    this.grade = '',
    this.summary = '',
    this.positives = const [],
    this.negatives = const [],
    this.advice = '',
    this.model = '',
  });

  factory AiBite.fromJson(Map<String, dynamic> j) => AiBite(
        ok: (j['ok'] as bool?) ?? false,
        msg: (j['msg'] ?? '').toString(),
        score: (j['score'] as num?)?.round(),
        grade: (j['grade'] ?? '').toString(),
        summary: (j['summary'] ?? '').toString(),
        positives: ((j['positives'] as List?) ?? const [])
            .map((e) => e.toString())
            .toList(),
        negatives: ((j['negatives'] as List?) ?? const [])
            .map((e) => e.toString())
            .toList(),
        advice: (j['advice'] ?? '').toString(),
        model: (j['model'] ?? '').toString(),
      );
}
