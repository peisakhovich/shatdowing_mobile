class UserSet {
  final int setId;
  final int userId;
  final String userNickname;
  final int setIndex;
  final String setName;
  final String setDescription;
  final bool setActive;
  final int itemsCount;

  const UserSet({
    required this.setId,
    required this.userId,
    required this.userNickname,
    required this.setIndex,
    required this.setName,
    required this.setDescription,
    required this.setActive,
    required this.itemsCount,
  });

  factory UserSet.fromJson(Map<String, dynamic> json) {
    return UserSet(
      setId: (json['set_id'] as num).toInt(),
      userId: (json['user_id'] as num).toInt(),
      userNickname: json['user_nickname'] as String,
      setIndex: (json['set_index'] as num).toInt(),
      setName: json['set_name'] as String,
      setDescription: json['set_description'] as String? ?? '',
      setActive: json['set_active'] as bool? ?? false,
      itemsCount: (json['items_count'] as num?)?.toInt() ?? 0,
    );
  }
}
