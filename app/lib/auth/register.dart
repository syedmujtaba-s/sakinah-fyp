import 'dart:async';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

// --- CUSTOM IMPORTS ---
import '../widgets/custom_text_field.dart';
import '../widgets/google_button.dart';
import '../widgets/offline_banner.dart';
import '../services/authService.dart';
import '../screens/profile/terms_screen.dart';
import '../screens/profile/privacy_screen.dart';

class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final _formKey = GlobalKey<FormState>();
  
  // Controllers
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  // State
  bool _isLoading = false;
  bool _showPassword = false;
  bool _showConfirmPassword = false;
  bool _termsAccepted = false;
  bool _termsError = false;
  bool _isEmailValid = false;
  String? _errorMessage;
  
  // Connectivity
  bool _noInternet = false;
  late final Connectivity _connectivity;
  late final StreamSubscription<List<ConnectivityResult>> _connectivitySubscription;

  // --- STRICT REGEX from Friend's Code ---
  static final RegExp _basicEmailRegex = RegExp(r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$');
  
  // Strict Domain List
  static final RegExp _allowedEmailDomainsRegex = RegExp(
    r'^[a-zA-Z0-9._%+-]+@(gmail\.com|yahoo\.com|outlook\.com|hotmail\.com|icloud\.com|me\.com|mac\.com)$',
    caseSensitive: false,
  );
  
  static final RegExp _passwordRegex = RegExp(
    r'^(?=.*[A-Z])(?=.*\d)(?=.*[!@#$%^&*()_+{}\[\]:;<>,.?~\\/-]).{6,}$',
  );

  @override
  void initState() {
    super.initState();
    _emailController.addListener(_validateEmail);
    _connectivity = Connectivity();
    _checkInitialConnectivity();
    _connectivitySubscription = _connectivity.onConnectivityChanged.listen((results) {
      final offline = results.isEmpty || results.every((r) => r == ConnectivityResult.none);
      if (mounted) setState(() => _noInternet = offline);
    });
  }

  Future<void> _checkInitialConnectivity() async {
    final results = await _connectivity.checkConnectivity();
    if (mounted) {
      setState(() => _noInternet = results.isEmpty || results.every((r) => r == ConnectivityResult.none));
    }
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _connectivitySubscription.cancel();
    super.dispose();
  }

  void _validateEmail() {
    final email = _emailController.text.trim().toLowerCase();
    setState(() {
      if (!_basicEmailRegex.hasMatch(email)) {
        _isEmailValid = false;
        return;
      }
      _isEmailValid = _allowedEmailDomainsRegex.hasMatch(email);
    });
  }

  // --- Strict Email Error Message ---
  String? _getEmailValidationError(String email) {
    final trimmed = email.trim().toLowerCase();
    if (trimmed.isEmpty) return 'Email is required';
    if (!_basicEmailRegex.hasMatch(trimmed)) return 'Invalid email format';
    if (!_allowedEmailDomainsRegex.hasMatch(trimmed)) {
      return 'Only Gmail, Yahoo, Outlook, or iCloud allowed';
    }
    return null;
  }

  // --- Strict Name Validation (Must start with Capital) ---
  String? _validateName(String? value, String label) {
    if (value == null || value.trim().isEmpty) return '$label is required';
    if (!RegExp(r'^[A-Z][a-zA-Z]*$').hasMatch(value.trim())) {
      return '$label must start with a Capital letter';
    }
    return null;
  }

  Future<void> _registerWithEmail() async {
    setState(() {
      _errorMessage = null;
      _isLoading = true;
      _termsError = false;
    });

    if (_noInternet) {
      setState(() { _errorMessage = "No internet connection."; _isLoading = false; });
      return;
    }
    if (!_termsAccepted) {
      setState(() { _termsError = true; _isLoading = false; });
      return;
    }
    if (!_formKey.currentState!.validate()) {
      setState(() => _isLoading = false);
      return;
    }

    final authService = AuthService();
    final error = await authService.registerWithEmail(
      firstName: _firstNameController.text.trim(),
      lastName: _lastNameController.text.trim(),
      email: _emailController.text.trim(),
      password: _passwordController.text.trim(),
    );

    if (error == null) {
      if (!mounted) return;
      Navigator.pop(context); // Success -> Go back to login
    } else {
      setState(() {
        _errorMessage = error;
        _isLoading = false;
      });
    }
  }

  Future<void> _handleGoogleSignIn() async {
    setState(() {
      _errorMessage = null;
      _isLoading = true;
      _termsError = false;
    });

    if (_noInternet) {
      setState(() { _errorMessage = "No internet connection."; _isLoading = false; });
      return;
    }
    if (!_termsAccepted) {
      setState(() { _termsError = true; _isLoading = false; });
      return;
    }

    final authService = AuthService();
    final error = await authService.signInWithGoogle();

    if (error == null) {
      if (!mounted) return;
      Navigator.pop(context); // Success
    } else {
      setState(() {
        _errorMessage = error;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // --- Responsive Math from Friend's Code ---
    final media = MediaQuery.of(context);
    final width = media.size.width;
    final height = media.size.height;
    
    double headingFontSize = width < 360 ? 22 : (width < 400 ? 24 : 26);
    double buttonHeight = (height * 0.06).clamp(48, 56);
    double horizontalPadding = width * 0.06;

    return Scaffold(
      backgroundColor: Colors.white,
      
      body: SafeArea(
        child: Stack(
          children: [
            SingleChildScrollView(
              padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
              child: Form(
                key: _formKey,
                child: Column(
                  children: [
                    const SizedBox(height: 10),
                    // Replaced Logo widget with Icon for simplicity if asset missing
                    Image.asset(
  'assets/images/sakina_logo.png',
  width: 160,
  height: 160,
  fit: BoxFit.contain,
),
                    const SizedBox(height: 0),
                    
                    Text(
                      "Create Account",
                      style: TextStyle(
                        fontSize: headingFontSize,
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFF064E3B),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      "Start your journey to inner peace.",
                      style: TextStyle(fontSize: 15, color: Colors.grey[600]),
                    ),
                    const SizedBox(height: 30),

                    // --- Custom Text Fields ---
                    Row(
                      children: [
                        Expanded(
                          child: CustomTextField(
                            label: "First Name",
                            hint: "Ali",
                            controller: _firstNameController,
                            validator: (val) => _validateName(val, "First Name"),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: CustomTextField(
                            label: "Last Name",
                            hint: "Khan",
                            controller: _lastNameController,
                            validator: (val) => _validateName(val, "Last Name"),
                          ),
                        ),
                      ],
                    ),

                    CustomTextField(
                      label: "Email",
                      hint: "example@gmail.com",
                      controller: _emailController,
                      isEmail: true,
                      isEmailValid: _isEmailValid,
                      validator: (val) => _getEmailValidationError(val ?? ''),
                    ),

                    CustomTextField(
                      label: "Password",
                      hint: "********",
                      controller: _passwordController,
                      isPassword: true,
                      obscure: !_showPassword,
                      toggleCallback: () => setState(() => _showPassword = !_showPassword),
                      helperText: "Min 6 chars, 1 Upper, 1 Number, 1 Special",
                      validator: (val) {
                        if (val == null || val.isEmpty) return "Required";
                        if (!_passwordRegex.hasMatch(val)) return "Password too weak";
                        return null;
                      },
                    ),

                    CustomTextField(
                      label: "Confirm Password",
                      hint: "********",
                      controller: _confirmPasswordController,
                      isPassword: true,
                      obscure: !_showConfirmPassword,
                      toggleCallback: () => setState(() => _showConfirmPassword = !_showConfirmPassword),
                      validator: (val) {
                        if (val != _passwordController.text) return "Passwords do not match";
                        return null;
                      },
                    ),

                    // --- Terms Checkbox ---
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          height: 24, width: 24,
                          child: Checkbox(
                            value: _termsAccepted,
                            activeColor: const Color(0xFF15803D),
                            onChanged: (val) {
                              setState(() {
                                _termsAccepted = val!;
                                if (val) _termsError = false;
                              });
                            },
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: RichText(
                            text: TextSpan(
                              style: const TextStyle(fontSize: 13, color: Colors.black87),
                              children: [
                                const TextSpan(text: "I agree to the "),
                                TextSpan(
                                  text: "Terms",
                                  style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF15803D)),
                                  recognizer: TapGestureRecognizer()..onTap = () => Navigator.push(context, MaterialPageRoute(builder: (_) => const TermsScreen())),
                                ),
                                const TextSpan(text: " and "),
                                TextSpan(
                                  text: "Privacy Policy",
                                  style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF15803D)),
                                  recognizer: TapGestureRecognizer()..onTap = () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PrivacyScreen())),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (_termsError)
                      const Padding(
                        padding: EdgeInsets.only(left: 34, top: 4),
                        child: Text("Please accept terms to continue", style: TextStyle(color: Colors.red, fontSize: 12)),
                      ),

                    if (_errorMessage != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 16),
                        child: Text(
                          _errorMessage!,
                          style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
                          textAlign: TextAlign.center,
                        ),
                      ),

                    const SizedBox(height: 24),

                    // --- Buttons ---
                    SizedBox(
                      width: double.infinity,
                      height: buttonHeight,
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _registerWithEmail,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF15803D),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: _isLoading
                            ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                            : const Text("Register", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      ),
                    ),

                    const SizedBox(height: 16),

                    GoogleButton(
                      text: "Sign up with Google",
                      height: buttonHeight,
                      onPressed: _isLoading ? null : _handleGoogleSignIn,
                    ),

                    const SizedBox(height: 24),
                    
                    // --- Login Link ---
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text("Already have an account? ", style: TextStyle(color: Colors.grey)),
                        GestureDetector(
                          onTap: () => Navigator.pop(context),
                          child: const Text("Log In", style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF15803D))),
                        ),
                      ],
                    ),
                    const SizedBox(height: 40),
                  ],
                ),
               ),
            ),

            // --- Offline Banner ---
            if (_noInternet)
              const Positioned(top: 0, left: 0, right: 0, child: OfflineBanner()),
          ],
        ),
      ),
    );
  }
}