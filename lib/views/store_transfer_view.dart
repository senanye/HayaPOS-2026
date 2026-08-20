import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart' hide TextDirection;
import '../services/api_service.dart';
import '../models/item.dart';
import '../models/currency.dart';
import '../models/account.dart';
import '../models/transaction.dart';

class StoreTransferView extends StatefulWidget {
  final bool isReceipt; // true = Store Receipt (22), false = Store Issuance (23)
  const StoreTransferView({super.key, required this.isReceipt});

  @override
  State<StoreTransferView> createState() => _StoreTransferViewState();
}

class _StoreTransferViewState extends State<StoreTransferView> {
  final List<TransferCartItem> _cart = [];
  CurrencyModel? _selectedCurrency;
  AccountModel? _selectedAccount;
  int _selectedGroupId = 0;
  String _searchQuery = '';
  final _searchController = TextEditingController();
  final _itemNameSearchController = TextEditingController();
  final _categoriesScrollController = ScrollController();
  int _selectedBranchId = 1; // Default to branch 1
  List<Map<String, dynamic>> _branches = [];

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
    _loadBranches();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final apiService = Provider.of<ApiService>(context, listen: false);
      if (apiService.items.isEmpty) {
        apiService.loadInitialData();
      }
    });
  }

  Future<void> _loadBranches() async {
    try {
      final apiService = Provider.of<ApiService>(context, listen: false);
      final list = await apiService.getLocalPoints();
      final currentPointNo = apiService.pointNo;
      if (mounted) {
        setState(() {
          _branches = list.where((x) => (x['fldPointNO'] as int) != currentPointNo).toList();
          if (_branches.isNotEmpty) {
            final exists = _branches.any((x) => x['fldPointNO'] == _selectedBranchId);
            if (!exists) {
              _selectedBranchId = _branches[0]['fldPointNO'];
            }
          }
        });
      }
    } catch (_) {}
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
        _cart.add(TransferCartItem(item: item, quantity: 1, price: item.cost * rate));
      }
    });
  }

  void _handleBarcodeSubmit(String value) {
    if (value.trim().isEmpty) return;
    final apiService = Provider.of<ApiService>(context, listen: false);
    final items = apiService.items;
    
    try {
      final item = items.firstWhere((x) => x.barcode == value.trim());
      _addToCart(item);
      _searchController.clear();
      setState(() {
        _searchQuery = '';
      });
    } catch (_) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('الصنف ذو الباركود $value غير موجود!', style: const TextStyle(fontFamily: 'Cairo')),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
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
            'تعديل سعر الصنف: ${cartItem.item.itemName}',
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
                decoration: InputDecoration(
                  labelText: 'السعر الجديد',
                  labelStyle: const TextStyle(color: Colors.white70, fontFamily: 'Cairo'),
                  border: const OutlineInputBorder(),
                  enabledBorder: const OutlineInputBorder(borderSide: BorderSide(color: Colors.white30)),
                  focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: widget.isReceipt ? Colors.tealAccent : Colors.orangeAccent)),
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
              style: ElevatedButton.styleFrom(backgroundColor: widget.isReceipt ? Colors.teal[700] : Colors.orange[800]),
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

  void _clearCart() {
    setState(() {
      _cart.clear();
      _selectedAccount = null;
      _searchController.clear();
      _searchQuery = '';
    });
  }

  double get _totalValue {
    return _cart.fold(0.0, (sum, item) => sum + (item.price * item.quantity));
  }

  Future<void> _saveTransfer() async {
    if (_cart.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('السلة فارغة!', style: TextStyle(fontFamily: 'Cairo')),
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
      return TransactionDetailModel(
        barcode: cartItem.item.barcode,
        itemName: cartItem.item.itemName,
        quantity: cartItem.quantity,
        salesPrice: cartItem.price,
        discount: 0,
        taxTotal: 0,
        totalItem: itemSubtotal.round(),
      );
    }).toList();

    final int fldType = widget.isReceipt ? 22 : 23;
    final String typeName = widget.isReceipt ? 'توريد مخزني' : 'صرف مخزني';

    final transaction = TransactionHeaderModel(
      date: apiService.selectedDate,
      description: widget.isReceipt 
          ? 'أمر توريد مخزني وارد من فرع رقم $_selectedBranchId' 
          : 'أمر صرف مخزني صادر إلى فرع رقم $_selectedBranchId',
      userId: user.userId,
      pointNo: apiService.pointNo,
      payCash: _selectedBranchId, // stores the other branch ID
      transType: fldType,
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
              title: Row(
                children: [
                  Icon(Icons.check_circle, color: widget.isReceipt ? Colors.tealAccent : Colors.orangeAccent, size: 28),
                  const SizedBox(width: 8),
                  Text(
                    'تم ترحيل $typeName بنجاح',
                    style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('رقم المستند: ${response['transNumber']}', style: const TextStyle(fontFamily: 'Cairo', fontSize: 16)),
                  const SizedBox(height: 8),
                  Text('الإجمالي: ${currencyFormat(_totalValue)}', style: const TextStyle(fontFamily: 'Cairo', fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Text('تم حفظ المستند في السيرفر بنجاح ونقله للفرع الآخر.', style: const TextStyle(fontFamily: 'Cairo', color: Colors.grey)),
                ],
              ),
              actions: [
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: widget.isReceipt ? Colors.teal : Colors.orange),
                  onPressed: () {
                    Navigator.pop(context);
                    _clearCart();
                  },
                  child: const Text('مستند جديد', style: TextStyle(fontFamily: 'Cairo', color: Colors.white)),
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
              title: const Text('فشل حفظ المستند', style: TextStyle(fontFamily: 'Cairo', color: Colors.red)),
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
    final themeColor = widget.isReceipt ? Colors.teal : Colors.orange;

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
                  Row(
                    children: [
                      Icon(widget.isReceipt ? Icons.download_rounded : Icons.upload_rounded, color: themeColor, size: 28),
                      const SizedBox(width: 12),
                      Text(
                        widget.isReceipt ? 'أمر توريد مخزني (وارد من فرع)' : 'أمر صرف مخزني (صادر إلى فرع)',
                        style: const TextStyle(
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
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        children: [
                          // Search & Filter Box
                          Row(
                            children: [
                              // 1. Barcode Search Input
                              Expanded(
                                flex: 5,
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF1E293B),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: themeColor.withOpacity(0.4)),
                                  ),
                                  child: TextField(
                                    controller: _searchController,
                                    style: const TextStyle(color: Colors.white, fontFamily: 'Cairo'),
                                    onSubmitted: _handleBarcodeSubmit,
                                    decoration: InputDecoration(
                                      prefixIcon: Icon(Icons.qr_code_2, color: themeColor),
                                      hintText: 'مسح / إدخال الباركود...',
                                      hintStyle: const TextStyle(color: Colors.white30, fontFamily: 'Cairo', fontSize: 13),
                                      border: InputBorder.none,
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                                    ),
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
                          const SizedBox(height: 12),
                          
                          // Horizontal Groups Scrollbar
                          SizedBox(
                            height: 48,
                            child: Scrollbar(
                              controller: _categoriesScrollController,
                              thumbVisibility: true,
                              trackVisibility: true,
                              child: SingleChildScrollView(
                                controller: _categoriesScrollController,
                                scrollDirection: Axis.horizontal,
                                padding: const EdgeInsets.only(bottom: 8),
                                child: Row(
                                  children: [
                                    ChoiceChip(
                                      label: const Text('الكل', style: TextStyle(fontFamily: 'Cairo')),
                                      selected: _selectedGroupId == 0,
                                      selectedColor: themeColor,
                                      backgroundColor: const Color(0xFF1E293B),
                                      labelStyle: const TextStyle(color: Colors.white),
                                      onSelected: (selected) {
                                        setState(() => _selectedGroupId = 0);
                                      },
                                    ),
                                    const SizedBox(width: 8),
                                    ...apiService.groups.map((g) => Padding(
                                      padding: const EdgeInsets.only(left: 8.0),
                                      child: ChoiceChip(
                                        label: Text(g.name, style: const TextStyle(fontFamily: 'Cairo')),
                                        selected: _selectedGroupId == g.id,
                                        selectedColor: themeColor,
                                        backgroundColor: const Color(0xFF1E293B),
                                        labelStyle: const TextStyle(color: Colors.white),
                                        onSelected: (selected) {
                                          setState(() => _selectedGroupId = g.id);
                                        },
                                      ),
                                    )),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          
                          // Grid of items
                          Expanded(
                            child: filteredItems.isEmpty
                                ? const Center(child: Text('لا توجد منتجات مطابقة', style: TextStyle(color: Colors.white30, fontFamily: 'Cairo')))
                                : GridView.builder(
                                    gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                                      maxCrossAxisExtent: 220,
                                      childAspectRatio: 0.85,
                                      crossAxisSpacing: 12,
                                      mainAxisSpacing: 12,
                                    ),
                                    itemCount: filteredItems.length,
                                    itemBuilder: (context, index) {
                                      final item = filteredItems[index];
                                      return Card(
                                        color: const Color(0xFF1E293B),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                        child: InkWell(
                                          onTap: () => _addToCart(item),
                                          borderRadius: BorderRadius.circular(8),
                                          child: Padding(
                                            padding: const EdgeInsets.all(12.0),
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Expanded(
                                                  child: Container(
                                                    alignment: Alignment.center,
                                                    decoration: BoxDecoration(
                                                      color: Colors.white.withOpacity(0.03),
                                                      borderRadius: BorderRadius.circular(6),
                                                    ),
                                                    child: Text(
                                                      item.itemName[0],
                                                      style: TextStyle(color: themeColor, fontSize: 32, fontWeight: FontWeight.bold),
                                                    ),
                                                  ),
                                                ),
                                                const SizedBox(height: 8),
                                                Text(
                                                  item.itemName,
                                                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontFamily: 'Cairo'),
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                                const SizedBox(height: 4),
                                                Text(
                                                  'الكود: ${item.barcode}',
                                                  style: const TextStyle(color: Colors.white38, fontSize: 11),
                                                ),
                                                const SizedBox(height: 6),
                                                Text(
                                                  currencyFormat(item.cost),
                                                  style: TextStyle(color: themeColor, fontWeight: FontWeight.bold),
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
                  
                  // --- RIGHT SIDE: CART (35%) ---
                  Expanded(
                    flex: 35,
                    child: Container(
                      color: const Color(0xFF111827),
                      child: Column(
                        children: [
                          // Select Branch Box
                          Container(
                            padding: const EdgeInsets.all(16.0),
                            color: const Color(0xFF1F2937),
                            child: Row(
                              children: [
                                Icon(Icons.store_mall_directory_rounded, color: themeColor),
                                const SizedBox(width: 8),
                                Text(
                                  widget.isReceipt ? 'من الفرع المورد:' : 'إلى الفرع المستلم:',
                                  style: const TextStyle(color: Colors.white70, fontFamily: 'Cairo', fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: DropdownButtonFormField<int>(
                                    value: _selectedBranchId,
                                    dropdownColor: const Color(0xFF1E293B),
                                    style: const TextStyle(color: Colors.white, fontFamily: 'Cairo'),
                                    decoration: const InputDecoration(
                                      contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                                      border: OutlineInputBorder(),
                                    ),
                                    items: _branches.isEmpty
                                        ? [
                                            DropdownMenuItem<int>(
                                              value: _selectedBranchId,
                                              child: Text('فرع رقم $_selectedBranchId'),
                                            )
                                          ]
                                        : _branches
                                            .where((p) => (p['fldPointNO'] as int) != apiService.pointNo)
                                            .map((p) {
                                            final id = p['fldPointNO'] as int;
                                            final name = p['fldName'] as String;
                                            return DropdownMenuItem<int>(
                                              value: id,
                                              child: Text('$name (فرع $id)'),
                                            );
                                          }).toList(),
                                    onChanged: (val) {
                                      if (val != null) {
                                        setState(() {
                                          _selectedBranchId = val;
                                        });
                                      }
                                    },
                                  ),
                                ),
                              ],
                            ),
                          ),
                          
                          // Cart Items Header
                          Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text('الأصناف المحددة', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold, fontFamily: 'Cairo')),
                                if (_cart.isNotEmpty)
                                  IconButton(
                                    icon: const Icon(Icons.delete_sweep, color: Colors.redAccent),
                                    onPressed: _clearCart,
                                    tooltip: 'مسح الكل',
                                  ),
                              ],
                            ),
                          ),
                          
                          // Cart Items List
                          Expanded(
                            child: _cart.isEmpty
                                ? const Center(child: Text('السلة فارغة. اختر أصنافاً من اليمين', style: TextStyle(color: Colors.white24, fontFamily: 'Cairo')))
                                : ListView.builder(
                                    itemCount: _cart.length,
                                    itemBuilder: (context, index) {
                                      final cartItem = _cart[index];
                                      return Card(
                                        color: const Color(0xFF1F2937),
                                        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                                        child: Padding(
                                          padding: const EdgeInsets.all(12.0),
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Row(
                                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                                children: [
                                                  Expanded(
                                                    child: Text(
                                                      cartItem.item.itemName,
                                                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontFamily: 'Cairo'),
                                                    ),
                                                  ),
                                                  IconButton(
                                                    icon: const Icon(Icons.close, color: Colors.redAccent, size: 18),
                                                    onPressed: () => _removeFromCart(index),
                                                  ),
                                                ],
                                              ),
                                              Row(
                                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                                children: [
                                                  // Qty controls
                                                  Row(
                                                    children: [
                                                      IconButton(
                                                        icon: const Icon(Icons.remove_circle_outline, color: Colors.redAccent),
                                                        onPressed: () => _updateQty(index, -1),
                                                      ),
                                                      Text(
                                                        cartItem.quantity.toString(),
                                                        style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                                                      ),
                                                      IconButton(
                                                        icon: const Icon(Icons.add_circle_outline, color: Colors.greenAccent),
                                                        onPressed: () => _updateQty(index, 1),
                                                      ),
                                                    ],
                                                  ),
                                                  
                                                  // Edit price button
                                                  InkWell(
                                                    onTap: () => _showEditPriceDialog(index),
                                                    child: Row(
                                                      children: [
                                                        Text(
                                                          currencyFormat(cartItem.price),
                                                          style: TextStyle(color: themeColor, fontWeight: FontWeight.bold),
                                                        ),
                                                        const SizedBox(width: 4),
                                                        const Icon(Icons.edit, color: Colors.white54, size: 14),
                                                      ],
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ],
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                          ),
                          
                          // Summary Footer
                          Container(
                            padding: const EdgeInsets.all(20),
                            color: const Color(0xFF1E293B),
                            child: Column(
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Text('إجمالي قيمة المستند:', style: TextStyle(color: Colors.white70, fontSize: 15, fontFamily: 'Cairo')),
                                    Text(
                                      currencyFormat(_totalValue),
                                      style: TextStyle(color: themeColor, fontSize: 20, fontWeight: FontWeight.bold),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 16),
                                
                                // Save button
                                SizedBox(
                                  width: double.infinity,
                                  height: 52,
                                  child: ElevatedButton.icon(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: themeColor[700],
                                      foregroundColor: Colors.white,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                    ),
                                    icon: const Icon(Icons.save_rounded),
                                    label: Text(
                                      widget.isReceipt ? 'ترحيل مستند التوريد للـ SQL Server' : 'ترحيل مستند الصرف للـ SQL Server',
                                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, fontFamily: 'Cairo'),
                                    ),
                                    onPressed: apiService.isLoading ? null : _saveTransfer,
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
                    'حساب عام / غير محدد',
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

class TransferCartItem {
  final ItemModel item;
  int quantity;
  double price;

  TransferCartItem({required this.item, required this.quantity, required this.price});
}
