import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../config.dart';
import 'dashboard_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _isLoading = false;
  String _statusText = 'AWAITING AUTHENTICATION';

  // The Native Google Sign-In instance
  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: ['email', 'profile'],
    clientId: '901086875987-nekpj2rk5i3ep4shve7m6nou73qs1gfb.apps.googleusercontent.com',
    serverClientId: '901086875987-462a9467nqo682h4cqne48e1mmgrt5qm.apps.googleusercontent.com',
  );

  Future<void> _handleSignIn() async {
    setState(() {
      _isLoading = true;
      _statusText = 'CONTACTING GOOGLE OAUTH...';
    });

    try {
      final GoogleSignInAccount? account = await _googleSignIn.signIn();
      
      if (account != null) {
        final GoogleSignInAuthentication auth = await account.authentication;
        final String? idToken = auth.idToken;

        if (idToken != null) {
          // Send ID token to backend to get the DriveNet JWT back.
          final response = await http.post(
            Uri.parse('${AppConfig.brokerUrl}/api/auth/login'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'google_token': idToken}),
          );

          if (response.statusCode == 200) {
            final data = jsonDecode(response.body);
            final backendJwt = data['token'];
            final backendUser = data['user'];
            final assignedDrive = data['assigned_drive'];

            final prefs = await SharedPreferences.getInstance();
            await prefs.setString('drivenet_jwt', backendJwt);
            await prefs.setString('drivenet_user', backendUser);
            if (assignedDrive != null) {
              await prefs.setString('drivenet_assigned_drive', assignedDrive);
            }

            if (mounted) {
              Navigator.of(context).pushReplacement(
                MaterialPageRoute(builder: (_) => const DashboardScreen()),
              );
            }
          } else {
            final errBody = jsonDecode(response.body);
            setState(() {
              _statusText = 'SERVER REFUSED AUTH: ${errBody['error'] ?? response.statusCode}';
              _isLoading = false;
            });
            await _googleSignIn.signOut();
          }
        }
      } else {
        setState(() {
          _statusText = 'AUTH CANCELLED';
          _isLoading = false;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _statusText = 'ERROR: $error';
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(40.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.cloud_sync, color: Color(0xFFFF4655), size: 80),
              const SizedBox(height: 20),
              Text(
                'DRIVE NET',
                style: TextStyle(
                  color: isDark ? Colors.white : Colors.black,
                  fontWeight: FontWeight.w900,
                  fontSize: 24,
                  letterSpacing: 2.0,
                ),
              ),
              const SizedBox(height: 60),
              Text(
                _statusText,
                style: const TextStyle(
                  color: Color(0xFFFF4655), 
                  fontFamily: 'Courier', 
                  fontSize: 12, 
                  fontWeight: FontWeight.bold
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator(color: Color(0xFFFF4655)))
                    : ElevatedButton.icon(
                        onPressed: _handleSignIn,
                        icon: Image.network(
                          'https://upload.wikimedia.org/wikipedia/commons/thumb/c/c1/Google_%22G%22_logo.svg/120px-Google_%22G%22_logo.svg.png',
                          width: 20,
                          height: 20,
                          errorBuilder: (_, __, ___) => const Icon(Icons.g_mobiledata, size: 24),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: isDark ? Colors.white : Colors.black,
                          foregroundColor: isDark ? Colors.black : Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                        ),
                        label: const Text(
                          'Sign in by Google',
                          style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 0.5, fontSize: 16),
                        ),
                      ),
              )
            ],
          ),
        ),
      ),
    );
  }
}
