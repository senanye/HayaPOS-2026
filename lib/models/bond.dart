class BondItemModel {
  int expensesId;
  String expensesName;
  double amount;
  String note;
  int accountId;

  BondItemModel({
    required this.expensesId,
    required this.expensesName,
    required this.amount,
    required this.note,
    this.accountId = 0,
  });

  factory BondItemModel.fromJson(Map<String, dynamic> json) {
    return BondItemModel(
      expensesId: json['expensesId'] ?? 0,
      expensesName: json['expensesName'] ?? '',
      amount: (json['amount'] ?? 0.0).toDouble(),
      note: json['note'] ?? '',
      accountId: json['accountId'] ?? (json['accId'] ?? 0),
    );
  }

  Map<String, dynamic> toJson() => {
    'expensesId': expensesId,
    'amount': amount,
    'note': note,
    'accountId': accountId,
  };
}

class BondModel {
  final int id;
  final double transNumber;
  final int expensesId;
  final String expensesName;
  final double amount;
  final String note;
  final String date;
  final bool isReceipt;
  final int pointNo;
  final int userId;
  final int moneyId;
  final String currencyName;
  final String currencySymbol;
  final int accountId;
  final List<BondItemModel> details;

  BondModel({
    required this.id,
    required this.transNumber,
    required this.expensesId,
    required this.expensesName,
    required this.amount,
    required this.note,
    required this.date,
    required this.isReceipt,
    required this.pointNo,
    required this.userId,
    this.moneyId = 1,
    this.currencyName = 'دينار أردني',
    this.currencySymbol = 'د.أ',
    this.accountId = 0,
    this.details = const [],
  });

  factory BondModel.fromJson(Map<String, dynamic> json) {
    var rawDetails = json['details'] as List? ?? [];
    List<BondItemModel> items = rawDetails.map((x) => BondItemModel.fromJson(x)).toList();

    return BondModel(
      id: json['id'] ?? 0,
      transNumber: (json['transNumber'] ?? 0.0).toDouble(),
      expensesId: json['expensesId'] ?? 0,
      expensesName: json['expensesName'] ?? '',
      amount: (json['amount'] ?? 0.0).toDouble(),
      note: json['note'] ?? '',
      date: json['date'] ?? '',
      isReceipt: json['isReceipt'] ?? true,
      pointNo: json['pointNo'] ?? 1,
      userId: json['userId'] ?? 1,
      moneyId: json['moneyId'] ?? 1,
      currencyName: json['currencyName'] ?? (json['moneyId'] == 2 ? 'ريال سعودي' : (json['moneyId'] == 3 ? 'دولار أمريكي' : 'دينار أردني')),
      currencySymbol: json['currencySymbol'] ?? (json['moneyId'] == 2 ? 'ر.س' : (json['moneyId'] == 3 ? '\$' : 'د.أ')),
      accountId: json['accountId'] ?? (json['expensesId'] ?? 0),
      details: items,
    );
  }
}
