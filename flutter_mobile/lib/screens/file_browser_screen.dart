import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';
import 'package:share_plus/share_plus.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter/services.dart';
import '../config.dart';
import 'file_preview_screen.dart';

enum _ViewMode { list, grid }
enum _SortBy { nameAsc, nameDesc, dateNew, dateOld, sizeBig, sizeSmall }

class FileBrowserScreen extends StatefulWidget {
  const FileBrowserScreen({super.key});

  @override
  State<FileBrowserScreen> createState() => _FileBrowserScreenState();
}

class _FileBrowserScreenState extends State<FileBrowserScreen>
    with WidgetsBindingObserver {
  final String _brokerUrl = AppConfig.brokerUrl;
  String _currentPath = '\\';
  List<Map<String, dynamic>> _items = [];
  bool _isLoading = false;
  bool _isAgentOnline = false;
  String _error = '';
  final Map<String, double> _uploadProgress = {};
  String? _selectedDrive;
  _ViewMode _viewMode = _ViewMode.list;
  _SortBy _sortBy = _SortBy.nameAsc;
  bool _isSearching = false;
  final TextEditingController _searchController = TextEditingController();
  List<Map<String, dynamic>> _searchResults = [];
  bool _isSearchLoading = false;
  Set<String> _starredPaths = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializePath();
    _loadStarred();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _searchController.dispose();
    super.dispose();
  }

  // Re-fetch drive info when app resumes (e.g., after user changes drive in Windows agent)
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _fetchDrives();
    }
  }

  Future<void> _loadStarred() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList('drivenet_starred') ?? [];
    setState(() => _starredPaths = Set.from(list));
  }

  Future<void> _toggleStar(Map<String, dynamic> item) async {
    final name = item['name'] as String;
    final path = _currentPath == '\\' ? name : '$_currentPath\\$name';
    final prefs = await SharedPreferences.getInstance();
    final set = Set<String>.from(_starredPaths);
    if (set.contains(path)) {
      set.remove(path);
    } else {
      set.add(path);
    }
    await prefs.setStringList('drivenet_starred', set.toList());
    setState(() => _starredPaths = set);
  }

  Future<void> _initializePath() async {
    await _fetchDrives();
  }

  Future<void> _fetchDrives() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('drivenet_jwt');
      if (token == null) return;

      final url = Uri.parse('$_brokerUrl/api/fs/me/agent');
      final response = await http.get(url, headers: {'Authorization': 'Bearer $token'});

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final isOnline = data['online'] ?? false;
        final activeDrive = data['drive'] as String?;

        setState(() {
          _isAgentOnline = isOnline;
          if (activeDrive != null && activeDrive.isNotEmpty) {
            _selectedDrive = activeDrive;
            _currentPath = activeDrive.endsWith('\\') ? activeDrive : '$activeDrive\\';
          }
        });
        _fetchFiles();
      }
    } catch (e) {
      debugPrint('Error fetching drives: $e');
    }
  }

  Future<void> _fetchFiles() async {
    setState(() {
      _isLoading = true;
      _error = '';
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('drivenet_jwt');
      if (token == null) throw Exception('Not authenticated');

      final driveParam = _selectedDrive != null ? '&drive=${Uri.encodeComponent(_selectedDrive!)}' : '';
      final url = Uri.parse('$_brokerUrl/api/fs/list?path=${Uri.encodeComponent(_currentPath)}$driveParam');
      final response = await http.get(url, headers: {'Authorization': 'Bearer $token'});

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          _items = List<Map<String, dynamic>>.from(data['items'] ?? []);
          if (data['current_path'] != null && _currentPath == '\\') {
            _currentPath = data['current_path'];
          }
        });
        // Save to recents
        _addToRecent(_currentPath);
      } else {
        throw Exception(jsonDecode(response.body)['error'] ?? 'Failed to fetch files');
      }
    } catch (e) {
      setState(() {
        _error = e.toString();
        if (e.toString().contains('OFFLINE') || e.toString().contains('disconnected')) {
          _error = 'Agent is offline. Ensure Windows Agent is running and connected.';
        }
      });
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _addToRecent(String path) async {
    final prefs = await SharedPreferences.getInstance();
    final recents = prefs.getStringList('drivenet_recents') ?? [];
    recents.remove(path);
    recents.insert(0, path);
    if (recents.length > 50) recents.removeRange(50, recents.length);
    await prefs.setStringList('drivenet_recents', recents);
  }

  void _navigateTo(String newPath) {
    setState(() => _currentPath = newPath);
    _fetchFiles();
  }

  // Navigate up one directory level (used by back gesture or programmatically)
  void _navigateUp() {
    if (_currentPath == '\\' || _currentPath.isEmpty) return;
    final List<String> parts = _currentPath.split('\\');
    final filtered = parts.where((p) => p.isNotEmpty).toList();
    if (filtered.length <= 1) {
      _navigateTo('\\');
    } else {
      filtered.removeLast();
      _navigateTo('${filtered.join('\\')}\\');
    }
  }

  // ─── UPLOAD ────────────────────────────────────────────────────────────────

  Future<void> _uploadFile({bool fromCamera = false, bool fromGallery = false}) async {
    try {
      List<int>? fileBytes;
      String? fileName;

      if (fromCamera || fromGallery) {
        final picker = ImagePicker();
        final XFile? picked = fromCamera
            ? await picker.pickImage(source: ImageSource.camera, imageQuality: 85)
            : await picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
        if (picked == null) return;
        fileBytes = await picked.readAsBytes();
        fileName = picked.name;
      } else {
        final result = await FilePicker.platform.pickFiles();
        if (result == null || result.files.isEmpty) return;
        final pf = result.files.single;
        fileBytes = await File(pf.path!).readAsBytes();
        fileName = pf.name;
      }

      // At this point fileName and fileBytes are guaranteed non-null since
      // all branches that set them return early on null
      final uploadName = fileName.toString();
      final uploadBytes = List<int>.from(fileBytes);

      setState(() => _uploadProgress[uploadName] = 0.0);

      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('drivenet_jwt');

      final uploadId = DateTime.now().millisecondsSinceEpoch.toString();
      const int chunkSize = 1 * 1024 * 1024;
      final int fileSize = uploadBytes.length;

      for (int i = 0; i < fileSize; i += chunkSize) {
        final int end = (i + chunkSize > fileSize) ? fileSize : i + chunkSize;
        final chunk = uploadBytes.sublist(i, end);
        final base64Chunk = base64Encode(chunk);
        final isFirst = i == 0;
        final isLast = end >= fileSize;

        final driveParam = _selectedDrive != null ? _selectedDrive! : '';
        final response = await http.post(
          Uri.parse('$_brokerUrl/api/fs/upload_chunk'),
          headers: {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'},
          body: jsonEncode({
            'uploadId': uploadId,
            'path': _currentPath,
            'name': uploadName,
            'chunk': base64Chunk,
            'isFirst': isFirst,
            'isLast': isLast,
            'drive': driveParam,
          }),
        );

        if (response.statusCode != 200) throw Exception('Upload failed');
        setState(() => _uploadProgress[uploadName] = end / fileSize);
      }

      setState(() => _uploadProgress.remove(uploadName));
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Uploaded: $uploadName')));
      _fetchFiles();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Upload error: $e')));
    }
  }

  // ─── FAB SPEED DIAL ────────────────────────────────────────────────────────

  void _showFabOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).cardColor,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _fabOption(Icons.upload_file, 'Upload File', () { Navigator.pop(context); _uploadFile(); }),
            _fabOption(Icons.camera_alt, 'Take Photo', () { Navigator.pop(context); _uploadFile(fromCamera: true); }),
            _fabOption(Icons.photo_library, 'Upload from Gallery', () { Navigator.pop(context); _uploadFile(fromGallery: true); }),
            _fabOption(Icons.create_new_folder, 'New Folder', () { Navigator.pop(context); _showCreateFolderDialog(); }),
          ],
        ),
      ),
    );
  }

  Widget _fabOption(IconData icon, String label, VoidCallback onTap) {
    return ListTile(
      leading: Icon(icon, color: const Color(0xFFFF4655)),
      title: Text(label),
      onTap: onTap,
    );
  }

  // ─── CREATE FOLDER ─────────────────────────────────────────────────────────

  void _showCreateFolderDialog() {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('New Folder'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Folder name'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFF4655)),
            onPressed: () async {
              final name = ctrl.text.trim();
              if (name.isEmpty) return;
              Navigator.pop(context);
              await _createFolder(name);
            },
            child: const Text('Create', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Future<void> _createFolder(String name) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('drivenet_jwt');
      final response = await http.post(
        Uri.parse('$_brokerUrl/api/fs/folder'),
        headers: {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'},
        body: jsonEncode({'path': _currentPath, 'name': name, 'drive': _selectedDrive ?? ''}),
      );
      if (response.statusCode == 200) {
        _fetchFiles();
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Folder "$name" created')));
      } else {
        throw Exception(jsonDecode(response.body)['error'] ?? 'Failed');
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  // ─── RENAME ────────────────────────────────────────────────────────────────

  void _showRenameDialog(Map<String, dynamic> item) {
    final name = item['name'] as String;
    final ctrl = TextEditingController(text: name);
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Rename'),
        content: TextField(controller: ctrl, autofocus: true, decoration: const InputDecoration(hintText: 'New name')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFF4655)),
            onPressed: () async {
              final newName = ctrl.text.trim();
              if (newName.isEmpty || newName == name) return;
              Navigator.pop(context);
              await _renameItem(name, newName);
            },
            child: const Text('Rename', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Future<void> _renameItem(String oldName, String newName) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('drivenet_jwt');
      final base = _currentPath == '\\' ? '' : _currentPath;
      final oldPath = '$base$oldName';
      final newPath = '$base$newName';
      final response = await http.post(
        Uri.parse('$_brokerUrl/api/fs/rename'),
        headers: {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'},
        body: jsonEncode({'oldPath': oldPath, 'newPath': newPath, 'drive': _selectedDrive ?? ''}),
      );
      if (response.statusCode == 200) {
        _fetchFiles();
      } else {
        throw Exception(jsonDecode(response.body)['error'] ?? 'Failed');
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Rename error: $e')));
    }
  }

  // ─── DOWNLOAD / OPEN ───────────────────────────────────────────────────────

  Future<void> _downloadAndOpenFile(Map<String, dynamic> item) async {
    final name = item['name'] as String;
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Downloading $name...')));
    setState(() => _isLoading = true);

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('drivenet_jwt');
      final relPath = _currentPath == '\\' ? name : '$_currentPath\\$name';
      final driveParam = _selectedDrive != null ? '&drive=${Uri.encodeComponent(_selectedDrive!)}' : '';
      final url = Uri.parse('$_brokerUrl/api/fs/download?path=${Uri.encodeComponent(relPath)}$driveParam');
      final response = await http.get(url, headers: {'Authorization': 'Bearer $token'});

      if (response.statusCode == 200) {
        final dir = await getApplicationDocumentsDirectory();
        final file = File('${dir.path}/$name');
        await file.writeAsBytes(response.bodyBytes);
        final result = await OpenFilex.open(file.path);
        if (result.type != ResultType.done && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not open file: ${result.message}')));
        }
      } else {
        throw Exception('Server rejected download request.');
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Download error: $e')));
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // ─── SHARE ─────────────────────────────────────────────────────────────────

  Future<void> _shareFile(Map<String, dynamic> item) async {
    final name = item['name'] as String;
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('drivenet_jwt');
      final relPath = _currentPath == '\\' ? name : '$_currentPath\\$name';
      final driveParam = _selectedDrive != null ? '&drive=${Uri.encodeComponent(_selectedDrive!)}' : '';
      final shareApiUrl = '$_brokerUrl/api/fs/share?path=${Uri.encodeComponent(relPath)}$driveParam';

      final response = await http.get(Uri.parse(shareApiUrl), headers: {'Authorization': 'Bearer $token'});
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final shareUrl = data['url'] as String;
        _showShareDialog(name, shareUrl);
      } else {
        throw Exception('Could not generate share link');
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Share error: $e')));
    }
  }

  void _showShareDialog(String fileName, String url) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.link, color: Color(0xFFFF4655)),
            const SizedBox(width: 8),
            Expanded(child: Text('Share: $fileName', overflow: TextOverflow.ellipsis)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Link expires in 15 minutes:', style: TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.grey.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(url, style: const TextStyle(fontSize: 11), maxLines: 3, overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: url));
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Link copied to clipboard')));
            },
            child: const Text('Copy Link'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFF4655)),
            onPressed: () {
              Navigator.pop(context);
              SharePlus.instance.share(ShareParams(text: 'Check out this file from DriveNet:\n\n$url'));
            },
            child: const Text('Share', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  // ─── TRASH ─────────────────────────────────────────────────────────────────

  Future<void> _moveToTrash(Map<String, dynamic> item) async {
    final name = item['name'] as String;
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('drivenet_jwt');
      final relPath = _currentPath == '\\' ? name : '$_currentPath\\$name';
      final driveParam = _selectedDrive != null ? '&drive=${Uri.encodeComponent(_selectedDrive!)}' : '';
      final url = Uri.parse('$_brokerUrl/api/fs/trash?path=${Uri.encodeComponent(relPath)}$driveParam');
      final response = await http.delete(url, headers: {'Authorization': 'Bearer $token'});

      if (response.statusCode == 200) {
        _fetchFiles();
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Moved "$name" to trash')));
      } else {
        throw Exception(jsonDecode(response.body)['error'] ?? 'Failed');
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  // ─── SEARCH ────────────────────────────────────────────────────────────────

  Future<void> _performSearch(String query) async {
    if (query.isEmpty) {
      setState(() => _searchResults = []);
      return;
    }
    setState(() => _isSearchLoading = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('drivenet_jwt');
      final driveParam = _selectedDrive != null ? '&drive=${Uri.encodeComponent(_selectedDrive!)}' : '';
      final url = Uri.parse('$_brokerUrl/api/fs/search?q=${Uri.encodeComponent(query)}$driveParam');
      final response = await http.get(url, headers: {'Authorization': 'Bearer $token'});
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() => _searchResults = List<Map<String, dynamic>>.from(data['items'] ?? []));
      }
    } catch (_) {} finally {
      setState(() => _isSearchLoading = false);
    }
  }

  // ─── CONTEXT MENU ──────────────────────────────────────────────────────────

  void _showItemOptions(Map<String, dynamic> item) {
    final name = item['name'] as String;
    final isDir = item['is_dir'] == true;
    final itemPath = _currentPath == '\\' ? name : '$_currentPath\\$name';
    final isStarred = _starredPaths.contains(itemPath);

    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).cardColor,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              child: Row(children: [
                Icon(_getIconData(item), color: _getIconColor(item), size: 28),
                const SizedBox(width: 12),
                Expanded(child: Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16), overflow: TextOverflow.ellipsis)),
              ]),
            ),
            const Divider(height: 1),
            if (!isDir) ...[
              ListTile(leading: const Icon(Icons.open_in_new, color: Colors.blue), title: const Text('Open / Preview'), onTap: () { Navigator.pop(context); _openPreview(item); }),
              ListTile(leading: const Icon(Icons.download), title: const Text('Download & Open'), onTap: () { Navigator.pop(context); _downloadAndOpenFile(item); }),
            ],
            ListTile(leading: const Icon(Icons.edit), title: const Text('Rename'), onTap: () { Navigator.pop(context); _showRenameDialog(item); }),
            ListTile(
              leading: Icon(isStarred ? Icons.star : Icons.star_border, color: Colors.amber),
              title: Text(isStarred ? 'Remove from Starred' : 'Add to Starred'),
              onTap: () { Navigator.pop(context); _toggleStar(item); },
            ),
            if (!isDir) ListTile(leading: const Icon(Icons.share, color: Colors.blue), title: const Text('Share Link'), onTap: () { Navigator.pop(context); _shareFile(item); }),
            ListTile(leading: const Icon(Icons.delete_outline, color: Colors.orange), title: const Text('Move to Trash'), onTap: () { Navigator.pop(context); _moveToTrash(item); }),
          ],
        ),
      ),
    );
  }

  void _openPreview(Map<String, dynamic> item) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => FilePreviewScreen(fileItem: item, currentPath: _currentPath, selectedDrive: _selectedDrive)),
    );
    if (result == true) _fetchFiles();
  }

  // ─── SORT ──────────────────────────────────────────────────────────────────

  List<Map<String, dynamic>> _getSortedItems() {
    final sorted = List<Map<String, dynamic>>.from(_items);
    sorted.sort((a, b) {
      // Folders first
      if (a['is_dir'] == true && b['is_dir'] != true) return -1;
      if (a['is_dir'] != true && b['is_dir'] == true) return 1;
      switch (_sortBy) {
        case _SortBy.nameAsc:
          return (a['name'] ?? '').compareTo(b['name'] ?? '');
        case _SortBy.nameDesc:
          return (b['name'] ?? '').compareTo(a['name'] ?? '');
        case _SortBy.dateNew:
          return (b['modified'] ?? 0).compareTo(a['modified'] ?? 0);
        case _SortBy.dateOld:
          return (a['modified'] ?? 0).compareTo(b['modified'] ?? 0);
        case _SortBy.sizeBig:
          return (b['size'] ?? 0).compareTo(a['size'] ?? 0);
        case _SortBy.sizeSmall:
          return (a['size'] ?? 0).compareTo(b['size'] ?? 0);
      }
    });
    return sorted;
  }

  // ─── HELPERS ───────────────────────────────────────────────────────────────

  String _formatSize(int bytes) {
    if (bytes <= 0) return '0 B';
    const suffixes = ['B', 'KB', 'MB', 'GB', 'TB'];
    int i = 0;
    double val = bytes.toDouble();
    while (val >= 1024 && i < suffixes.length - 1) { val /= 1024; i++; }
    return '${val.toStringAsFixed(1)} ${suffixes[i]}';
  }

  String _formatDate(dynamic timestamp) {
    if (timestamp == null) return '';
    try {
      int ms = timestamp is int ? timestamp : (int.tryParse(timestamp.toString()) ?? 0);
      final date = DateTime.fromMillisecondsSinceEpoch(ms).toLocal();
      return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    } catch (_) { return ''; }
  }

  IconData _getIconData(Map<String, dynamic> item) {
    final bool isDir = item['is_dir'] == true;
    if (isDir) return Icons.folder;
    final ext = (item['name'] as String? ?? '').split('.').last.toLowerCase();
    if (['png', 'jpg', 'jpeg', 'gif', 'webp', 'svg'].contains(ext)) return Icons.image;
    if (['mp4', 'mov', 'avi', 'mkv', 'webm'].contains(ext)) return Icons.video_file;
    if (['pdf'].contains(ext)) return Icons.picture_as_pdf;
    if (['txt', 'md', 'log'].contains(ext)) return Icons.description;
    if (['dart', 'js', 'ts', 'py', 'json', 'html', 'css', 'xml'].contains(ext)) return Icons.code;
    if (['mp3', 'wav', 'flac', 'aac', 'm4a'].contains(ext)) return Icons.audio_file;
    if (['zip', 'rar', '7z', 'tar', 'gz'].contains(ext)) return Icons.folder_zip;
    if (['doc', 'docx'].contains(ext)) return Icons.article;
    if (['xls', 'xlsx', 'csv'].contains(ext)) return Icons.table_chart;
    if (['ppt', 'pptx'].contains(ext)) return Icons.slideshow;
    if (['apk'].contains(ext)) return Icons.android;
    if (['exe', 'msi'].contains(ext)) return Icons.computer;
    return Icons.insert_drive_file;
  }

  Color _getIconColor(Map<String, dynamic> item) {
    final bool isDir = item['is_dir'] == true;
    if (isDir) return const Color(0xFF137FEC);
    final ext = (item['name'] as String? ?? '').split('.').last.toLowerCase();
    if (['png', 'jpg', 'jpeg', 'gif', 'webp', 'svg'].contains(ext)) return Colors.purpleAccent;
    if (['mp4', 'mov', 'avi', 'mkv', 'webm'].contains(ext)) return Colors.orangeAccent;
    if (['pdf'].contains(ext)) return Colors.redAccent;
    if (['dart', 'js', 'ts', 'py', 'json', 'html', 'css', 'xml'].contains(ext)) return Colors.greenAccent;
    if (['mp3', 'wav', 'flac', 'aac', 'm4a'].contains(ext)) return Colors.tealAccent;
    if (['zip', 'rar', '7z', 'tar', 'gz'].contains(ext)) return Colors.brown;
    if (['doc', 'docx'].contains(ext)) return Colors.blue;
    if (['xls', 'xlsx', 'csv'].contains(ext)) return Colors.green;
    if (['ppt', 'pptx'].contains(ext)) return Colors.orange;
    return Colors.grey;
  }

  // ─── BREADCRUMBS ───────────────────────────────────────────────────────────

  Widget _buildBreadcrumbs() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).appBarTheme.backgroundColor,
        border: Border(bottom: BorderSide(color: Theme.of(context).dividerColor.withValues(alpha: 0.1))),
      ),
      child: Row(
        children: [
          Container(width: 8, height: 8,
            decoration: BoxDecoration(shape: BoxShape.circle, color: _isAgentOnline ? Colors.green : Colors.orange)),
          const SizedBox(width: 6),
          Text(_isAgentOnline ? 'Online' : 'Offline',
            style: TextStyle(fontSize: 11, color: _isAgentOnline ? Colors.green : Colors.orange, fontWeight: FontWeight.bold)),
          const SizedBox(width: 4),
          if (_currentPath != '\\' && _currentPath.isNotEmpty)
            GestureDetector(
              onTap: _navigateUp,
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 4),
                child: Icon(Icons.arrow_upward, color: Color(0xFFFF4655), size: 16),
              ),
            ),
          const SizedBox(width: 4),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: _buildBreadcrumbChips(),
              ),
            ),
          ),
          IconButton(icon: const Icon(Icons.refresh, color: Colors.grey, size: 18), onPressed: _fetchFiles,
            padding: EdgeInsets.zero, constraints: const BoxConstraints()),
        ],
      ),
    );
  }

  List<Widget> _buildBreadcrumbChips() {
    final chips = <Widget>[];
    // Root chip
    chips.add(GestureDetector(
      onTap: () => _navigateTo('\\'),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: _selectedDrive != null ? const Color(0xFFFF4655).withValues(alpha: 0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          _selectedDrive?.toUpperCase() ?? 'Root',
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFFFF4655)),
        ),
      ),
    ));

    if (_currentPath != '\\' && _currentPath.isNotEmpty) {
      final parts = _currentPath.split('\\').where((p) => p.isNotEmpty).toList();
      // Skip the drive letter part since it's already the root chip
      final startIdx = (parts.isNotEmpty && parts[0].contains(':')) ? 1 : 0;
      String accumulated = _selectedDrive ?? '';
      for (int i = startIdx; i < parts.length; i++) {
        accumulated = accumulated.endsWith('\\') ? '$accumulated${parts[i]}' : '$accumulated\\${parts[i]}';
        final pathToNav = '$accumulated\\';
        final part = parts[i];
        chips.add(const Icon(Icons.chevron_right, color: Colors.grey, size: 16));
        chips.add(GestureDetector(
          onTap: () => _navigateTo(pathToNav),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: i == parts.length - 1 ? Colors.grey.withValues(alpha: 0.15) : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(part, style: TextStyle(fontSize: 12,
              fontWeight: i == parts.length - 1 ? FontWeight.bold : FontWeight.normal,
              color: Theme.of(context).textTheme.bodyLarge?.color)),
          ),
        ));
      }
    }
    return chips;
  }

  // ─── FILE ITEM ─────────────────────────────────────────────────────────────

  Widget _buildFileItem(Map<String, dynamic> item) {
    final bool isDir = item['is_dir'] == true;
    final String name = item['name'] ?? 'Unknown';
    final int size = item['size'] ?? 0;
    final String date = _formatDate(item['modified']);
    final itemPath = _currentPath == '\\' ? name : '$_currentPath\\$name';
    final isStarred = _starredPaths.contains(itemPath);

    return ListTile(
      leading: Container(
        width: 40, height: 40,
        decoration: BoxDecoration(
          color: _getIconColor(item).withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(_getIconData(item), color: _getIconColor(item)),
      ),
      title: Row(children: [
        Expanded(child: Text(name, style: TextStyle(color: Theme.of(context).textTheme.bodyLarge?.color, fontSize: 14, fontWeight: FontWeight.w500), maxLines: 1, overflow: TextOverflow.ellipsis)),
        if (isStarred) const Icon(Icons.star, color: Colors.amber, size: 14),
      ]),
      subtitle: Text(
        isDir ? 'Folder • $date' : '${_formatSize(size)} • $date',
        style: TextStyle(color: Theme.of(context).textTheme.bodySmall?.color?.withValues(alpha: 0.6) ?? Colors.grey, fontSize: 12),
      ),
      onTap: isDir ? () {
        String newPath = _currentPath;
        if (newPath == '\\') { newPath = '$name\\'; }
        else { if (!newPath.endsWith('\\')) newPath += '\\'; newPath += '$name\\'; }
        _navigateTo(newPath);
      } : () => _openPreview(item),
      onLongPress: () => _showItemOptions(item),
      trailing: IconButton(
        icon: const Icon(Icons.more_vert, color: Colors.grey, size: 20),
        onPressed: () => _showItemOptions(item),
      ),
    );
  }

  Widget _buildGridItem(Map<String, dynamic> item) {
    final bool isDir = item['is_dir'] == true;
    final String name = item['name'] ?? 'Unknown';
    final itemPath = _currentPath == '\\' ? name : '$_currentPath\\$name';
    final isStarred = _starredPaths.contains(itemPath);

    return GestureDetector(
      onTap: isDir ? () {
        String newPath = _currentPath;
        if (newPath == '\\') { newPath = '$name\\'; }
        else { if (!newPath.endsWith('\\')) newPath += '\\'; newPath += '$name\\'; }
        _navigateTo(newPath);
      } : () => _openPreview(item),
      onLongPress: () => _showItemOptions(item),
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Theme.of(context).dividerColor.withValues(alpha: 0.15)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Stack(
              children: [
                Icon(_getIconData(item), color: _getIconColor(item), size: 44),
                if (isStarred) const Positioned(right: 0, top: 0, child: Icon(Icons.star, color: Colors.amber, size: 14)),
              ],
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(name, maxLines: 2, overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: Theme.of(context).textTheme.bodyLarge?.color)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUploadProgress() {
    if (_uploadProgress.isEmpty) return const SizedBox.shrink();
    return Column(
      children: _uploadProgress.entries.map((e) => Container(
        color: Theme.of(context).cardColor,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Uploading: ${e.key}', style: TextStyle(color: Theme.of(context).textTheme.bodySmall?.color, fontSize: 12)),
            const SizedBox(height: 4),
            LinearProgressIndicator(value: e.value, color: const Color(0xFFFF4655), backgroundColor: Colors.grey[800]),
          ])),
          const SizedBox(width: 16),
          Text('${(e.value * 100).toStringAsFixed(0)}%', style: TextStyle(color: Theme.of(context).textTheme.bodySmall?.color, fontSize: 12)),
        ]),
      )).toList(),
    );
  }

  // ─── SEARCH BAR ────────────────────────────────────────────────────────────

  Widget _buildSearchBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: TextField(
        controller: _searchController,
        autofocus: true,
        decoration: InputDecoration(
          hintText: 'Search files and folders...',
          prefixIcon: const Icon(Icons.search, color: Color(0xFFFF4655)),
          suffixIcon: _searchController.text.isNotEmpty
              ? IconButton(icon: const Icon(Icons.clear), onPressed: () { _searchController.clear(); setState(() => _searchResults = []); })
              : null,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.withValues(alpha: 0.3))),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
        onChanged: (v) => _performSearch(v),
      ),
    );
  }

  // ─── BUILD ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final sortedItems = _getSortedItems();
    final displayItems = _isSearching ? _searchResults : sortedItems;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        automaticallyImplyLeading: false,
        title: _isSearching
            ? null
            : Row(children: [
                PopupMenuButton<_SortBy>(
                  icon: const Icon(Icons.sort, color: Colors.grey, size: 20),
                  tooltip: 'Sort',
                  onSelected: (v) => setState(() => _sortBy = v),
                  itemBuilder: (_) => [
                    const PopupMenuItem(value: _SortBy.nameAsc, child: Text('Name A→Z')),
                    const PopupMenuItem(value: _SortBy.nameDesc, child: Text('Name Z→A')),
                    const PopupMenuItem(value: _SortBy.dateNew, child: Text('Date (Newest)')),
                    const PopupMenuItem(value: _SortBy.dateOld, child: Text('Date (Oldest)')),
                    const PopupMenuItem(value: _SortBy.sizeBig, child: Text('Size (Largest)')),
                    const PopupMenuItem(value: _SortBy.sizeSmall, child: Text('Size (Smallest)')),
                  ],
                ),
              ]),
        actions: [
          IconButton(
            icon: Icon(_isSearching ? Icons.close : Icons.search, color: Colors.grey),
            onPressed: () {
              setState(() {
                _isSearching = !_isSearching;
                if (!_isSearching) { _searchController.clear(); _searchResults = []; }
              });
            },
          ),
          IconButton(
            icon: Icon(_viewMode == _ViewMode.list ? Icons.grid_view : Icons.view_list, color: Colors.grey),
            onPressed: () => setState(() => _viewMode = _viewMode == _ViewMode.list ? _ViewMode.grid : _ViewMode.list),
          ),
        ],
      ),
      body: Column(
        children: [
          if (_isSearching) _buildSearchBar(),
          if (!_isSearching) _buildBreadcrumbs(),
          _buildUploadProgress(),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: Color(0xFFFF4655)))
                : _error.isNotEmpty
                    ? Center(child: Padding(
                        padding: const EdgeInsets.all(32.0),
                        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                          const Icon(Icons.cloud_off, color: Color(0xFFFF4655), size: 48),
                          const SizedBox(height: 16),
                          Text(_error, style: TextStyle(color: Theme.of(context).textTheme.bodyMedium?.color?.withValues(alpha: 0.7)), textAlign: TextAlign.center),
                          const SizedBox(height: 16),
                          ElevatedButton(onPressed: _fetchFiles,
                            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFF4655)),
                            child: const Text('Retry', style: TextStyle(color: Colors.white))),
                        ]),
                      ))
                    : _isSearchLoading
                        ? const Center(child: CircularProgressIndicator(color: Color(0xFFFF4655)))
                        : displayItems.isEmpty
                            ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                                Icon(_isSearching ? Icons.search_off : Icons.folder_open,
                                  color: Theme.of(context).disabledColor.withValues(alpha: 0.2), size: 64),
                                const SizedBox(height: 16),
                                Text(_isSearching ? 'No results found' : 'Folder is empty',
                                  style: TextStyle(color: Theme.of(context).disabledColor)),
                              ]))
                            : _viewMode == _ViewMode.list
                                ? RefreshIndicator(
                                    color: const Color(0xFFFF4655),
                                    backgroundColor: Theme.of(context).cardColor,
                                    onRefresh: _fetchFiles,
                                    child: ListView.separated(
                                      itemCount: displayItems.length,
                                      separatorBuilder: (_, __) => Divider(color: Theme.of(context).dividerColor.withValues(alpha: 0.1), height: 1),
                                      itemBuilder: (_, i) => _buildFileItem(displayItems[i]),
                                    ),
                                  )
                                : RefreshIndicator(
                                    color: const Color(0xFFFF4655),
                                    backgroundColor: Theme.of(context).cardColor,
                                    onRefresh: _fetchFiles,
                                    child: GridView.builder(
                                      padding: const EdgeInsets.all(12),
                                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                                        crossAxisCount: 3, crossAxisSpacing: 10, mainAxisSpacing: 10, childAspectRatio: 0.85),
                                      itemCount: displayItems.length,
                                      itemBuilder: (_, i) => _buildGridItem(displayItems[i]),
                                    ),
                                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showFabOptions,
        backgroundColor: const Color(0xFFFF4655),
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }
}
