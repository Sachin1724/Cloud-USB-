import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'screens/login_screen.dart';
import 'screens/dashboard_screen.dart';

// Global notifier so any widget can toggle the theme
final ValueNotifier<ThemeMode> themeModeNotifier = ValueNotifier(ThemeMode.dark);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Load saved theme preference
  final prefs = await SharedPreferences.getInstance();
  final isDark = prefs.getBool('drivenet_dark_mode') ?? true;
  themeModeNotifier.value = isDark ? ThemeMode.dark : ThemeMode.light;
  runApp(const DriveNetMobileApp());
}

// ─── THEME CONSTANTS ──────────────────────────────────────────────────────────
const _kAccent = Color(0xFFFF4655);
const _kDarkBg = Color(0xFF0D0D14);
const _kDarkCard = Color(0xFF13131F);
const _kDarkSurface = Color(0xFF1A1A2E);

class DriveNetMobileApp extends StatelessWidget {
  const DriveNetMobileApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeModeNotifier,
      builder: (_, mode, __) => MaterialApp(
        debugShowCheckedModeBanner: false,
        themeMode: mode,
        theme: _buildLightTheme(),
        darkTheme: _buildDarkTheme(),
        home: const AppRouter(),
      ),
    );
  }

  ThemeData _buildLightTheme() {
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: _kAccent,
        brightness: Brightness.light,
        primary: _kAccent,
      ),
      scaffoldBackgroundColor: const Color(0xFFF5F5F7),
      cardColor: Colors.white,
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      drawerTheme: const DrawerThemeData(
        backgroundColor: Colors.white,
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: _kAccent,
        foregroundColor: Colors.white,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(backgroundColor: _kAccent, foregroundColor: Colors.white),
      ),
      dividerColor: Colors.grey.shade200,
    );
  }

  ThemeData _buildDarkTheme() {
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: _kAccent,
        brightness: Brightness.dark,
        primary: _kAccent,
        surface: _kDarkCard,
        onSurface: Colors.white,
      ),
      scaffoldBackgroundColor: _kDarkBg,
      cardColor: _kDarkCard,
      dialogBackgroundColor: _kDarkSurface,
      appBarTheme: const AppBarTheme(
        backgroundColor: _kDarkBg,
        foregroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      drawerTheme: const DrawerThemeData(
        backgroundColor: _kDarkCard,
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: _kDarkSurface,
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: _kAccent,
        foregroundColor: Colors.white,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(backgroundColor: _kAccent, foregroundColor: Colors.white),
      ),
      dividerColor: Colors.white.withValues(alpha: 0.06),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: _kDarkSurface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _kAccent),
        ),
        hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.3)),
      ),
    );
  }
}

class AppRouter extends StatefulWidget {
  const AppRouter({super.key});

  @override
  State<AppRouter> createState() => _AppRouterState();
}

class _AppRouterState extends State<AppRouter> {
  bool _loading = true;
  bool _isLoggedIn = false;

  @override
  void initState() {
    super.initState();
    _checkSession();
  }

  Future<void> _checkSession() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('drivenet_jwt');
    setState(() {
      _isLoggedIn = (token != null && token.isNotEmpty);
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: _kDarkBg,
        body: Center(child: CircularProgressIndicator(color: _kAccent)),
      );
    }
    return _isLoggedIn ? const DashboardScreen() : const LoginScreen();
  }
}
