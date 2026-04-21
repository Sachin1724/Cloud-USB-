import 'dart:convert';
import 'dart:io';
import 'dart:async';
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

  // Live tunnel status
  bool get _isConnected => TunnelClient.isConnected;

  // Tray
  final SystemTray _systemTray = SystemTray();
  final AppWindow _appWindow = AppWindow();

  // Boot + auto-connect
  bool _startOnBoot = false;
  Timer? _statusTimer;
  Timer? _autoConnectTimer;  // Pings broker until internet comes up, then goes online
  bool _autoConnectDone = false;

  // dn-colors
  static const Color dnBg = Color(0xFF0F0F14);
  static const Color dnSurface = Color(0xFF16161D);
  static const Color dnBorder = Color(0xFF2A2A38);
  static const Color dnText = Color(0xFFE8E8F0);
  static const Color dnSubText = Color(0xFF8888A8);
  static const Color dnAccent = Color(0xFF007AFF);
  static const Color dnSuccess = Color(0xFF30D158);
  static const Color dnWarn = Color(0xFFFF9F0A);
  static const Color dnDanger = Color(0xFFFF453A);

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    _loadData();
    _initTray();
    // Refresh status dot every 3 seconds
    _statusTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (mounted) setState(() {});
    });
    // Auto-connect loop: every 8s try internet, go online if connected
    _startAutoConnectLoop();
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    _statusTimer?.cancel();
    _autoConnectTimer?.cancel();
    super.dispose();
  }

  @override
  void onWindowClose() async => await windowManager.hide();

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

    // If the user was online last session, auto-connect will handle reconnection
    if (isOnline && _selectedDrive != null) {
      BackendService.syncConfig().catchError((e) => debugPrint('Auto-sync error: $e'));
    }
  }

  /// Periodically pings the cloud broker. Once internet is reachable AND
  /// the user had a drive set, silently calls _goOnline().
  void _startAutoConnectLoop() {
    _autoConnectTimer = Timer.periodic(const Duration(seconds: 8), (_) async {
      if (_autoConnectDone || !mounted) return;

      final prefs = await SharedPreferences.getInstance();
      final wasOnline = prefs.getBool('is_online') ?? false;
      final hasDrive = _selectedDrive != null;
      final hasToken = (prefs.getString('drivenet_jwt') ?? '').isNotEmpty;

      if (!wasOnline || !hasDrive || !hasToken) return; // nothing to auto-connect

      // Try a lightweight HTTP ping to the broker
      try {
        final client = HttpClient()..connectionTimeout = const Duration(seconds: 4);
        final req = await client.getUrl(Uri.parse('$_brokerUrl/api/health'));
        final resp = await req.close();
        await resp.drain<void>();
        // Broker is reachable — go online silently
        if (resp.statusCode == 200 && mounted && !_isOnline && !_goingOnline) {
          debugPrint('[DriveNet] Internet detected — auto-connecting...');
          _autoConnectDone = true; // only auto-connect once per session
          await _goOnline();
          // Update tray tooltip
          _updateTrayOnlineStatus();
        }
      } catch (_) {
        // Not connected yet — will retry next tick
        debugPrint('[DriveNet] Waiting for internet...');
      }
    });
  }

  void _updateTrayOnlineStatus() {
    try {
      _systemTray.setToolTip(
        _isOnline
            ? 'DriveNet — $_selectedDrive\\ ONLINE'
            : 'DriveNet — Offline',
      );
    } catch (_) {}
  }

  Future<void> _setStartOnBoot(bool enable) async {
    setState(() => _startOnBoot = enable);
    if (enable) {
      await StartupService.enable();
    } else {
      await StartupService.disable();
    }
  }

  Future<void> _goOnline() async {
    if (_selectedDrive == null || _goingOnline) return;
    setState(() => _goingOnline = true);

    try {
      final prefs = await SharedPreferences.getInstance();
      // Ensure trailing backslash is stored
      final driveToStore = _selectedDrive!.endsWith('\\') ? _selectedDrive! : '$_selectedDrive\\';
      await prefs.setString('selected_drive', driveToStore);
      await prefs.setBool('is_online', true);

      // Connect WebSocket tunnel to cloud
      await BackendService.syncConfig();

      // Register drive → email association on backend (email is the key)
      final token = prefs.getString('drivenet_jwt') ?? '';
      final driveToRegister = _selectedDrive != null && !_selectedDrive!.endsWith('\\') 
          ? '$_selectedDrive\\' 
          : _selectedDrive;
      try {
        final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
        final req = await client.postUrl(Uri.parse('$_brokerUrl/api/fs/me/register-drive'));
        req.headers.set('Authorization', 'Bearer $token');
        req.headers.set('Content-Type', 'application/json');
        req.write('{"drive":"$driveToRegister"}');
        final response = await req.close();
        final responseBody = await response.transform(utf8.decoder).join();
        debugPrint('[DriveNet] Drive registration response: ${response.statusCode} - $responseBody');
      } catch (e) {
        debugPrint('[DriveNet] Drive registration error: $e');
      }

      setState(() { _isOnline = true; _goingOnline = false; });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('✓ $_selectedDrive\\ is now YOUR cloud drive — access it from anywhere',
              style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
          backgroundColor: dnSuccess,
          duration: const Duration(seconds: 4),
        ));
      }
    } catch (e) {
      setState(() => _goingOnline = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error: $e', style: const TextStyle(color: Colors.white)), 
          backgroundColor: dnDanger,
        ));
      }
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
      await windowManager.show();
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (route) => false,
      );
    }
  }

  Future<void> _initTray() async {
    try {
      await _systemTray.initSystemTray(title: 'DriveNet', iconPath: 'assets/icon.ico');
      final menu = Menu();
      await menu.buildFrom([
        MenuItemLabel(label: 'DriveNet Agent', enabled: false),
        MenuSeparator(),
        MenuItemLabel(label: 'Show Window', onClicked: (_) => _appWindow.show()),
        MenuItemLabel(label: 'Go Offline', onClicked: (_) => _goOffline()),
        MenuItemLabel(label: 'Logout', onClicked: (_) => _handleLogout()),
        MenuItemLabel(label: 'Exit', onClicked: (_) { windowManager.destroy(); exit(0); }),
      ]);
      await _systemTray.setContextMenu(menu);
      _systemTray.registerSystemTrayEventHandler((ev) {
        if (ev == kSystemTrayEventClick) _appWindow.show();
        if (ev == kSystemTrayEventRightClick) _systemTray.popUpContextMenu();
      });
    } catch (e) { debugPrint('Tray skipped: $e'); }
  }

  // ─── BUILD ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: dnBg,
      body: Stack(children: [
        Column(children: [
          _buildTitleBar(),
          Expanded(child: _buildBody()),
        ]),
        // Window drag region
        Positioned(
          top: 0, left: 0, right: 0,
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onPanStart: (_) => windowManager.startDragging(),
            child: const SizedBox(height: 44),
          ),
        ),
      ]),
    );
  }

  Widget _buildTitleBar() {
    return Container(
      height: 44,
      color: dnSurface,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(children: [
        Container(
          width: 24, height: 24,
          decoration: BoxDecoration(color: dnAccent, borderRadius: BorderRadius.circular(6)),
          child: const Center(child: Icon(Icons.cloud_sync_rounded, color: Colors.white, size: 14)),
        ),
        const SizedBox(width: 10),
        const Text('DRIVENET', style: TextStyle(color: dnText, fontWeight: FontWeight.bold, fontSize: 13, letterSpacing: 1.5)),
        const SizedBox(width: 6),
        const Text('AGENT', style: TextStyle(color: dnSubText, fontSize: 10, letterSpacing: 1.5)),
        const Spacer(),
        // Status dot
        if (_isOnline) ...[
          Container(
            width: 8, height: 8,
            decoration: BoxDecoration(
              color: _isConnected ? dnSuccess : dnWarn,
              borderRadius: BorderRadius.circular(4),
              boxShadow: [BoxShadow(color: (_isConnected ? dnSuccess : dnWarn).withValues(alpha: 0.5), blurRadius: 4)],
            ),
          ),
          const SizedBox(width: 6),
          Text(_isConnected ? 'ONLINE' : 'CONNECTING...', style: TextStyle(
            color: _isConnected ? dnSuccess : dnWarn,
            fontSize: 9, letterSpacing: 1.5, fontWeight: FontWeight.bold,
          )),
          const SizedBox(width: 16),
        ],
        InkWell(
          onTap: () => windowManager.hide(),
          child: Container(
            width: 28, height: 24,
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(4)),
            child: const Center(child: Text('─', style: TextStyle(color: dnSubText, fontSize: 12))),
          ),
        ),
        const SizedBox(width: 4),
        InkWell(
          onTap: () => windowManager.hide(),
          hoverColor: dnDanger.withValues(alpha: 0.1),
          child: Container(
            width: 28, height: 24,
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(4)),
            child: const Center(child: Text('✕', style: TextStyle(color: dnSubText, fontSize: 11))),
          ),
        ),
      ]),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(color: dnAccent));
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // ── User identity ──────────────────────────────────────────────
        _buildUserCard(),
        const SizedBox(height: 32),

        // ── Drive selection ────────────────────────────────────────────
        const Text('AVAILABLE DRIVES', style: TextStyle(
          color: dnSubText, fontSize: 11, letterSpacing: 2, fontWeight: FontWeight.bold,
        )),
        const SizedBox(height: 12),
        if (_drives.isEmpty)
          _buildNoDrives()
        else
          ..._drives.map((d) => _buildDriveCard(d)),
        const SizedBox(height: 24),

        // ── GO ONLINE button ───────────────────────────────────────────
        _buildActionButton(),
        const SizedBox(height: 24),

        // ── Active session info (shows when online) ────────────────────
        if (_isOnline) _buildStatusPanel(),
        if (_isOnline) const SizedBox(height: 16),

        // ── Help text ──────────────────────────────────────────────────
        if (!_isOnline)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: dnSurface,
              border: Border.all(color: dnBorder),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Icon(Icons.info_outline, color: dnSubText, size: 20),
              const SizedBox(width: 12),
              Expanded(child: Text(
                'After going online, open ${_brokerUrl.replaceAll('https://cloud-usb.onrender.com', 'your web app')} in any browser on any network. Log in with the same Google account to securely access your drive.',
                style: const TextStyle(color: dnSubText, fontSize: 12, height: 1.5),
              )),
            ]),
          ),
      ]),
    );
  }

  Widget _buildUserCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: dnSurface,
        border: Border.all(color: dnBorder),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(children: [
        Container(
          width: 48, height: 48,
          decoration: BoxDecoration(
            color: dnAccent.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(24),
          ),
          child: const Center(child: Icon(Icons.person_rounded, color: dnAccent, size: 24)),
        ),
        const SizedBox(width: 16),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(_userEmail.split('@')[0], style: const TextStyle(color: dnText, fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(_userEmail, style: const TextStyle(color: dnSubText, fontSize: 13)),
        ])),
        // Logout
        InkWell(
          onTap: _handleLogout,
          borderRadius: BorderRadius.circular(8),
          hoverColor: dnDanger.withValues(alpha: 0.1),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(children: [
              const Icon(Icons.logout_rounded, color: dnSubText, size: 16),
              const SizedBox(width: 6),
              const Text('Logout', style: TextStyle(color: dnSubText, fontSize: 12, fontWeight: FontWeight.w500)),
            ]),
          ),
        ),
      ]),
    );
  }

  Widget _buildDriveCard(Map<String, dynamic> drive) {
    final name = drive['name'] as String;
    final label = (drive['label'] as String?) ?? name;
    final usedGb = (drive['usedGb'] as num).toDouble();
    final totalGb = (drive['totalGb'] as num).toDouble();
    final pct = totalGb > 0 ? (usedGb / totalGb) : 0.0;
    final isSelected = _selectedDrive == name;
    final isLive = _isOnline && isSelected;

    return GestureDetector(
      onTap: () async {
        setState(() => _selectedDrive = name);
        final prefs = await SharedPreferences.getInstance();
        final driveWithBackslash = name.endsWith('\\') ? name : '$name\\';
        await prefs.setString('selected_drive', driveWithBackslash);
        
        // Update active drive on backend so web/mobile see this selection
        final token = prefs.getString('drivenet_jwt') ?? '';
        try {
          final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
          final req = await client.postUrl(Uri.parse('$_brokerUrl/api/fs/me/set-active-drive'));
          req.headers.set('Authorization', 'Bearer $token');
          req.headers.set('Content-Type', 'application/json');
          req.write('{"drive":"$driveWithBackslash"}');
          await req.close();
        } catch (e) {
          debugPrint('[DriveNet] Set active drive error: $e');
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: isSelected ? dnAccent.withValues(alpha: 0.05) : dnSurface,
          border: Border.all(
            color: isSelected ? dnAccent : dnBorder,
            width: isSelected ? 1.5 : 1,
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: isSelected ? [BoxShadow(color: dnAccent.withValues(alpha: 0.1), blurRadius: 12)] : null,
        ),
        child: Row(children: [
          Container(
            width: 48, height: 48,
            decoration: BoxDecoration(
              color: isSelected ? dnAccent : dnBg,
              borderRadius: BorderRadius.circular(12),
              border: isSelected ? null : Border.all(color: dnBorder),
            ),
            child: Center(child: Icon(Icons.storage_rounded, color: isSelected ? Colors.white : dnSubText, size: 24)),
          ),
          const SizedBox(width: 16),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text(label, style: const TextStyle(color: dnText, fontWeight: FontWeight.bold, fontSize: 15)),
              const SizedBox(width: 12),
              if (isLive) _chip('LIVE TUNNEL', dnSuccess),
              if (isSelected && !isLive) _chip('SELECTED', dnAccent),
            ]),
            const SizedBox(height: 6),
            Text('${usedGb.toStringAsFixed(1)} GB used of ${totalGb.toStringAsFixed(1)} GB',
                style: const TextStyle(color: dnSubText, fontSize: 12)),
            const SizedBox(height: 12),
            // Storage bar
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: SizedBox(
                height: 4,
                child: LinearProgressIndicator(
                  value: pct.clamp(0.0, 1.0),
                  backgroundColor: dnBg,
                  color: isSelected ? dnAccent : dnSubText.withValues(alpha: 0.5),
                ),
              ),
            ),
          ])),
        ]),
      ),
    );
  }

  Widget _chip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Text(label, style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
    );
  }

  Widget _buildActionButton() {
    return SizedBox(
      width: double.infinity,
      child: _isOnline
          ? Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _goOffline,
                  icon: const Icon(Icons.power_settings_new_rounded, size: 18),
                  label: const Text('GO OFFLINE', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    side: const BorderSide(color: dnBorder),
                    foregroundColor: dnSubText,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: ElevatedButton.icon(
                  onPressed: _selectedDrive != null ? _goOnline : null,
                  icon: Icon(_isConnected ? Icons.cloud_done_rounded : Icons.sync_rounded, size: 18, color: Colors.white),
                  label: Text(
                    _isConnected ? 'DRIVE ONLINE' : 'RECONNECTING...',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600, fontSize: 14,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _isConnected ? dnSuccess : dnWarn,
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    elevation: 0,
                  ),
                ),
              ),
            ])
          : ElevatedButton.icon(
              onPressed: (_selectedDrive == null || _goingOnline) ? null : _goOnline,
              icon: _goingOnline
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Icon(Icons.public_rounded, size: 20, color: Colors.white),
              label: Text(
                _goingOnline ? 'CONNECTING...' : 'GO ONLINE',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: dnAccent,
                disabledBackgroundColor: dnBg,
                padding: const EdgeInsets.symmetric(vertical: 20),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                elevation: 0,
              ),
            ),
    );
  }

  Widget _buildStatusPanel() {
    final webUrl = _brokerUrl.contains('onrender.com')
        ? 'https://cloud-usb.vercel.app'
        : _brokerUrl;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: dnSuccess.withValues(alpha: 0.05),
        border: Border.all(color: dnSuccess.withValues(alpha: 0.2), width: 1.5),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 10, height: 10,
            decoration: BoxDecoration(
              color: dnSuccess,
              shape: BoxShape.circle,
              boxShadow: const [BoxShadow(color: dnSuccess, blurRadius: 10)],
            ),
          ),
          const SizedBox(width: 12),
          const Text('SECURE TUNNEL ACTIVE', style: TextStyle(
            color: dnSuccess, fontSize: 11, letterSpacing: 1.5, fontWeight: FontWeight.bold,
          )),
        ]),
        const SizedBox(height: 20),
        const Divider(color: dnBorder, height: 1),
        const SizedBox(height: 20),

        _statusRow(Icons.account_circle_rounded, 'ACCOUNT', _userEmail, dnAccent,
            subtitle: 'Gmail authenticating this tunnel'),
        const SizedBox(height: 16),

        _statusRow(Icons.storage_rounded, 'DRIVE SERVING', _selectedDrive != null ? '$_selectedDrive\\' : '—',
            dnText, subtitle: 'Currently mounted and accessible'),
        const SizedBox(height: 16),

        _statusRow(Icons.cloud_done_rounded, 'BROKER', _isConnected ? 'Connected via WebSocket' : 'Connecting...',
            _isConnected ? dnSuccess : dnWarn, subtitle: _brokerUrl),
        const SizedBox(height: 16),

        _statusRow(Icons.open_in_browser_rounded, 'WEB ACCESS', webUrl,
            dnAccent, subtitle: 'Open this URL in any browser to access files'),
        const SizedBox(height: 20),
        const Divider(color: dnBorder, height: 1),
        const SizedBox(height: 20),

        // Start on Boot toggle
        Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          Container(
            width: 40, height: 40,
            decoration: BoxDecoration(color: dnBg, borderRadius: BorderRadius.circular(10), border: Border.all(color: dnBorder)),
            child: const Center(child: Icon(Icons.power_settings_new_rounded, color: dnText, size: 20)),
          ),
          const SizedBox(width: 16),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Start on Boot', style: TextStyle(color: dnText, fontSize: 13, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(
              _startOnBoot ? 'Agent will auto-start globally' : 'Disabled (manual launch)',
              style: const TextStyle(color: dnSubText, fontSize: 11),
            ),
          ])),
          Switch(
            value: _startOnBoot,
            onChanged: _setStartOnBoot,
            activeColor: dnAccent,
            inactiveTrackColor: dnBg,
          ),
        ]),
      ]),
    );
  }

  Widget _statusRow(IconData icon, String label, String value, Color color, {String? subtitle}) {
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        width: 36, height: 36,
        decoration: BoxDecoration(color: dnBg, borderRadius: BorderRadius.circular(8), border: Border.all(color: dnBorder)),
        child: Center(child: Icon(icon, color: color, size: 18)),
      ),
      const SizedBox(width: 16),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: const TextStyle(color: dnSubText, fontSize: 9, letterSpacing: 1.5, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Text(value, style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.bold)),
        if (subtitle != null) ...[
          const SizedBox(height: 2),
          Text(subtitle, style: const TextStyle(color: dnSubText, fontSize: 11)),
        ],
      ])),
    ]);
  }

  Widget _buildNoDrives() {
    return Container(
      padding: const EdgeInsets.all(40),
      decoration: BoxDecoration(color: dnSurface, border: Border.all(color: dnBorder), borderRadius: BorderRadius.circular(16)),
      child: Center(child: Column(children: [
        const Icon(Icons.storage_rounded, size: 48, color: dnBorder),
        const SizedBox(height: 16),
        const Text('No drives detected', style: TextStyle(color: dnSubText, fontSize: 14)),
        const SizedBox(height: 16),
        OutlinedButton(
          onPressed: _loadData,
          style: OutlinedButton.styleFrom(side: const BorderSide(color: dnAccent), foregroundColor: dnAccent),
          child: const Text('Refresh'),
        ),
      ])),
    );
  }

}
