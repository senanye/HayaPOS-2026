import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart' hide TextDirection;
import '../services/api_service.dart';
import '../services/print_service.dart';
import '../services/barcode_label_service.dart';
import '../models/item.dart';
import '../models/currency.dart';
import '../models/account.dart';
import '../models/transaction.dart';

class ReturnsView extends StatefulWidget {
  const ReturnsView({super.key});

  @override
  State<ReturnsView> createState() => _ReturnsViewState();
}

class _ReturnsViewState extends State<ReturnsView> {
  final List<ReturnCartItem> _cart = [];
  double? _editingTransNumber;
  CurrencyModel? _selectedCurrency;
  AccountModel? _selectedAccount;
  int _selectedGroupId = 0;
  String _searchQuery = '';
  final _searchController = TextEditingController();
  final _itemNameSearchController = TextEditingController();
  final _barcodeFocusNode = FocusNode();
  
  int _payCash = 1; // 1 = Cash, 2 = Credit
  double _refundAmount = 0.0;

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
        item.price = item.item.salesPrice * rate;
      }
    });
  }

  Future<void> _showLoadReturnInvoiceDialog() async {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: const Color(0xFF0F172A),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: Colors.redAccent, width: 1.5)),
          title: const Row(
            children: [
              Icon(Icons.edit_note_rounded, color: Colors.redAccent, size: 28),
              SizedBox(width: 8),
              Text('استدعاء فاتورة مرتجع للتعديل', style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, color: Colors.white)),
            ],
          ),
          content: TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            style: const TextStyle(color: Colors.white, fontFamily: 'Cairo'),
            decoration: InputDecoration(
              labelText: 'أدخل رقم فاتورة المرتجع (مثال: 26713600001)',
              labelStyle: const TextStyle(color: Colors.white70, fontFamily: 'Cairo'),
              filled: true,
              fillColor: const Color(0xFF1E293B),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('إلغاء', style: TextStyle(fontFamily: 'Cairo', color: Colors.white60)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white),
              onPressed: () async {
                final numVal = double.tryParse(controller.text.trim());
                if (numVal == null) return;
                Navigator.pop(context);
                await _loadReturnForEdit(numVal);
              },
              child: const Text('بحث واستدعاء المرتجع', style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _loadReturnForEdit(double transNum) async {
    final apiService = Provider.of<ApiService>(context, listen: false);
    try {
      final trans = await apiService.fetchTransactionByNumber(transNum);
      final details = trans['details'] as List? ?? [];
      if (details.isEmpty) {
        throw Exception('لا توجد بنود مسجلة في هذه الفاتورة المرتجعة');
      }

      final moneyId = (trans['moneyId'] as num?)?.toInt() ?? apiService.defaultMoneyId;
      final matchedCurrency = apiService.getCurrencyById(moneyId) ?? apiService.defaultCurrency;

      final accId = (trans['accountId'] as num?)?.toInt() ?? 0;
      AccountModel? matchedAccount;
      if (accId > 0) {
        final matches = apiService.accounts.where((a) => a.accId == accId).toList();
        if (matches.isNotEmpty) {
          matchedAccount = matches.first;
        } else {
          matchedAccount = AccountModel(id: 0, name: trans['accountName'] ?? 'حساب $accId', accId: accId);
        }
      }

      setState(() {
        _editingTransNumber = transNum;
        _selectedCurrency = matchedCurrency;
        _selectedAccount = matchedAccount;
        _cart.clear();
        for (final d in details) {
          final barcode = d['barcode'] ?? '';
          final name = d['itemName'] ?? '';
          final qty = (d['quantity'] as num? ?? 1).toInt();
          final price = (d['salesPrice'] as num? ?? 0.0).toDouble();
          final unit = d['unitName'] ?? 'حبة';

          _cart.add(ReturnCartItem(
            item: ItemModel(
              barcode: barcode,
              itemName: name,
              salesPrice: price / (matchedCurrency.value > 0 ? matchedCurrency.value : 1.0),
              unitName: unit,
              cost: 0,
              groupId: 0,
              itemId: 0,
              unityId: 1,
              moneyId: moneyId,
              isActive: true,
            ),
            quantity: qty,
            price: price,
          ));
        }
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ تم فتح واستدعاء فاتورة المرتجع رقم #${transNum.toInt()} بنجاح للتعديل! عدل البنود ثم اضغط "حفظ تعديل المرتجع"', style: const TextStyle(fontFamily: 'Cairo')),
            backgroundColor: Colors.redAccent,
            duration: const Duration(seconds: 6),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ خطأ استدعاء المرتجع: $e', style: const TextStyle(fontFamily: 'Cairo')), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final apiService = Provider.of<ApiService>(context, listen: false);
      if (apiService.items.isEmpty) {
        apiService.loadInitialData();
      }
      _barcodeFocusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _itemNameSearchController.dispose();
    _categoriesScrollController.dispose();
    _barcodeFocusNode.dispose();
    super.dispose();
  }

  void _addToCart(ItemModel item) {
    setState(() {
      final index = _cart.indexWhere((x) => x.item.barcode == item.barcode);
      if (index >= 0) {
        _cart[index].quantity++;
      } else {
        final currentRate = _currencyRate;
        _cart.add(ReturnCartItem(
          item: item,
          quantity: 1,
          price: item.salesPrice * currentRate,
        ));
      }
    });
    _barcodeFocusNode.requestFocus();
  }

  void _onBarcodeSubmitted(String query) {
    final apiService = Provider.of<ApiService>(context, listen: false);
    query = query.trim();
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
            content: Text('تم إضافة ${matched.first.itemName} إلى المرتجع', style: const TextStyle(fontFamily: 'Cairo')),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 1),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('لم يتم العثور على صنف بالباركود: $query', style: const TextStyle(fontFamily: 'Cairo')),
            backgroundColor: Colors.orange,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
    _barcodeFocusNode.requestFocus();
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
    final convertedCost = cartItem.item.cost * _currencyRate;
    
    showDialog(
      context: context,
      builder: (context) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: const Color(0xFF1E293B),
          title: Text(
            'تعديل سعر المرتجع الصنف: ${cartItem.item.itemName}',
            style: const TextStyle(color: Colors.white, fontFamily: 'Cairo', fontSize: 16, fontWeight: FontWeight.bold),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'سعر الكلفة الحالي: ${currencyFormat(convertedCost)}',
                style: const TextStyle(color: Colors.white70, fontFamily: 'Cairo', fontSize: 14),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: controller,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: 'سعر المرتجع الجديد ($_currencySymbol)',
                  labelStyle: const TextStyle(color: Colors.white70, fontFamily: 'Cairo'),
                  border: const OutlineInputBorder(),
                  enabledBorder: const OutlineInputBorder(borderSide: BorderSide(color: Colors.white30)),
                  focusedBorder: const OutlineInputBorder(borderSide: BorderSide(color: Colors.blueAccent)),
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
              style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
              onPressed: () {
                final newPrice = double.tryParse(controller.text);
                if (newPrice == null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('الرجاء إدخال سعر صحيح', style: TextStyle(fontFamily: 'Cairo')), backgroundColor: Colors.redAccent),
                  );
                  return;
                }
                if (newPrice < convertedCost && cartItem.item.cost > 0) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'عذراً، لا يمكن أن يقل سعر المرتجع عن سعر الكلفة (${currencyFormat(convertedCost)})',
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

  void _clearReturn() {
    setState(() {
      _cart.clear();
      _selectedAccount = null;
      _payCash = 1;
      _searchController.clear();
      _itemNameSearchController.clear();
      _searchQuery = '';
    });
  }

  double get _subtotal {
    return _cart.fold(0.0, (sum, item) => sum + (item.price * item.quantity));
  }

  double get _tax {
    return 0.0; // Cancelled Tax for Sales Returns
  }

  double get _total {
    return _subtotal;
  }

  Future<void> _saveReturn() async {
    if (_cart.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('سلة المرتجعات فارغة!', style: TextStyle(fontFamily: 'Cairo')),
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
      description: 'فاتورة مرتجع مبيعات Flutter',
      userId: user.userId,
      pointNo: apiService.pointNo,
      payCash: _payCash,
      transType: 36, // 36 = Return (from schema check)
      moneyId: _activeCurrency.id,
      accountId: _selectedAccount?.accId ?? 0,
      details: details,
    );

    try {
      Map<String, dynamic> response;
      if (_editingTransNumber != null) {
        final transData = {
          "date": apiService.selectedDate,
          "description": 'تعديل مرتجع مبيعات #${_editingTransNumber!.toInt()}',
          "userId": user.userId,
          "pointNo": apiService.pointNo,
          "payCash": _payCash,
          "transType": 36,
          "moneyId": _activeCurrency.id,
          "accountId": _selectedAccount?.accId ?? 0,
          "details": details.map((d) => d.toJson()).toList(),
        };
        response = await apiService.updateTransaction(_editingTransNumber!, transData);
      } else {
        response = await apiService.saveTransaction(transaction);
      }

      final savedTransNum = response['transNumber'] ?? _editingTransNumber ?? 0;
      _editingTransNumber = null;
      
      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => Directionality(
            textDirection: TextDirection.rtl,
            child: AlertDialog(
              title: const Row(
                children: [
                  Icon(Icons.check_circle, color: Colors.redAccent, size: 28),
                  SizedBox(width: 8),
                  Text(
                    'تم حفظ المرتجع بنجاح',
                    style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('رقم الفاتورة المرتجعة: ${response['transNumber']}', style: const TextStyle(fontFamily: 'Cairo', fontSize: 16)),
                  const SizedBox(height: 8),
                  Text('المبلغ المسترد: ${currencyFormat(_total)}', style: const TextStyle(fontFamily: 'Cairo', fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  const Text('تم حفظ الفاتورة بنجاح في SQL Server وإعادة المواد للمخزون.', style: TextStyle(fontFamily: 'Cairo', color: Colors.green)),
                ],
              ),
              actions: [
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blueAccent,
                    foregroundColor: Colors.white,
                  ),
                  icon: const Icon(Icons.print_rounded),
                  label: const Text('🖨️ طباعة المرتجع', style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
                  onPressed: () {
                    final user = apiService.currentUser;
                    final receiptHtml = _generateReturnReceiptHtml(
                      pointName: apiService.pointName,
                      pointNo: apiService.pointNo,
                      transNumber: '${savedTransNum is num && savedTransNum > 0 ? (savedTransNum.truncateToDouble() == savedTransNum ? savedTransNum.toInt() : savedTransNum) : response['transNumber']}',
                      date: apiService.selectedDate,
                      userId: user?.userId ?? 1,
                      userName: user?.userName ?? 'مستخدم',
                      cartItems: List.from(_cart),
                      subtotal: _subtotal,
                      tax: _tax,
                      total: _total,
                      currencySymbol: _currencySymbol,
                      currencyName: _activeCurrency.name.isNotEmpty ? _activeCurrency.name : _currencySymbol,
                      logoBase64: apiService.logoBase64,
                    );
                    PrintService.printHtml(receiptHtml);
                  },
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () {
                    Navigator.pop(context);
                    _clearReturn();
                  },
                  child: const Text('مرتجع جديد', style: TextStyle(fontFamily: 'Cairo')),
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

  Future<void> _showImportFromSalesInvoiceDialog() async {
    final invoiceNumberController = TextEditingController();
    bool isLoading = false;
    Map<String, dynamic>? invoiceData;
    List<Map<String, dynamic>> selectedItems = []; // list of {item: ItemModel, originalQty: int, returnQty: int}
    String? errorMessage;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          return Directionality(
            textDirection: TextDirection.rtl,
            child: AlertDialog(
              backgroundColor: const Color(0xFF0F172A),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: const BorderSide(color: Colors.tealAccent, width: 1.5),
              ),
              title: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.receipt_long_rounded, color: Colors.tealAccent, size: 28),
                      SizedBox(width: 8),
                      Text(
                        'استيراد أصناف من فاتورة مبيعات',
                        style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, color: Colors.white, fontSize: 16),
                      ),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white60),
                    onPressed: () => Navigator.pop(dialogContext),
                  ),
                ],
              ),
              content: SizedBox(
                width: 600,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (invoiceData == null) ...[
                      // Step 1: Enter invoice number
                      const Text(
                        'يرجى إدخال رقم فاتورة المبيعات الأصلية لجلب موادها واختيار المرتجع منها:',
                        style: TextStyle(fontFamily: 'Cairo', color: Colors.white70, fontSize: 13),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: invoiceNumberController,
                        keyboardType: TextInputType.number,
                        style: const TextStyle(color: Colors.white, fontFamily: 'Cairo'),
                        decoration: InputDecoration(
                          labelText: 'رقم فاتورة المبيعات (مثال: 26713500001)',
                          labelStyle: const TextStyle(color: Colors.white70, fontFamily: 'Cairo'),
                          filled: true,
                          fillColor: const Color(0xFF1E293B),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                          errorText: errorMessage,
                        ),
                        onSubmitted: (val) async {
                          if (val.trim().isEmpty) return;
                          setDialogState(() {
                            isLoading = true;
                            errorMessage = null;
                          });
                          try {
                            final apiService = Provider.of<ApiService>(context, listen: false);
                            final numVal = double.tryParse(val.trim());
                            if (numVal == null) throw Exception('رقم الفاتورة غير صحيح');
                            final trans = await apiService.fetchTransactionByNumber(numVal);
                            final details = trans['details'] as List? ?? [];
                            if (details.isEmpty) {
                              throw Exception('لا توجد أصناف في هذه الفاتورة');
                            }
                            
                            final itemsList = <Map<String, dynamic>>[];
                            for (final d in details) {
                              final barcode = d['barcode'] ?? '';
                              final name = d['itemName'] ?? '';
                              final qty = (d['quantity'] as num? ?? 1).toInt();
                              final price = (d['salesPrice'] as num? ?? 0.0).toDouble();
                              final unit = d['unitName'] ?? 'حبة';
                              final moneyId = (trans['moneyId'] as num?)?.toInt() ?? apiService.defaultMoneyId;
                              
                              itemsList.add({
                                'item': ItemModel(
                                  barcode: barcode,
                                  itemName: name,
                                  salesPrice: price / (_currencyRate),
                                  unitName: unit,
                                  cost: 0,
                                  groupId: 0,
                                  itemId: 0,
                                  unityId: 1,
                                  moneyId: moneyId,
                                  isActive: true,
                                ),
                                'originalQty': qty,
                                'returnQty': qty,
                              });
                            }
                            
                            setDialogState(() {
                              invoiceData = trans;
                              selectedItems = itemsList;
                              isLoading = false;
                            });
                          } catch (e) {
                            setDialogState(() {
                              errorMessage = e.toString().replaceAll('Exception:', '').trim();
                              isLoading = false;
                            });
                          }
                        },
                      ),
                      const SizedBox(height: 16),
                      if (isLoading)
                        const Center(child: CircularProgressIndicator(color: Colors.tealAccent))
                      else
                        Align(
                          alignment: Alignment.centerLeft,
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(backgroundColor: Colors.tealAccent.shade700, foregroundColor: Colors.white),
                            icon: const Icon(Icons.search),
                            label: const Text('بحث وجلب الفاتورة', style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
                            onPressed: () async {
                              final val = invoiceNumberController.text.trim();
                              if (val.isEmpty) return;
                              setDialogState(() {
                                isLoading = true;
                                errorMessage = null;
                              });
                              try {
                                final apiService = Provider.of<ApiService>(context, listen: false);
                                final numVal = double.tryParse(val);
                                if (numVal == null) throw Exception('رقم الفاتورة غير صحيح');
                                final trans = await apiService.fetchTransactionByNumber(numVal);
                                final details = trans['details'] as List? ?? [];
                                if (details.isEmpty) {
                                  throw Exception('لا توجد أصناف في هذه الفاتورة');
                                }
                                
                                final itemsList = <Map<String, dynamic>>[];
                                for (final d in details) {
                                  final barcode = d['barcode'] ?? '';
                                  final name = d['itemName'] ?? '';
                                  final qty = (d['quantity'] as num? ?? 1).toInt();
                                  final price = (d['salesPrice'] as num? ?? 0.0).toDouble();
                                  final unit = d['unitName'] ?? 'حبة';
                                  final moneyId = (trans['moneyId'] as num?)?.toInt() ?? apiService.defaultMoneyId;
                                  
                                  itemsList.add({
                                    'item': ItemModel(
                                      barcode: barcode,
                                      itemName: name,
                                      salesPrice: price / (_currencyRate),
                                      unitName: unit,
                                      cost: 0,
                                      groupId: 0,
                                      itemId: 0,
                                      unityId: 1,
                                      moneyId: moneyId,
                                      isActive: true,
                                    ),
                                    'originalQty': qty,
                                    'returnQty': qty,
                                  });
                                }
                                
                                setDialogState(() {
                                  invoiceData = trans;
                                  selectedItems = itemsList;
                                  isLoading = false;
                                });
                              } catch (e) {
                                setDialogState(() {
                                  errorMessage = e.toString().replaceAll('Exception:', '').trim();
                                  isLoading = false;
                                });
                              }
                            },
                          ),
                        ),
                    ] else ...[
                      // Step 2: Show items and select return quantity
                      Text(
                        'فاتورة مبيعات رقم #${(invoiceData!['transNumber'] as num).toInt()} بتاريخ: ${invoiceData!['date']}',
                        style: const TextStyle(fontFamily: 'Cairo', color: Colors.tealAccent, fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'حدد كميات المواد المراد إرجاعها إلى السلة:',
                        style: TextStyle(fontFamily: 'Cairo', color: Colors.white70, fontSize: 12),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        constraints: const BoxConstraints(maxHeight: 300),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E293B),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.white10),
                        ),
                        child: ListView.builder(
                          shrinkWrap: true,
                          itemCount: selectedItems.length,
                          itemBuilder: (context, idx) {
                            final itemMap = selectedItems[idx];
                            final ItemModel itemObj = itemMap['item'];
                            final int origQty = itemMap['originalQty'];
                            final int retQty = itemMap['returnQty'];

                            return ListTile(
                              title: Text(itemObj.itemName, style: const TextStyle(color: Colors.white, fontFamily: 'Cairo', fontSize: 13, fontWeight: FontWeight.bold)),
                              subtitle: Text('السعر الأصلي: ${currencyFormat(itemObj.salesPrice * _currencyRate)} | الكمية المباعة: $origQty', style: const TextStyle(color: Colors.white54, fontSize: 11, fontFamily: 'Cairo')),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.remove_circle_outline, color: Colors.redAccent),
                                    onPressed: () {
                                      if (retQty > 0) {
                                        setDialogState(() {
                                          itemMap['returnQty'] = retQty - 1;
                                        });
                                      }
                                    },
                                  ),
                                  Text(
                                    '$retQty',
                                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.add_circle_outline, color: Colors.greenAccent),
                                    onPressed: () {
                                      if (retQty < origQty) {
                                        setDialogState(() {
                                          itemMap['returnQty'] = retQty + 1;
                                        });
                                      }
                                    },
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          TextButton(
                            child: const Text('جلب فاتورة أخرى', style: TextStyle(fontFamily: 'Cairo', color: Colors.white70)),
                            onPressed: () {
                              setDialogState(() {
                                invoiceData = null;
                                selectedItems = [];
                                invoiceNumberController.clear();
                              });
                            },
                          ),
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(backgroundColor: Colors.tealAccent.shade700, foregroundColor: Colors.white),
                            icon: const Icon(Icons.done_all),
                            label: const Text('تأكيد إضافة المرتجع', style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
                            onPressed: () {
                              setState(() {
                                for (final itemMap in selectedItems) {
                                  final ItemModel itemObj = itemMap['item'];
                                  final int retQty = itemMap['returnQty'];
                                  if (retQty > 0) {
                                    // Add/update return cart
                                    final index = _cart.indexWhere((x) => x.item.barcode == itemObj.barcode);
                                    if (index >= 0) {
                                      _cart[index].quantity = retQty;
                                    } else {
                                      _cart.add(ReturnCartItem(
                                        item: itemObj,
                                        quantity: retQty,
                                        price: itemObj.salesPrice * _currencyRate,
                                      ));
                                    }
                                  }
                                }
                              });
                              Navigator.pop(dialogContext);
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('✅ تم إضافة البنود المحددة من الفاتورة إلى سلة المرتجعات!', style: TextStyle(fontFamily: 'Cairo')),
                                  backgroundColor: Colors.teal,
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          );
        },
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
                  Row(
                    children: [
                      const Icon(Icons.assignment_return_outlined, color: Colors.redAccent, size: 28),
                      const SizedBox(width: 12),
                      Text(
                        _editingTransNumber != null ? 'تعديل فاتورة مرتجع #${_editingTransNumber!.toInt()}' : 'فاتورة مرتجع مبيعات جديدة',
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
                      const SizedBox(width: 14),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.teal.shade700,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        icon: const Icon(Icons.receipt_long_rounded, size: 18),
                        label: const Text(
                          'استيراد من فاتورة مبيعات',
                          style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold),
                        ),
                        onPressed: _showImportFromSalesInvoiceDialog,
                      ),
                      const SizedBox(width: 10),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _editingTransNumber != null ? Colors.amber.shade800 : Colors.redAccent,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        icon: const Icon(Icons.edit_note_rounded, size: 18),
                        label: Text(
                          _editingTransNumber != null ? 'تعديل مرتجع #${_editingTransNumber!.toInt()}' : 'استدعاء وتعديل فاتورة مرتجع',
                          style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold),
                        ),
                        onPressed: _showLoadReturnInvoiceDialog,
                      ),
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
                              // 1. Dedicated Barcode Input
                              Expanded(
                                flex: 5,
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF1E293B),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: Colors.redAccent.withOpacity(0.4)),
                                  ),
                                  child: TextField(
                                    focusNode: _barcodeFocusNode,
                                    controller: _searchController,
                                    style: const TextStyle(color: Colors.white, fontFamily: 'Cairo'),
                                    decoration: const InputDecoration(
                                      hintText: 'مسح / أدخل باركود المرتجع...',
                                      hintStyle: TextStyle(color: Colors.white30, fontFamily: 'Cairo', fontSize: 13),
                                      prefixIcon: Icon(Icons.qr_code_2, color: Colors.redAccent),
                                      border: InputBorder.none,
                                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                                    ),
                                    onSubmitted: (val) {
                                      _onBarcodeSubmitted(val);
                                    },
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),

                              // 2. Dedicated Item Name Search Box
                              Expanded(
                                flex: 6,
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF1E293B),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: Colors.teal.withOpacity(0.4)),
                                  ),
                                  child: TextField(
                                    controller: _itemNameSearchController,
                                    style: const TextStyle(color: Colors.white, fontFamily: 'Cairo'),
                                    decoration: InputDecoration(
                                      hintText: 'البحث باسم الصنف أو الباركود...',
                                      hintStyle: const TextStyle(color: Colors.white30, fontFamily: 'Cairo', fontSize: 13),
                                      prefixIcon: const Icon(Icons.search, color: Colors.teal),
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
                                      selectedColor: Colors.redAccent,
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
                                        selectedColor: Colors.redAccent,
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
                                              color: Colors.redAccent.withOpacity(0.08),
                                              borderRadius: BorderRadius.circular(8),
                                            ),
                                            child: const Icon(Icons.keyboard_return_rounded, color: Colors.redAccent, size: 28),
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
                                            'سعر البيع: ${currencyFormat(item.salesPrice * _currencyRate)}',
                                            style: const TextStyle(color: Colors.redAccent, fontSize: 12, fontFamily: 'Cairo', fontWeight: FontWeight.bold),
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
                                Icon(Icons.assignment_return_rounded, color: Colors.redAccent),
                                SizedBox(width: 10),
                                Text(
                                  'المواد المطلوب إرجاعها',
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
                                      'سلة المرتجعات فارغة. انقر على المواد لإضافتها.',
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
                                                          '${currencyFormat(cartItem.price)} / ${cartItem.item.unitName}',
                                                          style: const TextStyle(color: Colors.redAccent, fontSize: 12, fontFamily: 'Cairo', decoration: TextDecoration.underline),
                                                        ),
                                                        const SizedBox(width: 4),
                                                        const Icon(Icons.edit, size: 12, color: Colors.redAccent),
                                                      ],
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            // Qty controls
                                            Row(
                                              children: [
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
                                              ],
                                            ),
                                            const SizedBox(width: 12),
                                            Text(
                                              currencyFormat(cartItem.price * cartItem.quantity),
                                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontFamily: 'Cairo'),
                                            ),
                                            const SizedBox(width: 8),
                                            IconButton(
                                              icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 20),
                                              onPressed: () => _removeFromCart(index),
                                            ),
                                          ],
                                        ),
                                      );
                                    },
                                  ),
                          ),

                          // Bottom section
                          Container(
                            padding: const EdgeInsets.all(20),
                            decoration: const BoxDecoration(
                              color: Color(0xFF0F172A),
                              border: Border(top: BorderSide(color: Colors.white10)),
                            ),
                            child: Column(
                              children: [
                                // Subtotal
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Text('إجمالي قيمة المرتجع:', style: TextStyle(color: Colors.white70, fontFamily: 'Cairo', fontSize: 15)),
                                    Text(
                                      currencyFormat(_total),
                                      style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 18, fontFamily: 'Cairo'),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 14),

                                // Payment Mode
                                Row(
                                  children: [
                                    Expanded(
                                      child: ElevatedButton(
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: _payCash == 1 ? Colors.redAccent : const Color(0xFF1E293B),
                                          foregroundColor: Colors.white,
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                                        ),
                                        onPressed: () => setState(() => _payCash = 1),
                                        child: const Text('إرجاع نقدي', style: TextStyle(fontFamily: 'Cairo')),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: ElevatedButton(
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: _payCash == 2 ? Colors.redAccent : const Color(0xFF1E293B),
                                          foregroundColor: Colors.white,
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                                        ),
                                        onPressed: () => setState(() => _payCash = 2),
                                        child: const Text('خصم من الآجل', style: TextStyle(fontFamily: 'Cairo')),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 16),

                                // Actions
                                Row(
                                  children: [
                                    Expanded(
                                      flex: 3,
                                      child: SizedBox(
                                        height: 50,
                                        child: ElevatedButton.icon(
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: Colors.redAccent,
                                            foregroundColor: Colors.white,
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                          ),
                                          icon: const Icon(Icons.save_rounded),
                                          label: Text(
                                            _editingTransNumber != null ? 'حفظ تعديل المرتجع' : 'حفظ فاتورة المرتجع',
                                            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, fontFamily: 'Cairo'),
                                          ),
                                          onPressed: apiService.isLoading ? null : _saveReturn,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      flex: 1,
                                      child: SizedBox(
                                        height: 50,
                                        child: OutlinedButton(
                                          style: OutlinedButton.styleFrom(
                                            foregroundColor: Colors.redAccent,
                                            side: const BorderSide(color: Colors.redAccent),
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                          ),
                                          onPressed: _clearReturn,
                                          child: const Icon(Icons.delete_sweep_rounded),
                                        ),
                                      ),
                                    ),
                                  ],
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
                    'عميل نقدي / حساب عام',
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

  String _generateReturnReceiptHtml({
    required String pointName,
    required int pointNo,
    required String transNumber,
    required String date,
    required int userId,
    required String userName,
    required List<ReturnCartItem> cartItems,
    required double subtotal,
    required double tax,
    required double total,
    required String currencySymbol,
    required String currencyName,
    String? logoBase64,
  }) {
    final now = DateTime.now();
    final timeStr = DateFormat('hh:mm').format(now);
    final dateStr = DateFormat('dd-MM-yyyy').format(now);
    final period = now.hour >= 12 ? 'م' : 'ص';
    final formattedDateTime = '$dateStr $timeStr $period';

    int totalQuantity = 0;
    final itemsRows = cartItems.map((item) {
      totalQuantity += item.quantity;
      final linePrice = item.price;
      final priceStr = linePrice.truncateToDouble() == linePrice
          ? linePrice.toInt().toString()
          : linePrice.toStringAsFixed(2);
      return '''
      <tr>
        <td class="col-item">${item.item.itemName}</td>
        <td class="col-qty">${item.quantity}</td>
        <td class="col-price">$priceStr</td>
      </tr>
      ''';
    }).join('');

    final barcodeSvg = BarcodeLabelService.generateBarcodeSvg(transNumber.isNotEmpty ? transNumber : '1');

    String logoHtmlContent;
    if (logoBase64 != null && logoBase64.trim().isNotEmpty) {
      final src = logoBase64.startsWith('data:') ? logoBase64 : 'data:image/png;base64,$logoBase64';
      logoHtmlContent = '<img src="$src" alt="الشعار" style="max-height: 52px; max-width: 95%; object-fit: contain;" />';
    } else {
      logoHtmlContent = '<img src="assets/images/logo.png" onerror="this.style.display=\'none\'; document.getElementById(\'return-logo-fallback\').style.display=\'block\';" style="max-height: 52px; max-width: 95%; object-fit: contain;" /><span id="return-logo-fallback" style="display:none; font-size: 18px; font-weight: bold; color: #000; font-family: \'Cairo\', sans-serif;">منطقة الشعار</span>';
    }

    final currencyLabel = currencyName.isNotEmpty ? currencyName : (currencySymbol.isNotEmpty ? currencySymbol : 'ريال يمني');

    return '''
<!DOCTYPE html>
<html lang="ar" dir="rtl">
<head>
  <meta charset="utf-8">
  <title>فاتورة مرتجع مبيعات #$transNumber</title>
  <style>
    @page { size: 80mm auto; margin: 0; }
    * { box-sizing: border-box; }
    body {
      width: 76mm;
      margin: 0 auto;
      padding: 3mm 2mm;
      font-family: 'Cairo', 'Arial', Tahoma, sans-serif;
      font-size: 11.5px;
      direction: rtl;
      text-align: right;
      color: #000;
      background: #fff;
      -webkit-print-color-adjust: exact;
    }
    
    /* 1. Logo Container */
    .logo-container {
      border: 1.5px solid #000;
      width: 100%;
      min-height: 55px;
      display: flex;
      align-items: center;
      justify-content: center;
      text-align: center;
      padding: 4px;
      margin-bottom: 6px;
    }

    /* 2. Store Header */
    .store-header {
      text-align: center;
      font-size: 16px;
      font-weight: bold;
      margin: 2px 0 3px 0;
      font-family: 'Cairo', 'Arial', sans-serif;
    }
    .invoice-title {
      text-align: center;
      font-size: 12.5px;
      font-weight: bold;
      margin-bottom: 8px;
      text-decoration: underline;
      color: #000;
      font-family: 'Cairo', 'Arial', sans-serif;
    }

    /* 3. Invoice Meta Information */
    .meta-line {
      display: flex;
      justify-content: space-between;
      align-items: center;
      margin: 2.5px 0;
      font-size: 12px;
      font-weight: bold;
    }
    .meta-split {
      display: flex;
      justify-content: space-between;
      align-items: center;
      margin: 4px 0;
      font-size: 12px;
      font-weight: bold;
    }
    .meta-lbl {
      font-weight: normal;
    }
    .meta-val {
      font-weight: bold;
    }

    /* 4. Table */
    table.items-table {
      width: 100%;
      border-collapse: collapse;
      margin-top: 6px;
      border: 1.5px solid #000;
    }
    table.items-table th, table.items-table td {
      border: 1.5px solid #000;
      padding: 4px 3px;
      font-size: 11px;
    }
    table.items-table th {
      font-weight: bold;
      text-align: center;
      background-color: #fafafa;
    }
    table.items-table td.col-item {
      width: 55%;
      text-align: right;
      font-weight: bold;
    }
    table.items-table td.col-qty {
      width: 18%;
      text-align: center;
      font-weight: bold;
    }
    table.items-table td.col-price {
      width: 27%;
      text-align: center;
      font-weight: bold;
    }

    /* 5. Summary Section */
    .summary-section {
      margin-top: 6px;
      width: 100%;
      font-size: 12px;
      font-weight: bold;
    }
    .summary-row {
      display: flex;
      justify-content: space-between;
      align-items: center;
      margin: 2.5px 0;
    }
    .summary-pair-right {
      display: flex;
      align-items: center;
      gap: 8px;
      width: 45%;
    }
    .summary-pair-left {
      display: flex;
      justify-content: space-between;
      align-items: center;
      width: 55%;
    }
    .summary-row .lbl {
      font-weight: bold;
    }
    .summary-row .val {
      font-weight: bold;
    }
    .currency-row {
      text-align: center;
      font-weight: bold;
      font-size: 13px;
      margin: 5px 0 3px 0;
      font-family: 'Cairo', 'Arial', sans-serif;
    }

    /* 6. Barcode */
    .barcode-container {
      text-align: center;
      margin-top: 6px;
      display: flex;
      justify-content: center;
      align-items: center;
    }
    .barcode-container svg {
      max-width: 90%;
      height: 42px;
    }

    /* 7. Footer */
    .footer-note {
      text-align: center;
      font-size: 11px;
      margin-top: 4px;
      font-weight: bold;
      font-family: 'Cairo', 'Arial', sans-serif;
    }
  </style>
</head>
<body>
  <!-- 1. Logo Box -->
  <div class="logo-container">
    $logoHtmlContent
  </div>

  <!-- 2. Store & Invoice Type -->
  <div class="store-header">${pointName.isNotEmpty ? pointName : 'عنوان المحل'}</div>
  <div class="invoice-title"><u>مرتجع مبيعات (إرجاع مواد)</u></div>

  <!-- 3. Meta info -->
  <div class="meta-line">
    <span class="meta-lbl">رقم المرتجع</span>
    <span class="meta-val">$transNumber</span>
  </div>
  <div class="meta-line">
    <span class="meta-lbl">التاريخ</span>
    <span class="meta-val">$formattedDateTime</span>
  </div>
  <div class="meta-split">
    <span>رقم النقطه ${pointNo > 0 ? pointNo : ''}</span>
    <span>رقم المستخدم ${userId > 0 ? userId : ''}</span>
  </div>

  <!-- 4. Items Table -->
  <table class="items-table">
    <thead>
      <tr>
        <th class="col-item">الصنف</th>
        <th class="col-qty">الكميه</th>
        <th class="col-price">السعر</th>
      </tr>
    </thead>
    <tbody>
      $itemsRows
    </tbody>
  </table>

  <!-- 5. Totals / Summary -->
  <div class="summary-section">
    <div class="summary-row">
      <div class="summary-pair-right">
        <span class="lbl">عددالقطع المسترجعة</span>
        <span class="val">$totalQuantity</span>
      </div>
      <div class="summary-pair-left">
        <span class="lbl">صافي المسترد</span>
        <span class="val">${total.toStringAsFixed(2)}</span>
      </div>
    </div>
    <div class="currency-row">
      $currencyLabel
    </div>
  </div>

  <!-- 6. Barcode -->
  <div class="barcode-container">
    $barcodeSvg
  </div>

  <!-- 7. Footer -->
  <div class="footer-note">
    إشعار مرتجع واستلام رسمي
  </div>
</body>
</html>
    ''';
  }
}

class ReturnCartItem {
  final ItemModel item;
  int quantity;
  double price;

  ReturnCartItem({required this.item, required this.quantity, required this.price});
}
