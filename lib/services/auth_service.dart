import 'package:hive_flutter/hive_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/portal_user.dart';

class AuthService {
  final SupabaseClient _client;

  AuthService({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  User? get authUser => _client.auth.currentUser;

  Session? get currentSession => _client.auth.currentSession;

  // ============================================================
  // SIGN IN
  // ============================================================

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
          'Your teacher access request is still pending '
          'or this account is not registered for FG Academy Portal.',
        );
      }

      if (!portalUser.isActive) {
        throw StateError('This portal account is currently disabled.');
      }

      await _cachePortalUser(portalUser);

      return portalUser;
    } catch (_) {
      await _client.auth.signOut();
      await _clearCache();

      rethrow;
    }
  }

  // ============================================================
  // TEACHER SELF-REGISTRATION
  // ============================================================

  Future<void> registerTeacher({
    required String fullName,
    required String email,
    required String password,
    required String subject,
    required List<int> classLevels,
  }) async {
    final name = fullName.trim();
    final normalizedEmail = email.trim().toLowerCase();
    final normalizedSubject = normalizeTeacherSubject(subject);

    if (name.length < 2) {
      throw ArgumentError('Please enter your full name.');
    }

    if (normalizedEmail.isEmpty || !normalizedEmail.contains('@')) {
      throw ArgumentError('Please enter a valid email.');
    }

    final passwordError = validatePassword(password);

    if (passwordError != null) {
      throw ArgumentError(passwordError);
    }

    if (normalizedSubject.isEmpty) {
      throw ArgumentError('Subject is required.');
    }

    if (classLevels.isEmpty) {
      throw ArgumentError('Select at least one class.');
    }

    final levels =
        classLevels
            .where((value) => const [9, 10, 11, 12].contains(value))
            .toSet()
            .toList()
          ..sort();

    if (levels.isEmpty) {
      throw ArgumentError('Select at least one valid class.');
    }

    final response = await _client.auth.signUp(
      email: normalizedEmail,
      password: password,
      data: {
        'portal_registration': 'teacher_request',
        'full_name': name,
        'subject_name': normalizedSubject,
        'class_levels': levels,
      },
    );

    if (response.user == null) {
      throw StateError('Teacher registration could not be created.');
    }

    // If email confirmation is disabled Supabase may
    // automatically create a session. Pending teachers
    // must never stay logged in.
    if (_client.auth.currentSession != null) {
      await _client.auth.signOut();
    }

    await _clearCache();
  }

  static String normalizeTeacherSubject(String value) {
    final raw = value.trim();

    switch (raw.toLowerCase()) {
      case 'physics':
      case 'phy':
        return 'Phy';

      case 'chemistry':
      case 'chem':
        return 'Chem';

      case 'mathematics':
      case 'maths':
      case 'math':
        return 'Math';

      case 'english':
      case 'eng':
        return 'Eng';

      case 'computer':
      case 'computer science':
      case 'comp':
        return 'Comp';

      case 'biology':
      case 'bio':
        return 'Bio';

      default:
        return raw;
    }
  }

  static String subjectLabel(String code) {
    switch (code) {
      case 'Phy':
        return 'Physics';

      case 'Chem':
        return 'Chemistry';

      case 'Math':
        return 'Mathematics';

      case 'Eng':
        return 'English';

      case 'Comp':
        return 'Computer';

      case 'Bio':
        return 'Biology';

      default:
        return code;
    }
  }

  // ============================================================
  // FORGOT PASSWORD — EMAIL OTP
  // ============================================================

  Future<void> sendPasswordResetOtp({required String email}) async {
    final normalizedEmail = email.trim().toLowerCase();

    if (normalizedEmail.isEmpty || !normalizedEmail.contains('@')) {
      throw ArgumentError('Please enter a valid email address.');
    }

    await _client.auth.signInWithOtp(
      email: normalizedEmail,
      shouldCreateUser: false,
    );
  }

  Future<void> resetPasswordWithOtp({
    required String email,
    required String otp,
    required String newPassword,
  }) async {
    final normalizedEmail = email.trim().toLowerCase();
    final cleanOtp = otp.trim();

    if (normalizedEmail.isEmpty) {
      throw ArgumentError('Email is required.');
    }

    if (cleanOtp.isEmpty) {
      throw ArgumentError('Verification code is required.');
    }

    final validation = validatePassword(newPassword);

    if (validation != null) {
      throw ArgumentError(validation);
    }

    final response = await _client.auth.verifyOTP(
      email: normalizedEmail,
      token: cleanOtp,
      type: OtpType.email,
    );

    if (response.session == null) {
      throw StateError('Verification could not be completed.');
    }

    await _client.auth.updateUser(UserAttributes(password: newPassword));

    await _client.auth.signOut();
    await _clearCache();
  }

  // ============================================================
  // SESSION / PROFILE
  // ============================================================

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

  // ============================================================
  // NORMAL PASSWORD CHANGE FROM PROFILE
  // ============================================================

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
        'New password must be different from '
        'the current password.',
      );
    }

    await _client.auth.updateUser(
      UserAttributes(password: newPassword, currentPassword: oldPassword),
    );

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

  // ============================================================
  // PASSWORD RULES
  // ============================================================

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

  // ============================================================
  // LOCAL CACHE
  // ============================================================

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
