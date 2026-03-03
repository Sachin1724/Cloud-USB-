import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class RecentScreen extends StatefulWidget {
  const RecentScreen({super.key});

  @override
  State<RecentScreen> createState() => _RecentScreenState();
}

class _RecentScreenState extends State<RecentScreen> {
  List<String> _recentPaths = [];

  @override
  void initState() {
    super.initState();
    _loadRecents();
  }

  Future<void> _loadRecents() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() => _recentPaths = prefs.getStringList('drivenet_recents') ?? []);
  }

  Future<void> _clearRecents() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('drivenet_recents');
    setState(() => _recentPaths = []);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent, elevation: 0, automaticallyImplyLeading: false,
        title: const Text('Recent', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          if (_recentPaths.isNotEmpty)
            TextButton(onPressed: _clearRecents, child: const Text('Clear', style: TextStyle(color: Colors.grey))),
        ],
      ),
      body: _recentPaths.isEmpty
          ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.access_time, size: 64, color: Theme.of(context).disabledColor.withValues(alpha: 0.2)),
              const SizedBox(height: 16),
              Text('No recent files', style: TextStyle(color: Theme.of(context).disabledColor)),
            ]))
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: _recentPaths.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, i) {
                final path = _recentPaths[i];
                final parts = path.split('\\');
                final name = parts.isNotEmpty ? parts.last : path;
                return ListTile(
                  leading: Container(
                    width: 40, height: 40,
                    decoration: BoxDecoration(color: const Color(0xFFFF4655).withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                    child: const Icon(Icons.history, color: Color(0xFFFF4655)),
                  ),
                  title: Text(name.isEmpty ? path : name, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(path, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, color: Colors.grey)),
                  trailing: IconButton(
                    icon: const Icon(Icons.close, size: 16, color: Colors.grey),
                    onPressed: () async {
                      final prefs = await SharedPreferences.getInstance();
                      _recentPaths.remove(path);
                      await prefs.setStringList('drivenet_recents', _recentPaths);
                      setState(() {});
                    },
                  ),
                );
              },
            ),
    );
  }
}
