import 'package:hive_flutter/hive_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/portal_user.dart';

class AuthService {
  final SupabaseClient _client;

  AuthService({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  User? get authUser => _client.auth.currentUser;

  Session? get currentSession => _client.auth.currentSession;

  Future<PortalUser> signIn({
    required String email,
    required String password,
  }) async {
    final normalizedEmail = email.trim().toLowerCase();

    if (normalizedEmail.isEmpty) {
      throw ArgumentError('Email is required.');
    }

    if (password.isEmpty) {
      throw ArgumentError('Password is required.');
    }

    final response = await _client.auth.signInWithPassword(
      email: normalizedEmail,
      password: password,
    );

    final authUser = response.user;

    if (authUser == null) {
      throw StateError('Authentication failed.');
    }

    try {
      final portalUser = await loadCurrentUser();

      if (portalUser == null) {
        throw StateError(
          'This account is not registered for FG Academy Portal.',
        );
      }

      if (!portalUser.isActive) {
        throw StateError('This portal account is disabled.');
      }

      await _cachePortalUser(portalUser);

      return portalUser;
    } catch (_) {
      await _client.auth.signOut();
      await _clearCache();

      rethrow;
    }
  }

  Future<PortalUser?> restoreSession() async {
    if (_client.auth.currentSession == null) {
      await _clearCache();
      return null;
    }

    try {
      final portalUser = await loadCurrentUser();

      if (portalUser == null || !portalUser.isActive) {
        await signOut();
        return null;
      }

      await _cachePortalUser(portalUser);

      return portalUser;
    } catch (_) {
      await signOut();
      return null;
    }
  }

  Future<PortalUser?> loadCurrentUser() async {
    final user = _client.auth.currentUser;

    if (user == null) {
      return null;
    }

    final profile = await _client
        .from('user_profiles')
        .select(
          'user_id, email, full_name, '
          'role, must_change_password, '
          'is_active',
        )
        .eq('user_id', user.id)
        .maybeSingle();

    if (profile == null) {
      return null;
    }

    final role = profile['role']?.toString() ?? '';

    final assignments = <PortalAssignment>[];

    if (role == 'teacher') {
      final rows = await _client
          .from('teacher_assignments')
          .select('class_level, subject_code')
          .eq('teacher_id', user.id)
          .order('class_level');

      assignments.addAll(
        rows.map(
          (row) => PortalAssignment.fromJson(Map<String, dynamic>.from(row)),
        ),
      );
    }

    return PortalUser(
      userId: profile['user_id'].toString(),
      email: profile['email'].toString(),
      fullName: profile['full_name'].toString(),
      role: role,
      mustChangePassword: profile['must_change_password'] == true,
      isActive: profile['is_active'] == true,
      assignments: assignments,
    );
  }

  Future<void> changePassword({
    String? currentPassword,
    required String newPassword,
  }) async {
    final validation = validatePassword(newPassword);

    if (validation != null) {
      throw ArgumentError(validation);
    }

    final currentUser = _client.auth.currentUser;

    if (currentUser == null) {
      throw StateError('You are not signed in.');
    }

    final oldPassword = currentPassword?.trim() ?? '';

    if (oldPassword.isEmpty) {
      throw ArgumentError('Current password is required.');
    }

    if (oldPassword == newPassword) {
      throw ArgumentError(
        'New password must be different from the current password.',
      );
    }

    // IMPORTANT:
    // Do NOT call signInWithPassword() here.
    //
    // The user is already authenticated. Supabase supports validating the
    // current password directly as part of updateUser(). This avoids replacing
    // the active session while Flutter is displaying the profile/dialog.
    await _client.auth.updateUser(
      UserAttributes(password: newPassword, currentPassword: oldPassword),
    );

    // Password change is optional in FG Academy Portal.
    // There is no mandatory first-login password-change state to complete.

    final refreshed = await loadCurrentUser();

    if (refreshed != null) {
      await _cachePortalUser(refreshed);
    }
  }

  Future<void> signOut() async {
    try {
      await _client.auth.signOut();
    } finally {
      await _clearCache();
    }
  }

  static String? validatePassword(String password) {
    if (password.length < 10) {
      return 'Password must be at least 10 characters.';
    }

    if (!RegExp(r'[A-Z]').hasMatch(password)) {
      return 'Password must contain an uppercase letter.';
    }

    if (!RegExp(r'[a-z]').hasMatch(password)) {
      return 'Password must contain a lowercase letter.';
    }

    if (!RegExp(r'[0-9]').hasMatch(password)) {
      return 'Password must contain a number.';
    }

    if (!RegExp(r'[!@#$%^&*(),.?":{}|<>_\-+=]').hasMatch(password)) {
      return 'Password must contain a special character.';
    }

    return null;
  }

  Future<void> _cachePortalUser(PortalUser user) async {
    final box = Hive.box('settings');

    await box.put('isLoggedIn', true);

    await box.put('role', user.role);

    await box.put('username', user.fullName);

    await box.put('email', user.email);

    await box.put('user_id', user.userId);
  }

  Future<void> _clearCache() async {
    final box = Hive.box('settings');

    await box.put('isLoggedIn', false);

    await box.delete('role');
    await box.delete('username');
    await box.delete('email');
    await box.delete('user_id');
  }
}
