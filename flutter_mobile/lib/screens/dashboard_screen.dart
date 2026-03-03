import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../config.dart';
import '../main.dart';
import 'login_screen.dart';
import 'file_browser_screen.dart';
import 'recent_screen.dart';
import 'starred_screen.dart';
import 'trash_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen>
    with WidgetsBindingObserver {
  int _selectedIndex = 0;
  String _userName = '';
  String _userEmail = '';
  int _storageTotal = 0;
  int _storageUsed = 0;
  bool _statsLoaded = false;
  bool _agentOnline = false;
  String? _activeDrive;
  List<String> _drives = [];

  static const List<Widget> _screens = [
    FileBrowserScreen(),
    RecentScreen(),
    StarredScreen(),
    TrashScreen(),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadUserInfo();
    _loadAgentInfo();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // Refresh drive info when app comes back to foreground
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadAgentInfo();
    }
  }

  Future<void> _loadUserInfo() async {
    final prefs = await SharedPreferences.getInstance();
    final email = prefs.getString('drivenet_user') ?? '';
    setState(() {
      _userEmail = email;
      _userName = email.isNotEmpty ? email.split('@').first : 'User';
    });
  }

  Future<void> _loadAgentInfo() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('drivenet_jwt');
      if (token == null) return;

      final response = await http.get(
        Uri.parse('${AppConfig.brokerUrl}/api/fs/me/agent'),
        headers: {'Authorization': 'Bearer $token'},
      ).timeout(const Duration(seconds: 6));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final online = data['online'] == true;
        final drive = data['drive'] as String?;
        final rawDrives = data['drives'] as List<dynamic>?;
        final driveList = rawDrives?.map((d) => d['drive'].toString()).toList() ?? [];

        setState(() {
          _agentOnline = online;
          _activeDrive = drive;
          _drives = driveList;
          _statsLoaded = false; // Trigger stats reload
        });
        if (online) await _loadDiskStats(token: token, drive: drive);
      }
    } catch (_) {}
  }

  Future<void> _loadDiskStats({String? token, String? drive}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final tok = token ?? prefs.getString('drivenet_jwt');
      if (tok == null) return;
      final driveParam = drive != null ? '?drive=${Uri.encodeComponent(drive)}' : '';
      final response = await http.get(
        Uri.parse('${AppConfig.brokerUrl}/api/fs/stats$driveParam'),
        headers: {'Authorization': 'Bearer $tok'},
      ).timeout(const Duration(seconds: 6));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final t = data['storageTotal'] ?? 0;
        final u = data['storageUsed'] ?? (t - (data['storageAvailable'] ?? 0));
        setState(() {
          _storageTotal = t is int ? t : (t as num).toInt();
          _storageUsed = u is int ? u : (u as num).toInt();
          _statsLoaded = true;
        });
      }
    } catch (_) {}
  }

  Future<void> _setActiveDrive(String drive) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('drivenet_jwt');
      await http.post(
        Uri.parse('${AppConfig.brokerUrl}/api/fs/me/set-active-drive'),
        headers: {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'},
        body: jsonEncode({'drive': drive}),
      );
      setState(() {
        _activeDrive = drive;
        _statsLoaded = false;
      });
      await _loadDiskStats(drive: drive);
      // Tell the file browser to refresh
      if (mounted) Navigator.pop(context); // close drawer
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  Future<void> _logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('drivenet_jwt');
    await prefs.remove('drivenet_user');
    if (mounted) {
      Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const LoginScreen()));
    }
  }

  Future<void> _toggleTheme() async {
    final isDark = themeModeNotifier.value == ThemeMode.dark;
    themeModeNotifier.value = isDark ? ThemeMode.light : ThemeMode.dark;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('drivenet_dark_mode', !isDark);
  }

  String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    const s = ['B', 'KB', 'MB', 'GB', 'TB'];
    int i = 0; double v = bytes.toDouble();
    while (v >= 1024 && i < s.length - 1) { v /= 1024; i++; }
    return '${v.toStringAsFixed(1)} ${s[i]}';
  }

  void _onSelectItem(int index) {
    setState(() => _selectedIndex = index);
    Navigator.pop(context);
  }

  // ─── NEON GLOW ICON ────────────────────────────────────────────────────────

  Widget _neonIcon(IconData icon, Color glowColor, {double size = 22}) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: glowColor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(icon, color: glowColor, size: size),
    );
  }

  Widget _buildDrawerNavItem(int index, IconData icon, String label, Color glowColor) {
    final isSelected = _selectedIndex == index;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: ListTile(
        leading: _neonIcon(icon, isSelected ? glowColor : Colors.grey, size: 18),
        title: Text(label, style: TextStyle(
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          color: isSelected ? glowColor : null,
          fontSize: 14,
        )),
        selected: isSelected,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        selectedTileColor: glowColor.withValues(alpha: 0.08),
        onTap: () => _onSelectItem(index),
      ),
    );
  }

  // ─── DRIVE PICKER IN DRAWER ────────────────────────────────────────────────

  Widget _buildDrivePicker() {
    if (_drives.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Text('DRIVES', style: TextStyle(
            fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.5,
            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.35),
          )),
        ),
        ..._drives.map((drive) {
          final isActive = drive == _activeDrive;
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
            child: ListTile(
              leading: _neonIcon(
                Icons.storage,
                isActive ? const Color(0xFFFF4655) : Colors.grey,
                size: 16,
              ),
              title: Text(drive.toUpperCase(), style: TextStyle(
                fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                fontSize: 13,
                color: isActive ? const Color(0xFFFF4655) : null,
              )),
              trailing: isActive
                  ? Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFF4655).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text('ACTIVE', style: TextStyle(fontSize: 9, color: Color(0xFFFF4655), fontWeight: FontWeight.bold)),
                    )
                  : null,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              onTap: isActive ? null : () => _setActiveDrive(drive),
            ),
          );
        }),
        const SizedBox(height: 4),
      ],
    );
  }

  // ─── DISK USAGE BAR ────────────────────────────────────────────────────────

  Widget _buildDiskUsageBar() {
    if (!_statsLoaded || _storageTotal <= 0) {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('STORAGE', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.5,
          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.35))),
        const SizedBox(height: 8),
        Row(children: [
          const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFFF4655))),
          const SizedBox(width: 8),
          Text(_agentOnline ? 'Loading stats...' : 'Agent offline', style: const TextStyle(fontSize: 12, color: Colors.grey)),
        ]),
      ]);
    }

    final usedFraction = (_storageTotal > 0) ? (_storageUsed / _storageTotal).clamp(0.0, 1.0) : 0.0;
    final Color barColor = usedFraction < 0.7
        ? const Color(0xFFFF4655)
        : usedFraction < 0.9 ? Colors.orange : Colors.red;

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('STORAGE', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.5,
        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.35))),
      const SizedBox(height: 10),
      ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: LinearProgressIndicator(
          value: usedFraction,
          backgroundColor: Colors.grey.withValues(alpha: 0.15),
          valueColor: AlwaysStoppedAnimation<Color>(barColor),
          minHeight: 8,
        ),
      ),
      const SizedBox(height: 6),
      Text('${_formatBytes(_storageUsed)} / ${_formatBytes(_storageTotal)}',
        style: const TextStyle(fontSize: 12, color: Colors.grey)),
    ]);
  }

  // ─── BUILD ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        title: Row(children: [
          // NEON DC logo
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFFFF4655).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
              boxShadow: [BoxShadow(color: const Color(0xFFFF4655).withValues(alpha: 0.3), blurRadius: 12)],
            ),
            child: const Text('DRIVE', style: TextStyle(color: Color(0xFFFF4655), fontWeight: FontWeight.w900, letterSpacing: 2, fontSize: 13)),
          ),
          const SizedBox(width: 8),
          const Text('NET', style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 2, fontSize: 13)),
        ]),
        actions: [
          // Theme toggle
          Tooltip(
            message: isDark ? 'Switch to Light Mode' : 'Switch to Dark Mode',
            child: GestureDetector(
              onTap: _toggleTheme,
              child: Container(
                margin: const EdgeInsets.only(right: 12),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.08)
                      : Colors.black.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(isDark ? Icons.light_mode : Icons.dark_mode,
                      size: 16, color: isDark ? Colors.amber : Colors.indigo),
                    const SizedBox(width: 4),
                    Text(isDark ? 'Light' : 'Dark',
                      style: TextStyle(fontSize: 12,
                        color: isDark ? Colors.amber : Colors.indigo,
                        fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
      drawer: Drawer(
        width: 280,
        child: Column(
          children: [
            // Header
            Container(
              padding: EdgeInsets.fromLTRB(16, MediaQuery.of(context).padding.top + 16, 16, 16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: isDark
                      ? [const Color(0xFF1A1A2E), const Color(0xFF13131F)]
                      : [const Color(0xFFFF4655).withValues(alpha: 0.08), Colors.white],
                ),
              ),
              child: Row(children: [
                Container(
                  width: 52, height: 52,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFFFF4655).withValues(alpha: 0.15),
                  ),
                  child: Center(
                    child: Text(
                      _userName.isNotEmpty ? _userName[0].toUpperCase() : 'D',
                      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFFFF4655)),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(_userName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  const SizedBox(height: 2),
                  Text(_userEmail, style: TextStyle(fontSize: 11,
                    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5)),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 4),
                  Row(children: [
                    Container(width: 7, height: 7, decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _agentOnline ? Colors.greenAccent : Colors.orange,
                    )),
                    const SizedBox(width: 5),
                    Text(_agentOnline ? 'Agent Online' : 'Agent Offline',
                      style: TextStyle(fontSize: 11, color: _agentOnline ? Colors.greenAccent : Colors.orange, fontWeight: FontWeight.w600)),
                  ]),
                ])),
              ]),
            ),

            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 8),
                children: [
                  // Navigation items
                  _buildDrawerNavItem(0, Icons.folder_outlined, 'All Files', const Color(0xFFFF4655)),
                  _buildDrawerNavItem(1, Icons.access_time_filled, 'Recent', Colors.cyanAccent),
                  _buildDrawerNavItem(2, Icons.star_rounded, 'Starred', Colors.amber),
                  _buildDrawerNavItem(3, Icons.delete_outline_rounded, 'Trash', Colors.redAccent),
                  const Divider(height: 16),

                  // Drive picker
                  _buildDrivePicker(),

                  if (_drives.isNotEmpty) const Divider(height: 8),

                  // Refresh
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: ListTile(
                      leading: _neonIcon(Icons.sync, Colors.tealAccent, size: 16),
                      title: const Text('Refresh Drives', style: TextStyle(fontSize: 13)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      onTap: () { Navigator.pop(context); _loadAgentInfo(); },
                    ),
                  ),

                  // Logout
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: ListTile(
                      leading: _neonIcon(Icons.logout_rounded, Colors.redAccent, size: 16),
                      title: const Text('Logout', style: TextStyle(color: Colors.redAccent, fontSize: 13)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      onTap: _logout,
                    ),
                  ),
                ],
              ),
            ),

            // Disk usage footer
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: Theme.of(context).dividerColor)),
              ),
              child: _buildDiskUsageBar(),
            ),
          ],
        ),
      ),
      body: IndexedStack(
        index: _selectedIndex,
        children: _screens,
      ),
    );
  }
}
