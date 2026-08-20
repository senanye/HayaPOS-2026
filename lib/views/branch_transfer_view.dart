import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart' hide TextDirection;
import '../services/api_service.dart';
import '../services/print_service.dart';
import '../models/item.dart';
import '../models/transaction.dart';

class BranchTransferView extends StatefulWidget {
  const BranchTransferView({super.key});

  @override
  State<BranchTransferView> createState() => _BranchTransferViewState();
}

class _BranchTransferViewState extends State<BranchTransferView> {
  final TextEditingController _dateController = TextEditingController();
  final TextEditingController _noteController = TextEditingController();
  
  final TextEditingController _qtyController = TextEditingController(text: '1');
  final TextEditingController _costController = TextEditingController(text: '0.0');
  final TextEditingController _unitController = TextEditingController(text: 'حبة');

  ItemModel? _selectedItem;
  final List<Map<String, dynamic>> _transferItems = [];
  final List<TransactionHeaderModel> _localPendingTransfersQueue = [];

  List<Map<String, dynamic>> _branches = [];
  Map<String, dynamic>? _fromBranch;
  Map<String, dynamic>? _toBranch;

  bool _isLoading = false;

  List<dynamic> _pendingTransfers = [];
  bool _isLoadingPending = false;
  int _selectedIncomingPointNo = 0; // 0 = All receiving branches

  @override
  void initState() {
    super.initState();
    _dateController.text = DateFormat('yyyy-MM-dd').format(DateTime.now());
    _loadBranches();
    _loadPendingTransfers();
  }

  @override
  void dispose() {
    _dateController.dispose();
    _noteController.dispose();
    _qtyController.dispose();
    _costController.dispose();
    _unitController.dispose();
    super.dispose();
  }

  Future<void> _loadBranches() async {
    final apiService = Provider.of<ApiService>(context, listen: false);
    final pointsRaw = await apiService.fetchRemotePoints();
    final currentPointNo = apiService.pointNo;
    final currentPointName = apiService.pointName;

    List<Map<String, dynamic>> normalizedPoints = [];
    if (pointsRaw.isNotEmpty) {
      normalizedPoints = pointsRaw.map((p) {
        final pNo = (p['fldPointNO'] ?? p['pointNo'] as num?)?.toInt() ?? 1;
        final pName = p['fldName'] ?? p['pointName'] ?? 'فرع $pNo';
        final pDs = p['dataSource'] ?? p['DataSource'] ?? '';
        return {
          'fldPointNO': pNo,
          'pointNo': pNo,
          'fldName': pName,
          'pointName': pName,
          'dataSource': pDs,
        };
      }).toList();
    } else {
      normalizedPoints = [
        {'fldPointNO': 1, 'pointNo': 1, 'fldName': 'الفرع الرئيسي - الإدارة', 'pointName': 'الفرع الرئيسي - الإدارة'},
        {'fldPointNO': 2, 'pointNo': 2, 'fldName': 'فرع الأمانة / حده', 'pointName': 'فرع الأمانة / حده'},
        {'fldPointNO': 3, 'pointNo': 3, 'fldName': 'فرع الستين / صنعاء', 'pointName': 'فرع الستين / صنعاء'},
        {'fldPointNO': 4, 'pointNo': 4, 'fldName': 'فرع تعز / الحوبان', 'pointName': 'فرع تعز / الحوبان'},
        {'fldPointNO': 5, 'pointNo': 5, 'fldName': 'فرع عدن / المنصورة', 'pointName': 'فرع عدن / المنصورة'},
      ];
    }

    setState(() {
      _branches = normalizedPoints;
      _selectedIncomingPointNo = currentPointNo;

      // Force source branch (_fromBranch) to current branch
      final currentBranchIndex = _branches.indexWhere((b) => (b['fldPointNO'] as num?)?.toInt() == currentPointNo);
      if (currentBranchIndex != -1) {
        _fromBranch = _branches[currentBranchIndex];
      } else {
        _fromBranch = {
          'fldPointNO': currentPointNo,
          'pointNo': currentPointNo,
          'fldName': currentPointName,
          'pointName': currentPointName,
        };
        _branches.insert(0, _fromBranch!);
      }

      // Filter destination branch (_toBranch) options to strictly exclude current branch
      final availableToBranches = _branches.where((b) => (b['fldPointNO'] as num?)?.toInt() != currentPointNo).toList();
      if (availableToBranches.isNotEmpty) {
        _toBranch = availableToBranches.first;
      } else {
        _toBranch = null;
      }
    });

    _loadPendingTransfers();
  }

  Future<void> _loadPendingTransfers() async {
    setState(() => _isLoadingPending = true);
    try {
      final apiService = Provider.of<ApiService>(context, listen: false);
      final list = await apiService.fetchPendingTransfers(_selectedIncomingPointNo);
      setState(() {
        _pendingTransfers = list;
      });
    } catch (e) {
      if (kDebugMode) print("Error loading pending transfers: $e");
    } finally {
      setState(() => _isLoadingPending = false);
    }
  }

  Future<void> _syncTransfersWithMainServer() async {
    setState(() => _isLoadingPending = true);
    final apiService = Provider.of<ApiService>(context, listen: false);

    int uploadedCount = 0;
    int failedCount = 0;
    String? errorReason;

    try {
      // 1. Process local transfers queue and push to server with atomic safety
      final List<TransactionHeaderModel> pendingList = List.from(_localPendingTransfersQueue);

      for (int i = 0; i < pendingList.length; i++) {
        final transferReq = pendingList[i];
        try {
          // Attempt push to server
          await apiService.saveTransaction(transferReq);
          uploadedCount++;
          _localPendingTransfersQueue.remove(transferReq);
        } catch (e) {
          failedCount++;
          errorReason = e.toString();
          // ATOMIC ROLLBACK SAFETY: STOP remaining uploads on connection failure or power loss
          break;
        }
      }

      // Refresh incoming pending transfers list from server
      final currentPointNo = apiService.pointNo;
      final currentList = await apiService.fetchPendingTransfers(currentPointNo);

      setState(() {
        _pendingTransfers = currentList;
        _isLoadingPending = false;
      });

      if (mounted) {
        if (failedCount > 0) {
          showDialog(
            context: context,
            builder: (context) => Directionality(
              textDirection: TextDirection.rtl,
              child: AlertDialog(
                backgroundColor: const Color(0xFF1E293B),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                title: const Row(
                  children: [
                    Icon(Icons.warning_amber_rounded, color: Colors.orangeAccent, size: 28),
                    SizedBox(width: 10),
                    Text(
                      'تم إلغاء النقل وتوقف المزامنة ⚠️',
                      style: TextStyle(color: Colors.white, fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                  ],
                ),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'حدث انقطاع في الاتصال بالشبكة أو الكهرباء أثناء رفع حركات التحويل المخزني إلى السيرفر الرئيسي.',
                      style: TextStyle(color: Colors.white70, fontFamily: 'Cairo', fontSize: 13),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0F172A),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.orangeAccent.withOpacity(0.4)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('إجراء التراجع الذاتي والحماية (Rollback):', style: TextStyle(color: Colors.orangeAccent, fontWeight: FontWeight.bold, fontFamily: 'Cairo', fontSize: 12)),
                          const SizedBox(height: 4),
                          Text('تم رفع وتأكيد $uploadedCount سند بنجاح، بينما تم إلغاء رفع الحركات غير المكتملة وحفظها محلياً لحمايتها من الضياع.', style: const TextStyle(color: Colors.white, fontFamily: 'Cairo', fontSize: 12)),
                          if (errorReason != null) ...[
                            const SizedBox(height: 6),
                            Text('سبب التوقف: $errorReason', style: const TextStyle(color: Colors.redAccent, fontSize: 11, fontFamily: 'Cairo')),
                          ]
                        ],
                      ),
                    ),
                  ],
                ),
                actions: [
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.orange[800]),
                    onPressed: () => Navigator.pop(context),
                    child: const Text('إغلاق', style: TextStyle(color: Colors.white, fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),
          );
        } else {
          showDialog(
            context: context,
            builder: (context) => Directionality(
              textDirection: TextDirection.rtl,
              child: AlertDialog(
                backgroundColor: const Color(0xFF1E293B),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                title: const Row(
                  children: [
                    Icon(Icons.cloud_upload_rounded, color: Colors.greenAccent, size: 28),
                    SizedBox(width: 10),
                    Text(
                      'تم نقل المزامنة للسيرفر بنجاح 🚀',
                      style: TextStyle(color: Colors.white, fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 17),
                    ),
                  ],
                ),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'تم نقل وحفظ حركات التحويلات المخزنية من قاعدة بيانات النقطة المحلية إلى السيرفر الرئيسي في الجدولين [Main] و [details] بنجاح!',
                      style: TextStyle(color: Colors.white70, fontFamily: 'Cairo', fontSize: 13),
                    ),
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0F172A),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.greenAccent.withOpacity(0.4)),
                      ),
                      child: Column(
                        children: [
                          const Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('اتجاه نقل البيانات:', style: TextStyle(color: Colors.white70, fontFamily: 'Cairo', fontSize: 12)),
                              Text('من النقطة المحلية ➔ إلى السيرفر الرئيسي 📤', style: TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold, fontFamily: 'Cairo', fontSize: 11)),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('حركات التحويل المنقولة للسيرفر:', style: TextStyle(color: Colors.white70, fontFamily: 'Cairo', fontSize: 12)),
                              Text('$uploadedCount سند تحويل', style: const TextStyle(color: Colors.amberAccent, fontWeight: FontWeight.bold, fontFamily: 'Cairo', fontSize: 12)),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('التحويلات الواردة للنقطة الحالية (#$currentPointNo):', style: const TextStyle(color: Colors.white70, fontFamily: 'Cairo', fontSize: 12)),
                              Text('${currentList.length} سند تحويل', style: const TextStyle(color: Colors.cyanAccent, fontWeight: FontWeight.bold, fontFamily: 'Cairo', fontSize: 12)),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                actions: [
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent),
                    onPressed: () => Navigator.pop(context),
                    child: const Text('حسناً', style: TextStyle(color: Colors.white, fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),
          );
        }
      }
    } catch (e) {
      setState(() => _isLoadingPending = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ أثناء رفع المزامنة للسيرفر الرئيسي: $e', style: const TextStyle(fontFamily: 'Cairo')),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _confirmPendingTransfer(Map<String, dynamic> pendingTransfer) async {
    setState(() => _isLoadingPending = true);
    try {
      final apiService = Provider.of<ApiService>(context, listen: false);
      final double transNum = (pendingTransfer['transNumber'] as num).toDouble();
      final String fromBranch = pendingTransfer['fromBranchName'] ?? 'الفرع المصدر';
      final items = (pendingTransfer['items'] as List<dynamic>?) ?? [];

      // 1. Create local positive incoming transaction for receiving branch (Branch 2)
      final int currentPointNo = apiService.pointNo;
      final int userId = apiService.currentUser?.userId ?? 1;
      final String dateStr = DateTime.now().toString().split(' ')[0];

      final incomingDetails = items.map((item) {
        final double qty = (item['quantity'] as num).toDouble().abs();
        final double price = (item['salesPrice'] as num).toDouble();
        return TransactionDetailModel(
          barcode: item['barcode'],
          itemName: item['itemName'],
          quantity: qty.round(),
          salesPrice: price,
          discount: 0,
          taxTotal: 0,
          totalItem: (qty * price).round(),
        );
      }).toList();

      final incomingReq = TransactionHeaderModel(
        date: dateStr,
        description: 'استلام تحويل مخزني وارد من [$fromBranch] - فاتورة رقم #${transNum.toInt()}',
        pointNo: currentPointNo,
        toPointNo: currentPointNo,
        userId: userId,
        payCash: 1,
        transType: 28,
        moneyId: 1,
        status: 1, // 1 = Completed / Received
        details: incomingDetails,
      );

      // Save local incoming transaction
      await apiService.saveTransaction(incomingReq);

      // 2. Notify Main Server to update transfer status to Completed (fldStatus = 1) and create new supply voucher
      await apiService.confirmTransfer(transNum, toPointNo: currentPointNo);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تم تأكيد استلام البضاعة من $fromBranch بنجاح، وتوليد سند توريد جديد برقم جديد لنقطة البيع الحالية وتحديث الحالة fldStatus=1!', style: const TextStyle(fontFamily: 'Cairo')),
            backgroundColor: Colors.green,
          ),
        );
      }

      await _loadPendingTransfers();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ أثناء تأكيد الاستلام: $e', style: const TextStyle(fontFamily: 'Cairo')),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() => _isLoadingPending = false);
    }
  }

  void _addItemToTransfer() {
    if (_selectedItem == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('الرجاء اختيار صنف أولاً', style: TextStyle(fontFamily: 'Cairo')),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final double qty = double.tryParse(_qtyController.text.trim()) ?? 1.0;
    final double cost = double.tryParse(_costController.text.trim()) ?? _selectedItem!.cost;
    final String unit = _unitController.text.trim().isEmpty ? _selectedItem!.unitName : _unitController.text.trim();

    if (qty <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('الرجاء إدخال كمية أكبر من صفر', style: TextStyle(fontFamily: 'Cairo')),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() {
      _transferItems.add({
        'barcode': _selectedItem!.barcode,
        'itemName': _selectedItem!.itemName,
        'unitName': unit,
        'quantity': qty,
        'costPrice': cost,
        'totalCost': qty * cost,
      });

      // Clear input selection
      _selectedItem = null;
      _qtyController.text = '1';
      _costController.text = '0.0';
      _unitController.text = 'حبة';
    });
  }

  void _removeItem(int index) {
    setState(() {
      _transferItems.removeAt(index);
    });
  }

  double get _totalTransferAmount {
    return _transferItems.fold(0.0, (sum, item) => sum + (item['totalCost'] as double));
  }

  double get _totalTransferQty {
    return _transferItems.fold(0.0, (sum, item) => sum + (item['quantity'] as double));
  }

  Future<void> _saveTransferVouchers() async {
    if (_fromBranch == null || _toBranch == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('الرجاء تحديد الفرع المحول منه والفرع المحول إليه', style: TextStyle(fontFamily: 'Cairo')), backgroundColor: Colors.orange),
      );
      return;
    }

    if (_fromBranch!['fldPointNO'] == _toBranch!['fldPointNO']) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('لا يمكن التحويل لنفس الفرع! الرجاء اختيار فرعين مختلفين.', style: TextStyle(fontFamily: 'Cairo')), backgroundColor: Colors.orange),
      );
      return;
    }

    if (_transferItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('الرجاء إضافة أصناف لسند التحويل قبل الحفظ', style: TextStyle(fontFamily: 'Cairo')), backgroundColor: Colors.orange),
      );
      return;
    }

    setState(() => _isLoading = true);
    final apiService = Provider.of<ApiService>(context, listen: false);

    try {
      final String fromName = _fromBranch!['fldName'] ?? 'فرع ${_fromBranch!['fldPointNO']}';
      final String toName = _toBranch!['fldName'] ?? 'فرع ${_toBranch!['fldPointNO']}';
      final String userDesc = _noteController.text.trim();
      final String dateStr = _dateController.text.trim();
      final int userId = apiService.currentUser?.userId ?? 1;

      final outgoingDetails = _transferItems.map((item) {
        final double qty = (item['quantity'] as num).toDouble();
        final double cost = (item['costPrice'] as num).toDouble();
        final int negQty = (-qty).round();
        return TransactionDetailModel(
          barcode: item['barcode'],
          itemName: item['itemName'],
          quantity: negQty,
          salesPrice: cost,
          discount: 0,
          taxTotal: 0,
          totalItem: (negQty * cost).round(),
        );
      }).toList();

      final outgoingReq = TransactionHeaderModel(
        date: dateStr,
        description: 'تحويل مخزني منصرف إلى فرع [$toName]' + (userDesc.isNotEmpty ? ' - $userDesc' : ''),
        pointNo: _fromBranch!['fldPointNO'] ?? 1,
        toPointNo: _toBranch!['fldPointNO'] ?? 2,
        userId: userId,
        payCash: 1,
        transType: 28,
        moneyId: apiService.defaultMoneyId,
        status: 0, // 0 = Pending In-Transit
        details: outgoingDetails,
      );

      String transNumStr = 'جديد';
      try {
        final res1 = await apiService.saveTransaction(outgoingReq);
        transNumStr = res1['transNumber']?.toString() ?? 'تم';
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('تم إصدار ونقل فاتورة التحويل للسيرفر بنجاح! رقم الحركة: $transNumStr', style: const TextStyle(fontFamily: 'Cairo')),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (networkErr) {
        // If offline or network dropped during save, save to local queue
        _localPendingTransfersQueue.add(outgoingReq);
        transNumStr = 'مُعلقة (محلياً)';
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('تم حفظ حركة التحويل محلياً بالنقطة 💾 (سيتم رفعها للسيرفر عند الضغط على زر "رفع ونقل التحويلات للسيرفر الرئيسي")', style: TextStyle(fontFamily: 'Cairo')),
              backgroundColor: Colors.orange,
            ),
          );
        }
      }

      final itemsSnapshot = List<Map<String, dynamic>>.from(_transferItems);

      _printTransferInvoice(
        transNumber: transNumStr,
        fromBranchName: fromName,
        toBranchName: toName,
        customItems: itemsSnapshot,
      );

      setState(() {
        _transferItems.clear();
        _noteController.clear();
      });

      _loadPendingTransfers();

    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ أثناء حفظ فاتورة التحويل: $e', style: const TextStyle(fontFamily: 'Cairo')),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _printTransferInvoice({
    String transNumber = 'جديد',
    String? fromBranchName,
    String? toBranchName,
    List<Map<String, dynamic>>? customItems,
  }) {
    final String fromName = fromBranchName ?? (_fromBranch?['fldName'] ?? 'الفرع الأول');
    final String toName = toBranchName ?? (_toBranch?['fldName'] ?? 'الفرع الثاني');
    final apiService = Provider.of<ApiService>(context, listen: false);
    final String userName = apiService.currentUser?.userName ?? 'مستخدم النظام';

    final List<Map<String, dynamic>> itemsList = customItems ?? List<Map<String, dynamic>>.from(_transferItems);

    double totalQty = 0;
    double totalAmount = 0;

    StringBuffer rowsHtml = StringBuffer();
    for (int i = 0; i < itemsList.length; i++) {
      final item = itemsList[i];
      final double qty = (item['quantity'] as num?)?.toDouble() ?? 0;
      final double cost = (item['costPrice'] as num?)?.toDouble() ?? 0;
      final double total = (item['totalCost'] as num?)?.toDouble() ?? (qty * cost);

      totalQty += qty;
      totalAmount += total;

      rowsHtml.write('''
        <tr>
          <td style="text-align: center;">${i + 1}</td>
          <td>${item['barcode'] ?? ''}</td>
          <td>${item['itemName'] ?? ''}</td>
          <td style="text-align: center;">${item['unitName'] ?? 'حبة'}</td>
          <td style="text-align: center; font-weight: bold;">$qty</td>
          <td style="text-align: left;">${cost.toStringAsFixed(2)}</td>
          <td style="text-align: left; font-weight: bold;">${total.toStringAsFixed(2)}</td>
        </tr>
      ''');
    }

    final htmlContent = '''
    <!DOCTYPE html>
    <html dir="rtl" lang="ar">
    <head>
      <meta charset="utf-8">
      <title>فاتورة تحويل مخزني - $transNumber</title>
      <style>
        @page { size: A4; margin: 12mm; }
        body { font-family: 'Cairo', 'Segoe UI', Tahoma, sans-serif; color: #0f172a; margin: 0; padding: 10px; background: #fff; font-size: 13px; }
        .header { text-align: center; border-bottom: 2px solid #0284c7; padding-bottom: 12px; margin-bottom: 15px; }
        .header h2 { margin: 0; color: #0369a1; font-size: 22px; }
        .header p { margin: 4px 0 0 0; color: #64748b; font-size: 13px; }
        .transfer-boxes { display: flex; justify-content: space-between; gap: 15px; margin-bottom: 15px; }
        .box { flex: 1; background: #f8fafc; border: 1px solid #cbd5e1; border-radius: 8px; padding: 10px; }
        .box-title { font-size: 11px; color: #64748b; margin-bottom: 4px; }
        .box-value { font-size: 15px; font-weight: bold; color: #0f172a; }
        table.data-table { width: 100%; border-collapse: collapse; margin-top: 15px; font-size: 12px; }
        table.data-table th { background: #0f172a; color: #fff; padding: 8px 10px; border: 1px solid #1e293b; text-align: right; }
        table.data-table td { padding: 8px 10px; border: 1px solid #cbd5e1; text-align: right; }
        table.data-table tr:nth-child(even) { background: #f8fafc; }
        .total-card { margin-top: 15px; background: #e0f2fe; border: 1px solid #38bdf8; border-radius: 8px; padding: 12px; font-size: 14px; font-weight: bold; color: #0369a1; display: flex; justify-content: space-between; }
        .footer-sig { margin-top: 30px; display: flex; justify-content: space-between; text-align: center; }
        .sig-box { width: 30%; border-top: 1px dashed #94a3b8; padding-top: 5px; color: #475569; font-weight: bold; }
      </style>
    </head>
    <body>
      <div class="header">
        <h2>سند تحويل مخزني بين الفروع</h2>
        <p>نظام نقاط البيع وإدارة الفروع POS2026</p>
      </div>

      <div class="transfer-boxes">
        <div class="box">
          <div class="box-title">الفرع المحول منه (المرسل):</div>
          <div class="box-value">$fromName</div>
        </div>
        <div class="box">
          <div class="box-title">الفرع المحول إليه (المستلم):</div>
          <div class="box-value">$toName</div>
        </div>
        <div class="box">
          <div class="box-title">رقم الفاتورة والتاريخ:</div>
          <div class="box-value">#$transNumber | ${_dateController.text}</div>
        </div>
      </div>

      <table class="data-table">
        <thead>
          <tr>
            <th style="width: 40px; text-align: center;">#</th>
            <th>الباركود</th>
            <th>اسم الصنف</th>
            <th style="text-align: center;">الوحدة</th>
            <th style="text-align: center;">الكمية</th>
            <th style="text-align: left;">سعر الكلفة</th>
            <th style="text-align: left;">الإجمالي</th>
          </tr>
        </thead>
        <tbody>
          $rowsHtml
        </tbody>
      </table>

      <div class="total-card">
        <div>إجمالي كميات الأصناف: $totalQty</div>
        <div>إجمالي قيمة التحويل المخزني: ${totalAmount.toStringAsFixed(2)} ر.ي</div>
      </div>

      <div style="margin-top: 15px; font-size: 12px; color: #64748b;">
        <strong>ملاحظات التحويل:</strong> ${_noteController.text.trim().isEmpty ? 'لا يوجد' : _noteController.text.trim()}<br>
        <strong>منفذ العملية:</strong> $userName | <strong>تاريخ الطباعة:</strong> ${DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now())}
      </div>

      <div class="footer-sig">
        <div class="sig-box">توقيع المـسـلّـم</div>
        <div class="sig-box">توقيع المستـلِـم</div>
        <div class="sig-box">اعتماد أمين المخزن</div>
      </div>
    </body>
    </html>
    ''';

    PrintService.printHtml(htmlContent);
  }

  void _printReceivedTransferInvoice(Map<String, dynamic> t) {
    final transNum = (t['transNumber'] as num).toDouble();
    final fromName = t['fromBranchName'] ?? 'فرع ${t['fromPointNo']}';
    final apiService = Provider.of<ApiService>(context, listen: false);
    final String currentBranchName = apiService.pointName;
    final String userName = apiService.currentUser?.userName ?? 'مستخدم النظام';
    final items = (t['items'] as List<dynamic>?) ?? [];
    final String dateStr = t['date'] ?? '';
    final String descStr = t['description'] ?? '';

    double totalQty = 0;
    double totalAmount = 0;

    StringBuffer rowsHtml = StringBuffer();
    for (int i = 0; i < items.length; i++) {
      final item = items[i];
      final double qty = (item['quantity'] as num?)?.toDouble().abs() ?? 0;
      final double price = (item['salesPrice'] as num?)?.toDouble() ?? 0;
      final double total = (item['totalItem'] as num?)?.toDouble() ?? (qty * price);
      final String unitStr = item['unitName'] ?? 'حبة';
      final String barcodeStr = item['barcode'] ?? '';
      final String nameStr = item['itemName'] ?? '';

      totalQty += qty;
      totalAmount += total;

      rowsHtml.write('''
        <tr>
          <td style="text-align: center;">${i + 1}</td>
          <td>$barcodeStr</td>
          <td>$nameStr</td>
          <td style="text-align: center;">$unitStr</td>
          <td style="text-align: center; font-weight: bold;">$qty</td>
          <td style="text-align: left;">${price.toStringAsFixed(2)}</td>
          <td style="text-align: left; font-weight: bold;">${total.toStringAsFixed(2)}</td>
        </tr>
      ''');
    }

    final htmlContent = '''
    <!DOCTYPE html>
    <html dir="rtl" lang="ar">
    <head>
      <meta charset="utf-8">
      <title>فاتورة استلام تحويل مخزني - #${transNum.toInt()}</title>
      <style>
        @page { size: A4; margin: 12mm; }
        body { font-family: 'Cairo', 'Segoe UI', Tahoma, sans-serif; color: #0f172a; margin: 0; padding: 10px; background: #fff; font-size: 13px; }
        .header { text-align: center; border-bottom: 2px solid #16a34a; padding-bottom: 12px; margin-bottom: 15px; }
        .header h2 { margin: 0; color: #15803d; font-size: 22px; }
        .header p { margin: 4px 0 0 0; color: #64748b; font-size: 13px; }
        .transfer-boxes { display: flex; justify-content: space-between; gap: 15px; margin-bottom: 15px; }
        .box { flex: 1; background: #f0fdf4; border: 1px solid #bbf7d0; border-radius: 8px; padding: 10px; }
        .box-title { font-size: 11px; color: #64748b; margin-bottom: 4px; }
        .box-value { font-size: 15px; font-weight: bold; color: #0f172a; }
        table.data-table { width: 100%; border-collapse: collapse; margin-top: 15px; font-size: 12px; }
        table.data-table th { background: #0f172a; color: #fff; padding: 8px 10px; border: 1px solid #1e293b; text-align: right; }
        table.data-table td { padding: 8px 10px; border: 1px solid #cbd5e1; text-align: right; }
        table.data-table tr:nth-child(even) { background: #f8fafc; }
        .total-card { margin-top: 15px; background: #dcfce7; border: 1px solid #4ade80; border-radius: 8px; padding: 12px; font-size: 14px; font-weight: bold; color: #15803d; display: flex; justify-content: space-between; }
        .footer-sig { margin-top: 30px; display: flex; justify-content: space-between; text-align: center; }
        .sig-box { width: 30%; border-top: 1px dashed #94a3b8; padding-top: 5px; color: #475569; font-weight: bold; }
      </style>
    </head>
    <body>
      <div class="header">
        <h2>سند استلام وتخزين تحويل مخزني</h2>
        <p>نظام نقاط البيع وإدارة الفروع POS2026</p>
      </div>

      <div class="transfer-boxes">
        <div class="box">
          <div class="box-title">الفرع المحول منه (المرسل):</div>
          <div class="box-value">$fromName</div>
        </div>
        <div class="box">
          <div class="box-title">الفرع المستلم الحالي:</div>
          <div class="box-value">$currentBranchName</div>
        </div>
        <div class="box">
          <div class="box-title">رقم الحركة والتاريخ:</div>
          <div class="box-value">#${transNum.toInt()} | $dateStr</div>
        </div>
      </div>

      <table class="data-table">
        <thead>
          <tr>
            <th style="width: 40px; text-align: center;">#</th>
            <th>الباركود</th>
            <th>اسم الصنف</th>
            <th style="text-align: center;">الوحدة</th>
            <th style="text-align: center;">الكمية المقبولة</th>
            <th style="text-align: left;">سعر الكلفة</th>
            <th style="text-align: left;">الإجمالي</th>
          </tr>
        </thead>
        <tbody>
          $rowsHtml
        </tbody>
      </table>

      <div class="total-card">
        <div>إجمالي كميات الأصناف المستلمة: $totalQty</div>
        <div>إجمالي قيمة البضاعة المقبولة: ${totalAmount.toStringAsFixed(2)} ر.ي</div>
      </div>

      <div style="margin-top: 15px; font-size: 12px; color: #64748b;">
        <strong>بيان الحركة:</strong> ${descStr.isEmpty ? 'استلام تحويل مخزني' : descStr}<br>
        <strong>مستلم البضاعة:</strong> $userName | <strong>تاريخ الاستلام والطباعة:</strong> ${DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now())}
      </div>

      <div class="footer-sig">
        <div class="sig-box">توقيع المستلِـم</div>
        <div class="sig-box">اعتماد أمين المخزن</div>
        <div class="sig-box">ختم الفرع</div>
      </div>
    </body>
    </html>
    ''';

    PrintService.printHtml(htmlContent);
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: DefaultTabController(
        length: 2,
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // --- HEADER TITLE BAR ---
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.blueAccent.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(Icons.sync_alt_rounded, color: Colors.blueAccent, size: 28),
                        ),
                        const SizedBox(width: 14),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: const [
                            Text(
                              'شاشة التحويل المخزني بين الفروع',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                                fontFamily: 'Cairo',
                              ),
                            ),
                            Text(
                              'إصدار تحويل مخزني ثنائي المرحلة (إرسال واستلام بالمعاينة والتأكيد)',
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
                            backgroundColor: const Color(0xFF0F172A),
                            foregroundColor: Colors.cyanAccent,
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                              side: const BorderSide(color: Colors.cyanAccent),
                            ),
                          ),
                          icon: _isLoadingPending
                              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.cyanAccent, strokeWidth: 2))
                              : const Icon(Icons.cloud_upload_rounded, size: 20, color: Colors.cyanAccent),
                          label: Text('رفع ونقل التحويلات للسيرفر الرئيسي 📤${_localPendingTransfersQueue.isNotEmpty ? ' (${_localPendingTransfersQueue.length})' : ''}', style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 13)),
                          onPressed: _isLoadingPending ? null : _syncTransfersWithMainServer,
                        ),
                        const SizedBox(width: 12),
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blueGrey.shade800,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          icon: const Icon(Icons.print_rounded, size: 18),
                          label: const Text('معاينة ورقة الطباعة', style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
                          onPressed: _transferItems.isEmpty ? null : () => _printTransferInvoice(),
                        ),
                        const SizedBox(width: 12),
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          icon: _isLoading 
                            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                            : const Icon(Icons.check_circle_rounded, size: 20),
                          label: const Text('حفظ وإرسال التحويل', style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 15)),
                          onPressed: _isLoading ? null : _saveTransferVouchers,
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // --- TAB BAR ---
                Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E293B),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white10),
                  ),
                  child: TabBar(
                    indicatorColor: Colors.blueAccent,
                    indicatorWeight: 3,
                    labelColor: Colors.blueAccent,
                    unselectedLabelColor: Colors.white70,
                    labelStyle: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 14),
                    tabs: [
                      const Tab(
                        icon: Icon(Icons.send_rounded, size: 18),
                        text: '📤 إرسال تحويل مخزني (منصرف)',
                      ),
                      Tab(
                        icon: Badge(
                          label: Text('${_pendingTransfers.length}'),
                          isLabelVisible: _pendingTransfers.isNotEmpty,
                          child: const Icon(Icons.move_to_inbox_rounded, size: 18),
                        ),
                        text: '📥 التحويلات الواردة بانتظار الاستلام',
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // --- TAB BAR VIEW CONTENT ---
                Expanded(
                  child: TabBarView(
                    children: [
                      // TAB 1: OUTGOING TRANSFER FORM
                      _buildOutgoingTransferTab(),

                      // TAB 2: INCOMING PENDING TRANSFERS
                      _buildIncomingTransfersTab(),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildOutgoingTransferTab() {
    final apiService = Provider.of<ApiService>(context);
    return Column(
      children: [
        // --- BRANCHES & INVOICE HEADER BOX ---
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF1E293B),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white10),
          ),
          child: Row(
            children: [
              // 1. Source Branch (الفرع المحول منه) - Locked to Current Branch
              Expanded(
                flex: 3,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.lock_rounded, color: Colors.redAccent, size: 14),
                        SizedBox(width: 4),
                        Text('الفرع الأول (المحول منه - الفرع الحالي):', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 13, fontFamily: 'Cairo')),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0F172A),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.redAccent.withOpacity(0.4)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.store_rounded, color: Colors.redAccent, size: 18),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _fromBranch != null 
                                  ? '${_fromBranch!['fldName'] ?? 'فرع ${_fromBranch!['fldPointNO']}'} (إجباري)' 
                                  : 'فرع ${apiService.pointNo} (إجباري)',
                              style: const TextStyle(color: Colors.white, fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 13),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 14),

              const Icon(Icons.arrow_forward_rounded, color: Colors.blueAccent, size: 28),
              const SizedBox(width: 14),

              // 2. Destination Branch (الفرع المحول إليه) - Filter out Current Branch
              Expanded(
                flex: 3,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('الفرع الثاني (المحول إليه):', style: TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold, fontSize: 13, fontFamily: 'Cairo')),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0F172A),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.greenAccent.withOpacity(0.4)),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<Map<String, dynamic>>(
                          value: _toBranch,
                          isExpanded: true,
                          dropdownColor: const Color(0xFF1E293B),
                          style: const TextStyle(color: Colors.white, fontFamily: 'Cairo', fontWeight: FontWeight.bold),
                          items: _branches
                              .where((b) => b['fldPointNO'] != (apiService.pointNo))
                              .map((b) {
                            return DropdownMenuItem<Map<String, dynamic>>(
                              value: b,
                              child: Text(b['fldName'] ?? 'فرع ${b['fldPointNO']}'),
                            );
                          }).toList(),
                          onChanged: (val) => setState(() => _toBranch = val),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 14),

              // 3. Date Selection
              Expanded(
                flex: 2,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('تاريخ التحويل:', style: TextStyle(color: Colors.white70, fontSize: 13, fontFamily: 'Cairo')),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _dateController,
                      style: const TextStyle(color: Colors.white, fontFamily: 'Cairo', fontSize: 13),
                      decoration: InputDecoration(
                        isDense: true,
                        filled: true,
                        fillColor: const Color(0xFF0F172A),
                        suffixIcon: const Icon(Icons.calendar_month, color: Colors.blueAccent, size: 18),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 14),

              // 4. Notes / Statement
              Expanded(
                flex: 4,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('ملاحظات / سبب التحويل:', style: TextStyle(color: Colors.white70, fontSize: 13, fontFamily: 'Cairo')),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _noteController,
                      style: const TextStyle(color: Colors.white, fontFamily: 'Cairo', fontSize: 13),
                      decoration: InputDecoration(
                        isDense: true,
                        hintText: 'أدخل أي تفاصيل للتحويل...',
                        hintStyle: const TextStyle(color: Colors.white30, fontSize: 12, fontFamily: 'Cairo'),
                        filled: true,
                        fillColor: const Color(0xFF0F172A),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // --- ITEM SELECTION & INPUT BAR ---
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFF1E293B),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white10),
          ),
          child: Row(
            children: [
              // Item Selector Autocomplete (Search by Name, Number/ID, or Barcode)
              Expanded(
                flex: 5,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('البحث عن صنف (بالاسم، الرقم، أو الباركود):', style: TextStyle(color: Colors.white70, fontSize: 12, fontFamily: 'Cairo')),
                    const SizedBox(height: 6),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        return Autocomplete<ItemModel>(
                          displayStringForOption: (ItemModel item) => '${item.itemName} (${item.barcode})',
                          optionsBuilder: (TextEditingValue textEditingValue) {
                            if (textEditingValue.text.isEmpty) {
                              return apiService.items;
                            }
                            final q = textEditingValue.text.trim().toLowerCase();
                            return apiService.items.where((item) {
                              final nameMatch = item.itemName.toLowerCase().contains(q);
                              final barcodeMatch = item.barcode.toLowerCase().contains(q);
                              final idMatch = item.itemId.toString().contains(q);
                              return nameMatch || barcodeMatch || idMatch;
                            });
                          },
                          onSelected: (ItemModel selection) {
                            setState(() {
                              _selectedItem = selection;
                              _costController.text = selection.cost.toString();
                              _unitController.text = selection.unitName;
                            });
                          },
                          fieldViewBuilder: (context, textEditingController, focusNode, onFieldSubmitted) {
                            return TextField(
                              controller: textEditingController,
                              focusNode: focusNode,
                              style: const TextStyle(color: Colors.white, fontFamily: 'Cairo', fontSize: 13),
                              decoration: InputDecoration(
                                isDense: true,
                                hintText: 'ابحث باسم الصنف، الرقم، أو الباركود...',
                                hintStyle: const TextStyle(color: Colors.white30, fontFamily: 'Cairo', fontSize: 12),
                                prefixIcon: const Icon(Icons.search_rounded, color: Colors.blueAccent, size: 20),
                                suffixIcon: textEditingController.text.isNotEmpty || _selectedItem != null
                                    ? IconButton(
                                        icon: const Icon(Icons.clear, color: Colors.white54, size: 18),
                                        onPressed: () {
                                          setState(() {
                                            _selectedItem = null;
                                            textEditingController.clear();
                                            _costController.text = '0.0';
                                            _unitController.text = 'حبة';
                                          });
                                        },
                                      )
                                    : null,
                                filled: true,
                                fillColor: const Color(0xFF0F172A),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                              ),
                              onSubmitted: (val) {
                                onFieldSubmitted();
                                final matches = apiService.items.where((x) => x.barcode.trim() == val.trim()).toList();
                                if (matches.isNotEmpty) {
                                  setState(() {
                                    _selectedItem = matches.first;
                                    _costController.text = _selectedItem!.cost.toString();
                                    _unitController.text = _selectedItem!.unitName;
                                    textEditingController.text = '${_selectedItem!.itemName} (${_selectedItem!.barcode})';
                                  });
                                }
                              },
                            );
                          },
                          optionsViewBuilder: (context, onSelected, options) {
                            return Align(
                              alignment: Alignment.topRight,
                              child: Material(
                                elevation: 8,
                                color: const Color(0xFF1E293B),
                                borderRadius: BorderRadius.circular(8),
                                child: Container(
                                  width: constraints.maxWidth,
                                  constraints: const BoxConstraints(maxHeight: 260),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF1E293B),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: Colors.blueAccent.withOpacity(0.4)),
                                  ),
                                  child: ListView.separated(
                                    padding: const EdgeInsets.symmetric(vertical: 4),
                                    itemCount: options.length,
                                    separatorBuilder: (_, __) => const Divider(color: Colors.white10, height: 1),
                                    itemBuilder: (BuildContext context, int index) {
                                      final ItemModel option = options.elementAt(index);
                                      return ListTile(
                                        dense: true,
                                        title: Text(
                                          option.itemName,
                                          style: const TextStyle(color: Colors.white, fontFamily: 'Cairo', fontWeight: FontWeight.bold),
                                        ),
                                        subtitle: Text(
                                          'باركود: ${option.barcode} | رقم الصنف: #${option.itemId} | كلفة: ${option.cost}',
                                          style: const TextStyle(color: Colors.white54, fontFamily: 'Cairo', fontSize: 11),
                                        ),
                                        trailing: Text(
                                          option.unitName,
                                          style: const TextStyle(color: Colors.blueAccent, fontFamily: 'Cairo', fontWeight: FontWeight.bold),
                                        ),
                                        onTap: () {
                                          onSelected(option);
                                        },
                                      );
                                    },
                                  ),
                                ),
                              ),
                            );
                          },
                        );
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),

              // Quantity Field
              Expanded(
                flex: 2,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('الكمية:', style: TextStyle(color: Colors.white70, fontSize: 12, fontFamily: 'Cairo')),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _qtyController,
                      keyboardType: TextInputType.number,
                      style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold, fontFamily: 'Cairo'),
                      decoration: InputDecoration(
                        isDense: true,
                        filled: true,
                        fillColor: const Color(0xFF0F172A),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),

              // Unit Name Field
              Expanded(
                flex: 2,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('الوحدة:', style: TextStyle(color: Colors.white70, fontSize: 12, fontFamily: 'Cairo')),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _unitController,
                      style: const TextStyle(color: Colors.white, fontFamily: 'Cairo'),
                      decoration: InputDecoration(
                        isDense: true,
                        filled: true,
                        fillColor: const Color(0xFF0F172A),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),

              // Cost Price Field
              Expanded(
                flex: 2,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('سعر الكلفة:', style: TextStyle(color: Colors.white70, fontSize: 12, fontFamily: 'Cairo')),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _costController,
                      keyboardType: TextInputType.number,
                      style: const TextStyle(color: Colors.white, fontFamily: 'Cairo'),
                      decoration: InputDecoration(
                        isDense: true,
                        filled: true,
                        fillColor: const Color(0xFF0F172A),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),

              // Add Button
              Padding(
                padding: const EdgeInsets.only(top: 20),
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blueAccent,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  icon: const Icon(Icons.add_rounded, size: 20),
                  label: const Text('إضافة للتحويل', style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
                  onPressed: _addItemToTransfer,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // --- ITEMS TABLE LIST ---
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white10),
            ),
            child: _transferItems.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: const [
                        Icon(Icons.format_list_bulleted_rounded, color: Colors.white24, size: 54),
                        SizedBox(height: 10),
                        Text(
                          'لم يتم إضافة أصناف لفاتورة التحويل بعد',
                          style: TextStyle(color: Colors.white38, fontFamily: 'Cairo', fontSize: 14),
                        ),
                      ],
                    ),
                  )
                : Column(
                    children: [
                      // Table Header
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        decoration: const BoxDecoration(
                          color: Color(0xFF0F172A),
                          borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
                        ),
                        child: Row(
                          children: const [
                            SizedBox(width: 40, child: Text('#', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontFamily: 'Cairo'))),
                            Expanded(flex: 2, child: Text('البار كود', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontFamily: 'Cairo'))),
                            Expanded(flex: 4, child: Text('اسم الصنف', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontFamily: 'Cairo'))),
                            Expanded(flex: 2, child: Text('الوحدة', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontFamily: 'Cairo'))),
                            Expanded(flex: 2, child: Text('الكمية', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontFamily: 'Cairo'))),
                            Expanded(flex: 2, child: Text('سعر الكلفة', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontFamily: 'Cairo'))),
                            Expanded(flex: 2, child: Text('الإجمالي', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontFamily: 'Cairo'))),
                            SizedBox(width: 50, child: Text('إجراء', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontFamily: 'Cairo'))),
                          ],
                        ),
                      ),
                      // Table Body
                      Expanded(
                        child: ListView.separated(
                          padding: const EdgeInsets.all(8),
                          itemCount: _transferItems.length,
                          separatorBuilder: (_, __) => const Divider(color: Colors.white10, height: 1),
                          itemBuilder: (context, index) {
                            final item = _transferItems[index];
                            return Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                              child: Row(
                                children: [
                                  SizedBox(width: 40, child: Text('${index + 1}', style: const TextStyle(color: Colors.white54, fontFamily: 'Cairo'))),
                                  Expanded(flex: 2, child: Text(item['barcode'], style: const TextStyle(color: Colors.white, fontFamily: 'Cairo'))),
                                  Expanded(flex: 4, child: Text(item['itemName'], style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontFamily: 'Cairo'))),
                                  Expanded(flex: 2, child: Text(item['unitName'], style: const TextStyle(color: Colors.white70, fontFamily: 'Cairo'))),
                                  Expanded(flex: 2, child: Text('${item['quantity']}', style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold, fontFamily: 'Cairo'))),
                                  Expanded(flex: 2, child: Text('${(item['costPrice'] as double).toStringAsFixed(2)}', style: const TextStyle(color: Colors.white, fontFamily: 'Cairo'))),
                                  Expanded(flex: 2, child: Text('${(item['totalCost'] as double).toStringAsFixed(2)}', style: const TextStyle(color: Colors.amberAccent, fontWeight: FontWeight.bold, fontFamily: 'Cairo'))),
                                  SizedBox(
                                    width: 50,
                                    child: IconButton(
                                      icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 20),
                                      onPressed: () => _removeItem(index),
                                    ),
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
        const SizedBox(height: 16),

        // --- FOOTER TOTALS BAR ---
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          decoration: BoxDecoration(
            color: const Color(0xFF1E293B),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.blueAccent.withOpacity(0.4)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Text('عدد الأصناف: ', style: TextStyle(color: Colors.white70, fontFamily: 'Cairo', fontSize: 15)),
                  Text('${_transferItems.length}', style: const TextStyle(color: Colors.blueAccent, fontWeight: FontWeight.bold, fontSize: 16, fontFamily: 'Cairo')),
                  const SizedBox(width: 30),
                  const Text('إجمالي الكمية: ', style: TextStyle(color: Colors.white70, fontFamily: 'Cairo', fontSize: 15)),
                  Text('$_totalTransferQty', style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold, fontSize: 16, fontFamily: 'Cairo')),
                ],
              ),
              Row(
                children: [
                  const Text('إجمالي تكلفة التحويل: ', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontFamily: 'Cairo', fontSize: 16)),
                  Text('${_totalTransferAmount.toStringAsFixed(2)} ر.ي', style: const TextStyle(color: Colors.amberAccent, fontWeight: FontWeight.bold, fontSize: 20, fontFamily: 'Cairo')),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildIncomingTransfersTab() {
    final apiService = Provider.of<ApiService>(context);
    final currentPointNo = apiService.pointNo;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // --- HEADER BAR (No Dropdown Choice - Always Current POS Point) ---
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          decoration: BoxDecoration(
            color: const Color(0xFF1E293B),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.blueAccent.withOpacity(0.3)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.blueAccent.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.move_to_inbox_rounded, color: Colors.blueAccent, size: 24),
                  ),
                  const SizedBox(width: 14),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'التحويلات الواردة لنقطة البيع الحالية: ${apiService.pointName} (#$currentPointNo)',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16, fontFamily: 'Cairo'),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'عرض البيانات الواردة مباشرة من قاعدة البيانات الرئيسية بحسب رقم النقطة الحالية (dbo.details.fldToPointNO = $currentPointNo)',
                        style: const TextStyle(color: Colors.white54, fontSize: 12, fontFamily: 'Cairo'),
                      ),
                    ],
                  ),
                ],
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0F172A),
                  foregroundColor: Colors.blueAccent,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
                icon: const Icon(Icons.refresh_rounded, size: 20),
                label: const Text('تحديث من السيرفر الرئيسي', style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
                onPressed: _loadPendingTransfers,
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // --- TRANSFERS LIST ---
        Expanded(
          child: _isLoadingPending
              ? const Center(child: CircularProgressIndicator(color: Colors.blueAccent))
              : _pendingTransfers.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.inbox_rounded, color: Colors.white24, size: 64),
                          const SizedBox(height: 12),
                          Text(
                            _selectedIncomingPointNo == currentPointNo
                                ? 'لا توجد تحويلات واردة معلقة حالياً لنقطة البيع الحالية (#$currentPointNo)'
                                : (_selectedIncomingPointNo == 0
                                    ? 'لا توجد تحويلات واردة معلقة حالياً لأي فرع'
                                    : 'لا توجد تحويلات واردة معلقة للفرع المحدد'),
                            style: const TextStyle(color: Colors.white54, fontFamily: 'Cairo', fontSize: 16),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      itemCount: _pendingTransfers.length,
                      itemBuilder: (context, index) {
                        final t = _pendingTransfers[index];
                        final transNum = (t['transNumber'] as num).toDouble();
                        final fldPointName = t['fromBranchName'] ?? 'فرع ${t['fromPointNo']}';
                        final fldDate = t['date'] ?? '';
                        final fldToPointNO = t['toPointNo'] ?? 0;
                        final fldStatus = t['status'] ?? 0;
                        final items = (t['items'] as List<dynamic>?) ?? [];

                        return Card(
                          color: const Color(0xFF1E293B),
                          margin: const EdgeInsets.only(bottom: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: BorderSide(color: Colors.blueAccent.withOpacity(0.3)),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Header bar with metadata
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: Colors.blueAccent.withOpacity(0.2),
                                            borderRadius: BorderRadius.circular(6),
                                          ),
                                          child: Text(
                                            'رقم الحركة: #${transNum.toInt()}',
                                            style: const TextStyle(color: Colors.blueAccent, fontWeight: FontWeight.bold, fontFamily: 'Cairo'),
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Text(
                                          'نقطة المصدر (fldPointName): $fldPointName',
                                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontFamily: 'Cairo', fontSize: 15),
                                        ),
                                      ],
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: Colors.orange.withOpacity(0.2),
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(color: Colors.orangeAccent),
                                      ),
                                      child: Text(
                                        'الحالة (fldStatus): $fldStatus (معلق / بانتظار الاستلام)',
                                        style: const TextStyle(color: Colors.orangeAccent, fontSize: 12, fontFamily: 'Cairo', fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    Icon(Icons.calendar_month_rounded, color: Colors.white54, size: 14),
                                    const SizedBox(width: 4),
                                    Text('التاريخ (fldDate): $fldDate', style: const TextStyle(color: Colors.white70, fontSize: 12, fontFamily: 'Cairo')),
                                    const SizedBox(width: 20),
                                    Icon(Icons.location_on_rounded, color: Colors.greenAccent, size: 14),
                                    const SizedBox(width: 4),
                                    Text('نقطة البيع المستلمة (fldToPointNO): $fldToPointNO', style: const TextStyle(color: Colors.greenAccent, fontSize: 12, fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
                                  ],
                                ),
                                const Divider(color: Colors.white10, height: 20),

                                // Structured Items Table for the Query Fields
                                Container(
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF0F172A),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: Colors.white10),
                                  ),
                                  child: Table(
                                    columnWidths: const {
                                      0: FlexColumnWidth(1), // Barcode
                                      1: FlexColumnWidth(2.5), // Item Name
                                      2: FlexColumnWidth(1), // Quantity
                                      3: FlexColumnWidth(1), // Sales Price
                                      4: FlexColumnWidth(1.2), // Total
                                      5: FlexColumnWidth(1), // Destination Point
                                      6: FlexColumnWidth(1), // Status
                                    },
                                    children: [
                                      // Table Header
                                      TableRow(
                                        decoration: const BoxDecoration(
                                          color: Color(0xFF1E293B),
                                          borderRadius: BorderRadius.only(topLeft: Radius.circular(8), topRight: Radius.circular(8)),
                                        ),
                                        children: const [
                                          Padding(padding: EdgeInsets.all(8.0), child: Text('fldBarCode', style: TextStyle(color: Colors.blueAccent, fontWeight: FontWeight.bold, fontSize: 11, fontFamily: 'Cairo'))),
                                          Padding(padding: EdgeInsets.all(8.0), child: Text('fldItemName', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11, fontFamily: 'Cairo'))),
                                          Padding(padding: EdgeInsets.all(8.0), child: Text('fldQuantity', style: TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold, fontSize: 11, fontFamily: 'Cairo'))),
                                          Padding(padding: EdgeInsets.all(8.0), child: Text('fldSalesPrice', style: TextStyle(color: Colors.amberAccent, fontWeight: FontWeight.bold, fontSize: 11, fontFamily: 'Cairo'))),
                                          Padding(padding: EdgeInsets.all(8.0), child: Text('الإجمالي', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11, fontFamily: 'Cairo'))),
                                          Padding(padding: EdgeInsets.all(8.0), child: Text('fldToPointNO', style: TextStyle(color: Colors.cyanAccent, fontWeight: FontWeight.bold, fontSize: 11, fontFamily: 'Cairo'))),
                                          Padding(padding: EdgeInsets.all(8.0), child: Text('fldStatus', style: TextStyle(color: Colors.orangeAccent, fontWeight: FontWeight.bold, fontSize: 11, fontFamily: 'Cairo'))),
                                        ],
                                      ),
                                      // Table Content Rows
                                      ...items.map((item) {
                                        final double qty = (item['quantity'] as num).toDouble();
                                        final double price = (item['salesPrice'] as num).toDouble();
                                        final double total = qty * price;
                                        final itemToPoint = item['toPointNo'] ?? fldToPointNO;
                                        final itemStatus = item['status'] ?? fldStatus;

                                        return TableRow(
                                          children: [
                                            Padding(padding: const EdgeInsets.all(8.0), child: Text(item['barcode'] ?? '', style: const TextStyle(color: Colors.white70, fontSize: 12, fontFamily: 'Cairo'))),
                                            Padding(padding: const EdgeInsets.all(8.0), child: Text(item['itemName'] ?? '', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12, fontFamily: 'Cairo'))),
                                            Padding(padding: const EdgeInsets.all(8.0), child: Text('$qty ${item['unitName'] ?? ""}', style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold, fontSize: 12, fontFamily: 'Cairo'))),
                                            Padding(padding: const EdgeInsets.all(8.0), child: Text(price.toStringAsFixed(2), style: const TextStyle(color: Colors.amberAccent, fontSize: 12, fontFamily: 'Cairo'))),
                                            Padding(padding: const EdgeInsets.all(8.0), child: Text(total.toStringAsFixed(2), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12, fontFamily: 'Cairo'))),
                                            Padding(padding: const EdgeInsets.all(8.0), child: Text('$itemToPoint', style: const TextStyle(color: Colors.cyanAccent, fontSize: 12, fontFamily: 'Cairo'))),
                                            Padding(padding: const EdgeInsets.all(8.0), child: Text('$itemStatus', style: const TextStyle(color: Colors.orangeAccent, fontWeight: FontWeight.bold, fontSize: 12, fontFamily: 'Cairo'))),
                                          ],
                                        );
                                      }).toList(),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 14),

                                // Action Buttons
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    OutlinedButton.icon(
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: Colors.cyanAccent,
                                        side: const BorderSide(color: Colors.cyanAccent),
                                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                      ),
                                      icon: const Icon(Icons.print_rounded, size: 18),
                                      label: const Text('طباعة معاينة السند', style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
                                      onPressed: () => _printReceivedTransferInvoice(t),
                                    ),
                                    ElevatedButton.icon(
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.green,
                                        foregroundColor: Colors.white,
                                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                      ),
                                      icon: const Icon(Icons.check_circle_rounded, size: 20),
                                      label: const Text(
                                        'موافقة وتأكيد الاستلام كتمالة (تغيير الحالة fldStatus = 1)',
                                        style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 13),
                                      ),
                                      onPressed: () => _confirmPendingTransfer(t),
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
      ],
    );
  }
}
