/// Domain user — matches CLAUDE.md §5 User entity field names verbatim.
class User {
  const User({
    required this.id,
    required this.username,
    required this.displayName,
    required this.displayNameAr,
    required this.email,
    required this.role,
    required this.isActive,
  });

  final String id;
  final String username;
  final String displayName;
  final String displayNameAr;
  final String email;
  final UserRole role;
  final bool isActive;
}

enum UserRole {
  member,
  leader,
  admin,
  superAdmin;

  String get apiCode {
    switch (this) {
      case UserRole.member:
        return 'MEMBER';
      case UserRole.leader:
        return 'LEADER';
      case UserRole.admin:
        return 'ADMIN';
      case UserRole.superAdmin:
        return 'SUPER_ADMIN';
    }
  }

  static UserRole fromApiCode(String code) {
    switch (code) {
      case 'MEMBER':
        return UserRole.member;
      case 'LEADER':
        return UserRole.leader;
      case 'ADMIN':
        return UserRole.admin;
      case 'SUPER_ADMIN':
        return UserRole.superAdmin;
      default:
        throw ArgumentError('Unknown role code: $code');
    }
  }
}
