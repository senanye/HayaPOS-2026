import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'dart:convert';
import 'package:universal_html/js.dart' as js;
import '../services/api_service.dart';
import 'whatsapp_provider_dialog.dart';

class ReportsView extends StatefulWidget {
  const ReportsView({super.key});

  @override
  State<ReportsView> createState() => _ReportsViewState();
}

class _ReportsViewState extends State<ReportsView> {
  DateTime? _startDate;
  DateTime? _endDate;

  int _activeReportType = 35; // 35 = Sales, 20 = Purchases, 36 = Returns, 10 = Receipts, 11 = Payments, 99 = Stock
  int _activeCategoryGroup = 0; // 0 = Sales, 1 = Purchases/Stock, 2 = Expenses/Bonds
  int? _selectedMoneyId; // null or 0 = All Currencies, > 0 = specific currency
  String _stockStatusFilter = 'all'; // all, available, zero, low
  int _zeroThreshold = 0;
  late TextEditingController _zeroThresholdController;
  List<dynamic> _auditLogs = [];

  Map<String, dynamic> _summary = {
    "cashSales": 0.0,
    "creditSales": 0.0,
    "totalSales": 0.0,
    "totalPurchases": 0.0,
    "totalReturns": 0.0,
    "openingStockValue": 0.0,
    "totalReceiptBonds": 0.0,
    "totalDisbursementBonds": 0.0,
    "cashInRegister": 0.0,
    "byCurrency": [],
  };

  Map<String, dynamic> _stockSummary = {
    "totalItems": 0,
    "totalAvailable": 0,
    "totalZero": 0,
    "totalLow": 0,
    "totalStockValue": 0.0,
    "byCurrency": [],
  };

  Map<String, dynamic> _cashMovementData = {
    "summary": {
      "cashSales": 0.0,
      "cashReceipts": 0.0,
      "cashReturns": 0.0,
      "cashPurchases": 0.0,
      "cashExpenses": 0.0,
      "totalCashIn": 0.0,
      "totalCashOut": 0.0,
      "remainingCash": 0.0,
    },
    "summaryByCurrency": {},
    "movements": []
  };

  Map<String, dynamic> _accountStatementData = {"summary": {}, "summaryByCurrency": {}, "movements": []};
  Map<String, dynamic> _itemMovementData = {"summary": {}, "movements": []};
  Map<String, dynamic> _dailyFinancialData = {
    "summary": {
      "totalSales": 0.0,
      "cashSales": 0.0,
      "creditSales": 0.0,
      "totalReturns": 0.0,
      "totalPurchases": 0.0,
      "totalExpenses": 0.0,
      "totalReceipts": 0.0,
      "netRemainingCash": 0.0,
      "totalDaysWithActivity": 0,
      "totalSalesCount": 0,
      "totalReturnsCount": 0,
      "totalPurchasesCount": 0,
      "totalExpensesCount": 0,
    },
    "dailyRecords": []
  };

  List<dynamic> _transactions = [];
  List<dynamic> _stockItems = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _zeroThresholdController = TextEditingController(text: '0');
    // Default period: start date = today, end date = today
    _startDate = DateTime.now();
    _endDate = DateTime.now();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final api = Provider.of<ApiService>(context, listen: false);
      api.loadCurrencies();
    });
    _fetchReportData();
  }

  @override
  void dispose() {
    _zeroThresholdController.dispose();
    super.dispose();
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

  Future<void> _fetchReportData() async {
    setState(() => _isLoading = true);
    final apiService = Provider.of<ApiService>(context, listen: false);

    final startStr = _startDate != null ? DateFormat('yyyy-MM-dd').format(_startDate!) : null;
    final endStr = _endDate != null ? DateFormat('yyyy-MM-dd').format(_endDate!) : null;

    try {
      final summaryData = await apiService.fetchReportsSummary(startStr, endStr, moneyId: _selectedMoneyId);
      _summary = summaryData;

      // Always fetch stock summary for the pie chart
      final stockData = await apiService.getInventoryStockReport(statusFilter: _stockStatusFilter, zeroThreshold: _zeroThreshold, moneyId: _selectedMoneyId);
      _stockSummary = stockData['summary'] ?? {};
      _stockItems = stockData['items'] ?? [];

      if (_activeReportType == 300) {
        final auditData = await apiService.fetchAuditLogReport(startDate: startStr, endDate: endStr);
        _auditLogs = auditData['logs'] ?? [];
      } else if (_activeReportType == 500) {
        final dailyData = await apiService.fetchDailyFinancialBreakdownReport(startStr, endStr, moneyId: _selectedMoneyId);
        _dailyFinancialData = dailyData;
      } else if (_activeReportType == 101) {
        final cashData = await apiService.fetchCashMovementReport(startStr, endStr, moneyId: _selectedMoneyId);
        _cashMovementData = cashData;
      } else if (_activeReportType == 102) {
        final accData = await apiService.fetchAccountStatement(start: startStr, end: endStr, moneyId: _selectedMoneyId);
        _accountStatementData = accData;
      } else if (_activeReportType == 400) {
        final itemData = await apiService.fetchItemMovementReport(query: '', startDate: startStr, endDate: endStr);
        _itemMovementData = itemData;
      } else if (_activeReportType != 99) {
        final transactionData = await apiService.fetchReportsTransactions(_activeReportType, startStr, endStr, moneyId: _selectedMoneyId);
        _transactions = transactionData;
      }

      setState(() {});
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('خطأ أثناء جلب التقارير: $e', style: const TextStyle(fontFamily: 'Cairo'))),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }


  void _printReport() {
    final printContent = _generateReportHtmlContent() + '''
      <script>
        window.onload = function() {
          window.print();
        };
      </script>
    ''';
    try {
      js.context.callMethod('eval', [
        '''
        (function() {
          var win = window.open("", "_blank");
          win.document.write(${json.encode(printContent)});
          win.document.close();
        })()
        '''
      ]);
    } catch (_) {}
  }

  void _printCashSummaryReport() {
    final apiService = Provider.of<ApiService>(context, listen: false);
    final logoBase64 = apiService.logoBase64;
    final startStr = _startDate != null ? DateFormat('yyyy/MM/dd').format(_startDate!) : 'الكل';
    final endStr = _endDate != null ? DateFormat('yyyy/MM/dd').format(_endDate!) : 'الكل';

    String logoHtml = '';
    if (logoBase64.isNotEmpty) {
      logoHtml = '<div style="text-align: center; margin-bottom: 20px;"><img src="$logoBase64" style="max-height: 80px; max-width: 250px;" /></div>';
    }

    final cashSales = (_summary['cashSales'] as num? ?? 0.0).toDouble();
    final creditSales = (_summary['creditSales'] as num? ?? 0.0).toDouble();
    final totalPurchases = (_summary['totalPurchases'] as num? ?? 0.0).toDouble();
    final totalReturns = (_summary['totalReturns'] as num? ?? 0.0).toDouble();
    final totalReceipts = (_summary['totalReceiptBonds'] as num? ?? 0.0).toDouble();
    final totalDisbursements = (_summary['totalDisbursementBonds'] as num? ?? 0.0).toDouble();
    final cashInRegister = (_summary['cashInRegister'] as num? ?? 0.0).toDouble();

    final htmlContent = '''
      <!DOCTYPE html>
      <html lang="ar" dir="rtl">
      <head>
        <meta charset="utf-8">
        <title>تقرير ملخص حركة الصندوق والسيولة</title>
        <style>
          body { font-family: 'Cairo', Tahoma, Arial; padding: 20px; color: #333; }
          .header { text-align: center; margin-bottom: 30px; border-bottom: 2px solid #333; padding-bottom: 10px; }
          .header h1 { margin: 0; font-size: 22px; }
          .header p { margin: 5px 0 0 0; color: #666; font-size: 14px; }
          table { width: 100%; border-collapse: collapse; margin-top: 15px; }
          th, td { border: 1px solid #ddd; padding: 12px; text-align: right; font-size: 14px; }
          th { background-color: #f5f5f5; font-weight: bold; }
          .inflow { color: green; font-weight: bold; }
          .outflow { color: red; font-weight: bold; }
          .balance-row { background-color: #e0f2f1; font-size: 16px; font-weight: bold; }
        </style>
      </head>
      <body>
        $logoHtml
        <div class="header">
          <h1>تقرير ملخص حركة الصندوق والسيولة</h1>
          <p>الفترة الزمنية: من $startStr إلى $endStr</p>
          <p>نقطة البيع: ${apiService.pointName} (رقم #${apiService.pointNo})</p>
        </div>
        <table>
          <thead>
            <tr>
              <th>البند المالي</th>
              <th>الحركة (د.أ)</th>
              <th>الأثر المالي على الصندوق</th>
            </tr>
          </thead>
          <tbody>
            <tr>
              <td>إجمالي المبيعات النقدية</td>
              <td class="inflow">+ ${currencyFormat(cashSales)}</td>
              <td>إيداع / زيادة سيولة</td>
            </tr>
            <tr>
              <td>إجمالي المبيعات الآجلة (لا تؤثر على الصندوق)</td>
              <td>${currencyFormat(creditSales)}</td>
              <td>حسابات عملاء ذمم</td>
            </tr>
            <tr>
              <td>سندات القبض (المقبوضات النقدية)</td>
              <td class="inflow">+ ${currencyFormat(totalReceipts)}</td>
              <td>إيداع / زيادة سيولة</td>
            </tr>
            <tr>
              <td>إجمالي المشتريات المحلية (كاش)</td>
              <td class="outflow">- ${currencyFormat(totalPurchases)}</td>
              <td>صرف / نقص سيولة</td>
            </tr>
            <tr>
              <td>سندات الصرف (المدفوعات النقدية)</td>
              <td class="outflow">- ${currencyFormat(totalDisbursements)}</td>
              <td>صرف / نقص سيولة</td>
            </tr>
            <tr>
              <td>مرتجع المبيعات (المبالغ المستردة للزبائن)</td>
              <td class="outflow">- ${currencyFormat(totalReturns)}</td>
              <td>صرف / نقص سيولة</td>
            </tr>
            <tr class="balance-row">
              <td>المبلغ المتبقي في الصندوق (الرصيد الفعلي)</td>
              <td colspan="2" style="text-align: left; font-size: 18px; color: #00796B;">${currencyFormat(cashInRegister)}</td>
            </tr>
          </tbody>
        </table>
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

  void _printExecutiveSummaryReport() {
    final apiService = Provider.of<ApiService>(context, listen: false);
    final logoBase64 = apiService.logoBase64;
    final startStr = _startDate != null ? DateFormat('yyyy/MM/dd').format(_startDate!) : 'اليوم';
    final endStr = _endDate != null ? DateFormat('yyyy/MM/dd').format(_endDate!) : 'اليوم';

    final cashSales = (_summary['cashSales'] as num? ?? 0.0).toDouble();
    final creditSales = (_summary['creditSales'] as num? ?? 0.0).toDouble();
    final totalSales = (_summary['totalSales'] as num? ?? 0.0).toDouble();
    final totalReturns = (_summary['totalReturns'] as num? ?? 0.0).toDouble();
    final totalPurchases = (_summary['totalPurchases'] as num? ?? 0.0).toDouble();
    final totalReceipts = (_summary['totalReceiptBonds'] as num? ?? 0.0).toDouble();
    final totalDisbursements = (_summary['totalDisbursementBonds'] as num? ?? 0.0).toDouble();
    final totalTransfersIn = (_summary['totalTransfersIn'] as num? ?? 0.0).toDouble();
    final totalTransfersOut = (_summary['totalTransfersOut'] as num? ?? 0.0).toDouble();
    final cashInRegister = (_summary['cashInRegister'] as num? ?? 0.0).toDouble();

    String logoHtml = '';
    if (logoBase64.isNotEmpty) {
      logoHtml = '<div style="text-align: center; margin-bottom: 15px;"><img src="$logoBase64" style="max-height: 70px;" /></div>';
    }

    final htmlContent = '''
      <!DOCTYPE html>
      <html lang="ar" dir="rtl">
      <head>
        <meta charset="utf-8">
        <title>التقرير الختامي اليومي الموجز الموحد</title>
        <style>
          body { font-family: 'Cairo', Tahoma, Arial; padding: 25px; color: #1e293b; direction: rtl; }
          .header { text-align: center; margin-bottom: 25px; border-bottom: 2px solid #0284c7; padding-bottom: 12px; }
          .header h1 { margin: 0; font-size: 22px; color: #0f172a; }
          .header p { margin: 4px 0 0 0; color: #64748b; font-size: 13px; }
          table { width: 100%; border-collapse: collapse; margin-top: 15px; }
          th, td { border: 1px solid #cbd5e1; padding: 10px 14px; text-align: right; font-size: 13px; }
          th { background-color: #0f172a; color: white; font-weight: bold; }
          tr:nth-child(even) { background-color: #f8fafc; }
          .section-title { font-weight: bold; background-color: #e2e8f0; font-size: 14px; color: #0f172a; }
          .inflow { color: #16a34a; font-weight: bold; }
          .outflow { color: #dc2626; font-weight: bold; }
          .final-row { background-color: #0284c7; color: white; font-size: 16px; font-weight: bold; }
          .final-row td { color: white; }
          .footer-sig { margin-top: 40px; display: flex; justify-content: space-between; text-align: center; font-size: 13px; font-weight: bold; }
          .sig-box { width: 30%; border-top: 1px dashed #94a3b8; padding-top: 6px; }
        </style>
      </head>
      <body>
        $logoHtml
        <div class="header">
          <h1>التقرير الختامي المالي والمخزني الموجز</h1>
          <p>الفترة: من $startStr إلى $endStr | التاريخ: ${DateFormat('yyyy/MM/dd HH:mm').format(DateTime.now())}</p>
          <p>نقطة البيع: ${apiService.pointName} (#${apiService.pointNo})</p>
        </div>
        <table>
          <thead>
            <tr>
              <th>البند والعملية</th>
              <th>القيمة الإجمالية</th>
              <th>التفاصيل والشارح الموجز</th>
            </tr>
          </thead>
          <tbody>
            <tr class="section-title">
              <td colspan="3">1. حركة المبيعات والمرتجعات</td>
            </tr>
            <tr>
              <td>إجمالي المبيعات النقدية</td>
              <td class="inflow">${currencyFormat(cashSales)}</td>
              <td>سيولة داخلة للصندوق</td>
            </tr>
            <tr>
              <td>إجمالي المبيعات الآجلة (ذمم)</td>
              <td>${currencyFormat(creditSales)}</td>
              <td>حسابات ذمم عملاء</td>
            </tr>
            <tr>
              <td>إجمالي المبيعات الكلية</td>
              <td style="font-weight: bold;">${currencyFormat(totalSales)}</td>
              <td>مجموع المبيعات النقدية والآجلة</td>
            </tr>
            <tr>
              <td>إجمالي مردودات المبيعات</td>
              <td class="outflow">${currencyFormat(totalReturns)}</td>
              <td>مبالغ مستردة للزبائن</td>
            </tr>

            <tr class="section-title">
              <td colspan="3">2. حركة المشتريات والتحويلات المخزنية</td>
            </tr>
            <tr>
              <td>إجمالي المشتريات المحلية</td>
              <td class="outflow">${currencyFormat(totalPurchases)}</td>
              <td>فواتير التوريد النقدية</td>
            </tr>
            <tr>
              <td>أوامر التوريد المخزني الواردة (#22)</td>
              <td class="inflow">${currencyFormat(totalTransfersIn)}</td>
              <td>أصناف واردة من الفروع</td>
            </tr>
            <tr>
              <td>أوامر الصرف والتحويل الصادرة (#23 / #28)</td>
              <td class="outflow">${currencyFormat(totalTransfersOut)}</td>
              <td>أصناف منصرفة للفروع</td>
            </tr>

            <tr class="section-title">
              <td colspan="3">3. حركة السندات والسيولة النقدية</td>
            </tr>
            <tr>
              <td>سندات القبض النقدية</td>
              <td class="inflow">${currencyFormat(totalReceipts)}</td>
              <td>إيداعات نقدية للصندوق</td>
            </tr>
            <tr>
              <td>سندات الصرف والمصاريف</td>
              <td class="outflow">${currencyFormat(totalDisbursements)}</td>
              <td>مصروفات ومدفوعات نقدية</td>
            </tr>

            <tr class="final-row">
              <td>الصافي النهائي لرصيد الصندوق (السيولة)</td>
              <td colspan="2" style="text-align: left;">${currencyFormat(cashInRegister)}</td>
            </tr>
          </tbody>
        </table>

        <div class="footer-sig">
          <div class="sig-box">أمين الصندوق / الكاشير</div>
          <div class="sig-box">المحاسب المسئول</div>
          <div class="sig-box">اعتماد المدير</div>
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

  Widget _buildExecutiveBriefSummaryCard() {
    final cashSales = (_summary['cashSales'] as num? ?? 0.0).toDouble();
    final creditSales = (_summary['creditSales'] as num? ?? 0.0).toDouble();
    final totalSales = (_summary['totalSales'] as num? ?? 0.0).toDouble();
    final totalReturns = (_summary['totalReturns'] as num? ?? 0.0).toDouble();
    final totalPurchases = (_summary['totalPurchases'] as num? ?? 0.0).toDouble();
    final totalReceipts = (_summary['totalReceiptBonds'] as num? ?? 0.0).toDouble();
    final totalDisbursements = (_summary['totalDisbursementBonds'] as num? ?? 0.0).toDouble();
    final totalTransfersIn = (_summary['totalTransfersIn'] as num? ?? 0.0).toDouble();
    final totalTransfersOut = (_summary['totalTransfersOut'] as num? ?? 0.0).toDouble();
    final cashInRegister = (_summary['cashInRegister'] as num? ?? 0.0).toDouble();

    return Card(
      color: const Color(0xFF1E293B),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Row(
                  children: [
                    Icon(Icons.assessment_rounded, color: Colors.cyanAccent, size: 24),
                    SizedBox(width: 10),
                    Text(
                      'التقرير الختامي اليومي الموجز الموحد لكل العمليات',
                      style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold, fontFamily: 'Cairo'),
                    ),
                  ],
                ),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.teal,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  ),
                  icon: const Icon(Icons.print_rounded, size: 18),
                  label: const Text('طباعة التقرير الختامي الموجز', style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
                  onPressed: _printExecutiveSummaryReport,
                ),
              ],
            ),
            const Divider(color: Colors.white10, height: 24),
            _buildBriefRow('1. إجمالي المبيعات النقدية (+)', currencyFormat(cashSales), Colors.greenAccent),
            _buildBriefRow('2. إجمالي المبيعات الآجلة (ذمم)', currencyFormat(creditSales), Colors.blueAccent),
            _buildBriefRow('3. إجمالي المبيعات الكلية', currencyFormat(totalSales), Colors.white),
            _buildBriefRow('4. مردودات المبيعات (-)', currencyFormat(totalReturns), Colors.redAccent),
            const Divider(color: Colors.white10, height: 20),
            _buildBriefRow('5. إجمالي المشتريات المحلية (-)', currencyFormat(totalPurchases), Colors.amberAccent),
            _buildBriefRow('6. التحويلات المخزنية الواردة (+)', currencyFormat(totalTransfersIn), Colors.purpleAccent),
            _buildBriefRow('7. التحويلات المخزنية الصادرة (-)', currencyFormat(totalTransfersOut), Colors.orangeAccent),
            const Divider(color: Colors.white10, height: 20),
            _buildBriefRow('8. سندات القبض والإيداعات (+)', currencyFormat(totalReceipts), Colors.tealAccent),
            _buildBriefRow('9. سندات الصرف والمصاريف (-)', currencyFormat(totalDisbursements), Colors.orangeAccent),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.tealAccent.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.tealAccent.withOpacity(0.3)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'الصافي النهائي لرصيد السيولة بالصندوق:',
                    style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold, fontFamily: 'Cairo'),
                  ),
                  Text(
                    currencyFormat(cashInRegister),
                    style: const TextStyle(color: Colors.tealAccent, fontSize: 20, fontWeight: FontWeight.bold, fontFamily: 'Cairo'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBriefRow(String label, String value, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.white70, fontSize: 14, fontFamily: 'Cairo')),
          Text(value, style: TextStyle(color: color, fontSize: 15, fontWeight: FontWeight.bold, fontFamily: 'Cairo')),
        ],
      ),
    );
  }

  Widget _buildCurrencyBadge(int? moneyId, {String? symbol, String? name}) {
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

  Widget _buildCurrencyBreakdownBar() {
    final byCurList = (_summary['byCurrency'] as List?) ?? [];
    if (byCurList.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.cyanAccent.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          const Icon(Icons.currency_exchange_rounded, color: Colors.cyanAccent, size: 20),
          const SizedBox(width: 8),
          const Text(
            'توزيع السيولة والعملات:',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontFamily: 'Cairo', fontSize: 12),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  // All currencies chip
                  InkWell(
                    onTap: () {
                      setState(() => _selectedMoneyId = null);
                      _fetchReportData();
                    },
                    child: Container(
                      margin: const EdgeInsets.only(left: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: _selectedMoneyId == null ? Colors.cyanAccent.withOpacity(0.25) : Colors.white.withOpacity(0.05),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: _selectedMoneyId == null ? Colors.cyanAccent : Colors.white10),
                      ),
                      child: Text(
                        '🌐 كافة العملات (${byCurList.length})',
                        style: TextStyle(
                          color: _selectedMoneyId == null ? Colors.cyanAccent : Colors.white70,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'Cairo',
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ),
                  ...byCurList.map((cur) {
                    final mid = cur['moneyId'] ?? 1;
                    final sym = cur['currencySymbol'] ?? 'د.أ';
                    final name = cur['currencyName'] ?? '';
                    final tSales = (cur['totalSales'] as num? ?? 0.0).toDouble();
                    final netCash = (cur['cashInRegister'] as num? ?? 0.0).toDouble();
                    final isSelected = _selectedMoneyId == mid;

                    return InkWell(
                      onTap: () {
                        setState(() => _selectedMoneyId = isSelected ? null : mid);
                        _fetchReportData();
                      },
                      child: Container(
                        margin: const EdgeInsets.only(left: 8),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: isSelected ? Colors.blueAccent.withOpacity(0.25) : Colors.white.withOpacity(0.04),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: isSelected ? Colors.blueAccent : Colors.white12),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('$name ($sym): ', style: TextStyle(color: isSelected ? Colors.white : Colors.white70, fontWeight: FontWeight.bold, fontFamily: 'Cairo', fontSize: 11)),
                            Text('مبيعات ${tSales.toStringAsFixed(2)} $sym', style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold, fontSize: 11)),
                            const Text(' | ', style: TextStyle(color: Colors.white24)),
                            Text('صندوق ${netCash.toStringAsFixed(2)} $sym', style: const TextStyle(color: Colors.tealAccent, fontWeight: FontWeight.bold, fontSize: 11)),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
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
      _fetchReportData();
    }
  }

  String _getReportTypeName(int type) {
    switch (type) {
      case 35: return 'تقرير تقييم وحركة المبيعات التفصيلي';
      case 20: return 'تقرير المشتريات المحلية التفصيلي';
      case 36: return 'تقرير مرتجع المبيعات التفصيلي';
      case 10: return 'تقرير حركة سندات القبض والمقبوضات';
      case 11: return 'تقرير حركة سندات الصرف والمصاريف';
      case 100: return 'تقرير حركة سندات الصرف والقبض الشامل';
      case 1: return 'تقرير جرد أول المدة التفصيلي';
      case 22: return 'تقرير أوامر التوريد المخزني التفصيلي';
      case 23: return 'تقرير أوامر الصرف المخزني التفصيلي';
      case 28: return 'تقرير حركات التحويل المخزني بين الفروع';
      case 99: return 'تقرير المخزون والجرد المالي للكميات';
      case 101: return 'كشف حركة ومتبقي الصندوق النقدي';
      case 102: return 'كشف حساب المصاريف والحسابات التفصيلي';
      case 200: return 'التقرير الختامي الشامل وملخص السيولة والصندوق';
      case 300: return 'تقرير حركات التدقيق والرقابة المالية والنظام';
      case 400: return 'تقرير تقييم وحركة صنف محدد تفصيلي';
      case 500: return 'تقرير الإحصائية والحركة المالية اليومية المجمعة (كشف الصندوق اليومي)';
      default: return 'التقرير المالي والتدقيق';
    }
  }

  String _generateReportHtmlContent() {
    final apiService = Provider.of<ApiService>(context, listen: false);
    final logoBase64 = apiService.logoBase64;
    final reportTitle = _getReportTypeName(_activeReportType);
    final startStr = _startDate != null ? DateFormat('yyyy/MM/dd').format(_startDate!) : 'الكل';
    final endStr = _endDate != null ? DateFormat('yyyy/MM/dd').format(_endDate!) : 'الكل';
    final curName = _selectedMoneyId != null && _selectedMoneyId! > 0 ? _getCurrencyName(_selectedMoneyId) : 'كافة العملات';

    String logoHtml = '';
    if (logoBase64.isNotEmpty) {
      logoHtml = '<div style="text-align: center; margin-bottom: 15px;"><img src="$logoBase64" style="max-height: 70px; max-width: 240px;" /></div>';
    }

    String pointInfoHtml = '<div style="text-align: center; margin-bottom: 12px; font-size: 15px; font-weight: bold; color: #0284c7;">'
        'اسم نقطة البيع: ${apiService.pointName} (رقم #${apiService.pointNo}) | العملة: $curName'
        '</div>';

    String tableHeadersHtml = '';
    String rowsHtml = '';
    String summaryTotalHtml = '';

    if (_activeReportType == 500) {
      tableHeadersHtml = '''
        <tr>
          <th style="text-align: center;">التاريخ</th>
          <th style="text-align: left;">إجمالي المبيعات (+)</th>
          <th style="text-align: left;">المردودات (-)</th>
          <th style="text-align: left;">المشتريات (-)</th>
          <th style="text-align: left;">المصروفات والسندات (-)</th>
          <th style="text-align: left;">الصافي المتبقي بالصندوق (=)</th>
          <th style="text-align: center;">عدد العمليات</th>
        </tr>
      ''';
      final records = (_dailyFinancialData['dailyRecords'] as List?) ?? [];
      for (final r in records) {
        final dt = r['date'] ?? '';
        final sales = (r['sales'] as num? ?? 0.0).toDouble();
        final returns = (r['returns'] as num? ?? 0.0).toDouble();
        final purchases = (r['purchases'] as num? ?? 0.0).toDouble();
        final expenses = (r['expenses'] as num? ?? 0.0).toDouble();
        final net = (r['netRemainingCash'] as num? ?? 0.0).toDouble();
        final count = (r['salesCount'] as num? ?? 0).toInt() +
            (r['returnsCount'] as num? ?? 0).toInt() +
            (r['purchasesCount'] as num? ?? 0).toInt() +
            (r['expensesCount'] as num? ?? 0).toInt();

        rowsHtml += '''
          <tr>
            <td style="text-align: center; font-weight: bold;">$dt</td>
            <td style="text-align: left; color: #16a34a; font-weight: bold;">+ ${currencyFormat(sales)}</td>
            <td style="text-align: left; color: #d97706;">- ${currencyFormat(returns)}</td>
            <td style="text-align: left; color: #dc2626;">- ${currencyFormat(purchases)}</td>
            <td style="text-align: left; color: #9333ea;">- ${currencyFormat(expenses)}</td>
            <td style="text-align: left; font-weight: bold; color: ${net >= 0 ? '#0284c7' : '#dc2626'};">${currencyFormat(net)}</td>
            <td style="text-align: center;">$count</td>
          </tr>
        ''';
      }
      final sum = _dailyFinancialData['summary'] ?? {};
      final totNet = (sum['netRemainingCash'] as num? ?? 0.0).toDouble();
      final totSales = (sum['totalSales'] as num? ?? 0.0).toDouble();
      final totExp = (sum['totalExpenses'] as num? ?? 0.0).toDouble();
      final totPur = (sum['totalPurchases'] as num? ?? 0.0).toDouble();
      final totRet = (sum['totalReturns'] as num? ?? 0.0).toDouble();
      summaryTotalHtml = 'صافي رصيد الصندوق للفترة: ${currencyFormat(totNet)} (المبيعات: ${currencyFormat(totSales)} | المشتريات: ${currencyFormat(totPur)} | المردودات: ${currencyFormat(totRet)} | المصروفات: ${currencyFormat(totExp)})';
    } else if (_activeReportType == 200) {
      final cashSales = (_summary['cashSales'] as num? ?? 0.0).toDouble();
      final creditSales = (_summary['creditSales'] as num? ?? 0.0).toDouble();
      final totalPurchases = (_summary['totalPurchases'] as num? ?? 0.0).toDouble();
      final totalReturns = (_summary['totalReturns'] as num? ?? 0.0).toDouble();
      final totalReceipts = (_summary['totalReceiptBonds'] as num? ?? 0.0).toDouble();
      final totalDisbursements = (_summary['totalDisbursementBonds'] as num? ?? 0.0).toDouble();
      final cashInRegister = (_summary['cashInRegister'] as num? ?? 0.0).toDouble();

      tableHeadersHtml = '''
        <tr>
          <th>البند المالي والرئيسي</th>
          <th>القيمة والسيولة النقدية</th>
          <th>العملة</th>
          <th>الأثر المالي والتصنيف</th>
        </tr>
      ''';
      rowsHtml = '''
        <tr>
          <td>إجمالي المبيعات النقدية</td>
          <td style="color: #16a34a; font-weight: bold;">+ ${currencyFormat(cashSales)}</td>
          <td style="text-align: center;">$curName</td>
          <td>إيداع / زيادة سيولة</td>
        </tr>
        <tr>
          <td>إجمالي المبيعات الآجلة (لا تؤثر على الصندوق)</td>
          <td>${currencyFormat(creditSales)}</td>
          <td style="text-align: center;">$curName</td>
          <td>حسابات عملاء ذمم</td>
        </tr>
        <tr>
          <td>سندات القبض (المقبوضات النقدية)</td>
          <td style="color: #16a34a; font-weight: bold;">+ ${currencyFormat(totalReceipts)}</td>
          <td style="text-align: center;">$curName</td>
          <td>إيداع / زيادة سيولة</td>
        </tr>
        <tr>
          <td>إجمالي المشتريات المحلية (كاش)</td>
          <td style="color: #dc2626; font-weight: bold;">- ${currencyFormat(totalPurchases)}</td>
          <td style="text-align: center;">$curName</td>
          <td>صرف / نقص سيولة</td>
        </tr>
        <tr>
          <td>سندات الصرف (المدفوعات النقدية)</td>
          <td style="color: #dc2626; font-weight: bold;">- ${currencyFormat(totalDisbursements)}</td>
          <td style="text-align: center;">$curName</td>
          <td>صرف / نقص سيولة</td>
        </tr>
        <tr>
          <td>مرتجع المبيعات (المبالغ المستردة للزبائن)</td>
          <td style="color: #dc2626; font-weight: bold;">- ${currencyFormat(totalReturns)}</td>
          <td style="text-align: center;">$curName</td>
          <td>صرف / نقص سيولة</td>
        </tr>
      ''';
      summaryTotalHtml = 'المبلغ المتبقي في الصندوق (الرصيد الفعلي الحالي): ${currencyFormat(cashInRegister)}';
    } else if (_activeReportType == 102) {
      tableHeadersHtml = '''
        <tr>
          <th>#</th>
          <th>رقم المستند</th>
          <th>التاريخ</th>
          <th>اسم الحساب / البند</th>
          <th>العملة</th>
          <th>مدين (له)</th>
          <th>دائن (عليه)</th>
          <th>الرصيد التراكمي</th>
          <th>البيان والملاحظة</th>
        </tr>
      ''';
      final movements = (_accountStatementData['movements'] as List?) ?? [];
      for (final m in movements) {
        final debit = (m['debit'] as num? ?? 0.0).toDouble();
        final credit = (m['credit'] as num? ?? 0.0).toDouble();
        final balance = (m['balance'] as num? ?? 0.0).toDouble();
        final cSym = m['currencySymbol'] ?? 'د.أ';
        rowsHtml += '''
          <tr>
            <td style="text-align: center;">${m['id']}</td>
            <td style="text-align: center;">#${m['transNumber']}</td>
            <td style="text-align: center;">${m['date']}</td>
            <td style="font-weight: bold;">${m['accountName']}</td>
            <td style="text-align: center; font-weight: bold; color: #0284c7;">$cSym</td>
            <td style="text-align: left; color: #16a34a; font-weight: bold;">${debit > 0 ? currencyFormat(debit, symbol: cSym) : '-'}</td>
            <td style="text-align: left; color: #dc2626; font-weight: bold;">${credit > 0 ? currencyFormat(credit, symbol: cSym) : '-'}</td>
            <td style="text-align: left; font-weight: bold;">${currencyFormat(balance, symbol: cSym)}</td>
            <td>${m['note'] ?? ''}</td>
          </tr>
        ''';
      }
      final summary = _accountStatementData['summary'] ?? {};
      final finalBal = (summary['finalBalance'] as num? ?? 0.0).toDouble();
      summaryTotalHtml = 'الرصيد النهائي للحساب: ${currencyFormat(finalBal)}';
    } else if (_activeReportType == 400) {
      tableHeadersHtml = '''
        <tr>
          <th>#</th>
          <th>التاريخ</th>
          <th>نوع الحركة</th>
          <th>رقم المستند</th>
          <th>الوحدة</th>
          <th>سعر البيع</th>
          <th>كمية وارد (+)</th>
          <th>كمية منصرف (-)</th>
          <th>الرصيد المتبقي</th>
          <th>إجمالي القيمة</th>
        </tr>
      ''';
      final movements = (_itemMovementData['movements'] as List?) ?? [];
      for (final m in movements) {
        final qtyIn = (m['qtyIn'] as num? ?? 0).toInt();
        final qtyOut = (m['qtyOut'] as num? ?? 0).toInt();
        final balance = (m['balance'] as num? ?? 0).toInt();
        final price = (m['salesPrice'] as num? ?? 0.0).toDouble();
        final totalVal = (m['totalValue'] as num? ?? 0.0).toDouble();

        rowsHtml += '''
          <tr>
            <td style="text-align: center;">${m['id']}</td>
            <td style="text-align: center;">${m['date']}</td>
            <td style="font-weight: bold; color: #0284c7;">${m['type']}</td>
            <td style="text-align: center;">#${m['transNumber']}</td>
            <td>${m['unitName'] ?? 'حبة'}</td>
            <td style="text-align: left;">${currencyFormat(price)}</td>
            <td style="text-align: center; color: #16a34a; font-weight: bold;">${qtyIn > 0 ? qtyIn : '-'}</td>
            <td style="text-align: center; color: #dc2626; font-weight: bold;">${qtyOut > 0 ? qtyOut : '-'}</td>
            <td style="text-align: center; font-weight: bold;">$balance</td>
            <td style="text-align: left; font-weight: bold;">${currencyFormat(totalVal)}</td>
          </tr>
        ''';
      }
      final itemSummary = _itemMovementData['summary'] ?? {};
      final finalQty = (itemSummary['finalStock'] as num? ?? 0).toInt();
      final itemName = itemSummary['itemName'] ?? 'الصنف';
      summaryTotalHtml = 'الرصيد الحالي لصنف ($itemName): $finalQty حبة';
    } else if (_activeReportType == 300) {
      tableHeadersHtml = '''
        <tr>
          <th>#</th>
          <th>التاريخ والوقت</th>
          <th>المستخدم</th>
          <th>نوع الحركة والحدث</th>
          <th>بيان ووصف الحركة</th>
          <th>التفاصيل الإضافية</th>
        </tr>
      ''';
      for (final log in _auditLogs) {
        rowsHtml += '''
          <tr>
            <td style="text-align: center;">${log['id']}</td>
            <td style="text-align: center;">${log['date']}</td>
            <td>${log['userName'] ?? 'مستخدم'}</td>
            <td style="font-weight: bold; color: #0284c7; text-align: center;">${log['actionType']}</td>
            <td>${log['description'] ?? ''}</td>
            <td>${log['details'] ?? ''}</td>
          </tr>
        ''';
      }
      summaryTotalHtml = 'إجمالي الحركات المسجلة في سجل التدقيق: ${_auditLogs.length} حركة';
    } else if (_activeReportType == 99) {
      tableHeadersHtml = '''
        <tr>
          <th>الباركود</th>
          <th>اسم الصنف</th>
          <th>الوحدة</th>
          <th>العملة</th>
          <th>سعر التكلفة</th>
          <th>سعر البيع</th>
          <th>الكمية الحقيقية</th>
          <th>قيمة التكلفة</th>
          <th>قيمة البيع</th>
          <th>حالة المخزون</th>
        </tr>
      ''';
      for (final item in _stockItems) {
        final st = item['status'];
        final stLabel = st == 'available' ? 'متوفر' : (st == 'zero' ? 'صفر' : 'ناقص/سالب');
        final stColor = st == 'available' ? 'green' : (st == 'zero' ? 'orange' : 'red');
        final cSym = item['currencySymbol'] ?? 'د.أ';
        final costP = (item['costPrice'] as num? ?? 0.0).toDouble();
        final salesP = (item['salesPrice'] as num? ?? 0.0).toDouble();
        final salesV = (item['salesValue'] as num? ?? (item['stockValue'] as num? ?? 0.0)).toDouble();
        final costV = (item['costValue'] as num? ?? 0.0).toDouble();

        rowsHtml += '''
          <tr>
            <td>${item['barcode']}</td>
            <td>${item['itemName']}</td>
            <td>${item['unitName']}</td>
            <td style="text-align: center; font-weight: bold; color: #0284c7;">$cSym</td>
            <td>${currencyFormat(costP, symbol: cSym)}</td>
            <td>${currencyFormat(salesP, symbol: cSym)}</td>
            <td style="font-weight: bold; color: $stColor; text-align: center;">${item['quantity'] ?? item['currentQuantity']}</td>
            <td style="text-align: left;">${currencyFormat(costV, symbol: cSym)}</td>
            <td style="text-align: left; font-weight: bold;">${currencyFormat(salesV, symbol: cSym)}</td>
            <td style="color: $stColor; font-weight: bold; text-align: center;">$stLabel</td>
          </tr>
        ''';
      }
      final totalStockVal = (_stockSummary['totalStockValue'] as num? ?? 0.0).toDouble();
      summaryTotalHtml = 'إجمالي قيمة المخزون الحالي: ${currencyFormat(totalStockVal)}';
    } else if (_activeReportType == 101) {
      final cashSummary = _cashMovementData['summary'] ?? {};
      final movementsList = (_cashMovementData['movements'] as List?) ?? [];
      final remaining = (cashSummary['remainingCash'] as num? ?? 0.0).toDouble();

      tableHeadersHtml = '''
        <tr>
          <th>التاريخ</th>
          <th>نوع الحركة</th>
          <th>العملة</th>
          <th>رقم المستند</th>
          <th>البيان والشارح التفصيلي</th>
          <th>المقبوضات (+)</th>
          <th>المدفوعات (-)</th>
          <th>الرصيد التراكمي المتبقي</th>
        </tr>
      ''';
      for (final m in movementsList) {
        final cashInVal = (m['cashIn'] as num? ?? 0.0).toDouble();
        final cashOutVal = (m['cashOut'] as num? ?? 0.0).toDouble();
        final balanceVal = (m['balance'] as num? ?? 0.0).toDouble();
        final cSym = m['currencySymbol'] ?? 'د.أ';
        rowsHtml += '''
          <tr>
            <td style="text-align: center;">${m['date']}</td>
            <td style="text-align: center; font-weight: bold;">${m['type']}</td>
            <td style="text-align: center; font-weight: bold; color: #0284c7;">$cSym</td>
            <td style="text-align: center;">#${m['refNo']}</td>
            <td>${m['description']}</td>
            <td style="text-align: left; color: #16a34a; font-weight: bold;">${cashInVal > 0 ? currencyFormat(cashInVal, symbol: cSym) : '-'}</td>
            <td style="text-align: left; color: #dc2626; font-weight: bold;">${cashOutVal > 0 ? currencyFormat(cashOutVal, symbol: cSym) : '-'}</td>
            <td style="text-align: left; font-weight: bold;">${currencyFormat(balanceVal, symbol: cSym)}</td>
          </tr>
        ''';
      }
      summaryTotalHtml = 'المتبقي النقدي في الصندوق: ${currencyFormat(remaining)}';
    } else {
      final isBondReport = _activeReportType == 10 || _activeReportType == 11 || _activeReportType == 100;
      if (isBondReport) {
        tableHeadersHtml = '''
          <tr>
            <th>رقم السند</th>
            <th>التاريخ</th>
            <th>اسم الحساب / البند</th>
            <th>العملة</th>
            <th>بيان السند</th>
            <th>نوع السند</th>
            <th>المبلغ</th>
          </tr>
        ''';
        for (final tx in _transactions) {
          final bType = tx['bondType'] ?? (_activeReportType == 10 ? 'سند قبض' : 'سند صرف');
          final acc = tx['accountName'] ?? 'حساب عام';
          final cSym = tx['currencySymbol'] ?? 'د.أ';
          rowsHtml += '''
            <tr>
              <td>#${tx['transNumber']}</td>
              <td>${tx['date']}</td>
              <td>$acc</td>
              <td style="text-align: center; font-weight: bold; color: #0284c7;">$cSym</td>
              <td>${tx['description'] ?? ''}</td>
              <td>$bType</td>
              <td style="text-align: left; font-weight: bold;">${currencyFormat((tx['amount'] as num).toDouble(), symbol: cSym)}</td>
            </tr>
          ''';
        }
      } else {
        tableHeadersHtml = '''
          <tr>
            <th>#</th>
            <th>رقم الفاتورة</th>
            <th>التاريخ</th>
            <th>الباركود</th>
            <th>اسم الصنف</th>
            <th>العملة</th>
            <th style="text-align: center;">الكمية</th>
            <th style="text-align: left;">السعر</th>
            <th style="text-align: left;">الإجمالي</th>
            <th>البائع/المستخدم</th>
            <th style="text-align: center;">طريقة الدفع</th>
          </tr>
        ''';
        int idx = 1;
        for (final tx in _transactions) {
          final barcode = tx['barcode'] ?? '';
          final itemName = tx['itemName'] ?? (tx['description'] ?? 'صنف');
          final qty = tx['quantity'] ?? 0;
          final cSym = tx['currencySymbol'] ?? 'د.أ';
          final price = (tx['salesPrice'] as num? ?? 0.0).toDouble();
          final amount = (tx['amount'] as num? ?? 0.0).toDouble();
          final isCash = tx['payCash'] == 1;
          final typeText = isCash ? 'نقدي' : 'آجل';
          final userStr = tx['userName'] ?? 'مستخدم';
          rowsHtml += '''
            <tr>
              <td>${idx++}</td>
              <td>#${tx['transNumber']}</td>
              <td>${tx['date']}</td>
              <td>${barcode.isNotEmpty ? barcode : '-'}</td>
              <td>$itemName</td>
              <td style="text-align: center; font-weight: bold; color: #0284c7;">$cSym</td>
              <td style="text-align: center; font-weight: bold;">$qty</td>
              <td style="text-align: left;">${currencyFormat(price, symbol: cSym)}</td>
              <td style="text-align: left; font-weight: bold; color: green;">${currencyFormat(amount, symbol: cSym)}</td>
              <td>$userStr</td>
              <td style="text-align: center;">$typeText</td>
            </tr>
          ''';
        }
      }

      final totalSum = _transactions.fold(0.0, (sum, tx) => sum + ((tx['amount'] as num?) ?? 0.0).toDouble());
      summaryTotalHtml = 'الإجمالي الكلي للتقرير: ${currencyFormat(totalSum)}';
    }

    // Currency Breakdown HTML Table
    String currencyBreakdownHtml = '';
    final byCurList = (_summary['byCurrency'] as List?) ?? [];
    if (byCurList.isNotEmpty) {
      String curRows = '';
      for (final c in byCurList) {
        final cSym = c['currencySymbol'] ?? 'د.أ';
        final cName = c['currencyName'] ?? '';
        final sVal = (c['totalSales'] as num? ?? 0.0).toDouble();
        final pVal = (c['totalPurchases'] as num? ?? 0.0).toDouble();
        final rVal = (c['totalReturns'] as num? ?? 0.0).toDouble();
        final netCash = (c['cashInRegister'] as num? ?? 0.0).toDouble();
        curRows += '''
          <tr>
            <td style="font-weight: bold;">$cName ($cSym)</td>
            <td style="text-align: left; color: #16a34a; font-weight: bold;">${sVal.toStringAsFixed(2)} $cSym</td>
            <td style="text-align: left; color: #dc2626;">${pVal.toStringAsFixed(2)} $cSym</td>
            <td style="text-align: left; color: #d97706;">${rVal.toStringAsFixed(2)} $cSym</td>
            <td style="text-align: left; font-weight: bold; color: #0284c7;">${netCash.toStringAsFixed(2)} $cSym</td>
          </tr>
        ''';
      }

      currencyBreakdownHtml = '''
        <div style="margin-top: 20px;">
          <h3 style="font-size: 14px; margin-bottom: 6px; color: #0f172a;">ملخص الحركة المالية بحسب العملات:</h3>
          <table style="width: 100%; font-size: 11px;">
            <thead>
              <tr style="background: #e2e8f0; color: #0f172a;">
                <th>العملة</th>
                <th>إجمالي المبيعات</th>
                <th>إجمالي المشتريات</th>
                <th>إجمالي المرتجعات</th>
                <th>صافي السيولة النقدية</th>
              </tr>
            </thead>
            <tbody>
              $curRows
            </tbody>
          </table>
        </div>
      ''';
    }

    return '''
      <!DOCTYPE html>
      <html lang="ar" dir="rtl">
      <head>
        <meta charset="utf-8">
        <title>$reportTitle</title>
        <style>
          body { font-family: 'Cairo', 'Segoe UI', Tahoma, sans-serif; padding: 20px; color: #1e293b; direction: rtl; }
          .header { text-align: center; margin-bottom: 25px; border-bottom: 3px double #0284c7; padding-bottom: 15px; }
          .header h1 { margin: 0; font-size: 22px; color: #0f172a; }
          .header p { margin: 4px 0; color: #475569; font-size: 13px; }
          table { width: 100%; border-collapse: collapse; margin-top: 15px; font-size: 12px; }
          th, td { border: 1px solid #cbd5e1; padding: 9px; text-align: right; }
          th { background-color: #0f172a; color: white; font-weight: bold; text-align: center; }
          tr:nth-child(even) { background-color: #f8fafc; }
          .total-box { margin-top: 25px; padding: 12px; background: #e0f2fe; border: 1px solid #0284c7; border-radius: 6px; text-align: left; font-size: 16px; font-weight: bold; color: #0369a1; }
          .footer-sig { margin-top: 40px; width: 100%; display: flex; justify-content: space-between; text-align: center; font-size: 13px; font-weight: bold; }
          .sig-box { width: 30%; border-top: 1px dashed #64748b; padding-top: 8px; }
        </style>
      </head>
      <body>
        $logoHtml
        <div class="header">
          <h1>$reportTitle</h1>
          $pointInfoHtml
          <p>الفترة الزمنية للتقرير: من <b>$startStr</b> إلى <b>$endStr</b></p>
          <p style="font-size: 11px; color: #64748b;">تاريخ إصدار التقرير: ${DateFormat('yyyy/MM/dd HH:mm').format(DateTime.now())}</p>
        </div>
        <table>
          <thead>
            $tableHeadersHtml
          </thead>
          <tbody>
            $rowsHtml
          </tbody>
        </table>
        <div class="total-box">
          $summaryTotalHtml
        </div>
        $currencyBreakdownHtml
        <div class="footer-sig">
          <div class="sig-box">توقيع المسؤول</div>
          <div class="sig-box">توقيع المحاسب</div>
          <div class="sig-box">اعتماد المدير العام</div>
        </div>
      </body>
      </html>
    ''';
  }

  void _showWhatsAppReportDialog() async {
    final apiService = Provider.of<ApiService>(context, listen: false);
    final phoneController = TextEditingController();
    final messageController = TextEditingController();
    bool isSending = false;

    final startStr = _startDate != null ? DateFormat('yyyy/MM/dd').format(_startDate!) : 'اليوم';
    final endStr = _endDate != null ? DateFormat('yyyy/MM/dd').format(_endDate!) : 'اليوم';
    final reportName = _getReportTypeName(_activeReportType);

    // Fetch default settings
    try {
      final settings = await apiService.getWhatsAppSettings();
      if (_activeReportType == 300) {
        phoneController.text = (settings['auditPhone'] ?? '').isNotEmpty
            ? settings['auditPhone']
            : (settings['financialPhone'] ?? '967770000000');
      } else {
        phoneController.text = (settings['financialPhone'] ?? '').isNotEmpty
            ? settings['financialPhone']
            : '967770000000';
      }
    } catch (_) {
      phoneController.text = '967770000000';
    }

    messageController.text = '$reportName - نقطة البيع: ${apiService.pointName} (#${apiService.pointNo})';

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateDialog) => Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            backgroundColor: const Color(0xFF0F172A),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Row(
                  children: [
                    Icon(Icons.picture_as_pdf_rounded, color: Color(0xFF25D366), size: 26),
                    SizedBox(width: 10),
                    Text(
                      'إرسال تقرير PDF عبر واتساب 📄',
                      style: TextStyle(color: Colors.white, fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 17),
                    ),
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white54),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            content: SingleChildScrollView(
              child: SizedBox(
                width: 480,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Information Badge
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.blueAccent.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.blueAccent.withOpacity(0.3)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.store_rounded, color: Colors.cyanAccent, size: 18),
                              const SizedBox(width: 6),
                              Text(
                                'نقطة البيع: ${apiService.pointName} (رقم #${apiService.pointNo})',
                                style: const TextStyle(color: Colors.white, fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 13),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'التقرير المختار: $reportName للفترة ($startStr - $endStr)',
                            style: const TextStyle(color: Colors.white70, fontFamily: 'Cairo', fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Recipient Phone Input
                    const Text('رقم الواتساب المستلم (مع رمز الدولة):', style: TextStyle(color: Colors.white, fontFamily: 'Cairo', fontSize: 13, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    TextFormField(
                      controller: phoneController,
                      keyboardType: TextInputType.phone,
                      style: const TextStyle(color: Colors.amberAccent, fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 15),
                      decoration: InputDecoration(
                        isDense: true,
                        filled: true,
                        fillColor: const Color(0xFF1E293B),
                        prefixIcon: const Icon(Icons.phone_android_rounded, color: Color(0xFF25D366)),
                        hintText: 'مثال: 967770000000',
                        hintStyle: const TextStyle(color: Colors.white30, fontFamily: 'Cairo', fontSize: 12),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFF25D366), width: 1.5)),
                      ),
                    ),

                    const SizedBox(height: 12),

                    // Report Title / Notes Input
                    const Text('عنوان التقرير / وصف الرسالة المرفقة:', style: TextStyle(color: Colors.white70, fontFamily: 'Cairo', fontSize: 12)),
                    const SizedBox(height: 6),
                    TextFormField(
                      controller: messageController,
                      maxLines: 2,
                      style: const TextStyle(color: Colors.white, fontFamily: 'Cairo', fontSize: 12),
                      decoration: InputDecoration(
                        isDense: true,
                        filled: true,
                        fillColor: const Color(0xFF1E293B),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('إلغاء', style: TextStyle(color: Colors.white60, fontFamily: 'Cairo')),
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF25D366),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                icon: isSending 
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Icon(Icons.picture_as_pdf_rounded, size: 18),
                label: const Text(
                  'تحويل إلى PDF وإرسال للواتساب 📄',
                  style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold),
                ),
                onPressed: isSending ? null : () async {
                  final phone = phoneController.text.trim();
                  final msgText = messageController.text.trim();
                  if (phone.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('الرجاء إدخال رقم الواتساب المستلم', style: TextStyle(fontFamily: 'Cairo')), backgroundColor: Colors.orange),
                    );
                    return;
                  }

                  setStateDialog(() => isSending = true);
                  final apiService = Provider.of<ApiService>(context, listen: false);

                  try {
                    final htmlReport = _generateReportHtmlContent();
                    final res = await apiService.sendWhatsAppReportPdf(
                      phone: phone,
                      reportTitle: msgText.isNotEmpty ? msgText : reportName,
                      reportSummaryText: 'تقرير $reportName مفصل مع الجداول - نقطة البيع: ${apiService.pointName} (#${apiService.pointNo})',
                      htmlContent: htmlReport,
                    );

                    if (context.mounted) Navigator.pop(context);

                    final waLink = res['wa_link'];
                    if (waLink != null && waLink.toString().isNotEmpty) {
                      try {
                        js.context.callMethod('open', [waLink, '_blank']);
                      } catch (_) {}
                    }

                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(res['message'] ?? 'تم إرسال التقرير عبر الواتساب بنجاح 🚀', style: const TextStyle(fontFamily: 'Cairo')),
                          backgroundColor: Colors.green,
                        ),
                      );
                    }
                  } catch (e) {
                    setStateDialog(() => isSending = false);
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('خطأ أثناء إرسال التقرير: $e', style: const TextStyle(fontFamily: 'Cairo')),
                          backgroundColor: Colors.red,
                        ),
                      );
                    }
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final salesVal = (_summary['totalSales'] as num? ?? 0.0).toDouble();
    final returnsVal = (_summary['totalReturns'] as num? ?? 0.0).toDouble();
    final disbursementsVal = (_summary['totalDisbursementBonds'] as num? ?? 0.0).toDouble();
    final stockVal = (_stockSummary['totalStockValue'] as num? ?? 0.0).toDouble();

    final pieSegments = [
      PieChartSegment(
        label: 'حجم المبيعات',
        value: salesVal,
        color: Colors.blueAccent,
        icon: Icons.trending_up_rounded,
      ),
      PieChartSegment(
        label: 'المردود والمرتجعات',
        value: returnsVal,
        color: Colors.redAccent,
        icon: Icons.assignment_return_outlined,
      ),
      PieChartSegment(
        label: 'المصاريف وسندات الصرف',
        value: disbursementsVal,
        color: Colors.orangeAccent,
        icon: Icons.upload_rounded,
      ),
      PieChartSegment(
        label: 'المتبقي في المخزون',
        value: stockVal,
        color: Colors.purpleAccent,
        icon: Icons.inventory_2_outlined,
      ),
    ];

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
                        'التقارير المالية والتدقيق',
                        style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold, fontFamily: 'Cairo'),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'عرض إحصائيات المبيعات، المشتريات، المرتجعات، المصروفات والحركة المالية',
                        style: TextStyle(color: Colors.white54, fontSize: 13, fontFamily: 'Cairo'),
                      ),
                    ],
                  ),

                  Row(
                    children: [
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF0F172A),
                          foregroundColor: Colors.greenAccent,
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                            side: const BorderSide(color: Colors.greenAccent, width: 1.2),
                          ),
                        ),
                        icon: const Icon(Icons.qr_code_scanner_rounded, size: 18, color: Colors.greenAccent),
                        label: const Text('إدارة مزود الواتساب 📲', style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
                        onPressed: () {
                          final apiService = Provider.of<ApiService>(context, listen: false);
                          WhatsAppProviderDialog.show(context, apiService);
                        },
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF25D366),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        icon: const Icon(Icons.send_rounded, size: 18),
                        label: const Text('إرسال التقرير عبر واتساب 📱', style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
                        onPressed: _showWhatsAppReportDialog,
                      ),
                      const SizedBox(width: 12),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.teal,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        icon: const Icon(Icons.print_rounded),
                        label: const Text('طباعة التقرير الحالي', style: TextStyle(fontFamily: 'Cairo')),
                        onPressed: _printReport,
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
                                  _fetchReportData();
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

              // Summary Stats Grid (8 Compact Cards in 2 Rows of 4) & Financial Pie Chart Side-by-Side
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Left Side: 8 Compact Summary Cards Grid
                  Expanded(
                    flex: 3,
                    child: Column(
                      children: [
                        Row(
                          children: [
                            _buildSummaryCard(
                              'إجمالي المبيعات',
                              currencyFormat((_summary['totalSales'] as num? ?? 0.0).toDouble()),
                              'نقدي: ${currencyFormat((_summary['cashSales'] as num? ?? 0.0).toDouble())}',
                              Icons.trending_up_rounded,
                              Colors.blueAccent,
                            ),
                            const SizedBox(width: 8),
                            _buildSummaryCard(
                              'مرتجع المبيعات',
                              currencyFormat((_summary['totalReturns'] as num? ?? 0.0).toDouble()),
                              'المبالغ المستردة للزبائن',
                              Icons.assignment_return_outlined,
                              Colors.redAccent,
                            ),
                            const SizedBox(width: 8),
                            _buildSummaryCard(
                              'إجمالي المشتريات',
                              currencyFormat((_summary['totalPurchases'] as num? ?? 0.0).toDouble()),
                              'فواتير توريد المستودع',
                              Icons.local_shipping_outlined,
                              Colors.amberAccent,
                            ),
                            const SizedBox(width: 8),
                            _buildSummaryCard(
                              'التحويلات المخزنية',
                              currencyFormat((_summary['totalTransfers'] as num? ?? 0.0).toDouble()),
                              'وارد: ${currencyFormat((_summary['totalTransfersIn'] as num? ?? 0.0).toDouble())}',
                              Icons.swap_horiz_rounded,
                              Colors.purpleAccent,
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            _buildSummaryCard(
                              'إجمالي سندات الصرف',
                              currencyFormat((_summary['totalDisbursementBonds'] as num? ?? 0.0).toDouble()),
                              'المدفوعات والمصاريف',
                              Icons.upload_rounded,
                              Colors.orangeAccent,
                            ),
                            const SizedBox(width: 8),
                            _buildSummaryCard(
                              'إجمالي سندات القبض',
                              currencyFormat((_summary['totalReceiptBonds'] as num? ?? 0.0).toDouble()),
                              'المقبوضات والإيداعات',
                              Icons.download_rounded,
                              Colors.tealAccent,
                            ),
                            const SizedBox(width: 8),
                            _buildSummaryCard(
                              'رصيد الصندوق الفعلي',
                              currencyFormat((_summary['cashInRegister'] as num? ?? 0.0).toDouble()),
                              'حركة السيولة المتبقية',
                              Icons.account_balance_wallet_rounded,
                              Colors.greenAccent,
                              onTapPrint: _printCashSummaryReport,
                            ),
                            const SizedBox(width: 8),
                            _buildSummaryCard(
                              'التقرير الختامي الموجز',
                              'عرض التقرير',
                              'ملخص العمليات اليومية',
                              Icons.description_rounded,
                              Colors.cyanAccent,
                              onTapPrint: _printExecutiveSummaryReport,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),

                  // Right Side: Financial Pie Chart
                  Expanded(
                    flex: 2,
                    child: FinancialPieChart(segments: pieSegments),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Multi-Currency Breakdown Chips Bar
              _buildCurrencyBreakdownBar(),
              const SizedBox(height: 4),

              // Categorized Tab Header Bar (المبيعات | المشتريات والمخزون | التحويلات المخزنية | المصروفات | التقرير الختامي الموجز)
              Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white.withOpacity(0.08)),
                ),
                padding: const EdgeInsets.all(4),
                child: Row(
                  children: [
                    Expanded(child: _buildCategoryGroupTab(0, '🛒 المبيعات والمرتجعات', Colors.blueAccent)),
                    const SizedBox(width: 4),
                    Expanded(child: _buildCategoryGroupTab(1, '🚚 المشتريات والمخزون', Colors.amberAccent)),
                    const SizedBox(width: 4),
                    Expanded(child: _buildCategoryGroupTab(2, '🔁 التحويلات المخزنية', Colors.purpleAccent)),
                    const SizedBox(width: 4),
                    Expanded(child: _buildCategoryGroupTab(3, '💸 المصروفات والسندات والسيولة', Colors.tealAccent)),
                    const SizedBox(width: 4),
                    Expanded(child: _buildCategoryGroupTab(4, '📋 التقرير الختامي الموجز', Colors.cyanAccent)),
                    const SizedBox(width: 4),
                    Expanded(child: _buildCategoryGroupTab(5, '🛡️ سجل التدقيق والرقابة', Colors.redAccent)),
                  ],
                ),
              ),
              const SizedBox(height: 10),

              // Sub-report Filter Buttons based on Active Category Group
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _getReportTypeTabsForGroup(),
              ),
              const SizedBox(height: 12),

              // Stock Specific Filter Bar (if Stock report active)
              if (_activeReportType == 99) ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        _buildStockFilterChip('all', 'جميع الأصناف (${_stockSummary['totalItems'] ?? 0})', Colors.blueAccent),
                        const SizedBox(width: 8),
                        _buildStockFilterChip('available', 'الكميات المتوفرة (${_stockSummary['totalAvailable'] ?? 0})', Colors.greenAccent),
                        const SizedBox(width: 8),
                        _buildStockFilterChip('low', 'الكميات الناقصة/السالبة (${_stockSummary['totalLow'] ?? 0})', Colors.redAccent),
                        const SizedBox(width: 8),
                        _buildStockFilterChip('zero', 'الكميات الصفرية/أقل من $_zeroThreshold (${_stockSummary['totalZero'] ?? 0})', Colors.orangeAccent),
                        const SizedBox(width: 12),

                        // Zero Threshold Input Field
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.orange.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.orangeAccent.withOpacity(0.4)),
                          ),
                          child: Row(
                            children: [
                              const Text(
                                'حد الكمية الصفرية:',
                                style: TextStyle(color: Colors.orangeAccent, fontSize: 11, fontFamily: 'Cairo', fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(width: 6),
                              SizedBox(
                                width: 50,
                                height: 28,
                                child: TextField(
                                  controller: _zeroThresholdController,
                                  keyboardType: TextInputType.number,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                                  decoration: InputDecoration(
                                    isDense: true,
                                    contentPadding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
                                    filled: true,
                                    fillColor: const Color(0xFF0F172A),
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(4), borderSide: const BorderSide(color: Colors.orangeAccent)),
                                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(4), borderSide: const BorderSide(color: Colors.orangeAccent)),
                                  ),
                                  onChanged: (val) {
                                    final parsed = int.tryParse(val.trim());
                                    if (parsed != null && parsed >= 0) {
                                      setState(() {
                                        _zeroThreshold = parsed;
                                      });
                                      _fetchReportData();
                                    }
                                  },
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    Text(
                      'إجمالي قيمة المخزون الحالي: ${currencyFormat((_stockSummary['totalStockValue'] as num? ?? 0.0).toDouble())}',
                      style: const TextStyle(color: Colors.purpleAccent, fontWeight: FontWeight.bold, fontFamily: 'Cairo', fontSize: 14),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
              ],

              // Main Transactions Data Table or Executive Brief Summary
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : (_activeReportType == 500)
                        ? _buildDailyFinancialBreakdownWidget()
                        : (_activeReportType == 200)
                            ? SingleChildScrollView(child: _buildExecutiveBriefSummaryCard())
                            : (_activeReportType == 300
                                ? _auditLogs.isEmpty
                                : (_activeReportType == 99
                                    ? _stockItems.isEmpty
                                    : (_activeReportType == 101 ? ((_cashMovementData['movements'] as List?) ?? []).isEmpty : _transactions.isEmpty)))
                                ? const Center(
                                    child: Text(
                                      'لا توجد بيانات مسجلة في هذا التقرير للفترة المحددة.',
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
                                  // Table Header
                                  Container(
                                    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withOpacity(0.04),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Row(
                                      children: _activeReportType == 300
                                          ? const [
                                              Expanded(flex: 1, child: Text('#', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontFamily: 'Cairo'))),
                                              Expanded(flex: 2, child: Text('التاريخ والوقت', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontFamily: 'Cairo'))),
                                              Expanded(flex: 2, child: Text('المستخدم', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontFamily: 'Cairo'))),
                                              Expanded(flex: 2, child: Text('نوع الحركة', style: TextStyle(color: Colors.amberAccent, fontWeight: FontWeight.bold, fontFamily: 'Cairo'))),
                                              Expanded(flex: 4, child: Text('وصف الحدث', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontFamily: 'Cairo'))),
                                              Expanded(flex: 3, child: Text('التفاصيل الإضافية', style: TextStyle(color: Colors.white54, fontWeight: FontWeight.bold, fontFamily: 'Cairo'))),
                                            ]
                                          : (_activeReportType == 99
                                          ? const [
                                              Expanded(flex: 2, child: Text('الباركود', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontFamily: 'Cairo'))),
                                              Expanded(flex: 3, child: Text('اسم الصنف', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontFamily: 'Cairo'))),
                                              Expanded(flex: 1, child: Text('الوحدة', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontFamily: 'Cairo'))),
                                              Expanded(flex: 1, child: Text('العملة', style: TextStyle(color: Colors.cyanAccent, fontWeight: FontWeight.bold, fontFamily: 'Cairo'), textAlign: TextAlign.center)),
                                              Expanded(flex: 2, child: Text('سعر التكلفة', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontFamily: 'Cairo'), textAlign: TextAlign.end)),
                                              Expanded(flex: 2, child: Text('سعر البيع', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontFamily: 'Cairo'), textAlign: TextAlign.end)),
                                              Expanded(flex: 2, child: Text('الكمية الحقيقية', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontFamily: 'Cairo'), textAlign: TextAlign.center)),
                                              Expanded(flex: 2, child: Text('قيمة البيع', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontFamily: 'Cairo'), textAlign: TextAlign.end)),
                                              Expanded(flex: 2, child: Text('حالة المخزون', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontFamily: 'Cairo'), textAlign: TextAlign.center)),
                                            ]
                                          : (_activeReportType == 101
                                              ? const [
                                                  Expanded(flex: 2, child: Text('التاريخ', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontFamily: 'Cairo'))),
                                                  Expanded(flex: 2, child: Text('نوع الحركة', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontFamily: 'Cairo'))),
                                                  Expanded(flex: 1, child: Text('العملة', style: TextStyle(color: Colors.cyanAccent, fontWeight: FontWeight.bold, fontFamily: 'Cairo'), textAlign: TextAlign.center)),
                                                  Expanded(flex: 2, child: Text('رقم المستند', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontFamily: 'Cairo'))),
                                                  Expanded(flex: 3, child: Text('البيان والوصف', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontFamily: 'Cairo'))),
                                                  Expanded(flex: 2, child: Text('مقبوضات (+)', style: TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold, fontFamily: 'Cairo'), textAlign: TextAlign.end)),
                                                  Expanded(flex: 2, child: Text('مدفوعات (-)', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, fontFamily: 'Cairo'), textAlign: TextAlign.end)),
                                                  Expanded(flex: 2, child: Text('الرصيد المتبقي', style: TextStyle(color: Colors.blueAccent, fontWeight: FontWeight.bold, fontFamily: 'Cairo'), textAlign: TextAlign.end)),
                                                ]
                                              : ((_activeReportType == 10 || _activeReportType == 11 || _activeReportType == 100)
                                                  ? const [
                                                      Expanded(flex: 2, child: Text('رقم السند', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontFamily: 'Cairo'))),
                                                      Expanded(flex: 2, child: Text('التاريخ', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontFamily: 'Cairo'))),
                                                      Expanded(flex: 3, child: Text('الحساب / البند', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontFamily: 'Cairo'))),
                                                      Expanded(flex: 1, child: Text('العملة', style: TextStyle(color: Colors.cyanAccent, fontWeight: FontWeight.bold, fontFamily: 'Cairo'), textAlign: TextAlign.center)),
                                                      Expanded(flex: 4, child: Text('توضيح البيان والشارح', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontFamily: 'Cairo'))),
                                                      Expanded(flex: 2, child: Text('نوع السند', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontFamily: 'Cairo'))),
                                                      Expanded(flex: 2, child: Text('المبلغ', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontFamily: 'Cairo'), textAlign: TextAlign.end)),
                                                    ]
                                                  : const [
                                                      Expanded(flex: 1, child: Text('#', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontFamily: 'Cairo'))),
                                                      Expanded(flex: 2, child: Text('رقم الفاتورة', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontFamily: 'Cairo'))),
                                                      Expanded(flex: 2, child: Text('التاريخ', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontFamily: 'Cairo'))),
                                                      Expanded(flex: 2, child: Text('الباركود', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontFamily: 'Cairo'))),
                                                      Expanded(flex: 3, child: Text('اسم الصنف', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontFamily: 'Cairo'))),
                                                      Expanded(flex: 1, child: Text('العملة', style: TextStyle(color: Colors.cyanAccent, fontWeight: FontWeight.bold, fontFamily: 'Cairo'), textAlign: TextAlign.center)),
                                                      Expanded(flex: 1, child: Text('الكمية', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontFamily: 'Cairo'), textAlign: TextAlign.center)),
                                                      Expanded(flex: 2, child: Text('السعر', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontFamily: 'Cairo'), textAlign: TextAlign.end)),
                                                      Expanded(flex: 2, child: Text('الإجمالي', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontFamily: 'Cairo'), textAlign: TextAlign.end)),
                                                      Expanded(flex: 2, child: Text('البائع/المستخدم', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontFamily: 'Cairo'))),
                                                      Expanded(flex: 2, child: Text('طريقة الدفع', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontFamily: 'Cairo'), textAlign: TextAlign.center)),
                                                    ]))),
                                    ),
                                  ),
                                  const Divider(color: Colors.white10, height: 16),

                                  // Table Rows
                                  Expanded(
                                    child: ListView.builder(
                                      itemCount: _activeReportType == 300
                                          ? _auditLogs.length
                                          : (_activeReportType == 99
                                              ? _stockItems.length
                                              : (_activeReportType == 101 ? ((_cashMovementData['movements'] as List?) ?? []).length : _transactions.length)),
                                      itemBuilder: (context, index) {
                                        if (_activeReportType == 300) {
                                          final logItem = _auditLogs[index];
                                          final actType = logItem['actionType'] ?? 'حركة';
                                          Color actColor = Colors.blueAccent;
                                          if (actType.contains('تسجيل') || actType.contains('دخول')) actColor = Colors.tealAccent;
                                          if (actType.contains('بيع') || actType.contains('فاتورة')) actColor = Colors.greenAccent;
                                          if (actType.contains('سند') || actType.contains('مالي')) actColor = Colors.purpleAccent;
                                          if (actType.contains('حذف') || actType.contains('تعديل')) actColor = Colors.amberAccent;

                                          return Padding(
                                            padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
                                            child: Row(
                                              children: [
                                                Expanded(flex: 1, child: Text('${logItem['id']}', style: const TextStyle(color: Colors.white54))),
                                                Expanded(flex: 2, child: Text('${logItem['date']}', style: const TextStyle(color: Colors.white70, fontSize: 12))),
                                                Expanded(flex: 2, child: Text(logItem['userName'] ?? 'المستخدم', style: const TextStyle(color: Colors.white, fontFamily: 'Cairo', fontWeight: FontWeight.bold))),
                                                Expanded(
                                                  flex: 2,
                                                  child: Container(
                                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                    decoration: BoxDecoration(
                                                      color: actColor.withOpacity(0.15),
                                                      borderRadius: BorderRadius.circular(6),
                                                      border: Border.all(color: actColor.withOpacity(0.4)),
                                                    ),
                                                    child: Text(
                                                      actType,
                                                      textAlign: TextAlign.center,
                                                      style: TextStyle(color: actColor, fontSize: 12, fontFamily: 'Cairo', fontWeight: FontWeight.bold),
                                                    ),
                                                  ),
                                                ),
                                                Expanded(flex: 4, child: Text(logItem['description'] ?? '', style: const TextStyle(color: Colors.white, fontFamily: 'Cairo'))),
                                                Expanded(flex: 3, child: Text(logItem['details'] ?? '', style: const TextStyle(color: Colors.white54, fontFamily: 'Cairo', fontSize: 11))),
                                              ],
                                            ),
                                          );
                                        }
                                        if (_activeReportType == 99) {
                                          final item = _stockItems[index];
                                          final st = item['status'];
                                          final stLabel = st == 'available' ? 'متوفر' : (st == 'zero' ? 'كمية صفرية' : 'كمية ناقصة/سالبة');
                                          final stColor = st == 'available' ? Colors.greenAccent : (st == 'zero' ? Colors.orangeAccent : Colors.redAccent);
                                          final qty = item['quantity'] ?? item['currentQuantity'] ?? 0;
                                          final cSym = item['currencySymbol'] ?? 'د.أ';
                                          final costP = (item['costPrice'] as num? ?? 0.0).toDouble();
                                          final salesP = (item['salesPrice'] as num? ?? 0.0).toDouble();
                                          final salesV = (item['salesValue'] as num? ?? (item['stockValue'] as num? ?? 0.0)).toDouble();

                                          return Padding(
                                            padding: const EdgeInsets.symmetric(vertical: 10.0, horizontal: 16.0),
                                            child: Row(
                                              children: [
                                                Expanded(flex: 2, child: Text(item['barcode'] ?? '', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
                                                Expanded(flex: 3, child: Text(item['itemName'] ?? '', style: const TextStyle(color: Colors.white, fontFamily: 'Cairo'))),
                                                Expanded(flex: 1, child: Text(item['unitName'] ?? 'حبة', style: const TextStyle(color: Colors.white70, fontFamily: 'Cairo'))),
                                                Expanded(flex: 1, child: Center(child: _buildCurrencyBadge(item['moneyId'], symbol: cSym))),
                                                Expanded(flex: 2, child: Text(currencyFormat(costP, symbol: cSym), textAlign: TextAlign.end, style: const TextStyle(color: Colors.white54))),
                                                Expanded(flex: 2, child: Text(currencyFormat(salesP, symbol: cSym), textAlign: TextAlign.end, style: const TextStyle(color: Colors.white70))),
                                                Expanded(flex: 2, child: Text('$qty', textAlign: TextAlign.center, style: TextStyle(color: stColor, fontWeight: FontWeight.bold, fontSize: 16))),
                                                Expanded(flex: 2, child: Text(currencyFormat(salesV, symbol: cSym), textAlign: TextAlign.end, style: const TextStyle(color: Colors.tealAccent, fontWeight: FontWeight.bold))),
                                                Expanded(
                                                  flex: 2,
                                                  child: Container(
                                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                    decoration: BoxDecoration(
                                                      color: stColor.withOpacity(0.15),
                                                      borderRadius: BorderRadius.circular(4),
                                                      border: Border.all(color: stColor.withOpacity(0.4)),
                                                    ),
                                                    child: Text(
                                                      stLabel,
                                                      textAlign: TextAlign.center,
                                                      style: TextStyle(color: stColor, fontSize: 11, fontFamily: 'Cairo', fontWeight: FontWeight.bold),
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          );
                                        }

                                        if (_activeReportType == 101) {
                                          final movementsList = (_cashMovementData['movements'] as List?) ?? [];
                                          final m = movementsList[index];
                                          final cashInVal = (m['cashIn'] as num? ?? 0.0).toDouble();
                                          final cashOutVal = (m['cashOut'] as num? ?? 0.0).toDouble();
                                          final balanceVal = (m['balance'] as num? ?? 0.0).toDouble();
                                          final typeStr = m['type'] ?? '';
                                          final cSym = m['currencySymbol'] ?? 'د.أ';

                                          return Padding(
                                            padding: const EdgeInsets.symmetric(vertical: 10.0, horizontal: 16.0),
                                            child: Row(
                                              children: [
                                                Expanded(flex: 2, child: Text('${m['date']}', style: const TextStyle(color: Colors.white70))),
                                                Expanded(
                                                  flex: 2,
                                                  child: Container(
                                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                                    decoration: BoxDecoration(
                                                      color: cashInVal > 0 ? Colors.green.withOpacity(0.15) : Colors.orange.withOpacity(0.15),
                                                      borderRadius: BorderRadius.circular(4),
                                                    ),
                                                    child: Text(
                                                      typeStr,
                                                      style: TextStyle(
                                                        color: cashInVal > 0 ? Colors.greenAccent : Colors.orangeAccent,
                                                        fontWeight: FontWeight.bold,
                                                        fontSize: 12,
                                                        fontFamily: 'Cairo',
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                                Expanded(flex: 1, child: Center(child: _buildCurrencyBadge(m['moneyId'], symbol: cSym))),
                                                Expanded(flex: 2, child: Text('# ${m['refNo']}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
                                                Expanded(flex: 3, child: Text('${m['description']}', style: const TextStyle(color: Colors.white54, fontFamily: 'Cairo'), maxLines: 1, overflow: TextOverflow.ellipsis)),
                                                Expanded(flex: 2, child: Text(cashInVal > 0 ? currencyFormat(cashInVal, symbol: cSym) : '-', textAlign: TextAlign.end, style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold))),
                                                Expanded(flex: 2, child: Text(cashOutVal > 0 ? currencyFormat(cashOutVal, symbol: cSym) : '-', textAlign: TextAlign.end, style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold))),
                                                Expanded(flex: 2, child: Text(currencyFormat(balanceVal, symbol: cSym), textAlign: TextAlign.end, style: const TextStyle(color: Colors.blueAccent, fontWeight: FontWeight.bold, fontSize: 14))),
                                              ],
                                            ),
                                          );
                                        }

                                        final tx = _transactions[index];
                                        final isBond = _activeReportType == 10 || _activeReportType == 11 || _activeReportType == 100;
                                        final isReceipt = tx['isReceipt'] == true || tx['bondType'] == 'سند قبض';
                                        final cSym = tx['currencySymbol'] ?? 'د.أ';

                                        if (isBond) {
                                          return Padding(
                                            padding: const EdgeInsets.symmetric(vertical: 10.0, horizontal: 16.0),
                                            child: Row(
                                              children: [
                                                Expanded(
                                                  flex: 2,
                                                  child: Text('# ${tx['transNumber']}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                                ),
                                                Expanded(
                                                  flex: 2,
                                                  child: Text('${tx['date']}', style: const TextStyle(color: Colors.white70)),
                                                ),
                                                Expanded(
                                                  flex: 3,
                                                  child: Text(
                                                    tx['accountName'] ?? 'حساب عام',
                                                    style: const TextStyle(color: Colors.cyanAccent, fontFamily: 'Cairo', fontWeight: FontWeight.bold),
                                                    maxLines: 1,
                                                    overflow: TextOverflow.ellipsis,
                                                  ),
                                                ),
                                                Expanded(
                                                  flex: 1,
                                                  child: Center(child: _buildCurrencyBadge(tx['moneyId'], symbol: cSym)),
                                                ),
                                                Expanded(
                                                  flex: 4,
                                                  child: Text(
                                                    tx['description'] ?? '',
                                                    style: const TextStyle(color: Colors.white70, fontFamily: 'Cairo'),
                                                    maxLines: 2,
                                                    overflow: TextOverflow.ellipsis,
                                                  ),
                                                ),
                                                Expanded(
                                                  flex: 2,
                                                  child: Container(
                                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                    decoration: BoxDecoration(
                                                      color: isReceipt ? Colors.teal.withOpacity(0.15) : Colors.orange.withOpacity(0.15),
                                                      borderRadius: BorderRadius.circular(4),
                                                      border: Border.all(color: isReceipt ? Colors.tealAccent.withOpacity(0.3) : Colors.orangeAccent.withOpacity(0.3)),
                                                    ),
                                                    child: Text(
                                                      isReceipt ? 'سند قبض (إيداع)' : 'سند صرف (دفعة)',
                                                      style: TextStyle(
                                                        color: isReceipt ? Colors.tealAccent : Colors.orangeAccent,
                                                        fontSize: 12,
                                                        fontFamily: 'Cairo',
                                                        fontWeight: FontWeight.bold,
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                                Expanded(
                                                  flex: 2,
                                                  child: Text(
                                                    currencyFormat((tx['amount'] as num).toDouble(), symbol: cSym),
                                                    textAlign: TextAlign.end,
                                                    style: TextStyle(
                                                      color: isReceipt ? Colors.tealAccent : Colors.orangeAccent,
                                                      fontWeight: FontWeight.bold,
                                                      fontSize: 15,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          );
                                        }

                                        final barcode = tx['barcode'] ?? '';
                                        final itemName = tx['itemName'] ?? (tx['description'] ?? 'صنف');
                                        final qty = tx['quantity'] ?? 0;
                                        final price = (tx['salesPrice'] as num? ?? 0.0).toDouble();
                                        final amount = (tx['amount'] as num? ?? 0.0).toDouble();
                                        final userName = tx['userName'] ?? 'مستخدم 1';
                                        final isCash = tx['payCash'] == 1;

                                        return Padding(
                                          padding: const EdgeInsets.symmetric(vertical: 10.0, horizontal: 16.0),
                                          child: Row(
                                            children: [
                                              Expanded(
                                                flex: 1,
                                                child: Text(
                                                  '${index + 1}',
                                                  style: const TextStyle(color: Colors.white38, fontSize: 13),
                                                ),
                                              ),
                                              Expanded(
                                                flex: 2,
                                                child: Text(
                                                  '# ${tx['transNumber']}',
                                                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                                                ),
                                              ),
                                              Expanded(
                                                flex: 2,
                                                child: Text(
                                                  tx['date'],
                                                  style: const TextStyle(color: Colors.white70),
                                                ),
                                              ),
                                              Expanded(
                                                flex: 2,
                                                child: Text(
                                                  barcode.isNotEmpty ? barcode : '-',
                                                  style: const TextStyle(color: Colors.blueAccent, fontWeight: FontWeight.bold),
                                                ),
                                              ),
                                              Expanded(
                                                flex: 3,
                                                child: Text(
                                                  itemName,
                                                  style: const TextStyle(color: Colors.white, fontFamily: 'Cairo', fontWeight: FontWeight.bold),
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              ),
                                              Expanded(
                                                flex: 1,
                                                child: Center(child: _buildCurrencyBadge(tx['moneyId'], symbol: cSym)),
                                              ),
                                              Expanded(
                                                flex: 1,
                                                child: Text(
                                                  '$qty',
                                                  textAlign: TextAlign.center,
                                                  style: const TextStyle(color: Colors.amberAccent, fontWeight: FontWeight.bold, fontSize: 15),
                                                ),
                                              ),
                                              Expanded(
                                                flex: 2,
                                                child: Text(
                                                  currencyFormat(price, symbol: cSym),
                                                  textAlign: TextAlign.end,
                                                  style: const TextStyle(color: Colors.white70),
                                                ),
                                              ),
                                              Expanded(
                                                flex: 2,
                                                child: Text(
                                                  currencyFormat(amount, symbol: cSym),
                                                  textAlign: TextAlign.end,
                                                  style: const TextStyle(
                                                    color: Colors.greenAccent,
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 15,
                                                  ),
                                                ),
                                              ),
                                              Expanded(
                                                flex: 2,
                                                child: Text(
                                                  userName,
                                                  style: const TextStyle(color: Colors.cyanAccent, fontFamily: 'Cairo', fontSize: 13),
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              ),
                                              Expanded(
                                                flex: 2,
                                                child: _activeReportType == 1
                                                    ? const Text('جرد داخلي', textAlign: TextAlign.center, style: TextStyle(color: Colors.purpleAccent, fontFamily: 'Cairo', fontSize: 13))
                                                    : (_activeReportType == 22
                                                        ? const Text('توريد مخزني', textAlign: TextAlign.center, style: TextStyle(color: Colors.tealAccent, fontFamily: 'Cairo', fontSize: 13))
                                                        : (_activeReportType == 23
                                                            ? const Text('صرف مخزني', textAlign: TextAlign.center, style: TextStyle(color: Colors.orangeAccent, fontFamily: 'Cairo', fontSize: 13))
                                                            : Container(
                                                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                                                decoration: BoxDecoration(
                                                                  color: isCash ? Colors.green.withOpacity(0.1) : Colors.blueAccent.withOpacity(0.1),
                                                                  borderRadius: BorderRadius.circular(4),
                                                                ),
                                                                child: Text(
                                                                  isCash ? 'نقدي' : 'آجل',
                                                                  textAlign: TextAlign.center,
                                                                  style: TextStyle(
                                                                    color: isCash ? Colors.greenAccent : Colors.blueAccent,
                                                                    fontSize: 12,
                                                                    fontFamily: 'Cairo',
                                                                    fontWeight: FontWeight.bold,
                                                                  ),
                                                                ),
                                                              ))),
                                              ),
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

  Widget _buildCategoryGroupTab(int groupIndex, String title, Color activeColor) {
    final bool isSelected = _activeCategoryGroup == groupIndex;
    return InkWell(
      onTap: () {
        setState(() {
          _activeCategoryGroup = groupIndex;
          if (groupIndex == 0) _activeReportType = 35;
          if (groupIndex == 1) _activeReportType = 20;
          if (groupIndex == 2) _activeReportType = 22; // Store Transfers
          if (groupIndex == 3) _activeReportType = 10; // Expenses & Bonds
          if (groupIndex == 4) _activeReportType = 500; // Daily Financial Breakdown & Cash Flow
          if (groupIndex == 5) _activeReportType = 300; // Audit Logs
        });
        _fetchReportData();
      },
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? activeColor.withOpacity(0.2) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: isSelected ? activeColor : Colors.transparent),
        ),
        child: Text(
          title,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: isSelected ? activeColor : Colors.white60,
            fontSize: 12,
            fontWeight: FontWeight.bold,
            fontFamily: 'Cairo',
          ),
        ),
      ),
    );
  }

  List<Widget> _getReportTypeTabsForGroup() {
    if (_activeCategoryGroup == 0) {
      return [
        _buildReportTypeTab(35, 'قائمة المبيعات', Icons.shopping_cart_outlined),
        _buildReportTypeTab(36, 'قائمة مرتجع المبيعات', Icons.assignment_return_outlined),
      ];
    } else if (_activeCategoryGroup == 1) {
      return [
        _buildReportTypeTab(20, 'قائمة المشتريات المحلية', Icons.local_shipping_outlined),
        _buildReportTypeTab(1, 'قائمة جرد أول المدة', Icons.inventory_2_outlined),
        _buildReportTypeTab(99, 'تقرير جرد الكميات والحالة', Icons.inventory_rounded),
      ];
    } else if (_activeCategoryGroup == 2) {
      return [
        _buildReportTypeTab(22, 'أوامر التوريد المخزني الواردة (#22)', Icons.download_rounded),
        _buildReportTypeTab(23, 'أوامر الصرف المخزني الصادرة (#23)', Icons.upload_rounded),
        _buildReportTypeTab(28, 'حركات التحويل المخزني بين الفروع (#28)', Icons.sync_alt_rounded),
      ];
    } else if (_activeCategoryGroup == 3) {
      return [
        _buildReportTypeTab(10, 'حركة سندات القبض', Icons.download_rounded),
        _buildReportTypeTab(11, 'حركة سندات الصرف', Icons.upload_rounded),
        _buildReportTypeTab(100, 'جميع حركات السندات والسيولة', Icons.receipt_long_rounded),
        _buildReportTypeTab(101, 'كشف حركة ومتبقي الصندوق النقدي', Icons.point_of_sale_rounded),
      ];
    } else if (_activeCategoryGroup == 4) {
      return [
        _buildReportTypeTab(500, '📊 الإحصائية والحركة اليومية الشاملة (حسب التاريخ)', Icons.date_range_rounded),
        _buildReportTypeTab(200, 'التقرير الختامي اليومي الموجز الموحد', Icons.assessment_rounded),
      ];
    } else {
      return [
        _buildReportTypeTab(300, 'تقرير سجل التدقيق والرقابة المالية والنظام (#300)', Icons.security_rounded),
      ];
    }
  }

  void _printSingleDayFinancial(Map<String, dynamic> dayRecord) {
    final apiService = Provider.of<ApiService>(context, listen: false);
    final logoBase64 = apiService.logoBase64;
    final dt = dayRecord['date'] ?? '';
    final sales = (dayRecord['sales'] as num? ?? 0.0).toDouble();
    final cashSales = (dayRecord['cashSales'] as num? ?? 0.0).toDouble();
    final creditSales = (dayRecord['creditSales'] as num? ?? 0.0).toDouble();
    final returns = (dayRecord['returns'] as num? ?? 0.0).toDouble();
    final purchases = (dayRecord['purchases'] as num? ?? 0.0).toDouble();
    final expenses = (dayRecord['expenses'] as num? ?? 0.0).toDouble();
    final net = (dayRecord['netRemainingCash'] as num? ?? 0.0).toDouble();

    String logoHtml = '';
    if (logoBase64.isNotEmpty) {
      logoHtml = '<div style="text-align: center; margin-bottom: 12px;"><img src="$logoBase64" style="max-height: 60px;" /></div>';
    }

    final htmlContent = '''
      <!DOCTYPE html>
      <html lang="ar" dir="rtl">
      <head>
        <meta charset="utf-8">
        <title>كشف الحساب والإحصائية اليومية - $dt</title>
        <style>
          body { font-family: 'Cairo', Tahoma, sans-serif; padding: 20px; color: #0f172a; direction: rtl; }
          .header { text-align: center; margin-bottom: 20px; border-bottom: 2px solid #0284c7; padding-bottom: 10px; }
          .header h1 { margin: 0; font-size: 20px; color: #0f172a; }
          .header p { margin: 4px 0 0 0; color: #64748b; font-size: 13px; }
          table { width: 100%; border-collapse: collapse; margin-top: 15px; }
          th, td { border: 1px solid #cbd5e1; padding: 10px 12px; text-align: right; font-size: 13px; }
          th { background-color: #0f172a; color: white; font-weight: bold; }
          .inflow { color: #16a34a; font-weight: bold; }
          .outflow { color: #dc2626; font-weight: bold; }
          .net-row { background-color: #0284c7; color: white; font-size: 15px; font-weight: bold; }
          .net-row td { color: white; }
          .footer-sig { margin-top: 35px; display: flex; justify-content: space-between; text-align: center; font-size: 13px; font-weight: bold; }
          .sig-box { width: 30%; border-top: 1px dashed #94a3b8; padding-top: 6px; }
        </style>
      </head>
      <body>
        $logoHtml
        <div class="header">
          <h1>كشف الإحصائية والحركة المالية اليومية</h1>
          <p>تاريخ اليوم: <b>$dt</b> | نقطة البيع: ${apiService.pointName} (#${apiService.pointNo})</p>
          <p style="font-size: 11px;">تاريخ الطباعة: ${DateFormat('yyyy/MM/dd HH:mm').format(DateTime.now())}</p>
        </div>
        <table>
          <thead>
            <tr>
              <th>البند المالي والعملية</th>
              <th>المبلغ والقيمة</th>
              <th>ملاحظات وتوضيح</th>
            </tr>
          </thead>
          <tbody>
            <tr>
              <td>المبيعات النقدية</td>
              <td class="inflow">+ ${currencyFormat(cashSales)}</td>
              <td>سيولة نقدية داخلة للصندوق</td>
            </tr>
            <tr>
              <td>المبيعات الآجلة (ذمم)</td>
              <td>${currencyFormat(creditSales)}</td>
              <td>حسابات ذمم عملاء</td>
            </tr>
            <tr style="background: #f8fafc; font-weight: bold;">
              <td>إجمالي المبيعات الكلية</td>
              <td style="color: #0284c7;">${currencyFormat(sales)}</td>
              <td>المبيعات النقدية + الآجلة</td>
            </tr>
            <tr>
              <td>مردودات المبيعات</td>
              <td class="outflow">- ${currencyFormat(returns)}</td>
              <td>مبالغ مستردة للزبائن</td>
            </tr>
            <tr>
              <td>المشتريات المحلية</td>
              <td class="outflow">- ${currencyFormat(purchases)}</td>
              <td>فواتير التوريد النقدية</td>
            </tr>
            <tr>
              <td>المصروفات وسندات الصرف</td>
              <td class="outflow">- ${currencyFormat(expenses)}</td>
              <td>نفقات ومدفوعات تشغيلية</td>
            </tr>
            <tr class="net-row">
              <td>الصافي المتبقي بالصندوق لليوم</td>
              <td colspan="2" style="text-align: left;">${currencyFormat(net)}</td>
            </tr>
          </tbody>
        </table>
        <div class="footer-sig">
          <div class="sig-box">الكاشير / أمين الصندوق</div>
          <div class="sig-box">المحاسب المسئول</div>
          <div class="sig-box">اعتماد الإدارة</div>
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

  Widget _buildDailyFinancialBreakdownWidget() {
    final records = (_dailyFinancialData['dailyRecords'] as List?) ?? [];
    final summary = _dailyFinancialData['summary'] ?? {};
    final totSales = (summary['totalSales'] as num? ?? 0.0).toDouble();
    final totReturns = (summary['totalReturns'] as num? ?? 0.0).toDouble();
    final totPurchases = (summary['totalPurchases'] as num? ?? 0.0).toDouble();
    final totExpenses = (summary['totalExpenses'] as num? ?? 0.0).toDouble();
    final totNet = (summary['netRemainingCash'] as num? ?? 0.0).toDouble();
    final daysCount = (summary['totalDaysWithActivity'] as num? ?? 0).toInt();

    return Column(
      children: [
        // Summary Highlights Bar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: const Color(0xFF1E293B),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.cyanAccent.withOpacity(0.3)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(Icons.analytics_rounded, color: Colors.cyanAccent, size: 22),
                  const SizedBox(width: 8),
                  Text(
                    'إحصائية الأيام النشطة: $daysCount يوم | الفترة: ${_startDate != null ? DateFormat('yyyy-MM-dd').format(_startDate!) : ''} إلى ${_endDate != null ? DateFormat('yyyy-MM-dd').format(_endDate!) : ''}',
                    style: const TextStyle(color: Colors.white, fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ],
              ),
              Row(
                children: [
                  const Text(
                    'الصافي الكلي المتبقي بالصندوق للفترة: ',
                    style: TextStyle(color: Colors.white70, fontFamily: 'Cairo', fontSize: 13),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: totNet >= 0 ? Colors.teal.withOpacity(0.2) : Colors.red.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: totNet >= 0 ? Colors.tealAccent : Colors.redAccent),
                    ),
                    child: Text(
                      currencyFormat(totNet),
                      style: TextStyle(
                        color: totNet >= 0 ? Colors.tealAccent : Colors.redAccent,
                        fontFamily: 'Cairo',
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),

        // Main Table
        Expanded(
          child: Card(
            color: const Color(0xFF1E293B),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  // Table Header
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.04),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Row(
                      children: [
                        Expanded(flex: 2, child: Text('التاريخ', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontFamily: 'Cairo'))),
                        Expanded(flex: 3, child: Text('المبيعات (+)', style: TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold, fontFamily: 'Cairo'), textAlign: TextAlign.end)),
                        Expanded(flex: 2, child: Text('المردودات (-)', style: TextStyle(color: Colors.amberAccent, fontWeight: FontWeight.bold, fontFamily: 'Cairo'), textAlign: TextAlign.end)),
                        Expanded(flex: 2, child: Text('المشتريات (-)', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, fontFamily: 'Cairo'), textAlign: TextAlign.end)),
                        Expanded(flex: 2, child: Text('المصروفات (-)', style: TextStyle(color: Colors.purpleAccent, fontWeight: FontWeight.bold, fontFamily: 'Cairo'), textAlign: TextAlign.end)),
                        Expanded(flex: 3, child: Text('الصافي المتبقي بالصندوق (=)', style: TextStyle(color: Colors.cyanAccent, fontWeight: FontWeight.bold, fontFamily: 'Cairo'), textAlign: TextAlign.end)),
                        Expanded(flex: 2, child: Text('العمليات', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontFamily: 'Cairo'), textAlign: TextAlign.center)),
                        Expanded(flex: 2, child: Text('طباعة اليوم', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontFamily: 'Cairo'), textAlign: TextAlign.center)),
                      ],
                    ),
                  ),
                  const Divider(color: Colors.white10, height: 16),

                  // Table Rows
                  Expanded(
                    child: records.isEmpty
                        ? const Center(
                            child: Text(
                              'لا توجد حركات مالية مسجلة خلال الفترة الزمنية المحددة.',
                              style: TextStyle(color: Colors.white30, fontSize: 16, fontFamily: 'Cairo'),
                            ),
                          )
                        : ListView.separated(
                            itemCount: records.length,
                            separatorBuilder: (_, __) => const Divider(color: Colors.white10, height: 1),
                            itemBuilder: (context, index) {
                              final r = records[index];
                              final dt = r['date'] ?? '';
                              final sales = (r['sales'] as num? ?? 0.0).toDouble();
                              final cashSales = (r['cashSales'] as num? ?? 0.0).toDouble();
                              final creditSales = (r['creditSales'] as num? ?? 0.0).toDouble();
                              final returns = (r['returns'] as num? ?? 0.0).toDouble();
                              final purchases = (r['purchases'] as num? ?? 0.0).toDouble();
                              final expenses = (r['expenses'] as num? ?? 0.0).toDouble();
                              final net = (r['netRemainingCash'] as num? ?? 0.0).toDouble();
                              final totalOps = (r['salesCount'] as num? ?? 0).toInt() +
                                  (r['returnsCount'] as num? ?? 0).toInt() +
                                  (r['purchasesCount'] as num? ?? 0).toInt() +
                                  (r['expensesCount'] as num? ?? 0).toInt();

                              return Padding(
                                padding: const EdgeInsets.symmetric(vertical: 10.0, horizontal: 16.0),
                                child: Row(
                                  children: [
                                    // Date
                                    Expanded(
                                      flex: 2,
                                      child: Row(
                                        children: [
                                          const Icon(Icons.event_note_rounded, color: Colors.blueAccent, size: 16),
                                          const SizedBox(width: 6),
                                          Text(
                                            dt,
                                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontFamily: 'Cairo', fontSize: 13),
                                          ),
                                        ],
                                      ),
                                    ),

                                    // Sales
                                    Expanded(
                                      flex: 3,
                                      child: Tooltip(
                                        message: 'نقدي: ${currencyFormat(cashSales)} | آجل: ${currencyFormat(creditSales)}',
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.end,
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Text(
                                              currencyFormat(sales),
                                              style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold, fontSize: 14),
                                            ),
                                            if (creditSales > 0)
                                              Text(
                                                'آجل: ${currencyFormat(creditSales)}',
                                                style: const TextStyle(color: Colors.white38, fontSize: 10, fontFamily: 'Cairo'),
                                              ),
                                          ],
                                        ),
                                      ),
                                    ),

                                    // Returns
                                    Expanded(
                                      flex: 2,
                                      child: Text(
                                        returns > 0 ? currencyFormat(returns) : '-',
                                        textAlign: TextAlign.end,
                                        style: TextStyle(color: returns > 0 ? Colors.amberAccent : Colors.white30, fontWeight: returns > 0 ? FontWeight.bold : FontWeight.normal),
                                      ),
                                    ),

                                    // Purchases
                                    Expanded(
                                      flex: 2,
                                      child: Text(
                                        purchases > 0 ? currencyFormat(purchases) : '-',
                                        textAlign: TextAlign.end,
                                        style: TextStyle(color: purchases > 0 ? Colors.redAccent : Colors.white30, fontWeight: purchases > 0 ? FontWeight.bold : FontWeight.normal),
                                      ),
                                    ),

                                    // Expenses
                                    Expanded(
                                      flex: 2,
                                      child: Text(
                                        expenses > 0 ? currencyFormat(expenses) : '-',
                                        textAlign: TextAlign.end,
                                        style: TextStyle(color: expenses > 0 ? Colors.purpleAccent : Colors.white30, fontWeight: expenses > 0 ? FontWeight.bold : FontWeight.normal),
                                      ),
                                    ),

                                    // Net
                                    Expanded(
                                      flex: 3,
                                      child: Text(
                                        currencyFormat(net),
                                        textAlign: TextAlign.end,
                                        style: TextStyle(
                                          color: net >= 0 ? Colors.cyanAccent : Colors.redAccent,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 15,
                                        ),
                                      ),
                                    ),

                                    // Ops count
                                    Expanded(
                                      flex: 2,
                                      child: Center(
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: Colors.white.withOpacity(0.06),
                                            borderRadius: BorderRadius.circular(10),
                                          ),
                                          child: Text(
                                            '$totalOps حركة',
                                            style: const TextStyle(color: Colors.white70, fontSize: 11, fontFamily: 'Cairo'),
                                          ),
                                        ),
                                      ),
                                    ),

                                    // Print Day Button
                                    Expanded(
                                      flex: 2,
                                      child: Center(
                                        child: ElevatedButton.icon(
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: Colors.teal.withOpacity(0.2),
                                            foregroundColor: Colors.tealAccent,
                                            side: const BorderSide(color: Colors.tealAccent, width: 0.8),
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                                          ),
                                          icon: const Icon(Icons.print_rounded, size: 14),
                                          label: const Text('طباعة اليوم', style: TextStyle(fontFamily: 'Cairo', fontSize: 11)),
                                          onPressed: () => _printSingleDayFinancial(r),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                  ),

                  // Grand Total Footer Row
                  if (records.isNotEmpty) ...[
                    const Divider(color: Colors.cyanAccent, height: 16, thickness: 1.5),
                    Container(
                      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
                      decoration: BoxDecoration(
                        color: Colors.cyanAccent.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          const Expanded(
                            flex: 2,
                            child: Text(
                              'الإجمالي العام للفترة:',
                              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontFamily: 'Cairo', fontSize: 13),
                            ),
                          ),
                          Expanded(
                            flex: 3,
                            child: Text(
                              currencyFormat(totSales),
                              textAlign: TextAlign.end,
                              style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold, fontSize: 15),
                            ),
                          ),
                          Expanded(
                            flex: 2,
                            child: Text(
                              currencyFormat(totReturns),
                              textAlign: TextAlign.end,
                              style: const TextStyle(color: Colors.amberAccent, fontWeight: FontWeight.bold, fontSize: 14),
                            ),
                          ),
                          Expanded(
                            flex: 2,
                            child: Text(
                              currencyFormat(totPurchases),
                              textAlign: TextAlign.end,
                              style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 14),
                            ),
                          ),
                          Expanded(
                            flex: 2,
                            child: Text(
                              currencyFormat(totExpenses),
                              textAlign: TextAlign.end,
                              style: const TextStyle(color: Colors.purpleAccent, fontWeight: FontWeight.bold, fontSize: 14),
                            ),
                          ),
                          Expanded(
                            flex: 3,
                            child: Text(
                              currencyFormat(totNet),
                              textAlign: TextAlign.end,
                              style: TextStyle(
                                color: totNet >= 0 ? Colors.cyanAccent : Colors.redAccent,
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                          ),
                          const Expanded(flex: 4, child: SizedBox()),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSummaryCard(String label, String value, String subtitle, IconData icon, Color color, {VoidCallback? onTapPrint}) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 8.0),
        decoration: BoxDecoration(
          color: const Color(0xFF1E293B),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white.withOpacity(0.06)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(label, style: const TextStyle(color: Colors.white60, fontSize: 11, fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
                Icon(icon, color: color, size: 16),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(color: color, fontSize: 14, fontWeight: FontWeight.bold, fontFamily: 'Cairo'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 2),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    subtitle,
                    style: const TextStyle(color: Colors.white30, fontSize: 9, fontFamily: 'Cairo'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (onTapPrint != null)
                  InkWell(
                    onTap: onTapPrint,
                    child: const Icon(Icons.print_rounded, size: 13, color: Colors.cyanAccent),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStockFilterChip(String filterKey, String label, Color accentColor) {
    final isSelected = _stockStatusFilter == filterKey;
    return ChoiceChip(
      label: Text(label, style: const TextStyle(fontFamily: 'Cairo', fontSize: 12)),
      selected: isSelected,
      selectedColor: accentColor.withOpacity(0.2),
      backgroundColor: const Color(0xFF1E293B),
      labelStyle: TextStyle(
        color: isSelected ? accentColor : Colors.white60,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
      ),
      side: BorderSide(color: isSelected ? accentColor : Colors.white10),
      onSelected: (selected) {
        if (selected) {
          setState(() {
            _stockStatusFilter = filterKey;
          });
          _fetchReportData();
        }
      },
    );
  }

  Widget _buildReportTypeTab(int type, String label, IconData icon) {
    final isActive = _activeReportType == type;
    return OutlinedButton.icon(
      style: OutlinedButton.styleFrom(
        backgroundColor: isActive ? Colors.blueAccent : Colors.transparent,
        foregroundColor: isActive ? Colors.white : Colors.white60,
        side: BorderSide(color: isActive ? Colors.blueAccent : Colors.white10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      ),
      icon: Icon(icon, size: 16),
      label: Text(label, style: const TextStyle(fontFamily: 'Cairo', fontSize: 12, fontWeight: FontWeight.bold)),
      onPressed: () {
        setState(() {
          _activeReportType = type;
        });
        _fetchReportData();
      },
    );
  }
}

class PieChartSegment {
  final String label;
  final double value;
  final Color color;
  final IconData icon;

  PieChartSegment({
    required this.label,
    required this.value,
    required this.color,
    required this.icon,
  });
}

class FinancialPieChart extends StatelessWidget {
  final List<PieChartSegment> segments;

  const FinancialPieChart({super.key, required this.segments});

  @override
  Widget build(BuildContext context) {
    final double total = segments.fold(0.0, (sum, s) => sum + (s.value < 0 ? 0 : s.value));

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(Icons.pie_chart_rounded, color: Colors.cyanAccent, size: 18),
                  SizedBox(width: 6),
                  Text(
                    'مخطط التوزيع المالي والمخزني',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'Cairo',
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.cyanAccent.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.cyanAccent.withOpacity(0.3)),
                ),
                child: Text(
                  '${total.toStringAsFixed(2)} د.أ',
                  style: const TextStyle(
                    color: Colors.cyanAccent,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'Cairo',
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              // Doughnut Chart Graphic
              SizedBox(
                width: 125,
                height: 125,
                child: CustomPaint(
                  painter: _PieChartPainter(segments: segments, total: total),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.account_balance_rounded, color: Colors.white60, size: 18),
                        const SizedBox(height: 2),
                        Text(
                          total > 0 ? '${(total / 1000).toStringAsFixed(1)}k' : '0.0',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'Cairo',
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),

              // Legend List
              Expanded(
                child: Column(
                  children: segments.map((seg) {
                    final double percentage = total > 0 ? (seg.value / total) * 100 : 0.0;
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4.0),
                      child: Row(
                        children: [
                          Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              color: seg.color,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Icon(seg.icon, size: 14, color: seg.color),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              seg.label,
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 11,
                                fontFamily: 'Cairo',
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Text(
                            '${seg.value.toStringAsFixed(0)} د.أ',
                            style: TextStyle(
                              color: seg.color,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              fontFamily: 'Cairo',
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(
                              color: seg.color.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              '${percentage.toStringAsFixed(0)}%',
                              style: TextStyle(
                                color: seg.color,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PieChartPainter extends CustomPainter {
  final List<PieChartSegment> segments;
  final double total;

  _PieChartPainter({required this.segments, required this.total});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    const strokeWidth = 18.0;

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.butt;

    if (total <= 0) {
      paint.color = Colors.white12;
      canvas.drawCircle(center, radius - strokeWidth / 2, paint);
      return;
    }

    double startAngle = -3.141592653589793 / 2;

    for (final seg in segments) {
      final sweepAngle = (seg.value / total) * 2 * 3.141592653589793;
      if (sweepAngle <= 0) continue;

      paint.color = seg.color;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius - strokeWidth / 2),
        startAngle,
        sweepAngle - 0.04,
        false,
        paint,
      );
      startAngle += sweepAngle;
    }
  }

  @override
  bool shouldRepaint(covariant _PieChartPainter oldDelegate) {
    return oldDelegate.total != total || oldDelegate.segments != segments;
  }
}
