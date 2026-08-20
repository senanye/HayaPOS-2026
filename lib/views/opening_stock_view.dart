import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart' hide TextDirection;
import '../services/api_service.dart';
import '../models/item.dart';
import '../models/currency.dart';
import '../models/transaction.dart';

class OpeningStockView extends StatefulWidget {
  const OpeningStockView({super.key});

  @override
  State<OpeningStockView> createState() => _OpeningStockViewState();
}

class _OpeningStockViewState extends State<OpeningStockView> {
  final List<StockCartItem> _cart = [];
  CurrencyModel? _selectedCurrency;
  int _selectedGroupId = 0;
  String _searchQuery = '';
  final _searchController = TextEditingController();

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
        item.price = item.item.cost * rate;
      }
    });
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final apiService = Provider.of<ApiService>(context, listen: false);
      if (apiService.items.isEmpty) {
        apiService.loadInitialData();
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
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
        _cart.add(StockCartItem(item: item, quantity: 10, price: item.cost * rate)); // Default to 10 for quick stock setup
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

  void _showEditPriceDialog(int index) {
    final cartItem = _cart[index];
    final controller = TextEditingController(text: cartItem.price.toStringAsFixed(2));
    
    showDialog(
      context: context,
      builder: (context) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: const Color(0xFF1E293B),
          title: Text(
            'تعديل سعر كلفة الصنف: ${cartItem.item.itemName}',
            style: const TextStyle(color: Colors.white, fontFamily: 'Cairo', fontSize: 16, fontWeight: FontWeight.bold),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'سعر الكلفة المرجعي: ${currencyFormat(cartItem.item.cost)}',
                style: const TextStyle(color: Colors.white70, fontFamily: 'Cairo', fontSize: 14),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: controller,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'السعر الجديد للجرد',
                  labelStyle: TextStyle(color: Colors.white70, fontFamily: 'Cairo'),
                  border: OutlineInputBorder(),
                  enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white30)),
                  focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.purpleAccent)),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('إلغاء', style: TextStyle(fontFamily: 'Cairo', color: Colors.white70)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.purpleAccent),
              onPressed: () {
                final newPrice = double.tryParse(controller.text);
                if (newPrice == null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('الرجاء إدخال سعر صحيح', style: TextStyle(fontFamily: 'Cairo')), backgroundColor: Colors.redAccent),
                  );
                  return;
                }
                if (newPrice < cartItem.item.cost) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'عذراً، لا يمكن أن يقل السعر عن سعر الكلفة (${cartItem.item.cost.toStringAsFixed(2)})',
                        style: const TextStyle(fontFamily: 'Cairo'),
                      ),
                      backgroundColor: Colors.redAccent,
                    ),
                  );
                  return;
                }
                setState(() {
                  _cart[index].price = newPrice;
                });
                Navigator.pop(context);
              },
              child: const Text('حفظ', style: TextStyle(fontFamily: 'Cairo', color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  void _removeFromCart(int index) {
    setState(() {
      _cart.removeAt(index);
    });
  }

  void _clearStock() {
    setState(() {
      _cart.clear();
      _searchController.clear();
      _searchQuery = '';
    });
  }

  double get _totalCostValue {
    return _cart.fold(0.0, (sum, item) => sum + (item.price * item.quantity));
  }

  Future<void> _saveOpeningStock() async {
    if (_cart.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('سلة الجرد فارغة!', style: TextStyle(fontFamily: 'Cairo')),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final apiService = Provider.of<ApiService>(context, listen: false);
    final user = apiService.currentUser;
    if (user == null) return;

    final List<TransactionDetailModel> details = _cart.map((cartItem) {
      final double itemSubtotal = cartItem.price * cartItem.quantity;
      final double itemTax = 0.0; // Opening stock has no tax
      final double itemTotal = itemSubtotal;

      return TransactionDetailModel(
        barcode: cartItem.item.barcode,
        itemName: cartItem.item.itemName,
        quantity: cartItem.quantity,
        salesPrice: cartItem.price,
        discount: 0,
        taxTotal: 0,
        totalItem: itemTotal.round(),
      );
    }).toList();

    final transaction = TransactionHeaderModel(
      date: apiService.selectedDate,
      description: 'مخزون أول المدة الجرد الافتتاحي Flutter',
      userId: user.userId,
      pointNo: apiService.pointNo,
      payCash: 1, // Default to cash/direct
      transType: 1, // 1 = Opening Stock (from schema check)
      moneyId: _activeCurrency.id,
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
                  Icon(Icons.check_circle, color: Colors.purpleAccent, size: 28),
                  SizedBox(width: 8),
                  Text(
                    'تم ترحيل الجرد الافتتاحي',
                    style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('رقم عملية الجرد: ${response['transNumber']}', style: const TextStyle(fontFamily: 'Cairo', fontSize: 16)),
                  const SizedBox(height: 8),
                  Text('القيمة الإجمالية للمخزون: ${currencyFormat(_totalCostValue)}', style: const TextStyle(fontFamily: 'Cairo', fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  const Text('تم حفظ الكميات بنجاح في SQL Server كـ (مخزون أول المدة).', style: TextStyle(fontFamily: 'Cairo', color: Colors.grey)),
                ],
              ),
              actions: [
                ElevatedButton(
                  onPressed: () {
                    Navigator.pop(context);
                    _clearStock();
                  },
                  child: const Text('جرد جديد', style: TextStyle(fontFamily: 'Cairo')),
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
                      Icon(Icons.inventory_2_outlined, color: Colors.purpleAccent, size: 28),
                      SizedBox(width: 12),
                      Text(
                        'تعريف مخزون أول المدة الجرد الافتتاحي',
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
                          Row(
                            children: [
                              Expanded(
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF1E293B),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: TextField(
                                    controller: _searchController,
                                    style: const TextStyle(color: Colors.white, fontFamily: 'Cairo'),
                                    decoration: const InputDecoration(
                                      hintText: 'البحث باسم الصنف أو الباركود لإضافته للجرد...',
                                      hintStyle: TextStyle(color: Colors.white30, fontFamily: 'Cairo'),
                                      prefixIcon: Icon(Icons.search, color: Colors.white54),
                                      border: InputBorder.none,
                                      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                                    ),
                                    onChanged: (val) {
                                      setState(() {
                                        _searchQuery = val;
                                      });
                                    },
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
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            SnackBar(
                                              content: Text('تم إضافة ${matched.first.itemName}', style: const TextStyle(fontFamily: 'Cairo')),
                                              backgroundColor: Colors.green,
                                              duration: const Duration(seconds: 1),
                                            ),
                                          );
                                        }
                                      }
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
                                      selectedColor: Colors.purple,
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
                                        selectedColor: Colors.purple,
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
                                              color: Colors.purpleAccent.withOpacity(0.08),
                                              borderRadius: BorderRadius.circular(8),
                                            ),
                                            child: const Icon(Icons.inventory_2_outlined, color: Colors.purpleAccent, size: 28),
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
                                            'سعر التكلفة: ${currencyFormat(item.cost)}',
                                            style: const TextStyle(color: Colors.orangeAccent, fontSize: 12, fontFamily: 'Cairo'),
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
                                Icon(Icons.edit_note, color: Colors.purpleAccent),
                                SizedBox(width: 10),
                                Text(
                                  'المواد وقائمة الجرد الحالية',
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
                                      'قائمة الجرد فارغة. انقر لإدراج المواد.',
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
                                        child: Row(
                                          children: [
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    cartItem.item.itemName,
                                                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontFamily: 'Cairo'),
                                                  ),
                                                  InkWell(
                                                    onTap: () => _showEditPriceDialog(index),
                                                    child: Row(
                                                      children: [
                                                        Text(
                                                          'التكلفة: ${currencyFormat(cartItem.price)} / ${cartItem.item.unitName}',
                                                          style: const TextStyle(color: Colors.purpleAccent, fontSize: 12, fontFamily: 'Cairo', decoration: TextDecoration.underline),
                                                        ),
                                                        const SizedBox(width: 4),
                                                        const Icon(Icons.edit, size: 12, color: Colors.purpleAccent),
                                                      ],
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            // Qty controls (using inputs or +/-)
                                            Row(
                                              children: [
                                                IconButton(
                                                  icon: const Icon(Icons.remove_circle_outline, color: Colors.redAccent, size: 20),
                                                  onPressed: () => _updateQty(index, -10),
                                                ),
                                                Text(
                                                  '${cartItem.quantity}',
                                                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                                                ),
                                                IconButton(
                                                  icon: const Icon(Icons.add_circle_outline, color: Colors.greenAccent, size: 20),
                                                  onPressed: () => _updateQty(index, 10),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(width: 8),
                                            // Subtotal value
                                             SizedBox(
                                               width: 80,
                                               child: Text(
                                                 currencyFormat(cartItem.price * cartItem.quantity),
                                                 textAlign: TextAlign.end,
                                                 style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                                               ),
                                             ),
                                            IconButton(
                                              icon: const Icon(Icons.delete_outline, color: Colors.white30),
                                              onPressed: () => _removeFromCart(index),
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
                                    const Text('القيمة الإجمالية للجرد الجاري:', style: TextStyle(color: Colors.white60, fontFamily: 'Cairo')),
                                    Text(currencyFormat(_totalCostValue), style: const TextStyle(color: Colors.purpleAccent, fontSize: 18, fontWeight: FontWeight.bold)),
                                  ],
                                ),
                                const Divider(color: Colors.white10, height: 24),
                                const Text(
                                  '* جرد مخزون أول المدة لا يحتوي على ضرائب أو مبيعات نقدية/آجلة، هو فقط لتدشين الكميات في السيرفر.',
                                  style: TextStyle(color: Colors.white38, fontSize: 11, fontFamily: 'Cairo'),
                                ),
                                const SizedBox(height: 16),
                                
                                // Save
                                SizedBox(
                                  width: double.infinity,
                                  height: 52,
                                  child: ElevatedButton.icon(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.purpleAccent[700],
                                      foregroundColor: Colors.white,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                    ),
                                    icon: const Icon(Icons.save_rounded),
                                    label: const Text('ترحيل الجرد الافتتاحي للـ SQL Server', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, fontFamily: 'Cairo')),
                                    onPressed: apiService.isLoading ? null : _saveOpeningStock,
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
}

class StockCartItem {
  final ItemModel item;
  int quantity;
  double price;

  StockCartItem({required this.item, required this.quantity, required this.price});
}
