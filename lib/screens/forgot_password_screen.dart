import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../app_theme.dart';
import '../services/auth_service.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final AuthService _authService = AuthService();

  final _emailController = TextEditingController();
  final _otpController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();

  bool _codeSent = false;
  bool _loading = false;
  bool _hidePassword = true;

  @override
  void dispose() {
    _emailController.dispose();
    _otpController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();

    super.dispose();
  }

  void _message(String value, {bool error = false}) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).hideCurrentSnackBar();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(value),
        backgroundColor: error ? AppTheme.danger : AppTheme.success,
      ),
    );
  }

  Future<void> _sendCode() async {
    if (_loading) return;

    setState(() {
      _loading = true;
    });

    try {
      await _authService.sendPasswordResetOtp(email: _emailController.text);

      if (!mounted) return;

      setState(() {
        _codeSent = true;
      });

      _message('Verification code sent. Check your email.');
    } on AuthException catch (e) {
      _message(e.message, error: true);
    } on ArgumentError catch (e) {
      _message(e.message?.toString() ?? 'Invalid email.', error: true);
    } catch (e) {
      debugPrint('Password OTP error: $e');

      _message('Could not send verification code.', error: true);
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<void> _resetPassword() async {
    if (_loading) return;

    if (_passwordController.text != _confirmController.text) {
      _message('Passwords do not match.', error: true);

      return;
    }

    setState(() {
      _loading = true;
    });

    try {
      await _authService.resetPasswordWithOtp(
        email: _emailController.text,
        otp: _otpController.text,
        newPassword: _passwordController.text,
      );

      if (!mounted) return;

      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          return AlertDialog(
            icon: const Icon(
              Icons.check_circle_outline_rounded,
              color: AppTheme.success,
              size: 40,
            ),
            title: const Text('Password Updated'),
            content: const Text(
              'Your password has been changed successfully. '
              'You can now sign in using the new password.',
              textAlign: TextAlign.center,
            ),
            actionsAlignment: MainAxisAlignment.center,
            actions: [
              ElevatedButton(
                onPressed: () {
                  Navigator.of(dialogContext).pop();
                },
                child: const Text('Back to Login'),
              ),
            ],
          );
        },
      );

      if (!mounted) return;

      Navigator.of(context).pop();
    } on AuthException catch (e) {
      _message(e.message, error: true);
    } on ArgumentError catch (e) {
      _message(
        e.message?.toString() ?? 'Please check the information.',
        error: true,
      );
    } catch (e) {
      debugPrint('Password reset error: $e');

      _message(
        'Password could not be reset. '
        'Check the code and try again.',
        error: true,
      );
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset('assets/images/school_bg.png', fit: BoxFit.cover),
          Container(color: AppTheme.fgNavyBlue.withValues(alpha: 0.83)),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(18),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(25),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              IconButton(
                                tooltip: 'Back',
                                onPressed: _loading
                                    ? null
                                    : () {
                                        Navigator.of(context).pop();
                                      },
                                icon: const Icon(Icons.arrow_back_rounded),
                              ),
                              const SizedBox(width: 8),
                              const Expanded(
                                child: Text(
                                  'Forgot Password',
                                  style: TextStyle(
                                    fontSize: 24,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _codeSent
                                ? 'Enter the verification code sent to your email and choose a new password.'
                                : 'Enter your registered academy email to receive a verification code.',
                            style: const TextStyle(
                              color: AppTheme.textSecondary,
                              fontSize: 14,
                              height: 1.45,
                            ),
                          ),
                          const SizedBox(height: 23),
                          TextField(
                            controller: _emailController,
                            enabled: !_codeSent && !_loading,
                            keyboardType: TextInputType.emailAddress,
                            autocorrect: false,
                            decoration: const InputDecoration(
                              labelText: 'Email Address',
                              prefixIcon: Icon(Icons.alternate_email_rounded),
                            ),
                          ),
                          if (!_codeSent) ...[
                            const SizedBox(height: 22),
                            SizedBox(
                              height: 51,
                              child: ElevatedButton.icon(
                                onPressed: _loading ? null : _sendCode,
                                icon: _loading
                                    ? const SizedBox(
                                        width: 19,
                                        height: 19,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white,
                                        ),
                                      )
                                    : const Icon(
                                        Icons.mark_email_unread_outlined,
                                      ),
                                label: Text(
                                  _loading
                                      ? 'Sending…'
                                      : 'Send Verification Code',
                                ),
                              ),
                            ),
                          ] else ...[
                            const SizedBox(height: 14),
                            TextField(
                              controller: _otpController,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: 'Verification Code',
                                prefixIcon: Icon(Icons.pin_outlined),
                              ),
                            ),
                            const SizedBox(height: 14),
                            TextField(
                              controller: _passwordController,
                              obscureText: _hidePassword,
                              decoration: InputDecoration(
                                labelText: 'New Password',
                                prefixIcon: const Icon(
                                  Icons.lock_outline_rounded,
                                ),
                                suffixIcon: IconButton(
                                  onPressed: () {
                                    setState(() {
                                      _hidePassword = !_hidePassword;
                                    });
                                  },
                                  icon: Icon(
                                    _hidePassword
                                        ? Icons.visibility_outlined
                                        : Icons.visibility_off_outlined,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 14),
                            TextField(
                              controller: _confirmController,
                              obscureText: true,
                              textInputAction: TextInputAction.done,
                              onSubmitted: (_) {
                                if (!_loading) {
                                  _resetPassword();
                                }
                              },
                              decoration: const InputDecoration(
                                labelText: 'Confirm New Password',
                                prefixIcon: Icon(Icons.lock_reset_rounded),
                              ),
                            ),
                            const SizedBox(height: 22),
                            SizedBox(
                              height: 51,
                              child: ElevatedButton.icon(
                                onPressed: _loading ? null : _resetPassword,
                                icon: _loading
                                    ? const SizedBox(
                                        width: 19,
                                        height: 19,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white,
                                        ),
                                      )
                                    : const Icon(Icons.password_rounded),
                                label: Text(
                                  _loading ? 'Updating…' : 'Set New Password',
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            TextButton.icon(
                              onPressed: _loading ? null : _sendCode,
                              icon: const Icon(Icons.refresh_rounded),
                              label: const Text('Resend Code'),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
