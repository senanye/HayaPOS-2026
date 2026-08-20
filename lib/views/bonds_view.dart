import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart' hide TextDirection;
import '../services/api_service.dart';
import '../models/account.dart';
import '../models/bond.dart';
import '../models/currency.dart';

class BondsView extends StatefulWidget {
  const BondsView({super.key});

  @override
  State<BondsView> createState() => _BondsViewState();
}

class _BondsViewState extends State<BondsView> {
  // Inquiry Date, Type & Currency Filters
  final TextEditingController _startDateController = TextEditingController();
  final TextEditingController _endDateController = TextEditingController();
  int _selectedTypeFilter = 0; // 0: All, 10: Receipt (قبض/قرض), 11: Payment (صرف)
  int? _selectedPointFilter;
  int? _selectedMoneyFilter; // null = All Currencies

  // Selected Bond for Editing/Actions
  BondModel? _selectedBond;
  bool _isUploadingBonds = false;

  // Dialog Form Controllers
  final _mainNoteController = TextEditingController();
  final _dateController = TextEditingController();
  
  // Single/Multi Line Form Entry state
  AccountModel? _lineAccount;
  final _lineAmountController = TextEditingController();
  final _lineNoteController = TextEditingController();
  List<BondItemModel> _bondLines = [];
  bool _dialogIsReceipt = false;
  int _dialogPointNo = 1;

  @override
  void initState() {
    super.initState();
    final todayStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
    _startDateController.text = todayStr;
    _endDateController.text = todayStr;
    
    // Load initial bonds list, accounts, and currencies after frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final api = Provider.of<ApiService>(context, listen: false);
      api.loadCurrencies();
      api.loadAccounts();
      _fetchFilteredBonds();
    });
  }

  @override
  void dispose() {
    _startDateController.dispose();
    _endDateController.dispose();
    _mainNoteController.dispose();
    _dateController.dispose();
    _lineAmountController.dispose();
    _lineNoteController.dispose();
    super.dispose();
  }

  void _fetchFilteredBonds() {
    final apiService = Provider.of<ApiService>(context, listen: false);
    apiService.loadBonds(
      startDate: _startDateController.text.trim(),
      endDate: _endDateController.text.trim(),
      pointNo: _selectedPointFilter,
      transType: _selectedTypeFilter,
      moneyId: _selectedMoneyFilter,
    );
  }

  Widget _buildCurrencyBadge(int? moneyId, {String? symbol}) {
    final sym = (symbol != null && symbol.isNotEmpty) ? symbol : (moneyId == 2 ? 'ر.س' : (moneyId == 3 ? '\$' : 'د.أ'));
    Color cColor = Colors.blueAccent;
    if (sym.contains('د.أ') || moneyId == 1) {
      cColor = Colors.tealAccent;
    } else if (sym.contains('ر.س') || moneyId == 2) {
      cColor = Colors.greenAccent;
    } else if (sym.contains('\$') || moneyId == 3) {
      cColor = Colors.amberAccent;
    } else {
      cColor = Colors.cyanAccent;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: cColor.withOpacity(0.12),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: cColor.withOpacity(0.4)),
      ),
      child: Text(
        sym,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: cColor,
          fontWeight: FontWeight.bold,
          fontSize: 11,
          fontFamily: 'Cairo',
        ),
      ),
    );
  }

  Future<void> _selectDate(BuildContext context, TextEditingController controller) async {
    DateTime initial = DateTime.now();
    try {
      if (controller.text.isNotEmpty) {
        initial = DateFormat('yyyy-MM-dd').parse(controller.text);
      }
    } catch (_) {}

    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      builder: (context, child) {
        return Theme(
          data: ThemeData.dark().copyWith(
            colorScheme: const ColorScheme.dark(
              primary: Colors.blueAccent,
              onPrimary: Colors.white,
              surface: Color(0xFF1E293B),
              onSurface: Colors.white,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() {
        controller.text = DateFormat('yyyy-MM-dd').format(picked);
      });
    }
  }

  // --- ADD / EDIT MULTI-LINE BOND DIALOG ---
  void _showBondFormDialog({BondModel? bondToEdit}) {
    final apiService = Provider.of<ApiService>(context, listen: false);
    final isEditing = bondToEdit != null;

    _lineAmountController.clear();
    _lineNoteController.clear();
    _bondLines.clear();

    if (isEditing) {
      _mainNoteController.text = bondToEdit.note;
      _dateController.text = bondToEdit.date;
      _dialogIsReceipt = bondToEdit.isReceipt;
      _dialogPointNo = bondToEdit.pointNo;

      if (bondToEdit.details.isNotEmpty) {
        _bondLines = List.from(bondToEdit.details);
      } else {
        _bondLines.add(BondItemModel(
          expensesId: bondToEdit.expensesId,
          expensesName: bondToEdit.expensesName,
          amount: bondToEdit.amount,
          note: bondToEdit.note,
        ));
      }
    } else {
      _mainNoteController.clear();
      _dateController.text = apiService.selectedDate;
      _dialogIsReceipt = false;
      _dialogPointNo = apiService.pointNo;
    }

    _lineAccount = apiService.accounts.isNotEmpty ? apiService.accounts.first : null;
    CurrencyModel? dialogCurrency;
    if (apiService.currencies.isNotEmpty) {
      if (isEditing) {
        final matches = apiService.currencies.where((c) => c.id == bondToEdit.moneyId).toList();
        dialogCurrency = matches.isNotEmpty ? matches.first : apiService.currencies.first;
      } else {
        final matches = apiService.currencies.where((c) => c.id == apiService.defaultMoneyId).toList();
        dialogCurrency = matches.isNotEmpty ? matches.first : apiService.currencies.first;
      }
    }
    final dialogFormKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            final totalVoucherAmount = _bondLines.fold(0.0, (sum, item) => sum + item.amount);

            return Directionality(
              textDirection: TextDirection.rtl,
              child: AlertDialog(
                backgroundColor: const Color(0xFF1E293B),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                title: Row(
                  children: [
                    Icon(
                      isEditing ? Icons.edit_note_rounded : Icons.receipt_long_rounded,
                      color: isEditing ? Colors.amberAccent : Colors.blueAccent,
                      size: 28,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      isEditing ? 'تعديل السند المالي متعدد البنود' : 'إصدار سند مالي جديد (متعدد الحسابات والعمليات)',
                      style: const TextStyle(
                        fontFamily: 'Cairo',
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        fontSize: 18,
                      ),
                    ),
                    if (isEditing) ...[
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          'رقم السند: ${bondToEdit.transNumber.toStringAsFixed(0)}',
                          style: const TextStyle(color: Colors.blueAccent, fontSize: 12, fontFamily: 'Cairo', fontWeight: FontWeight.bold),
                        ),
                      )
                    ]
                  ],
                ),
                content: SizedBox(
                  width: 720,
                  child: Form(
                    key: dialogFormKey,
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Toggle Receipt vs Payment & Date
                          Row(
                            children: [
                              Expanded(
                                flex: 2,
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: ElevatedButton.icon(
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: !_dialogIsReceipt ? const Color(0xFFEF4444) : const Color(0xFF0F172A),
                                          foregroundColor: Colors.white,
                                          padding: const EdgeInsets.symmetric(vertical: 14),
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(8),
                                            side: BorderSide(
                                              color: !_dialogIsReceipt ? Colors.redAccent : Colors.white24,
                                              width: !_dialogIsReceipt ? 2 : 1,
                                            ),
                                          ),
                                          elevation: !_dialogIsReceipt ? 6 : 0,
                                        ),
                                        icon: Icon(Icons.arrow_upward_rounded, size: 18, color: !_dialogIsReceipt ? Colors.white : Colors.white60),
                                        label: Text(
                                          !_dialogIsReceipt ? 'سند صرف (Payment) ⬆  (محدد ✅)' : 'سند صرف (Payment) ⬆',
                                          style: TextStyle(
                                            fontFamily: 'Cairo',
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold,
                                            color: !_dialogIsReceipt ? Colors.white : Colors.white60,
                                          ),
                                        ),
                                        onPressed: () => setStateDialog(() => _dialogIsReceipt = false),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: ElevatedButton.icon(
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: _dialogIsReceipt ? const Color(0xFF10B981) : const Color(0xFF0F172A),
                                          foregroundColor: Colors.white,
                                          padding: const EdgeInsets.symmetric(vertical: 14),
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(8),
                                            side: BorderSide(
                                              color: _dialogIsReceipt ? Colors.greenAccent : Colors.white24,
                                              width: _dialogIsReceipt ? 2 : 1,
                                            ),
                                          ),
                                          elevation: _dialogIsReceipt ? 6 : 0,
                                        ),
                                        icon: Icon(Icons.arrow_downward_rounded, size: 18, color: _dialogIsReceipt ? Colors.white : Colors.white60),
                                        label: Text(
                                          _dialogIsReceipt ? 'سند قبض / قرض (Receipt) ⬇  (محدد ✅)' : 'سند قبض / قرض (Receipt) ⬇',
                                          style: TextStyle(
                                            fontFamily: 'Cairo',
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold,
                                            color: _dialogIsReceipt ? Colors.white : Colors.white60,
                                          ),
                                        ),
                                        onPressed: () => setStateDialog(() => _dialogIsReceipt = true),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 12),
                              SizedBox(
                                width: 160,
                                child: TextFormField(
                                  controller: _dateController,
                                  readOnly: true,
                                  onTap: () async {
                                    await _selectDate(context, _dateController);
                                    setStateDialog(() {});
                                  },
                                  decoration: const InputDecoration(
                                    labelText: 'التاريخ',
                                    filled: true,
                                    fillColor: Color(0xFF0F172A),
                                    border: OutlineInputBorder(),
                                    prefixIcon: Icon(Icons.calendar_today, color: Colors.blueAccent, size: 18),
                                  ),
                                  style: const TextStyle(fontFamily: 'Cairo', color: Colors.white, fontSize: 13),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),

                          // Header Note & POS Info & Currency
                          Row(
                            children: [
                              Expanded(
                                flex: 3,
                                child: TextFormField(
                                  controller: _mainNoteController,
                                  decoration: const InputDecoration(
                                    labelText: 'البيان العام / ملاحظة السند المالي',
                                    filled: true,
                                    fillColor: Color(0xFF0F172A),
                                    border: OutlineInputBorder(),
                                    prefixIcon: Icon(Icons.edit_note_outlined, color: Colors.amberAccent),
                                  ),
                                  style: const TextStyle(fontFamily: 'Cairo', color: Colors.white, fontSize: 13),
                                ),
                              ),
                              const SizedBox(width: 10),
                              // Currency Selector Dropdown
                              if (apiService.currencies.isNotEmpty)
                                SizedBox(
                                  width: 170,
                                  child: DropdownButtonFormField<CurrencyModel>(
                                    value: dialogCurrency,
                                    style: const TextStyle(color: Colors.white, fontFamily: 'Cairo', fontSize: 13),
                                    dropdownColor: const Color(0xFF1E293B),
                                    decoration: const InputDecoration(
                                      labelText: 'العملة',
                                      labelStyle: TextStyle(color: Colors.amberAccent, fontFamily: 'Cairo', fontSize: 12),
                                      contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                      filled: true,
                                      fillColor: Color(0xFF0F172A),
                                      border: OutlineInputBorder(),
                                      prefixIcon: Icon(Icons.monetization_on_outlined, color: Colors.amberAccent, size: 18),
                                    ),
                                    items: apiService.currencies.map((curr) {
                                      return DropdownMenuItem<CurrencyModel>(
                                        value: curr,
                                        child: Text('${curr.name} (${curr.symbol})', style: const TextStyle(fontFamily: 'Cairo', fontSize: 12)),
                                      );
                                    }).toList(),
                                    onChanged: (val) {
                                      if (val != null) {
                                        setStateDialog(() {
                                          dialogCurrency = val;
                                        });
                                      }
                                    },
                                  ),
                                ),
                              const SizedBox(width: 10),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                                decoration: BoxDecoration(
                                  color: Colors.blueAccent.withOpacity(0.12),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: Colors.blueAccent.withOpacity(0.3)),
                                ),
                                child: Text(
                                  'نقطة #$_dialogPointNo',
                                  style: const TextStyle(color: Colors.blueAccent, fontWeight: FontWeight.bold, fontFamily: 'Cairo', fontSize: 13),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 20),

                          // --- LINE ENTRY FORM (إضافة بند حركة جديد للسند) ---
                          Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: const Color(0xFF0F172A),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: Colors.blueAccent.withOpacity(0.2)),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'إضافة بنود وحسابات للسند (مثل أسطر فاتورة المبيعات والأصناف):',
                                  style: TextStyle(color: Colors.blueAccent, fontWeight: FontWeight.bold, fontFamily: 'Cairo', fontSize: 13),
                                ),
                                const SizedBox(height: 10),
                                Row(
                                  children: [
                                    // Account Selection
                                    Expanded(
                                      flex: 3,
                                      child: DropdownButtonFormField<AccountModel>(
                                        value: _lineAccount,
                                        hint: const Text('اختر الحساب', style: TextStyle(fontFamily: 'Cairo', fontSize: 12)),
                                        style: const TextStyle(color: Colors.white, fontFamily: 'Cairo', fontSize: 13),
                                        dropdownColor: const Color(0xFF1E293B),
                                        decoration: const InputDecoration(
                                          contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                          filled: true,
                                          fillColor: Color(0xFF1E293B),
                                          border: OutlineInputBorder(),
                                        ),
                                        items: apiService.accounts.map((acc) {
                                          return DropdownMenuItem<AccountModel>(
                                            value: acc,
                                            child: Text(acc.name),
                                          );
                                        }).toList(),
                                        onChanged: (val) {
                                          setStateDialog(() {
                                            _lineAccount = val;
                                          });
                                        },
                                      ),
                                    ),
                                    const SizedBox(width: 8),

                                    // Amount Field
                                    Expanded(
                                      flex: 2,
                                      child: TextFormField(
                                        controller: _lineAmountController,
                                        decoration: const InputDecoration(
                                          hintText: 'المبلغ',
                                          contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                          filled: true,
                                          fillColor: Color(0xFF1E293B),
                                          border: OutlineInputBorder(),
                                        ),
                                        keyboardType: TextInputType.number,
                                        style: const TextStyle(fontFamily: 'Cairo', color: Colors.greenAccent, fontWeight: FontWeight.bold, fontSize: 13),
                                      ),
                                    ),
                                    const SizedBox(width: 8),

                                    // Line Note Field
                                    Expanded(
                                      flex: 3,
                                      child: TextFormField(
                                        controller: _lineNoteController,
                                        decoration: const InputDecoration(
                                          hintText: 'تفاصيل البند / البيان',
                                          contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                          filled: true,
                                          fillColor: Color(0xFF1E293B),
                                          border: OutlineInputBorder(),
                                        ),
                                        style: const TextStyle(fontFamily: 'Cairo', color: Colors.white, fontSize: 13),
                                      ),
                                    ),
                                    const SizedBox(width: 8),

                                    // Add Line Button
                                    ElevatedButton.icon(
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.blueAccent,
                                        foregroundColor: Colors.white,
                                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                                      ),
                                      icon: const Icon(Icons.add, size: 18),
                                      label: const Text('إضافة بند +', style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 12)),
                                      onPressed: () {
                                        if (_lineAccount == null) {
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            const SnackBar(content: Text('يرجى اختيار الحساب أولاً', style: TextStyle(fontFamily: 'Cairo')), backgroundColor: Colors.red),
                                          );
                                          return;
                                        }
                                        final amt = double.tryParse(_lineAmountController.text);
                                        if (amt == null || amt <= 0) {
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            const SnackBar(content: Text('يرجى إدخال مبلغ صحيح للبند', style: TextStyle(fontFamily: 'Cairo')), backgroundColor: Colors.red),
                                          );
                                          return;
                                        }

                                        setStateDialog(() {
                                          _bondLines.add(BondItemModel(
                                            expensesId: _lineAccount!.id,
                                            expensesName: _lineAccount!.name,
                                            amount: amt,
                                            note: _lineNoteController.text.trim(),
                                          ));
                                          _lineAmountController.clear();
                                          _lineNoteController.clear();
                                        });
                                      },
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),

                          // --- LINES DATA TABLE ---
                          const Text('أسطر وبنود السند المالي المسجلة:', style: TextStyle(color: Colors.white70, fontFamily: 'Cairo', fontSize: 13, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 6),
                          Container(
                            constraints: const BoxConstraints(maxHeight: 200),
                            decoration: BoxDecoration(
                              color: const Color(0xFF0F172A),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.white10),
                            ),
                            child: _bondLines.isEmpty
                                ? const Center(
                                    child: Padding(
                                      padding: EdgeInsets.all(20.0),
                                      child: Text(
                                        'لم يتم إضافة بنود بعد. قم باختيار الحساب والمبلغ والضغط على "إضافة بند +".',
                                        style: TextStyle(color: Colors.white38, fontFamily: 'Cairo', fontSize: 12),
                                      ),
                                    ),
                                  )
                                : ListView.separated(
                                    shrinkWrap: true,
                                    itemCount: _bondLines.length,
                                    separatorBuilder: (_, __) => const Divider(color: Colors.white10, height: 1),
                                    itemBuilder: (context, idx) {
                                      final line = _bondLines[idx];
                                      return ListTile(
                                        dense: true,
                                        leading: CircleAvatar(
                                          radius: 12,
                                          backgroundColor: Colors.blueAccent.withOpacity(0.2),
                                          child: Text('${idx + 1}', style: const TextStyle(color: Colors.blueAccent, fontSize: 11, fontWeight: FontWeight.bold)),
                                        ),
                                        title: Text(line.expensesName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontFamily: 'Cairo', fontSize: 13)),
                                        subtitle: Text(line.note.isNotEmpty ? line.note : 'بدون بيان فرعي', style: const TextStyle(color: Colors.white54, fontFamily: 'Cairo', fontSize: 11)),
                                        trailing: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Text('${line.amount.toStringAsFixed(2)} د.أ', style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold, fontSize: 14)),
                                            const SizedBox(width: 8),
                                            IconButton(
                                              icon: const Icon(Icons.remove_circle_outline, color: Colors.redAccent, size: 18),
                                              onPressed: () {
                                                setStateDialog(() {
                                                  _bondLines.removeAt(idx);
                                                });
                                              },
                                            )
                                          ],
                                        ),
                                      );
                                    },
                                  ),
                          ),
                          const SizedBox(height: 16),

                          // Total Voucher Amount Summary Bar
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            decoration: BoxDecoration(
                              color: Colors.green.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.green.withOpacity(0.3)),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'إجمالي مبلغ السند (${_bondLines.length} بنود):',
                                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontFamily: 'Cairo', fontSize: 14),
                                ),
                                Text(
                                  '${totalVoucherAmount.toStringAsFixed(2)} د.أ',
                                  style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold, fontSize: 20),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('إلغاء', style: TextStyle(fontFamily: 'Cairo', color: Colors.white60)),
                  ),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _dialogIsReceipt ? Colors.green : Colors.redAccent,
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    icon: Icon(isEditing ? Icons.save_rounded : Icons.check_circle_rounded, color: Colors.white),
                    label: Text(
                      isEditing ? 'حفظ تعديلات السند' : 'حفظ السند متعدد البنود في Main و tblExpenses',
                      style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                    onPressed: () async {
                      if (_bondLines.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('يرجى إضافة بند واحد على الأقل للسند قبل الحفظ', style: TextStyle(fontFamily: 'Cairo')), backgroundColor: Colors.red),
                        );
                        return;
                      }

                      try {
                        final mainNote = _mainNoteController.text.trim();
                        final dateVal = _dateController.text.trim();
                        final firstExpId = _bondLines.first.expensesId;

                        final selectedMoneyId = dialogCurrency?.id ?? apiService.defaultMoneyId;
                        if (isEditing) {
                          await apiService.updateBond(
                            bondToEdit.id,
                            bondToEdit.transNumber,
                            firstExpId,
                            totalVoucherAmount,
                            mainNote,
                            _dialogIsReceipt,
                            pointNo: _dialogPointNo,
                            bondDate: dateVal,
                            moneyId: selectedMoneyId,
                            accountId: firstExpId,
                            details: _bondLines,
                          );
                        } else {
                          await apiService.addBond(
                            firstExpId,
                            totalVoucherAmount,
                            mainNote,
                            _dialogIsReceipt,
                            pointNo: _dialogPointNo,
                            bondDate: dateVal,
                            moneyId: selectedMoneyId,
                            accountId: firstExpId,
                            details: _bondLines,
                          );
                        }

                        if (mounted) {
                          Navigator.pop(context);
                          _fetchFilteredBonds();
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                isEditing ? 'تم تعديل السند المالي بنجاح' : (_dialogIsReceipt ? 'تم حفظ سند القبض متعدد البنود في Main و tblExpenses بنجاح' : 'تم حفظ سند الصرف متعدد البنود في Main و tblExpenses بنجاح'),
                                style: const TextStyle(fontFamily: 'Cairo'),
                              ),
                              backgroundColor: Colors.green,
                            ),
                          );
                        }
                      } catch (e) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('خطأ أثناء حفظ السند: $e', style: const TextStyle(fontFamily: 'Cairo')),
                              backgroundColor: Colors.red,
                            ),
                          );
                        }
                      }
                    },
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // --- POST / SYNC BONDS TO REMOTE DB ---
  Future<void> _handlePostBondsToRemote() async {
    final apiService = Provider.of<ApiService>(context, listen: false);
    setState(() {
      _isUploadingBonds = true;
    });

    try {
      final res = await apiService.uploadBonds();
      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => Directionality(
            textDirection: TextDirection.rtl,
            child: AlertDialog(
              backgroundColor: const Color(0xFF1E293B),
              title: const Row(
                children: [
                  Icon(Icons.check_circle, color: Colors.green, size: 28),
                  SizedBox(width: 10),
                  Text('تم ترحيل السندات بنجاح', style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, color: Colors.white)),
                ],
              ),
              content: Text(
                res['message'] ?? 'تم ترحيل جميع السندات إلى قاعدة البيانات الأساسية في الجهاز الرئيسي بنجاح.',
                style: const TextStyle(fontFamily: 'Cairo', color: Colors.white70),
              ),
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
    } catch (e) {
      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => Directionality(
            textDirection: TextDirection.rtl,
            child: AlertDialog(
              backgroundColor: const Color(0xFF1E293B),
              title: const Text('فشل ترحيل السندات', style: TextStyle(fontFamily: 'Cairo', color: Colors.red)),
              content: Text(e.toString().replaceAll('Exception:', '').trim(), style: const TextStyle(fontFamily: 'Cairo', color: Colors.white70)),
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
    } finally {
      if (mounted) {
        setState(() {
          _isUploadingBonds = false;
        });
      }
    }
  }

  // --- DELETE BOND DIALOG ---
  void _confirmDeleteBond(BondModel bond) {
    final apiService = Provider.of<ApiService>(context, listen: false);

    showDialog(
      context: context,
      builder: (context) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: const Color(0xFF1E293B),
          title: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.redAccent, size: 28),
              SizedBox(width: 10),
              Text('تأكيد حذف السند', style: TextStyle(fontFamily: 'Cairo', color: Colors.white, fontWeight: FontWeight.bold)),
            ],
          ),
          content: Text(
            'هل أنت تأكد من رغبتك في حذف السند رقم ${bond.transNumber.toStringAsFixed(0)} كلياً بقيمة إجمالية ${bond.amount.toStringAsFixed(2)}؟\nسيتم حذف البيانات والبنود التابعة له من جدولي Main و tblExpenses.',
            style: const TextStyle(fontFamily: 'Cairo', color: Colors.white70),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('إلغاء', style: TextStyle(fontFamily: 'Cairo', color: Colors.white60)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
              onPressed: () async {
                try {
                  await apiService.deleteBond(bond.id, bond.transNumber);
                  if (mounted) {
                    Navigator.pop(context);
                    if (_selectedBond?.id == bond.id) {
                      setState(() {
                        _selectedBond = null;
                      });
                    }
                    _fetchFilteredBonds();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('تم حذف السند بكافة بنوده بنجاح', style: TextStyle(fontFamily: 'Cairo')),
                        backgroundColor: Colors.green,
                      ),
                    );
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('فشل الحذف: $e', style: const TextStyle(fontFamily: 'Cairo')),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                }
              },
              child: const Text('نعم، احذف السند كلياً', style: TextStyle(fontFamily: 'Cairo', color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final apiService = Provider.of<ApiService>(context);
    final bondsList = apiService.bonds;

    // Calculate Summary statistics
    double totalReceipts = 0.0;
    double totalPayments = 0.0;

    for (var b in bondsList) {
      if (b.isReceipt) {
        totalReceipts += b.amount;
      } else {
        totalPayments += b.amount;
      }
    }
    final netMovement = totalReceipts - totalPayments;

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      body: Directionality(
        textDirection: TextDirection.rtl,
        child: Padding(
          padding: const EdgeInsets.all(28.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // --- HEADER & MAIN ACTIONS ---
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'إدارة واستعلامات السندات المالية متعددة البنود (Main & tblExpenses)',
                        style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold, fontFamily: 'Cairo'),
                      ),
                      Text(
                        'إصدار سندات متعددة العمليات والحسابات، استعلام بالفترة الزمنية، تعديل، وترحيل السندات لقاعدة البيانات الرئيسية (نقطة البيع: ${apiService.pointNo})',
                        style: const TextStyle(color: Colors.white54, fontSize: 13, fontFamily: 'Cairo'),
                      ),
                    ],
                  ),

                  // Action Buttons Row
                  Row(
                    children: [
                      // Post / Transfer Bonds Button
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.teal,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        icon: _isUploadingBonds
                            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Icon(Icons.cloud_upload_rounded),
                        label: const Text('ترحيل السندات للسيرفر الرئيسي', style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
                        onPressed: _isUploadingBonds || !apiService.isConnected ? null : _handlePostBondsToRemote,
                      ),
                      const SizedBox(width: 12),

                      // Edit Selected Bond Button
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _selectedBond != null ? Colors.amber[700] : Colors.white12,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        icon: const Icon(Icons.edit_note_rounded),
                        label: const Text('تعديل السند', style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
                        onPressed: _selectedBond != null ? () => _showBondFormDialog(bondToEdit: _selectedBond) : null,
                      ),
                      const SizedBox(width: 12),

                      // New Bond Button
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blueAccent,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        icon: const Icon(Icons.note_add_outlined),
                        label: const Text('إنشاء سند جديد متعدد البنود', style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
                        onPressed: () => _showBondFormDialog(),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // --- INQUIRY FILTER BAR ---
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white10),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.filter_alt_outlined, color: Colors.blueAccent, size: 22),
                    const SizedBox(width: 8),
                    const Text('تصفية الاستعلامات:', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontFamily: 'Cairo', fontSize: 14)),
                    const SizedBox(width: 16),

                    // From Date
                    const Text('من تاريخ:', style: TextStyle(color: Colors.white70, fontFamily: 'Cairo', fontSize: 12)),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 140,
                      height: 40,
                      child: TextField(
                        controller: _startDateController,
                        readOnly: true,
                        onTap: () async {
                          await _selectDate(context, _startDateController);
                          _fetchFilteredBonds();
                        },
                        style: const TextStyle(color: Colors.white, fontFamily: 'Cairo', fontSize: 12),
                        decoration: InputDecoration(
                          filled: true,
                          fillColor: const Color(0xFF0F172A),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                          suffixIcon: const Icon(Icons.calendar_month, color: Colors.white30, size: 16),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),

                    // To Date
                    const Text('إلى تاريخ:', style: TextStyle(color: Colors.white70, fontFamily: 'Cairo', fontSize: 12)),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 140,
                      height: 40,
                      child: TextField(
                        controller: _endDateController,
                        readOnly: true,
                        onTap: () async {
                          await _selectDate(context, _endDateController);
                          _fetchFilteredBonds();
                        },
                        style: const TextStyle(color: Colors.white, fontFamily: 'Cairo', fontSize: 12),
                        decoration: InputDecoration(
                          filled: true,
                          fillColor: const Color(0xFF0F172A),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                          suffixIcon: const Icon(Icons.calendar_month, color: Colors.white30, size: 16),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),

                    // Type Filter Dropdown
                    const Text('نوع السند:', style: TextStyle(color: Colors.white70, fontFamily: 'Cairo', fontSize: 12)),
                    const SizedBox(width: 8),
                    Container(
                      height: 40,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0F172A),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: Colors.white24),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<int>(
                          value: _selectedTypeFilter,
                          dropdownColor: const Color(0xFF0F172A),
                          style: const TextStyle(color: Colors.white, fontFamily: 'Cairo', fontSize: 12),
                          items: const [
                            DropdownMenuItem(value: 0, child: Text('كافة السندات (قبض وصرف)')),
                            DropdownMenuItem(value: 10, child: Text('سندات القبض والقروض فقط')),
                            DropdownMenuItem(value: 11, child: Text('سندات الصرف والمصروفات فقط')),
                          ],
                          onChanged: (val) {
                            if (val != null) {
                              setState(() {
                                _selectedTypeFilter = val;
                              });
                              _fetchFilteredBonds();
                            }
                          },
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),

                    // Currency Filter Dropdown
                    const Text('العملة:', style: TextStyle(color: Colors.white70, fontFamily: 'Cairo', fontSize: 12)),
                    const SizedBox(width: 8),
                    Consumer<ApiService>(
                      builder: (context, api, _) {
                        final currencies = api.currencies;
                        return Container(
                          height: 40,
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0F172A),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: Colors.cyanAccent.withOpacity(0.3)),
                          ),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<int?>(
                              value: _selectedMoneyFilter,
                              dropdownColor: const Color(0xFF0F172A),
                              style: const TextStyle(color: Colors.white, fontFamily: 'Cairo', fontSize: 12),
                              items: [
                                const DropdownMenuItem<int?>(
                                  value: null,
                                  child: Text('🌐 كافة العملات', style: TextStyle(color: Colors.cyanAccent, fontWeight: FontWeight.bold)),
                                ),
                                ...currencies.map((c) => DropdownMenuItem<int?>(
                                  value: c.id,
                                  child: Text('${c.name} (${c.symbol})'),
                                )),
                              ],
                              onChanged: (val) {
                                setState(() {
                                  _selectedMoneyFilter = val;
                                });
                                _fetchFilteredBonds();
                              },
                            ),
                          ),
                        );
                      },
                    ),
                    const Spacer(),

                    // Search Button
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blueAccent,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                      ),
                      icon: const Icon(Icons.search, size: 18),
                      label: const Text('استعلام الحركات', style: TextStyle(fontFamily: 'Cairo', fontSize: 12, fontWeight: FontWeight.bold)),
                      onPressed: _fetchFilteredBonds,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // --- KPI SUMMARY CARDS ---
              Row(
                children: [
                  // Total Receipts Card
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.green.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.green.withOpacity(0.3)),
                      ),
                      child: Row(
                        children: [
                          const CircleAvatar(
                            backgroundColor: Colors.green,
                            child: Icon(Icons.arrow_downward_rounded, color: Colors.white),
                          ),
                          const SizedBox(width: 12),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('إجمالي المقبوضات والقروض', style: TextStyle(color: Colors.white60, fontSize: 12, fontFamily: 'Cairo')),
                              Text(
                                '${totalReceipts.toStringAsFixed(2)} ${bondsList.isNotEmpty && bondsList.first.currencySymbol.isNotEmpty ? bondsList.first.currencySymbol : 'د.أ'}',
                                style: const TextStyle(color: Colors.greenAccent, fontSize: 18, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),

                  // Total Payments Card
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.redAccent.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.redAccent.withOpacity(0.3)),
                      ),
                      child: Row(
                        children: [
                          const CircleAvatar(
                            backgroundColor: Colors.redAccent,
                            child: Icon(Icons.arrow_upward_rounded, color: Colors.white),
                          ),
                          const SizedBox(width: 12),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('إجمالي المصروفات والمدفوعات', style: TextStyle(color: Colors.white60, fontSize: 12, fontFamily: 'Cairo')),
                              Text(
                                '${totalPayments.toStringAsFixed(2)} ${bondsList.isNotEmpty && bondsList.first.currencySymbol.isNotEmpty ? bondsList.first.currencySymbol : 'د.أ'}',
                                style: const TextStyle(color: Colors.redAccent, fontSize: 18, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),

                  // Net Movement Card
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: (netMovement >= 0 ? Colors.blueAccent : Colors.orangeAccent).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: (netMovement >= 0 ? Colors.blueAccent : Colors.orangeAccent).withOpacity(0.3)),
                      ),
                      child: Row(
                        children: [
                          CircleAvatar(
                            backgroundColor: netMovement >= 0 ? Colors.blueAccent : Colors.orangeAccent,
                            child: const Icon(Icons.account_balance_wallet_outlined, color: Colors.white),
                          ),
                          const SizedBox(width: 12),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('صافي حركة الفترة الاستعلامية', style: TextStyle(color: Colors.white60, fontSize: 12, fontFamily: 'Cairo')),
                              Text(
                                '${netMovement.abs().toStringAsFixed(2)} ${bondsList.isNotEmpty && bondsList.first.currencySymbol.isNotEmpty ? bondsList.first.currencySymbol : 'د.أ'} (${netMovement >= 0 ? 'فائض' : 'عجز'})',
                                style: TextStyle(color: netMovement >= 0 ? Colors.blueAccent : Colors.orangeAccent, fontSize: 18, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),

                  // Total Count Card
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E293B),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.white10),
                    ),
                    child: Column(
                      children: [
                        const Text('عدد السندات', style: TextStyle(color: Colors.white60, fontSize: 12, fontFamily: 'Cairo')),
                        Text(
                          '${bondsList.length}',
                          style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // --- BONDS LIST / INQUIRY DATA TABLE ---
              Expanded(
                child: apiService.isLoading && bondsList.isEmpty
                    ? const Center(child: CircularProgressIndicator())
                    : bondsList.isEmpty
                        ? const Center(
                            child: Text(
                              'لا توجد حركات سندات مالية في الفترة المحددة.',
                              style: TextStyle(color: Colors.white30, fontSize: 16, fontFamily: 'Cairo'),
                            ),
                          )
                        : ListView.builder(
                            itemCount: bondsList.length,
                            itemBuilder: (context, index) {
                              final bond = bondsList[index];
                              final isSelected = _selectedBond?.id == bond.id;
                              final cSym = bond.currencySymbol.isNotEmpty ? bond.currencySymbol : 'د.أ';

                              return Card(
                                color: isSelected ? const Color(0xFF2A3952) : const Color(0xFF1E293B),
                                margin: const EdgeInsets.only(bottom: 10),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  side: isSelected ? const BorderSide(color: Colors.blueAccent, width: 2) : BorderSide.none,
                                ),
                                child: ExpansionTile(
                                  tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                                  leading: CircleAvatar(
                                    backgroundColor: bond.isReceipt 
                                        ? Colors.green.withOpacity(0.15) 
                                        : Colors.redAccent.withOpacity(0.15),
                                    child: Icon(
                                      bond.isReceipt ? Icons.arrow_downward_rounded : Icons.arrow_upward_rounded,
                                      color: bond.isReceipt ? Colors.green : Colors.redAccent,
                                    ),
                                  ),
                                  title: Row(
                                    children: [
                                      Text(
                                        bond.expensesName,
                                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15, fontFamily: 'Cairo'),
                                      ),
                                      const SizedBox(width: 10),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: bond.isReceipt ? Colors.green.withOpacity(0.15) : Colors.redAccent.withOpacity(0.15),
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          bond.isReceipt ? 'قبض / قرض' : 'صرف / مصروفات',
                                          style: TextStyle(
                                            color: bond.isReceipt ? Colors.green : Colors.redAccent,
                                            fontSize: 11,
                                            fontFamily: 'Cairo',
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      _buildCurrencyBadge(bond.moneyId, symbol: cSym),
                                      if (bond.details.length > 1) ...[
                                        const SizedBox(width: 8),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: Colors.blueAccent.withOpacity(0.2),
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          child: Text(
                                            '${bond.details.length} بنود فرعية',
                                            style: const TextStyle(color: Colors.blueAccent, fontSize: 11, fontFamily: 'Cairo', fontWeight: FontWeight.bold),
                                          ),
                                        )
                                      ]
                                    ],
                                  ),
                                  subtitle: Text(
                                    'رقم السند: ${bond.transNumber > 0 ? bond.transNumber.toStringAsFixed(0) : "غير محدد"}  |  التاريخ: ${bond.date}  |  العملة: $cSym  |  البيان: ${bond.note.isNotEmpty ? bond.note : "بدون بيان عام"}',
                                    style: const TextStyle(color: Colors.white54, fontSize: 12, fontFamily: 'Cairo'),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        '${bond.amount.toStringAsFixed(2)} $cSym',
                                        style: TextStyle(
                                          color: bond.isReceipt ? Colors.greenAccent : Colors.redAccent,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 17,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      IconButton(
                                        icon: const Icon(Icons.edit_outlined, color: Colors.amberAccent, size: 20),
                                        tooltip: 'تعديل السند',
                                        onPressed: () => _showBondFormDialog(bondToEdit: bond),
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 20),
                                        tooltip: 'حذف السند',
                                        onPressed: () => _confirmDeleteBond(bond),
                                      ),
                                    ],
                                  ),
                                  children: [
                                    if (bond.details.isNotEmpty)
                                      Container(
                                        padding: const EdgeInsets.all(12),
                                        color: const Color(0xFF0F172A),
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            const Text('تفاصيل أسطر وبنود السند الفرعية:', style: TextStyle(color: Colors.blueAccent, fontWeight: FontWeight.bold, fontFamily: 'Cairo', fontSize: 12)),
                                            const SizedBox(height: 8),
                                            ...bond.details.map((d) {
                                              return Padding(
                                                padding: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 8.0),
                                                child: Row(
                                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                                  children: [
                                                    Row(
                                                      children: [
                                                        const Icon(Icons.subdirectory_arrow_right, color: Colors.white38, size: 16),
                                                        const SizedBox(width: 8),
                                                        Text(d.expensesName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontFamily: 'Cairo', fontSize: 13)),
                                                        const SizedBox(width: 12),
                                                        Text(d.note.isNotEmpty ? '(${d.note})' : '', style: const TextStyle(color: Colors.white54, fontFamily: 'Cairo', fontSize: 12)),
                                                      ],
                                                    ),
                                                    Text('${d.amount.toStringAsFixed(2)} $cSym', style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold, fontSize: 13)),
                                                  ],
                                                ),
                                              );
                                            }),
                                          ],
                                        ),
                                      )
                                  ],
                                ),
                              );
                            },
                          ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
