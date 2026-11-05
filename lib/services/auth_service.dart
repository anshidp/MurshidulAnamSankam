import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/auth_models.dart';

class LocalAuthService {
  static const String _sessionUsernameKey = 'auth_session_username';
  static const String _sessionRoleKey = 'auth_session_role';

  FirebaseFirestore get _firestore => FirebaseFirestore.instance;

  Future<AuthSnapshot> loadSnapshot() async {
    try {
      final doc = await _firestore.collection('config').doc('admin').get();
      if (!doc.exists || doc.data() == null) {
        return const AuthSnapshot(hasAccount: false);
      }

      final data = doc.data()!;
      final adminUser = AuthUser.fromJson(data);

      final prefs = await SharedPreferences.getInstance();
      final sessionUsername = prefs.getString(_sessionUsernameKey);
      final sessionRole = prefs.getString(_sessionRoleKey) ?? 'admin';

      AuthUser? currentUser;

      if (sessionUsername != null) {
        if (sessionRole == 'admin' && sessionUsername == adminUser.username) {
          currentUser = adminUser;
        } else if (sessionRole == 'staff') {
          final staffDoc = await _firestore
              .collection('staff')
              .doc(sessionUsername)
              .get();
          if (staffDoc.exists && staffDoc.data() != null) {
            final staff = StaffUser.fromFirestore(staffDoc.data()!);
            currentUser = staff.toAuthUser();
          }
        }
      }

      return AuthSnapshot(
        hasAccount: true,
        adminUser: adminUser,
        currentUser: currentUser,
      );
    } catch (_) {
      return const AuthSnapshot(hasAccount: false);
    }
  }

  Future<void> setupAdmin({
    required String fullName,
    required String username,
    required String password,
  }) async {
    try {
      final doc = await _firestore.collection('config').doc('admin').get();
      if (doc.exists) {
        throw const AuthException(
          'Admin account is already created. Please log in.',
        );
      }

      final normalizedUsername = username.trim().toLowerCase();
      final user = AuthUser(
        fullName: fullName.trim(),
        username: normalizedUsername,
        role: 'admin',
      );

      final payload = user.toJson();
      payload['password'] = password;

      await _firestore.collection('config').doc('admin').set(payload);

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_sessionUsernameKey, normalizedUsername);
      await prefs.setString(_sessionRoleKey, 'admin');
    } on AuthException {
      rethrow;
    } catch (_) {
      throw const AuthException(
        'Could not create admin account in Firestore. Check your connection.',
      );
    }
  }

  Future<AuthUser?> login({
    required String username,
    required String password,
  }) async {
    try {
      final normalizedUsername = username.trim().toLowerCase();

      // Try admin first
      final doc = await _firestore.collection('config').doc('admin').get();
      if (!doc.exists || doc.data() == null) {
        throw const AuthException('No admin account exists yet.');
      }

      final data = doc.data()!;
      final adminUser = AuthUser.fromJson(data);
      final storedPassword = data['password'] as String?;

      if (normalizedUsername == adminUser.username &&
          storedPassword != null &&
          storedPassword == password) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_sessionUsernameKey, adminUser.username);
        await prefs.setString(_sessionRoleKey, 'admin');
        return adminUser;
      }

      // Try staff collection
      final staffDoc = await _firestore
          .collection('staff')
          .doc(normalizedUsername)
          .get();

      if (staffDoc.exists && staffDoc.data() != null) {
        final staff = StaffUser.fromFirestore(staffDoc.data()!);
        if (staff.password == password) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(_sessionUsernameKey, normalizedUsername);
          await prefs.setString(_sessionRoleKey, 'staff');
          return staff.toAuthUser();
        }
      }

      return null; // Invalid credentials
    } on AuthException {
      rethrow;
    } catch (_) {
      throw const AuthException('Could not verify login with Firestore.');
    }
  }

  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_sessionUsernameKey);
    await prefs.remove(_sessionRoleKey);
  }
}

class AuthException implements Exception {
  const AuthException(this.message);

  final String message;
}
