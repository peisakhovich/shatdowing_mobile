import 'learning_item.dart';

class LearningSet {
  final int setId;
  final String setName;
  final String setDescription;
  final String userNickname;
  final List<LearningItem> items;
  final int currentIndex;

  const LearningSet({
    required this.setId,
    required this.setName,
    required this.setDescription,
    required this.userNickname,
    required this.items,
    required this.currentIndex,
  });

  factory LearningSet.fromJson(Map<String, dynamic> json) {
    final setJson = json['set'] as Map<String, dynamic>;
    final itemsJson = json['items'] as List<dynamic>;
    final stateJson = json['state'] as Map<String, dynamic>;

    return LearningSet(
      setId: setJson['set_id'] as int,
      setName: setJson['set_name'] as String,
      setDescription: setJson['set_description'] as String,
      userNickname: setJson['user_nickname'] as String,
      items: itemsJson
          .map((item) => LearningItem.fromJson(item as Map<String, dynamic>))
          .toList(),
      currentIndex: stateJson['current_index'] as int,
    );
  }
}
