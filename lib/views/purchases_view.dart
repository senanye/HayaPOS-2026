import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart' hide TextDirection;
import '../services/api_service.dart';
import '../models/item.dart';
import '../models/currency.dart';
import '../models/account.dart';
import '../models/transaction.dart';

class PurchasesView extends StatefulWidget {
  const PurchasesView({super.key});

  @override
  State<PurchasesView> createState() => _PurchasesViewState();
}

class _PurchasesViewState extends State<PurchasesView> {
  final List<PurchaseCartItem> _cart = [];
  CurrencyModel? _selectedCurrency;
  AccountModel? _selectedAccount;
  int _selectedGroupId = 0;
  String _searchQuery = '';
  final _searchController = TextEditingController();
  final _itemNameSearchController = TextEditingController();
  
  int _payCash = 1; // 1 = Cash, 2 = Credit
  double _discount = 0.0;
  final _discountController = TextEditingController(text: '0');

  final _categoriesScrollController = ScrollController();

  CurrencyModel get _activeCurrency {
    final apiService = Provider.of<ApiService>(context, listen: false);
    return _selectedCurrency ?? apiService.defaultCurrency;
  }

  double get _currencyRate {
    final cur = _activeCurrency;
    return cur.value > 0 ? cur.value : 1.0;
  }

  String get _currencySymbol {
    final cur = _activeCurrency;
    return cur.symbol.isNotEmpty ? cur.symbol : cur.name;
  }

  String currencyFormat(double val) {
    return '${val.toStringAsFixed(2)} $_currencySymbol';
  }

  void _onCurrencyChanged(CurrencyModel newCurrency) {
    setState(() {
      _selectedCurrency = newCurrency;
      final rate = newCurrency.value > 0 ? newCurrency.value : 1.0;
      for (var item in _cart) {
        item.purchaseCost = item.item.cost * rate;
        item.salesPrice = item.item.salesPrice * rate;
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _discountController.dispose();
    _categoriesScrollController.dispose();
    super.dispose();
  }

  void _addToCart(ItemModel item) {
    setState(() {
      final index = _cart.indexWhere((x) => x.item.barcode == item.barcode);
      final rate = _currencyRate;
      if (index >= 0) {
        _cart[index].quantity++;
      } else {
        // In purchases, we default to the cost price as the transaction price with active currency rate
        _cart.add(PurchaseCartItem(
          item: item, 
          quantity: 1, 
          purchaseCost: item.cost * rate,
          salesPrice: item.salesPrice * rate,
        ));
      }
    });
  }

  void _updateQty(int index, int delta) {
    setState(() {
      _cart[index].quantity += delta;
      if (_cart[index].quantity <= 0) {
        _cart.removeAt(index);
      }
    });
  }

  void _updatePrices(int index, double cost, double sale) {
    setState(() {
      _cart[index].purchaseCost = cost;
      _cart[index].salesPrice = sale;
    });
  }

  void _removeFromCart(int index) {
    setState(() {
      _cart.removeAt(index);
    });
  }

  void _clearPurchase() {
    setState(() {
      _cart.clear();
      _selectedAccount = null;
      _discount = 0.0;
      _discountController.text = '0';
      _payCash = 1;
      _searchController.clear();
      _searchQuery = '';
    });
  }

  double get _subtotal {
    return _cart.fold(0.0, (sum, item) => sum + (item.purchaseCost * item.quantity));
  }

  double get _tax {
    return 0.0; // Cancelled Tax
  }

  double get _total {
    final t = _subtotal - _discount;
    return t < 0 ? 0.0 : t;
  }

  Future<void> _savePurchase() async {
    if (_cart.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('سلة المشتريات فارغة!', style: TextStyle(fontFamily: 'Cairo')),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final apiService = Provider.of<ApiService>(context, listen: false);
    final user = apiService.currentUser;
    if (user == null) return;

    final List<TransactionDetailModel> details = _cart.map((cartItem) {
      final double itemSubtotal = cartItem.purchaseCost * cartItem.quantity;
      final double itemTax = 0.0; // Cancelled Tax
      final double itemTotal = itemSubtotal;

      return TransactionDetailModel(
        barcode: cartItem.item.barcode,
        itemName: cartItem.item.itemName,
        quantity: cartItem.quantity,
        salesPrice: cartItem.purchaseCost, // Using purchaseCost as the recorded transaction price
        discount: 0,
        taxTotal: 0,
        totalItem: itemTotal.round(),
      );
    }).toList();

    final transaction = TransactionHeaderModel(
      date: apiService.selectedDate,
      description: 'فاتورة مشتريات محلية Flutter',
      userId: user.userId,
      pointNo: apiService.pointNo,
      payCash: _payCash,
      transType: 20, // 20 = Purchase (from schema check)
      moneyId: _activeCurrency.id,
      accountId: _selectedAccount?.accId ?? 0,
      details: details,
    );

    try {
      final response = await apiService.saveTransaction(transaction);
      
      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => Directionality(
            textDirection: TextDirection.rtl,
            child: AlertDialog(
              title: const Row(
                children: [
                  Icon(Icons.check_circle, color: Colors.green, size: 28),
                  SizedBox(width: 8),
                  Text(
                    'تم حفظ المشتريات',
                    style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('رقم الفاتورة: ${response['transNumber']}', style: const TextStyle(fontFamily: 'Cairo', fontSize: 16)),
                  const SizedBox(height: 8),
                  Text('إجمالي التكلفة: ${currencyFormat(_total)}', style: const TextStyle(fontFamily: 'Cairo', fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  const Text('تم حفظ الفاتورة بنجاح في SQL Server وزيادة كميات المخزون.', style: TextStyle(fontFamily: 'Cairo', color: Colors.grey)),
                ],
              ),
              actions: [
                ElevatedButton(
                  onPressed: () {
                    Navigator.pop(context);
                    _clearPurchase();
                  },
                  child: const Text('فاتورة جديدة', style: TextStyle(fontFamily: 'Cairo')),
                ),
              ],
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => Directionality(
            textDirection: TextDirection.rtl,
            child: AlertDialog(
              title: const Text('فشل حفظ الفاتورة', style: TextStyle(fontFamily: 'Cairo', color: Colors.red)),
              content: Text(e.toString().replaceAll('Exception:', '').trim(), style: const TextStyle(fontFamily: 'Cairo')),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('حسناً', style: TextStyle(fontFamily: 'Cairo')),
                )
              ],
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final apiService = Provider.of<ApiService>(context);

    final filteredItems = apiService.items.where((item) {
      final matchesGroup = _selectedGroupId == 0 || item.groupId == _selectedGroupId;
      final matchesSearch = item.itemName.toLowerCase().contains(_searchQuery.toLowerCase()) ||
                            item.barcode.contains(_searchQuery);
      return matchesGroup && matchesSearch;
    }).toList();

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      body: Directionality(
        textDirection: TextDirection.rtl,
        child: Column(
          children: [
            // --- TOP HEADER ---
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              color: const Color(0xFF1E293B),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.local_shipping_outlined, color: Colors.greenAccent, size: 28),
                      SizedBox(width: 12),
                      Text(
                        'فاتورة مشتريات محلية جديدة',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'Cairo',
                        ),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      _buildCurrencyDropdown(apiService),
                      const SizedBox(width: 10),
                      _buildAccountDropdown(apiService),
                    ],
                  ),
                ],
              ),
            ),
            
            // --- SPLIT VIEW ---
            Expanded(
              child: Row(
                children: [
                  // --- LEFT SIDE: PRODUCTS GRID & FILTERS (65%) ---
                  Expanded(
                    flex: 65,
                    child: Container(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Search & filter
                          Row(
                            children: [
                              // 1. Barcode Search Input
                              Expanded(
                                flex: 5,
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF1E293B),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: Colors.green.withOpacity(0.4)),
                                  ),
                                  child: TextField(
                                    controller: _searchController,
                                    style: const TextStyle(color: Colors.white, fontFamily: 'Cairo'),
                                    decoration: const InputDecoration(
                                      hintText: 'مسح / إدخال باركود الشراء...',
                                      hintStyle: TextStyle(color: Colors.white30, fontFamily: 'Cairo', fontSize: 13),
                                      prefixIcon: Icon(Icons.qr_code_2, color: Colors.green),
                                      border: InputBorder.none,
                                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                                    ),
                                    onSubmitted: (val) {
                                      final query = val.trim();
                                      if (query.isNotEmpty) {
                                        final matched = apiService.items.where((item) => item.barcode.trim() == query).toList();
                                        if (matched.isNotEmpty) {
                                          _addToCart(matched.first);
                                          _searchController.clear();
                                          setState(() {
                                            _searchQuery = '';
                                          });
                                        }
                                      }
                                    },
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),

                              // 2. Item Name Search Input
                              Expanded(
                                flex: 6,
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF1E293B),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: Colors.amber.withOpacity(0.4)),
                                  ),
                                  child: TextField(
                                    controller: _itemNameSearchController,
                                    style: const TextStyle(color: Colors.white, fontFamily: 'Cairo'),
                                    decoration: InputDecoration(
                                      hintText: 'البحث باسم الصنف فقط...',
                                      hintStyle: const TextStyle(color: Colors.white30, fontFamily: 'Cairo', fontSize: 13),
                                      prefixIcon: const Icon(Icons.search, color: Colors.amber),
                                      suffixIcon: _itemNameSearchController.text.isNotEmpty
                                          ? IconButton(
                                              icon: const Icon(Icons.clear, color: Colors.white54, size: 18),
                                              onPressed: () {
                                                setState(() {
                                                  _itemNameSearchController.clear();
                                                  _searchQuery = '';
                                                });
                                              },
                                            )
                                          : null,
                                      border: InputBorder.none,
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                                    ),
                                    onChanged: (val) {
                                      setState(() {
                                        _searchQuery = val;
                                      });
                                    },
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),

                          // Categories list
                          SizedBox(
                            height: 52,
                            child: Scrollbar(
                              controller: _categoriesScrollController,
                              thumbVisibility: true,
                              trackVisibility: true,
                              child: ListView(
                                controller: _categoriesScrollController,
                                scrollDirection: Axis.horizontal,
                                padding: const EdgeInsets.only(bottom: 12),
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.only(left: 8.0),
                                    child: ChoiceChip(
                                      label: const Text('كل الأصناف', style: TextStyle(fontFamily: 'Cairo')),
                                      selected: _selectedGroupId == 0,
                                      selectedColor: Colors.green,
                                      backgroundColor: const Color(0xFF1E293B),
                                      labelStyle: TextStyle(color: _selectedGroupId == 0 ? Colors.white : Colors.white60),
                                      onSelected: (_) => setState(() => _selectedGroupId = 0),
                                    ),
                                  ),
                                  ...apiService.groups.map((group) {
                                    return Padding(
                                      padding: const EdgeInsets.only(left: 8.0),
                                      child: ChoiceChip(
                                        label: Text(group.name, style: const TextStyle(fontFamily: 'Cairo')),
                                        selected: _selectedGroupId == group.id,
                                        selectedColor: Colors.green,
                                        backgroundColor: const Color(0xFF1E293B),
                                        labelStyle: TextStyle(color: _selectedGroupId == group.id ? Colors.white : Colors.white60),
                                        onSelected: (_) => setState(() => _selectedGroupId = group.id),
                                      ),
                                    );
                                  }),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),

                          // Grid
                          Expanded(
                            child: GridView.builder(
                              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                                maxCrossAxisExtent: 220,
                                mainAxisSpacing: 16,
                                crossAxisSpacing: 16,
                                childAspectRatio: 0.85,
                              ),
                              itemCount: filteredItems.length,
                              itemBuilder: (context, index) {
                                final item = filteredItems[index];
                                return Card(
                                  color: const Color(0xFF1E293B),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(10),
                                    onTap: () => _addToCart(item),
                                    child: Padding(
                                      padding: const EdgeInsets.all(12.0),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Container(
                                            width: double.infinity,
                                            height: 60,
                                            decoration: BoxDecoration(
                                              color: Colors.greenAccent.withOpacity(0.08),
                                              borderRadius: BorderRadius.circular(8),
                                            ),
                                            child: const Icon(Icons.add_shopping_cart, color: Colors.greenAccent, size: 28),
                                          ),
                                          const SizedBox(height: 10),
                                          Text(
                                            item.itemName,
                                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13, fontFamily: 'Cairo'),
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          const Spacer(),
                                          Text(
                                            'التكلفة: ${currencyFormat(item.cost)}',
                                            style: const TextStyle(color: Colors.orangeAccent, fontSize: 12, fontFamily: 'Cairo'),
                                          ),
                                          Text(
                                            'سعر البيع: ${currencyFormat(item.salesPrice)}',
                                            style: const TextStyle(color: Colors.greenAccent, fontSize: 12, fontFamily: 'Cairo'),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // --- RIGHT SIDE: CART PANEL (35%) ---
                  Expanded(
                    flex: 35,
                    child: Container(
                      decoration: const BoxDecoration(
                        color: Color(0xFF1E293B),
                        border: Border(right: BorderSide(color: Colors.white10)),
                      ),
                      child: Column(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: const BoxDecoration(
                              border: Border(bottom: BorderSide(color: Colors.white10)),
                            ),
                            child: const Row(
                              children: [
                                Icon(Icons.local_shipping, color: Colors.greenAccent),
                                SizedBox(width: 10),
                                Text(
                                  'المواد المشحونة للفاتورة',
                                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontFamily: 'Cairo'),
                                ),
                              ],
                            ),
                          ),

                          // Cart list
                          Expanded(
                            child: _cart.isEmpty
                                ? const Center(
                                    child: Text(
                                      'السلة فارغة. انقر لاستيراد المواد.',
                                      style: TextStyle(color: Colors.white30, fontFamily: 'Cairo'),
                                    ),
                                  )
                                : ListView.builder(
                                    itemCount: _cart.length,
                                    itemBuilder: (context, index) {
                                      final cartItem = _cart[index];
                                      return Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                        decoration: const BoxDecoration(
                                          border: Border(bottom: BorderSide(color: Colors.white10)),
                                        ),
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              cartItem.item.itemName,
                                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontFamily: 'Cairo'),
                                            ),
                                            const SizedBox(height: 8),
                                            Row(
                                              children: [
                                                // Qty controls
                                                IconButton(
                                                  icon: const Icon(Icons.remove_circle_outline, color: Colors.redAccent, size: 20),
                                                  onPressed: () => _updateQty(index, -1),
                                                ),
                                                Text(
                                                  '${cartItem.quantity}',
                                                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                                                ),
                                                IconButton(
                                                  icon: const Icon(Icons.add_circle_outline, color: Colors.greenAccent, size: 20),
                                                  onPressed: () => _updateQty(index, 1),
                                                ),
                                                const Spacer(),
                                                // Edit Cost field
                                                const Text('التكلفة: ', style: TextStyle(color: Colors.white54, fontSize: 11, fontFamily: 'Cairo')),
                                                SizedBox(
                                                  width: 70,
                                                  height: 30,
                                                  child: TextField(
                                                    style: const TextStyle(color: Colors.orangeAccent, fontSize: 12),
                                                    decoration: const InputDecoration(
                                                      fillColor: Colors.white12,
                                                      filled: true,
                                                      contentPadding: EdgeInsets.symmetric(horizontal: 4),
                                                      border: OutlineInputBorder(borderSide: BorderSide.none),
                                                    ),
                                                    keyboardType: TextInputType.number,
                                                    controller: TextEditingController(text: cartItem.purchaseCost.toString()),
                                                    onSubmitted: (val) {
                                                      final cost = double.tryParse(val);
                                                      if (cost == null) return;
                                                      if (cost < cartItem.item.cost) {
                                                        ScaffoldMessenger.of(context).showSnackBar(
                                                          SnackBar(
                                                            content: Text('عذراً، لا يمكن أن يقل سعر الشراء عن سعر الكلفة (${cartItem.item.cost.toStringAsFixed(2)})', style: const TextStyle(fontFamily: 'Cairo')),
                                                            backgroundColor: Colors.redAccent,
                                                          ),
                                                        );
                                                        return;
                                                      }
                                                      _updatePrices(index, cost, cartItem.salesPrice);
                                                    },
                                                  ),
                                                ),
                                                IconButton(
                                                  icon: const Icon(Icons.delete_outline, color: Colors.white30),
                                                  onPressed: () => _removeFromCart(index),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      );
                                    },
                                  ),
                          ),

                          // Calculation summary
                          Container(
                            padding: const EdgeInsets.all(20),
                            color: const Color(0xFF0F172A).withOpacity(0.5),
                            child: Column(
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Text('المجموع الفرعي (التكلفة):', style: TextStyle(color: Colors.white60, fontFamily: 'Cairo')),
                                    Text(currencyFormat(_subtotal), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                  ],
                                ),
                                const Divider(color: Colors.white10, height: 24),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Text('الإجمالي النهائي للمشتريات:', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold, fontFamily: 'Cairo')),
                                    Text(currencyFormat(_total), style: const TextStyle(color: Colors.greenAccent, fontSize: 20, fontWeight: FontWeight.bold)),
                                  ],
                                ),
                                const SizedBox(height: 16),
                                
                                // Payment selector
                                Row(
                                  children: [
                                    Expanded(
                                      child: ElevatedButton(
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: _payCash == 1 ? Colors.green : const Color(0xFF1E293B),
                                          foregroundColor: Colors.white,
                                        ),
                                        onPressed: () => setState(() => _payCash = 1),
                                        child: const Text('نقدي (Cash)', style: TextStyle(fontFamily: 'Cairo')),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: ElevatedButton(
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: _payCash == 2 ? Colors.green : const Color(0xFF1E293B),
                                          foregroundColor: Colors.white,
                                        ),
                                        onPressed: () => setState(() => _payCash = 2),
                                        child: const Text('آجل (Credit)', style: TextStyle(fontFamily: 'Cairo')),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 16),
                                
                                // Save
                                SizedBox(
                                  width: double.infinity,
                                  height: 50,
                                  child: ElevatedButton.icon(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.green,
                                      foregroundColor: Colors.white,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                    ),
                                    icon: const Icon(Icons.save_rounded),
                                    label: const Text('ترحيل فاتورة الشراء للـ SQL Server', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, fontFamily: 'Cairo')),
                                    onPressed: apiService.isLoading ? null : _savePurchase,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCurrencyDropdown(ApiService apiService) {
    final currencies = apiService.currencies;
    if (currencies.isEmpty) return const SizedBox.shrink();

    final currentCurrency = _activeCurrency;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.amberAccent.withOpacity(0.6), width: 1.2),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int>(
          value: currentCurrency.id,
          dropdownColor: const Color(0xFF1E293B),
          icon: const Icon(Icons.arrow_drop_down, color: Colors.amberAccent, size: 20),
          isDense: true,
          style: const TextStyle(
            color: Colors.white,
            fontFamily: 'Cairo',
            fontSize: 13,
            fontWeight: FontWeight.bold,
          ),
          items: currencies.map((c) {
            final isCurrent = c.id == currentCurrency.id;
            return DropdownMenuItem<int>(
              value: c.id,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.monetization_on_outlined, color: Colors.amberAccent, size: 16),
                  const SizedBox(width: 6),
                  Text(
                    '${c.name} (${c.symbol})',
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      color: isCurrent ? Colors.amberAccent : Colors.white,
                      fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.black26,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      'سعر الصرف: ${c.value.toStringAsFixed(c.value.truncateToDouble() == c.value ? 0 : 2)}',
                      style: const TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 11,
                        color: Colors.white70,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
          onChanged: (selectedId) {
            if (selectedId == null) return;
            final match = apiService.getCurrencyById(selectedId);
            if (match != null) {
              _onCurrencyChanged(match);
            }
          },
        ),
      ),
    );
  }

  Widget _buildAccountDropdown(ApiService apiService) {
    final accounts = apiService.accounts;
    final selectedAcc = _selectedAccount;
    final selectedAccId = selectedAcc?.accId ?? 0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.cyanAccent.withOpacity(0.6), width: 1.2),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int>(
          value: (selectedAccId > 0 && accounts.any((a) => a.accId == selectedAccId)) ? selectedAccId : 0,
          dropdownColor: const Color(0xFF1E293B),
          icon: const Icon(Icons.arrow_drop_down, color: Colors.cyanAccent, size: 20),
          isDense: true,
          style: const TextStyle(
            color: Colors.white,
            fontFamily: 'Cairo',
            fontSize: 13,
            fontWeight: FontWeight.bold,
          ),
          items: [
            const DropdownMenuItem<int>(
              value: 0,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.person_outline_rounded, color: Colors.cyanAccent, size: 16),
                  SizedBox(width: 6),
                  Text(
                    'مورد عام / نقدي',
                    style: TextStyle(fontFamily: 'Cairo', color: Colors.white70),
                  ),
                ],
              ),
            ),
            ...accounts.map((a) {
              final isCurrent = a.accId == selectedAccId;
              return DropdownMenuItem<int>(
                value: a.accId,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.account_balance_wallet_outlined, color: Colors.cyanAccent, size: 16),
                    const SizedBox(width: 6),
                    Text(
                      a.name,
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        color: isCurrent ? Colors.cyanAccent : Colors.white,
                        fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.black26,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        '#${a.accId}',
                        style: const TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 11,
                          color: Colors.white60,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ],
          onChanged: (newAccId) {
            setState(() {
              if (newAccId == null || newAccId == 0) {
                _selectedAccount = null;
              } else {
                final match = accounts.firstWhere((a) => a.accId == newAccId, orElse: () => AccountModel(id: 0, name: '', accId: newAccId));
                _selectedAccount = match;
              }
            });
          },
        ),
      ),
    );
  }
}

class PurchaseCartItem {
  final ItemModel item;
  int quantity;
  double purchaseCost;
  double salesPrice;

  PurchaseCartItem({
    required this.item,
    required this.quantity,
    required this.purchaseCost,
    required this.salesPrice,
  });
}
