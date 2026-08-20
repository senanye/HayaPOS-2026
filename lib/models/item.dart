class ItemModel {
  final String barcode;
  final String itemName;
  final String unitName;
  final double salesPrice;
  final double cost;
  final int groupId;
  final int itemId;
  final int unityId;
  final int moneyId;
  final bool isActive;

  ItemModel({
    required this.barcode,
    required this.itemName,
    required this.unitName,
    required this.salesPrice,
    required this.cost,
    required this.groupId,
    required this.itemId,
    required this.unityId,
    required this.moneyId,
    required this.isActive,
  });

  factory ItemModel.fromJson(Map<String, dynamic> json) {
    return ItemModel(
      barcode: json['barcode'] ?? '',
      itemName: json['itemName'] ?? '',
      unitName: json['unitName'] ?? '',
      salesPrice: (json['salesPrice'] ?? 0.0).toDouble(),
      cost: (json['cost'] ?? 0.0).toDouble(),
      groupId: json['groupId'] ?? 0,
      itemId: json['itemId'] ?? 0,
      unityId: json['unityId'] ?? 0,
      moneyId: json['moneyId'] ?? 0,
      isActive: json['isActive'] ?? true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'barcode': barcode,
      'itemName': itemName,
      'unitName': unitName,
      'salesPrice': salesPrice,
      'cost': cost,
      'groupId': groupId,
      'itemId': itemId,
      'unityId': unityId,
      'moneyId': moneyId,
      'isActive': isActive,
    };
  }
}
