import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:system_tray/system_tray.dart';
import 'package:window_manager/window_manager.dart';
import '../services/drive_service.dart';
import '../services/backend_service.dart';
import '../services/tunnel_client.dart';
import '../main.dart' show StartupService;
import 'login_screen.dart';

class DriveScreen extends StatefulWidget {
  const DriveScreen({super.key});
  @override
  State<DriveScreen> createState() => _DriveScreenState();
}

class _DriveScreenState extends State<DriveScreen> with WindowListener {
  List<Map<String, dynamic>> _drives = [];
  String? _selectedDrive;
  bool _isLoading = true;
  bool _isOnline = false;
  bool _goingOnline = false;
  String _userEmail = '';
  String _brokerUrl = 'https://cloud-usb.onrender.com';

  bool get _isConnected => TunnelClient.isConnected;
  final SystemTray _systemTray = SystemTray();
  bool _startOnBoot = false;

  // Stitch Colors
  static const Color dnBg = Color(0xFF131318);
  static const Color dnSurface = Color(0xFF1F1F25);
  static const Color dnAccent = Color(0xFF6366F1);
  static const Color dnText = Color(0xFFFFFFFF);
  static const Color dnSubtext = Color(0xFF908FA0);
  static const Color dnSuccess = Color(0xFF34D399);
  static const Color dnError = Color(0xFFF87171);

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    _loadData();
    _initTray();
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    final email = prefs.getString('drivenet_user') ?? '';
    final savedDrive = prefs.getString('selected_drive');
    final brokerUrl = prefs.getString('broker_url') ?? 'https://cloud-usb.onrender.com';
    final isOnline = prefs.getBool('is_online') ?? false;
    final startOnBoot = await StartupService.isEnabled();

    final rawDrives = await DriveService.getWindowsDrives();
    final detailedDrives = await DriveService.getDriveDetails(rawDrives);

    setState(() {
      _userEmail = email;
      _brokerUrl = brokerUrl;
      _drives = detailedDrives;
      _selectedDrive = savedDrive ?? (detailedDrives.isNotEmpty ? detailedDrives[0]['name'] : null);
      _isOnline = isOnline;
      _startOnBoot = startOnBoot;
      _isLoading = false;
    });

    if (isOnline && _selectedDrive != null) {
      BackendService.syncConfig().catchError((e) => debugPrint('Auto-sync error: $e'));
    }
  }

  Future<void> _goOnline() async {
    if (_selectedDrive == null || _goingOnline) return;
    setState(() => _goingOnline = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final driveToStore = _selectedDrive!.endsWith('\\') ? _selectedDrive! : '$_selectedDrive\\';
      await prefs.setString('selected_drive', driveToStore);
      await prefs.setBool('is_online', true);
      await BackendService.syncConfig();
      setState(() { _isOnline = true; _goingOnline = false; });
    } catch (e) {
      setState(() => _goingOnline = false);
    }
  }

  Future<void> _goOffline() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('is_online', false);
    BackendService.stopAgent();
    setState(() => _isOnline = false);
  }

  Future<void> _handleLogout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('drivenet_jwt');
    await prefs.remove('drivenet_user');
    await prefs.setBool('is_online', false);
    BackendService.stopAgent();
    if (mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (route) => false,
      );
    }
  }

  Future<void> _initTray() async {
    try {
      await _systemTray.initSystemTray(title: 'Indigo Vault', iconPath: 'assets/icon.ico');
      final menu = Menu();
      await menu.buildFrom([
        MenuItemLabel(label: 'Indigo Vault Agent', enabled: false),
        MenuSeparator(),
        MenuItemLabel(label: 'Open Dashboard', onClicked: (_) => windowManager.show()),
        MenuItemLabel(label: 'Sign Out', onClicked: (_) => _handleLogout()),
      ]);
      await _systemTray.setContextMenu(menu);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Container(
        decoration: const BoxDecoration(color: dnBg),
        child: Row(
          children: [
            _buildSidebar(),
            Expanded(child: _buildMainContent()),
          ],
        ),
      ),
    );
  }

  Widget _buildSidebar() {
    return Container(
      width: 220,
      decoration: BoxDecoration(
        color: dnBg,
        border: Border(right: BorderSide(color: Colors.white.withValues(alpha: 0.05))),
      ),
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              'Indigo Vault',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: dnText, letterSpacing: -0.5),
            ),
          ),
          const SizedBox(height: 40),
          _sidebarItem(Icons.dashboard_rounded, 'Dashboard', true),
          _sidebarItem(Icons.settings_rounded, 'Settings', false),
          _sidebarItem(Icons.help_outline_rounded, 'Support', false),
          const Spacer(),
          _buildProfileSection(),
        ],
      ),
    );
  }

  Widget _sidebarItem(IconData icon, String label, bool active) {
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      decoration: BoxDecoration(
        color: active ? dnAccent.withValues(alpha: 0.1) : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Stack(
        children: [
          if (active)
            Positioned(
              left: 0, top: 12, bottom: 12,
              child: Container(width: 3, decoration: const BoxDecoration(color: dnAccent, borderRadius: BorderRadius.horizontal(right: Radius.circular(4)))),
            ),
          ListTile(
            onTap: () {},
            dense: true,
            leading: Icon(icon, color: active ? dnAccent : dnSubtext, size: 20),
            title: Text(label, style: TextStyle(color: active ? dnText : dnSubtext, fontSize: 13, fontWeight: active ? FontWeight.bold : FontWeight.normal)),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ],
      ),
    );
  }

  Widget _buildProfileSection() {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.03),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 14,
                backgroundColor: dnAccent.withValues(alpha: 0.2),
                child: Text(_userEmail.substring(0, 1).toUpperCase(), style: const TextStyle(color: dnAccent, fontSize: 10, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(width: 10),
              Expanded(child: Text(_userEmail.split('@')[0], style: const TextStyle(color: dnText, fontSize: 11, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis)),
            ],
          ),
        ),
        const SizedBox(height: 12),
        TextButton.icon(
          onPressed: _handleLogout,
          icon: const Icon(Icons.logout_rounded, size: 14, color: dnError),
          label: const Text('Sign Out', style: TextStyle(color: dnError, fontSize: 11, fontWeight: FontWeight.bold)),
          style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 12)),
        ),
      ],
    );
  }

  Widget _buildMainContent() {
    if (_isLoading) return const Center(child: CircularProgressIndicator(color: dnAccent));

    return Column(
      children: [
        _buildHeader(),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(40),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildBentoGrid(),
                const SizedBox(height: 48),
                const Text('ACTIVE STORAGE', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: dnSubtext, letterSpacing: 2)),
                const SizedBox(height: 20),
                ..._drives.map(_buildDriveCard),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHeader() {
    return Container(
      height: 80,
      padding: const EdgeInsets.symmetric(horizontal: 40),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.05)))),
      child: Row(
        children: [
          const Text('Workspace Dashboard', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: dnText)),
          const Spacer(),
          _statusIndicator(),
        ],
      ),
    );
  }

  Widget _statusIndicator() {
    final online = _isOnline && _isConnected;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: (online ? dnSuccess : dnError).withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(100),
        border: Border.all(color: (online ? dnSuccess : dnError).withValues(alpha: 0.1)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6, height: 6,
            decoration: BoxDecoration(color: online ? dnSuccess : dnError, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Text(
            online ? 'SYNC ACTIVE' : 'GATEWAY OFFLINE',
            style: TextStyle(fontSize: 9, fontWeight: FontWeight.w900, color: online ? dnSuccess : dnError, letterSpacing: 0.5),
          ),
        ],
      ),
    );
  }

  Widget _buildBentoGrid() {
    return Row(
      children: [
        _bentoCard('Connection Pool', _isConnected ? 'Active Tunnel' : 'Connecting...', Icons.bolt_rounded, dnAccent),
        const SizedBox(width: 20),
        _bentoCard('Active Vault', _selectedDrive ?? 'No Selection', Icons.folder_rounded, dnSuccess),
        const SizedBox(width: 20),
        _bentoCard('Agent Uptime', '100.0%', Icons.verified_user_rounded, dnAccent),
      ],
    );
  }

  Widget _bentoCard(String title, String value, IconData icon, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: dnSurface,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white.withValues(alpha: 0.03)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(height: 20),
            Text(title, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: dnSubtext, letterSpacing: 1)),
            const SizedBox(height: 4),
            Text(value, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: dnText), overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    );
  }

  Widget _buildDriveCard(Map<String, dynamic> drive) {
    final name = drive['name'] as String;
    final isSelected = _selectedDrive == name;
    final totalGb = (drive['totalGb'] as num).toDouble();
    final usedGb = (drive['usedGb'] as num).toDouble();
    final pct = totalGb > 0 ? (usedGb / totalGb) : 0.0;

    return GestureDetector(
      onTap: () async {
        setState(() => _selectedDrive = name);
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('selected_drive', name.endsWith('\\') ? name : '$name\\');
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: isSelected ? dnSurface : Colors.transparent,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: isSelected ? dnAccent.withValues(alpha: 0.3) : Colors.white.withValues(alpha: 0.03)),
          boxShadow: isSelected ? [BoxShadow(color: dnAccent.withValues(alpha: 0.05), blurRadius: 20)] : null,
        ),
        child: Row(
          children: [
            Container(
              width: 52, height: 52,
              decoration: BoxDecoration(color: isSelected ? dnAccent : dnSurface, borderRadius: BorderRadius.circular(16)),
              child: Icon(Icons.storage_rounded, color: isSelected ? Colors.white : dnSubtext, size: 24),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: dnText)),
                  const SizedBox(height: 4),
                  Text('${usedGb.toStringAsFixed(1)} GB / ${totalGb.toStringAsFixed(1)} GB Used', style: const TextStyle(fontSize: 12, color: dnSubtext)),
                  const SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(value: pct, backgroundColor: Colors.black12, color: isSelected ? dnAccent : dnSubtext),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 20),
            if (!_isOnline || !isSelected)
              ElevatedButton(
                onPressed: isSelected ? _goOnline : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: dnAccent,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                ),
                child: Text(isSelected ? 'GO ONLINE' : 'SELECT', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900)),
              )
            else
              TextButton(
                onPressed: _goOffline,
                child: const Text('DISCONNECT', style: TextStyle(color: dnError, fontSize: 11, fontWeight: FontWeight.w900)),
              ),
          ],
        ),
      ),
    );
  }
}
