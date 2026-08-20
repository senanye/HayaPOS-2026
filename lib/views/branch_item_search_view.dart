import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/api_service.dart';
import '../services/barcode_label_service.dart';
import '../models/item.dart';

class BranchItemSearchView extends StatefulWidget {
  const BranchItemSearchView({super.key});

  @override
  State<BranchItemSearchView> createState() => _BranchItemSearchViewState();
}

class _BranchItemSearchViewState extends State<BranchItemSearchView> {
  final TextEditingController _searchController = TextEditingController();
  List<dynamic> _searchResults = [];
  bool _isLoading = false;
  String _dataSource = '';
  String _searchedQuery = '';
  bool _hasSearched = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _performSearch() async {
    final query = _searchController.text.trim();
    if (query.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('يرجى إدخال اسم الصنف أو الباركود للبحث', style: TextStyle(fontFamily: 'Cairo')),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() {
      _isLoading = true;
      _hasSearched = true;
      _searchedQuery = query;
    });

    final apiService = Provider.of<ApiService>(context, listen: false);
    try {
      final res = await apiService.searchRemoteBranchItems(query);
      setState(() {
        _searchResults = res['items'] ?? [];
        _dataSource = res['source'] ?? 'remote';
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ أثناء البحث في قواعد البيانات: $e', style: const TextStyle(fontFamily: 'Cairo')),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  double get _totalQuantity {
    return _searchResults.fold(0.0, (sum, item) => sum + (item['quantity'] as num? ?? 0.0).toDouble());
  }

  int get _branchCount {
    final branches = _searchResults.map((item) => item['branchName']).toSet();
    return branches.length;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      body: Directionality(
        textDirection: TextDirection.rtl,
        child: Padding(
          padding: const EdgeInsets.all(28.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header Title & Data Source Indicator
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'البحث عن صنف في كافة الفروع',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'Cairo',
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'الاستعلام المباشر من قاعدة البيانات الرئيسية لجميع الفروع ونقاط البيع',
                        style: TextStyle(color: Colors.white54, fontSize: 13, fontFamily: 'Cairo'),
                      ),
                    ],
                  ),

                  if (_hasSearched)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: _dataSource == 'remote'
                            ? Colors.green.withOpacity(0.15)
                            : Colors.amber.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: _dataSource == 'remote' ? Colors.greenAccent : Colors.amberAccent,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            _dataSource == 'remote' ? Icons.cloud_done_rounded : Icons.storage_rounded,
                            color: _dataSource == 'remote' ? Colors.greenAccent : Colors.amberAccent,
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _dataSource == 'remote'
                                ? 'مصدر البيانات: السيرفر الرئيسي (Remote DB)'
                                : 'مصدر البيانات: قاعدة البيانات المحلية (Local Fallback)',
                            style: TextStyle(
                              color: _dataSource == 'remote' ? Colors.greenAccent : Colors.amberAccent,
                              fontFamily: 'Cairo',
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 24),

              // Search Bar Panel
              Card(
                color: const Color(0xFF1E293B),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _searchController,
                          style: const TextStyle(color: Colors.white, fontFamily: 'Cairo', fontSize: 15),
                          decoration: InputDecoration(
                            hintText: 'أدخل اسم الصنف أو الباركود للاستعلام في الفروع...',
                            hintStyle: const TextStyle(color: Colors.white38, fontFamily: 'Cairo', fontSize: 14),
                            prefixIcon: const Icon(Icons.search_rounded, color: Colors.blueAccent),
                            suffixIcon: _searchController.text.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(Icons.clear, color: Colors.white54),
                                    onPressed: () {
                                      _searchController.clear();
                                      setState(() {});
                                    },
                                  )
                                : null,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: const BorderSide(color: Colors.white10),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: const BorderSide(color: Colors.white10),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: const BorderSide(color: Colors.blueAccent),
                            ),
                            filled: true,
                            fillColor: const Color(0xFF0F172A),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                          ),
                          onSubmitted: (_) => _performSearch(),
                        ),
                      ),
                      const SizedBox(width: 16),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blueAccent,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          elevation: 2,
                        ),
                        icon: _isLoading
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                              )
                            : const Icon(Icons.saved_search_rounded, size: 22),
                        label: const Text(
                          'استعلام الفروع',
                          style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                        onPressed: _isLoading ? null : _performSearch,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // Summary Stats Row (Only if searched)
              if (_hasSearched && !_isLoading) ...[
                Row(
                  children: [
                    _buildStatCard('عدد الفروع المتوفر بها', '$_branchCount فرع', Icons.store_rounded, Colors.cyanAccent),
                    const SizedBox(width: 16),
                    _buildStatCard('إجمالي الكميات المتوفرة', '${_totalQuantity.toStringAsFixed(1)} قطعة', Icons.inventory_rounded, Colors.greenAccent),
                    const SizedBox(width: 16),
                    _buildStatCard('عدد أسطر الاستعلام', '${_searchResults.length} نتيجة', Icons.format_list_bulleted_rounded, Colors.purpleAccent),
                  ],
                ),
                const SizedBox(height: 20),
              ],

              // Search Results Table
              Expanded(
                child: _isLoading
                    ? const Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            CircularProgressIndicator(color: Colors.blueAccent),
                            SizedBox(height: 16),
                            Text('جاري الاتصال بالسيرفر الرئيسي وجلب كميات الأصناف للفروع...', style: TextStyle(color: Colors.white70, fontFamily: 'Cairo')),
                          ],
                        ),
                      )
                    : !_hasSearched
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.manage_search_rounded, size: 80, color: Colors.blueAccent.withOpacity(0.3)),
                                const SizedBox(height: 16),
                                const Text(
                                  'ابحث عن أي صنف بالاسم أو الباركود لعرض توفره وكمياته في جميع الفروع',
                                  style: TextStyle(color: Colors.white30, fontSize: 16, fontFamily: 'Cairo'),
                                ),
                              ],
                            ),
                          )
                        : _searchResults.isEmpty
                            ? Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Icon(Icons.search_off_rounded, size: 70, color: Colors.redAccent),
                                    const SizedBox(height: 16),
                                    Text(
                                      'لم يتم العثور على أي نتائج للصنف "$_searchedQuery" في الفروع',
                                      style: const TextStyle(color: Colors.white70, fontSize: 16, fontFamily: 'Cairo'),
                                    ),
                                  ],
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
                                          color: Colors.white.withOpacity(0.03),
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: const Row(
                                          children: [
                                            Expanded(flex: 3, child: Text('اسم الفرع / نقطة البيع', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontFamily: 'Cairo'))),
                                            Expanded(flex: 3, child: Text('اسم الصنف', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontFamily: 'Cairo'))),
                                            Expanded(flex: 2, child: Text('الباركود', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontFamily: 'Cairo'))),
                                            Expanded(flex: 2, child: Text('الكمية المتوفرة', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontFamily: 'Cairo'), textAlign: TextAlign.center)),
                                            Expanded(flex: 2, child: Text('سعر البيع', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontFamily: 'Cairo'), textAlign: TextAlign.end)),
                                            const SizedBox(width: 44, child: Text('طباعة', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontFamily: 'Cairo'), textAlign: TextAlign.center)),
                                          ],
                                        ),
                                      ),
                                      const Divider(color: Colors.white10, height: 16),

                                      // Table List Rows
                                      Expanded(
                                        child: ListView.separated(
                                          itemCount: _searchResults.length,
                                          separatorBuilder: (context, index) => const Divider(color: Colors.white10, height: 1),
                                          itemBuilder: (context, index) {
                                            final item = _searchResults[index];
                                            final qty = (item['quantity'] as num? ?? 0.0).toDouble();
                                            final price = (item['salesPrice'] as num? ?? 0.0).toDouble();
                                            final bCode = (item['barcode'] ?? '').toString();
                                            final iName = (item['itemName'] ?? '').toString();

                                            Color qtyColor = Colors.greenAccent;
                                            if (qty <= 0) {
                                              qtyColor = Colors.redAccent;
                                            } else if (qty <= 10) {
                                              qtyColor = Colors.orangeAccent;
                                            }

                                            return Padding(
                                              padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
                                              child: Row(
                                                children: [
                                                  // Branch Name
                                                  Expanded(
                                                    flex: 3,
                                                    child: Row(
                                                      children: [
                                                        const Icon(Icons.storefront_rounded, color: Colors.blueAccent, size: 20),
                                                        const SizedBox(width: 8),
                                                        Expanded(
                                                          child: Text(
                                                            item['branchName'] ?? 'الفرع الرئيسي',
                                                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontFamily: 'Cairo', fontSize: 14),
                                                            maxLines: 1,
                                                            overflow: TextOverflow.ellipsis,
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                  // Item Name
                                                  Expanded(
                                                    flex: 3,
                                                    child: Text(
                                                      iName,
                                                      style: const TextStyle(color: Colors.white, fontFamily: 'Cairo', fontSize: 14),
                                                      maxLines: 1,
                                                      overflow: TextOverflow.ellipsis,
                                                    ),
                                                  ),
                                                  // Barcode
                                                  Expanded(
                                                    flex: 2,
                                                    child: Text(
                                                      bCode,
                                                      style: const TextStyle(color: Colors.white54, fontFamily: 'monospace', fontSize: 13),
                                                    ),
                                                  ),
                                                  // Quantity Chip
                                                  Expanded(
                                                    flex: 2,
                                                    child: Center(
                                                      child: Container(
                                                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                                        decoration: BoxDecoration(
                                                          color: qtyColor.withValues(alpha: 0.12),
                                                          borderRadius: BorderRadius.circular(6),
                                                          border: Border.all(color: qtyColor.withValues(alpha: 0.3)),
                                                        ),
                                                        child: Text(
                                                          '${qty.toStringAsFixed(1)} قطعة',
                                                          style: TextStyle(
                                                            color: qtyColor,
                                                            fontWeight: FontWeight.bold,
                                                            fontFamily: 'Cairo',
                                                            fontSize: 13,
                                                          ),
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                  // Sales Price
                                                  Expanded(
                                                    flex: 2,
                                                    child: Text(
                                                      '${price.toStringAsFixed(2)} د.أ',
                                                      textAlign: TextAlign.end,
                                                      style: const TextStyle(
                                                        color: Colors.white,
                                                        fontWeight: FontWeight.bold,
                                                        fontSize: 14,
                                                      ),
                                                    ),
                                                  ),
                                                  // Print Barcode Action
                                                  SizedBox(
                                                    width: 44,
                                                    child: Center(
                                                      child: IconButton(
                                                        icon: const Icon(Icons.qr_code_2_rounded, color: Colors.tealAccent, size: 20),
                                                        tooltip: 'طباعة ملصق الباركود للصنف',
                                                        onPressed: () {
                                                          final api = Provider.of<ApiService>(context, listen: false);
                                                          final match = api.items.where((it) => it.barcode.trim() == bCode.trim()).toList();
                                                          final itemToPrint = match.isNotEmpty
                                                              ? match.first
                                                              : ItemModel(
                                                                  barcode: bCode.isNotEmpty ? bCode : '123456',
                                                                  itemName: iName.isNotEmpty ? iName : 'صنف غير محدد',
                                                                  salesPrice: price,
                                                                  unitName: 'حبة',
                                                                  cost: 0,
                                                                  groupId: 0,
                                                                  itemId: 0,
                                                                  unityId: 1,
                                                                  moneyId: 1,
                                                                  isActive: true,
                                                                );
                                                          BarcodeLabelService.showQuickBarcodePrintDialog(
                                                            context: context,
                                                            item: itemToPrint,
                                                          );
                                                        },
                                                      ),
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
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatCard(String title, String value, IconData icon, Color color) {
    return Expanded(
      child: Card(
        color: const Color(0xFF1E293B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: color, size: 24),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(color: Colors.white54, fontSize: 11, fontFamily: 'Cairo')),
                  const SizedBox(height: 2),
                  Text(value, style: TextStyle(color: color, fontSize: 16, fontWeight: FontWeight.bold, fontFamily: 'Cairo')),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
