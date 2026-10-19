import 'package:flutter/material.dart';

/// 搜索页（V1 演示：输入关键词后在本地动态里做标题模糊匹配）
/// 真实项目可接入 Supabase 的全文检索或 ElasticSearch
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _ctrl = TextEditingController();
  List<String> _history = ['千岛湖', '路亚', '暴雨钓鱼'];
  List<String> _results = [];

  void _search(String q) {
    if (q.isEmpty) return;
    setState(() {
      _results = List.generate(
        3,
        (i) => '「$q」相关结果 ${i + 1}：附近钓点 / 钓友 / 渔获',
      );
      if (!_history.contains(q)) _history.insert(0, q);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _ctrl,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: '搜索钓点 / 钓友 / 渔获',
            border: InputBorder.none,
          ),
          onSubmitted: _search,
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('历史搜索', style: TextStyle(color: Colors.grey)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: _history
                .map((h) => ActionChip(
                      label: Text(h),
                      onPressed: () {
                        _ctrl.text = h;
                        _search(h);
                      },
                    ))
                .toList(),
          ),
          const SizedBox(height: 20),
          if (_results.isNotEmpty) ...[
            const Text('搜索结果', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            ..._results.map((r) => ListTile(
                  leading: const Icon(Icons.search),
                  title: Text(r),
                )),
          ],
        ],
      ),
    );
  }
}
