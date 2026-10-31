import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../models/user_address.dart';
import '../services/settings_service.dart';
import '../widgets/app_refresh.dart';
import '../widgets/center_toast.dart';

/// 收货地址管理（设置 - 收货地址）
///
/// 后端 user_addresses 表：增删改 + 默认地址（同账号下默认地址只会有一个）。
class AddressListScreen extends StatefulWidget {
  const AddressListScreen({super.key});

  @override
  State<AddressListScreen> createState() => _AddressListScreenState();
}

class _AddressListScreenState extends State<AddressListScreen> {
  List<UserAddress> _list = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    // 已有数据时刷新不清空，避免整块消失闪白
    setState(() => _loading = _list.isEmpty);
    try {
      final list = await SettingsService.addresses();
      if (mounted) setState(() => _list = list);
    } catch (e) {
      if (mounted) CenterToast.show(context, '加载失败：$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _edit([UserAddress? a]) async {
    final result = await showModalBottomSheet<List<UserAddress>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppTheme.radiusLg)),
      ),
      builder: (_) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: _AddressEditor(existing: a),
      ),
    );
    if (result != null && mounted) setState(() => _list = result);
  }

  Future<void> _setDefault(UserAddress a) async {
    try {
      final list = await SettingsService.setDefaultAddress(a.id);
      if (mounted) setState(() => _list = list);
    } catch (e) {
      if (mounted) CenterToast.show(context, '设置失败：$e');
    }
  }

  Future<void> _delete(UserAddress a) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除地址'),
        content: Text('确定删除「${a.name} ${a.maskedPhone}」这条收货地址吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除', style: TextStyle(color: AppTheme.danger)),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      final list = await SettingsService.deleteAddress(a.id);
      if (mounted) {
        setState(() => _list = list);
        CenterToast.show(context, '已删除');
      }
    } catch (e) {
      if (mounted) CenterToast.show(context, '删除失败：$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('收货地址'),
        elevation: 0,
        actions: [
          TextButton(
            onPressed: () => _edit(),
            child: const Text('新增',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
      body: AppRefresh(
        onRefresh: _load,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _list.isEmpty
                ? _empty()
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
                    itemCount: _list.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (_, i) => _card(_list[i]),
                  ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
          child: SizedBox(
            height: 46,
            child: ElevatedButton.icon(
              onPressed: () => _edit(),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('新增收货地址'),
            ),
          ),
        ),
      ),
    );
  }

  Widget _empty() => ListView(
        children: const [
          SizedBox(height: 120),
          Icon(Icons.location_off_outlined, size: 54, color: AppTheme.textTertiary),
          SizedBox(height: 12),
          Center(
            child: Text('还没有收货地址',
                style: TextStyle(fontSize: 14, color: AppTheme.textSecondary)),
          ),
          SizedBox(height: 6),
          Center(
            child: Text('添加后商城下单可直接使用',
                style: TextStyle(fontSize: 12, color: AppTheme.textTertiary)),
          ),
        ],
      );

  Widget _card(UserAddress a) => Container(
        padding: const EdgeInsets.fromLTRB(13, 12, 8, 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(AppTheme.radiusMd),
          border: Border.all(color: AppTheme.divider),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(a.name,
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w700)),
                const SizedBox(width: 8),
                Text(a.maskedPhone,
                    style: const TextStyle(
                        fontSize: 13, color: AppTheme.textSecondary)),
                if (a.isDefault) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppTheme.accentLight,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: AppTheme.accentMid.withOpacity(.5)),
                    ),
                    child: const Text('默认',
                        style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.accentDark)),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 6),
            Text(a.fullAddress,
                style: const TextStyle(
                    fontSize: 13, height: 1.5, color: AppTheme.textSecondary)),
            const SizedBox(height: 4),
            Row(
              children: [
                if (!a.isDefault)
                  TextButton(
                    onPressed: () => _setDefault(a),
                    style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        minimumSize: const Size(0, 32)),
                    child: const Text('设为默认', style: TextStyle(fontSize: 12.5)),
                  ),
                const Spacer(),
                TextButton(
                  onPressed: () => _edit(a),
                  style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      minimumSize: const Size(0, 32)),
                  child: const Text('编辑', style: TextStyle(fontSize: 12.5)),
                ),
                TextButton(
                  onPressed: () => _delete(a),
                  style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      minimumSize: const Size(0, 32)),
                  child: const Text('删除',
                      style: TextStyle(fontSize: 12.5, color: AppTheme.danger)),
                ),
              ],
            ),
          ],
        ),
      );
}

/// 新增 / 编辑收货地址
class _AddressEditor extends StatefulWidget {
  const _AddressEditor({this.existing});
  final UserAddress? existing;

  @override
  State<_AddressEditor> createState() => _AddressEditorState();
}

class _AddressEditorState extends State<_AddressEditor> {
  late final TextEditingController _name =
      TextEditingController(text: widget.existing?.name ?? '');
  late final TextEditingController _phone =
      TextEditingController(text: widget.existing?.phone ?? '');
  late final TextEditingController _region =
      TextEditingController(text: widget.existing?.region ?? '');
  late final TextEditingController _detail =
      TextEditingController(text: widget.existing?.detail ?? '');
  late bool _isDefault = widget.existing?.isDefault ?? false;
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _region.dispose();
    _detail.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    if (_name.text.trim().isEmpty) {
      CenterToast.show(context, '请填写收货人');
      return;
    }
    if (_phone.text.trim().length < 6) {
      CenterToast.show(context, '请填写正确的联系电话');
      return;
    }
    if (_detail.text.trim().isEmpty) {
      CenterToast.show(context, '请填写详细地址');
      return;
    }
    setState(() => _saving = true);
    try {
      final list = await SettingsService.saveAddress(
        id: widget.existing?.id,
        name: _name.text.trim(),
        phone: _phone.text.trim(),
        region: _region.text.trim(),
        detail: _detail.text.trim(),
        isDefault: _isDefault,
      );
      if (mounted) Navigator.pop(context, list);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        CenterToast.show(context, '保存失败：$e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.existing == null ? '新增收货地址' : '编辑收货地址',
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 14),
            _field(_name, '收货人', hint: '请填写收货人姓名'),
            const SizedBox(height: 10),
            _field(_phone, '联系电话',
                hint: '请填写手机号', keyboard: TextInputType.phone),
            const SizedBox(height: 10),
            _field(_region, '所在地区', hint: '省 / 市 / 区（选填）'),
            const SizedBox(height: 10),
            _field(_detail, '详细地址', hint: '街道、门牌号、楼栋单元', maxLines: 2),
            const SizedBox(height: 6),
            Row(
              children: [
                const Expanded(
                  child: Text('设为默认地址',
                      style: TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w600)),
                ),
                Switch(
                  value: _isDefault,
                  onChanged: (v) => setState(() => _isDefault = v),
                  activeTrackColor: AppTheme.primary,
                  activeColor: AppTheme.accent,
                ),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              height: 46,
              child: ElevatedButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('保存'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _field(TextEditingController c, String label,
      {String? hint, TextInputType? keyboard, int maxLines = 1}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(fontSize: 12.5, color: AppTheme.textSecondary)),
        const SizedBox(height: 4),
        TextField(
          controller: c,
          keyboardType: keyboard,
          maxLines: maxLines,
          style: const TextStyle(fontSize: 14),
          decoration: InputDecoration(
            hintText: hint,
            isDense: true,
            filled: true,
            fillColor: AppTheme.primarySoft,
            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: AppTheme.border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: AppTheme.border),
            ),
          ),
        ),
      ],
    );
  }
}
