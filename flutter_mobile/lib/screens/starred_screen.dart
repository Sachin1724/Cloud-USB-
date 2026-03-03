import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class StarredScreen extends StatefulWidget {
  const StarredScreen({super.key});

  @override
  State<StarredScreen> createState() => _StarredScreenState();
}

class _StarredScreenState extends State<StarredScreen> {
  List<String> _starred = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() => _starred = prefs.getStringList('drivenet_starred') ?? []);
  }

  Future<void> _unstar(String path) async {
    final prefs = await SharedPreferences.getInstance();
    _starred.remove(path);
    await prefs.setStringList('drivenet_starred', _starred);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent, elevation: 0, automaticallyImplyLeading: false,
        title: const Text('Starred', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: _starred.isEmpty
          ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.star_border, size: 64, color: Theme.of(context).disabledColor.withValues(alpha: 0.2)),
              const SizedBox(height: 16),
              Text('No starred files', style: TextStyle(color: Theme.of(context).disabledColor)),
              const SizedBox(height: 8),
              const Text('Long-press any file and tap ★ to star it', style: TextStyle(color: Colors.grey, fontSize: 13)),
            ]))
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: _starred.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, i) {
                final path = _starred[i];
                final parts = path.split('\\');
                final name = parts.isNotEmpty ? parts.last : path;
                return ListTile(
                  leading: Container(
                    width: 40, height: 40,
                    decoration: BoxDecoration(color: Colors.amber.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                    child: const Icon(Icons.star, color: Colors.amber),
                  ),
                  title: Text(name.isEmpty ? path : name, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(path, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, color: Colors.grey)),
                  trailing: IconButton(
                    icon: const Icon(Icons.star, color: Colors.amber, size: 20),
                    onPressed: () => _unstar(path),
                    tooltip: 'Remove from starred',
                  ),
                );
              },
            ),
    );
  }
}
