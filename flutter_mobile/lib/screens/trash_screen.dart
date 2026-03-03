import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../config.dart';

class TrashScreen extends StatefulWidget {
  const TrashScreen({super.key});

  @override
  State<TrashScreen> createState() => _TrashScreenState();
}

class _TrashScreenState extends State<TrashScreen> {
  List<Map<String, dynamic>> _items = [];
  bool _isLoading = true;
  String _error = '';
  String? _selectedDrive;

  @override
  void initState() {
    super.initState();
    _loadDriveAndFetch();
  }

  Future<void> _loadDriveAndFetch() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('drivenet_jwt');
    if (token == null) return;
    try {
      final info = await http.get(Uri.parse('${AppConfig.brokerUrl}/api/fs/me/agent'), headers: {'Authorization': 'Bearer $token'});
      if (info.statusCode == 200) {
        final data = jsonDecode(info.body);
        _selectedDrive = data['drive'] as String?;
      }
    } catch (_) {}
    await _fetchTrash();
  }

  Future<void> _fetchTrash() async {
    setState(() { _isLoading = true; _error = ''; });
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('drivenet_jwt');
      final driveParam = _selectedDrive != null ? '?drive=${Uri.encodeComponent(_selectedDrive!)}' : '';
      final response = await http.get(
        Uri.parse('${AppConfig.brokerUrl}/api/fs/trash/list$driveParam'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() => _items = List<Map<String, dynamic>>.from(data['items'] ?? []));
      } else {
        setState(() => _error = jsonDecode(response.body)['error'] ?? 'Failed to load trash');
      }
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _restore(Map<String, dynamic> item) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('drivenet_jwt');
      final response = await http.post(
        Uri.parse('${AppConfig.brokerUrl}/api/fs/restore'),
        headers: {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'},
        body: jsonEncode({'path': item['trashPath'], 'drive': _selectedDrive ?? ''}),
      );
      if (response.statusCode == 200) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Restored: ${item['name']}')));
        _fetchTrash();
      } else {
        throw Exception(jsonDecode(response.body)['error'] ?? 'Failed');
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  Future<void> _purge(Map<String, dynamic> item) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Forever?'),
        content: Text('"${item['name']}" will be permanently deleted and cannot be recovered.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete Forever', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('drivenet_jwt');
      final driveParam = _selectedDrive != null ? '&drive=${Uri.encodeComponent(_selectedDrive!)}' : '';
      final response = await http.delete(
        Uri.parse('${AppConfig.brokerUrl}/api/fs/trash/purge?path=${Uri.encodeComponent(item['trashPath'])}$driveParam'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (response.statusCode == 200) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Permanently deleted: ${item['name']}')));
        _fetchTrash();
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  String _formatSize(int bytes) {
    if (bytes <= 0) return '0 B';
    const s = ['B', 'KB', 'MB', 'GB'];
    int i = 0; double v = bytes.toDouble();
    while (v >= 1024 && i < s.length - 1) { v /= 1024; i++; }
    return '${v.toStringAsFixed(1)} ${s[i]}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent, elevation: 0, automaticallyImplyLeading: false,
        title: const Text('Trash', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _fetchTrash),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFFFF4655)))
          : _error.isNotEmpty
              ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  const Icon(Icons.error_outline, color: Color(0xFFFF4655), size: 48),
                  const SizedBox(height: 16),
                  Text(_error, textAlign: TextAlign.center),
                  const SizedBox(height: 16),
                  ElevatedButton(onPressed: _fetchTrash, style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFF4655)),
                    child: const Text('Retry', style: TextStyle(color: Colors.white))),
                ]))
              : _items.isEmpty
                  ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Icon(Icons.delete_outline, size: 64, color: Theme.of(context).disabledColor.withValues(alpha: 0.2)),
                      const SizedBox(height: 16),
                      Text('Trash is empty', style: TextStyle(color: Theme.of(context).disabledColor)),
                    ]))
                  : Column(children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        child: Row(children: [
                          const Icon(Icons.info_outline, size: 14, color: Colors.grey),
                          const SizedBox(width: 8),
                          Expanded(child: Text('${_items.length} item(s) in trash. Stored in .drivenet_trash on your PC.', style: const TextStyle(fontSize: 12, color: Colors.grey))),
                        ]),
                      ),
                      Expanded(
                        child: ListView.separated(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: _items.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (_, i) {
                            final item = _items[i];
                            return ListTile(
                              leading: Container(
                                width: 40, height: 40,
                                decoration: BoxDecoration(color: Colors.red.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                                child: Icon(item['is_dir'] == true ? Icons.folder : Icons.insert_drive_file, color: Colors.redAccent),
                              ),
                              title: Text(item['name'] ?? 'Unknown', maxLines: 1, overflow: TextOverflow.ellipsis),
                              subtitle: Text(item['is_dir'] == true ? 'Folder' : _formatSize(item['size'] ?? 0), style: const TextStyle(fontSize: 12, color: Colors.grey)),
                              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                                IconButton(
                                  icon: const Icon(Icons.restore, color: Colors.green, size: 20),
                                  tooltip: 'Restore',
                                  onPressed: () => _restore(item),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete_forever, color: Colors.redAccent, size: 20),
                                  tooltip: 'Delete Forever',
                                  onPressed: () => _purge(item),
                                ),
                              ]),
                            );
                          },
                        ),
                      ),
                    ]),
    );
  }
}
