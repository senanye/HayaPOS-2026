class TransactionDetailModel {
  final String barcode;
  final String itemName; // Helper field for UI
  final int quantity;
  final double salesPrice;
  final int discount;
  final int taxTotal;
  final int totalItem;
  final int? toPointNo;

  TransactionDetailModel({
    required this.barcode,
    required this.itemName,
    required this.quantity,
    required this.salesPrice,
    required this.discount,
    required this.taxTotal,
    required this.totalItem,
    this.toPointNo,
  });

  factory TransactionDetailModel.fromJson(Map<String, dynamic> json) {
    return TransactionDetailModel(
      barcode: json['barcode'] ?? '',
      itemName: json['itemName'] ?? '',
      quantity: json['quantity'] ?? 0,
      salesPrice: (json['salesPrice'] ?? 0.0).toDouble(),
      discount: json['discount'] ?? 0,
      taxTotal: json['taxTotal'] ?? 0,
      totalItem: json['totalItem'] ?? 0,
      toPointNo: json['toPointNo'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'barcode': barcode,
      'quantity': quantity,
      'salesPrice': salesPrice,
      'discount': discount,
      'taxTotal': taxTotal,
      'totalItem': totalItem,
      if (toPointNo != null) 'toPointNo': toPointNo,
    };
  }
}

class TransactionHeaderModel {
  final String date; // YYYY-MM-DD
  final String? description;
  final double? transNumber; // Will be set by API
  final int userId;
  final int pointNo;
  final int? toPointNo;
  final int payCash; // 1 = Cash, 2 = Credit
  final int transType; // 1 = Sale, 2 = Purchase, 28 = Inter-branch Transfer
  final int moneyId;
  final int? accountId; // fldAccID from tblExpensesList
  final int? status; // 0 = Pending/In-Transit, 1 = Confirmed/Received
  final List<TransactionDetailModel> details;

  TransactionHeaderModel({
    required this.date,
    this.description,
    this.transNumber,
    required this.userId,
    required this.pointNo,
    this.toPointNo,
    required this.payCash,
    required this.transType,
    required this.moneyId,
    this.accountId,
    this.status,
    required this.details,
  });

  Map<String, dynamic> toJson() {
    return {
      'date': date,
      'description': description,
      'userId': userId,
      'pointNo': pointNo,
      if (toPointNo != null) 'toPointNo': toPointNo,
      'payCash': payCash,
      'transType': transType,
      'moneyId': moneyId,
      'accountId': accountId ?? 0,
      if (status != null) 'status': status,
      'details': details.map((d) => d.toJson()).toList(),
    };
  }
}
