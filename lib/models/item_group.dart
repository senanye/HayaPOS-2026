class ItemGroupModel {
  final int id;
  final String name;
  final String? code;

  ItemGroupModel({
    required this.id,
    required this.name,
    this.code,
  });

  factory ItemGroupModel.fromJson(Map<String, dynamic> json) {
    return ItemGroupModel(
      id: json['id'] ?? 0,
      name: json['name'] ?? '',
      code: json['code'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'code': code,
    };
  }
}
