import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';
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
  HttpServer? _callbackServer;

  final _dashboardController = TextEditingController(text: 'https://cloud-usb.vercel.app');

  @override
  void initState() {
    super.initState();
    _loadSavedUrls();
  }

  Future<void> _loadSavedUrls() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _dashboardController.text = prefs.getString('dashboard_url') ?? 'https://cloud-usb.vercel.app';
      });
    }
  }

  @override
  void dispose() {
    _callbackServer?.close(force: true);
    super.dispose();
  }

  Future<void> _startGoogleSignIn() async {
    setState(() => _isLoading = true);

    try {
      await _callbackServer?.close(force: true);
      _callbackServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 9292);
      
      final dashboardUrl = _dashboardController.text.trim().replaceAll(RegExp(r'/$'), '');
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('dashboard_url', dashboardUrl);

      final loginUrl = Uri.parse('$dashboardUrl/login?agent=true');
      await launchUrl(loginUrl, mode: LaunchMode.externalApplication);

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
            
            await prefs.setString('drivenet_jwt', token);
            await prefs.setString('drivenet_user', user ?? 'user');

            if (mounted) {
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => const DriveScreen()),
                (route) => false,
              );
            }
            break;
          }
        } else if (request.method == 'OPTIONS') {
          request.response
            ..headers.add('Access-Control-Allow-Origin', '*')
            ..headers.add('Access-Control-Allow-Methods', 'POST, GET, OPTIONS')
            ..headers.add('Access-Control-Allow-Headers', 'Content-Type')
            ..statusCode = 200;
          await request.response.close();
        }
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent, // Allow for window transparency
      body: Stack(
        children: [
          // Ambient Glow Background
          Positioned.fill(
            child: Container(
              color: const Color(0xFF131318),
              child: Stack(
                children: [
                   Positioned(
                    top: -100,
                    right: -50,
                    child: Container(
                      width: 400,
                      height: 400,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: const Color(0xFF6366F1).withValues(alpha: 0.08),
                      ),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 80, sigmaY: 80),
                        child: Container(color: Colors.transparent),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Draggable area
          Positioned(
            top: 0, left: 0, right: 0,
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onPanStart: (_) {},
              child: const SizedBox(height: 40),
            ),
          ),

          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 40),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Brand Header
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [const Color(0xFF6366F1), const Color(0xFF4F46E5)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(18),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF6366F1).withValues(alpha: 0.3),
                          blurRadius: 20,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: const Icon(Icons.cloud_upload_rounded, color: Colors.white, size: 32),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'Indigo Vault Agent',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                      letterSpacing: -1,
                    ),
                  ),
                  const Text(
                    'PRIVATE CLOUD GATEWAY',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF818CF8),
                      letterSpacing: 2,
                    ),
                  ),
                  const SizedBox(height: 48),

                  // Glass Portal Card
                  ClipRRect(
                    borderRadius: BorderRadius.circular(28),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                      child: Container(
                        width: 380,
                        padding: const EdgeInsets.all(32),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1F1F25).withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(28),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (_isLoading) ...[
                              const Center(
                                child: Column(
                                  children: [
                                    SizedBox(
                                      width: 48,
                                      height: 48,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 3,
                                        valueColor: AlwaysStoppedAnimation(Color(0xFF6366F1)),
                                      ),
                                    ),
                                    SizedBox(height: 24),
                                    Text(
                                      'Awaiting Secure Gateway...',
                                      style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                                    ),
                                    SizedBox(height: 8),
                                    Text(
                                      'Please complete sign-in in your browser',
                                      style: TextStyle(color: Color(0xFF908FA0), fontSize: 11),
                                    ),
                                  ],
                                ),
                              ),
                            ] else ...[
                              ElevatedButton(
                                onPressed: _startGoogleSignIn,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF6366F1),
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(vertical: 20),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                  elevation: 8,
                                  shadowColor: const Color(0xFF6366F1).withValues(alpha: 0.5),
                                ),
                                child: const Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.vpn_key_rounded, size: 20),
                                    SizedBox(width: 12),
                                    Text(
                                      'Authorize Machine',
                                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900, letterSpacing: 0.5),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 24),
                              const Text(
                                'DASHBOARD ENDPOINT',
                                style: TextStyle(fontSize: 9, fontWeight: FontWeight.w900, color: Color(0xFF908FA0), letterSpacing: 1.5),
                              ),
                              const SizedBox(height: 8),
                              TextField(
                                controller: _dashboardController,
                                style: const TextStyle(color: Colors.white, fontSize: 12),
                                decoration: InputDecoration(
                                  isDense: true,
                                  filled: true,
                                  fillColor: Colors.black.withValues(alpha: 0.2),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide.none,
                                  ),
                                  prefixIcon: const Icon(Icons.language_rounded, size: 16, color: Color(0xFF908FA0)),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                  
                  const SizedBox(height: 48),
                  Opacity(
                    opacity: 0.4,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.shield_rounded, size: 12, color: Color(0xFF908FA0)),
                        const SizedBox(width: 8),
                        const Text(
                          'END-TO-END TUNNEL ACTIVE',
                          style: TextStyle(fontSize: 9, fontWeight: FontWeight.w900, color: Color(0xFF908FA0), letterSpacing: 1.5),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Window Controls
          Positioned(
            top: 12, right: 16,
            child: IconButton(
              icon: const Icon(Icons.close_rounded, size: 20, color: Color(0xFF908FA0)),
              onPressed: () => exit(0),
              splashRadius: 20,
            ),
          ),
        ],
      ),
    );
  }
}
