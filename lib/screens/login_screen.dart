import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../app_theme.dart';
import '../services/auth_service.dart';
import 'dashboard_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final AuthService _authService = AuthService();

  final TextEditingController emailController = TextEditingController();

  final TextEditingController passwordController = TextEditingController();

  final FocusNode _passwordFocus = FocusNode();

  bool isLoading = false;
  bool _obscurePassword = true;

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    _passwordFocus.dispose();

    super.dispose();
  }

  Future<void> signIn() async {
    final email = emailController.text.trim().toLowerCase();

    final password = passwordController.text;

    if (email.isEmpty || password.isEmpty) {
      _message('Please enter email and password.', error: true);

      return;
    }

    setState(() {
      isLoading = true;
    });

    try {
      final portalUser = await _authService.signIn(
        email: email,
        password: password,
      );

      if (!mounted) return;

      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => DashboardScreen(userRole: portalUser.role),
        ),
      );
    } on AuthException catch (e) {
      debugPrint('Auth error: ${e.message}');

      if (!mounted) return;

      _message('Invalid email or password.', error: true);
    } catch (e) {
      debugPrint('Login error: $e');

      if (!mounted) return;

      _message(
        e is StateError ? e.message : 'Unable to sign in. Please try again.',
        error: true,
      );
    } finally {
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    }
  }

  void _message(String value, {bool error = false}) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(value),
        backgroundColor: error ? AppTheme.danger : AppTheme.success,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset('assets/images/school_bg.png', fit: BoxFit.cover),

          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  AppTheme.fgNavyBlue.withValues(alpha: 0.78),
                  AppTheme.navy700.withValues(alpha: 0.70),
                  const Color(0xFF061C3B).withValues(alpha: 0.77),
                ],
              ),
            ),
          ),

          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final wide = constraints.maxWidth >= 900;

                return Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(22),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1050),
                      child: Card(
                        clipBehavior: Clip.antiAlias,
                        child: wide
                            ? SizedBox(
                                height: 590,
                                child: Row(
                                  children: [
                                    Expanded(child: _brandPanel()),
                                    Expanded(child: _loginPanel()),
                                  ],
                                ),
                              )
                            : _loginPanel(mobile: true),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _brandPanel() {
    return Container(
      decoration: const BoxDecoration(gradient: AppTheme.brandGradient),
      padding: const EdgeInsets.all(44),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 108,
            height: 108,
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: AppTheme.fgGold, width: 2),
            ),
            child: Image.asset('assets/images/app_logo_bg.png'),
          ),

          const Spacer(),

          const Text(
            'FG Academy\nPortal',
            style: TextStyle(
              color: Colors.white,
              fontSize: 42,
              height: 1.05,
              fontWeight: FontWeight.w800,
            ),
          ),

          const SizedBox(height: 15),

          const Text(
            'Secure access for academy administrators and teaching staff.',
            style: TextStyle(color: Colors.white70, fontSize: 15, height: 1.5),
          ),

          const SizedBox(height: 23),

          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(30),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.shield_outlined, color: AppTheme.fgGold, size: 19),
                SizedBox(width: 7),
                Text(
                  'Role-Based Secure Access',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _loginPanel({bool mobile = false}) {
    return Container(
      color: Colors.white.withValues(alpha: 0.96),
      padding: EdgeInsets.symmetric(
        horizontal: mobile ? 24 : 43,
        vertical: mobile ? 30 : 42,
      ),
      child: Column(
        mainAxisSize: mobile ? MainAxisSize.min : MainAxisSize.max,
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (mobile) ...[
            Center(
              child: Container(
                width: 84,
                height: 84,
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppTheme.fgGold),
                ),
                child: Image.asset('assets/images/app_logo_bg.png'),
              ),
            ),
            const SizedBox(height: 18),
          ],

          const Text(
            'Welcome Back',
            style: TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 28,
              fontWeight: FontWeight.w800,
            ),
          ),

          const SizedBox(height: 7),

          const Text(
            'Sign in using your registered academy email.',
            style: TextStyle(color: AppTheme.textSecondary, fontSize: 14),
          ),

          const SizedBox(height: 28),

          TextField(
            controller: emailController,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            autocorrect: false,
            onSubmitted: (_) => _passwordFocus.requestFocus(),
            decoration: const InputDecoration(
              labelText: 'Email Address',
              prefixIcon: Icon(Icons.alternate_email_rounded),
            ),
          ),

          const SizedBox(height: 15),

          TextField(
            controller: passwordController,
            focusNode: _passwordFocus,
            obscureText: _obscurePassword,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) {
              if (!isLoading) {
                signIn();
              }
            },
            decoration: InputDecoration(
              labelText: 'Password',
              prefixIcon: const Icon(Icons.lock_outline_rounded),
              suffixIcon: IconButton(
                onPressed: () {
                  setState(() {
                    _obscurePassword = !_obscurePassword;
                  });
                },
                icon: Icon(
                  _obscurePassword
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                ),
              ),
            ),
          ),

          const SizedBox(height: 21),

          SizedBox(
            height: 51,
            child: ElevatedButton.icon(
              onPressed: isLoading ? null : signIn,
              icon: isLoading
                  ? const SizedBox(
                      width: 19,
                      height: 19,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : const Icon(Icons.login_rounded),
              label: Text(isLoading ? 'Signing In…' : 'Sign In'),
            ),
          ),
        ],
      ),
    );
  }
}
