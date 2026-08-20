import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart' hide TextDirection;
import '../services/api_service.dart';
import '../services/print_service.dart';
import '../services/barcode_label_service.dart';
import '../models/item.dart';
import 'barcode_print_view.dart';

class ItemMovementView extends StatefulWidget {
  final String? initialQuery;
  const ItemMovementView({super.key, this.initialQuery});

  @override
  State<ItemMovementView> createState() => _ItemMovementViewState();
}

class _ItemMovementViewState extends State<ItemMovementView> {
  late TextEditingController _queryController;
  final TextEditingController _startDateController = TextEditingController();
  final TextEditingController _endDateController = TextEditingController();

  bool _isLoading = false;
  Map<String, dynamic>? _reportData;
  List<dynamic> _movements = [];
  Map<String, dynamic> _summary = {};
  Map<String, dynamic> _itemInfo = {};

  @override
  void initState() {
    super.initState();
    _queryController = TextEditingController(text: widget.initialQuery ?? '');
    
    // Set default date range to current month
    final now = DateTime.now();
    final firstDay = DateTime(now.year, now.month, 1);
    final formatter = DateFormat('yyyy-MM-dd');
    _startDateController.text = formatter.format(firstDay);
    _endDateController.text = formatter.format(now);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_queryController.text.trim().isNotEmpty) {
        _fetchReport();
      }
    });
  }

  @override
  void dispose() {
    _queryController.dispose();
    _startDateController.dispose();
    _endDateController.dispose();
    super.dispose();
  }

  Future<void> _selectDate(BuildContext context, TextEditingController controller) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
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
          child: Directionality(textDirection: TextDirection.rtl, child: child!),
        );
      },
    );
    if (picked != null) {
      setState(() {
        controller.text = DateFormat('yyyy-MM-dd').format(picked);
      });
    }
  }

  Future<void> _fetchReport() async {
    final q = _queryController.text.trim();
    if (q.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('الرجاء إدخال باركود أو اسم الصنف أو رقم الصنف للبحث', style: TextStyle(fontFamily: 'Cairo')),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);
    final apiService = Provider.of<ApiService>(context, listen: false);

    try {
      final res = await apiService.fetchItemMovementReport(
        query: q,
        startDate: _startDateController.text.trim(),
        endDate: _endDateController.text.trim(),
      );

      setState(() {
        _reportData = res;
        _movements = res['movements'] as List? ?? [];
        _summary = res['summary'] as Map<String, dynamic>? ?? {};
        _itemInfo = res['itemInfo'] as Map<String, dynamic>? ?? {};
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ جلب حركة الصنف: $e', style: const TextStyle(fontFamily: 'Cairo')),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  static String currencyFormat(double val) {
    return '${val.toStringAsFixed(2)} د.أ';
  }

  void _printReport() {
    if (_reportData == null || _movements.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('لا توجد بيانات حركة صنف جاهزة للطباعة', style: TextStyle(fontFamily: 'Cairo')),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final apiService = Provider.of<ApiService>(context, listen: false);
    final logoBase64 = apiService.logoBase64;
    final nowStr = DateFormat('yyyy/MM/dd - HH:mm').format(DateTime.now());

    final itemName = _itemInfo['itemName'] ?? _queryController.text;
    final barcode = _itemInfo['barcode'] ?? '-';
    final unitName = _itemInfo['unitName'] ?? 'حبة';
    final salesPrice = (_itemInfo['salesPrice'] as num? ?? 0.0).toDouble();

    final totalIn = _summary['totalIncoming'] ?? 0;
    final totalOut = _summary['totalOutgoing'] ?? 0;
    final balance = _summary['currentBalance'] ?? 0;

    String rowsHtml = '';
    for (int i = 0; i < _movements.length; i++) {
      final m = _movements[i];
      final isAdd = m['isAddition'] == true;
      final rawQty = m['rawQuantity'] ?? 0;
      final price = (m['unitPrice'] as num? ?? 0.0).toDouble();
      final total = (m['totalAmount'] as num? ?? 0.0).toDouble();
      final runBal = m['runningBalance'] ?? 0;

      final qtyStr = isAdd ? '+$rawQty' : '-$rawQty';
      final qtyColor = isAdd ? 'green' : 'red';

      rowsHtml += '''
        <tr>
          <td style="text-align: center;">${i + 1}</td>
          <td style="font-weight: bold;">#${m['transNumber']}</td>
          <td style="font-weight: bold;">${m['typeName']}</td>
          <td>${m['date']}</td>
          <td style="text-align: center; font-weight: bold; color: $qtyColor;">$qtyStr</td>
          <td style="text-align: left;">${currencyFormat(price)}</td>
          <td style="text-align: left; font-weight: bold;">${currencyFormat(total)}</td>
          <td style="text-align: center; font-weight: bold; color: #1E3A8A;">$runBal</td>
          <td>${m['userName'] ?? 'مستخدم 1'}</td>
        </tr>
      ''';
    }

    String logoHtml = '';
    if (logoBase64.isNotEmpty) {
      logoHtml = '<div style="text-align: center; margin-bottom: 15px;"><img src="$logoBase64" style="max-height: 75px; max-width: 240px;" /></div>';
    }

    final htmlContent = '''
    <!DOCTYPE html>
    <html dir="rtl" lang="ar">
    <head>
      <meta charset="utf-8">
      <title>كشف حركة الصنف - $itemName</title>
      <style>
        @page { size: A4; margin: 12mm; }
        body { font-family: 'Cairo', 'Segoe UI', Tahoma, sans-serif; color: #0f172a; margin: 0; padding: 10px; background: #fff; font-size: 13px; }
        .header-title { text-align: center; margin-bottom: 15px; }
        .header-title h2 { margin: 0; color: #0369a1; font-size: 22px; }
        .header-title p { margin: 4px 0 0 0; color: #64748b; font-size: 13px; }
        
        .item-info-box { background: #f8fafc; border: 1px solid #e2e8f0; border-radius: 8px; padding: 12px; margin-bottom: 15px; }
        .info-grid { display: grid; grid-template-columns: repeat(4, 1fr); gap: 10px; }
        .info-item { font-size: 13px; }
        .info-item span { font-weight: bold; color: #0284c7; }

        .summary-cards { display: grid; grid-template-columns: repeat(4, 1fr); gap: 10px; margin-bottom: 18px; }
        .card { padding: 10px; border-radius: 6px; text-align: center; }
        .card-in { background: #dcfce7; color: #166534; border: 1px solid #bbf7d0; }
        .card-out { background: #fee2e2; color: #991b1b; border: 1px solid #fecaca; }
        .card-bal { background: #e0f2fe; color: #075985; border: 1px solid #bae6fd; }
        .card-cnt { background: #f3e8ff; color: #6b21a8; border: 1px solid #e9d5ff; }
        .card-val { font-size: 18px; font-weight: bold; margin-top: 4px; }

        table.data-table { width: 100%; border-collapse: collapse; margin-top: 10px; font-size: 12px; }
        table.data-table th { background: #0f172a; color: #fff; padding: 8px 10px; border: 1px solid #1e293b; text-align: right; }
        table.data-table td { padding: 8px 10px; border: 1px solid #cbd5e1; text-align: right; }
        table.data-table tr:nth-child(even) { background: #f8fafc; }

        .footer-sig { margin-top: 30px; width: 100%; display: flex; justify-content: space-between; text-align: center; }
        .sig-box { width: 30%; border-top: 1px dashed #94a3b8; padding-top: 8px; font-weight: bold; color: #475569; }
      </style>
    </head>
    <body>
      $logoHtml
      <div class="header-title">
        <h2>تقرير كشف حركة صنف تفصيلي</h2>
        <p>تاريخ الطباعة واستخراج التقرير: $nowStr</p>
      </div>

      <div class="item-info-box">
        <div class="info-grid">
          <div class="info-item">اسم الصنف: <span>$itemName</span></div>
          <div class="info-item">الباركود: <span>$barcode</span></div>
          <div class="info-item">الوحدة: <span>$unitName</span></div>
          <div class="info-item">سعر البيع: <span>${currencyFormat(salesPrice)}</span></div>
        </div>
        <div style="margin-top: 8px; font-size: 12px; color: #475569;">
          الفترة الزمنية من: <b>${_startDateController.text}</b> إلى: <b>${_endDateController.text}</b>
        </div>
      </div>

      <div class="summary-cards">
        <div class="card card-in">
          <div>إجمالي الوارد (+)</div>
          <div class="card-val">+$totalIn $unitName</div>
        </div>
        <div class="card card-out">
          <div>إجمالي المنصرف (-)</div>
          <div class="card-val">-$totalOut $unitName</div>
        </div>
        <div class="card card-bal">
          <div>صافي رصيد الصنف</div>
          <div class="card-val">$balance $unitName</div>
        </div>
        <div class="card card-cnt">
          <div>عدد الحركات</div>
          <div class="card-val">${_movements.length} حركة</div>
        </div>
      </div>

      <table class="data-table">
        <thead>
          <tr>
            <th style="text-align: center;">#</th>
            <th>رقم الحركة</th>
            <th>نوع الحركة</th>
            <th>التاريخ</th>
            <th style="text-align: center;">الكمية</th>
            <th style="text-align: left;">السعر</th>
            <th style="text-align: left;">الإجمالي</th>
            <th style="text-align: center;">الرصيد التراكمي</th>
            <th>البائع / المستخدم</th>
          </tr>
        </thead>
        <tbody>
          $rowsHtml
        </tbody>
      </table>

      <div class="footer-sig">
        <div class="sig-box">منظم التقرير</div>
        <div class="sig-box">أمين المخزن / المشرف</div>
        <div class="sig-box">اعتماد الإدارة</div>
      </div>
    </body>
    </html>
    ''';

    PrintService.printHtml(htmlContent);
  }

  void _printItemBarcodeLabel(ApiService apiService, {Map<String, dynamic>? itemMap}) {
    final info = itemMap ?? _itemInfo;
    String barcode = (info['barcode'] ?? _queryController.text).toString().trim();
    String itemName = (info['itemName'] ?? (info['item_name'] ?? _queryController.text)).toString().trim();
    double salesPrice = (info['salesPrice'] as num? ?? (info['unitPrice'] as num? ?? (info['sales_price'] as num? ?? 0.0))).toDouble();
    String unitName = (info['unitName'] ?? (info['unit_name'] ?? 'حبة')).toString();

    // Look for best match in apiService.items
    ItemModel? matchedItem;
    if (barcode.isNotEmpty) {
      final m = apiService.items.where((i) => i.barcode.trim() == barcode).toList();
      if (m.isNotEmpty) matchedItem = m.first;
    }
    if (matchedItem == null && itemName.isNotEmpty) {
      final m = apiService.items.where((i) => i.itemName.trim() == itemName || i.itemName.contains(itemName)).toList();
      if (m.isNotEmpty) matchedItem = m.first;
    }

    ItemModel itemToPrint;
    if (matchedItem != null) {
      itemToPrint = matchedItem;
    } else {
      if (barcode.isEmpty && itemName.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('الرجاء اختيار أو البحث عن صنف أولاً لطباعة ملصق الباركود', style: TextStyle(fontFamily: 'Cairo')),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }
      itemToPrint = ItemModel(
        barcode: barcode.isNotEmpty ? barcode : '123456',
        itemName: itemName.isNotEmpty ? itemName : 'صنف غير محدد',
        salesPrice: salesPrice,
        unitName: unitName,
        cost: 0,
        groupId: 0,
        itemId: 0,
        unityId: 1,
        moneyId: 1,
        isActive: true,
      );
    }

    BarcodeLabelService.showQuickBarcodePrintDialog(
      context: context,
      item: itemToPrint,
      onOpenDesigner: () {
        showDialog(
          context: context,
          builder: (dialogContext) => Dialog(
            backgroundColor: const Color(0xFF0F172A),
            insetPadding: const EdgeInsets.all(16),
            child: SizedBox(
              width: 1200,
              height: 800,
              child: BarcodePrintView(initialItem: itemToPrint),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final apiService = Provider.of<ApiService>(context);
    final allItems = apiService.items;

    final totalIn = _summary['totalIncoming'] ?? 0;
    final totalOut = _summary['totalOutgoing'] ?? 0;
    final balance = _summary['currentBalance'] ?? 0;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFF0F172A),
        body: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // --- HEADER BAR ---
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.blueAccent.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.blueAccent.withOpacity(0.3)),
                        ),
                        child: const Icon(Icons.history_rounded, color: Colors.blueAccent, size: 28),
                      ),
                      const SizedBox(width: 14),
                      const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'كشف حركة صنف تفصيلي (سجل الحركة)',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              fontFamily: 'Cairo',
                            ),
                          ),
                          Text(
                            'استعلام بالباركود أو الاسم بالفترة الزمنية لحساب رصيد الصنف والوارد والمنصرف',
                            style: TextStyle(color: Colors.white54, fontSize: 13, fontFamily: 'Cairo'),
                          ),
                        ],
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.teal.shade700,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        icon: const Icon(Icons.qr_code_2_rounded, size: 20),
                        label: const Text('طباعة ملصق الباركود للصنف', style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
                        onPressed: (_itemInfo.isEmpty && _queryController.text.trim().isEmpty)
                            ? null
                            : () => _printItemBarcodeLabel(apiService),
                      ),
                      const SizedBox(width: 10),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blueAccent,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        icon: const Icon(Icons.print_rounded, size: 20),
                        label: const Text('طباعة كشف الحركة A4', style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
                        onPressed: _movements.isEmpty ? null : _printReport,
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // --- SEARCH & FILTER BAR ---
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.white10),
                ),
                child: Row(
                  children: [
                    // 1. Item AutoComplete Search Input
                    Expanded(
                      flex: 4,
                      child: Autocomplete<ItemModel>(
                        displayStringForOption: (item) => '${item.itemName} (${item.barcode})',
                        optionsBuilder: (TextEditingValue textEditingValue) {
                          if (textEditingValue.text.isEmpty) {
                            return const Iterable<ItemModel>.empty();
                          }
                          return allItems.where((ItemModel item) {
                            return item.itemName.toLowerCase().contains(textEditingValue.text.toLowerCase()) ||
                                item.barcode.contains(textEditingValue.text);
                          });
                        },
                        onSelected: (ItemModel selection) {
                          _queryController.text = selection.barcode;
                          _fetchReport();
                        },
                        fieldViewBuilder: (context, controller, focusNode, onEditingComplete) {
                          if (_queryController.text.isNotEmpty && controller.text.isEmpty) {
                            controller.text = _queryController.text;
                          }
                          return TextField(
                            controller: controller,
                            focusNode: focusNode,
                            style: const TextStyle(color: Colors.white, fontFamily: 'Cairo'),
                            onChanged: (val) => _queryController.text = val,
                            decoration: InputDecoration(
                              labelText: 'البحث برقم الصنف / الباركود / الاسم',
                              labelStyle: const TextStyle(color: Colors.white70, fontFamily: 'Cairo'),
                              hintText: 'ادخل الباركود أو اسم الصنف...',
                              hintStyle: const TextStyle(color: Colors.white30, fontFamily: 'Cairo', fontSize: 12),
                              prefixIcon: const Icon(Icons.qr_code_scanner_rounded, color: Colors.blueAccent),
                              filled: true,
                              fillColor: const Color(0xFF0F172A),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(width: 12),

                    // 2. Start Date Picker
                    Expanded(
                      flex: 2,
                      child: TextField(
                        controller: _startDateController,
                        readOnly: true,
                        style: const TextStyle(color: Colors.white, fontFamily: 'Cairo', fontSize: 13),
                        onTap: () => _selectDate(context, _startDateController),
                        decoration: InputDecoration(
                          labelText: 'من تاريخ',
                          labelStyle: const TextStyle(color: Colors.white70, fontFamily: 'Cairo'),
                          prefixIcon: const Icon(Icons.calendar_today_rounded, color: Colors.blueAccent, size: 18),
                          filled: true,
                          fillColor: const Color(0xFF0F172A),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),

                    // 3. End Date Picker
                    Expanded(
                      flex: 2,
                      child: TextField(
                        controller: _endDateController,
                        readOnly: true,
                        style: const TextStyle(color: Colors.white, fontFamily: 'Cairo', fontSize: 13),
                        onTap: () => _selectDate(context, _endDateController),
                        decoration: InputDecoration(
                          labelText: 'إلى تاريخ',
                          labelStyle: const TextStyle(color: Colors.white70, fontFamily: 'Cairo'),
                          prefixIcon: const Icon(Icons.event_rounded, color: Colors.blueAccent, size: 18),
                          filled: true,
                          fillColor: const Color(0xFF0F172A),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),

                    // 4. Fetch Button
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.teal.shade700,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      icon: _isLoading
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.search_rounded),
                      label: const Text('عرض الحركة', style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
                      onPressed: _isLoading ? null : _fetchReport,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),

              // --- ITEM INFO RIBBON WITH DIRECT BARCODE PRINT ---
              if (_itemInfo.isNotEmpty) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E293B),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.tealAccent.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: Colors.tealAccent.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Icon(Icons.inventory_2_rounded, color: Colors.tealAccent, size: 20),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Wrap(
                          spacing: 20,
                          runSpacing: 6,
                          children: [
                            Text(
                              'الصنف: ${_itemInfo['itemName'] ?? ''}',
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontFamily: 'Cairo', fontSize: 13),
                            ),
                            Text(
                              'الباركود: ${_itemInfo['barcode'] ?? ''}',
                              style: const TextStyle(color: Colors.amberAccent, fontFamily: 'Cairo', fontSize: 13, fontWeight: FontWeight.bold),
                            ),
                            Text(
                              'الوحدة: ${_itemInfo['unitName'] ?? 'حبة'}',
                              style: const TextStyle(color: Colors.white70, fontFamily: 'Cairo', fontSize: 13),
                            ),
                            Text(
                              'سعر البيع: ${currencyFormat((_itemInfo['salesPrice'] as num? ?? 0.0).toDouble())}',
                              style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold, fontFamily: 'Cairo', fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.tealAccent.shade700,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        icon: const Icon(Icons.qr_code_2_rounded, size: 18),
                        label: const Text(
                          'طباعة ملصق الباركود',
                          style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 12),
                        ),
                        onPressed: () => _printItemBarcodeLabel(apiService),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
              ],

              // --- STATS CARDS BAR ---
              Row(
                children: [
                  Expanded(
                    child: _buildSummaryCard(
                      title: 'إجمالي الوارد (+)',
                      value: '+$totalIn ${_itemInfo['unitName'] ?? 'حبة'}',
                      icon: Icons.move_to_inbox_rounded,
                      color: Colors.greenAccent,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildSummaryCard(
                      title: 'إجمالي المنصرف (-)',
                      value: '-$totalOut ${_itemInfo['unitName'] ?? 'حبة'}',
                      icon: Icons.outbox_rounded,
                      color: Colors.redAccent,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildSummaryCard(
                      title: 'صافي رصيد الصنف التراكمي',
                      value: '$balance ${_itemInfo['unitName'] ?? 'حبة'}',
                      icon: Icons.inventory_2_rounded,
                      color: Colors.blueAccent,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildSummaryCard(
                      title: 'إجمالي الحركات',
                      value: '${_movements.length} حركة',
                      icon: Icons.format_list_numbered_rounded,
                      color: Colors.purpleAccent,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // --- DATA TABLE ---
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E293B),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.white10),
                  ),
                  child: Column(
                    children: [
                      // Table Header Row
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        decoration: const BoxDecoration(
                          color: Color(0xFF0F172A),
                          borderRadius: BorderRadius.only(
                            topLeft: Radius.circular(14),
                            topRight: Radius.circular(14),
                          ),
                        ),
                        child: const Row(
                          children: [
                            Expanded(flex: 1, child: Text('#', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontFamily: 'Cairo'))),
                            Expanded(flex: 2, child: Text('رقم الحركة', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontFamily: 'Cairo'))),
                            Expanded(flex: 2, child: Text('نوع الحركة', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontFamily: 'Cairo'))),
                            Expanded(flex: 2, child: Text('التاريخ', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontFamily: 'Cairo'))),
                            Expanded(flex: 2, child: Text('الكمية', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontFamily: 'Cairo'), textAlign: TextAlign.center)),
                            Expanded(flex: 2, child: Text('السعر', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontFamily: 'Cairo'), textAlign: TextAlign.end)),
                            Expanded(flex: 2, child: Text('الإجمالي', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontFamily: 'Cairo'), textAlign: TextAlign.end)),
                            Expanded(flex: 2, child: Text('الرصيد التراكمي', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontFamily: 'Cairo'), textAlign: TextAlign.center)),
                            Expanded(flex: 2, child: Text('المستخدم', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontFamily: 'Cairo'))),
                            const SizedBox(width: 44, child: Text('طباعة', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontFamily: 'Cairo'), textAlign: TextAlign.center)),
                          ],
                        ),
                      ),
                      const Divider(color: Colors.white10, height: 1),

                      // Rows List
                      Expanded(
                        child: _isLoading
                            ? const Center(child: CircularProgressIndicator(color: Colors.blueAccent))
                            : (_movements.isEmpty
                                ? const Center(
                                    child: Text(
                                      'لا توجد حركات مسجلة بهذا الصنف في هذه الفترة',
                                      style: TextStyle(color: Colors.white38, fontFamily: 'Cairo', fontSize: 15),
                                    ),
                                  )
                                : ListView.separated(
                                    itemCount: _movements.length,
                                    separatorBuilder: (context, index) => const Divider(color: Colors.white10, height: 1),
                                    itemBuilder: (context, index) {
                                      final m = _movements[index];
                                      final isAdd = m['isAddition'] == true;
                                      final rawQty = m['rawQuantity'] ?? 0;
                                      final price = (m['unitPrice'] as num? ?? 0.0).toDouble();
                                      final total = (m['totalAmount'] as num? ?? 0.0).toDouble();
                                      final runBal = m['runningBalance'] ?? 0;
                                      final userName = m['userName'] ?? 'مستخدم 1';

                                      return Padding(
                                        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                                        child: Row(
                                          children: [
                                            Expanded(flex: 1, child: Text('${index + 1}', style: const TextStyle(color: Colors.white38, fontSize: 13))),
                                            Expanded(flex: 2, child: Text('# ${m['transNumber']}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
                                            Expanded(
                                              flex: 2,
                                              child: Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                                decoration: BoxDecoration(
                                                  color: isAdd ? Colors.green.withValues(alpha: 0.15) : Colors.redAccent.withValues(alpha: 0.15),
                                                  borderRadius: BorderRadius.circular(4),
                                                ),
                                                child: Text(
                                                  '${m['typeName']}',
                                                  style: TextStyle(
                                                    color: isAdd ? Colors.greenAccent : Colors.redAccent,
                                                    fontSize: 12,
                                                    fontFamily: 'Cairo',
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                              ),
                                            ),
                                            Expanded(flex: 2, child: Text('${m['date']}', style: const TextStyle(color: Colors.white70))),
                                            Expanded(
                                              flex: 2,
                                              child: Text(
                                                isAdd ? '+$rawQty' : '-$rawQty',
                                                textAlign: TextAlign.center,
                                                style: TextStyle(
                                                  color: isAdd ? Colors.greenAccent : Colors.redAccent,
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 15,
                                                ),
                                              ),
                                            ),
                                            Expanded(flex: 2, child: Text(currencyFormat(price), textAlign: TextAlign.end, style: const TextStyle(color: Colors.white70))),
                                            Expanded(flex: 2, child: Text(currencyFormat(total), textAlign: TextAlign.end, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
                                            Expanded(
                                              flex: 2,
                                              child: Text(
                                                '$runBal',
                                                textAlign: TextAlign.center,
                                                style: const TextStyle(color: Colors.blueAccent, fontWeight: FontWeight.bold, fontSize: 16),
                                              ),
                                            ),
                                            Expanded(flex: 2, child: Text(userName, style: const TextStyle(color: Colors.cyanAccent, fontFamily: 'Cairo', fontSize: 13))),
                                            SizedBox(
                                              width: 44,
                                              child: Center(
                                                child: IconButton(
                                                  icon: const Icon(Icons.qr_code_2_rounded, color: Colors.tealAccent, size: 20),
                                                  tooltip: 'طباعة ملصق الباركود للصنف',
                                                  onPressed: () => _printItemBarcodeLabel(apiService, itemMap: m),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      );
                                    },
                                  )),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSummaryCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withOpacity(0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(color: Colors.white60, fontSize: 11, fontFamily: 'Cairo')),
                const SizedBox(height: 2),
                Text(value, style: TextStyle(color: color, fontSize: 16, fontWeight: FontWeight.bold, fontFamily: 'Cairo')),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
