import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/api_service.dart';

class AccountsView extends StatefulWidget {
  const AccountsView({super.key});

  @override
  State<AccountsView> createState() => _AccountsViewState();
}

class _AccountsViewState extends State<AccountsView> {
  final _nameController = TextEditingController();
  final _accIdController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  String _searchQuery = '';

  @override
  void dispose() {
    _nameController.dispose();
    _accIdController.dispose();
    super.dispose();
  }

  void _showAddAccountDialog() {
    _nameController.clear();
    _accIdController.clear();
    final apiService = Provider.of<ApiService>(context, listen: false);

    showDialog(
      context: context,
      builder: (context) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            backgroundColor: const Color(0xFF0F172A),
            title: const Text(
              'إضافة عميل / مورد / حساب جديد',
              style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, color: Colors.white),
            ),
            content: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Searchable General Ledger Account list
                  Autocomplete<Map<String, dynamic>>(
                    optionsBuilder: (TextEditingValue textEditingValue) {
                      if (textEditingValue.text.isEmpty) {
                        return apiService.remoteAccounts;
                      }
                      return apiService.remoteAccounts.where((option) {
                        return option['name'].toString().toLowerCase().contains(textEditingValue.text.toLowerCase()) ||
                               option['id'].toString().contains(textEditingValue.text);
                      });
                    },
                    displayStringForOption: (option) => '${option['name']} (${option['id']})',
                    fieldViewBuilder: (context, fieldTextEditingController, fieldFocusNode, onFieldSubmitted) {
                      return TextFormField(
                        controller: fieldTextEditingController,
                        focusNode: fieldFocusNode,
                        style: const TextStyle(color: Colors.white, fontFamily: 'Cairo'),
                        decoration: const InputDecoration(
                          labelText: 'البحث عن حساب الأستاذ (dbo.tblAccount)',
                          labelStyle: TextStyle(color: Colors.white70, fontFamily: 'Cairo'),
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.search, color: Colors.white70),
                          helperText: 'ابحث بالاسم أو رقم الحساب من قاعدة البيانات الرئيسية',
                          helperStyle: TextStyle(color: Colors.white30, fontFamily: 'Cairo', fontSize: 10),
                        ),
                        validator: (val) {
                          if (val == null || val.isEmpty) return 'يرجى اختيار حساب';
                          if (_accIdController.text.isEmpty) return 'يرجى اختيار حساب من القائمة المنسدلة';
                          return null;
                        },
                      );
                    },
                    optionsViewBuilder: (context, onSelected, options) {
                      return Align(
                        alignment: Alignment.topRight,
                        child: Material(
                          elevation: 4.0,
                          color: const Color(0xFF1E293B),
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            width: 320,
                            constraints: const BoxConstraints(maxHeight: 250),
                            child: ListView.builder(
                              padding: EdgeInsets.zero,
                              shrinkWrap: true,
                              itemCount: options.length,
                              itemBuilder: (BuildContext context, int index) {
                                final option = options.elementAt(index);
                                return ListTile(
                                  title: Text(
                                    option['name'],
                                    style: const TextStyle(color: Colors.white, fontFamily: 'Cairo', fontSize: 13),
                                  ),
                                  subtitle: Text(
                                    'رقم الحساب: ${option['id']}',
                                    style: const TextStyle(color: Colors.white54, fontFamily: 'Cairo', fontSize: 11),
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
                    onSelected: (selection) {
                      _nameController.text = selection['name'];
                      _accIdController.text = selection['id'].toString();
                    },
                  ),
                  const SizedBox(height: 16),
                  
                  // Display Selected Name
                  TextFormField(
                    controller: _nameController,
                    style: const TextStyle(color: Colors.white, fontFamily: 'Cairo'),
                    decoration: const InputDecoration(
                      labelText: 'الاسم الكامل / اسم الحساب (منقول تلقائياً)',
                      labelStyle: TextStyle(color: Colors.white70, fontFamily: 'Cairo'),
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.person_add_alt_1_outlined, color: Colors.white70),
                    ),
                    validator: (val) {
                      if (val == null || val.isEmpty) return 'يرجى إدخال الاسم';
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),

                  // Display Selected AccID
                  TextFormField(
                    controller: _accIdController,
                    readOnly: true,
                    style: const TextStyle(color: Colors.white54, fontFamily: 'Cairo'),
                    decoration: const InputDecoration(
                      labelText: 'رقم حساب الأستاذ المختار (AccID)',
                      labelStyle: TextStyle(color: Colors.white70, fontFamily: 'Cairo'),
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.account_balance_wallet_outlined, color: Colors.white30),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('إلغاء', style: TextStyle(fontFamily: 'Cairo')),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent),
                onPressed: () async {
                  if (!_formKey.currentState!.validate()) return;
                  
                  try {
                    await apiService.addAccount(
                      _nameController.text.trim(),
                      int.parse(_accIdController.text),
                    );
                    if (mounted) {
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('تم حفظ الاسم بنجاح في SQL Server', style: TextStyle(fontFamily: 'Cairo')),
                          backgroundColor: Colors.green,
                        ),
                      );
                    }
                  } catch (e) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('فشل الحفظ: $e', style: const TextStyle(fontFamily: 'Cairo')),
                          backgroundColor: Colors.red,
                        ),
                      );
                    }
                  }
                },
                child: const Text('حفظ في قاعدة البيانات', style: TextStyle(fontFamily: 'Cairo', color: Colors.white)),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final apiService = Provider.of<ApiService>(context);
    final filteredAccounts = apiService.accounts.where((acc) {
      return acc.name.toLowerCase().contains(_searchQuery.toLowerCase()) ||
             acc.id.toString() == _searchQuery ||
             acc.accId.toString() == _searchQuery;
    }).toList();

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      body: Directionality(
        textDirection: TextDirection.rtl,
        child: Padding(
          padding: const EdgeInsets.all(32.0),
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
                        'دليل العملاء والموردين والحسابات',
                        style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold, fontFamily: 'Cairo'),
                      ),
                      Text(
                        'عرض وإدارة الحسابات المسجلة في جدول tblExpensesList',
                        style: TextStyle(color: Colors.white54, fontSize: 13, fontFamily: 'Cairo'),
                      ),
                    ],
                  ),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blueAccent,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    icon: const Icon(Icons.person_add_rounded),
                    label: const Text('إضافة حساب جديد', style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
                    onPressed: () async {
                      showDialog(
                        context: context,
                        barrierDismissible: false,
                        builder: (context) => const Center(child: CircularProgressIndicator()),
                      );
                      try {
                        await apiService.fetchRemoteAccounts();
                        if (context.mounted) {
                          Navigator.pop(context); // close loader
                          _showAddAccountDialog();
                        }
                      } catch (e) {
                        if (context.mounted) {
                          Navigator.pop(context); // close loader
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('فشل جلب الحسابات من قاعدة البيانات الرئيسية: $e', style: const TextStyle(fontFamily: 'Cairo')),
                              backgroundColor: Colors.red,
                            ),
                          );
                        }
                      }
                    },
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // Search bar
              Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: TextField(
                  style: const TextStyle(color: Colors.white, fontFamily: 'Cairo'),
                  decoration: const InputDecoration(
                    hintText: 'البحث عن زبون أو مورد بالاسم أو المعرف الرقمي...',
                    hintStyle: TextStyle(color: Colors.white30, fontFamily: 'Cairo'),
                    prefixIcon: Icon(Icons.search, color: Colors.white54),
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  ),
                  onChanged: (val) {
                    setState(() {
                      _searchQuery = val;
                    });
                  },
                ),
              ),
              const SizedBox(height: 20),

              // Accounts list
              Expanded(
                child: apiService.isLoading && apiService.accounts.isEmpty
                    ? const Center(child: CircularProgressIndicator())
                    : filteredAccounts.isEmpty
                        ? const Center(
                            child: Text(
                              'لا توجد حسابات مسجلة تطابق البحث.',
                              style: TextStyle(color: Colors.white30, fontSize: 16, fontFamily: 'Cairo'),
                            ),
                          )
                        : ListView.builder(
                            itemCount: filteredAccounts.length,
                            itemBuilder: (context, index) {
                              final acc = filteredAccounts[index];
                              return Card(
                                color: const Color(0xFF1E293B),
                                margin: const EdgeInsets.only(bottom: 12),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                child: ListTile(
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                                  leading: CircleAvatar(
                                    backgroundColor: Colors.blueAccent.withOpacity(0.1),
                                    child: const Icon(Icons.account_box, color: Colors.blueAccent),
                                  ),
                                  title: Text(
                                    acc.name,
                                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15, fontFamily: 'Cairo'),
                                  ),
                                  subtitle: Text(
                                    'رقم الحساب الفريد: ${acc.id}  |  حساب الأستاذ العام: ${acc.accId}',
                                    style: const TextStyle(color: Colors.white54, fontSize: 12, fontFamily: 'Cairo'),
                                  ),
                                  trailing: const Icon(Icons.arrow_forward_ios, color: Colors.white24, size: 16),
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
