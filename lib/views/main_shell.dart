import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:universal_html/js.dart' as js;
import '../services/api_service.dart';
import 'pos_sales_view.dart';
import 'purchases_view.dart';
import 'returns_view.dart';
import 'opening_stock_view.dart';
import 'accounts_view.dart';
import 'bonds_view.dart';
import 'reports_view.dart';
import 'login_view.dart';
import 'store_transfer_view.dart';
import 'barcode_print_view.dart';
import 'branch_item_search_view.dart';
import 'items_management_view.dart';
import 'item_movement_view.dart';
import 'branch_transfer_view.dart';
import 'expenses_account_statement_view.dart';

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  List<int> _openTabIndices = [0];
  int _activeTabIndex = 0;
  dynamic _speechRecognition;
  bool _isListening = false;
  String _lastVoiceCommand = 'لا يوجد';
  bool _isSyncing = false;
  bool _isTransferring = false;
  bool _voiceEnabled = true;
  double _zoomScale = 1.0;
  bool _isSidebarCollapsed = false;
  bool _hasUpdate = false;
  String _latestVersion = '';
  Map<String, dynamic>? _updateInfo;
  bool _isCheckingUpdate = false;



  final Map<int, ({String title, IconData icon})> _screenMeta = {
    0: (title: 'لوحة التحكم الرئيسية', icon: Icons.dashboard_rounded),
    1: (title: 'المبيعات الكاشير', icon: Icons.shopping_cart_rounded),
    2: (title: 'المشتريات المحلية', icon: Icons.local_shipping_rounded),
    3: (title: 'مرتجع المبيعات', icon: Icons.assignment_return_rounded),
    4: (title: 'مخزون أول المدة', icon: Icons.inventory_2_rounded),
    5: (title: 'دليل العملاء والموردين', icon: Icons.people_rounded),
    6: (title: 'سندات القبض والصرف', icon: Icons.payments_rounded),
    7: (title: 'التقارير المالية والتدقيق', icon: Icons.analytics_rounded),
    8: (title: 'أوامر التوريد المخزني', icon: Icons.download_rounded),
    9: (title: 'أوامر الصرف المخزني', icon: Icons.upload_rounded),
    10: (title: 'تصميم وطباعة الباركود', icon: Icons.qr_code_scanner_rounded),
    11: (title: 'البحث عن صنف بالفروع', icon: Icons.travel_explore_rounded),
    12: (title: 'إدارة ودليل الأصناف', icon: Icons.inventory_rounded),
    13: (title: 'كشف حركة صنف تفصيلي', icon: Icons.history_rounded),
    14: (title: 'التحويل المخزني بين الفروع', icon: Icons.sync_alt_rounded),
    15: (title: 'كشف حساب المصاريف والحسابات', icon: Icons.account_balance_wallet_rounded),
  };

  void _openOrSwitchToTab(int screenIndex) {
    setState(() {
      final existingPos = _openTabIndices.indexOf(screenIndex);
      if (existingPos != -1) {
        _activeTabIndex = existingPos;
      } else {
        _openTabIndices.add(screenIndex);
        _activeTabIndex = _openTabIndices.length - 1;
      }
    });
  }

  void _closeTab(int tabPosition) {
    if (tabPosition < 0 || tabPosition >= _openTabIndices.length) return;
    final closingIndex = _openTabIndices[tabPosition];
    // Don't close Dashboard if it's the only tab
    if (closingIndex == 0 && _openTabIndices.length == 1) return;

    setState(() {
      _openTabIndices.removeAt(tabPosition);
      if (_openTabIndices.isEmpty) {
        _openTabIndices = [0];
        _activeTabIndex = 0;
      } else if (_activeTabIndex >= _openTabIndices.length) {
        _activeTabIndex = _openTabIndices.length - 1;
      } else if (_activeTabIndex == tabPosition) {
        _activeTabIndex = (tabPosition - 1).clamp(0, _openTabIndices.length - 1);
      } else if (_activeTabIndex > tabPosition) {
        _activeTabIndex--;
      }
    });
  }

  void _closeOtherTabs(int keepPosition) {
    if (keepPosition < 0 || keepPosition >= _openTabIndices.length) return;
    final keepIndex = _openTabIndices[keepPosition];
    setState(() {
      if (keepIndex == 0) {
        _openTabIndices = [0];
        _activeTabIndex = 0;
      } else {
        _openTabIndices = [0, keepIndex];
        _activeTabIndex = 1;
      }
    });
  }

  void _closeAllTabs() {
    setState(() {
      _openTabIndices = [0];
      _activeTabIndex = 0;
    });
  }

  void _setZoom(double zoom) {
    final clamped = zoom.clamp(0.65, 1.6);
    setState(() {
      _zoomScale = clamped;
    });
    if (kIsWeb) {
      try {
        js.context.callMethod('setAppZoom', [clamped]);
      } catch (e) {
        debugPrint("Zoom error: $e");
      }
    }
  }

  bool get _isSpeechSupported {
    try {
      return js.context.hasProperty('SpeechRecognition') || js.context.hasProperty('webkitSpeechRecognition');
    } catch (e) {
      return false;
    }
  }

  final List<Widget> _views = [
    const SizedBox(), // Tab 0: Dashboard/Overview placeholder (rendered dynamically)
    const PosSalesView(),      // Tab 1: Sales (بيع)
    const PurchasesView(),     // Tab 2: Purchases (شراء)
    const ReturnsView(),       // Tab 3: Returns (مرتجع)
    const OpeningStockView(),  // Tab 4: Opening Stock (مخزون أول المدة)
    const AccountsView(),      // Tab 5: Customers & Suppliers (العملاء والموردين)
    const BondsView(),         // Tab 6: Bonds (سندات القبض والصرف)
    const ReportsView(),       // Tab 7: Reports (التقارير المالية)
    const StoreTransferView(isReceipt: true),  // Tab 8: Store Receipt (التوريد المخزني)
    const StoreTransferView(isReceipt: false), // Tab 9: Store Issuance (الصرف المخزني)
    const BarcodePrintView(),  // Tab 10: Barcode Design & Printing (تصميم وطباعة الباركود)
    const BranchItemSearchView(), // Tab 11: Branch Item Search (البحث عن صنف بالفروع)
    const ItemsManagementView(),  // Tab 12: Items Management (إدارة ودليل الأصناف)
    const ItemMovementView(),      // Tab 13: Item Movement History (كشف حركة صنف)
    const BranchTransferView(),    // Tab 14: Inter-Branch Store Transfer (التحويل المخزني بين الفروع)
    const ExpensesAccountStatementView(), // Tab 15: Expenses Account Ledger (كشف حساب المصاريف والحسابات)
  ];

  @override
  void initState() {
    super.initState();
    _initSpeechRecognition();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final apiService = Provider.of<ApiService>(context, listen: false);
      if (apiService.items.isEmpty) {
        apiService.loadInitialData();
      }
      // فحص التحديثات بهدوء بعد 3 ثوانٍ من تشغيل النظام
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted) {
          _checkSystemUpdate(manual: false);
        }
      });
    });
  }

  void _initSpeechRecognition() {
    try {
      if (_isSpeechSupported) {
        final speechClass = js.context.hasProperty('SpeechRecognition') 
            ? js.context['SpeechRecognition'] 
            : js.context['webkitSpeechRecognition'];
            
        if (speechClass != null) {
          _speechRecognition = js.JsObject(speechClass as js.JsFunction);
          _speechRecognition['lang'] = 'ar-YE';
          _speechRecognition['continuous'] = true;
          _speechRecognition['interimResults'] = false;
          
          _speechRecognition.callMethod('addEventListener', ['result', (event) {
            try {
              final results = event['results'];
              if (results != null && results['length'] > 0) {
                final lastResultIndex = results['length'] - 1;
                final alternatives = results[lastResultIndex];
                final transcript = alternatives[0]['transcript']?.toString().trim().toLowerCase();
                if (transcript != null && transcript.isNotEmpty) {
                  setState(() {
                    _lastVoiceCommand = transcript;
                  });
                  _processVoiceCommand(transcript);
                }
              }
            } catch (e) {
              debugPrint("Voice command parsing error: $e");
            }
          }]);

          _speechRecognition.callMethod('addEventListener', ['start', (event) {
            setState(() {
              _isListening = true;
            });
          }]);

          _speechRecognition.callMethod('addEventListener', ['end', (event) {
            setState(() {
              _isListening = false;
            });
            // Auto restart to keep listening
            if (_voiceEnabled && _speechRecognition != null) {
              try {
                _speechRecognition.callMethod('start');
              } catch (e) {}
            }
          }]);
          
          _speechRecognition.callMethod('start');
        }
      }
    } catch (e) {
      debugPrint("Speech recognition dynamic init error: $e");
    }
  }

  void _processVoiceCommand(String command) {
    debugPrint("Voice Command Received: $command");
    
    // Check keywords to switch views
    if (command.contains("الرئيسية") || command.contains("التحكم") || command.contains("لوحة")) {
      _openOrSwitchToTab(0);
    } else if (command.contains("مبيعات") || command.contains("كاشير") || command.contains("بيع")) {
      _openOrSwitchToTab(1);
    } else if (command.contains("مشتريات") || command.contains("شراء") || command.contains("مورد")) {
      _openOrSwitchToTab(2);
    } else if (command.contains("مرتجع") || command.contains("ترجيع") || command.contains("ارجاع")) {
      _openOrSwitchToTab(3);
    } else if (command.contains("جرد") || command.contains("مخزون") || command.contains("افتتاحي")) {
      _openOrSwitchToTab(4);
    } else if (command.contains("عملاء") || command.contains("حسابات") || command.contains("زبائن") || command.contains("دليل")) {
      _openOrSwitchToTab(5);
    } else if (command.contains("سند") || command.contains("قبض") || command.contains("صرف") || command.contains("سندات")) {
      _openOrSwitchToTab(6);
    } else if (command.contains("تقرير") || command.contains("تقارير") || command.contains("ارباح") || command.contains("تدقيق")) {
      _openOrSwitchToTab(7);
    } else if (command.contains("فرع") || command.contains("فروع") || command.contains("بحث عن صنف")) {
      _openOrSwitchToTab(11);
    }
  }

  void _toggleVoice() {
    setState(() {
      _voiceEnabled = !_voiceEnabled;
    });
    if (_speechRecognition != null) {
      try {
        if (_voiceEnabled) {
          _speechRecognition.callMethod('start');
        } else {
          _speechRecognition.callMethod('stop');
          setState(() {
            _isListening = false;
          });
        }
      } catch (e) {
        debugPrint("Toggle voice recognition error: $e");
      }
    }
  }

  Future<void> _handleSync() async {
    final apiService = Provider.of<ApiService>(context, listen: false);
    setState(() {
      _isSyncing = true;
    });
    try {
      final msg = await apiService.syncItems();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(msg, style: const TextStyle(fontFamily: 'Cairo')),
            backgroundColor: Colors.green,
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
              title: const Text('فشل المزامنة', style: TextStyle(fontFamily: 'Cairo', color: Colors.red)),
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
    } finally {
      if (mounted) {
        setState(() {
          _isSyncing = false;
        });
      }
    }
  }

  Future<void> _handleTransfer() async {
    final apiService = Provider.of<ApiService>(context, listen: false);
    setState(() {
      _isTransferring = true;
    });
    try {
      final res = await apiService.uploadTransactions();
      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => Directionality(
            textDirection: TextDirection.rtl,
            child: AlertDialog(
              title: const Row(
                children: [
                  Icon(Icons.check_circle, color: Colors.green, size: 28),
                  SizedBox(width: 8),
                  Text('تم ترحيل البيانات بنجاح', style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
                ],
              ),
              content: Text(
                res['message'] ?? 'تم ترحيل كافة الفواتير والسندات غير المرحلة لقاعدة البيانات بنجاح.',
                style: const TextStyle(fontFamily: 'Cairo'),
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
              title: const Text('فشل ترحيل البيانات', style: TextStyle(fontFamily: 'Cairo', color: Colors.red)),
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
    } finally {
      if (mounted) {
        setState(() {
          _isTransferring = false;
        });
      }
    }
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
          // Auto-prompt user smoothly
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

  @override
  void dispose() {
    _speechRecognition = null; // Clean speech recognition instance
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final apiService = Provider.of<ApiService>(context);
    final user = apiService.currentUser;

    if (user == null) {
      return const LoginView();
    }

    final activeScreenIndex = _openTabIndices.isNotEmpty ? _openTabIndices[_activeTabIndex.clamp(0, _openTabIndices.length - 1)] : 0;

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF140712), // Deep Luxury Plum Charcoal
              Color(0xFF240B1E), // Transition
              Color(0xFF3B0C2B), // Deep Royal Magenta
            ],
          ),
        ),
        child: Directionality(
          textDirection: TextDirection.rtl,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isSmallScreen = constraints.maxWidth < 800;
              final sidebarWidth = _isSidebarCollapsed || isSmallScreen ? 70.0 : 260.0;
              
              return Row(
                children: [
                  // --- SIDEBAR NAVIGATION ---
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: sidebarWidth,
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Color(0xFF1B0718),
                          Color(0xFF280C23),
                          Color(0xFF380D2D),
                        ],
                      ),
                      border: Border(left: BorderSide(color: Color(0xFF4D183E))),
                    ),
                    child: Column(
                      children: [
                        // App Title Header
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
                          decoration: const BoxDecoration(
                            border: Border(bottom: BorderSide(color: Colors.white10)),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Row(
                                children: [
                                  Icon(Icons.storefront_rounded, color: Color(0xFFC2185B), size: 26),
                                  SizedBox(width: 8),
                                  Text(
                                    'نظام هيا لنقاط البيع',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      fontFamily: 'Cairo',
                                    ),
                                  ),
                                ],
                              ),
                              IconButton(
                                icon: Icon(_isSidebarCollapsed ? Icons.chevron_left : Icons.chevron_right, color: Colors.white70, size: 20),
                                onPressed: () {
                                  setState(() {
                                    _isSidebarCollapsed = !_isSidebarCollapsed;
                                  });
                                },
                              ),
                            ],
                          ),
                        ),

                        // Zoom Control Box
                        _buildZoomControl(),

                        // User Info Box
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                          margin: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.04),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            children: [
                              const CircleAvatar(
                                backgroundColor: Colors.blueAccent,
                                radius: 18,
                                child: Icon(Icons.person, color: Colors.white, size: 18),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      user.userName,
                                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13, fontFamily: 'Cairo'),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    Text(
                                      user.isAdmin ? 'مدير النظام' : 'كاشير مبيعات',
                                      style: const TextStyle(color: Colors.white54, fontSize: 11, fontFamily: 'Cairo'),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),

                        const Divider(color: Colors.white10, height: 1),
                        const SizedBox(height: 12),

                        // Navigation items
                        Expanded(
                          child: ListView(
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            children: [
                              if (apiService.isScreenVisible(0)) _buildNavItem(0, 'لوحة التحكم', Icons.dashboard_outlined),
                              if (apiService.isScreenVisible(1)) _buildNavItem(1, 'المبيعات الكاشير', Icons.shopping_cart_outlined),
                              if (apiService.isScreenVisible(2)) _buildNavItem(2, 'المشتريات المحلية', Icons.local_shipping_outlined),
                              if (apiService.isScreenVisible(3)) _buildNavItem(3, 'مرتجع المبيعات', Icons.assignment_return_outlined),
                              if (apiService.isScreenVisible(12)) _buildNavItem(12, 'إدارة ودليل الأصناف (List)', Icons.inventory_rounded),
                              if (apiService.isScreenVisible(13)) _buildNavItem(13, 'كشف حركة صنف تفصيلي', Icons.history_rounded),
                              if (apiService.isScreenVisible(4)) _buildNavItem(4, 'مخزون أول المدة', Icons.inventory_2_outlined),
                              if (apiService.isScreenVisible(8)) _buildNavItem(8, 'أوامر التوريد المخزني', Icons.download_rounded),
                              if (apiService.isScreenVisible(9)) _buildNavItem(9, 'أوامر الصرف المخزني', Icons.upload_rounded),
                              if (apiService.isScreenVisible(14)) _buildNavItem(14, 'التحويل المخزني بين الفروع', Icons.sync_alt_rounded),
                              if (apiService.isScreenVisible(5)) _buildNavItem(5, 'دليل العملاء والموردين', Icons.people_outline),
                              if (apiService.isScreenVisible(6)) _buildNavItem(6, 'سندات القبض والصرف', Icons.payments_outlined),
                              if (apiService.isScreenVisible(15)) _buildNavItem(15, 'كشف حساب المصاريف والحسابات', Icons.account_balance_wallet_outlined),
                              if (apiService.isScreenVisible(7)) _buildNavItem(7, 'التقارير المالية والتدقيق', Icons.analytics_outlined),
                              if (apiService.isScreenVisible(11)) _buildNavItem(11, 'البحث عن صنف بالفروع', Icons.travel_explore_rounded),
                              if (apiService.isScreenVisible(10)) _buildNavItem(10, 'تصميم وطباعة الباركود', Icons.qr_code_scanner_outlined),
                            ],
                          ),
                        ),

                        // Connection status & logout at bottom
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: const BoxDecoration(
                            border: Border(top: BorderSide(color: Colors.white10)),
                          ),
                          child: Column(
                            children: [
                              Row(
                                children: [
                                  Container(
                                    width: 8,
                                    height: 8,
                                    decoration: BoxDecoration(
                                      color: apiService.isConnected ? Colors.green : Colors.red,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Text(
                                    apiService.isConnected ? 'متصل بالسيرفر' : 'غير متصل',
                                    style: const TextStyle(color: Colors.white60, fontSize: 12, fontFamily: 'Cairo'),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              SizedBox(
                                width: double.infinity,
                                child: OutlinedButton.icon(
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: Colors.redAccent,
                                    side: const BorderSide(color: Colors.redAccent),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                  ),
                                  icon: const Icon(Icons.logout_rounded, size: 18),
                                  label: const Text('خروج من الحساب', style: TextStyle(fontFamily: 'Cairo')),
                                  onPressed: () {
                                    apiService.logout();
                                    Navigator.pushReplacement(
                                      context,
                                      MaterialPageRoute(builder: (context) => const LoginView()),
                                    );
                                  },
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  // --- MAIN VIEW PORT (Multi-Tab Enabled) ---
                  Expanded(
                    child: Column(
                      children: [
                        // Top Workspace Tab Bar
                        _buildTopTabBar(),

                        // Active View (State Preserved via IndexedStack)
                        Expanded(
                          child: IndexedStack(
                            index: activeScreenIndex,
                            children: List.generate(_views.length, (idx) {
                              if (idx == 0) {
                                return DashboardOverview(
                                  isSyncing: _isSyncing,
                                  isTransferring: _isTransferring,
                                  isListening: _isListening,
                                  voiceEnabled: _voiceEnabled,
                                  lastVoiceCommand: _lastVoiceCommand,
                                  isCheckingUpdate: _isCheckingUpdate,
                                  onSync: _handleSync,
                                  onTransfer: _handleTransfer,
                                  onToggleVoice: _toggleVoice,
                                  onCheckUpdate: () => _checkSystemUpdate(manual: true),
                                );
                              }
                              if (_openTabIndices.contains(idx)) {
                                return _views[idx];
                              }
                              return const SizedBox();
                            }),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildTopTabBar() {
    return Container(
      height: 46,
      decoration: BoxDecoration(
        color: const Color(0xFF140813),
        border: Border(
          bottom: BorderSide(color: const Color(0xFF4A183C).withValues(alpha: 0.5)),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 4,
            offset: const Offset(0, 2),
          )
        ],
      ),
      child: Row(
        children: [
          // Scrollable Tab List
          Expanded(
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              itemCount: _openTabIndices.length,
              itemBuilder: (context, pos) {
                final screenIndex = _openTabIndices[pos];
                final meta = _screenMeta[screenIndex] ?? (title: 'نافذة $screenIndex', icon: Icons.window_rounded);
                final isActive = pos == _activeTabIndex;
                final isDashboard = screenIndex == 0;

                return Padding(
                  padding: const EdgeInsets.only(left: 6.0),
                  child: InkWell(
                    onTap: () => setState(() => _activeTabIndex = pos),
                    borderRadius: BorderRadius.circular(8),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        gradient: isActive
                            ? const LinearGradient(
                                colors: [Color(0xFF9C0E62), Color(0xFFC2185B)],
                              )
                            : LinearGradient(
                                colors: [Colors.white.withValues(alpha: 0.06), Colors.white.withValues(alpha: 0.02)],
                              ),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: isActive ? const Color(0xFFE91E63) : const Color(0xFF4A183C),
                          width: isActive ? 1.5 : 1,
                        ),
                        boxShadow: isActive
                            ? [
                                BoxShadow(
                                  color: const Color(0xFF9C0E62).withValues(alpha: 0.4),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                )
                              ]
                            : null,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            meta.icon,
                            size: 16,
                            color: isActive ? Colors.white : Colors.white60,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            meta.title,
                            style: TextStyle(
                              color: isActive ? Colors.white : Colors.white70,
                              fontFamily: 'Cairo',
                              fontSize: 12,
                              fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                            ),
                          ),
                          if (!isDashboard || _openTabIndices.length > 1) ...[
                            const SizedBox(width: 8),
                            InkWell(
                              onTap: () => _closeTab(pos),
                              borderRadius: BorderRadius.circular(12),
                              child: Container(
                                padding: const EdgeInsets.all(2),
                                decoration: BoxDecoration(
                                  color: isActive ? Colors.black.withOpacity(0.2) : Colors.transparent,
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  Icons.close_rounded,
                                  size: 14,
                                  color: isActive ? Colors.white : Colors.white38,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),

          // Workspace Tab Controls (Count & Menu)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              border: Border(right: BorderSide(color: Colors.white.withOpacity(0.08))),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.blueAccent.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.blueAccent.withOpacity(0.3)),
                  ),
                  child: Text(
                    '${_openTabIndices.length} نوافذ',
                    style: const TextStyle(
                      color: Colors.blueAccent,
                      fontSize: 11,
                      fontFamily: 'Cairo',
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                PopupMenuButton<String>(
                  tooltip: 'إدارة النوافذ والتبويبات',
                  icon: const Icon(Icons.more_vert_rounded, color: Colors.white60, size: 18),
                  color: const Color(0xFF1E293B),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  onSelected: (val) {
                    if (val == 'close_others') {
                      _closeOtherTabs(_activeTabIndex);
                    } else if (val == 'close_all') {
                      _closeAllTabs();
                    }
                  },
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                      value: 'close_others',
                      child: Row(
                        children: [
                          Icon(Icons.tab_unselected_rounded, color: Colors.amberAccent, size: 18),
                          SizedBox(width: 8),
                          Text('إغلاق النوافذ الأخرى', style: TextStyle(color: Colors.white, fontFamily: 'Cairo', fontSize: 13)),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'close_all',
                      child: Row(
                        children: [
                          Icon(Icons.close_fullscreen_rounded, color: Colors.redAccent, size: 18),
                          SizedBox(width: 8),
                          Text('إغلاق جميع النوافذ والعودة للرئيسية', style: TextStyle(color: Colors.white, fontFamily: 'Cairo', fontSize: 13)),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildZoomControl() {
    final zoomPercent = (_zoomScale * 100).round();
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white10),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            icon: const Icon(Icons.zoom_out, color: Colors.white70, size: 18),
            tooltip: 'تصغير الشاشة',
            onPressed: () => _setZoom(_zoomScale - 0.15),
          ),
          InkWell(
            onTap: () => _setZoom(1.0),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.blueAccent.withOpacity(0.2),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '$zoomPercent%',
                style: const TextStyle(color: Colors.blueAccent, fontWeight: FontWeight.bold, fontSize: 12, fontFamily: 'Cairo'),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.zoom_in, color: Colors.white70, size: 18),
            tooltip: 'تكبير الشاشة',
            onPressed: () => _setZoom(_zoomScale + 0.15),
          ),
        ],
      ),
    );
  }

  Widget _buildNavItem(int index, String label, IconData icon) {
    final isCurrentActive = _openTabIndices.isNotEmpty && _openTabIndices[_activeTabIndex.clamp(0, _openTabIndices.length - 1)] == index;
    final isOpen = _openTabIndices.contains(index);

    return Padding(
      padding: const EdgeInsets.only(bottom: 6.0),
      child: ListTile(
        selected: isCurrentActive,
        selectedTileColor: const Color(0xFF9C0E62).withValues(alpha: 0.22),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        leading: Icon(icon, color: isCurrentActive ? const Color(0xFFE91E63) : (isOpen ? const Color(0xFF7CB342) : Colors.white60), size: 22),
        title: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: isCurrentActive ? Colors.white : (isOpen ? Colors.white : Colors.white70),
                  fontWeight: isCurrentActive ? FontWeight.bold : (isOpen ? FontWeight.w600 : FontWeight.normal),
                  fontFamily: 'Cairo',
                  fontSize: 13.5,
                ),
              ),
            ),
            if (isOpen && !isCurrentActive) ...[
              Container(
                width: 6,
                height: 6,
                decoration: const BoxDecoration(
                  color: Color(0xFF7CB342),
                  shape: BoxShape.circle,
                ),
              ),
            ],
          ],
        ),
        onTap: () => _openOrSwitchToTab(index),
      ),
    );
  }
}

// --- DASHBOARD OVERVIEW SUB-VIEW ---
class DashboardOverview extends StatefulWidget {
  final bool isSyncing;
  final bool isTransferring;
  final bool isListening;
  final bool voiceEnabled;
  final String lastVoiceCommand;
  final bool isCheckingUpdate;
  final VoidCallback onSync;
  final VoidCallback onTransfer;
  final VoidCallback onToggleVoice;
  final VoidCallback onCheckUpdate;

  const DashboardOverview({
    super.key,
    required this.isSyncing,
    required this.isTransferring,
    required this.isListening,
    required this.voiceEnabled,
    required this.lastVoiceCommand,
    required this.isCheckingUpdate,
    required this.onSync,
    required this.onTransfer,
    required this.onToggleVoice,
    required this.onCheckUpdate,
  });

  @override
  State<DashboardOverview> createState() => _DashboardOverviewState();
}

class _DashboardOverviewState extends State<DashboardOverview> {
  @override
  Widget build(BuildContext context) {
    final apiService = Provider.of<ApiService>(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'لوحة التحكم وإدارة النظام',
                    style: TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.bold, fontFamily: 'Cairo'),
                  ),
                  Text(
                    'تاريخ النظام النشط حالياً: ${apiService.selectedDate} | نقطة البيع الحالية: ${apiService.pointName} (#${apiService.pointNo})',
                    style: const TextStyle(color: Colors.blueAccent, fontSize: 13, fontFamily: 'Cairo', fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              
              // Top Action Buttons
              Row(
                children: [
                  // Refresh Data / Sync Items Button
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blueAccent,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    icon: widget.isSyncing
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.refresh_rounded, size: 20),
                    label: const Text('تحديث البيانات (الأصناف والتحويلات)', style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
                    onPressed: widget.isSyncing || !apiService.isConnected ? null : widget.onSync,
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Transferred Items from Branches Card (from Main Database)
          const TransferredItemsFromBranchesWidget(),
        ],
      ),
    );
  }
}

// --- TRANSFERRED ITEMS FROM BRANCHES (MAIN DATABASE) WIDGET FOR DASHBOARD ---
class TransferredItemsFromBranchesWidget extends StatefulWidget {
  const TransferredItemsFromBranchesWidget({super.key});

  @override
  State<TransferredItemsFromBranchesWidget> createState() => _TransferredItemsFromBranchesWidgetState();
}

class _TransferredItemsFromBranchesWidgetState extends State<TransferredItemsFromBranchesWidget> {
  bool _isLoading = false;
  bool _hasFetched = false;
  List<dynamic> _transfers = [];

  @override
  void initState() {
    super.initState();
    // Do NOT load transfers automatically on screen open as explicitly requested!
  }

  Future<void> _loadTransfers() async {
    setState(() {
      _isLoading = true;
      _hasFetched = true;
    });
    try {
      final apiService = Provider.of<ApiService>(context, listen: false);
      final list = await apiService.fetchPendingTransfers(apiService.pointNo);
      setState(() {
        _transfers = list;
      });
    } catch (_) {
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _confirmTransfer(double transNum) async {
    setState(() => _isLoading = true);
    try {
      final apiService = Provider.of<ApiService>(context, listen: false);
      await apiService.confirmTransfer(transNum, toPointNo: apiService.pointNo);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم تأكيد استلام الأصناف وتحديث الحالة fldStatus=1 وإنشاء توريد جديد برقم جديد بنجاح!', style: TextStyle(fontFamily: 'Cairo')),
            backgroundColor: Colors.green,
          ),
        );
      }
      await _loadTransfers();
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
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final apiService = Provider.of<ApiService>(context);

    return Card(
      color: const Color(0xFF1E293B),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.blueAccent.withOpacity(0.3)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.blueAccent.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.sync_alt_rounded, color: Colors.blueAccent, size: 22),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'الأصناف والتحويلات المحولة من الفروع (من قاعدة البيانات الأساسية)',
                          style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold, fontFamily: 'Cairo'),
                        ),
                        Text(
                          'نقطة البيع الحالية المستلمة: ${apiService.pointName} (#${apiService.pointNo}) | fldToPointNO = ${apiService.pointNo}',
                          style: const TextStyle(color: Colors.white54, fontSize: 12, fontFamily: 'Cairo'),
                        ),
                      ],
                    ),
                  ],
                ),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blueAccent,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text('تحديث البيانات (عرض الأصناف والتحويلات)', style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
                  onPressed: _loadTransfers,
                ),
              ],
            ),
            const Divider(color: Colors.white10, height: 24),
            _isLoading
                ? const Center(child: Padding(padding: EdgeInsets.all(20.0), child: CircularProgressIndicator(color: Colors.blueAccent)))
                : !_hasFetched
                    ? Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(28),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0F172A),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.blueAccent.withOpacity(0.2)),
                        ),
                        child: Column(
                          children: [
                            const Icon(Icons.touch_app_rounded, color: Colors.amberAccent, size: 44),
                            const SizedBox(height: 12),
                            const Text(
                              'انقر على زر "تحديث البيانات 🔄" بالأعلى لعرض الأصناف والتحويلات المخزنية المحولة من الفروع',
                              style: TextStyle(color: Colors.amberAccent, fontFamily: 'Cairo', fontSize: 14, fontWeight: FontWeight.bold),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 16),
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.blueAccent,
                                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                              ),
                              icon: const Icon(Icons.refresh_rounded, color: Colors.white),
                              label: const Text('عرض وتحديث البيانات الآن', style: TextStyle(color: Colors.white, fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
                              onPressed: _loadTransfers,
                            ),
                          ],
                        ),
                      )
                    : _transfers.isEmpty
                        ? Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(24),
                            decoration: BoxDecoration(
                              color: const Color(0xFF0F172A),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Column(
                              children: [
                                Icon(Icons.inbox_rounded, color: Colors.white24, size: 48),
                                SizedBox(height: 8),
                                Text(
                                  'لا توجد تحويلات أو أصناف محولة قيد الانتظار حالياً لهذه النقطة من قاعدة البيانات الأساسية',
                                  style: TextStyle(color: Colors.white54, fontFamily: 'Cairo', fontSize: 14),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          )
                    : ListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: _transfers.length,
                        itemBuilder: (context, index) {
                          final t = _transfers[index];
                          final transNum = (t['transNumber'] as num).toDouble();
                          final fromName = t['fromBranchName'] ?? 'فرع ${t['fromPointNo']}';
                          final dateStr = t['date'] ?? '';
                          final items = (t['items'] as List<dynamic>?) ?? [];

                          return Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: const Color(0xFF0F172A),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.white10),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      'حركة تحويل #${transNum.toInt()} | من: $fromName ➔ إلى نقطتك (#${apiService.pointNo})',
                                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontFamily: 'Cairo', fontSize: 14),
                                    ),
                                    Text(
                                      'تاريخ التحويل: $dateStr',
                                      style: const TextStyle(color: Colors.white54, fontFamily: 'Cairo', fontSize: 12),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                ...items.map((item) {
                                  return Padding(
                                    padding: const EdgeInsets.symmetric(vertical: 2.0),
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text('• ${item['itemName']} (${item['barcode']})', style: const TextStyle(color: Colors.white70, fontFamily: 'Cairo', fontSize: 13)),
                                        Text('الكمية: ${item['quantity']} ${item['unitName']} | السعر: ${item['salesPrice']}', style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold, fontFamily: 'Cairo', fontSize: 13)),
                                      ],
                                    ),
                                  );
                                }).toList(),
                                const SizedBox(height: 10),
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: ElevatedButton.icon(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.green,
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                                    ),
                                    icon: const Icon(Icons.check_circle_rounded, size: 16),
                                    label: const Text('تأكيد الاستلام والتوريد (fldStatus = 1)', style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 12)),
                                    onPressed: () => _confirmTransfer(transNum),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
          ],
        ),
      ),
    );
  }
}
