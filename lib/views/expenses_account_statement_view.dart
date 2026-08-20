import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'dart:convert';
import 'package:universal_html/js.dart' as js;
import '../services/api_service.dart';

class ExpensesAccountStatementView extends StatefulWidget {
  const ExpensesAccountStatementView({super.key});

  @override
  State<ExpensesAccountStatementView> createState() => _ExpensesAccountStatementViewState();
}

class _ExpensesAccountStatementViewState extends State<ExpensesAccountStatementView> {
  DateTime? _startDate;
  DateTime? _endDate;

  int? _selectedAccountId;
  int? _selectedMoneyId;
  String _accountSearchQuery = '';
  List<Map<String, dynamic>> _accountsList = [];

  Map<String, dynamic> _statementData = {
    "accountId": 0,
    "accountName": "جميع الحسابات والمصاريف",
    "totalDebit": 0.0,
    "totalCredit": 0.0,
    "balance": 0.0,
    "summaryByCurrency": {},
    "movements": []
  };

  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _startDate = DateTime.now();
    _endDate = DateTime.now();
    _loadAccounts();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final api = Provider.of<ApiService>(context, listen: false);
      api.loadCurrencies();
    });
    _fetchStatementData();
  }

  Future<void> _loadAccounts() async {
    final apiService = Provider.of<ApiService>(context, listen: false);
    try {
      final accs = await apiService.getExpensesAccountsList();
      if (mounted) {
        setState(() {
          _accountsList = accs;
        });
      }
    } catch (e) {
      debugPrint("Error loading accounts list: $e");
    }
  }

  Future<void> _fetchStatementData() async {
    setState(() => _isLoading = true);
    final apiService = Provider.of<ApiService>(context, listen: false);

    final startStr = _startDate != null ? DateFormat('yyyy-MM-dd').format(_startDate!) : null;
    final endStr = _endDate != null ? DateFormat('yyyy-MM-dd').format(_endDate!) : null;

    try {
      final res = await apiService.fetchAccountStatement(
        accountId: _selectedAccountId,
        start: startStr,
        end: endStr,
        moneyId: _selectedMoneyId,
      );
      setState(() {
        _statementData = res;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ أثناء جلب كشف الحساب: $e', style: const TextStyle(fontFamily: 'Cairo')),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _getCurrencySymbol(int? moneyId) {
    if (moneyId == null || moneyId <= 0) {
      final api = Provider.of<ApiService>(context, listen: false);
      if (api.currencies.isNotEmpty) {
        final def = api.currencies.firstWhere((c) => c.id == api.defaultMoneyId, orElse: () => api.currencies.first);
        return def.symbol.isNotEmpty ? def.symbol : 'د.أ';
      }
      return 'د.أ';
    }
    final api = Provider.of<ApiService>(context, listen: false);
    final matches = api.currencies.where((c) => c.id == moneyId).toList();
    if (matches.isNotEmpty && matches.first.symbol.isNotEmpty) {
      return matches.first.symbol;
    }
    return moneyId == 2 ? 'ر.س' : (moneyId == 3 ? '\$' : 'د.أ');
  }

  String _getCurrencyName(int? moneyId) {
    if (moneyId == null || moneyId <= 0) return 'جميع العملات';
    final api = Provider.of<ApiService>(context, listen: false);
    final matches = api.currencies.where((c) => c.id == moneyId).toList();
    if (matches.isNotEmpty && matches.first.name.isNotEmpty) {
      return matches.first.name;
    }
    return moneyId == 2 ? 'ريال سعودي' : (moneyId == 3 ? 'دولار أمريكي' : 'دينار أردني');
  }

  String currencyFormat(double val, {int? moneyId, String? symbol}) {
    final sym = symbol ?? _getCurrencySymbol(moneyId ?? _selectedMoneyId);
    return '${val.toStringAsFixed(2)} $sym';
  }

  Widget _buildCurrencyBadge(int? moneyId, {String? symbol}) {
    final sym = symbol ?? _getCurrencySymbol(moneyId);
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

  void _printAccountStatement() {
    final apiService = Provider.of<ApiService>(context, listen: false);
    final logoBase64 = apiService.logoBase64;
    final startStr = _startDate != null ? DateFormat('yyyy/MM/dd').format(_startDate!) : 'الكل';
    final endStr = _endDate != null ? DateFormat('yyyy/MM/dd').format(_endDate!) : 'الكل';
    final curName = _selectedMoneyId != null && _selectedMoneyId! > 0 ? _getCurrencyName(_selectedMoneyId) : 'كافة العملات';

    final accName = _statementData['accountName'] ?? 'جميع الحسابات والمصاريف';
    final totalDebit = (_statementData['totalDebit'] as num? ?? 0.0).toDouble();
    final totalCredit = (_statementData['totalCredit'] as num? ?? 0.0).toDouble();
    final netBalance = (_statementData['balance'] as num? ?? 0.0).toDouble();
    final movements = (_statementData['movements'] as List?) ?? [];

    String rowsHtml = '';
    for (int i = 0; i < movements.length; i++) {
      final m = movements[i];
      final debitVal = (m['debit'] as num? ?? 0.0).toDouble();
      final creditVal = (m['credit'] as num? ?? 0.0).toDouble();
      final balVal = (m['balance'] as num? ?? 0.0).toDouble();
      final cSym = m['currencySymbol'] ?? 'د.أ';

      rowsHtml += '''
        <tr>
          <td style="text-align: center;">${i + 1}</td>
          <td style="text-align: center;">${m['date']}</td>
          <td style="text-align: center; font-weight: bold;">#${m['transNumber']}</td>
          <td>${m['accountName']}</td>
          <td style="text-align: center; font-weight: bold; color: #0284c7;">$cSym</td>
          <td style="text-align: center;">${m['type']}</td>
          <td>${m['description']}</td>
          <td style="text-align: left; color: #16a34a; font-weight: bold;">${debitVal > 0 ? currencyFormat(debitVal, symbol: cSym) : '-'}</td>
          <td style="text-align: left; color: #dc2626; font-weight: bold;">${creditVal > 0 ? currencyFormat(creditVal, symbol: cSym) : '-'}</td>
          <td style="text-align: left; font-weight: bold; background-color: #f8fafc;">${currencyFormat(balVal, symbol: cSym)}</td>
        </tr>
      ''';
    }

    String logoHtml = '';
    if (logoBase64.isNotEmpty) {
      logoHtml = '<div style="text-align: center; margin-bottom: 15px;"><img src="$logoBase64" style="max-height: 70px;" /></div>';
    }

    final htmlContent = '''
      <!DOCTYPE html>
      <html lang="ar" dir="rtl">
      <head>
        <meta charset="utf-8">
        <title>كشف حساب حركة المصاريف والحسابات - $accName</title>
        <style>
          body { font-family: 'Cairo', Tahoma, Arial; padding: 25px; color: #1e293b; direction: rtl; }
          .header { text-align: center; margin-bottom: 25px; border-bottom: 2px solid #0284c7; padding-bottom: 12px; }
          .header h1 { margin: 0; font-size: 22px; color: #0f172a; }
          .header p { margin: 4px 0 0 0; color: #64748b; font-size: 13px; }
          
          .account-box { display: flex; justify-content: space-between; background: #f8fafc; border: 1px solid #cbd5e1; padding: 14px; border-radius: 8px; margin-bottom: 20px; }
          .account-box .item { flex: 1; text-align: center; }
          .account-box .label { font-size: 12px; color: #64748b; font-weight: bold; }
          .account-box .val { font-size: 16px; font-weight: bold; margin-top: 4px; }
          
          table { width: 100%; border-collapse: collapse; margin-top: 15px; font-size: 13px; }
          th, td { border: 1px solid #cbd5e1; padding: 9px 12px; text-align: right; }
          th { background-color: #0f172a; color: white; font-weight: bold; }
          tr:nth-child(even) { background-color: #f8fafc; }
          
          .total-row { background-color: #e2e8f0; font-weight: bold; font-size: 14px; }
          .final-balance { background-color: #0284c7; color: white; font-weight: bold; font-size: 15px; }
          .final-balance td { color: white; }

          .footer-sig { margin-top: 40px; display: flex; justify-content: space-between; text-align: center; font-size: 13px; font-weight: bold; }
          .sig-box { width: 30%; border-top: 1px dashed #94a3b8; padding-top: 6px; }
        </style>
      </head>
      <body>
        $logoHtml
        <div class="header">
          <h1>كشف حساب حركة المصاريف والحسابات</h1>
          <p>اسم الحساب: <b>$accName</b> | العملة: <b>$curName</b> | الفترة: من <b>$startStr</b> إلى <b>$endStr</b></p>
          <p>نقطة البيع: ${apiService.pointName} (#${apiService.pointNo}) | تاريخ الاستخراج: ${DateFormat('yyyy/MM/dd HH:mm').format(DateTime.now())}</p>
        </div>

        <div class="account-box">
          <div class="account-item">
            <div class="label">إجمالي المدين (مصاريف/مدفوعات)</div>
            <div class="val" style="color: #16a34a;">${currencyFormat(totalDebit)}</div>
          </div>
          <div class="account-item">
            <div class="label">إجمالي الدائن (مقبوضات/إيداعات)</div>
            <div class="val" style="color: #dc2626;">${currencyFormat(totalCredit)}</div>
          </div>
          <div class="account-item">
            <div class="label">الرصيد المتبقي بالحساب</div>
            <div class="val" style="color: #0284c7;">${currencyFormat(netBalance)}</div>
          </div>
        </div>

        <table>
          <thead>
            <tr>
              <th style="text-align: center;">#</th>
              <th style="text-align: center;">التاريخ</th>
              <th style="text-align: center;">رقم المستند</th>
              <th>اسم الحساب</th>
              <th style="text-align: center;">العملة</th>
              <th style="text-align: center;">نوع العملية</th>
              <th>البيان والشارح التفصيلي</th>
              <th style="text-align: left;">مدين (+)</th>
              <th style="text-align: left;">دائن (-)</th>
              <th style="text-align: left;">الرصيد التراكمي</th>
            </tr>
          </thead>
          <tbody>
            $rowsHtml
          </tbody>
          <tfoot>
            <tr class="total-row">
              <td colspan="7" style="text-align: right; padding: 10px;">إجمالي الحركة المالية:</td>
              <td style="color: #16a34a; text-align: left;">${currencyFormat(totalDebit)}</td>
              <td style="color: #dc2626; text-align: left;">${currencyFormat(totalCredit)}</td>
              <td style="color: #0284c7; text-align: left;">${currencyFormat(netBalance)}</td>
            </tr>
            <tr class="final-balance">
              <td colspan="7" style="text-align: right; padding: 12px;">صافي رصيد الحساب المتبقي:</td>
              <td colspan="3" style="text-align: left; font-size: 16px;">${currencyFormat(netBalance)}</td>
            </tr>
          </tfoot>
        </table>

        <div class="footer-sig">
          <div class="sig-box">توقيع أخصائي الحسابات</div>
          <div class="sig-box">توقيع المحاسب المسئول</div>
          <div class="sig-box">اعتماد المدير العام</div>
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

    try {
      js.context.callMethod('eval', [
        '''
        (function() {
          var win = window.open("", "_blank");
          win.document.write(${json.encode(htmlContent)});
          win.document.close();
        })()
        '''
      ]);
    } catch (_) {}
  }

  Future<void> _selectDateRange(BuildContext context) async {
    final pickedRange = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2025),
      lastDate: DateTime(2030),
      initialDateRange: DateTimeRange(
        start: _startDate ?? DateTime.now(),
        end: _endDate ?? DateTime.now(),
      ),
      builder: (context, child) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: child!,
        );
      },
    );

    if (pickedRange != null) {
      setState(() {
        _startDate = pickedRange.start;
        _endDate = pickedRange.end;
      });
      _fetchStatementData();
    }
  }

  @override
  Widget build(BuildContext context) {
    final filteredAccounts = _accountsList.where((acc) {
      final name = (acc['name'] ?? '').toString().toLowerCase();
      final id = (acc['id'] ?? '').toString();
      final q = _accountSearchQuery.toLowerCase().trim();
      return name.contains(q) || id.contains(q);
    }).toList();

    final movements = (_statementData['movements'] as List?) ?? [];
    final totalDebit = (_statementData['totalDebit'] as num? ?? 0.0).toDouble();
    final totalCredit = (_statementData['totalCredit'] as num? ?? 0.0).toDouble();
    final netBalance = (_statementData['balance'] as num? ?? 0.0).toDouble();

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      body: Directionality(
        textDirection: TextDirection.rtl,
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'كشف حساب المصاريف والحسابات',
                        style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold, fontFamily: 'Cairo'),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'عرض وتدقيق تفاصيل حركة الحساب، المدين، الدائن، والرصيد التراكمي المتبقي',
                        style: TextStyle(color: Colors.white54, fontSize: 13, fontFamily: 'Cairo'),
                      ),
                    ],
                  ),

                  Row(
                    children: [
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.teal,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        icon: const Icon(Icons.print_rounded),
                        label: const Text('طباعة كشف الحساب المطبوع', style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
                        onPressed: _printAccountStatement,
                      ),
                      const SizedBox(width: 12),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF1E293B),
                          foregroundColor: Colors.white70,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          side: const BorderSide(color: Colors.white10),
                        ),
                        icon: const Icon(Icons.date_range, color: Colors.cyanAccent),
                        label: Text(
                          _startDate == null
                              ? 'اختر الفترة الزمنية'
                              : 'الفترة: ${DateFormat('yyyy/MM/dd').format(_startDate!)} - ${DateFormat('yyyy/MM/dd').format(_endDate!)}',
                          style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold),
                        ),
                        onPressed: () => _selectDateRange(context),
                      ),
                      const SizedBox(width: 12),

                      // Currency Filter Dropdown
                      Consumer<ApiService>(
                        builder: (context, api, _) {
                          final currencies = api.currencies;
                          return Container(
                            height: 48,
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1E293B),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.cyanAccent.withOpacity(0.4), width: 1.2),
                            ),
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<int?>(
                                value: _selectedMoneyId,
                                dropdownColor: const Color(0xFF1E293B),
                                icon: const Icon(Icons.currency_exchange, color: Colors.cyanAccent, size: 18),
                                hint: const Row(
                                  children: [
                                    Text('🌐 كافة العملات', style: TextStyle(color: Colors.white, fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 13)),
                                  ],
                                ),
                                style: const TextStyle(color: Colors.white, fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 13),
                                items: [
                                  const DropdownMenuItem<int?>(
                                    value: null,
                                    child: Text('🌐 كافة العملات (الكل)', style: TextStyle(color: Colors.cyanAccent, fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
                                  ),
                                  ...currencies.map((c) => DropdownMenuItem<int?>(
                                    value: c.id,
                                    child: Row(
                                      children: [
                                        Text('${c.name} (${c.symbol})', style: const TextStyle(fontFamily: 'Cairo')),
                                        if (c.id == api.defaultMoneyId)
                                          const Text(' ⭐', style: TextStyle(fontSize: 11)),
                                      ],
                                    ),
                                  )),
                                ],
                                onChanged: (val) {
                                  setState(() {
                                    _selectedMoneyId = val;
                                  });
                                  _fetchStatementData();
                                },
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Filter Controls Card (Search Account, Currency & Select Account)
              Card(
                color: const Color(0xFF1E293B),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    children: [
                      // Account Search & Selector
                      Expanded(
                        flex: 3,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('ابحث واختر اسم الحساب:', style: TextStyle(color: Colors.white70, fontSize: 12, fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
                            const SizedBox(height: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.05),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.white10),
                              ),
                              child: DropdownButtonHideUnderline(
                                child: DropdownButton<int?>(
                                  value: _selectedAccountId,
                                  isExpanded: true,
                                  dropdownColor: const Color(0xFF1E293B),
                                  hint: const Text('جميع الحسابات والمصاريف', style: TextStyle(color: Colors.white70, fontFamily: 'Cairo')),
                                  items: [
                                    const DropdownMenuItem<int?>(
                                      value: null,
                                      child: Text('جميع الحسابات والمصاريف (شامل)', style: TextStyle(color: Colors.cyanAccent, fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
                                    ),
                                    ...filteredAccounts.map((acc) {
                                      return DropdownMenuItem<int?>(
                                        value: acc['id'] as int?,
                                        child: Text(
                                          '#${acc['id']} - ${acc['name']}',
                                          style: const TextStyle(color: Colors.white, fontFamily: 'Cairo'),
                                        ),
                                      );
                                    }),
                                  ],
                                  onChanged: (val) {
                                    setState(() {
                                      _selectedAccountId = val;
                                    });
                                    _fetchStatementData();
                                  },
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 16),

                      // Currency Filter Dropdown in Filter Card
                      Expanded(
                        flex: 2,
                        child: Consumer<ApiService>(
                          builder: (context, api, _) {
                            final currencies = api.currencies;
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('تصفية حسب العملة:', style: TextStyle(color: Colors.white70, fontSize: 12, fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
                                const SizedBox(height: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withOpacity(0.05),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: Colors.white10),
                                  ),
                                  child: DropdownButtonHideUnderline(
                                    child: DropdownButton<int?>(
                                      value: _selectedMoneyId,
                                      isExpanded: true,
                                      dropdownColor: const Color(0xFF1E293B),
                                      hint: const Text('كافة العملات', style: TextStyle(color: Colors.white70, fontFamily: 'Cairo')),
                                      items: [
                                        const DropdownMenuItem<int?>(
                                          value: null,
                                          child: Text('🌐 كافة العملات', style: TextStyle(color: Colors.cyanAccent, fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
                                        ),
                                        ...currencies.map((c) => DropdownMenuItem<int?>(
                                          value: c.id,
                                          child: Text('${c.name} (${c.symbol})', style: const TextStyle(color: Colors.white, fontFamily: 'Cairo')),
                                        )),
                                      ],
                                      onChanged: (val) {
                                        setState(() {
                                          _selectedMoneyId = val;
                                        });
                                        _fetchStatementData();
                                      },
                                    ),
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                      ),
                      const SizedBox(width: 16),

                      // Real-time Text Search Input
                      Expanded(
                        flex: 2,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('تصفية قائمة الحسابات:', style: TextStyle(color: Colors.white70, fontSize: 12, fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
                            const SizedBox(height: 6),
                            TextField(
                              style: const TextStyle(color: Colors.white, fontFamily: 'Cairo'),
                              decoration: InputDecoration(
                                hintText: 'اكتب اسم أو رقم الحساب...',
                                hintStyle: const TextStyle(color: Colors.white30, fontSize: 13, fontFamily: 'Cairo'),
                                prefixIcon: const Icon(Icons.search, color: Colors.white54, size: 20),
                                filled: true,
                                fillColor: Colors.white.withOpacity(0.05),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Colors.white10)),
                                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Colors.white10)),
                              ),
                              onChanged: (q) {
                                setState(() {
                                  _accountSearchQuery = q;
                                });
                              },
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Account Balance Summary Cards (3 Cards)
              Row(
                children: [
                  _buildStatCard(
                    'إجمالي المدين (+)',
                    currencyFormat(totalDebit),
                    'المصاريف والمدفوعات',
                    Icons.trending_down_rounded,
                    Colors.greenAccent,
                  ),
                  const SizedBox(width: 12),
                  _buildStatCard(
                    'إجمالي الدائن (-)',
                    currencyFormat(totalCredit),
                    'المقبوضات والإيداعات',
                    Icons.trending_up_rounded,
                    Colors.redAccent,
                  ),
                  const SizedBox(width: 12),
                  _buildStatCard(
                    'الرصيد المتبقي بالحساب',
                    currencyFormat(netBalance),
                    'الصافي التراكمي الحقيقي',
                    Icons.account_balance_wallet_rounded,
                    Colors.cyanAccent,
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Ledger Transactions Table
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : movements.isEmpty
                        ? const Center(
                            child: Text(
                              'لا توجد حركات مسجلة بهذا الحساب للفترة المحددة.',
                              style: TextStyle(color: Colors.white30, fontSize: 16, fontFamily: 'Cairo'),
                            ),
                          )
                        : Card(
                            color: const Color(0xFF1E293B),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            child: Padding(
                              padding: const EdgeInsets.all(16.0),
                              child: Column(
                                children: [
                                  // Header Row
                                  Container(
                                    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withOpacity(0.04),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: const Row(
                                      children: [
                                        Expanded(flex: 1, child: Text('#', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontFamily: 'Cairo'))),
                                        Expanded(flex: 2, child: Text('التاريخ', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontFamily: 'Cairo'))),
                                        Expanded(flex: 2, child: Text('رقم المستند', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontFamily: 'Cairo'))),
                                        Expanded(flex: 3, child: Text('اسم الحساب', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontFamily: 'Cairo'))),
                                        Expanded(flex: 1, child: Text('العملة', style: TextStyle(color: Colors.cyanAccent, fontWeight: FontWeight.bold, fontFamily: 'Cairo'), textAlign: TextAlign.center)),
                                        Expanded(flex: 2, child: Text('نوع العملية', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontFamily: 'Cairo'))),
                                        Expanded(flex: 4, child: Text('البيان والشارح', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontFamily: 'Cairo'))),
                                        Expanded(flex: 2, child: Text('مدين (+)', style: TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold, fontFamily: 'Cairo'), textAlign: TextAlign.end)),
                                        Expanded(flex: 2, child: Text('دائن (-)', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, fontFamily: 'Cairo'), textAlign: TextAlign.end)),
                                        Expanded(flex: 2, child: Text('الرصيد التراكمي', style: TextStyle(color: Colors.cyanAccent, fontWeight: FontWeight.bold, fontFamily: 'Cairo'), textAlign: TextAlign.end)),
                                      ],
                                    ),
                                  ),
                                  const Divider(color: Colors.white10, height: 16),

                                  // List Rows
                                  Expanded(
                                    child: ListView.builder(
                                      itemCount: movements.length,
                                      itemBuilder: (context, index) {
                                        final m = movements[index];
                                        final debitVal = (m['debit'] as num? ?? 0.0).toDouble();
                                        final creditVal = (m['credit'] as num? ?? 0.0).toDouble();
                                        final balVal = (m['balance'] as num? ?? 0.0).toDouble();
                                        final isDebit = debitVal > 0;
                                        final cSym = m['currencySymbol'] ?? 'د.أ';

                                        return Padding(
                                          padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
                                          child: Row(
                                            children: [
                                              Expanded(flex: 1, child: Text('${index + 1}', style: const TextStyle(color: Colors.white38, fontSize: 12))),
                                              Expanded(flex: 2, child: Text('${m['date']}', style: const TextStyle(color: Colors.white70, fontSize: 13))),
                                              Expanded(flex: 2, child: Text('# ${m['transNumber']}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13))),
                                              Expanded(flex: 3, child: Text('${m['accountName']}', style: const TextStyle(color: Colors.amberAccent, fontFamily: 'Cairo', fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis)),
                                              Expanded(flex: 1, child: Center(child: _buildCurrencyBadge(m['moneyId'], symbol: cSym))),
                                              Expanded(
                                                flex: 2,
                                                child: Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                                  decoration: BoxDecoration(
                                                    color: isDebit ? Colors.green.withOpacity(0.15) : Colors.red.withOpacity(0.15),
                                                    borderRadius: BorderRadius.circular(4),
                                                  ),
                                                  child: Text(
                                                    '${m['type']}',
                                                    style: TextStyle(
                                                      color: isDebit ? Colors.greenAccent : Colors.redAccent,
                                                      fontSize: 11,
                                                      fontFamily: 'Cairo',
                                                      fontWeight: FontWeight.bold,
                                                    ),
                                                    textAlign: TextAlign.center,
                                                  ),
                                                ),
                                              ),
                                              Expanded(flex: 4, child: Text('${m['description']}', style: const TextStyle(color: Colors.white70, fontFamily: 'Cairo', fontSize: 13), maxLines: 1, overflow: TextOverflow.ellipsis)),
                                              Expanded(flex: 2, child: Text(debitVal > 0 ? currencyFormat(debitVal, symbol: cSym) : '-', textAlign: TextAlign.end, style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold))),
                                              Expanded(flex: 2, child: Text(creditVal > 0 ? currencyFormat(creditVal, symbol: cSym) : '-', textAlign: TextAlign.end, style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold))),
                                              Expanded(flex: 2, child: Text(currencyFormat(balVal, symbol: cSym), textAlign: TextAlign.end, style: const TextStyle(color: Colors.cyanAccent, fontWeight: FontWeight.bold, fontSize: 14))),
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
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatCard(String label, String value, String subtitle, IconData icon, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(14.0),
        decoration: BoxDecoration(
          color: const Color(0xFF1E293B),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withOpacity(0.06)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withOpacity(0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: const TextStyle(color: Colors.white60, fontSize: 12, fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text(
                    value,
                    style: TextStyle(color: color, fontSize: 18, fontWeight: FontWeight.bold, fontFamily: 'Cairo'),
                  ),
                  Text(subtitle, style: const TextStyle(color: Colors.white30, fontSize: 10, fontFamily: 'Cairo')),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
