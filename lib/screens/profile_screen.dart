import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../app_theme.dart';
import '../models/portal_user.dart';
import '../services/auth_service.dart';
import '../utils/dashboard_section_header.dart';

class ProfileScreen extends StatefulWidget {
  final String userRole;

  // Kept for compatibility with existing DashboardScreen.
  final VoidCallback onChangePassword;

  final VoidCallback onLogout;

  const ProfileScreen({
    super.key,
    required this.userRole,
    required this.onChangePassword,
    required this.onLogout,
  });

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final AuthService _authService = AuthService();

  PortalUser? _user;

  bool _loading = true;

  bool _changingPassword = false;

  String? _error;

  @override
  void initState() {
    super.initState();

    _load();
  }

  Future<void> _load() async {
    try {
      final user = await _authService.loadCurrentUser();

      if (!mounted) return;

      setState(() {
        _user = user;
        _loading = false;

        _error = user == null ? 'Profile not found.' : null;
      });
    } catch (e) {
      debugPrint('Profile error: $e');

      if (!mounted) return;

      setState(() {
        _loading = false;
        _error = 'Unable to load profile.';
      });
    }
  }

  Future<void> _changePassword() async {
    if (_changingPassword) {
      return;
    }

    // The dialog only collects and validates values.
    // No Supabase/Auth operation happens inside the dialog route.
    final request = await showDialog<_PasswordChangeRequest>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _ChangePasswordDialog(),
    );

    if (request == null || !mounted) {
      return;
    }

    setState(() {
      _changingPassword = true;
    });

    try {
      await _authService.changePassword(
        currentPassword: request.currentPassword,
        newPassword: request.newPassword,
      );

      if (!mounted) return;

      await _load();

      if (!mounted) return;

      ScaffoldMessenger.of(context).hideCurrentSnackBar();

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Password changed successfully. '
            'Use the new password the next time you sign in.',
          ),
          backgroundColor: AppTheme.success,
        ),
      );
    } on AuthException catch (e) {
      debugPrint('Password AuthException: ${e.message}');

      if (!mounted) return;

      final message = e.message.toLowerCase();

      String friendlyMessage;

      if (message.contains('password') &&
          (message.contains('incorrect') ||
              message.contains('invalid') ||
              message.contains('current'))) {
        friendlyMessage = 'Current password is incorrect.';
      } else if (message.contains('same') || message.contains('different')) {
        friendlyMessage =
            'New password must be different from the current password.';
      } else {
        friendlyMessage =
            'Password could not be changed. Please verify the current password and try again.';
      }

      ScaffoldMessenger.of(context).hideCurrentSnackBar();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(friendlyMessage),
          backgroundColor: AppTheme.danger,
        ),
      );
    } on ArgumentError catch (e) {
      debugPrint('Password validation: $e');

      if (!mounted) return;

      final message = e.message?.toString() ?? 'Invalid password.';

      ScaffoldMessenger.of(context).hideCurrentSnackBar();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), backgroundColor: AppTheme.danger),
      );
    } catch (e) {
      debugPrint('Password update error: $e');

      if (!mounted) return;

      ScaffoldMessenger.of(context).hideCurrentSnackBar();

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Password could not be changed. '
            'Please check your connection and try again.',
          ),
          backgroundColor: AppTheme.danger,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _changingPassword = false;
        });
      }
    }
  }

  Future<void> _logout() async {
    await _authService.signOut();

    if (!mounted) return;

    widget.onLogout();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null || _user == null) {
      return Center(child: Text(_error ?? 'Profile unavailable.'));
    }

    final user = _user!;

    final initial = user.fullName.isEmpty
        ? '?'
        : user.fullName[0].toUpperCase();

    return Column(
      children: [
        const DashboardSectionHeader(
          title: 'Profile',
          subtitle: 'Account, role and teaching assignments',
        ),

        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 30),
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 720),
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(26),
                      child: Column(
                        children: [
                          CircleAvatar(
                            radius: 48,
                            backgroundColor: AppTheme.fgNavyBlue,
                            foregroundColor: Colors.white,
                            child: Text(
                              initial,
                              style: const TextStyle(
                                fontSize: 38,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),

                          const SizedBox(height: 15),

                          Text(
                            user.fullName,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 23,
                              fontWeight: FontWeight.w800,
                            ),
                          ),

                          const SizedBox(height: 5),

                          Text(
                            user.isAdmin ? 'Administrator' : 'Teacher',
                            style: const TextStyle(
                              color: AppTheme.fgNavyBlue,
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),

                          const SizedBox(height: 22),

                          _InfoTile(
                            icon: Icons.alternate_email_rounded,
                            label: 'Email',
                            value: user.email,
                          ),

                          const SizedBox(height: 9),

                          _InfoTile(
                            icon: Icons.shield_outlined,
                            label: 'Access',
                            value: user.assignmentSummary,
                          ),

                          if (user.assignments.isNotEmpty) ...[
                            const SizedBox(height: 18),

                            Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                'Teaching Assignments',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                            ),

                            const SizedBox(height: 9),

                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: user.assignments
                                  .map(
                                    (assignment) => Chip(
                                      avatar: const Icon(
                                        Icons.school_outlined,
                                        size: 17,
                                      ),
                                      label: Text(assignment.displayText),
                                    ),
                                  )
                                  .toList(),
                            ),
                          ],

                          const SizedBox(height: 25),

                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: _changingPassword
                                  ? null
                                  : _changePassword,
                              icon: _changingPassword
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.lock_reset_rounded),
                              label: Text(
                                _changingPassword
                                    ? 'Changing Password...'
                                    : 'Change Password',
                              ),
                            ),
                          ),

                          const SizedBox(height: 9),

                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: _changingPassword ? null : _logout,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppTheme.danger,
                              ),
                              icon: const Icon(Icons.logout_rounded),
                              label: const Text('Logout'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PasswordChangeRequest {
  final String currentPassword;
  final String newPassword;

  const _PasswordChangeRequest({
    required this.currentPassword,
    required this.newPassword,
  });
}

class _ChangePasswordDialog extends StatefulWidget {
  const _ChangePasswordDialog();

  @override
  State<_ChangePasswordDialog> createState() => _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends State<_ChangePasswordDialog> {
  final TextEditingController _currentController = TextEditingController();

  final TextEditingController _newController = TextEditingController();

  final TextEditingController _confirmController = TextEditingController();

  bool _oldHidden = true;
  bool _newHidden = true;
  bool _confirmHidden = true;

  String? _error;

  @override
  void dispose() {
    _currentController.dispose();
    _newController.dispose();
    _confirmController.dispose();

    super.dispose();
  }

  void _submit() {
    final currentPassword = _currentController.text;

    final newPassword = _newController.text;

    final confirmPassword = _confirmController.text;

    if (currentPassword.trim().isEmpty) {
      setState(() {
        _error = 'Current password is required.';
      });

      return;
    }

    if (newPassword.isEmpty) {
      setState(() {
        _error = 'New password is required.';
      });

      return;
    }

    if (newPassword != confirmPassword) {
      setState(() {
        _error = 'New passwords do not match.';
      });

      return;
    }

    if (currentPassword == newPassword) {
      setState(() {
        _error = 'New password must be different from the current password.';
      });

      return;
    }

    final validation = AuthService.validatePassword(newPassword);

    if (validation != null) {
      setState(() {
        _error = validation;
      });

      return;
    }

    Navigator.of(context).pop(
      _PasswordChangeRequest(
        currentPassword: currentPassword,
        newPassword: newPassword,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.lock_reset_rounded, color: AppTheme.fgNavyBlue),
          SizedBox(width: 10),
          Expanded(child: Text('Change Password')),
        ],
      ),
      content: SizedBox(
        width: 430,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _currentController,
                obscureText: _oldHidden,
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.password],
                decoration: InputDecoration(
                  labelText: 'Current Password',
                  prefixIcon: const Icon(Icons.lock_outline_rounded),
                  suffixIcon: IconButton(
                    tooltip: _oldHidden ? 'Show password' : 'Hide password',
                    onPressed: () {
                      setState(() {
                        _oldHidden = !_oldHidden;
                      });
                    },
                    icon: Icon(
                      _oldHidden
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 13),

              TextField(
                controller: _newController,
                obscureText: _newHidden,
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.newPassword],
                decoration: InputDecoration(
                  labelText: 'New Password',
                  prefixIcon: const Icon(Icons.key_rounded),
                  suffixIcon: IconButton(
                    tooltip: _newHidden ? 'Show password' : 'Hide password',
                    onPressed: () {
                      setState(() {
                        _newHidden = !_newHidden;
                      });
                    },
                    icon: Icon(
                      _newHidden
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 13),

              TextField(
                controller: _confirmController,
                obscureText: _confirmHidden,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _submit(),
                autofillHints: const [AutofillHints.newPassword],
                decoration: InputDecoration(
                  labelText: 'Confirm New Password',
                  prefixIcon: const Icon(Icons.verified_user_outlined),
                  suffixIcon: IconButton(
                    tooltip: _confirmHidden ? 'Show password' : 'Hide password',
                    onPressed: () {
                      setState(() {
                        _confirmHidden = !_confirmHidden;
                      });
                    },
                    icon: Icon(
                      _confirmHidden
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 14),

              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.fgNavyBlue.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Text(
                  'New password must contain at least 10 characters, '
                  'uppercase, lowercase, a number and a special character.',
                  style: TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 13,
                    height: 1.45,
                  ),
                ),
              ),

              if (_error != null) ...[
                const SizedBox(height: 12),

                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(11),
                  decoration: BoxDecoration(
                    color: AppTheme.danger.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    _error!,
                    style: const TextStyle(
                      color: AppTheme.danger,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            Navigator.of(context).pop();
          },
          child: const Text('Cancel'),
        ),
        ElevatedButton.icon(
          onPressed: _submit,
          icon: const Icon(Icons.lock_reset_rounded),
          label: const Text('Change Password'),
        ),
      ],
    );
  }
}

class _InfoTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _InfoTile({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.surfaceSoft,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        children: [
          Icon(icon, color: AppTheme.fgNavyBlue),

          const SizedBox(width: 12),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),

                const SizedBox(height: 3),

                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
