import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../auth/login.dart';
// Import your home/main screen here
// import '../screens/home_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scaleAnimation;
  late final Animation<double> _fadeAnimation;
  late final Animation<double> _textFadeAnimation;
  Timer? _timer;

  // Sakinah brand color
  static const Color _primaryColor = Color(0xFF15803D);
  static const Color _circleBackground = Color(0xFFF7F4EF);

  @override
  void initState() {
    super.initState();
    _setupAnimations();
    _startNavigationTimer();
  }

  void _setupAnimations() {
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );

    // Logo scale animation with bounce effect
    _scaleAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutBack,
    );

    // Logo fade animation (starts slightly after scale)
    _fadeAnimation = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.2, 0.8, curve: Curves.easeIn),
    );

    // Text fade animation (appears after logo)
    _textFadeAnimation = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.5, 1.0, curve: Curves.easeIn),
    );

    _controller.forward();
  }

  void _startNavigationTimer() {
    // Wait for animation to complete + small buffer
    _timer = Timer(
      const Duration(milliseconds: 2000),
      _checkAuthAndNavigate,
    );
  }

  Future<void> _checkAuthAndNavigate() async {
    if (!mounted) return;

    try {
      // Check if user is already logged in
      final user = FirebaseAuth.instance.currentUser;
      
      // Add a small delay to ensure smooth transition
      await Future.delayed(const Duration(milliseconds: 100));
      
      if (!mounted) return;

      if (user != null) {
        // User is logged in - go to home screen
        // Uncomment and use your actual home screen
        // _navigateToScreen(const HomeScreen());
        
        // For now, still go to login (remove this when home screen is ready)
        _navigateToScreen(const LoginPage());
      } else {
        // User not logged in - go to login
        _navigateToScreen(const LoginPage());
      }
    } catch (e) {
      // If error checking auth, default to login screen
      if (mounted) {
        _navigateToScreen(const LoginPage());
      }
    }
  }

  void _navigateToScreen(Widget screen) {
    if (!mounted) return;
    
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 600),
        pageBuilder: (_, __, ___) => screen,
        transitionsBuilder: (_, animation, __, child) {
          final curved = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
          );
          return FadeTransition(
            opacity: curved,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 0.05),
                end: Offset.zero,
              ).animate(curved),
              child: child,
            ),
          );
        },
      ),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    final isSmallScreen = screenHeight < 700;

    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: ScaleTransition(
            scale: _scaleAnimation,
            child: _buildLogoSection(isSmallScreen, screenWidth, screenHeight),
          ),
        ),
      ),
    );
  }

  Widget _buildLogoSection(bool isSmallScreen, double screenWidth, double screenHeight) {
    // Responsive sizing based on screen dimensions
    final double logoSize;
    
    if (screenWidth < 360) {
      // Very small phones
      logoSize = screenWidth * 0.55;
    } else if (screenWidth < 400) {
      // Small phones
      logoSize = screenWidth * 0.6;
    } else if (screenHeight < 700) {
      // Medium phones with short height
      logoSize = screenWidth * 0.65;
    } else {
      // Larger phones and tablets
      logoSize = screenWidth * 0.7;
    }
    
    return SizedBox(
      width: logoSize,
      height: logoSize,
      child: Image.asset(
        'assets/images/sakina_logo.png',
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) {
          // Fallback if image fails to load
          return Icon(
            Icons.spa,
            size: logoSize * 0.6,
            color: _primaryColor,
          );
        },
      ),
    );
  }
}