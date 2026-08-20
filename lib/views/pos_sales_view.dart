import 'dart:js' as js;
import 'dart:convert';
import 'package:universal_html/html.dart' as html;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart' hide TextDirection;
import '../services/api_service.dart';
import '../services/print_service.dart';
import '../services/barcode_label_service.dart';
import '../models/item.dart';
import '../models/item_group.dart';
import '../models/currency.dart';
import '../models/account.dart';
import '../models/transaction.dart';

class PosInvoice {
  final String id;
  final List<CartItem> cart;
  int payCash; // 1 = Cash, 2 = Credit
  double discount;
  bool shouldPrint; // true = Save & Print, false = Save Only
  CurrencyModel? selectedCurrency;
  AccountModel? selectedAccount;
  final TextEditingController discountController;
  final TextEditingController paidAmountController;

  PosInvoice({
    required this.id,
    List<CartItem>? cart,
    this.payCash = 1,
    this.discount = 0.0,
    this.shouldPrint = true,
    this.selectedCurrency,
    this.selectedAccount,
    TextEditingController? discountController,
    TextEditingController? paidAmountController,
  })  : cart = cart ?? [],
        discountController = discountController ?? TextEditingController(text: '0'),
        paidAmountController = paidAmountController ?? TextEditingController();
}

class PosSalesView extends StatefulWidget {
  const PosSalesView({super.key});

  @override
  State<PosSalesView> createState() => _PosSalesViewState();
}

class _PosSalesViewState extends State<PosSalesView> {
  final List<PosInvoice> _invoices = [];
  int _activeInvoiceIndex = 0;
  double? _editingTransNumber;

  int _selectedGroupId = 0; // 0 means "All"
  String _searchQuery = '';
  final _searchController = TextEditingController();
  final _itemNameSearchController = TextEditingController();
  final _barcodeFocusNode = FocusNode();
  bool _isSyncingItems = false;
  
  final _categoriesScrollController = ScrollController();

  PosInvoice get _activeInvoice => _invoices[_activeInvoiceIndex];
  List<CartItem> get _cart => _activeInvoice.cart;
  
  int get _payCash => _activeInvoice.payCash;
  set _payCash(int val) => setState(() => _activeInvoice.payCash = val);
  
  double get _discount => _activeInvoice.discount;

  CurrencyModel get _selectedCurrency {
    final apiService = Provider.of<ApiService>(context, listen: false);
    return _activeInvoice.selectedCurrency ?? apiService.defaultCurrency;
  }

  double get _currencyRate {
    final cur = _selectedCurrency;
    return cur.value > 0 ? cur.value : 1.0;
  }

  String get _currencySymbol {
    final cur = _selectedCurrency;
    return cur.symbol.isNotEmpty ? cur.symbol : cur.name;
  }

  String currencyFormat(double val) {
    return '${val.toStringAsFixed(2)} $_currencySymbol';
  }

  void _onCurrencyChanged(CurrencyModel newCurrency) {
    setState(() {
      _activeInvoice.selectedCurrency = newCurrency;
      final rate = newCurrency.value > 0 ? newCurrency.value : 1.0;
      for (var item in _cart) {
        item.price = item.item.salesPrice * rate;
      }
    });
  }

  Future<void> _showLoadInvoiceDialog() async {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: const Color(0xFF0F172A),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: Colors.blueAccent, width: 1.5)),
          title: const Row(
            children: [
              Icon(Icons.edit_note_rounded, color: Colors.blueAccent, size: 28),
              SizedBox(width: 8),
              Text('استدعاء فاتورة مبيعات للتعديل', style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, color: Colors.white)),
            ],
          ),
          content: TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            style: const TextStyle(color: Colors.white, fontFamily: 'Cairo'),
            decoration: InputDecoration(
              labelText: 'أدخل رقم الفاتورة (مثال: 26713500001)',
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
              style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent, foregroundColor: Colors.white),
              onPressed: () async {
                final numVal = double.tryParse(controller.text.trim());
                if (numVal == null) return;
                Navigator.pop(context);
                await _loadTransactionForEdit(numVal);
              },
              child: const Text('بحث واستدعاء الفاتورة', style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _loadTransactionForEdit(double transNum) async {
    final apiService = Provider.of<ApiService>(context, listen: false);
    try {
      final trans = await apiService.fetchTransactionByNumber(transNum);
      final details = trans['details'] as List? ?? [];
      if (details.isEmpty) {
        throw Exception('لا توجد بنود مسجلة في هذه الفاتورة');
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
        _activeInvoice.selectedCurrency = matchedCurrency;
        _activeInvoice.selectedAccount = matchedAccount;
        _cart.clear();
        for (final d in details) {
          final barcode = d['barcode'] ?? '';
          final name = d['itemName'] ?? '';
          final qty = (d['quantity'] as num? ?? 1).toInt();
          final price = (d['salesPrice'] as num? ?? 0.0).toDouble();
          final unit = d['unitName'] ?? 'حبة';
          
          _cart.add(CartItem(
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
            content: Text('✅ تم فتح واستدعاء الفاتورة رقم #${transNum.toInt()} بنجاح للتعديل! أضف أو عدل البنود ثم اضغط "حفظ تعديل الفاتورة"', style: const TextStyle(fontFamily: 'Cairo')),
            backgroundColor: Colors.blueAccent,
            duration: const Duration(seconds: 6),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ خطأ استدعاء الفاتورة: $e', style: const TextStyle(fontFamily: 'Cairo')), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  Future<void> _handleSyncItems() async {
    if (_isSyncingItems) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: const Color(0xFF1E293B),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: Color(0xFF0D9488), width: 1.5),
          ),
          title: const Row(
            children: [
              Icon(Icons.cloud_sync_rounded, color: Color(0xFF2DD4BF), size: 28),
              SizedBox(width: 10),
              Text(
                'مزامنة الأصناف من الجهاز الرئيسي',
                style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, color: Colors.white, fontSize: 16),
              ),
            ],
          ),
          content: const Text(
            'هل تريد بدء مزامنة ونقل بيانات الأصناف، الأسعار، والمجموعات من السيرفر الرئيسي إلى نقطة البيع هذه؟',
            style: TextStyle(fontFamily: 'Cairo', color: Colors.white70, fontSize: 14),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('إلغاء', style: TextStyle(fontFamily: 'Cairo', color: Colors.white60)),
            ),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0D9488),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              icon: const Icon(Icons.sync_rounded, size: 18),
              label: const Text('بدء المزامنة الآن', style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
              onPressed: () => Navigator.pop(context, true),
            ),
          ],
        ),
      ),
    );

    if (confirm != true || !mounted) return;

    final apiService = Provider.of<ApiService>(context, listen: false);
    setState(() => _isSyncingItems = true);
    try {
      final msg = await apiService.syncItems();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle_rounded, color: Colors.white),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '✅ $msg - تم نقل وتحديث بيانات الأصناف بنجاح من الجهاز الرئيسي!',
                    style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            backgroundColor: const Color(0xFF0F766E),
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error_outline_rounded, color: Colors.white),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '❌ خطأ أثناء مزامنة الأصناف من الجهاز الرئيسي: $e',
                    style: const TextStyle(fontFamily: 'Cairo'),
                  ),
                ),
              ],
            ),
            backgroundColor: Colors.redAccent.shade700,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSyncingItems = false);
        _barcodeFocusNode.requestFocus();
      }
    }
  }
  set _discount(double val) => setState(() => _activeInvoice.discount = val);
  
  bool _persistedShouldPrint = true;

  bool get _shouldPrint => _activeInvoice.shouldPrint;
  set _shouldPrint(bool val) {
    setState(() {
      _activeInvoice.shouldPrint = val;
      _persistedShouldPrint = val;
    });
    _savePrintPreference(val);
  }

  Future<void> _loadPrintPreference() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getBool('pos_should_print');
    if (saved != null) {
      setState(() {
        _persistedShouldPrint = saved;
        for (var inv in _invoices) {
          inv.shouldPrint = saved;
        }
      });
    }
  }

  Future<void> _savePrintPreference(bool val) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('pos_should_print', val);
  }

  void _pickInvoiceLogo(ApiService apiService) {
    if (kIsWeb) {
      try {
        final uploadInput = html.FileUploadInputElement();
        uploadInput.accept = 'image/*';
        uploadInput.click();

        uploadInput.onChange.listen((e) {
          final files = uploadInput.files;
          if (files != null && files.isNotEmpty) {
            final file = files[0];
            final reader = html.FileReader();
            reader.readAsDataUrl(file);
            reader.onLoadEnd.listen((e) {
              if (reader.result != null) {
                final base64String = reader.result as String;
                apiService.updateInvoiceLogo(base64String);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('✅ تم تحديث وحفظ شعار الفاتورة المطبوعة بنجاح!', style: TextStyle(fontFamily: 'Cairo')),
                      backgroundColor: Colors.green,
                      duration: Duration(seconds: 3),
                    ),
                  );
                }
              }
            });
          }
        });
      } catch (e) {
        debugPrint("Error picking invoice logo: $e");
      }
    }
  }

  void _showInvoiceLogoDialog() {
    final apiService = Provider.of<ApiService>(context, listen: false);
    showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (context, setDialogState) {
          final currentLogo = apiService.logoBase64;
          return Directionality(
            textDirection: TextDirection.rtl,
            child: AlertDialog(
              backgroundColor: const Color(0xFF1E293B),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: const Row(
                children: [
                  Icon(Icons.image_rounded, color: Colors.purpleAccent, size: 24),
                  SizedBox(width: 10),
                  Text(
                    'تخصيص شعار الفاتورة المطبوعة',
                    style: TextStyle(color: Colors.white, fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ],
              ),
              content: SizedBox(
                width: 420,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'يمكنك اختيار صورة شعار مخصصة (PNG أو JPG) لتظهر في رأس إيصالات وفواتير المبيعات المطبوعة:',
                      style: TextStyle(color: Colors.white70, fontFamily: 'Cairo', fontSize: 13),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      width: double.infinity,
                      height: 120,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.purpleAccent.withOpacity(0.4), width: 1.5),
                      ),
                      child: Center(
                        child: currentLogo.isNotEmpty
                            ? (currentLogo.startsWith('data:image/svg')
                                ? SvgPicture.string(
                                    utf8.decode(base64Decode(currentLogo.split(',')[1])),
                                    fit: BoxFit.contain,
                                  )
                                : Image.memory(
                                    base64Decode(currentLogo.split(',').length > 1 ? currentLogo.split(',')[1] : currentLogo),
                                    fit: BoxFit.contain,
                                    errorBuilder: (_, __, ___) => const Icon(Icons.broken_image, color: Colors.grey, size: 40),
                                  ))
                            : Image.asset(
                                'assets/images/logo.png',
                                fit: BoxFit.contain,
                                errorBuilder: (_, __, ___) => const Text('شعار المحل الافتراضي', style: TextStyle(fontFamily: 'Cairo', color: Colors.black54)),
                              ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF9C0E62),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                            icon: const Icon(Icons.upload_file_rounded, size: 18),
                            label: const Text('اختيار صورة من الجهاز 📁', style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
                            onPressed: () {
                              _pickInvoiceLogo(apiService);
                              Navigator.pop(dialogCtx);
                            },
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              actions: [
                if (currentLogo.isNotEmpty)
                  TextButton.icon(
                    style: TextButton.styleFrom(foregroundColor: Colors.orangeAccent),
                    icon: const Icon(Icons.restore_rounded, size: 18),
                    label: const Text('استعادة الشعار الافتراضي', style: TextStyle(fontFamily: 'Cairo')),
                    onPressed: () async {
                      await apiService.updateInvoiceLogo('');
                      if (mounted) Navigator.pop(dialogCtx);
                    },
                  ),
                TextButton(
                  onPressed: () => Navigator.pop(dialogCtx),
                  child: const Text('إغلاق', style: TextStyle(color: Colors.white70, fontFamily: 'Cairo')),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  TextEditingController get _discountController => _activeInvoice.discountController;
  TextEditingController get _paidAmountController => _activeInvoice.paidAmountController;

  double get _paidAmount {
    final text = _paidAmountController.text.trim();
    if (text.isEmpty) return _total;
    return double.tryParse(text) ?? _total;
  }

  double get _changeAmount {
    final diff = _paidAmount - _total;
    return diff > 0 ? diff : 0.0;
  }

  @override
  void initState() {
    super.initState();
    _loadPrintPreference();
    _invoices.add(PosInvoice(id: 'فاتورة 1', shouldPrint: _persistedShouldPrint));
    // Auto load data on view open
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<ApiService>(context, listen: false).loadInitialData();
      _barcodeFocusNode.requestFocus();
    });
  }

  void _startCameraScan() {
    if (kIsWeb) {
      try {
        js.context.callMethod('openBarcodeScanner', [
          (dynamic barcode) {
            if (barcode != null && barcode.toString().isNotEmpty) {
              final code = barcode.toString().trim();
              _searchController.text = code;
              _onBarcodeSubmitted(code);
            }
          }
        ]);
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تعذر تشغيل الكاميرا: $e', style: const TextStyle(fontFamily: 'Cairo')),
            backgroundColor: Colors.red,
          ),
        );
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('خاصية كاميرا الباركود متوفرة عند فتح التطبيق عبر المتصفح', style: TextStyle(fontFamily: 'Cairo')),
          backgroundColor: Colors.orange,
        ),
      );
    }
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
            content: Text('تم إضافة ${matched.first.itemName}', style: const TextStyle(fontFamily: 'Cairo')),
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

  @override
  void dispose() {
    _searchController.dispose();
    _barcodeFocusNode.dispose();
    _categoriesScrollController.dispose();
    for (var inv in _invoices) {
      inv.discountController.dispose();
      inv.paidAmountController.dispose();
    }
    super.dispose();
  }

  Future<void> _closeInvoice(int index) async {
    final inv = _invoices[index];
    if (inv.cart.isNotEmpty) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (context) => Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            backgroundColor: const Color(0xFF1E293B),
            title: const Text('تأكيد الإغلاق', style: TextStyle(fontFamily: 'Cairo', color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
            content: const Text(
              'هل أنت متأكد من إغلاق هذه الفاتورة؟ السلة تحتوي على أصناف وسيتم فقدان البيانات غير المحفوظة.',
              style: TextStyle(fontFamily: 'Cairo', color: Colors.white70),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('إلغاء', style: TextStyle(fontFamily: 'Cairo', color: Colors.white70)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
                onPressed: () => Navigator.pop(context, true),
                child: const Text('إغلاق الفاتورة', style: TextStyle(fontFamily: 'Cairo', color: Colors.white)),
              ),
            ],
          ),
        ),
      );
      if (confirm != true) return;
    }
    
    setState(() {
      inv.discountController.dispose();
      inv.paidAmountController.dispose();
      _invoices.removeAt(index);
      if (_activeInvoiceIndex >= _invoices.length) {
        _activeInvoiceIndex = _invoices.length - 1;
      }
      if (_invoices.isEmpty) {
        _invoices.add(PosInvoice(id: 'فاتورة 1', shouldPrint: _persistedShouldPrint));
        _activeInvoiceIndex = 0;
      }
    });
    _barcodeFocusNode.requestFocus();
  }

  void _addToCart(ItemModel item) {
    setState(() {
      final index = _cart.indexWhere((x) => x.item.barcode == item.barcode);
      if (index >= 0) {
        _cart[index].quantity++;
      } else {
        final currentRate = _currencyRate;
        _cart.add(CartItem(
          item: item,
          quantity: 1,
          price: item.salesPrice * currentRate,
        ));
      }
    });
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
            'تعديل سعر الصنف: ${cartItem.item.itemName}',
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
                  labelText: 'السعر الجديد في الفاتورة ($_currencySymbol)',
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
              style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent),
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
                        'عذراً، لا يمكن أن يقل السعر عن سعر الكلفة (${currencyFormat(convertedCost)})',
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
    _barcodeFocusNode.requestFocus();
  }

  void _clearSale() {
    setState(() {
      _cart.clear();
      _discount = 0.0;
      _discountController.text = '0';
      _paidAmountController.clear();
      _payCash = 1;
      _searchController.clear();
      _searchQuery = '';
    });
    _barcodeFocusNode.requestFocus();
  }

  double get _subtotal {
    return _cart.fold(0.0, (sum, item) => sum + (item.price * item.quantity));
  }

  double get _tax {
    return 0.0; // Cancelled Tax
  }

  double get _total {
    final t = _subtotal - _discount;
    return t < 0 ? 0.0 : t;
  }

  Future<void> _checkout() async {
    if (_cart.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('سلة المبيعات فارغة!', style: TextStyle(fontFamily: 'Cairo')),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final apiService = Provider.of<ApiService>(context, listen: false);
    final user = apiService.currentUser;
    if (user == null) return;

    // Create transaction details
    final List<TransactionDetailModel> details = _cart.map((cartItem) {
      final double itemSubtotal = cartItem.price * cartItem.quantity;
      final double itemTotal = itemSubtotal;

      return TransactionDetailModel(
        barcode: cartItem.item.barcode,
        itemName: cartItem.item.itemName,
        quantity: cartItem.quantity,
        salesPrice: cartItem.price,
        discount: 0, // Item level discount
        taxTotal: 0,
        totalItem: itemTotal.round(),
      );
    }).toList();

    // Create transaction header
    final transaction = TransactionHeaderModel(
      date: apiService.selectedDate,
      description: 'مبيعات نقطة البيع Flutter',
      userId: user.userId,
      pointNo: apiService.pointNo, // Dynamic POS Terminal
      payCash: _payCash,
      transType: 35, // 35 = Sale (from Main schema type check)
      moneyId: _selectedCurrency.id, // Selected POS Currency
      accountId: _activeInvoice.selectedAccount?.accId ?? 0,
      details: details,
    );

    try {
      Map<String, dynamic> response;
      if (_editingTransNumber != null) {
        final transData = {
          "date": apiService.selectedDate,
          "description": 'تعديل مبيعات نقطة البيع #${_editingTransNumber!.toInt()}',
          "userId": user.userId,
          "pointNo": apiService.pointNo,
          "payCash": _payCash,
          "transType": 35,
          "moneyId": _selectedCurrency.id,
          "accountId": _activeInvoice.selectedAccount?.accId ?? 0,
          "details": details.map((d) => d.toJson()).toList(),
        };
        response = await apiService.updateTransaction(_editingTransNumber!, transData);
      } else {
        response = await apiService.saveTransaction(transaction);
      }

      final savedTransNum = response['transNumber'] ?? _editingTransNumber ?? 0;
      _editingTransNumber = null;
      
      if (mounted) {
        // Trigger thermal receipt print ONLY if user selected "Save & Print"
        if (_shouldPrint) {
          final receiptHtml = _generateReceiptHtml(
            pointName: apiService.pointName,
            pointNo: apiService.pointNo,
            transNumber: '${savedTransNum is num && savedTransNum > 0 ? (savedTransNum.truncateToDouble() == savedTransNum ? savedTransNum.toInt() : savedTransNum) : response['transNumber']}',
            date: apiService.selectedDate,
            userId: user.userId,
            userName: user.userName,
            cartItems: List.from(_cart),
            subtotal: _subtotal,
            discount: _discount,
            tax: _tax,
            total: _total,
            paidAmount: _paidAmount,
            changeAmount: _changeAmount,
            payCash: _payCash,
            currencySymbol: _currencySymbol,
            currencyName: _selectedCurrency.name.isNotEmpty ? _selectedCurrency.name : _currencySymbol,
            logoBase64: apiService.logoBase64,
          );
          PrintService.printHtml(receiptHtml);
        }

        // Show success alert
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
                    'تمت العملية بنجاح',
                    style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('رقم الفاتورة: #${response['transNumber']}', style: const TextStyle(fontFamily: 'Cairo', fontSize: 16)),
                  const SizedBox(height: 6),
                  Text('إجمالي الفاتورة: ${currencyFormat(_total)}', style: const TextStyle(fontFamily: 'Cairo', fontSize: 15, fontWeight: FontWeight.bold, color: Colors.green)),
                  const SizedBox(height: 4),
                  Text('المبلغ المقبوض: ${currencyFormat(_paidAmount)}', style: const TextStyle(fontFamily: 'Cairo', fontSize: 14, color: Colors.blueAccent)),
                  const SizedBox(height: 4),
                  Text('المتبقي للعميل: ${currencyFormat(_changeAmount)}', style: const TextStyle(fontFamily: 'Cairo', fontSize: 14, color: Colors.amber, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  const Text('تم حفظ الفاتورة بنجاح في SQL Server.', style: TextStyle(fontFamily: 'Cairo', color: Colors.grey, fontSize: 12)),
                ],
              ),
              actions: [
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blueAccent,
                    foregroundColor: Colors.white,
                  ),
                  icon: const Icon(Icons.print_rounded),
                  label: const Text('🖨️ طباعة الفاتورة', style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
                  onPressed: () {
                    final receiptHtml = _generateReceiptHtml(
                      pointName: apiService.pointName,
                      pointNo: apiService.pointNo,
                      transNumber: '${savedTransNum is num && savedTransNum > 0 ? (savedTransNum.truncateToDouble() == savedTransNum ? savedTransNum.toInt() : savedTransNum) : response['transNumber']}',
                      date: apiService.selectedDate,
                      userId: user.userId,
                      userName: user.userName,
                      cartItems: List.from(_cart),
                      subtotal: _subtotal,
                      discount: _discount,
                      tax: _tax,
                      total: _total,
                      paidAmount: _paidAmount,
                      changeAmount: _changeAmount,
                      payCash: _payCash,
                      currencySymbol: _currencySymbol,
                      currencyName: _selectedCurrency.name.isNotEmpty ? _selectedCurrency.name : _currencySymbol,
                      logoBase64: apiService.logoBase64,
                    );
                    PrintService.printHtml(receiptHtml);
                  },
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () {
                    Navigator.pop(context);
                    _clearSale();
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

    // Filter items based on search and category
    final filteredItems = apiService.items.where((item) {
      final matchesGroup = _selectedGroupId == 0 || item.groupId == _selectedGroupId;
      final matchesSearch = item.itemName.toLowerCase().contains(_searchQuery.toLowerCase()) ||
                            item.barcode.contains(_searchQuery);
      return matchesGroup && matchesSearch;
    }).toList();

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Directionality(
          textDirection: TextDirection.rtl,
          child: Column(
            children: [
              // --- TOP HEADER WITH MULTI-INVOICE TABS ---
              Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
              color: const Color(0xFF1B0718),
              child: Row(
                children: [
                  const Icon(Icons.shopping_cart_outlined, color: Color(0xFFC2185B), size: 26),
                  const SizedBox(width: 8),
                  const Text(
                    'المبيعات',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'Cairo',
                    ),
                  ),
                  const SizedBox(width: 24),
                  
                  // Invoices Tabs
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          ..._invoices.asMap().entries.map((entry) {
                            final idx = entry.key;
                            final inv = entry.value;
                            final isActive = idx == _activeInvoiceIndex;
                            return Container(
                              margin: const EdgeInsets.symmetric(horizontal: 4),
                              child: ChoiceChip(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                label: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      inv.id,
                                      style: TextStyle(
                                        fontFamily: 'Cairo',
                                        color: isActive ? Colors.white : Colors.white70,
                                        fontSize: 12,
                                        fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    InkWell(
                                      onTap: () => _closeInvoice(idx),
                                      child: Container(
                                        padding: const EdgeInsets.all(2),
                                        decoration: BoxDecoration(
                                          color: isActive ? Colors.white30 : Colors.white12,
                                          shape: BoxShape.circle,
                                        ),
                                        child: Icon(
                                          Icons.close,
                                          size: 10,
                                          color: isActive ? Colors.white : Colors.white60,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                selected: isActive,
                                selectedColor: const Color(0xFF9C0E62),
                                backgroundColor: Colors.white.withValues(alpha: 0.04),
                                onSelected: (selected) {
                                  if (selected) {
                                    setState(() {
                                      _activeInvoiceIndex = idx;
                                    });
                                    _barcodeFocusNode.requestFocus();
                                  }
                                },
                              ),
                            );
                          }).toList(),
                          
                          // Add Tab Button
                          IconButton(
                            icon: const Icon(Icons.add_circle_outline, color: Color(0xFF7CB342), size: 24),
                            tooltip: 'فتح فاتورة جديدة',
                            onPressed: () {
                              setState(() {
                                // Find next available serial number
                                int nextNum = 1;
                                while (_invoices.any((x) => x.id == 'فاتورة $nextNum')) {
                                  nextNum++;
                                }
                                _invoices.add(PosInvoice(
                                  id: 'فاتورة $nextNum',
                                  selectedCurrency: _selectedCurrency,
                                  shouldPrint: _persistedShouldPrint,
                                ));
                                _activeInvoiceIndex = _invoices.length - 1;
                              });
                              _barcodeFocusNode.requestFocus();
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),

                  // Currency Dropdown Selector
                  _buildCurrencyDropdown(apiService),
                  const SizedBox(width: 10),

                  // Accounts Dropdown Selector (tblExpensesList / fldAccID)
                  _buildAccountDropdown(apiService),
                  const SizedBox(width: 12),

                  // Invoice Custom Logo Button
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF9C0E62),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    icon: const Icon(Icons.image_rounded, size: 18),
                    label: const Text(
                      'شعار الفاتورة 🖼️',
                      style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 12),
                    ),
                    onPressed: _showInvoiceLogoDialog,
                  ),
                ],
              ),
            ),
            
            // --- MAIN CONTENT SPLIT VIEW ---
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
                          // Search & Barcode Scan Area
                          Row(
                            children: [
                              // 1. Dedicated Barcode Input
                              Expanded(
                                flex: 5,
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF240E20),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: const Color(0xFFC2185B).withValues(alpha: 0.5)),
                                  ),
                                  child: TextField(
                                    focusNode: _barcodeFocusNode,
                                    controller: _searchController,
                                    inputFormatters: [ArabicToEnglishQwerMappingFormatter()],
                                    style: const TextStyle(color: Colors.white, fontFamily: 'Cairo'),
                                    decoration: InputDecoration(
                                      hintText: 'مسح / أدخل الباركود...',
                                      hintStyle: const TextStyle(color: Colors.white30, fontFamily: 'Cairo', fontSize: 13),
                                      prefixIcon: const Icon(Icons.qr_code_2, color: Color(0xFFC2185B)),
                                      suffixIcon: IconButton(
                                        icon: const Icon(Icons.qr_code_scanner, color: Color(0xFFE91E63)),
                                        tooltip: 'مسح الباركود بالكاميرا',
                                        onPressed: _startCameraScan,
                                      ),
                                      border: InputBorder.none,
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
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
                                    color: const Color(0xFF240E20),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: const Color(0xFF7CB342).withValues(alpha: 0.5)),
                                  ),
                                  child: TextField(
                                    controller: _itemNameSearchController,
                                    style: const TextStyle(color: Colors.white, fontFamily: 'Cairo'),
                                    decoration: InputDecoration(
                                      hintText: 'البحث باسم الصنف...',
                                      hintStyle: const TextStyle(color: Colors.white30, fontFamily: 'Cairo', fontSize: 13),
                                      prefixIcon: const Icon(Icons.search, color: Color(0xFF7CB342)),
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
                              const SizedBox(width: 10),

                              // Refresh Data Button
                              ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF240E20),
                                  foregroundColor: Colors.white70,
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    side: const BorderSide(color: Color(0xFF4D183E)),
                                  ),
                                ),
                                icon: apiService.isLoading 
                                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFC2185B)))
                                    : const Icon(Icons.sync_rounded),
                                label: const Text('تحديث', style: TextStyle(fontFamily: 'Cairo')),
                                onPressed: () => apiService.loadInitialData(),
                              ),
                              const SizedBox(width: 8),

                              // Sync Items From Main Server Button
                              ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF0D9488),
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                                icon: _isSyncingItems
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                      )
                                    : const Icon(Icons.cloud_download_rounded, size: 18),
                                label: const Text(
                                  'مزامنة الأصناف',
                                  style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold),
                                ),
                                onPressed: _isSyncingItems || apiService.isLoading ? null : _handleSyncItems,
                              ),
                              const SizedBox(width: 8),

                              // POS Movements Button
                              ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF5B7B32),
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                                icon: const Icon(Icons.analytics_rounded, size: 18),
                                label: const Text('عرض حركة المبيعات', style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
                                onPressed: () {
                                  showDialog(
                                    context: context,
                                    builder: (context) => const PosMovementsDialog(),
                                  );
                                },
                              ),
                            ],
                          ),
                          const SizedBox(height: 20),

                          // Horizontal Categories Chip list
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
                                  // "All" Category
                                  Padding(
                                    padding: const EdgeInsets.only(left: 8.0),
                                    child: ChoiceChip(
                                      label: const Text('كل الأصناف', style: TextStyle(fontFamily: 'Cairo')),
                                      selected: _selectedGroupId == 0,
                                      selectedColor: const Color(0xFF9C0E62),
                                      disabledColor: const Color(0xFF240E20),
                                      backgroundColor: const Color(0xFF240E20),
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
                                        selectedColor: const Color(0xFF9C0E62),
                                        backgroundColor: const Color(0xFF240E20),
                                        labelStyle: TextStyle(color: _selectedGroupId == group.id ? Colors.white : Colors.white60),
                                        onSelected: (_) => setState(() => _selectedGroupId = group.id),
                                      ),
                                    );
                                  }),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 20),

                          // Grid View of Products
                          Expanded(
                            child: apiService.isLoading && apiService.items.isEmpty
                                ? const Center(child: CircularProgressIndicator(color: Color(0xFFC2185B)))
                                : filteredItems.isEmpty
                                    ? const Center(
                                        child: Text(
                                          'لا توجد أصناف تطابق البحث!',
                                          style: TextStyle(color: Colors.white54, fontSize: 18, fontFamily: 'Cairo'),
                                        ),
                                      )
                                    : GridView.builder(
                                        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                                          maxCrossAxisExtent: 220,
                                          mainAxisSpacing: 16,
                                          crossAxisSpacing: 16,
                                          childAspectRatio: 0.82,
                                        ),
                                        itemCount: filteredItems.length,
                                        itemBuilder: (context, index) {
                                          final item = filteredItems[index];
                                          return Card(
                                            color: const Color(0xFF240E20),
                                            shape: RoundedRectangleBorder(
                                              borderRadius: BorderRadius.circular(12),
                                              side: const BorderSide(color: Color(0xFF4D183E), width: 1),
                                            ),
                                            elevation: 3,
                                            child: InkWell(
                                              borderRadius: BorderRadius.circular(12),
                                              onTap: () => _addToCart(item),
                                              child: Padding(
                                                padding: const EdgeInsets.all(12.0),
                                                child: Column(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  children: [
                                                    // Product icon/category indicator
                                                    Container(
                                                      width: double.infinity,
                                                      height: 70,
                                                      decoration: BoxDecoration(
                                                        color: const Color(0xFF9C0E62).withValues(alpha: 0.12),
                                                        borderRadius: BorderRadius.circular(8),
                                                      ),
                                                      child: const Icon(
                                                        Icons.checkroom,
                                                        color: Color(0xFFE91E63),
                                                        size: 32,
                                                      ),
                                                    ),
                                                    const SizedBox(height: 8),
                                                    // Category Badge from tblItemGroup
                                                    Text(
                                                      apiService.groups.firstWhere(
                                                        (g) => g.id == item.groupId, 
                                                        orElse: () => ItemGroupModel(id: 0, name: 'عام')
                                                      ).name,
                                                      style: const TextStyle(color: Color(0xFFC2185B), fontSize: 11, fontWeight: FontWeight.bold, fontFamily: 'Cairo'),
                                                    ),
                                                    const SizedBox(height: 4),
                                                    // Name
                                                    Text(
                                                       item.itemName,
                                                       style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14, fontFamily: 'Cairo'), maxLines: 2, overflow: TextOverflow.ellipsis),
                                                     const Spacer(),
                                                     Row(
                                                       mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                                       children: [
                                                         Text(
                                                           item.unitName,
                                                           style: const TextStyle(color: Colors.white54, fontSize: 11, fontFamily: 'Cairo'),
                                                         ),
                                                         Text(
                                                           item.barcode,
                                                           style: const TextStyle(color: Colors.white30, fontSize: 11),
                                                         ),
                                                       ],
                                                     ),
                                                     const SizedBox(height: 6),
                                                    // Price
                                                    Text(
                                                      currencyFormat(item.salesPrice),
                                                      style: const TextStyle(
                                                        color: Color(0xFF7CB342),
                                                        fontWeight: FontWeight.bold,
                                                        fontSize: 15,
                                                      ),
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
                        color: Color(0xFF1B0718),
                        border: Border(right: BorderSide(color: Color(0xFF4D183E))),
                      ),
                      child: Column(
                        children: [
                          // Header Customer Panel
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: const BoxDecoration(
                              border: Border(bottom: BorderSide(color: Colors.white10)),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.people_outline, color: Colors.blueAccent),
                                const SizedBox(width: 10),
                                const Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'الزبون الحالى:',
                                        style: TextStyle(color: Colors.white54, fontSize: 12, fontFamily: 'Cairo'),
                                      ),
                                      Text(
                                        'زبون نقدي عام',
                                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontFamily: 'Cairo'),
                                      ),
                                    ],
                                  ),
                                ),
                                TextButton.icon(
                                  icon: const Icon(Icons.edit, size: 16),
                                  label: const Text('تغيير', style: TextStyle(fontFamily: 'Cairo')),
                                  onPressed: () {
                                    // Add customer change dialog if needed
                                  },
                                ),
                              ],
                            ),
                          ),

                          // Cart Items list
                          Expanded(
                            child: _cart.isEmpty
                                ? Center(
                                    child: Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Icon(Icons.shopping_cart_outlined, size: 64, color: Colors.white.withOpacity(0.1)),
                                        const SizedBox(height: 12),
                                        const Text(
                                          'السلة فارغة. انقر على المنتجات لإضافتها.',
                                          style: TextStyle(color: Colors.white30, fontFamily: 'Cairo'),
                                        ),
                                      ],
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
                                            // Item Name & unit
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    cartItem.item.itemName,
                                                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontFamily: 'Cairo'),
                                                    maxLines: 1,
                                                    overflow: TextOverflow.ellipsis,
                                                  ),
                                                  InkWell(
                                                    onTap: () => _showEditPriceDialog(index),
                                                    child: Row(
                                                      children: [
                                                        Text(
                                                          '${currencyFormat(cartItem.price)} / ${cartItem.item.unitName}',
                                                          style: const TextStyle(color: Colors.blueAccent, fontSize: 12, fontFamily: 'Cairo', decoration: TextDecoration.underline),
                                                        ),
                                                        const SizedBox(width: 4),
                                                        const Icon(Icons.edit, size: 12, color: Colors.blueAccent),
                                                      ],
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            // Qty Controls
                                            Row(
                                              children: [
                                                IconButton(
                                                  icon: const Icon(Icons.remove_circle_outline, color: Colors.redAccent, size: 22),
                                                  onPressed: () => _updateQty(index, -1),
                                                ),
                                                Text(
                                                  '${cartItem.quantity}',
                                                  style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                                                ),
                                                IconButton(
                                                  icon: const Icon(Icons.add_circle_outline, color: Colors.greenAccent, size: 22),
                                                  onPressed: () => _updateQty(index, 1),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(width: 8),
                                            // Subtotal
                                            SizedBox(
                                              width: 75,
                                              child: Text(
                                                currencyFormat(cartItem.price * cartItem.quantity),
                                                textAlign: TextAlign.end,
                                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                                              ),
                                            ),
                                            IconButton(
                                              icon: const Icon(Icons.delete_outline, color: Colors.white30, size: 20),
                                              onPressed: () => _removeFromCart(index),
                                            ),
                                          ],
                                        ),
                                      );
                                    },
                                  ),
                          ),

                          // Calculation Summary panel
                          Container(
                            padding: const EdgeInsets.all(20),
                            color: const Color(0xFF140712).withValues(alpha: 0.7),
                            child: Column(
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Text('المجموع الفرعي:', style: TextStyle(color: Colors.white60, fontFamily: 'Cairo')),
                                    Text(currencyFormat(_subtotal), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                // Discount Row
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Text('الخصم المباشر:', style: TextStyle(color: Colors.white60, fontFamily: 'Cairo')),
                                    SizedBox(
                                      width: 100,
                                      height: 30,
                                      child: TextField(
                                        controller: _discountController,
                                        style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 13),
                                        textAlign: TextAlign.center,
                                        keyboardType: TextInputType.number,
                                        decoration: const InputDecoration(
                                          fillColor: Colors.white12,
                                          filled: true,
                                          border: OutlineInputBorder(borderSide: BorderSide.none),
                                          contentPadding: EdgeInsets.zero,
                                        ),
                                        onChanged: (val) {
                                          setState(() {
                                            _discount = double.tryParse(val) ?? 0.0;
                                          });
                                        },
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Text(
                                      'المجموع الكلي:',
                                      style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold, fontFamily: 'Cairo'),
                                    ),
                                    Text(
                                      currencyFormat(_total),
                                      style: const TextStyle(color: Color(0xFF7CB342), fontSize: 22, fontWeight: FontWeight.bold, fontFamily: 'Cairo'),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),

                                // Paid Amount & Remaining Amount Row
                                Row(
                                  children: [
                                    // Paid Amount Input
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          const Text('المبلغ المدفوع:', style: TextStyle(color: Colors.white70, fontSize: 12, fontFamily: 'Cairo')),
                                          const SizedBox(height: 4),
                                          SizedBox(
                                            height: 38,
                                            child: TextField(
                                              controller: _paidAmountController,
                                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14, fontFamily: 'Cairo'),
                                              decoration: InputDecoration(
                                                hintText: _total.toStringAsFixed(2),
                                                hintStyle: const TextStyle(color: Colors.white30, fontSize: 13),
                                                filled: true,
                                                fillColor: const Color(0xFF240E20),
                                                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: Color(0xFFC2185B))),
                                                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: Color(0xFF4D183E))),
                                                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: Color(0xFFE91E63))),
                                              ),
                                              onChanged: (_) => setState(() {}),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    // Remaining Amount Display
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          const Text('المبلغ المتبقي:', style: TextStyle(color: Colors.white70, fontSize: 12, fontFamily: 'Cairo')),
                                          const SizedBox(height: 4),
                                          Container(
                                            height: 38,
                                            padding: const EdgeInsets.symmetric(horizontal: 10),
                                            decoration: BoxDecoration(
                                              color: _changeAmount > 0 ? const Color(0xFF5B7B32).withValues(alpha: 0.25) : const Color(0xFF240E20),
                                              borderRadius: BorderRadius.circular(6),
                                              border: Border.all(color: _changeAmount > 0 ? const Color(0xFF7CB342) : const Color(0xFF4D183E)),
                                            ),
                                            alignment: Alignment.centerRight,
                                            child: Text(
                                              currencyFormat(_changeAmount),
                                              style: TextStyle(
                                                color: _changeAmount > 0 ? const Color(0xFF7CB342) : Colors.white70,
                                                fontWeight: FontWeight.bold,
                                                fontSize: 14,
                                                fontFamily: 'Cairo',
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                
                                // Save Option Toggle Bar: (Save & Print vs Save Only)
                                Row(
                                  children: [
                                    Expanded(
                                      child: InkWell(
                                        onTap: () => setState(() => _shouldPrint = true),
                                        borderRadius: BorderRadius.circular(6),
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(vertical: 8),
                                          decoration: BoxDecoration(
                                            color: _shouldPrint ? const Color(0xFF9C0E62).withValues(alpha: 0.25) : const Color(0xFF240E20),
                                            border: Border.all(color: _shouldPrint ? const Color(0xFFE91E63) : const Color(0xFF4D183E)),
                                            borderRadius: BorderRadius.circular(6),
                                          ),
                                          child: Row(
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            children: [
                                              Icon(Icons.print_rounded, size: 16, color: _shouldPrint ? const Color(0xFFE91E63) : Colors.white54),
                                              const SizedBox(width: 6),
                                              Text(
                                                'حفظ مع الطباعة',
                                                style: TextStyle(
                                                  fontFamily: 'Cairo',
                                                  fontSize: 12,
                                                  fontWeight: _shouldPrint ? FontWeight.bold : FontWeight.normal,
                                                  color: _shouldPrint ? const Color(0xFFFDF2F8) : Colors.white54,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: InkWell(
                                        onTap: () => setState(() => _shouldPrint = false),
                                        borderRadius: BorderRadius.circular(6),
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(vertical: 8),
                                          decoration: BoxDecoration(
                                            color: !_shouldPrint ? const Color(0xFF5B7B32).withValues(alpha: 0.25) : const Color(0xFF240E20),
                                            border: Border.all(color: !_shouldPrint ? const Color(0xFF7CB342) : const Color(0xFF4D183E)),
                                            borderRadius: BorderRadius.circular(6),
                                          ),
                                          child: Row(
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            children: [
                                              Icon(Icons.save_rounded, size: 16, color: !_shouldPrint ? const Color(0xFF7CB342) : Colors.white54),
                                              const SizedBox(width: 6),
                                              Text(
                                                'فقط حفظ بدون طباعة',
                                                style: TextStyle(
                                                  fontFamily: 'Cairo',
                                                  fontSize: 12,
                                                  fontWeight: !_shouldPrint ? FontWeight.bold : FontWeight.normal,
                                                  color: !_shouldPrint ? const Color(0xFF7CB342) : Colors.white54,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),

                                // Payment Method Row
                                Row(
                                  children: [
                                    Expanded(
                                      child: ElevatedButton(
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: _payCash == 1 ? const Color(0xFF9C0E62) : const Color(0xFF240E20),
                                          foregroundColor: Colors.white,
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(6),
                                            side: BorderSide(color: _payCash == 1 ? const Color(0xFFE91E63) : const Color(0xFF4D183E)),
                                          ),
                                        ),
                                        onPressed: () => setState(() => _payCash = 1),
                                        child: const Text('نقدي (Cash)', style: TextStyle(fontFamily: 'Cairo')),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: ElevatedButton(
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: _payCash == 2 ? const Color(0xFF5B7B32) : const Color(0xFF240E20),
                                          foregroundColor: Colors.white,
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(6),
                                            side: BorderSide(color: _payCash == 2 ? const Color(0xFF7CB342) : const Color(0xFF4D183E)),
                                          ),
                                        ),
                                        onPressed: () => setState(() => _payCash = 2),
                                        child: const Text('آجل (Credit)', style: TextStyle(fontFamily: 'Cairo')),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 16),
                                
                                // Action Buttons
                                Row(
                                  children: [
                                    Expanded(
                                      flex: 3,
                                      child: SizedBox(
                                        height: 52,
                                        child: ElevatedButton(
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: _shouldPrint ? const Color(0xFF9C0E62) : const Color(0xFF5B7B32),
                                            foregroundColor: Colors.white,
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                            elevation: 4,
                                          ),
                                          onPressed: apiService.isLoading ? null : _checkout,
                                          child: apiService.isLoading
                                              ? const CircularProgressIndicator(color: Colors.white)
                                              : Row(
                                                  mainAxisAlignment: MainAxisAlignment.center,
                                                  children: [
                                                    Icon(_shouldPrint ? Icons.print_rounded : Icons.save_rounded),
                                                    const SizedBox(width: 8),
                                                    Text(
                                                      _shouldPrint ? 'حفظ وطباعة الفاتورة' : 'حفظ الفاتورة فقط',
                                                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, fontFamily: 'Cairo'),
                                                    ),
                                                  ],
                                                ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    // Clear Button
                                    Expanded(
                                      flex: 1,
                                      child: SizedBox(
                                        height: 52,
                                        child: OutlinedButton(
                                          style: OutlinedButton.styleFrom(
                                            foregroundColor: Colors.redAccent,
                                            side: const BorderSide(color: Colors.redAccent),
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                          ),
                                          onPressed: _clearSale,
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

    final currentCurrency = _selectedCurrency;

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
    final selectedAcc = _activeInvoice.selectedAccount;
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
                _activeInvoice.selectedAccount = null;
              } else {
                final match = accounts.firstWhere((a) => a.accId == newAccId, orElse: () => AccountModel(id: 0, name: '', accId: newAccId));
                _activeInvoice.selectedAccount = match;
              }
            });
          },
        ),
      ),
    );
  }

  String _generateReceiptHtml({
    required String pointName,
    required int pointNo,
    required String transNumber,
    required String date,
    required int userId,
    required String userName,
    required List<CartItem> cartItems,
    required double subtotal,
    required double discount,
    required double tax,
    required double total,
    required double paidAmount,
    required double changeAmount,
    required int payCash,
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
      logoHtmlContent = '<img src="assets/images/logo.png" onerror="this.style.display=\'none\'; document.getElementById(\'logo-fallback-txt\').style.display=\'block\';" style="max-height: 52px; max-width: 95%; object-fit: contain;" /><span id="logo-fallback-txt" style="display:none; font-size: 18px; font-weight: bold; color: #000; font-family: \'Cairo\', sans-serif;">منطقة الشعار</span>';
    }

    final currencyLabel = currencyName.isNotEmpty ? currencyName : (currencySymbol.isNotEmpty ? currencySymbol : 'ريال يمني');

    return '''
<!DOCTYPE html>
<html lang="ar" dir="rtl">
<head>
  <meta charset="utf-8">
  <title>فاتورة مبيعات #$transNumber</title>
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
  <div class="invoice-title"><u>مبيعات (نقاط بيع)  ${payCash == 1 ? 'نقد' : 'آجل'}</u></div>

  <!-- 3. Meta info -->
  <div class="meta-line">
    <span class="meta-lbl">رقم الفاتوره</span>
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
        <span class="lbl">عددالقطع</span>
        <span class="val">$totalQuantity</span>
      </div>
      <div class="summary-pair-left">
        <span class="lbl">الاجمالي</span>
        <span class="val">${subtotal.toStringAsFixed(2)}</span>
      </div>
    </div>
    <div class="summary-row">
      <div class="summary-pair-right">
        <span class="lbl">الخصم</span>
        <span class="val">${discount.toStringAsFixed(0)}</span>
      </div>
      <div class="summary-pair-left">
        <span class="lbl">الصافي</span>
        <span class="val">${total.toStringAsFixed(2)}</span>
      </div>
    </div>
    <div class="summary-row">
      <div class="summary-pair-right">
        <span class="lbl">المدفوع</span>
        <span class="val">${paidAmount > 0 ? (paidAmount.truncateToDouble() == paidAmount ? paidAmount.toInt().toString() : paidAmount.toStringAsFixed(2)) : ''}</span>
      </div>
      <div class="summary-pair-left">
        <span class="lbl">الباقي</span>
        <span class="val">${changeAmount > 0 ? (changeAmount.truncateToDouble() == changeAmount ? changeAmount.toInt().toString() : changeAmount.toStringAsFixed(2)) : ''}</span>
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
    يتم استبدال البضاعة خلال ...
  </div>
</body>
</html>
    ''';
  }
}

class CartItem {
  final ItemModel item;
  int quantity;
  double price;

  CartItem({required this.item, required this.quantity, required this.price});
}

class ArabicToEnglishQwerMappingFormatter extends TextInputFormatter {
  static const Map<String, String> _map = {
    // Numerals
    '٠': '0', '١': '1', '٢': '2', '٣': '3', '٤': '4', '٥': '5', '٦': '6', '٧': '7', '٨': '8', '٩': '9',
    // Top row
    'ض': 'q', 'ص': 'w', 'ث': 'e', 'ق': 'r', 'ف': 't', 'غ': 'y', 'ع': 'u', 'ه': 'i', 'خ': 'o', 'ح': 'p', 'ج': '[', 'د': ']',
    // Home row
    'ش': 'a', 'س': 's', 'ي': 'd', 'ب': 'f', 'ل': 'g', 'ا': 'h', 'ت': 'j', 'ن': 'k', 'م': 'l', 'ك': ';', 'ط': "'",
    // Bottom row
    'ئ': 'z', 'ء': 'x', 'ؤ': 'c', 'ر': 'v', 'لا': 'b', 'ى': 'n', 'ة': 'm', 'و': ',', 'ز': '.', 'ظ': '/'
  };

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final buffer = StringBuffer();
    for (int i = 0; i < newValue.text.length; i++) {
      final char = newValue.text[i];
      if (char == 'ل' && i + 1 < newValue.text.length && newValue.text[i + 1] == 'ا') {
        buffer.write('b');
        i++; // Skip 'ا'
      } else if (char == 'ل' && i + 1 < newValue.text.length && newValue.text[i + 1] == 'أ') {
        buffer.write('F');
        i++;
      } else if (char == 'ل' && i + 1 < newValue.text.length && newValue.text[i + 1] == 'إ') {
        buffer.write('T');
        i++;
      } else if (char == 'ل' && i + 1 < newValue.text.length && newValue.text[i + 1] == 'آ') {
        buffer.write('G');
        i++;
      } else {
        buffer.write(_map[char] ?? char);
      }
    }
    return TextEditingValue(
      text: buffer.toString(),
      selection: newValue.selection,
    );
  }
}

class PosMovementsDialog extends StatefulWidget {
  const PosMovementsDialog({super.key});

  @override
  State<PosMovementsDialog> createState() => _PosMovementsDialogState();
}

class _PosMovementsDialogState extends State<PosMovementsDialog> {
  DateTime _startDate = DateTime.now();
  DateTime _endDate = DateTime.now();
  late TextEditingController _pointNoController;
  
  bool _isLoading = false;
  List<dynamic> _movements = [];
  Map<String, dynamic> _summary = {
    'salesTotal': 0.0,
    'returnsTotal': 0.0,
    'receiptsTotal': 0.0,
    'disbursementsTotal': 0.0,
    'totalCount': 0
  };

  @override
  void initState() {
    super.initState();
    final apiService = Provider.of<ApiService>(context, listen: false);
    _pointNoController = TextEditingController(text: apiService.pointNo.toString());
    _loadMovements();
  }

  @override
  void dispose() {
    _pointNoController.dispose();
    super.dispose();
  }

  Future<void> _loadMovements() async {
    setState(() => _isLoading = true);
    final apiService = Provider.of<ApiService>(context, listen: false);
    final ptNo = int.tryParse(_pointNoController.text) ?? apiService.pointNo;
    final startStr = DateFormat('yyyy-MM-dd').format(_startDate);
    final endStr = DateFormat('yyyy-MM-dd').format(_endDate);

    try {
      final res = await apiService.fetchPosMovements(
        pointNo: ptNo,
        startDate: startStr,
        endDate: endStr,
      );
      setState(() {
        _movements = res['movements'] ?? [];
        _summary = res['summary'] ?? {};
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ أثناء جلب حركات المبيعات: $e', style: const TextStyle(fontFamily: 'Cairo')),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _printMovementsReport() {
    final apiService = Provider.of<ApiService>(context, listen: false);
    final startStr = DateFormat('yyyy/MM/dd').format(_startDate);
    final endStr = DateFormat('yyyy/MM/dd').format(_endDate);
    final ptNo = _pointNoController.text;

    String rowsHtml = '';
    for (final item in _movements) {
      rowsHtml += '''
        <tr>
          <td>#${item['fldTransNumber']}</td>
          <td>${item['fldDate']}</td>
          <td>${item['fldPointNO']}</td>
          <td>${item['fldNMenuame']}</td>
          <td>${item['fldBarCode']}</td>
          <td>${item['fldName']}</td>
          <td style="text-align: center;">${item['fldQuantity']}</td>
          <td style="text-align: left;">${(item['fldSalesPrice'] as num).toStringAsFixed(2)}</td>
          <td style="text-align: left;">${(item['fldDiscount'] as num).toStringAsFixed(2)}</td>
          <td style="text-align: left; font-weight: bold;">${(item['fldTotalItem'] as num).toStringAsFixed(2)}</td>
        </tr>
      ''';
    }

    final htmlContent = '''
      <!DOCTYPE html>
      <html lang="ar" dir="rtl">
      <head>
        <meta charset="utf-8">
        <title>تقرير حركة المبيعات اليومية لنقطة البيع</title>
        <style>
          body { font-family: 'Cairo', Tahoma, Arial; padding: 20px; color: #333; }
          .header { text-align: center; margin-bottom: 20px; border-bottom: 2px solid #0056b3; padding-bottom: 10px; }
          .header h2 { margin: 0; color: #0056b3; font-size: 22px; }
          .header p { margin: 4px 0; color: #666; font-size: 13px; }
          .stats-grid { display: flex; justify-content: space-between; margin-bottom: 20px; gap: 10px; }
          .stat-card { flex: 1; background: #f8f9fa; border: 1px solid #ddd; border-radius: 6px; padding: 10px; text-align: center; }
          .stat-title { font-size: 12px; color: #555; }
          .stat-value { font-size: 16px; font-weight: bold; margin-top: 4px; }
          table { width: 100%; border-collapse: collapse; margin-top: 10px; }
          th, td { border: 1px solid #ccc; padding: 8px; font-size: 12px; text-align: right; }
          th { background-color: #0056b3; color: white; }
          tr:nth-child(even) { background-color: #f2f2f2; }
          .total { margin-top: 20px; text-align: left; font-size: 15px; font-weight: bold; color: #0056b3; }
        </style>
      </head>
      <body>
        <div class="header">
          <h2>تقرير حركة المبيعات التفصيلي اليومية</h2>
          <p>نقطة البيع: #${ptNo} (${apiService.pointName}) | الفترة: من $startStr إلى $endStr</p>
        </div>

        <div class="stats-grid">
          <div class="stat-card">
            <div class="stat-title">إجمالي المبيعات (بيع)</div>
            <div class="stat-value" style="color: #10B981;">${(_summary['salesTotal'] as num? ?? 0).toStringAsFixed(2)}</div>
          </div>
          <div class="stat-card">
            <div class="stat-title">إجمالي المرتجعات (مرتجع)</div>
            <div class="stat-value" style="color: #EF4444;">${(_summary['returnsTotal'] as num? ?? 0).toStringAsFixed(2)}</div>
          </div>
          <div class="stat-card">
            <div class="stat-title">إجمالي التوريد (ستور)</div>
            <div class="stat-value" style="color: #3B82F6;">${(_summary['receiptsTotal'] as num? ?? 0).toStringAsFixed(2)}</div>
          </div>
          <div class="stat-card">
            <div class="stat-title">إجمالي الصرف (صرف)</div>
            <div class="stat-value" style="color: #F59E0B;">${(_summary['disbursementsTotal'] as num? ?? 0).toStringAsFixed(2)}</div>
          </div>
        </div>

        <table>
          <thead>
            <tr>
              <th>رقم الحركة</th>
              <th>التاريخ</th>
              <th>النقطة</th>
              <th>نوع الحركة/القائمة</th>
              <th>الباركود</th>
              <th>اسم الصنف</th>
              <th style="text-align: center;">الكمية</th>
              <th>السعر</th>
              <th>الخصم</th>
              <th>الإجمالي</th>
            </tr>
          </thead>
          <tbody>
            $rowsHtml
          </tbody>
        </table>

        <div class="total">
          عدد حركات الأصناف المعروضة: ${_movements.length}
        </div>

        <script>
          window.onload = function() {
            window.print();
            setTimeout(function() { window.close(); }, 500);
          }
        </script>
      </body>
      </html>
    ''';

    PrintService.printHtml(htmlContent);
  }

  Widget _buildStatCard(String title, double amount, Color color, IconData icon) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: color.withOpacity(0.2), shape: BoxShape.circle),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontFamily: 'Cairo', fontSize: 11, color: Colors.white70)),
                  const SizedBox(height: 2),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      amount.toStringAsFixed(2),
                      style: TextStyle(fontFamily: 'Cairo', fontSize: 15, fontWeight: FontWeight.bold, color: color),
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

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Dialog(
        backgroundColor: const Color(0xFF0F172A),
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Container(
          width: MediaQuery.of(context).size.width * 0.85,
          height: MediaQuery.of(context).size.height * 0.85,
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header & Close
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.analytics_rounded, color: Colors.blueAccent, size: 26),
                      SizedBox(width: 10),
                      Text(
                        'عرض حركة المبيعات اليومية لنقطة البيع',
                        style: TextStyle(fontFamily: 'Cairo', color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blueAccent,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        ),
                        icon: const Icon(Icons.print_rounded, size: 18),
                        label: const Text('طباعة التقرير', style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
                        onPressed: _movements.isEmpty ? null : _printMovementsReport,
                      ),
                      const SizedBox(width: 10),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white70),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Filter Controls Bar
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    // Point No Filter
                    SizedBox(
                      width: 140,
                      child: TextField(
                        controller: _pointNoController,
                        style: const TextStyle(color: Colors.white, fontFamily: 'Cairo', fontSize: 13),
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'رقم نقطة البيع',
                          labelStyle: TextStyle(color: Colors.white60, fontFamily: 'Cairo', fontSize: 12),
                          isDense: true,
                          border: OutlineInputBorder(),
                          enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),

                    // From Date
                    InkWell(
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: _startDate,
                          firstDate: DateTime(2020),
                          lastDate: DateTime(2030),
                        );
                        if (picked != null) setState(() => _startDate = picked);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.white24),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.calendar_today, color: Colors.blueAccent, size: 16),
                            const SizedBox(width: 6),
                            Text(
                              'من: ${DateFormat('yyyy-MM-dd').format(_startDate)}',
                              style: const TextStyle(color: Colors.white, fontFamily: 'Cairo', fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),

                    // To Date
                    InkWell(
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: _endDate,
                          firstDate: DateTime(2020),
                          lastDate: DateTime(2030),
                        );
                        if (picked != null) setState(() => _endDate = picked);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.white24),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.calendar_today, color: Colors.blueAccent, size: 16),
                            const SizedBox(width: 6),
                            Text(
                              'إلى: ${DateFormat('yyyy-MM-dd').format(_endDate)}',
                              style: const TextStyle(color: Colors.white, fontFamily: 'Cairo', fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),

                    // Filter Button
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.teal,
                        foregroundColor: Colors.white,
                      ),
                      icon: const Icon(Icons.search_rounded, size: 18),
                      label: const Text('عرض الحركة', style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
                      onPressed: _loadMovements,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Summary Statistics Row
              Row(
                children: [
                  _buildStatCard(
                    'إجمالي المبيعات (بيع)',
                    (_summary['salesTotal'] as num? ?? 0.0).toDouble(),
                    Colors.greenAccent,
                    Icons.shopping_cart_checkout_rounded,
                  ),
                  const SizedBox(width: 10),
                  _buildStatCard(
                    'إجمالي المرتجعات (مرتجع)',
                    (_summary['returnsTotal'] as num? ?? 0.0).toDouble(),
                    Colors.redAccent,
                    Icons.assignment_return_rounded,
                  ),
                  const SizedBox(width: 10),
                  _buildStatCard(
                    'إجمالي التوريد (ستور)',
                    (_summary['receiptsTotal'] as num? ?? 0.0).toDouble(),
                    Colors.blueAccent,
                    Icons.move_to_inbox_rounded,
                  ),
                  const SizedBox(width: 10),
                  _buildStatCard(
                    'إجمالي الصرف (صرف)',
                    (_summary['disbursementsTotal'] as num? ?? 0.0).toDouble(),
                    Colors.orangeAccent,
                    Icons.outbox_rounded,
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Data Table Area
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator(color: Colors.blueAccent))
                    : _movements.isEmpty
                        ? const Center(
                            child: Text(
                              'لا توجد حركات مبيعات مطابقة للفترة ونقطة البيع المحددة',
                              style: TextStyle(fontFamily: 'Cairo', color: Colors.white54, fontSize: 14),
                            ),
                          )
                        : Container(
                            decoration: BoxDecoration(
                              color: const Color(0xFF1E293B),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: Colors.white10),
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: SingleChildScrollView(
                                scrollDirection: Axis.vertical,
                                child: SingleChildScrollView(
                                  scrollDirection: Axis.horizontal,
                                  child: DataTable(
                                    headingRowColor: MaterialStateProperty.all(const Color(0xFF334155)),
                                    columns: const [
                                      DataColumn(label: Text('رقم الحركة', style: TextStyle(fontFamily: 'Cairo', color: Colors.white, fontWeight: FontWeight.bold))),
                                      DataColumn(label: Text('التاريخ', style: TextStyle(fontFamily: 'Cairo', color: Colors.white, fontWeight: FontWeight.bold))),
                                      DataColumn(label: Text('رقم النقطة', style: TextStyle(fontFamily: 'Cairo', color: Colors.white, fontWeight: FontWeight.bold))),
                                      DataColumn(label: Text('نوع الحركة/القائمة', style: TextStyle(fontFamily: 'Cairo', color: Colors.white, fontWeight: FontWeight.bold))),
                                      DataColumn(label: Text('الباركود', style: TextStyle(fontFamily: 'Cairo', color: Colors.white, fontWeight: FontWeight.bold))),
                                      DataColumn(label: Text('اسم الصنف', style: TextStyle(fontFamily: 'Cairo', color: Colors.white, fontWeight: FontWeight.bold))),
                                      DataColumn(label: Text('الكمية', style: TextStyle(fontFamily: 'Cairo', color: Colors.white, fontWeight: FontWeight.bold))),
                                      DataColumn(label: Text('السعر', style: TextStyle(fontFamily: 'Cairo', color: Colors.white, fontWeight: FontWeight.bold))),
                                      DataColumn(label: Text('الخصم', style: TextStyle(fontFamily: 'Cairo', color: Colors.white, fontWeight: FontWeight.bold))),
                                      DataColumn(label: Text('الإجمالي', style: TextStyle(fontFamily: 'Cairo', color: Colors.white, fontWeight: FontWeight.bold))),
                                    ],
                                    rows: _movements.map((item) {
                                      return DataRow(
                                        cells: [
                                          DataCell(Text('#${item['fldTransNumber']}', style: const TextStyle(fontFamily: 'Cairo', color: Colors.blueAccent))),
                                          DataCell(Text('${item['fldDate']}', style: const TextStyle(fontFamily: 'Cairo', color: Colors.white70))),
                                          DataCell(Text('${item['fldPointNO']}', style: const TextStyle(fontFamily: 'Cairo', color: Colors.white70))),
                                          DataCell(Text('${item['fldNMenuame']}', style: const TextStyle(fontFamily: 'Cairo', color: Colors.amberAccent))),
                                          DataCell(Text('${item['fldBarCode']}', style: const TextStyle(fontFamily: 'Cairo', color: Colors.white70))),
                                          DataCell(Text('${item['fldName']}', style: const TextStyle(fontFamily: 'Cairo', color: Colors.white, fontWeight: FontWeight.bold))),
                                          DataCell(Text('${item['fldQuantity']}', style: const TextStyle(fontFamily: 'Cairo', color: Colors.white70))),
                                          DataCell(Text((item['fldSalesPrice'] as num).toStringAsFixed(2), style: const TextStyle(fontFamily: 'Cairo', color: Colors.white70))),
                                          DataCell(Text((item['fldDiscount'] as num).toStringAsFixed(2), style: const TextStyle(fontFamily: 'Cairo', color: Colors.white70))),
                                          DataCell(Text((item['fldTotalItem'] as num).toStringAsFixed(2), style: const TextStyle(fontFamily: 'Cairo', color: Colors.greenAccent, fontWeight: FontWeight.bold))),
                                        ],
                                      );
                                    }).toList(),
                                  ),
                                ),
                              ),
                            ),
                          ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
