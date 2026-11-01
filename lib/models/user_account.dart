class UserAccount {
  final int userId;
  final String nickname;
  final String? firstName;
  final String? lastName;
  final bool active;

  const UserAccount({
    required this.userId,
    required this.nickname,
    this.firstName,
    this.lastName,
    required this.active,
  });

  factory UserAccount.fromJson(Map<String, dynamic> json) {
    return UserAccount(
      userId: (json['user_id'] as num).toInt(),
      nickname: json['nickname'] as String,
      firstName: json['first_name'] as String?,
      lastName: json['last_name'] as String?,
      active: json['active'] as bool? ?? false,
    );
  }
}
