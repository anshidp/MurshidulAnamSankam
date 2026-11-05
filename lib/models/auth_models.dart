import 'block_utils.dart';

class AuthUser {
  const AuthUser({
    required this.fullName,
    required this.username,
    required this.role,
    this.assignedBlocks = const <String>[],
  });

  final String fullName;
  final String username;
  final String role; // 'admin' | 'staff'
  final List<String> assignedBlocks; // empty = all access (admin)

  bool get isAdmin => role == 'admin';

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'fullName': fullName,
      'username': username,
      'role': role,
      'assignedBlocks': normalizeBlockCodes(assignedBlocks),
    };
  }

  factory AuthUser.fromJson(Map<String, dynamic> json) {
    final rawBlocks = json['assignedBlocks'];
    final blocks = rawBlocks is List
        ? normalizeBlockCodes(rawBlocks.map((dynamic e) => '$e'))
        : <String>[];
    return AuthUser(
      fullName: '${json['fullName'] ?? ''}',
      username: '${json['username'] ?? ''}',
      role: '${json['role'] ?? 'admin'}',
      assignedBlocks: blocks,
    );
  }
}

class StaffUser {
  const StaffUser({
    required this.username,
    required this.fullName,
    required this.password,
    required this.blocks,
  });

  final String username;
  final String fullName;
  final String password;
  final List<String> blocks;

  Map<String, dynamic> toFirestore() {
    return <String, dynamic>{
      'fullName': fullName,
      'username': username,
      'password': password,
      'blocks': normalizeBlockCodes(blocks),
      'role': 'staff',
    };
  }

  factory StaffUser.fromFirestore(Map<String, dynamic> data) {
    final rawBlocks = data['blocks'];
    final blocks = rawBlocks is List
        ? normalizeBlockCodes(rawBlocks.map((dynamic e) => '$e'))
        : <String>[];
    return StaffUser(
      username: '${data['username'] ?? ''}',
      fullName: '${data['fullName'] ?? ''}',
      password: '${data['password'] ?? ''}',
      blocks: blocks,
    );
  }

  AuthUser toAuthUser() {
    return AuthUser(
      fullName: fullName,
      username: username,
      role: 'staff',
      assignedBlocks: normalizeBlockCodes(blocks),
    );
  }
}

class AuthSnapshot {
  const AuthSnapshot({
    required this.hasAccount,
    this.adminUser,
    this.currentUser,
  });

  final bool hasAccount;
  final AuthUser? adminUser;
  final AuthUser? currentUser;

  bool get isAuthenticated => currentUser != null;
}
