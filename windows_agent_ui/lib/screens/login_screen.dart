import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'drive_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _isLoading = false;
  String _statusText = 'PERIPHERAL DATA ACCESS REQUIRED';
  String _statusCode = '// AUTH_PENDING';
  HttpServer? _callbackServer;

  final _dashboardController = TextEditingController(text: 'https://cloud-usb.vercel.app');
  final _brokerController = TextEditingController(text: 'https://cloud-usb.onrender.com');

  @override
  void initState() {
    super.initState();
    _loadSavedUrls();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startGoogleSignIn();
    });
  }

  Future<void> _loadSavedUrls() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _dashboardController.text = prefs.getString('dashboard_url') ?? 'https://cloud-usb.vercel.app';
        _brokerController.text = prefs.getString('broker_url') ?? 'https://cloud-usb.onrender.com';
      });
    }
  }

  @override
  void dispose() {
    _callbackServer?.close(force: true);
    super.dispose();
  }

  Future<void> _startGoogleSignIn() async {
    setState(() {
      _isLoading = true;
      _statusText = 'LAUNCHING AUTH GATEWAY...';
      _statusCode = '// CONNECTING';
    });

    try {
      // Start local callback server on 5173 redirect
      await _callbackServer?.close(force: true);
      _callbackServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 9292);
      
      // Open the web frontend login page in the browser
      // The web frontend will handle the Google OAuth and save the JWT to localStorage
      // We redirect the user to a special deep-link URL that our local server will intercept
      
      final dashboardUrl = _dashboardController.text.trim().replaceAll(RegExp(r'/$'), '');
      final brokerUrl = _brokerController.text.trim().replaceAll(RegExp(r'/$'), '');
      
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('dashboard_url', dashboardUrl);
      await prefs.setString('broker_url', brokerUrl);

      final loginUrl = Uri.parse('$dashboardUrl/login?agent=true');
      await launchUrl(loginUrl, mode: LaunchMode.externalApplication);

      setState(() {
        _statusText = 'BROWSER OPENED — SIGN IN WITH GOOGLE';
        _statusCode = '// AWAITING_RESPONSE';
      });

      // Listen for callback — the web frontend will POST the JWT token to our local server
      await for (final request in _callbackServer!) {
        if (request.method == 'POST' && request.uri.path == '/token') {
          final body = await utf8.decoder.bind(request).join();
          final data = jsonDecode(body) as Map<String, dynamic>;
          
          final token = data['token'] as String?;
          final user = data['user'] as String?;

          if (token != null && token.isNotEmpty) {
            request.response
              ..headers.add('Access-Control-Allow-Origin', '*')
              ..statusCode = 200
              ..write('{"status":"ok"}');
            await request.response.close();
            await _callbackServer!.close(force: true);
            
            // Save session to prefs
            final prefs = await SharedPreferences.getInstance();
            await prefs.setString('drivenet_jwt', token);
            await prefs.setString('drivenet_user', user ?? 'user');

            if (mounted) {
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => const DriveScreen()),
                (route) => false,
              );
            }
            break;
          } else {
            request.response
              ..statusCode = 400
              ..write('{"error":"no token"}');
            await request.response.close();
          }
        } else if (request.method == 'OPTIONS') {
          // CORS preflight
          request.response
            ..headers.add('Access-Control-Allow-Origin', '*')
            ..headers.add('Access-Control-Allow-Methods', 'POST, GET, OPTIONS')
            ..headers.add('Access-Control-Allow-Headers', 'Content-Type')
            ..statusCode = 200;
          await request.response.close();
        } else {
          request.response.statusCode = 404;
          await request.response.close();
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _statusText = 'CONNECTION FAILED — ${e.runtimeType}';
          _statusCode = '// ERROR';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F14), // dn-bg
      body: Stack(
        children: [
          // Drag handle for frameless window
          Positioned(
            top: 0, left: 0, right: 0,
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onPanStart: (_) {},
              child: const SizedBox(height: 40),
            ),
          ),
          
          // Background Glow
          Center(
            child: Container(
              width: 500,
              height: 500,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    const Color(0xFF007AFF).withValues(alpha: 0.1),
                    Colors.transparent,
                  ],
                  stops: const [0.0, 0.7],
                ),
              ),
            ),
          ),

          // Main Layout
          Center(
            child: SizedBox(
              width: 420,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Logo
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF007AFF), Color(0xFF0055CC)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF007AFF).withValues(alpha: 0.35),
                          blurRadius: 24,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: const Center(
                      child: Icon(Icons.cloud_upload_rounded, color: Colors.white, size: 36),
                    ),
                  ),
                  const SizedBox(height: 24),
                  
                  const Text(
                    'DriveNet',
                    style: TextStyle(
                      color: Color(0xFFE8E8F0),
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Agent authentication required',
                    style: TextStyle(
                      color: Color(0xFF8888A8),
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 48),

                  // Login Card
                  Container(
                    padding: const EdgeInsets.all(32),
                    decoration: BoxDecoration(
                      color: const Color(0xFF16161D), // dn-surface
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: const Color(0xFF2A2A38)), // dn-border
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.3),
                          blurRadius: 40,
                          offset: const Offset(0, 16),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        if (_isLoading)
                          Container(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            child: const Column(
                              children: [
                                SizedBox(
                                  width: 24, height: 24,
                                  child: CircularProgressIndicator(color: Color(0xFF007AFF), strokeWidth: 2),
                                ),
                                SizedBox(height: 16),
                                Text(
                                  'Awaiting browser authentication...',
                                  style: TextStyle(color: Color(0xFF8888A8), fontSize: 13, fontWeight: FontWeight.w500),
                                ),
                              ],
                            ),
                          )
                        else
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: _startGoogleSignIn,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFFE8E8F0), // White-ish button
                                foregroundColor: const Color(0xFF0F0F14), // Dark text
                                padding: const EdgeInsets.symmetric(vertical: 16),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                elevation: 0,
                              ),
                              child: const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.g_mobiledata_rounded, size: 28),
                                  SizedBox(width: 8),
                                  Text(
                                    'Continue with Google',
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        const SizedBox(height: 24),
                        const Divider(color: Color(0xFF2A2A38)),
                        const SizedBox(height: 24),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: const Color(0xFF007AFF).withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(Icons.sync_rounded, color: Color(0xFF007AFF), size: 16),
                            ),
                            const SizedBox(width: 16),
                            const Expanded(
                              child: Text(
                                'This local agent runs constantly in the background. It negotiates end-to-end encrypted tunnels automatically after auth.',
                                style: TextStyle(color: Color(0xFF8888A8), fontSize: 11, height: 1.5),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Top Window Controls
          Positioned(
            top: 12, right: 16,
            child: IconButton(
              icon: const Icon(Icons.close_rounded, size: 20, color: Color(0xFF8888A8)),
              onPressed: () async {
                await _callbackServer?.close(force: true);
                exit(0);
              },
              hoverColor: const Color(0xFFFF453A).withValues(alpha: 0.1), // dn-danger
              highlightColor: const Color(0xFFFF453A).withValues(alpha: 0.2),
              tooltip: 'Exit',
            ),
          ),
        ],
      ),
    );
  }
}
