import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_theme.dart';
import '../services/api_config.dart';
import '../services/content_service.dart';
import '../services/session_provider.dart';
import '../widgets/center_toast.dart';
import '../widgets/emoji_panel.dart';
import 'auth_screen.dart';

const List<String> _weekCn = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];

String _twoPad(int v) => v.toString().padLeft(2, '0');

/// 「10月25日 周六 14:00」
String _humanText(DateTime d) =>
    '${d.month}月${d.day}日 ${_weekCn[(d.weekday - 1).clamp(0, 6)]} '
    '${_twoPad(d.hour)}:${_twoPad(d.minute)}';

/// 发布活动
///
/// 提交后进「待审核」，后台通过才会出现在活动列表里。
/// 时间用自绘滚轮选择器（App 没接 flutter_localizations，
/// 系统 DatePicker 会显示英文月份，这里自己做一个中文的）。
class PublishActivityScreen extends StatefulWidget {
  const PublishActivityScreen({super.key});

  @override
  State<PublishActivityScreen> createState() => _PublishActivityScreenState();
}

class _PublishActivityScreenState extends State<PublishActivityScreen> {
  final _title = TextEditingController();
  final _location = TextEditingController();
  final _fee = TextEditingController();
  final _maxJoin = TextEditingController();
  final _contact = TextEditingController();
  final _cover = TextEditingController();
  final _summary = TextEditingController();
  final _body = TextEditingController();

  DateTime? _start;
  DateTime? _end;
  bool _busy = false;

  @override
  void dispose() {
    for (final c in [
      _title,
      _location,
      _fee,
      _maxJoin,
      _contact,
      _cover,
      _summary,
      _body,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  static String _two(int v) => v.toString().padLeft(2, '0');

  /// 传给后端的时间串：2026-10-25 14:00:00
  static String _wire(DateTime d) =>
      '${d.year}-${_two(d.month)}-${_two(d.day)} '
      '${_two(d.hour)}:${_two(d.minute)}:00';

  static String _human(DateTime d) => _humanText(d);

  Future<void> _submit() async {
    final title = _title.text.trim();
    if (title.isEmpty) {
      CenterToast.show(context, '请先填写活动标题');
      return;
    }
    if (_start == null) {
      CenterToast.show(context, '请选择活动开始时间');
      return;
    }
    if (_end != null && _end!.isBefore(_start!)) {
      CenterToast.show(context, '结束时间不能早于开始时间');
      return;
    }
    final sp = Provider.of<SessionProvider>(context, listen: false);
    if (ApiConfig.enabled && !sp.isLoggedIn) {
      CenterToast.show(context, '请先登录后再发布', icon: Icons.lock_outline);
      await Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => const AuthScreen()));
      return;
    }

    setState(() => _busy = true);
    final r = await ContentService.submitActivity(
      title: title,
      startAt: _wire(_start!),
      endAt: _end == null ? '' : _wire(_end!),
      location: _location.text.trim(),
      fee: _fee.text.trim(),
      maxJoin: int.tryParse(_maxJoin.text.trim()) ?? 0,
      contact: _contact.text.trim(),
      cover: _cover.text.trim(),
      summary: _summary.text.trim(),
      content: _body.text.trim(),
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (r.ok) {
      Navigator.of(context).pop(true);
    } else {
      CenterToast.show(context, r.msg);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(title: const Text('发布活动')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 30),
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: AppTheme.warningLight,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Row(
              children: [
                Icon(Icons.info_outline, size: 15, color: AppTheme.warning),
                SizedBox(width: 7),
                Expanded(
                  child: Text('提交后需要后台审核，通过后才会出现在活动列表里',
                      style: TextStyle(
                          fontSize: 12,
                          color: AppTheme.warning,
                          height: 1.4)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          _label('活动标题'),
          _field(_title, hint: '例如：周末城郊水库野钓局', maxLength: 40),
          const SizedBox(height: 14),

          _label('开始时间', sub: '必填'),
          _timeRow(
            value: _start == null ? '选择开始时间' : _human(_start!),
            filled: _start != null,
            onTap: () async {
              final d = await _pickDateTime(_start ?? _defaultStart());
              if (d != null) setState(() => _start = d);
            },
            onClear: _start == null ? null : () => setState(() => _start = null),
          ),
          const SizedBox(height: 14),

          _label('结束时间', sub: '选填'),
          _timeRow(
            value: _end == null ? '选择结束时间' : _human(_end!),
            filled: _end != null,
            onTap: () async {
              final d = await _pickDateTime(_end ?? (_start ?? _defaultStart()));
              if (d != null) setState(() => _end = d);
            },
            onClear: _end == null ? null : () => setState(() => _end = null),
          ),
          const SizedBox(height: 14),

          _label('集合地点'),
          _field(_location, hint: '例如：XX 水库南岸停车场', maxLength: 60),
          const SizedBox(height: 14),

          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _label('费用'),
                    _field(_fee, hint: '免费 / AA / 50元', maxLength: 20),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _label('名额', sub: '0 为不限'),
                    _field(_maxJoin,
                        hint: '0', maxLength: 4, number: true),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          _label('联系方式'),
          _field(_contact, hint: '微信 / 手机号，仅报名者可见', maxLength: 40),
          const SizedBox(height: 14),

          _label('封面图片地址', sub: '选填'),
          _field(_cover, hint: 'https://…', maxLength: 200),
          const SizedBox(height: 14),

          _label('一句话介绍', sub: '选填，留空会自动截取正文'),
          _field(_summary, hint: '这场活动玩什么、适合谁', maxLength: 60,
              emoji: true),
          const SizedBox(height: 14),

          _label('详细说明'),
          _field(_body,
              hint: '行程安排、装备要求、注意事项…（空行分段）',
              maxLines: 10,
              maxLength: 2000,
              emoji: true),
          const SizedBox(height: 22),

          SizedBox(
            height: 46,
            child: ElevatedButton(
              onPressed: _busy ? null : _submit,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                foregroundColor: Colors.white,
                disabledBackgroundColor: AppTheme.primary.withOpacity(0.5),
                elevation: 0,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(13)),
              ),
              child: _busy
                  ? const SizedBox(
                      width: 19,
                      height: 19,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('提交审核',
                      style: TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
    );
  }

  /// 默认开始时间：明天上午 9 点
  DateTime _defaultStart() {
    final n = DateTime.now().add(const Duration(days: 1));
    return DateTime(n.year, n.month, n.day, 9);
  }

  // ------------------------------------------------------------ 时间选择器

  Future<DateTime?> _pickDateTime(DateTime init) {
    return showModalBottomSheet<DateTime>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _DateTimeWheelSheet(initial: init),
    );
  }


  // ------------------------------------------------------------ 基础控件

  Widget _timeRow({
    required String value,
    required bool filled,
    required VoidCallback onTap,
    VoidCallback? onClear,
  }) {
    return Material(
      color: AppTheme.surface,
      borderRadius: BorderRadius.circular(AppTheme.radiusMd),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppTheme.radiusMd),
            border: Border.all(color: AppTheme.border),
          ),
          child: Row(
            children: [
              Icon(Icons.schedule,
                  size: 16,
                  color: filled ? AppTheme.primary : AppTheme.textSecondary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(value,
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight:
                            filled ? FontWeight.w600 : FontWeight.w400,
                        color: filled
                            ? AppTheme.textPrimary
                            : AppTheme.textSecondary)),
              ),
              if (onClear != null)
                GestureDetector(
                  onTap: onClear,
                  child: const Padding(
                    padding: EdgeInsets.only(left: 6),
                    child: Icon(Icons.close,
                        size: 16, color: AppTheme.textSecondary),
                  ),
                )
              else
                const Icon(Icons.chevron_right,
                    size: 18, color: AppTheme.textSecondary),
            ],
          ),
        ),
      ),
    );
  }

  Widget _label(String t, {String? sub}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6, left: 2),
      child: Row(
        children: [
          Text(t,
              style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textPrimary)),
          if (sub != null) ...[
            const SizedBox(width: 6),
            Text(sub,
                style: const TextStyle(
                    fontSize: 11, color: AppTheme.textSecondary)),
          ],
        ],
      ),
    );
  }

  Widget _field(
    TextEditingController c, {
    String? hint,
    int maxLength = 200,
    int maxLines = 1,
    bool number = false,
    bool emoji = false,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        border: Border.all(color: AppTheme.border),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: TextField(
        controller: c,
        maxLines: maxLines,
        maxLength: maxLength,
        keyboardType: number ? TextInputType.number : null,
        style: const TextStyle(fontSize: 14, height: 1.6),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle:
              const TextStyle(fontSize: 13, color: AppTheme.textSecondary),
          border: InputBorder.none,
          counterText: '',
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(vertical: 10),
          suffixIcon: emoji
              ? IconButton(
                  icon: const Icon(Icons.emoji_emotions_outlined,
                      size: 20, color: AppTheme.textSecondary),
                  tooltip: '表情',
                  onPressed: () => showEmojiSheet(context, c),
                )
              : null,
        ),
      ),
    );
  }
}

/// 中文时间滚轮（月 / 日 / 时 / 分）
///
/// 独立成 StatefulWidget，四个 FixedExtentScrollController 只建一次，
/// 避免放在 builder 里每次重建都把滚轮位置重置回初始值。
/// 年份自动推断：选出来的时间已经过去，就按明年算。
class _DateTimeWheelSheet extends StatefulWidget {
  final DateTime initial;
  const _DateTimeWheelSheet({required this.initial});

  @override
  State<_DateTimeWheelSheet> createState() => _DateTimeWheelSheetState();
}

class _DateTimeWheelSheetState extends State<_DateTimeWheelSheet> {
  final DateTime _now = DateTime.now();

  late int _month;
  late int _day;
  late int _hour;
  late int _minute;

  late final FixedExtentScrollController _mCtrl;
  late final FixedExtentScrollController _dCtrl;
  late final FixedExtentScrollController _hCtrl;
  late final FixedExtentScrollController _minCtrl;

  @override
  void initState() {
    super.initState();
    _month = widget.initial.month;
    _day = widget.initial.day.clamp(1, _daysIn(_month));
    _hour = widget.initial.hour;
    _minute = (widget.initial.minute ~/ 5) * 5;
    _mCtrl = FixedExtentScrollController(initialItem: _month - 1);
    _dCtrl = FixedExtentScrollController(initialItem: _day - 1);
    _hCtrl = FixedExtentScrollController(initialItem: _hour);
    _minCtrl = FixedExtentScrollController(initialItem: _minute ~/ 5);
  }

  @override
  void dispose() {
    _mCtrl.dispose();
    _dCtrl.dispose();
    _hCtrl.dispose();
    _minCtrl.dispose();
    super.dispose();
  }

  int _daysIn(int m) => DateTime(_now.year, m + 1, 0).day;

  /// 结算最终时间（含年份推断）
  DateTime get _resolved {
    final d = _day.clamp(1, _daysIn(_month));
    final guess = DateTime(_now.year, _month, d, _hour, _minute);
    if (!guess.isBefore(_now)) return guess;
    return DateTime(_now.year + 1, _month, d, _hour, _minute);
  }

  void _onMonth(int i) {
    setState(() {
      _month = i + 1;
      final max = _daysIn(_month);
      if (_day > max) _day = max;
    });
    // 天数变少时把日滚轮同步过来（不能在 build 里直接 jump）
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_dCtrl.hasClients && _dCtrl.selectedItem != _day - 1) {
        _dCtrl.jumpToItem(_day - 1);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final preview = _resolved;
    return Container(
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 4, 6, 2),
              child: Row(
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('取消',
                        style: TextStyle(
                            fontSize: 13.5, color: AppTheme.textSecondary)),
                  ),
                  Expanded(
                    child: Text('${preview.year}年 · ${_humanText(preview)}',
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.textPrimary)),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(preview),
                    child: const Text('确定',
                        style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.primary)),
                  ),
                ],
              ),
            ),
            const Divider(color: AppTheme.divider, height: 1),
            SizedBox(
              height: 188,
              child: Stack(
                children: [
                  // 中间选中高亮带
                  Center(
                    child: Container(
                      height: 36,
                      margin: const EdgeInsets.symmetric(horizontal: 14),
                      decoration: BoxDecoration(
                        color: AppTheme.primarySoft,
                        borderRadius: BorderRadius.circular(9),
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      _wheel(
                        items: List.generate(12, (i) => '${i + 1}月'),
                        selected: _month - 1,
                        ctrl: _mCtrl,
                        onChanged: _onMonth,
                      ),
                      _wheel(
                        items: List.generate(_daysIn(_month), (i) => '${i + 1}日'),
                        selected: _day - 1,
                        ctrl: _dCtrl,
                        onChanged: (i) => setState(() => _day = i + 1),
                      ),
                      _wheel(
                        items: List.generate(24, (i) => '${_twoPad(i)}时'),
                        selected: _hour,
                        ctrl: _hCtrl,
                        onChanged: (i) => setState(() => _hour = i),
                      ),
                      _wheel(
                        items: List.generate(12, (i) => '${_twoPad(i * 5)}分'),
                        selected: _minute ~/ 5,
                        ctrl: _minCtrl,
                        onChanged: (i) => setState(() => _minute = i * 5),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
          ],
        ),
      ),
    );
  }

  Widget _wheel({
    required List<String> items,
    required int selected,
    required FixedExtentScrollController ctrl,
    required ValueChanged<int> onChanged,
  }) {
    return Expanded(
      child: ListWheelScrollView.useDelegate(
        itemExtent: 36,
        diameterRatio: 1.7,
        perspective: 0.004,
        physics: const FixedExtentScrollPhysics(),
        controller: ctrl,
        onSelectedItemChanged: onChanged,
        childDelegate: ListWheelChildBuilderDelegate(
          childCount: items.length,
          builder: (_, i) => Center(
            child: Text(
              items[i],
              style: TextStyle(
                fontSize: i == selected ? 16 : 15,
                fontWeight: i == selected ? FontWeight.w700 : FontWeight.w500,
                color: i == selected
                    ? AppTheme.textPrimary
                    : AppTheme.textSecondary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
