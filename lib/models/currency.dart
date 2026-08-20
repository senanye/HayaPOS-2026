class CurrencyModel {
  final int id;
  final String symbol;
  final String name;
  final double value;

  CurrencyModel({
    required this.id,
    required this.symbol,
    required this.name,
    required this.value,
  });

  factory CurrencyModel.fromJson(Map<String, dynamic> json) {
    return CurrencyModel(
      id: json['id'] ?? 0,
      symbol: json['symbol'] ?? '',
      name: json['name'] ?? '',
      value: (json['value'] ?? 1.0).toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'symbol': symbol,
      'name': name,
      'value': value,
    };
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CurrencyModel &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}
