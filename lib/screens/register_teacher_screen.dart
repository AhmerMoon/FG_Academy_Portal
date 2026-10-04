import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../app_theme.dart';
import '../services/auth_service.dart';

class RegisterTeacherScreen extends StatefulWidget {
  const RegisterTeacherScreen({super.key});

  @override
  State<RegisterTeacherScreen> createState() => _RegisterTeacherScreenState();
}

class _RegisterTeacherScreenState extends State<RegisterTeacherScreen> {
  final AuthService _authService = AuthService();

  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _subjectController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();

  final Set<int> _classes = {};

  bool _loading = false;
  bool _hidePassword = true;
  bool _hideConfirm = true;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _subjectController.dispose();
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

  Future<void> _submit() async {
    if (_loading) return;

    final password = _passwordController.text;

    if (password != _confirmController.text) {
      _message('Passwords do not match.', error: true);

      return;
    }

    setState(() {
      _loading = true;
    });

    try {
      await _authService.registerTeacher(
        fullName: _nameController.text,
        email: _emailController.text,
        password: password,
        subject: _subjectController.text,
        classLevels: _classes.toList(),
      );

      if (!mounted) return;

      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          return AlertDialog(
            icon: const Icon(
              Icons.mark_email_read_outlined,
              color: AppTheme.success,
              size: 38,
            ),
            title: const Text('Request Submitted'),
            content: const Text(
              'Your teacher access request has been '
              'sent to the academy administrator.\n\n'
              'If you receive an email verification '
              'message, please verify your email.\n\n'
              'You can sign in using this same password '
              'after the administrator approves your request.',
              textAlign: TextAlign.center,
            ),
            actionsAlignment: MainAxisAlignment.center,
            actions: [
              ElevatedButton(
                onPressed: () {
                  Navigator.of(dialogContext).pop();
                },
                child: const Text('OK'),
              ),
            ],
          );
        },
      );

      if (!mounted) return;

      Navigator.of(context).pop();
    } on AuthException catch (e) {
      debugPrint('Teacher registration auth error: ${e.message}');

      _message(e.message, error: true);
    } on ArgumentError catch (e) {
      _message(
        e.message?.toString() ?? 'Please check the entered information.',
        error: true,
      );
    } catch (e) {
      debugPrint('Teacher registration error: $e');

      _message(
        'Registration could not be submitted. '
        'Please check the details and try again.',
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
                  constraints: const BoxConstraints(maxWidth: 620),
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
                                  'Teacher Registration',
                                  style: TextStyle(
                                    fontSize: 24,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 5),
                          const Text(
                            'Request access to FG Academy Portal. '
                            'Your account becomes active only '
                            'after administrator approval.',
                            style: TextStyle(
                              color: AppTheme.textSecondary,
                              height: 1.45,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 24),
                          TextField(
                            controller: _nameController,
                            textCapitalization: TextCapitalization.words,
                            decoration: const InputDecoration(
                              labelText: 'Full Name',
                              prefixIcon: Icon(Icons.person_outline_rounded),
                            ),
                          ),
                          const SizedBox(height: 13),
                          TextField(
                            controller: _emailController,
                            keyboardType: TextInputType.emailAddress,
                            autocorrect: false,
                            decoration: const InputDecoration(
                              labelText: 'Email Address',
                              prefixIcon: Icon(Icons.alternate_email_rounded),
                            ),
                          ),
                          const SizedBox(height: 13),
                          TextField(
                            controller: _subjectController,
                            textCapitalization: TextCapitalization.words,
                            decoration: const InputDecoration(
                              labelText: 'Subject',
                              hintText: 'Physics, Urdu, Islamiyat...',
                              prefixIcon: Icon(Icons.menu_book_outlined),
                            ),
                          ),
                          const SizedBox(height: 18),
                          const Text(
                            'Classes You Teach',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 9),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [9, 10, 11, 12].map((level) {
                              return FilterChip(
                                label: Text('Class $level'),
                                selected: _classes.contains(level),
                                onSelected: _loading
                                    ? null
                                    : (selected) {
                                        setState(() {
                                          if (selected) {
                                            _classes.add(level);
                                          } else {
                                            _classes.remove(level);
                                          }
                                        });
                                      },
                              );
                            }).toList(),
                          ),
                          const SizedBox(height: 19),
                          TextField(
                            controller: _passwordController,
                            obscureText: _hidePassword,
                            decoration: InputDecoration(
                              labelText: 'Choose Password',
                              helperText:
                                  'Minimum 10 characters with uppercase, '
                                  'lowercase, number and special character.',
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
                          const SizedBox(height: 13),
                          TextField(
                            controller: _confirmController,
                            obscureText: _hideConfirm,
                            textInputAction: TextInputAction.done,
                            onSubmitted: (_) {
                              if (!_loading) {
                                _submit();
                              }
                            },
                            decoration: InputDecoration(
                              labelText: 'Confirm Password',
                              prefixIcon: const Icon(Icons.lock_reset_rounded),
                              suffixIcon: IconButton(
                                onPressed: () {
                                  setState(() {
                                    _hideConfirm = !_hideConfirm;
                                  });
                                },
                                icon: Icon(
                                  _hideConfirm
                                      ? Icons.visibility_outlined
                                      : Icons.visibility_off_outlined,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 24),
                          SizedBox(
                            height: 52,
                            child: ElevatedButton.icon(
                              onPressed: _loading ? null : _submit,
                              icon: _loading
                                  ? const SizedBox(
                                      width: 19,
                                      height: 19,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Icon(Icons.send_rounded),
                              label: Text(
                                _loading
                                    ? 'Submitting…'
                                    : 'Request Teacher Access',
                              ),
                            ),
                          ),
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
