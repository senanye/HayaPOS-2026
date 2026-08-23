import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:universal_html/js.dart' as js;
import '../services/api_service.dart';
import '../models/user.dart';
import 'main_shell.dart';

class LoginView extends StatefulWidget {
  const LoginView({super.key});

  @override
  State<LoginView> createState() => _LoginViewState();
}

class _LoginViewState extends State<LoginView> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  
  final _dateFocus = FocusNode();
  final _usernameFocus = FocusNode();
  final _passwordFocus = FocusNode();
  
  final _formKey = GlobalKey<FormState>();
  bool _obscurePassword = true;
  bool _isSyncingUsers = false;

  bool _isCheckingUpdate = false;
  bool _hasUpdate = false;
  String _latestVersion = '';
  Map<String, dynamic>? _updateInfo;

  bool _isSpecialLogin = false;
  bool _isSpecialLoginUnlocked = false;
  List<Map<String, dynamic>> _remotePoints = [];
  int? _selectedPointNo;
  List<Map<String, dynamic>> _remotePointUsers = [];
  bool _isLoadingPoints = false;
  bool _isLoadingPointUsers = false;

  void _showUnlockSpecialLoginDialog() {
    final pinController = TextEditingController();
    String? pinError;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateDialog) => Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            backgroundColor: const Color(0xFF1E293B),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            title: const Row(
              children: [
                Icon(Icons.security_rounded, color: Colors.amberAccent, size: 24),
                SizedBox(width: 10),
                Text(
                  'التحقق من صلاحية الفروع البعيدة 🔐',
                  style: TextStyle(color: Colors.white, fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'يرجى إدخال رمز فك القفل السري للوصول لخيارات نقاط البيع والفروع البعيدة:',
                  style: TextStyle(color: Colors.white70, fontFamily: 'Cairo', fontSize: 13),
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: pinController,
                  obscureText: true,
                  autofocus: true,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(color: Colors.amberAccent, letterSpacing: 4, fontWeight: FontWeight.bold, fontSize: 18),
                  decoration: InputDecoration(
                    labelText: 'رمز الفك السري (PIN)',
                    labelStyle: const TextStyle(color: Colors.white70, fontFamily: 'Cairo'),
                    errorText: pinError,
                    prefixIcon: const Icon(Icons.key_rounded, color: Colors.amberAccent),
                    enabledBorder: OutlineInputBorder(borderSide: const BorderSide(color: Colors.white24), borderRadius: BorderRadius.circular(8)),
                    focusedBorder: OutlineInputBorder(borderSide: const BorderSide(color: Colors.amberAccent, width: 2), borderRadius: BorderRadius.circular(8)),
                  ),
                  onFieldSubmitted: (val) {
                    if (val.trim() == "2026" || val.trim() == "2025" || val.trim() == "8888") {
                      Navigator.pop(context);
                      setState(() {
                        _isSpecialLoginUnlocked = true;
                        _isSpecialLogin = true;
                      });
                      if (_remotePoints.isEmpty) {
                        _loadRemotePoints();
                      }
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('تم فك قفل الدخول الخاص بالفروع البعيدة بنجاح 🔓', style: TextStyle(fontFamily: 'Cairo')),
                          backgroundColor: Colors.green,
                        ),
                      );
                    } else {
                      setStateDialog(() {
                        pinError = 'رمز الفك السري غير صحيح!';
                      });
                    }
                  },
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('إلغاء', style: TextStyle(color: Colors.white60, fontFamily: 'Cairo')),
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.amber[700]),
                icon: const Icon(Icons.lock_open_rounded, color: Colors.white),
                label: const Text('تحقق وفك القفل', style: TextStyle(color: Colors.white, fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
                onPressed: () {
                  final val = pinController.text;
                  if (val.trim() == "2026" || val.trim() == "2025" || val.trim() == "8888") {
                    Navigator.pop(context);
                    setState(() {
                      _isSpecialLoginUnlocked = true;
                      _isSpecialLogin = true;
                    });
                    if (_remotePoints.isEmpty) {
                      _loadRemotePoints();
                    }
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('تم فك قفل الدخول الخاص بالفروع البعيدة بنجاح 🔓', style: TextStyle(fontFamily: 'Cairo')),
                        backgroundColor: Colors.green,
                      ),
                    );
                  } else {
                    setStateDialog(() {
                      pinError = 'رمز الفك السري غير صحيح!';
                    });
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _loadRemotePoints() async {
    setState(() => _isLoadingPoints = true);
    final apiService = Provider.of<ApiService>(context, listen: false);
    final points = await apiService.fetchRemotePoints();
    if (mounted) {
      setState(() {
        _remotePoints = points;
        _isLoadingPoints = false;
        if (_remotePoints.isNotEmpty) {
          final firstPointNo = (_remotePoints.first['pointNo'] as num?)?.toInt() ?? 1;
          _selectedPointNo = firstPointNo;
          apiService.setActiveBranchPoint(firstPointNo);
          _loadRemoteUsersForSelectedPoint(firstPointNo);
        } else {
          _selectedPointNo = null;
        }
      });
    }
  }

  Future<void> _loadRemoteUsersForSelectedPoint(int pointNo) async {
    setState(() {
      _isLoadingPointUsers = true;
      _remotePointUsers = [];
      _usernameController.clear();
    });
    final apiService = Provider.of<ApiService>(context, listen: false);
    final res = await apiService.fetchRemotePointUsers(pointNo);
    if (mounted) {
      setState(() {
        final List<dynamic> usersList = res['users'] ?? [];
        _remotePointUsers = usersList.map((x) => Map<String, dynamic>.from(x)).toList();

        final String ds = res['dataSource']?.toString() ?? '';
        if (ds.isNotEmpty) {
          final idx = _remotePoints.indexWhere((p) => (p['pointNo'] as num?)?.toInt() == pointNo);
          if (idx != -1) {
            _remotePoints[idx]['dataSource'] = ds;
          }
        }

        _isLoadingPointUsers = false;
        if (_remotePointUsers.isNotEmpty) {
          _usernameController.text = _remotePointUsers.first['userName'] ?? '';
        }
      });
    }
  }

  @override
  void initState() {
    super.initState();
    _isSpecialLogin = false;
    _isSpecialLoginUnlocked = false;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final apiService = Provider.of<ApiService>(context, listen: false);
      apiService.fetchUsers();
    });
  }

  // ==========================================================
  //          وظائف التحديث الأونلاين التلقائي (Auto Update)
  // ==========================================================

  Future<void> _checkSystemUpdate({bool manual = false}) async {
    if (_isCheckingUpdate) return;
    setState(() => _isCheckingUpdate = true);

    try {
      final apiService = Provider.of<ApiService>(context, listen: false);
      final res = await apiService.checkSystemUpdate();
      
      if (mounted) {
        setState(() {
          _isCheckingUpdate = false;
          _hasUpdate = res['has_update'] == true;
          _latestVersion = res['latest_version'] ?? '';
          _updateInfo = res;
        });

        if (manual) {
          if (_hasUpdate) {
            _showUpdateDialog();
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  res['message'] ?? 'نظامك محدث إلى آخر إصدار.',
                  style: const TextStyle(fontFamily: 'Cairo'),
                ),
                backgroundColor: Colors.green.shade700,
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
        } else if (_hasUpdate) {
          _showUpdateDialog();
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isCheckingUpdate = false);
        if (manual) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('خطأ أثناء فحص التحديثات: $e', style: const TextStyle(fontFamily: 'Cairo')),
              backgroundColor: Colors.red.shade700,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    }
  }

  void _showUpdateDialog() {
    if (_updateInfo == null) return;
    final changelog = _updateInfo?['changelog'] as List<dynamic>? ?? [];
    final latestVer = _latestVersion;
    final currentVer = _updateInfo?['current_version'] ?? '1.0.0';
    final isMandatory = _updateInfo?['is_mandatory'] == true;
    bool isUpdating = false;
    String updateStatusText = '';

    showDialog(
      context: context,
      barrierDismissible: !isMandatory,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (context, setDialogState) => Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
            backgroundColor: const Color(0xFF1E232D),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.amber.withOpacity(0.2),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.rocket_launch_rounded, color: Colors.amber, size: 26),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'يوجد تحديث جديد متاح للنظام',
                        style: TextStyle(fontFamily: 'Cairo', fontSize: 17, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                      Text(
                        'الإصدار الحالي: $currentVer  ←  الإصدار الجديد: $latestVer',
                        style: TextStyle(fontFamily: 'Cairo', fontSize: 12, color: Colors.blueAccent.shade100),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            content: SizedBox(
              width: 480,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Divider(color: Colors.white12),
                  const SizedBox(height: 6),
                  const Text(
                    'أبرز التحسينات والمميزات الجديدة:',
                    style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 13, color: Colors.white70),
                  ),
                  const SizedBox(height: 8),
                  if (changelog.isNotEmpty)
                    ...changelog.map((log) => Padding(
                          padding: const EdgeInsets.only(bottom: 6.0),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(Icons.check_circle_outline, color: Colors.greenAccent, size: 16),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  log.toString(),
                                  style: const TextStyle(fontFamily: 'Cairo', fontSize: 13, color: Colors.white),
                                ),
                              ),
                            ],
                          ),
                        ))
                  else
                    const Text('تحسينات عامة واستقرار للنظام.', style: TextStyle(fontFamily: 'Cairo', color: Colors.white)),
                  const SizedBox(height: 12),
                  if (isUpdating) ...[
                    const SizedBox(height: 8),
                    LinearProgressIndicator(backgroundColor: Colors.white10, color: Colors.greenAccent.shade400),
                    const SizedBox(height: 10),
                    Center(
                      child: Text(
                        updateStatusText.isNotEmpty ? updateStatusText : 'جاري تحميل التحديث وتثبيته... يرجى الانتظار',
                        style: const TextStyle(fontFamily: 'Cairo', fontSize: 12, color: Colors.amberAccent),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              if (!isMandatory && !isUpdating)
                TextButton(
                  onPressed: () => Navigator.pop(dialogCtx),
                  child: const Text('تذكيري لاحقاً', style: TextStyle(fontFamily: 'Cairo', color: Colors.white54)),
                ),
              if (!isUpdating)
                ElevatedButton.icon(
                  icon: const Icon(Icons.download_for_offline_rounded, color: Colors.white, size: 18),
                  label: const Text('تحديث النظام الآن (1-Click)', style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF10B981),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: () async {
                    setDialogState(() {
                      isUpdating = true;
                      updateStatusText = 'جاري الاتصال بـ GitHub وتنزيل التحديث...';
                    });
                    
                    final apiService = Provider.of<ApiService>(context, listen: false);
                    final updateRes = await apiService.applySystemUpdate(
                      updateUrl: _updateInfo?['update_url'],
                    );

                    if (updateRes['status'] == 'success') {
                      setDialogState(() {
                        updateStatusText = 'تم تثبيت التحديث بنجاح! جاري إعادة تشغيل الواجهة...';
                      });
                      await Future.delayed(const Duration(seconds: 2));
                      if (kIsWeb) {
                        try {
                          js.context['location'].callMethod('reload', []);
                        } catch (_) {}
                      }
                      if (mounted) Navigator.pop(dialogCtx);
                    } else {
                      setDialogState(() {
                        isUpdating = false;
                        updateStatusText = '';
                      });
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(updateRes['message'] ?? 'فشل التحديث', style: const TextStyle(fontFamily: 'Cairo')),
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

  Future<void> _selectDate(BuildContext context, ApiService apiService) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime.parse(apiService.selectedDate),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.dark(
              primary: Colors.blueAccent,
              onPrimary: Colors.white,
              surface: Color(0xFF1E293B),
              onSurface: Colors.white,
            ),
            dialogBackgroundColor: const Color(0xFF0F172A),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      final formatted = DateFormat('yyyy-MM-dd').format(picked);
      await apiService.updateSelectedDate(formatted);
      if (mounted) {
        FocusScope.of(context).requestFocus(_usernameFocus);
      }
    }
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _dateFocus.dispose();
    _usernameFocus.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  void _showSettingsSecurityCheck(BuildContext context) {
    final adminUserCtrl = TextEditingController();
    final adminPassCtrl = TextEditingController();
    final userFocus = FocusNode();
    final passFocus = FocusNode();

    showDialog(
      context: context,
      builder: (context) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: const Color(0xFF1E293B),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          title: const Row(
            children: [
              Icon(Icons.security, color: Colors.amber, size: 28),
              SizedBox(width: 8),
              Text(
                'التحقق من صلاحية مدير النظام',
                style: TextStyle(color: Colors.white, fontFamily: 'Cairo', fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'يُرجى إدخال بيانات مرور مدير النظام لفتح الإعدادات:',
                style: TextStyle(color: Colors.white70, fontFamily: 'Cairo', fontSize: 13),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: adminUserCtrl,
                focusNode: userFocus,
                textInputAction: TextInputAction.next,
                onSubmitted: (_) => FocusScope.of(context).requestFocus(passFocus),
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'اسم المستخدم',
                  labelStyle: TextStyle(color: Colors.white70, fontFamily: 'Cairo'),
                  prefixIcon: Icon(Icons.person, color: Colors.white54),
                  border: OutlineInputBorder(),
                  enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white30)),
                  focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.amber)),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: adminPassCtrl,
                focusNode: passFocus,
                obscureText: true,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'كلمة المرور',
                  labelStyle: TextStyle(color: Colors.white70, fontFamily: 'Cairo'),
                  prefixIcon: Icon(Icons.lock, color: Colors.white54),
                  border: OutlineInputBorder(),
                  enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white30)),
                  focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.amber)),
                ),
                onSubmitted: (_) {
                  if (adminUserCtrl.text.trim() == 'مدير النظام' && adminPassCtrl.text == '1977257863') {
                    Navigator.pop(context);
                    _showDatabaseSettingsDialog(context);
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('عذراً، بيانات مرور مدير النظام غير صحيحة!', style: TextStyle(fontFamily: 'Cairo')),
                        backgroundColor: Colors.redAccent,
                      ),
                    );
                  }
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('إلغاء', style: TextStyle(fontFamily: 'Cairo', color: Colors.white70)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.amber[700]),
              onPressed: () {
                if (adminUserCtrl.text.trim() == 'مدير النظام' && adminPassCtrl.text == '1977257863') {
                  Navigator.pop(context);
                  _showDatabaseSettingsDialog(context);
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('عذراً، بيانات مرور مدير النظام غير صحيحة!', style: TextStyle(fontFamily: 'Cairo')),
                      backgroundColor: Colors.redAccent,
                    ),
                  );
                }
              },
              child: const Text('دخول', style: TextStyle(fontFamily: 'Cairo', color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  void _showDatabaseSettingsDialog(BuildContext context) {
    final apiService = Provider.of<ApiService>(context, listen: false);
    List<Map<String, dynamic>> branchesList = [];
    bool isLoadingBranches = true;
    String? loadError;
    final searchCtrl = TextEditingController();
    String searchQuery = '';
    final hScrollCtrl = ScrollController();
    final vScrollCtrl = ScrollController();
    StateSetter? dialogSetState;

    Map<String, dynamic>? selectedBranch;
    final pointNoCtrl = TextEditingController();
    final pointNameCtrl = TextEditingController();
    final branchNoCtrl = TextEditingController();
    final dsCtrl = TextEditingController(text: r"SENANSERVER\SQLEXPRESS");
    final mainDsCtrl = TextEditingController(text: '');
    final catCtrl = TextEditingController(text: "sp");
    final mainCatCtrl = TextEditingController(text: "sp");
    final userCtrl = TextEditingController(text: "sa");
    final passCtrl = TextEditingController(text: "as");
    final formKey = GlobalKey<FormState>();
    bool isSaving = false;
    bool isTestingConn = false;
    String? formSuccessMsg;
    String? formErrorMsg;

    void populateForm(Map<String, dynamic>? branch) {
      selectedBranch = branch;
      formErrorMsg = null;
      if (branch != null) {
        pointNoCtrl.text = '${branch['pointNo'] ?? ''}';
        pointNameCtrl.text = branch['pointName']?.toString() ?? '';
        branchNoCtrl.text = '${branch['branchNo'] ?? branch['pointNo'] ?? ''}';
        dsCtrl.text = branch['dataSource']?.toString() ?? r"SENANSERVER\SQLEXPRESS";
        mainDsCtrl.text = branch['mainDataSource']?.toString() ?? '';
        catCtrl.text = branch['catalog']?.toString() ?? "sp";
        mainCatCtrl.text = branch['mainCatalog']?.toString() ?? "sp";
        userCtrl.text = branch['userId']?.toString() ?? "sa";
        passCtrl.text = branch['password']?.toString() ?? "as";
      } else {
        int suggestedNo = 1;
        if (branchesList.isNotEmpty) {
          final maxNo = branchesList.fold<int>(0, (prev, elem) {
            final no = (elem['pointNo'] as num?)?.toInt() ?? 0;
            return no > prev ? no : prev;
          });
          suggestedNo = maxNo + 1;
        }
        pointNoCtrl.text = '$suggestedNo';
        pointNameCtrl.text = '';
        branchNoCtrl.text = '$suggestedNo';
        dsCtrl.text = r"SENANSERVER\SQLEXPRESS";
        mainDsCtrl.text = '';
        catCtrl.text = "sp";
        mainCatCtrl.text = "sp";
        userCtrl.text = "sa";
        passCtrl.text = "as";
      }
    }

    Future<void> reloadBranches() async {
      if (dialogSetState != null) {
        dialogSetState!(() => isLoadingBranches = true);
      }
      try {
        final points = await apiService.fetchRemotePoints();
        if (dialogSetState != null) {
          dialogSetState!(() {
            branchesList = points;
            isLoadingBranches = false;
            loadError = null;
            if (selectedBranch == null && branchesList.isNotEmpty) {
              populateForm(branchesList.first);
            }
          });
        }
        if (mounted) {
          setState(() {
            _remotePoints = points;
          });
        }
      } catch (e) {
        if (dialogSetState != null) {
          dialogSetState!(() {
            loadError = e.toString().replaceAll('Exception:', '').trim();
            isLoadingBranches = false;
          });
        }
      }
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateDialog) {
          dialogSetState = setStateDialog;
          if (isLoadingBranches && branchesList.isEmpty && loadError == null) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              reloadBranches();
            });
          }

          final isEditing = selectedBranch != null;

          // Real-time branch filtering
          final filteredBranches = branchesList.where((b) {
            if (searchQuery.trim().isEmpty) return true;
            final q = searchQuery.trim().toLowerCase();
            final pNo = (b['pointNo'] ?? '').toString().toLowerCase();
            final pName = (b['pointName'] ?? '').toString().toLowerCase();
            final bNo = (b['branchNo'] ?? '').toString().toLowerCase();
            final ds = (b['dataSource'] ?? '').toString().toLowerCase();
            final mainDs = (b['mainDataSource'] ?? '').toString().toLowerCase();
            final cat = (b['catalog'] ?? '').toString().toLowerCase();
            final mainCat = (b['mainCatalog'] ?? '').toString().toLowerCase();
            final usr = (b['userId'] ?? '').toString().toLowerCase();
            return pNo.contains(q) ||
                pName.contains(q) ||
                bNo.contains(q) ||
                ds.contains(q) ||
                mainDs.contains(q) ||
                cat.contains(q) ||
                mainCat.contains(q) ||
                usr.contains(q);
          }).toList();

          return Directionality(
            textDirection: TextDirection.rtl,
            child: AlertDialog(
              backgroundColor: const Color(0xFF131722),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.storage_rounded, color: Colors.amberAccent, size: 28),
                          SizedBox(width: 10),
                          Text(
                            'سجل فروع SQLite - لوحة التعديل وإدارة عناوين الاتصال',
                            style: TextStyle(color: Colors.white, fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 17),
                          ),
                        ],
                      ),
                      Row(
                        children: [
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green[700],
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                            icon: const Icon(Icons.add_circle_outline_rounded, color: Colors.white, size: 18),
                            label: const Text(
                              '➕ تفريغ الحقول لإضافة فرع جديد',
                              style: TextStyle(color: Colors.white, fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 12),
                            ),
                            onPressed: () {
                              setStateDialog(() {
                                populateForm(null);
                                formSuccessMsg = null;
                                formErrorMsg = null;
                              });
                            },
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blueAccent,
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                            icon: const Icon(Icons.sync_rounded, color: Colors.white, size: 18),
                            label: const Text(
                              'مزامنة من SQL Server',
                              style: TextStyle(color: Colors.white, fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 12),
                            ),
                            onPressed: () async {
                              await apiService.syncBranchesFromSqlServer();
                              await reloadBranches();
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
              content: SizedBox(
                width: 1100,
                height: 600,
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // --- 1. LIVE DIRECT BRANCH EDITOR FORM ---
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: isEditing
                                ? [const Color(0xFF1E293B), const Color(0xFF0F172A)]
                                : [const Color(0xFF1B2E3B), const Color(0xFF0F1E2A)],
                          ),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isEditing ? Colors.blueAccent.withOpacity(0.5) : Colors.greenAccent.withOpacity(0.5),
                            width: 1.5,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: isEditing ? Colors.blueAccent.withOpacity(0.15) : Colors.greenAccent.withOpacity(0.15),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Form(
                          key: formKey,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Header of the editor
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Row(
                                    children: [
                                      Icon(
                                        isEditing ? Icons.edit_note_rounded : Icons.add_business_rounded,
                                        color: isEditing ? Colors.amberAccent : Colors.greenAccent,
                                        size: 24,
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        isEditing
                                            ? '✏️ نموذج تعديل بيانات الفرع: #${selectedBranch!['pointNo']} (${selectedBranch!['pointName'] ?? ''})'
                                            : '➕ نموذج إضافة عنوان اتصال فرع جديد في SQLite',
                                        style: TextStyle(
                                          color: isEditing ? Colors.amberAccent : Colors.greenAccent,
                                          fontFamily: 'Cairo',
                                          fontWeight: FontWeight.bold,
                                          fontSize: 15,
                                        ),
                                      ),
                                    ],
                                  ),
                                  if (isEditing)
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: Colors.amberAccent.withOpacity(0.15),
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(color: Colors.amberAccent.withOpacity(0.4)),
                                      ),
                                      child: const Text(
                                        'غيّر أي حقل واضغط حفظ التعديلات لتطبيقها فوراً',
                                        style: TextStyle(color: Colors.amberAccent, fontFamily: 'Cairo', fontSize: 11),
                                      ),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 12),

                              // Success / Error Banner
                              if (formSuccessMsg != null) ...[
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                  margin: const EdgeInsets.only(bottom: 12),
                                  decoration: BoxDecoration(
                                    color: Colors.green.withOpacity(0.2),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: Colors.green),
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(Icons.check_circle_rounded, color: Colors.greenAccent, size: 20),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          formSuccessMsg!,
                                          style: const TextStyle(color: Colors.greenAccent, fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 13),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                              if (formErrorMsg != null) ...[
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                  margin: const EdgeInsets.only(bottom: 12),
                                  decoration: BoxDecoration(
                                    color: Colors.redAccent.withOpacity(0.2),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: Colors.redAccent),
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(Icons.error_outline_rounded, color: Colors.redAccent, size: 20),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          formErrorMsg!,
                                          style: const TextStyle(color: Colors.redAccent, fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 12),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],

                              // Fields Row 1: Point No | Branch Name | Branch No
                              Row(
                                children: [
                                  Expanded(
                                    flex: 2,
                                    child: TextFormField(
                                      controller: pointNoCtrl,
                                      keyboardType: TextInputType.number,
                                      decoration: InputDecoration(
                                        labelText: 'رقم النقطة (fldPointNO)',
                                        labelStyle: const TextStyle(color: Colors.amberAccent, fontFamily: 'Cairo', fontSize: 12, fontWeight: FontWeight.bold),
                                        prefixIcon: const Icon(Icons.pin_rounded, color: Colors.amberAccent, size: 18),
                                        isDense: true,
                                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                        enabledBorder: OutlineInputBorder(borderSide: const BorderSide(color: Colors.white24), borderRadius: BorderRadius.circular(8)),
                                        focusedBorder: OutlineInputBorder(borderSide: const BorderSide(color: Colors.amberAccent), borderRadius: BorderRadius.circular(8)),
                                      ),
                                      style: const TextStyle(color: Colors.amberAccent, fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 14),
                                      validator: (v) => (v == null || v.trim().isEmpty) ? 'مطلوب' : null,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    flex: 3,
                                    child: TextFormField(
                                      controller: pointNameCtrl,
                                      decoration: InputDecoration(
                                        labelText: 'اسم الفرع (fldName)',
                                        labelStyle: const TextStyle(color: Colors.white, fontFamily: 'Cairo', fontSize: 12, fontWeight: FontWeight.bold),
                                        prefixIcon: const Icon(Icons.store_rounded, color: Colors.amberAccent, size: 18),
                                        isDense: true,
                                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                        enabledBorder: OutlineInputBorder(borderSide: const BorderSide(color: Colors.white24), borderRadius: BorderRadius.circular(8)),
                                        focusedBorder: OutlineInputBorder(borderSide: const BorderSide(color: Colors.amberAccent), borderRadius: BorderRadius.circular(8)),
                                      ),
                                      style: const TextStyle(color: Colors.white, fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 14),
                                      validator: (v) => (v == null || v.trim().isEmpty) ? 'اسم الفرع مطلوب' : null,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    flex: 2,
                                    child: TextFormField(
                                      controller: branchNoCtrl,
                                      keyboardType: TextInputType.number,
                                      decoration: InputDecoration(
                                        labelText: 'رقم الفرع الأساسي (fldBranchNo)',
                                        labelStyle: const TextStyle(color: Colors.white70, fontFamily: 'Cairo', fontSize: 12),
                                        prefixIcon: const Icon(Icons.tag_rounded, color: Colors.white70, size: 18),
                                        isDense: true,
                                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                        enabledBorder: OutlineInputBorder(borderSide: const BorderSide(color: Colors.white24), borderRadius: BorderRadius.circular(8)),
                                        focusedBorder: OutlineInputBorder(borderSide: const BorderSide(color: Colors.amberAccent), borderRadius: BorderRadius.circular(8)),
                                      ),
                                      style: const TextStyle(color: Colors.white, fontFamily: 'Cairo', fontSize: 13),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),

                              // Fields Row 2: DataSource | Catalog | MainDataSource | MainCatalog
                              Row(
                                children: [
                                  Expanded(
                                    child: TextFormField(
                                      controller: dsCtrl,
                                      decoration: InputDecoration(
                                        labelText: 'سيرفر الفرع (DataSource / IP)',
                                        labelStyle: const TextStyle(color: Colors.cyanAccent, fontFamily: 'Cairo', fontSize: 12),
                                        prefixIcon: const Icon(Icons.dns_rounded, color: Colors.cyanAccent, size: 18),
                                        isDense: true,
                                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                        enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.cyanAccent.withOpacity(0.4)), borderRadius: BorderRadius.circular(8)),
                                        focusedBorder: OutlineInputBorder(borderSide: const BorderSide(color: Colors.cyanAccent), borderRadius: BorderRadius.circular(8)),
                                      ),
                                      style: const TextStyle(color: Colors.cyanAccent, fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 13),
                                      validator: (v) => (v == null || v.trim().isEmpty) ? 'مطلوب' : null,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: TextFormField(
                                      controller: catCtrl,
                                      decoration: InputDecoration(
                                        labelText: 'قاعدة بيانات الفرع (Catalog)',
                                        labelStyle: const TextStyle(color: Colors.white70, fontFamily: 'Cairo', fontSize: 12),
                                        prefixIcon: const Icon(Icons.storage_rounded, color: Colors.white70, size: 18),
                                        isDense: true,
                                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                        enabledBorder: OutlineInputBorder(borderSide: const BorderSide(color: Colors.white24), borderRadius: BorderRadius.circular(8)),
                                        focusedBorder: OutlineInputBorder(borderSide: const BorderSide(color: Colors.amberAccent), borderRadius: BorderRadius.circular(8)),
                                      ),
                                      style: const TextStyle(color: Colors.white, fontFamily: 'Cairo', fontSize: 13),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: TextFormField(
                                      controller: mainDsCtrl,
                                      decoration: InputDecoration(
                                        labelText: 'السيرفر الرئيسي (MainDataSource)',
                                        labelStyle: const TextStyle(color: Colors.amberAccent, fontFamily: 'Cairo', fontSize: 12),
                                        prefixIcon: const Icon(Icons.hub_rounded, color: Colors.amberAccent, size: 18),
                                        isDense: true,
                                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                        enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.amberAccent.withOpacity(0.4)), borderRadius: BorderRadius.circular(8)),
                                        focusedBorder: OutlineInputBorder(borderSide: const BorderSide(color: Colors.amberAccent), borderRadius: BorderRadius.circular(8)),
                                      ),
                                      style: const TextStyle(color: Colors.amberAccent, fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 13),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: TextFormField(
                                      controller: mainCatCtrl,
                                      decoration: InputDecoration(
                                        labelText: 'قاعدة البيانات الرئيسية (MainCatalog)',
                                        labelStyle: const TextStyle(color: Colors.amberAccent, fontFamily: 'Cairo', fontSize: 12),
                                        prefixIcon: const Icon(Icons.account_tree_rounded, color: Colors.amberAccent, size: 18),
                                        isDense: true,
                                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                        enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.amberAccent.withOpacity(0.4)), borderRadius: BorderRadius.circular(8)),
                                        focusedBorder: OutlineInputBorder(borderSide: const BorderSide(color: Colors.amberAccent), borderRadius: BorderRadius.circular(8)),
                                      ),
                                      style: const TextStyle(color: Colors.amberAccent, fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 13),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),

                              // Fields Row 3: User | Password | Actions
                              Row(
                                children: [
                                  Expanded(
                                    child: TextFormField(
                                      controller: userCtrl,
                                      decoration: InputDecoration(
                                        labelText: 'اسم المستخدم (UserID)',
                                        labelStyle: const TextStyle(color: Colors.white70, fontFamily: 'Cairo', fontSize: 12),
                                        prefixIcon: const Icon(Icons.person_rounded, color: Colors.white70, size: 18),
                                        isDense: true,
                                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                        enabledBorder: OutlineInputBorder(borderSide: const BorderSide(color: Colors.white24), borderRadius: BorderRadius.circular(8)),
                                        focusedBorder: OutlineInputBorder(borderSide: const BorderSide(color: Colors.amberAccent), borderRadius: BorderRadius.circular(8)),
                                      ),
                                      style: const TextStyle(color: Colors.white, fontFamily: 'Cairo', fontSize: 13),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: TextFormField(
                                      controller: passCtrl,
                                      obscureText: false,
                                      decoration: InputDecoration(
                                        labelText: 'كلمة المرور (Password)',
                                        labelStyle: const TextStyle(color: Colors.white70, fontFamily: 'Cairo', fontSize: 12),
                                        prefixIcon: const Icon(Icons.key_rounded, color: Colors.white70, size: 18),
                                        isDense: true,
                                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                        enabledBorder: OutlineInputBorder(borderSide: const BorderSide(color: Colors.white24), borderRadius: BorderRadius.circular(8)),
                                        focusedBorder: OutlineInputBorder(borderSide: const BorderSide(color: Colors.amberAccent), borderRadius: BorderRadius.circular(8)),
                                      ),
                                      style: const TextStyle(color: Colors.white, fontFamily: 'Cairo', fontSize: 13),
                                    ),
                                  ),
                                  const SizedBox(width: 12),

                                  // Test Connection Button
                                  OutlinedButton.icon(
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: Colors.cyanAccent,
                                      side: const BorderSide(color: Colors.cyanAccent),
                                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                    ),
                                    icon: isTestingConn
                                        ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.cyanAccent))
                                        : const Icon(Icons.sensors_rounded, size: 18),
                                    label: const Text('فحص الاتصال 📡', style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 12)),
                                    onPressed: isTestingConn
                                        ? null
                                        : () async {
                                            setStateDialog(() {
                                              isTestingConn = true;
                                              formErrorMsg = null;
                                              formSuccessMsg = null;
                                            });
                                            final res = await apiService.testBranchConnection(
                                              dataSource: dsCtrl.text.trim(),
                                              catalog: catCtrl.text.trim().isNotEmpty ? catCtrl.text.trim() : 'sp',
                                              userId: userCtrl.text.trim().isNotEmpty ? userCtrl.text.trim() : 'sa',
                                              password: passCtrl.text,
                                            );
                                            setStateDialog(() {
                                              isTestingConn = false;
                                              if (res['connected'] == true) {
                                                formSuccessMsg = res['message'] ?? 'الاتصال بالسيرفر يعمل بكفاءة 📡';
                                              } else {
                                                formErrorMsg = res['message'] ?? 'فشل الاتصال بالسيرفر';
                                              }
                                            });
                                          },
                                  ),
                                  const SizedBox(width: 10),

                                  // Big Save Button
                                  ElevatedButton.icon(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: isEditing ? Colors.amber[700] : Colors.green[700],
                                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                      elevation: 4,
                                    ),
                                    icon: isSaving
                                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                        : Icon(isEditing ? Icons.save_rounded : Icons.add_circle_rounded, color: Colors.white, size: 20),
                                    label: Text(
                                      isSaving
                                          ? 'جاري الحفظ...'
                                          : (isEditing ? '💾 حفظ وتطبيق تعديل بيانات الفرع في SQLite' : '➕ حفظ وإضافة الفرع الجديد في SQLite'),
                                      style: const TextStyle(color: Colors.white, fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 13),
                                    ),
                                    onPressed: isSaving
                                        ? null
                                        : () async {
                                            if (!formKey.currentState!.validate()) return;
                                            setStateDialog(() {
                                              isSaving = true;
                                              formErrorMsg = null;
                                              formSuccessMsg = null;
                                            });
                                            final pNo = int.tryParse(pointNoCtrl.text.trim()) ?? 1;
                                            final bNo = int.tryParse(branchNoCtrl.text.trim()) ?? pNo;
                                            final oldNo = isEditing ? ((selectedBranch!['pointNo'] as num?)?.toInt() ?? pNo) : pNo;
                                            try {
                                              if (isEditing) {
                                                await apiService.updateBranch(
                                                  pointNo: oldNo,
                                                  newPointNo: pNo,
                                                  pointName: pointNameCtrl.text.trim(),
                                                  branchNo: bNo,
                                                  dataSource: dsCtrl.text.trim(),
                                                  mainDataSource: mainDsCtrl.text.trim(),
                                                  catalog: catCtrl.text.trim().isNotEmpty ? catCtrl.text.trim() : 'sp',
                                                  mainCatalog: mainCatCtrl.text.trim(),
                                                  userId: userCtrl.text.trim().isNotEmpty ? userCtrl.text.trim() : 'sa',
                                                  password: passCtrl.text,
                                                );
                                              } else {
                                                await apiService.createBranch(
                                                  pointNo: pNo,
                                                  pointName: pointNameCtrl.text.trim(),
                                                  branchNo: bNo,
                                                  dataSource: dsCtrl.text.trim(),
                                                  mainDataSource: mainDsCtrl.text.trim(),
                                                  catalog: catCtrl.text.trim().isNotEmpty ? catCtrl.text.trim() : 'sp',
                                                  mainCatalog: mainCatCtrl.text.trim(),
                                                  userId: userCtrl.text.trim().isNotEmpty ? userCtrl.text.trim() : 'sa',
                                                  password: passCtrl.text,
                                                );
                                              }
                                              await reloadBranches();
                                              setStateDialog(() {
                                                isSaving = false;
                                                formSuccessMsg = isEditing
                                                    ? 'تم حفظ وتحديث بيانات الفرع #$pNo (${pointNameCtrl.text.trim()}) بنجاح في SQLite 💾'
                                                    : 'تمت إضافة الفرع الجديد #$pNo بنجاح في SQLite ✨';
                                              });
                                            } catch (e) {
                                              setStateDialog(() {
                                                isSaving = false;
                                                formErrorMsg = e.toString().replaceAll("Exception:", "").trim();
                                              });
                                            }
                                          },
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(height: 16),

                      // --- 2. SEARCH BAR & BRANCH COUNT ---
                      Row(
                        children: [
                          Expanded(
                            child: Container(
                              height: 42,
                              decoration: BoxDecoration(
                                color: const Color(0xFF0F172A),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: Colors.white12),
                              ),
                              child: TextField(
                                controller: searchCtrl,
                                onChanged: (val) {
                                  setStateDialog(() {
                                    searchQuery = val;
                                  });
                                },
                                style: const TextStyle(color: Colors.white, fontFamily: 'Cairo', fontSize: 13),
                                decoration: InputDecoration(
                                  hintText: 'ابحث عن أي فرع بالاسم أو الرقم لتعديله فوراً...',
                                  hintStyle: const TextStyle(color: Colors.white38, fontFamily: 'Cairo', fontSize: 12),
                                  prefixIcon: const Icon(Icons.search_rounded, color: Colors.amberAccent, size: 18),
                                  suffixIcon: searchQuery.isNotEmpty
                                      ? IconButton(
                                          icon: const Icon(Icons.clear_rounded, color: Colors.white54, size: 16),
                                          onPressed: () {
                                            searchCtrl.clear();
                                            setStateDialog(() {
                                              searchQuery = '';
                                            });
                                          },
                                        )
                                      : null,
                                  border: InputBorder.none,
                                  contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                            decoration: BoxDecoration(
                              color: Colors.amber.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.amber.withOpacity(0.3)),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.list_alt_rounded, color: Colors.amberAccent, size: 18),
                                const SizedBox(width: 6),
                                Text(
                                  'إجمالي الفروع: ${branchesList.length}',
                                  style: const TextStyle(color: Colors.amberAccent, fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 12),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 10),

                      // --- 3. BRANCHES TABLE WITH DIRECT SELECTION ---
                      Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFF0F172A).withOpacity(0.8),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.white10),
                        ),
                        child: Scrollbar(
                          controller: vScrollCtrl,
                          thumbVisibility: true,
                          child: SingleChildScrollView(
                            controller: vScrollCtrl,
                            scrollDirection: Axis.vertical,
                            child: Scrollbar(
                              controller: hScrollCtrl,
                              thumbVisibility: true,
                              notificationPredicate: (notif) => notif.depth == 1 || notif.metrics.axis == Axis.horizontal,
                              child: SingleChildScrollView(
                                controller: hScrollCtrl,
                                scrollDirection: Axis.horizontal,
                                child: ConstrainedBox(
                                  constraints: const BoxConstraints(minWidth: 1060),
                                  child: DataTable(
                                    showCheckboxColumn: false,
                                    headingRowColor: WidgetStateProperty.all(Colors.white.withOpacity(0.08)),
                                    horizontalMargin: 16,
                                    columnSpacing: 18,
                                    columns: const [
                                      DataColumn(label: Text('تعديل فوري', style: TextStyle(color: Colors.amberAccent, fontFamily: 'Cairo', fontWeight: FontWeight.bold))),
                                      DataColumn(label: Text('رقم النقطة', style: TextStyle(color: Colors.amberAccent, fontFamily: 'Cairo', fontWeight: FontWeight.bold))),
                                      DataColumn(label: Text('اسم الفرع', style: TextStyle(color: Colors.amberAccent, fontFamily: 'Cairo', fontWeight: FontWeight.bold))),
                                      DataColumn(label: Text('رقم الفرع', style: TextStyle(color: Colors.amberAccent, fontFamily: 'Cairo', fontWeight: FontWeight.bold))),
                                      DataColumn(label: Text('سيرفر الفرع (DataSource)', style: TextStyle(color: Colors.cyanAccent, fontFamily: 'Cairo', fontWeight: FontWeight.bold))),
                                      DataColumn(label: Text('قاعدة بيانات الفرع', style: TextStyle(color: Colors.white, fontFamily: 'Cairo', fontWeight: FontWeight.bold))),
                                      DataColumn(label: Text('السيرفر الرئيسي (MainDataSource)', style: TextStyle(color: Colors.amberAccent, fontFamily: 'Cairo', fontWeight: FontWeight.bold))),
                                      DataColumn(label: Text('قاعدة البيانات الرئيسية', style: TextStyle(color: Colors.amber, fontFamily: 'Cairo', fontWeight: FontWeight.bold))),
                                      DataColumn(label: Text('المستخدم', style: TextStyle(color: Colors.white, fontFamily: 'Cairo', fontWeight: FontWeight.bold))),
                                      DataColumn(label: Text('كلمة المرور', style: TextStyle(color: Colors.white, fontFamily: 'Cairo', fontWeight: FontWeight.bold))),
                                      DataColumn(label: Text('حذف', style: TextStyle(color: Colors.redAccent, fontFamily: 'Cairo', fontWeight: FontWeight.bold))),
                                    ],
                                    rows: filteredBranches.map((b) {
                                      final int pNo = (b['pointNo'] as num?)?.toInt() ?? 1;
                                      final String pName = b['pointName'] ?? '';
                                      final int bNo = (b['branchNo'] as num?)?.toInt() ?? pNo;
                                      final String ds = b['dataSource'] ?? '';
                                      final String mainDs = b['mainDataSource'] ?? '';
                                      final String cat = b['catalog'] ?? 'sp';
                                      final String mainCat = b['mainCatalog'] ?? '';
                                      final String usr = b['userId'] ?? 'sa';
                                      final String pwd = b['password'] ?? 'as';

                                      final isThisSelected = selectedBranch != null && (selectedBranch!['pointNo'] as num?)?.toInt() == pNo;

                                      return DataRow(
                                        selected: isThisSelected,
                                        onSelectChanged: (_) {
                                          setStateDialog(() {
                                            populateForm(b);
                                            formSuccessMsg = 'تم اختيار الفرع #$pNo ($pName) للتعديل في النموذج أعلاه ✏️';
                                            formErrorMsg = null;
                                          });
                                        },
                                        color: WidgetStateProperty.resolveWith<Color?>((Set<WidgetState> states) {
                                          if (isThisSelected) {
                                            return Colors.blueAccent.withOpacity(0.25);
                                          }
                                          if (states.contains(WidgetState.hovered)) {
                                            return Colors.blueAccent.withOpacity(0.1);
                                          }
                                          return null;
                                        }),
                                        cells: [
                                          DataCell(
                                            ElevatedButton.icon(
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor: isThisSelected ? Colors.amber[700] : Colors.blue[600],
                                                foregroundColor: Colors.white,
                                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                                              ),
                                              icon: const Icon(Icons.edit_rounded, color: Colors.white, size: 14),
                                              label: Text(
                                                isThisSelected ? 'محدد للتعديل ✏️' : 'تعديل ✏️',
                                                style: const TextStyle(color: Colors.white, fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 11),
                                              ),
                                              onPressed: () {
                                                setStateDialog(() {
                                                  populateForm(b);
                                                  formSuccessMsg = 'تم تحميل بيانات الفرع #$pNo ($pName) في النموذج أعلاه للتعديل ✏️';
                                                  formErrorMsg = null;
                                                });
                                              },
                                            ),
                                          ),
                                          DataCell(Text('#$pNo', style: const TextStyle(color: Colors.amberAccent, fontFamily: 'Cairo', fontWeight: FontWeight.bold))),
                                          DataCell(Text(pName, style: const TextStyle(color: Colors.white, fontFamily: 'Cairo', fontWeight: FontWeight.bold))),
                                          DataCell(Text('#$bNo', style: const TextStyle(color: Colors.white70, fontFamily: 'Cairo'))),
                                          DataCell(
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                              decoration: BoxDecoration(
                                                color: Colors.cyan.withOpacity(0.12),
                                                borderRadius: BorderRadius.circular(6),
                                              ),
                                              child: Text(ds.isNotEmpty ? ds : '-', style: const TextStyle(color: Colors.cyanAccent, fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 12)),
                                            ),
                                          ),
                                          DataCell(Text(cat.isNotEmpty ? cat : 'sp', style: const TextStyle(color: Colors.white70, fontFamily: 'Cairo'))),
                                          DataCell(
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                              decoration: BoxDecoration(
                                                color: Colors.amber.withOpacity(0.12),
                                                borderRadius: BorderRadius.circular(6),
                                              ),
                                              child: Text(mainDs.isNotEmpty ? mainDs : '-', style: const TextStyle(color: Colors.amberAccent, fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 12)),
                                            ),
                                          ),
                                          DataCell(
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                              decoration: BoxDecoration(
                                                color: Colors.amber.withOpacity(0.15),
                                                borderRadius: BorderRadius.circular(6),
                                                border: Border.all(color: Colors.amber.withOpacity(0.4)),
                                              ),
                                              child: Text(mainCat.isNotEmpty ? mainCat : (cat.isNotEmpty ? cat : 'sp'), style: const TextStyle(color: Colors.amberAccent, fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 12)),
                                            ),
                                          ),
                                          DataCell(Text(usr, style: const TextStyle(color: Colors.white70, fontFamily: 'Cairo'))),
                                          DataCell(Text(pwd, style: const TextStyle(color: Colors.white38, fontFamily: 'Cairo'))),
                                          DataCell(
                                            IconButton(
                                              icon: const Icon(Icons.delete_forever_rounded, color: Colors.redAccent, size: 20),
                                              tooltip: 'حذف الفرع نهائياً من SQLite',
                                              onPressed: () async {
                                                final confirm = await showDialog<bool>(
                                                  context: context,
                                                  builder: (c) => Directionality(
                                                    textDirection: TextDirection.rtl,
                                                    child: AlertDialog(
                                                      backgroundColor: const Color(0xFF1E293B),
                                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                                      title: const Row(
                                                        children: [
                                                          Icon(Icons.warning_amber_rounded, color: Colors.redAccent, size: 24),
                                                          SizedBox(width: 8),
                                                          Text('تأكيد حذف بيانات الفرع', style: TextStyle(color: Colors.white, fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
                                                        ],
                                                      ),
                                                      content: Text(
                                                        'هل أنت متأكد من حذف الفرع "$pName" (رقم #$pNo) من قاعدة بيانات SQLite وعناوين الاتصال؟',
                                                        style: const TextStyle(color: Colors.white70, fontFamily: 'Cairo', fontSize: 13),
                                                      ),
                                                      actions: [
                                                        TextButton(
                                                          onPressed: () => Navigator.pop(c, false),
                                                          child: const Text('إلغاء', style: TextStyle(color: Colors.white70, fontFamily: 'Cairo')),
                                                        ),
                                                        ElevatedButton.icon(
                                                          style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
                                                          icon: const Icon(Icons.delete_forever_rounded, color: Colors.white, size: 18),
                                                          label: const Text('تأكيد الحذف', style: TextStyle(color: Colors.white, fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
                                                          onPressed: () => Navigator.pop(c, true),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                );

                                                if (confirm == true) {
                                                  try {
                                                    await apiService.deleteBranch(pNo);
                                                    await reloadBranches();
                                                    setStateDialog(() {
                                                      formSuccessMsg = 'تم حذف الفرع #$pNo بنجاح من SQLite 🗑️';
                                                      if (selectedBranch != null && (selectedBranch!['pointNo'] as num?)?.toInt() == pNo) {
                                                        populateForm(null);
                                                      }
                                                    });
                                                  } catch (errEx) {
                                                    setStateDialog(() {
                                                      formErrorMsg = 'خطأ أثناء الحذف: $errEx';
                                                    });
                                                  }
                                                }
                                              },
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
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFE11D48),
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  icon: const Icon(Icons.check_circle_rounded, color: Colors.white),
                  label: const Text('إغلاق وتطبيق التحديثات', style: TextStyle(color: Colors.white, fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 14)),
                  onPressed: () {
                    Navigator.pop(context);
                    _loadRemotePoints();
                  },
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) return;

    final apiService = Provider.of<ApiService>(context, listen: false);
    try {
      UserModel? user;
      if (_isSpecialLogin) {
        if (_selectedPointNo == null || _remotePoints.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('يرجى اختيار نقطة البيع البعيدة', style: TextStyle(fontFamily: 'Cairo')),
              backgroundColor: Colors.orange,
            ),
          );
          return;
        }
        final pointObj = _remotePoints.firstWhere(
          (p) => (p['pointNo'] as num?)?.toInt() == _selectedPointNo,
          orElse: () => _remotePoints.first,
        );
        user = await apiService.loginSpecial(
          username: _usernameController.text.trim(),
          password: _passwordController.text,
          pointNo: (pointObj['pointNo'] as num).toInt(),
          pointName: pointObj['pointName']?.toString() ?? 'فرع',
          dataSource: pointObj['dataSource']?.toString() ?? '',
          mainCatalog: pointObj['mainCatalog']?.toString() ?? '',
        );
      } else {
        user = await apiService.login(
          _usernameController.text.trim(),
          _passwordController.text,
        );
      }

      if (user != null && mounted) {
        _passwordController.clear(); // Ensure passwords are never stored in memory/controllers!
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const MainShell()),
        );
      }
    } catch (e) {
      _passwordController.clear(); // Clear password input on error as well!
      if (mounted) {
        // Notify user about incorrect credentials or failed communication beautifully
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              e.toString().replaceAll('Exception:', '').trim(),
              style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold),
            ),
            backgroundColor: Colors.redAccent,
            duration: const Duration(seconds: 4),
            action: SnackBarAction(
              label: 'حسناً',
              textColor: Colors.white,
              onPressed: () {},
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final apiService = Provider.of<ApiService>(context);

    if (_usernameController.text.isEmpty && apiService.users.isNotEmpty) {
      _usernameController.text = apiService.users.first['name'];
    }

    return Scaffold(
      body: Stack(
        children: [
          // Background Gradient
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF140712), Color(0xFF240B1E), Color(0xFF3B0C2B)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          ),
          
          // Settings and Online Update buttons in top corner
          Positioned(
            top: 35,
            left: 20,
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.settings, color: Colors.white70, size: 28),
                  tooltip: 'إعدادات الاتصال وقاعدة البيانات',
                  onPressed: () => _showSettingsSecurityCheck(context),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF10B981),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  icon: _isCheckingUpdate
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.rocket_launch_rounded, size: 18),
                  label: const Text('تحديث النسخة أونلاين 🚀', style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 12)),
                  onPressed: _isCheckingUpdate ? null : () => _checkSystemUpdate(manual: true),
                ),
              ],
            ),
          ),

          // Database Status Indicator
          Positioned(
            top: 40,
            right: 20,
            child: Row(
              children: [
                Text(
                  apiService.isConnected ? 'متصل بالسيرفر' : 'غير متصل بالسيرفر',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontFamily: 'Cairo',
                    fontSize: 12,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: apiService.isConnected ? const Color(0xFF5B7B32) : Colors.red,
                    shape: BoxShape.circle,
                  ),
                ),
              ],
            ),
          ),

          // Main Login Card
          Center(
            child: SingleChildScrollView(
              child: Card(
                elevation: 16,
                color: const Color(0xFF240E20).withValues(alpha: 0.92),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                  side: const BorderSide(color: Color(0xFF4D183E), width: 1.5),
                ),
                child: Container(
                  width: 500,
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 32),
                  child: Directionality(
                    textDirection: TextDirection.rtl,
                    child: Form(
                      key: _formKey,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // App Logo / Icon
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: const Color(0xFF9C0E62).withValues(alpha: 0.2),
                              shape: BoxShape.circle,
                              border: Border.all(color: const Color(0xFFC2185B).withValues(alpha: 0.4), width: 2),
                            ),
                            child: const Icon(
                              Icons.storefront_rounded,
                              size: 52,
                              color: Color(0xFFE91E63),
                            ),
                          ),
                          const SizedBox(height: 14),
                          const Text(
                            'نظام هيا لنقاط البيع',
                            style: TextStyle(
                              color: Color(0xFFFDF2F8),
                              fontSize: 24,
                              fontWeight: FontWeight.w900,
                              fontFamily: 'Cairo',
                              letterSpacing: 1.2,
                            ),
                          ),
                          const Text(
                            'إصدار النسخة: 2026-08-20',
                            style: TextStyle(
                              color: Color(0xFF7CB342),
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              fontFamily: 'Cairo',
                            ),
                          ),
                          const SizedBox(height: 8),
                          // Online Update Action Chip in Card
                          InkWell(
                            onTap: _isCheckingUpdate ? null : () => _checkSystemUpdate(manual: true),
                            borderRadius: BorderRadius.circular(20),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                              decoration: BoxDecoration(
                                color: const Color(0xFF10B981).withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.4)),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  _isCheckingUpdate
                                      ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF34D399)))
                                      : const Icon(Icons.cloud_sync_rounded, size: 16, color: Color(0xFF34D399)),
                                  const SizedBox(width: 6),
                                  const Text(
                                    'فحص وتحديث النسخة أونلاين 🚀',
                                    style: TextStyle(
                                      color: Color(0xFF34D399),
                                      fontFamily: 'Cairo',
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),

                          // --- BRANCH / POS POINT SELECTOR (Full Width) ---
                          if (_remotePoints.isNotEmpty) ...[
                            DropdownButtonFormField<int>(
                              isExpanded: true,
                              value: _remotePoints.any((p) => p['pointNo'] == _selectedPointNo)
                                  ? _selectedPointNo
                                  : (_remotePoints.isNotEmpty ? (_remotePoints.first['pointNo'] as num).toInt() : null),
                              items: _remotePoints.map((p) {
                                final pNo = (p['pointNo'] as num?)?.toInt() ?? 1;
                                final pName = p['pointName'] ?? 'فرع';
                                return DropdownMenuItem<int>(
                                  value: pNo,
                                  child: Text(
                                    '$pName | فرع #$pNo',
                                    style: const TextStyle(color: Colors.white, fontFamily: 'Cairo', fontSize: 13, fontWeight: FontWeight.bold),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                );
                              }).toList(),
                              onChanged: (val) {
                                if (val != null) {
                                  setState(() {
                                    _selectedPointNo = val;
                                    _isSpecialLogin = true;
                                  });
                                  apiService.setActiveBranchPoint(val);
                                  _loadRemoteUsersForSelectedPoint(val);
                                }
                              },
                              dropdownColor: const Color(0xFF1E293B),
                              decoration: InputDecoration(
                                labelText: 'اختر نقطة البيع',
                                labelStyle: const TextStyle(color: Colors.amberAccent, fontFamily: 'Cairo', fontWeight: FontWeight.bold),
                                prefixIcon: const Icon(Icons.store_rounded, color: Colors.amberAccent),
                                enabledBorder: OutlineInputBorder(
                                  borderSide: const BorderSide(color: Colors.amber),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderSide: const BorderSide(color: Colors.amberAccent, width: 2),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                            ),
                            const SizedBox(height: 14),
                            if (_selectedPointNo != null) ...[
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Row(
                                    children: [
                                      const Icon(Icons.people_alt_rounded, color: Colors.amberAccent, size: 16),
                                      const SizedBox(width: 6),
                                      Text(
                                        'مستخدمو الفرع (#$_selectedPointNo):',
                                        style: const TextStyle(color: Colors.amberAccent, fontFamily: 'Cairo', fontSize: 11, fontWeight: FontWeight.bold),
                                      ),
                                    ],
                                  ),
                                  Text(
                                    _isLoadingPointUsers ? 'جاري الاتصال...' : '${_remotePointUsers.length} مستخدم',
                                    style: const TextStyle(color: Colors.white, fontFamily: 'Cairo', fontSize: 11),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                            ],
                          ],

                          // Date Field (First & Autofocused)
                          Focus(
                            onKeyEvent: (node, event) {
                              if (event is KeyDownEvent && (event.logicalKey == LogicalKeyboardKey.enter || event.logicalKey == LogicalKeyboardKey.numpadEnter)) {
                                _selectDate(context, apiService);
                                return KeyEventResult.handled;
                              }
                              return KeyEventResult.ignored;
                            },
                            child: InkWell(
                              onTap: () => _selectDate(context, apiService),
                              child: IgnorePointer(
                                child: TextFormField(
                                  focusNode: _dateFocus,
                                  autofocus: true,
                                  key: ValueKey(apiService.selectedDate),
                                  initialValue: apiService.selectedDate,
                                  style: const TextStyle(color: Colors.white, fontFamily: 'Cairo'),
                                  decoration: InputDecoration(
                                    labelText: 'تاريخ النظام والعمليات',
                                    labelStyle: const TextStyle(color: Colors.white70, fontFamily: 'Cairo'),
                                    prefixIcon: const Icon(Icons.calendar_today_outlined, color: Colors.white70),
                                    enabledBorder: OutlineInputBorder(
                                      borderSide: const BorderSide(color: Colors.white30),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderSide: const BorderSide(color: Colors.blueAccent),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 20),

                          // Username Dropdown Field (Second)
                          Focus(
                            onKeyEvent: (node, event) {
                              if (event is KeyDownEvent && (event.logicalKey == LogicalKeyboardKey.enter || event.logicalKey == LogicalKeyboardKey.numpadEnter)) {
                                FocusScope.of(context).requestFocus(_passwordFocus);
                                return KeyEventResult.handled;
                              }
                              return KeyEventResult.ignored;
                            },
                            child: _isSpecialLogin && _isLoadingPointUsers
                                ? const Center(child: Padding(padding: EdgeInsets.all(8), child: CircularProgressIndicator(color: Colors.amber, strokeWidth: 2)))
                                : DropdownButtonFormField<String>(
                                    value: _isSpecialLogin
                                        ? (_remotePointUsers.any((u) => u['userName'] == _usernameController.text)
                                            ? _usernameController.text
                                            : (_remotePointUsers.isNotEmpty ? _remotePointUsers.first['userName'] : null))
                                        : (apiService.users.any((u) => u['name'] == _usernameController.text)
                                            ? _usernameController.text
                                            : (apiService.users.isNotEmpty ? apiService.users.first['name'] : null)),
                                    items: (_isSpecialLogin
                                            ? _remotePointUsers.map((u) => u['userName'] as String)
                                            : apiService.users.map((u) => u['name'] as String))
                                        .map((uName) {
                                      return DropdownMenuItem<String>(
                                        value: uName,
                                        child: Text(
                                          uName,
                                          style: const TextStyle(color: Colors.white, fontFamily: 'Cairo', fontSize: 13),
                                        ),
                                      );
                                    }).toList(),
                                    onChanged: (val) {
                                      if (val != null) {
                                        _usernameController.text = val;
                                      }
                                    },
                                    focusNode: _usernameFocus,
                                    style: const TextStyle(color: Colors.white, fontFamily: 'Cairo'),
                                    dropdownColor: const Color(0xFF1E293B),
                                    decoration: InputDecoration(
                                      labelText: _isSpecialLogin ? 'اسم مستخدم النقطة البعيدة' : 'اسم المستخدم',
                                      labelStyle: TextStyle(color: _isSpecialLogin ? Colors.amberAccent : Colors.white70, fontFamily: 'Cairo'),
                                      prefixIcon: Icon(Icons.person_outline, color: _isSpecialLogin ? Colors.amber : Colors.white70),
                                      enabledBorder: OutlineInputBorder(
                                        borderSide: BorderSide(color: _isSpecialLogin ? Colors.amber : Colors.white30),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      focusedBorder: OutlineInputBorder(
                                        borderSide: BorderSide(color: _isSpecialLogin ? Colors.amberAccent : Colors.blueAccent),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      errorBorder: OutlineInputBorder(
                                        borderSide: const BorderSide(color: Colors.redAccent),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                    ),
                                    validator: (val) {
                                      if (val == null || val.isEmpty) return 'الحقل مطلوب';
                                      return null;
                                    },
                                  ),
                          ),
                          const SizedBox(height: 20),

                          // Password Field (Third - Autofill Disabled)
                          TextFormField(
                            controller: _passwordController,
                            focusNode: _passwordFocus,
                            obscureText: _obscurePassword,
                            enableSuggestions: false,
                            autocorrect: false,
                            autofillHints: const [], // Completely disable browser password saving/autofill
                            textInputAction: TextInputAction.done,
                            onFieldSubmitted: (_) {
                              _handleLogin();
                            },
                            style: const TextStyle(color: Colors.white),
                            decoration: InputDecoration(
                              labelText: 'كلمة المرور',
                              labelStyle: const TextStyle(color: Colors.white70, fontFamily: 'Cairo'),
                              prefixIcon: const Icon(Icons.lock_outline, color: Colors.white70),
                              suffixIcon: IconButton(
                                icon: Icon(
                                  _obscurePassword ? Icons.visibility_off : Icons.visibility,
                                  color: Colors.white70,
                                ),
                                onPressed: () {
                                  setState(() => _obscurePassword = !_obscurePassword);
                                },
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderSide: const BorderSide(color: Colors.white30),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderSide: const BorderSide(color: Colors.blueAccent),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              errorBorder: OutlineInputBorder(
                                borderSide: const BorderSide(color: Colors.redAccent),
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            validator: (val) {
                              if (val == null || val.isEmpty) return 'الحقل مطلوب';
                              return null;
                            },
                          ),
                          const SizedBox(height: 32),

                          // Submit Button
                          SizedBox(
                            width: double.infinity,
                            height: 50,
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _isSpecialLogin ? Colors.amber[700] : const Color(0xFF9C0E62),
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                elevation: 4,
                              ),
                              onPressed: apiService.isLoading ? null : _handleLogin,
                              child: apiService.isLoading
                                  ? const CircularProgressIndicator(color: Colors.white)
                                  : const Text(
                                      'تسجيل الدخول',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                        fontFamily: 'Cairo',
                                      ),
                                    ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          TextButton.icon(
                            style: TextButton.styleFrom(
                              foregroundColor: Colors.blueAccent,
                            ),
                            icon: _isSyncingUsers
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.blueAccent),
                                  )
                                : const Icon(Icons.sync_rounded, size: 18),
                            label: const Text(
                              'تحديث قائمة المستخدمين والبيانات',
                              style: TextStyle(fontFamily: 'Cairo', fontSize: 13, fontWeight: FontWeight.bold),
                            ),
                            onPressed: _isSyncingUsers
                                ? null
                                : () async {
                                    setState(() {
                                      _isSyncingUsers = true;
                                    });
                                    try {
                                      await apiService.fetchUsers();
                                      await apiService.loadInitialData();
                                      if (_remotePoints.isNotEmpty && _selectedPointNo != null) {
                                        await _loadRemoteUsersForSelectedPoint(_selectedPointNo!);
                                      }
                                      String msg = 'تم تحديث قائمة المستخدمين والبيانات بنجاح!';
                                      if (apiService.isConnected) {
                                        try {
                                          final remoteMsg = await apiService.syncItems();
                                          if (remoteMsg.isNotEmpty) msg = remoteMsg;
                                        } catch (_) {}
                                      }
                                      if (mounted) {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(
                                            content: Text(msg, style: const TextStyle(fontFamily: 'Cairo')),
                                            backgroundColor: Colors.green,
                                            duration: const Duration(seconds: 3),
                                          ),
                                        );
                                      }
                                    } catch (e) {
                                      if (mounted) {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(
                                            content: Text('تم تحديث البيانات: ' + e.toString().replaceAll('Exception:', '').trim(), style: const TextStyle(fontFamily: 'Cairo')),
                                            backgroundColor: Colors.blueAccent,
                                          ),
                                        );
                                      }
                                    } finally {
                                      if (mounted) {
                                        setState(() {
                                          _isSyncingUsers = false;
                                        });
                                      }
                                    }
                                  },
                          ),

                          const SizedBox(height: 14),
                          // Copyright & Version badge with today's day, month, and year
                          Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text(
                                'الحقوق محفوظة م. علي سنان',
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontFamily: 'Cairo',
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.08),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(color: const Color(0xFF7CB342).withValues(alpha: 0.35)),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.verified_rounded, size: 16, color: Color(0xFF7CB342)),
                                    const SizedBox(width: 8),
                                    Text(
                                      const String.fromEnvironment('APP_VERSION', defaultValue: 'إصدار النسخة: 2026-08-20'),
                                      style: const TextStyle(
                                        color: Color(0xFF9CCC65),
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
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          // Footer Copyright & Version Date
          Positioned(
            bottom: 12,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 7),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'الحقوق محفوظة م. علي سنان',
                      style: TextStyle(
                        color: Colors.white,
                        fontFamily: 'Cairo',
                        fontSize: 12.5,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 3),
                    const Text(
                      'إصدار النسخة: 2026-08-20',
                      style: TextStyle(
                        color: Color(0xFF9CCC65),
                        fontFamily: 'Cairo',
                        fontSize: 11.5,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
