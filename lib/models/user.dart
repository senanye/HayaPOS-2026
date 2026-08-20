class UserModel {
  final int userId;
  final String userName;
  final bool isAdmin;
  final bool canSale;
  final bool canReturn;
  final bool canChangePrice;
  final bool canDiscount;
  final bool canExpenses;
  final bool canReport;

  UserModel({
    required this.userId,
    required this.userName,
    required this.isAdmin,
    required this.canSale,
    required this.canReturn,
    required this.canChangePrice,
    required this.canDiscount,
    required this.canExpenses,
    required this.canReport,
  });

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      userId: json['userId'],
      userName: json['userName'],
      isAdmin: json['isAdmin'] ?? false,
      canSale: json['canSale'] ?? false,
      canReturn: json['canReturn'] ?? false,
      canChangePrice: json['canChangePrice'] ?? false,
      canDiscount: json['canDiscount'] ?? false,
      canExpenses: json['canExpenses'] ?? false,
      canReport: json['canReport'] ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'userId': userId,
      'userName': userName,
      'isAdmin': isAdmin,
      'canSale': canSale,
      'canReturn': canReturn,
      'canChangePrice': canChangePrice,
      'canDiscount': canDiscount,
      'canExpenses': canExpenses,
      'canReport': canReport,
    };
  }
}
