import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:barcode/barcode.dart' as bc_lib;
import '../services/api_service.dart';
import '../services/print_service.dart';
import '../services/barcode_label_service.dart';
import '../models/item.dart';
import '../models/item_group.dart';
import 'item_movement_view.dart';
import 'barcode_print_view.dart';

class ItemsManagementView extends StatefulWidget {
  const ItemsManagementView({super.key});

  @override
  State<ItemsManagementView> createState() => _ItemsManagementViewState();
}

class _ItemsManagementViewState extends State<ItemsManagementView> {
  final TextEditingController _searchController = TextEditingController();
  int _selectedGroupId = 0; // 0 = All Groups
  String _activeFilter = 'all'; // 'all', 'active', 'inactive'
  bool _isSaving = false;
  bool _isSyncingItems = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final apiService = Provider.of<ApiService>(context, listen: false);
      apiService.reloadItems();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<ItemModel> _filterItems(List<ItemModel> allItems) {
    final query = _searchController.text.trim().toLowerCase();
    return allItems.where((item) {
      final matchesSearch = query.isEmpty ||
          item.itemName.toLowerCase().contains(query) ||
          item.barcode.toLowerCase().contains(query) ||
          item.itemId.toString().contains(query);

      final matchesGroup = _selectedGroupId == 0 || item.groupId == _selectedGroupId;

      bool matchesActive = true;
      if (_activeFilter == 'active') {
        matchesActive = item.isActive;
      } else if (_activeFilter == 'inactive') {
        matchesActive = !item.isActive;
      }

      return matchesSearch && matchesGroup && matchesActive;
    }).toList();
  }

  void _openAddEditDialog([ItemModel? item]) {
    final isEditing = item != null;

    final nameController = TextEditingController(text: isEditing ? item.itemName : '');
    final barcodeController = TextEditingController(text: isEditing ? item.barcode : '');
    final unitController = TextEditingController(text: isEditing ? item.unitName : 'حبة');
    final salesPriceController = TextEditingController(text: isEditing ? item.salesPrice.toString() : '0.0');
    final costController = TextEditingController(text: isEditing ? item.cost.toString() : '0.0');
    
    int selectedGroup = isEditing ? item.groupId : 1;
    bool isActive = isEditing ? item.isActive : true;

    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final apiService = Provider.of<ApiService>(context, listen: false);
          final groups = apiService.groups;

          return Directionality(
            textDirection: TextDirection.rtl,
            child: AlertDialog(
              backgroundColor: const Color(0xFF0F172A),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: const BorderSide(color: Colors.blueAccent, width: 1.5),
              ),
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: isEditing ? Colors.amber.withOpacity(0.2) : Colors.blueAccent.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      isEditing ? Icons.edit_rounded : Icons.add_box_rounded,
                      color: isEditing ? Colors.amber : Colors.blueAccent,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    isEditing ? 'تعديل صنف في جدول الأصناف (List)' : 'إضافة صنف جديد (جدول List)',
                    style: const TextStyle(
                      fontFamily: 'Cairo',
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
              content: SizedBox(
                width: 500,
                child: Form(
                  key: formKey,
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: nameController,
                          style: const TextStyle(color: Colors.white, fontFamily: 'Cairo'),
                          decoration: InputDecoration(
                            labelText: 'اسم الصنف *',
                            labelStyle: const TextStyle(color: Colors.white70, fontFamily: 'Cairo'),
                            prefixIcon: const Icon(Icons.inventory_2_outlined, color: Colors.blueAccent),
                            filled: true,
                            fillColor: const Color(0xFF1E293B),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          validator: (val) => val == null || val.trim().isEmpty ? 'يرجى إدخال اسم الصنف' : null,
                        ),
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                controller: barcodeController,
                                style: const TextStyle(color: Colors.white, fontFamily: 'Cairo'),
                                decoration: InputDecoration(
                                  labelText: 'الباركود / رمز الصنف',
                                  hintText: 'يولد تلقائياً في حال الترُك',
                                  hintStyle: const TextStyle(color: Colors.white38, fontSize: 12, fontFamily: 'Cairo'),
                                  labelStyle: const TextStyle(color: Colors.white70, fontFamily: 'Cairo'),
                                  prefixIcon: const Icon(Icons.qr_code_rounded, color: Colors.blueAccent),
                                  filled: true,
                                  fillColor: const Color(0xFF1E293B),
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            IconButton(
                              tooltip: 'توليد باركود تلقائي',
                              icon: const Icon(Icons.auto_awesome, color: Colors.amber),
                              onPressed: () {
                                setDialogState(() {
                                  barcodeController.text = DateTime.now().millisecondsSinceEpoch.toString().substring(5);
                                });
                              },
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                controller: unitController,
                                style: const TextStyle(color: Colors.white, fontFamily: 'Cairo'),
                                decoration: InputDecoration(
                                  labelText: 'اسم الوحدة',
                                  labelStyle: const TextStyle(color: Colors.white70, fontFamily: 'Cairo'),
                                  prefixIcon: const Icon(Icons.straighten_rounded, color: Colors.blueAccent),
                                  filled: true,
                                  fillColor: const Color(0xFF1E293B),
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: DropdownButtonFormField<int>(
                                value: groups.any((g) => g.id == selectedGroup) ? selectedGroup : (groups.isNotEmpty ? groups.first.id : 1),
                                dropdownColor: const Color(0xFF1E293B),
                                style: const TextStyle(color: Colors.white, fontFamily: 'Cairo'),
                                decoration: InputDecoration(
                                  labelText: 'المجموعة',
                                  labelStyle: const TextStyle(color: Colors.white70, fontFamily: 'Cairo'),
                                  filled: true,
                                  fillColor: const Color(0xFF1E293B),
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                ),
                                items: groups.map((g) {
                                  return DropdownMenuItem<int>(
                                    value: g.id,
                                    child: Text(g.name, style: const TextStyle(fontFamily: 'Cairo')),
                                  );
                                }).toList(),
                                onChanged: (val) {
                                  if (val != null) {
                                    setDialogState(() => selectedGroup = val);
                                  }
                                },
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                controller: salesPriceController,
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold, fontFamily: 'Cairo'),
                                decoration: InputDecoration(
                                  labelText: 'سعر البيع *',
                                  labelStyle: const TextStyle(color: Colors.white70, fontFamily: 'Cairo'),
                                  prefixIcon: const Icon(Icons.attach_money_rounded, color: Colors.greenAccent),
                                  filled: true,
                                  fillColor: const Color(0xFF1E293B),
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                ),
                                validator: (val) {
                                  if (val == null || val.trim().isEmpty) return 'أدخل السعر';
                                  if (double.tryParse(val) == null) return 'سعر غير صالح';
                                  return null;
                                },
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: TextFormField(
                                controller: costController,
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                style: const TextStyle(color: Colors.orangeAccent, fontWeight: FontWeight.bold, fontFamily: 'Cairo'),
                                decoration: InputDecoration(
                                  labelText: 'التكلفة *',
                                  labelStyle: const TextStyle(color: Colors.white70, fontFamily: 'Cairo'),
                                  prefixIcon: const Icon(Icons.money_off_rounded, color: Colors.orangeAccent),
                                  filled: true,
                                  fillColor: const Color(0xFF1E293B),
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                ),
                                validator: (val) {
                                  if (val == null || val.trim().isEmpty) return 'أدخل التكلفة';
                                  if (double.tryParse(val) == null) return 'تكلفة غير صالحة';
                                  return null;
                                },
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1E293B),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.white10),
                          ),
                          child: SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('حالة الصنف (نشط / مفعل)', style: TextStyle(color: Colors.white, fontFamily: 'Cairo', fontSize: 14)),
                            subtitle: Text(isActive ? 'الصنف يظهر في الكاشير والبحث' : 'الصنف معطل ولا يظهر في المبيعات', style: const TextStyle(color: Colors.white54, fontSize: 11, fontFamily: 'Cairo')),
                            value: isActive,
                            activeColor: Colors.blueAccent,
                            onChanged: (val) {
                              setDialogState(() => isActive = val);
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: _isSaving ? null : () => Navigator.pop(dialogContext),
                  child: const Text('إلغاء', style: TextStyle(color: Colors.white60, fontFamily: 'Cairo')),
                ),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isEditing ? Colors.amber.shade700 : Colors.blueAccent,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  icon: _isSaving
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.check_circle_rounded, size: 18),
                  label: Text(
                    isEditing ? 'حفظ التعديلات' : 'إضافة الصنف',
                    style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold),
                  ),
                  onPressed: _isSaving
                      ? null
                      : () async {
                          if (formKey.currentState!.validate()) {
                            setDialogState(() => _isSaving = true);
                            try {
                              final newItem = ItemModel(
                                barcode: barcodeController.text.trim(),
                                itemName: nameController.text.trim(),
                                unitName: unitController.text.trim(),
                                salesPrice: double.parse(salesPriceController.text.trim()),
                                cost: double.parse(costController.text.trim()),
                                groupId: selectedGroup,
                                itemId: isEditing ? item.itemId : 0,
                                unityId: isEditing ? item.unityId : 1,
                                moneyId: isEditing ? item.moneyId : 1,
                                isActive: isActive,
                              );

                              if (isEditing) {
                                await apiService.updateItem(newItem);
                              } else {
                                await apiService.addItem(newItem);
                              }

                              if (mounted) {
                                Navigator.pop(dialogContext);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      isEditing ? 'تم تعديل الصنف بنجاح' : 'تم إضافة الصنف بنجاح إلى جدول List',
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
                                    content: Text('خطأ: $e', style: const TextStyle(fontFamily: 'Cairo')),
                                    backgroundColor: Colors.red,
                                  ),
                                );
                              }
                            } finally {
                              setDialogState(() => _isSaving = false);
                            }
                          }
                        },
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _confirmDelete(ItemModel item) {
    showDialog(
      context: context,
      builder: (dialogContext) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: const Color(0xFF0F172A),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: Colors.redAccent, width: 1.5),
          ),
          title: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.redAccent, size: 28),
              SizedBox(width: 8),
              Text('تأكيد تعطيل / إيقاف الصنف', style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, color: Colors.white)),
            ],
          ),
          content: Text(
            'هل أنت أصل من إيقاف الصنف "${item.itemName}" (الباركود: ${item.barcode})؟\nسيتم تعطيل الصنف وعدم إظهاره في عمليات البيع.',
            style: const TextStyle(fontFamily: 'Cairo', color: Colors.white70),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('إلغاء', style: TextStyle(fontFamily: 'Cairo', color: Colors.white60)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white),
              onPressed: () async {
                final apiService = Provider.of<ApiService>(context, listen: false);
                Navigator.pop(dialogContext);
                try {
                  await apiService.deleteItem(item.itemId);
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('تم تعطيل الصنف بنجاح', style: TextStyle(fontFamily: 'Cairo')), backgroundColor: Colors.orange),
                    );
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('خطأ: $e', style: const TextStyle(fontFamily: 'Cairo')), backgroundColor: Colors.red),
                    );
                  }
                }
              },
              child: const Text('تأكيد الإيقاف', style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext meContext) {
    final currencyFormatter = NumberFormat('#,##0.00', 'ar');

    return Consumer<ApiService>(
      builder: (context, apiService, child) {
        final allItems = apiService.items;
        final groups = apiService.groups;
        final filteredItems = _filterItems(allItems);

        final totalItemsCount = allItems.length;
        final activeItemsCount = allItems.where((i) => i.isActive).length;
        final totalInventoryCost = allItems.fold(0.0, (sum, i) => sum + i.cost);
        final avgSalesPrice = totalItemsCount > 0 ? allItems.fold(0.0, (sum, i) => sum + i.salesPrice) / totalItemsCount : 0.0;

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
                            child: const Icon(Icons.inventory_2_rounded, color: Colors.blueAccent, size: 28),
                          ),
                          const SizedBox(width: 14),
                          const Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'شاشة إدارة وحركة الأصناف (جدول List)',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold,
                                  fontFamily: 'Cairo',
                                ),
                              ),
                              Text(
                                'إضافة، تعديل، استعلام وبحث فوري في قاعدة بيانات الأصناف المعتمدة',
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
                            icon: _isSyncingItems
                                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                : const Icon(Icons.sync_rounded, size: 18),
                            label: const Text('مزامنة الأصناف من السيرفر الرئيسي', style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
                            onPressed: _isSyncingItems || !apiService.isConnected
                                ? null
                                : () async {
                                    setState(() => _isSyncingItems = true);
                                    try {
                                      final msg = await apiService.syncItems();
                                      await apiService.reloadItems();
                                      if (mounted) {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(
                                            content: Text('✅ $msg - تم إعادة تحديث وعرض الأصناف تلقائياً!', style: const TextStyle(fontFamily: 'Cairo')),
                                            backgroundColor: Colors.teal.shade700,
                                          ),
                                        );
                                      }
                                    } catch (e) {
                                      if (mounted) {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(
                                            content: Text('❌ خطأ أثناء المزامنة: $e', style: const TextStyle(fontFamily: 'Cairo')),
                                            backgroundColor: Colors.redAccent,
                                          ),
                                        );
                                      }
                                    } finally {
                                      if (mounted) setState(() => _isSyncingItems = false);
                                    }
                                  },
                          ),
                          const SizedBox(width: 10),
                          IconButton(
                            tooltip: 'إعادة تحديث القائمة',
                            icon: const Icon(Icons.refresh_rounded, color: Colors.white70),
                            onPressed: () => apiService.reloadItems(),
                          ),
                          const SizedBox(width: 10),
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blueAccent,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              elevation: 4,
                            ),
                            icon: const Icon(Icons.add_circle_outline_rounded, size: 20),
                            label: const Text(
                              'إضافة صنف جديد',
                              style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 14),
                            ),
                            onPressed: () => _openAddEditDialog(),
                          ),
                        ],
                      ),
                    ],
                  ),

                  const SizedBox(height: 20),

                  // --- STATS OVERVIEW CARDS ---
                  Row(
                    children: [
                      _buildStatCard(
                        title: 'إجمالي الأصناف',
                        value: '$totalItemsCount صنف',
                        icon: Icons.list_alt_rounded,
                        color: Colors.blue,
                      ),
                      const SizedBox(width: 14),
                      _buildStatCard(
                        title: 'الأصناف النشطة',
                        value: '$activeItemsCount صنف',
                        icon: Icons.check_circle_outline_rounded,
                        color: Colors.green,
                      ),
                      const SizedBox(width: 14),
                      _buildStatCard(
                        title: 'متوسط سعر البيع',
                        value: '${currencyFormatter.format(avgSalesPrice)} ر.ي',
                        icon: Icons.price_change_outlined,
                        color: Colors.purpleAccent,
                      ),
                      const SizedBox(width: 14),
                      _buildStatCard(
                        title: 'إجمالي قيمة التكلفة',
                        value: '${currencyFormatter.format(totalInventoryCost)} ر.ي',
                        icon: Icons.account_balance_wallet_outlined,
                        color: Colors.orangeAccent,
                      ),
                    ],
                  ),

                  const SizedBox(height: 20),

                  // --- SEARCH & FILTERS BAR ---
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E293B),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.white10),
                    ),
                    child: Row(
                      children: [
                        // Search Field
                        Expanded(
                          flex: 3,
                          child: TextField(
                            controller: _searchController,
                            onChanged: (val) => setState(() {}),
                            style: const TextStyle(color: Colors.white, fontFamily: 'Cairo'),
                            decoration: InputDecoration(
                              hintText: 'البحث باسم الصنف أو الباركود أو الرقم...',
                              hintStyle: const TextStyle(color: Colors.white38, fontFamily: 'Cairo'),
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
                              filled: true,
                              fillColor: const Color(0xFF0F172A),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: BorderSide.none,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 14),

                        // Group Dropdown Filter
                        Expanded(
                          flex: 2,
                          child: DropdownButtonFormField<int>(
                            value: _selectedGroupId,
                            dropdownColor: const Color(0xFF1E293B),
                            style: const TextStyle(color: Colors.white, fontFamily: 'Cairo', fontSize: 13),
                            decoration: InputDecoration(
                              labelText: 'تصفية بالمجموعة',
                              labelStyle: const TextStyle(color: Colors.white60, fontFamily: 'Cairo'),
                              filled: true,
                              fillColor: const Color(0xFF0F172A),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: BorderSide.none,
                              ),
                            ),
                            items: [
                              const DropdownMenuItem<int>(
                                value: 0,
                                child: Text('جميع المجموعات', style: TextStyle(fontFamily: 'Cairo')),
                              ),
                              ...groups.map((g) => DropdownMenuItem<int>(
                                    value: g.id,
                                    child: Text(g.name, style: const TextStyle(fontFamily: 'Cairo')),
                                  )),
                            ],
                            onChanged: (val) {
                              if (val != null) {
                                setState(() => _selectedGroupId = val);
                              }
                            },
                          ),
                        ),
                        const SizedBox(width: 14),

                        // Active Filter Segmented Toggle
                        Container(
                          decoration: BoxDecoration(
                            color: const Color(0xFF0F172A),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            children: [
                              _buildFilterChip('الكل', 'all'),
                              _buildFilterChip('النشطة فقط', 'active'),
                              _buildFilterChip('المعطلة', 'inactive'),
                            ],
                          ),
                        ),
                      ],
                    ),
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
                      child: apiService.isLoading
                          ? const Center(child: CircularProgressIndicator(color: Colors.blueAccent))
                          : filteredItems.isEmpty
                              ? _buildEmptyState()
                              : ClipRRect(
                                  borderRadius: BorderRadius.circular(14),
                                  child: SingleChildScrollView(
                                    scrollDirection: Axis.vertical,
                                    child: SingleChildScrollView(
                                      scrollDirection: Axis.horizontal,
                                      child: DataTable(
                                        headingRowColor: MaterialStateProperty.all(const Color(0xFF0F172A)),
                                        headingTextStyle: const TextStyle(
                                          color: Colors.blueAccent,
                                          fontWeight: FontWeight.bold,
                                          fontFamily: 'Cairo',
                                          fontSize: 14,
                                        ),
                                        dataTextStyle: const TextStyle(color: Colors.white, fontFamily: 'Cairo', fontSize: 13),
                                        dividerThickness: 0.5,
                                        horizontalMargin: 20,
                                        columnSpacing: 24,
                                        columns: const [
                                          DataColumn(label: Text('# ID')),
                                          DataColumn(label: Text('الباركود')),
                                          DataColumn(label: Text('اسم الصنف')),
                                          DataColumn(label: Text('الوحدة')),
                                          DataColumn(label: Text('المجموعة')),
                                          DataColumn(label: Text('سعر البيع')),
                                          DataColumn(label: Text('التكلفة')),
                                          DataColumn(label: Text('الحالة')),
                                          DataColumn(label: Text('الإجراءات')),
                                        ],
                                        rows: filteredItems.map((item) {
                                          final groupName = groups.firstWhere(
                                            (g) => g.id == item.groupId,
                                            orElse: () => ItemGroupModel(id: item.groupId, name: 'مجموعة (${item.groupId})'),
                                          ).name;

                                          return DataRow(
                                            cells: [
                                              DataCell(Text(item.itemId.toString(), style: const TextStyle(color: Colors.white54))),
                                              DataCell(
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                  decoration: BoxDecoration(
                                                    color: Colors.blueAccent.withOpacity(0.1),
                                                    borderRadius: BorderRadius.circular(6),
                                                    border: Border.all(color: Colors.blueAccent.withOpacity(0.2)),
                                                  ),
                                                  child: Text(
                                                    item.barcode,
                                                    style: const TextStyle(color: Colors.blueAccent, fontWeight: FontWeight.bold, fontFamily: 'monospace'),
                                                  ),
                                                ),
                                              ),
                                              DataCell(
                                                Text(
                                                  item.itemName,
                                                  style: const TextStyle(fontWeight: FontWeight.bold),
                                                ),
                                              ),
                                              DataCell(Text(item.unitName.isNotEmpty ? item.unitName : 'حبة')),
                                              DataCell(Text(groupName, style: const TextStyle(color: Colors.white70))),
                                              DataCell(
                                                Text(
                                                  '${currencyFormatter.format(item.salesPrice)} ر.ي',
                                                  style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold),
                                                ),
                                              ),
                                              DataCell(
                                                Text(
                                                  '${currencyFormatter.format(item.cost)} ر.ي',
                                                  style: const TextStyle(color: Colors.orangeAccent),
                                                ),
                                              ),
                                              DataCell(
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                                  decoration: BoxDecoration(
                                                    color: item.isActive ? Colors.green.withOpacity(0.15) : Colors.red.withOpacity(0.15),
                                                    borderRadius: BorderRadius.circular(20),
                                                    border: Border.all(color: item.isActive ? Colors.green : Colors.red),
                                                  ),
                                                  child: Text(
                                                    item.isActive ? 'نشط' : 'معطل',
                                                    style: TextStyle(
                                                      color: item.isActive ? Colors.greenAccent : Colors.redAccent,
                                                      fontSize: 12,
                                                      fontWeight: FontWeight.bold,
                                                      fontFamily: 'Cairo',
                                                    ),
                                                  ),
                                                ),
                                              ),
                                              DataCell(
                                                Row(
                                                  mainAxisSize: MainAxisSize.min,
                                                  children: [
                                                    IconButton(
                                                      tooltip: 'طباعة ملصق الباركود للصنف (طابعة حرارية)',
                                                      icon: const Icon(Icons.qr_code_2_rounded, color: Colors.tealAccent, size: 20),
                                                      onPressed: () => _showBarcodePrintDialog(item),
                                                    ),
                                                    IconButton(
                                                      tooltip: 'كشف حركة الصنف تفصيلي',
                                                      icon: const Icon(Icons.history_rounded, color: Colors.cyanAccent, size: 20),
                                                      onPressed: () {
                                                        showDialog(
                                                          context: context,
                                                          builder: (dialogContext) => Dialog(
                                                            backgroundColor: const Color(0xFF0F172A),
                                                            insetPadding: const EdgeInsets.all(20),
                                                            child: SizedBox(
                                                              width: 1200,
                                                              height: 800,
                                                              child: ItemMovementView(initialQuery: item.barcode),
                                                            ),
                                                          ),
                                                        );
                                                      },
                                                    ),
                                                    IconButton(
                                                      tooltip: 'تعديل بيانات الصنف',
                                                      icon: const Icon(Icons.edit_outlined, color: Colors.amberAccent, size: 20),
                                                      onPressed: () => _openAddEditDialog(item),
                                                    ),
                                                    IconButton(
                                                      tooltip: 'إيقاف / تعطيل الصنف',
                                                      icon: const Icon(Icons.block_outlined, color: Colors.redAccent, size: 20),
                                                      onPressed: () => _confirmDelete(item),
                                                    ),
                                                  ],
                                                ),
                                              ),
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
      },
    );
  }

  Widget _buildFilterChip(String label, String value) {
    final isSelected = _activeFilter == value;
    return InkWell(
      onTap: () => setState(() => _activeFilter = value),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? Colors.blueAccent : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : Colors.white60,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            fontSize: 12,
            fontFamily: 'Cairo',
          ),
        ),
      ),
    );
  }

  Widget _buildStatCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF1E293B),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withOpacity(0.3)),
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
                  Text(
                    title,
                    style: const TextStyle(color: Colors.white60, fontSize: 12, fontFamily: 'Cairo'),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'Cairo',
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.inventory_2_outlined, size: 64, color: Colors.white.withOpacity(0.2)),
          const SizedBox(height: 12),
          const Text(
            'لا توجد أصناف تطابق معايير البحث',
            style: TextStyle(color: Colors.white70, fontSize: 16, fontFamily: 'Cairo', fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          const Text(
            'جرب تغيير كلمة البحث أو تصفية المجموعات، أو أضف صنف جديد.',
            style: TextStyle(color: Colors.white38, fontSize: 12, fontFamily: 'Cairo'),
          ),
        ],
      ),
    );
  }

  void _showBarcodePrintDialog(ItemModel item) {
    BarcodeLabelService.showQuickBarcodePrintDialog(
      context: context,
      item: item,
      onOpenDesigner: () {
        showDialog(
          context: context,
          builder: (dialogContext) => Dialog(
            backgroundColor: const Color(0xFF0F172A),
            insetPadding: const EdgeInsets.all(16),
            child: SizedBox(
              width: 1200,
              height: 800,
              child: BarcodePrintView(initialItem: item),
            ),
          ),
        );
      },
    );
  }
}

