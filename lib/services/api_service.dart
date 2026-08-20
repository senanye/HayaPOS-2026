import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import '../models/user.dart';
import '../models/item.dart';
import '../models/item_group.dart';
import '../models/currency.dart';
import '../models/transaction.dart';
import '../models/account.dart';
import '../models/bond.dart';

class ApiService extends ChangeNotifier {
  static const String keyApiUrl = 'pref_api_url';

  static String get defaultUrl {
    if (kIsWeb) {
      final host = Uri.base.host.isNotEmpty ? Uri.base.host : '127.0.0.1';
      final cleanHost = (host == 'localhost') ? '127.0.0.1' : host;
      return 'http://$cleanHost:9000';
    }
    return 'http://127.0.0.1:9000';
  }

  String _baseUrl = defaultUrl;
  bool _isConnected = false;
  bool _isLoading = false;
  UserModel? _currentUser;
  
  List<ItemModel> _items = [];
  List<ItemGroupModel> _groups = [];
  List<CurrencyModel> _currencies = [];
  List<AccountModel> _accounts = [];
  List<BondModel> _bonds = [];

  int _pointNo = 1;
  int _defaultMoneyId = 1;
  String _pointName = 'الرئيسية';
  String _logoBase64 = '';
  String _selectedDate = DateFormat('yyyy-MM-dd').format(DateTime.now());
  List<Map<String, dynamic>> _remoteAccounts = [];
  List<Map<String, dynamic>> _users = [];

  String get baseUrl => _baseUrl;
  bool get isConnected => _isConnected;
  bool get isLoading => _isLoading;
  UserModel? get currentUser => _currentUser;
  List<ItemModel> get items => _items;
  List<ItemGroupModel> get groups => _groups;
  List<CurrencyModel> get currencies => _currencies;
  List<AccountModel> get accounts => _accounts;
  List<BondModel> get bonds => _bonds;
  int get pointNo => _pointNo;
  int get defaultMoneyId => _defaultMoneyId;
  String get pointName => _pointName;
  String get logoBase64 => _logoBase64;
  String get selectedDate => _selectedDate;
  List<Map<String, dynamic>> get remoteAccounts => _remoteAccounts;
  List<Map<String, dynamic>> get users => _users;

  CurrencyModel? getCurrencyById(int id) {
    final matches = _currencies.where((c) => c.id == id).toList();
    return matches.isNotEmpty ? matches.first : null;
  }

  CurrencyModel get defaultCurrency {
    return getCurrencyById(_defaultMoneyId) ??
        (_currencies.isNotEmpty
            ? _currencies.first
            : CurrencyModel(id: 1, symbol: 'ر.س', name: 'ريال سعودي', value: 1.0));
  }

  Map<int, bool> _screenVisibility = {
    0: true,  // Dashboard (Always visible)
    1: true,  // Sales
    2: true,  // Purchases
    3: true,  // Returns
    4: true,  // Opening stock
    5: true,  // Accounts
    6: true,  // Bonds
    7: true,  // Reports
    8: true,  // Store receipt
    9: true,  // Store issuance
    10: true, // Barcode print
    11: true, // Branch item search
    12: true, // Items management
    13: true, // Item movement
    14: true, // Branch transfer
    15: true, // Expenses Account Statement
  };

  Map<int, bool> get screenVisibility => _screenVisibility;

  bool isScreenVisible(int index) {
    if (index == 0) return true;
    return _screenVisibility[index] ?? true;
  }

  ApiService() {
    _loadSettings();
    loadScreenVisibility();
  }

  // Load screen visibility settings
  Future<void> loadScreenVisibility() async {
    final prefs = await SharedPreferences.getInstance();
    final Map<int, bool> updated = Map.from(_screenVisibility);
    for (int i = 1; i <= 15; i++) {
      final val = prefs.getBool('screen_vis_$i');
      if (val != null) {
        updated[i] = val;
      }
    }
    _screenVisibility = updated;
    notifyListeners();
  }

  // Update & Save screen visibility settings
  Future<void> updateScreenVisibility(Map<int, bool> newVisibility) async {
    _screenVisibility = Map.from(newVisibility);
    final prefs = await SharedPreferences.getInstance();
    for (var entry in newVisibility.entries) {
      await prefs.setBool('screen_vis_${entry.key}', entry.value);
    }
    notifyListeners();
  }

  // Safe HTTP GET wrapper with dynamic URL fallback & automatic hostname alignment
  Future<http.Response> safeHttpGet(String pathAndQuery) async {
    final fullUrl = '$_baseUrl$pathAndQuery';
    try {
      return await http.get(Uri.parse(fullUrl));
    } catch (e) {
      if (kIsWeb) {
        final host = Uri.base.host.isNotEmpty ? Uri.base.host : 'localhost';
        final fallbackUrl = 'http://$host:9000$pathAndQuery';
        if (fallbackUrl != fullUrl) {
          try {
            final resp = await http.get(Uri.parse(fallbackUrl));
            _baseUrl = 'http://$host:9000';
            final prefs = await SharedPreferences.getInstance();
            await prefs.setString(keyApiUrl, _baseUrl);
            notifyListeners();
            return resp;
          } catch (_) {}
        }
      }
      rethrow;
    }
  }

  // Load saved API base URL
  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(keyApiUrl);
    if (saved == null || saved.contains(':8888') || saved.contains(':8000')) {
      _baseUrl = defaultUrl;
      await prefs.setString(keyApiUrl, _baseUrl);
    } else {
      _baseUrl = saved;
    }

    if (kIsWeb) {
      final currentHost = (Uri.base.host.isNotEmpty && Uri.base.host != 'localhost') ? Uri.base.host : '127.0.0.1';
      _baseUrl = 'http://$currentHost:9000';
      await prefs.setString(keyApiUrl, _baseUrl);
    }

    _selectedDate = prefs.getString('pref_selected_date') ?? DateFormat('yyyy-MM-dd').format(DateTime.now());
    final savedLogo = prefs.getString('invoice_logo_base64');
    if (savedLogo != null && savedLogo.isNotEmpty) {
      _logoBase64 = savedLogo;
    }
    notifyListeners();
    checkConnection();
  }

  // Update & Save Invoice Printed Logo
  Future<void> updateInvoiceLogo(String base64Logo) async {
    _logoBase64 = base64Logo;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('invoice_logo_base64', base64Logo);
    notifyListeners();

    try {
      await http.post(
        Uri.parse('$_baseUrl/api/settings/logo'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'logo_base64': base64Logo}),
      );
    } catch (_) {}
  }

  // Update saved System Date
  Future<void> updateSelectedDate(String date) async {
    _selectedDate = date;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('pref_selected_date', date);
    notifyListeners();
  }

  // Save new API base URL
  Future<void> updateBaseUrl(String newUrl) async {
    // Strip trailing slash if present
    if (newUrl.endsWith('/')) {
      newUrl = newUrl.substring(0, newUrl.length - 1);
    }
    if (newUrl.contains(':8888')) {
      newUrl = newUrl.replaceAll(':8888', ':9000');
    } else if (newUrl.contains(':8000')) {
      newUrl = newUrl.replaceAll(':8000', ':9000');
    }
    _baseUrl = newUrl;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(keyApiUrl, newUrl);
    notifyListeners();
    await checkConnection();
  }

  // Check health of the API connection
  Future<bool> checkConnection() async {
    _isLoading = true;
    notifyListeners();
    try {
      final response = await http.get(Uri.parse('$_baseUrl/api/health')).timeout(const Duration(seconds: 3));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        _isConnected = data['status'] == 'healthy';
      } else {
        _isConnected = false;
      }
    } catch (e) {
      if (_baseUrl != defaultUrl) {
        _baseUrl = defaultUrl;
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(keyApiUrl, defaultUrl);
        return checkConnection();
      }
      _isConnected = false;
    }
    _isLoading = false;
    notifyListeners();
    return _isConnected;
  }

  // User Login
  Future<UserModel?> login(String username, String password) async {
    _isLoading = true;
    notifyListeners();
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/api/login'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'username': username, 'password': password}),
      );

      if (response.statusCode == 200) {
        final userData = json.decode(utf8.decode(response.bodyBytes));
        _currentUser = UserModel.fromJson(userData);
        _isConnected = true;
        
        // Load initial data upon login
        await loadInitialData();
        
        _isLoading = false;
        notifyListeners();
        return _currentUser;
      } else {
        final errorMsg = json.decode(utf8.decode(response.bodyBytes))['detail'] ?? 'خطأ في المصادقة';
        _isLoading = false;
        notifyListeners();
        throw Exception(errorMsg);
      }
    } catch (e) {
      _isLoading = false;
      notifyListeners();
      rethrow;
    }
  }

  // Fetch points from tblPointList
  Future<List<Map<String, dynamic>>> fetchRemotePoints() async {
    try {
      final response = await http.get(Uri.parse('$_baseUrl/api/points'));
      if (response.statusCode == 200) {
        final List decoded = json.decode(utf8.decode(response.bodyBytes));
        return decoded.map((x) => Map<String, dynamic>.from(x)).toList();
      }
    } catch (e) {
      if (kDebugMode) print("Error fetching remote points: $e");
    }
    return [];
  }

  // Fetch users for a specific point
  Future<Map<String, dynamic>> fetchRemotePointUsers(int pointNo) async {
    try {
      final response = await http.get(Uri.parse('$_baseUrl/api/points/$pointNo/users'));
      if (response.statusCode == 200) {
        final decoded = json.decode(utf8.decode(response.bodyBytes));
        if (decoded is Map<String, dynamic>) {
          return decoded;
        } else if (decoded is List) {
          return {
            "pointNo": pointNo,
            "dataSource": "",
            "users": decoded.map((x) => Map<String, dynamic>.from(x)).toList()
          };
        }
      }
    } catch (e) {
      if (kDebugMode) print("Error fetching point users: $e");
    }
    return {"pointNo": pointNo, "dataSource": "", "users": []};
  }

  // Set Active Branch Point in Backend
  Future<void> setActiveBranchPoint(int pointNo) async {
    try {
      await http.post(Uri.parse('$_baseUrl/api/points/active/$pointNo'));
      await checkConnection();
    } catch (e) {
      if (kDebugMode) print("Error setting active branch: $e");
    }
  }

  // SQLite Branch CRUD Operations
  Future<bool> createBranch({
    required int pointNo,
    required String pointName,
    int? branchNo,
    required String dataSource,
    String catalog = "sp",
    String userId = "sa",
    String password = "as",
    String? mainDataSource,
    String? mainCatalog,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/api/points'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'pointNo': pointNo,
          'pointName': pointName,
          'branchNo': branchNo ?? pointNo,
          'dataSource': dataSource,
          'catalog': catalog,
          'userId': userId,
          'password': password,
          'mainDataSource': mainDataSource ?? '',
          'mainCatalog': mainCatalog ?? '',
        }),
      );
      if (response.statusCode == 200) {
        await fetchRemotePoints();
        return true;
      } else {
        final err = json.decode(utf8.decode(response.bodyBytes))['detail'] ?? 'خطأ في إضافة الفرع';
        throw Exception(err);
      }
    } catch (e) {
      rethrow;
    }
  }

  Future<bool> updateBranch({
    required int pointNo,
    int? newPointNo,
    required String pointName,
    int? branchNo,
    required String dataSource,
    String catalog = "sp",
    String userId = "sa",
    String password = "as",
    String? mainDataSource,
    String? mainCatalog,
  }) async {
    try {
      final response = await http.put(
        Uri.parse('$_baseUrl/api/points/$pointNo'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'pointNo': newPointNo ?? pointNo,
          'pointName': pointName,
          'branchNo': branchNo ?? (newPointNo ?? pointNo),
          'dataSource': dataSource,
          'catalog': catalog,
          'userId': userId,
          'password': password,
          'mainDataSource': mainDataSource ?? '',
          'mainCatalog': mainCatalog ?? '',
        }),
      );
      if (response.statusCode == 200) {
        await fetchRemotePoints();
        return true;
      } else {
        final err = json.decode(utf8.decode(response.bodyBytes))['detail'] ?? 'خطأ في تعديل الفرع';
        throw Exception(err);
      }
    } catch (e) {
      rethrow;
    }
  }

  Future<bool> deleteBranch(int pointNo) async {
    try {
      final response = await http.delete(Uri.parse('$_baseUrl/api/points/$pointNo'));
      if (response.statusCode == 200) {
        return true;
      } else {
        final err = json.decode(utf8.decode(response.bodyBytes))['detail'] ?? 'خطأ في حذف الفرع';
        throw Exception(err);
      }
    } catch (e) {
      rethrow;
    }
  }

  Future<Map<String, dynamic>> testBranchConnection({
    required String dataSource,
    String catalog = "sp",
    String userId = "sa",
    String password = "as",
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/api/points/test-connection'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'dataSource': dataSource,
          'catalog': catalog,
          'userId': userId,
          'password': password,
        }),
      );
      if (response.statusCode == 200) {
        return json.decode(utf8.decode(response.bodyBytes));
      } else {
        return {
          'status': 'error',
          'connected': false,
          'message': 'فشل فحص الاتصال (كود ${response.statusCode})'
        };
      }
    } catch (e) {
      return {
        'status': 'error',
        'connected': false,
        'message': 'خطأ في الاتصال بالخدمة: $e'
      };
    }
  }

  Future<bool> syncBranchesFromSqlServer() async {
    try {
      final response = await http.post(Uri.parse('$_baseUrl/api/points/sync-sqlserver'));
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  // Special Remote POS Login
  Future<UserModel?> loginSpecial({
    required String username,
    required String password,
    required int pointNo,
    required String pointName,
    String? dataSource,
    String? mainCatalog,
  }) async {
    _isLoading = true;
    notifyListeners();
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/api/login/special'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'username': username,
          'password': password,
          'pointNo': pointNo,
          'pointName': pointName,
          'dataSource': dataSource ?? '',
          'mainCatalog': mainCatalog ?? '',
        }),
      );

      if (response.statusCode == 200) {
        final userData = json.decode(utf8.decode(response.bodyBytes));
        _currentUser = UserModel.fromJson(userData);
        _pointNo = pointNo;
        _pointName = pointName;
        _isConnected = true;

        await loadInitialData(isSpecialBranch: true);

        _isLoading = false;
        notifyListeners();
        return _currentUser;
      } else {
        final errorMsg = json.decode(utf8.decode(response.bodyBytes))['detail'] ?? 'خطأ في المصادقة لدخول النقطة البعيدة';
        _isLoading = false;
        notifyListeners();
        throw Exception(errorMsg);
      }
    } catch (e) {
      _isLoading = false;
      notifyListeners();
      rethrow;
    }
  }

  // Logout
  void logout() {
    _currentUser = null;
    notifyListeners();
  }

  // Load all items, groups, currencies in parallel
  Future<void> loadInitialData({bool isSpecialBranch = false}) async {
    if (!_isConnected && !await checkConnection()) return;
    
    _isLoading = true;
    notifyListeners();
    
    try {
      if (!isSpecialBranch) {
        try {
          final settings = await getConnectionSettings();
          _pointNo = settings['pointNo'] ?? 1;
          _pointName = settings['pointName'] ?? 'الرئيسية';
          _logoBase64 = settings['logoBase64'] ?? '';
        } catch (_) {}
      }

      try {
        final res = await http.get(Uri.parse('$_baseUrl/api/items'));
        if (res.statusCode == 200) {
          final List decoded = json.decode(utf8.decode(res.bodyBytes));
          _items = decoded.map((x) => ItemModel.fromJson(x)).toList();
        }
      } catch (e) {
        if (kDebugMode) print("Error fetching items: $e");
      }

      try {
        final res = await http.get(Uri.parse('$_baseUrl/api/groups'));
        if (res.statusCode == 200) {
          final List decoded = json.decode(utf8.decode(res.bodyBytes));
          _groups = decoded.map((x) => ItemGroupModel.fromJson(x)).toList();
        }
      } catch (e) {
        if (kDebugMode) print("Error fetching groups: $e");
      }

      try {
        final res = await http.get(Uri.parse('$_baseUrl/api/currencies'));
        if (res.statusCode == 200) {
          final List decoded = json.decode(utf8.decode(res.bodyBytes));
          _currencies = decoded.map((x) => CurrencyModel.fromJson(x)).toList();
        }
      } catch (e) {
        if (kDebugMode) print("Error fetching currencies: $e");
      }

      try {
        final res = await http.get(Uri.parse('$_baseUrl/api/settings/default-currency'));
        if (res.statusCode == 200) {
          final decoded = json.decode(utf8.decode(res.bodyBytes));
          _defaultMoneyId = decoded['defaultMoneyId'] ?? 1;
        }
      } catch (e) {
        if (kDebugMode) print("Error fetching default currency: $e");
      }

      try {
        final res = await http.get(Uri.parse('$_baseUrl/api/accounts'));
        if (res.statusCode == 200) {
          final List decoded = json.decode(utf8.decode(res.bodyBytes));
          _accounts = decoded.map((x) => AccountModel.fromJson(x)).toList();
        }
      } catch (e) {
        if (kDebugMode) print("Error fetching accounts: $e");
      }

      try {
        final res = await http.get(Uri.parse('$_baseUrl/api/bonds'));
        if (res.statusCode == 200) {
          final List decoded = json.decode(utf8.decode(res.bodyBytes));
          _bonds = decoded.map((x) => BondModel.fromJson(x)).toList();
        }
      } catch (e) {
        if (kDebugMode) print("Error fetching bonds: $e");
      }
      
    } catch (e) {
      if (kDebugMode) {
        print("Error loading initial data: $e");
      }
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Save Transaction (Invoice)
  Future<Map<String, dynamic>> saveTransaction(TransactionHeaderModel transaction) async {
    _isLoading = true;
    notifyListeners();
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/api/transactions'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode(transaction.toJson()),
      );

      if (response.statusCode == 200) {
        final result = json.decode(utf8.decode(response.bodyBytes));
        _isLoading = false;
        notifyListeners();
        return result;
      } else {
        final errorMsg = json.decode(utf8.decode(response.bodyBytes))['detail'] ?? 'فشل حفظ الفاتورة';
        _isLoading = false;
        notifyListeners();
        throw Exception(errorMsg);
      }
    } catch (e) {
      _isLoading = false;
      notifyListeners();
      rethrow;
    }
  }

  // Load Currencies
  Future<void> loadCurrencies() async {
    try {
      final res = await http.get(Uri.parse('$_baseUrl/api/currencies'));
      if (res.statusCode == 200) {
        final List decoded = json.decode(utf8.decode(res.bodyBytes));
        _currencies = decoded.map((x) => CurrencyModel.fromJson(x)).toList();
        notifyListeners();
      }
    } catch (e) {
      if (kDebugMode) print("Error fetching currencies: $e");
    }
  }

  // Load Accounts
  Future<void> loadAccounts() async {
    try {
      final response = await http.get(Uri.parse('$_baseUrl/api/accounts'));
      if (response.statusCode == 200) {
        final List decoded = json.decode(utf8.decode(response.bodyBytes));
        _accounts = decoded.map((x) => AccountModel.fromJson(x)).toList();
        notifyListeners();
      }
    } catch (e) {
      if (kDebugMode) print("Error loading accounts: $e");
    }
  }

  // Create Account
  Future<void> addAccount(String name, int accId) async {
    _isLoading = true;
    notifyListeners();
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/api/accounts'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'name': name, 'accId': accId}),
      );
      if (response.statusCode == 200) {
        await loadAccounts();
      } else {
        throw Exception("فشل إضافة الحساب");
      }
    } catch (e) {
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Load Bonds with filtering by date range, pointNo, transType, and moneyId
  Future<void> loadBonds({String? startDate, String? endDate, int? pointNo, int? transType, int? moneyId}) async {
    try {
      final queryParams = <String, String>{};
      if (startDate != null && startDate.isNotEmpty) queryParams['start_date'] = startDate;
      if (endDate != null && endDate.isNotEmpty) queryParams['end_date'] = endDate;
      if (pointNo != null && pointNo > 0) queryParams['point_no'] = pointNo.toString();
      if (transType != null && transType > 0) queryParams['trans_type'] = transType.toString();
      if (moneyId != null && moneyId > 0) queryParams['money_id'] = moneyId.toString();

      final uri = Uri.parse('$_baseUrl/api/bonds').replace(queryParameters: queryParams);
      final response = await http.get(uri);
      if (response.statusCode == 200) {
        final List decoded = json.decode(utf8.decode(response.bodyBytes));
        _bonds = decoded.map((x) => BondModel.fromJson(x)).toList();
        notifyListeners();
      }
    } catch (e) {
      if (kDebugMode) print("Error loading bonds: $e");
    }
  }

  // Create Bond (Single or Multi-line)
  Future<void> addBond(int expensesId, double amount, String note, bool isReceipt, {int? pointNo, String? bondDate, int? moneyId, int? accountId, List<BondItemModel>? details}) async {
    _isLoading = true;
    notifyListeners();
    try {
      final bodyData = <String, dynamic>{
        'expensesId': expensesId,
        'amount': amount,
        'note': note,
        'date': bondDate ?? _selectedDate,
        'isReceipt': isReceipt,
        'pointNo': pointNo ?? _pointNo,
        'userId': _currentUser?.userId ?? 1,
        'moneyId': moneyId ?? 1,
        'accountId': accountId ?? expensesId,
      };

      if (details != null && details.isNotEmpty) {
        bodyData['details'] = details.map((x) => x.toJson()).toList();
      }

      final response = await http.post(
        Uri.parse('$_baseUrl/api/bonds'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode(bodyData),
      );
      if (response.statusCode == 200) {
        await loadBonds();
      } else {
        final err = json.decode(utf8.decode(response.bodyBytes));
        throw Exception(err['detail'] ?? "فشل حفظ السند");
      }
    } catch (e) {
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Update Bond (Single or Multi-line)
  Future<void> updateBond(int id, double transNumber, int expensesId, double amount, String note, bool isReceipt, {int? pointNo, String? bondDate, int? moneyId, int? accountId, List<BondItemModel>? details}) async {
    _isLoading = true;
    notifyListeners();
    try {
      final bodyData = <String, dynamic>{
        'id': id,
        'transNumber': transNumber,
        'expensesId': expensesId,
        'amount': amount,
        'note': note,
        'date': bondDate ?? _selectedDate,
        'isReceipt': isReceipt,
        'pointNo': pointNo ?? _pointNo,
        'userId': _currentUser?.userId ?? 1,
        'moneyId': moneyId ?? 1,
        'accountId': accountId ?? expensesId,
      };

      if (details != null && details.isNotEmpty) {
        bodyData['details'] = details.map((x) => x.toJson()).toList();
      }

      final response = await http.put(
        Uri.parse('$_baseUrl/api/bonds'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode(bodyData),
      );
      if (response.statusCode == 200) {
        await loadBonds();
      } else {
        final err = json.decode(utf8.decode(response.bodyBytes));
        throw Exception(err['detail'] ?? "فشل تعديل السند");
      }
    } catch (e) {
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Delete Bond
  Future<void> deleteBond(int id, double transNumber) async {
    _isLoading = true;
    notifyListeners();
    try {
      final uri = Uri.parse('$_baseUrl/api/bonds/$id?trans_number=$transNumber');
      final response = await http.delete(uri);
      if (response.statusCode == 200) {
        await loadBonds();
      } else {
        final err = json.decode(utf8.decode(response.bodyBytes));
        throw Exception(err['detail'] ?? "فشل حذف السند");
      }
    } catch (e) {
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Upload/Post Bonds to Remote DB
  Future<Map<String, dynamic>> uploadBonds() async {
    _isLoading = true;
    notifyListeners();
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/api/bonds/upload'),
      );
      if (response.statusCode == 200) {
        return json.decode(utf8.decode(response.bodyBytes));
      }
      final err = json.decode(utf8.decode(response.bodyBytes));
      throw Exception(err['detail'] ?? 'فشل ترحيل السندات للسيرفر الرئيسي');
    } catch (e) {
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Fetch Remote Accounts from Main Server (dbo.tblAccount)
  Future<void> fetchRemoteAccounts() async {
    _isLoading = true;
    notifyListeners();
    try {
      final response = await http.get(Uri.parse('$_baseUrl/api/remote-accounts'));
      if (response.statusCode == 200) {
        final List decoded = json.decode(utf8.decode(response.bodyBytes));
        _remoteAccounts = decoded.cast<Map<String, dynamic>>();
      } else {
        throw Exception("فشل جلب الحسابات من الخادم الرئيسي");
      }
    } catch (e) {
      if (kDebugMode) print("Error fetching remote accounts: $e");
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Fetch local users list from local DB (tblUsers)
  Future<void> fetchUsers() async {
    try {
      final response = await http.get(Uri.parse('$_baseUrl/api/users'));
      if (response.statusCode == 200) {
        final List decoded = json.decode(utf8.decode(response.bodyBytes));
        _users = decoded.cast<Map<String, dynamic>>();
        notifyListeners();
      }
    } catch (e) {
      if (kDebugMode) print("Error fetching local users: $e");
    }
  }

  // Fetch Reports Summary
  // Fetch Reports Summary
  Future<Map<String, dynamic>> fetchReportsSummary(String? start, String? end, {int? moneyId}) async {
    try {
      String path = '/api/reports/summary?point_no=$_pointNo';
      if (start != null && end != null) {
        path += '&start_date=$start&end_date=$end';
      }
      if (moneyId != null && moneyId > 0) {
        path += '&money_id=$moneyId';
      }
      final response = await safeHttpGet(path);
      if (response.statusCode == 200) {
        return json.decode(utf8.decode(response.bodyBytes));
      }
      throw Exception("فشل جلب ملخص التقارير");
    } catch (e) {
      rethrow;
    }
  }

  // Fetch Reports Transactions
  Future<List<dynamic>> fetchReportsTransactions(int type, String? start, String? end, {int? moneyId}) async {
    try {
      String path = '/api/reports/transactions?type=$type&point_no=$_pointNo';
      if (start != null && end != null) {
        path += '&start_date=$start&end_date=$end';
      }
      if (moneyId != null && moneyId > 0) {
        path += '&money_id=$moneyId';
      }
      final response = await safeHttpGet(path);
      if (response.statusCode == 200) {
        return json.decode(utf8.decode(response.bodyBytes));
      }
      throw Exception("فشل جلب قائمة المعاملات");
    } catch (e) {
      rethrow;
    }
  }

  // Fetch Account Statement Ledger
  Future<Map<String, dynamic>> fetchAccountStatement({int? accountId, String? start, String? end, int? moneyId}) async {
    try {
      String path = '/api/reports/account-statement?point_no=$_pointNo&';
      if (accountId != null && accountId > 0) path += 'account_id=$accountId&';
      if (start != null && start.isNotEmpty) path += 'start_date=$start&';
      if (end != null && end.isNotEmpty) path += 'end_date=$end&';
      if (moneyId != null && moneyId > 0) path += 'money_id=$moneyId&';

      final response = await safeHttpGet(path);
      if (response.statusCode == 200) {
        return json.decode(utf8.decode(response.bodyBytes));
      }
      throw Exception("فشل جلب كشف حساب المصاريف والحسابات");
    } catch (e) {
      rethrow;
    }
  }

  // Get expenses & accounts list (tblExpensesList)
  Future<List<Map<String, dynamic>>> getExpensesAccountsList() async {
    try {
      final response = await safeHttpGet('/api/accounts');
      if (response.statusCode == 200) {
        final List data = json.decode(utf8.decode(response.bodyBytes));
        return data.cast<Map<String, dynamic>>();
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  Future<Map<String, dynamic>> fetchTransactionByNumber(double transNumber) async {
    try {
      final response = await safeHttpGet('/api/transactions/$transNumber');
      if (response.statusCode == 200) {
        return json.decode(utf8.decode(response.bodyBytes));
      }
      final err = json.decode(utf8.decode(response.bodyBytes))['detail'] ?? 'فشل جلب تفاصيل الفاتورة';
      throw Exception(err);
    } catch (e) {
      rethrow;
    }
  }

  Future<Map<String, dynamic>> updateTransaction(double transNumber, Map<String, dynamic> transData) async {
    try {
      final response = await http.put(
        Uri.parse('$_baseUrl/api/transactions/$transNumber'),
        headers: {'Content-Type': 'application/json; charset=utf-8'},
        body: json.encode(transData),
      );
      if (response.statusCode == 200) {
        return json.decode(utf8.decode(response.bodyBytes));
      }
      final err = json.decode(utf8.decode(response.bodyBytes))['detail'] ?? 'فشل تعديل الفاتورة';
      throw Exception(err);
    } catch (e) {
      rethrow;
    }
  }

  // Search item across all branches via remote main DB
  Future<Map<String, dynamic>> searchRemoteBranchItems(String query) async {
    try {
      final encodedQuery = Uri.encodeComponent(query);
      final response = await safeHttpGet('/api/remote/branch-item-search?query=$encodedQuery');
      if (response.statusCode == 200) {
        return json.decode(utf8.decode(response.bodyBytes));
      }
      throw Exception("فشل البحث في السيرفر الرئيسي عن الصنف في الفروع");
    } catch (e) {
      rethrow;
    }
  }

  // Get Inventory Stock Report (quantities, zero stock, low stock)
  Future<Map<String, dynamic>> getInventoryStockReport({
    String statusFilter = 'all',
    int groupId = 0,
    String searchQuery = '',
    int zeroThreshold = 0,
    int? moneyId,
  }) async {
    try {
      final encodedQuery = Uri.encodeComponent(searchQuery);
      var path = '/api/reports/stock?point_no=$_pointNo&status_filter=$statusFilter&group_id=$groupId&search_query=$encodedQuery&zero_threshold=$zeroThreshold';
      if (moneyId != null && moneyId > 0) {
        path += '&money_id=$moneyId';
      }
      final response = await safeHttpGet(path);
      if (response.statusCode == 200) {
        return json.decode(utf8.decode(response.bodyBytes));
      }
      throw Exception("فشل جلب تقرير الجرد المخزني");
    } catch (e) {
      rethrow;
    }
  }

  // Get connection settings from the server
  Future<Map<String, dynamic>> getConnectionSettings() async {
    try {
      final response = await http.get(Uri.parse('$_baseUrl/api/settings/connection'));
      if (response.statusCode == 200) {
        final bodyStr = utf8.decode(response.bodyBytes).trim();
        if (bodyStr.startsWith('<')) {
          throw Exception("عنوان خادم الـ API الحالي غير صحيح ($_baseUrl). يرجى إدخال عنوان خادم الـ API بالمنفذ 9000 (مثال: http://localhost:9000) بدلاً من منفذ الويب 8888.");
        }
        return json.decode(bodyStr);
      }
      throw Exception("فشل جلب إعدادات الاتصال من السيرفر (كود الاستجابة: ${response.statusCode})");
    } catch (e) {
      if (e.toString().contains('<') || e.toString().contains('SyntaxError') || _baseUrl.contains(':8888')) {
        throw Exception("عنوان خادم الـ API غير صحيح ($_baseUrl). يرجى تغيير عنوان خادم الـ API في الحقل بالأسفل إلى المنفذ 9000 (مثال: http://localhost:9000) بدلاً من منفذ المتصفح 8888.");
      }
      rethrow;
    }
  }

  // Update connection settings on the server and test them
  Future<void> updateConnectionSettings({
    required String server,
    required String remoteServer,
    required String localDb,
    required String remoteDb,
    required String username,
    required String password,
    required String port,
    required int pointNo,
    required String pointName,
    String logoBase64 = "",
  }) async {
    _isLoading = true;
    notifyListeners();
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/api/settings/connection'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'server': server,
          'remoteServer': remoteServer,
          'localDb': localDb,
          'remoteDb': remoteDb,
          'username': username,
          'password': password,
          'port': port,
          'pointNo': pointNo,
          'pointName': pointName,
          'logoBase64': logoBase64,
        }),
      );

      if (response.statusCode == 200) {
        // Success: reload initial data since connection properties changed!
        _isConnected = true;
        await loadInitialData();
      } else {
        final errorMsg = json.decode(utf8.decode(response.bodyBytes))['detail'] ?? 'فشل الاتصال بقاعدة البيانات';
        throw Exception(errorMsg);
      }
    } catch (e) {
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Fetch available POS points from main server
  Future<List<dynamic>> fetchPoints({
    required String remoteServer,
    required String remoteDb,
    required String username,
    required String password,
    required String port,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/api/settings/fetch-points'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'remoteServer': remoteServer,
          'remoteDb': remoteDb,
          'username': username,
          'password': password,
          'port': port,
        }),
      );
      if (response.statusCode == 200) {
        return json.decode(utf8.decode(response.bodyBytes));
      } else {
        final errorMsg = json.decode(utf8.decode(response.bodyBytes))['detail'] ?? 'فشل جلب نقاط البيع';
        throw Exception(errorMsg);
      }
    } catch (e) {
      rethrow;
    }
  }

  // Sync items from remote main server to local List database table
  Future<String> syncItems() async {
    _isLoading = true;
    notifyListeners();
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/api/settings/sync-items'),
        headers: {'Content-Type': 'application/json'},
      );
      if (response.statusCode == 200) {
        final Map<String, dynamic> data = json.decode(utf8.decode(response.bodyBytes));
        
        // Reload local items list immediately in the app!
        await loadInitialData();
        
        return data['message'] ?? 'تمت المزامنة بنجاح!';
      } else {
        final errorMsg = json.decode(utf8.decode(response.bodyBytes))['detail'] ?? 'فشل مزامنة الأصناف';
        throw Exception(errorMsg);
      }
    } catch (e) {
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Upload/Sync Transactions to remote DB
  Future<Map<String, dynamic>> uploadTransactions() async {
    _isLoading = true;
    notifyListeners();
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/api/settings/upload-transactions'),
      );
      if (response.statusCode == 200) {
        return json.decode(utf8.decode(response.bodyBytes));
      }
      final err = json.decode(utf8.decode(response.bodyBytes));
      throw Exception(err['detail'] ?? 'فشل ترحيل البيانات');
    } catch (e) {
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Transfer Main & details tables to remote DB
  Future<Map<String, dynamic>> transferMainDetailsTables() async {
    _isLoading = true;
    notifyListeners();
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/api/settings/transfer-tables'),
      );
      if (response.statusCode == 200) {
        return json.decode(utf8.decode(response.bodyBytes));
      }
      final err = json.decode(utf8.decode(response.bodyBytes));
      throw Exception(err['detail'] ?? 'فشل نقل الجداول');
    } catch (e) {
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Get local points list (tblPointList)
  Future<List<Map<String, dynamic>>> getLocalPoints() async {
    try {
      final response = await http.get(Uri.parse('$_baseUrl/api/points'));
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(utf8.decode(response.bodyBytes));
        return data.cast<Map<String, dynamic>>();
      } else {
        throw Exception('فشل جلب قائمة نقاط البيع المحلية');
      }
    } catch (e) {
      return [];
    }
  }

  // --- INTER-BRANCH TRANSFERS ---
  Future<List<dynamic>> fetchPendingTransfers(int toPointNo) async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/api/transfers/pending?to_point_no=$toPointNo'),
      );
      if (response.statusCode == 200) {
        return json.decode(utf8.decode(response.bodyBytes));
      } else {
        throw Exception('فشل جلب التحويلات المعلقة');
      }
    } catch (e) {
      if (kDebugMode) print("Error fetching pending transfers: $e");
      rethrow;
    }
  }

  Future<void> confirmTransfer(double transNumber, {int? toPointNo}) async {
    _isLoading = true;
    notifyListeners();
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/api/transfers/confirm'),
        headers: {'Content-Type': 'application/json; charset=utf-8'},
        body: json.encode({
          'transNumber': transNumber,
          'userId': _currentUser?.userId ?? 1,
          'toPointNo': toPointNo ?? _pointNo,
        }),
      );
      if (response.statusCode != 200) {
        final err = json.decode(utf8.decode(response.bodyBytes))['detail'] ?? 'فشل تأكيد الاستلام';
        throw Exception(err);
      }
    } catch (e) {
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Fetch POS Movements Report with Statistics
  Future<Map<String, dynamic>> fetchPosMovements({int? pointNo, String? startDate, String? endDate}) async {
    try {
      final queryParams = <String, String>{};
      if (pointNo != null && pointNo > 0) queryParams['point_no'] = pointNo.toString();
      if (startDate != null && startDate.isNotEmpty) queryParams['start_date'] = startDate;
      if (endDate != null && endDate.isNotEmpty) queryParams['end_date'] = endDate;

      final uri = Uri.parse('$_baseUrl/api/reports/pos-movements').replace(queryParameters: queryParams);
      final response = await http.get(uri);

      if (response.statusCode == 200) {
        return json.decode(utf8.decode(response.bodyBytes));
      } else {
        throw Exception('فشل جلب حركة المبيعات');
      }
    } catch (e) {
      rethrow;
    }
  }

  // --- ITEMS MANAGEMENT ---
  Future<void> reloadItems() async {
    try {
      final res = await http.get(Uri.parse('$_baseUrl/api/items'));
      if (res.statusCode == 200) {
        final List decoded = json.decode(utf8.decode(res.bodyBytes));
        _items = decoded.map((x) => ItemModel.fromJson(x)).toList();
        notifyListeners();
      }
    } catch (e) {
      if (kDebugMode) print("Error reloading items: $e");
    }
  }

  Future<ItemModel> addItem(ItemModel item) async {
    _isLoading = true;
    notifyListeners();
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/api/items'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode(item.toJson()),
      );
      if (response.statusCode == 200) {
        final Map<String, dynamic> data = json.decode(utf8.decode(response.bodyBytes));
        final created = ItemModel.fromJson(data);
        await reloadItems();
        return created;
      } else {
        final err = json.decode(utf8.decode(response.bodyBytes))['detail'] ?? 'فشل إضافة الصنف';
        throw Exception(err);
      }
    } catch (e) {
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<ItemModel> updateItem(ItemModel item) async {
    _isLoading = true;
    notifyListeners();
    try {
      final response = await http.put(
        Uri.parse('$_baseUrl/api/items/${item.itemId}'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode(item.toJson()),
      );
      if (response.statusCode == 200) {
        final Map<String, dynamic> data = json.decode(utf8.decode(response.bodyBytes));
        final updated = ItemModel.fromJson(data);
        await reloadItems();
        return updated;
      } else {
        final err = json.decode(utf8.decode(response.bodyBytes))['detail'] ?? 'فشل تعديل الصنف';
        throw Exception(err);
      }
    } catch (e) {
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> deleteItem(int itemId) async {
    _isLoading = true;
    notifyListeners();
    try {
      final response = await http.delete(
        Uri.parse('$_baseUrl/api/items/$itemId'),
      );
      if (response.statusCode == 200) {
        await reloadItems();
      } else {
        final err = json.decode(utf8.decode(response.bodyBytes))['detail'] ?? 'فشل إيقاف الصنف';
        throw Exception(err);
      }
    } catch (e) {
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // --- DAILY FINANCIAL BREAKDOWN REPORT ---
  Future<Map<String, dynamic>> fetchDailyFinancialBreakdownReport(String? startDate, String? endDate, {int? moneyId, int? pointNo}) async {
    try {
      final pt = pointNo ?? _pointNo;
      String path = '/api/reports/daily-financial-breakdown?point_no=$pt&';
      if (startDate != null && startDate.isNotEmpty) path += 'start_date=$startDate&';
      if (endDate != null && endDate.isNotEmpty) path += 'end_date=$endDate&';
      if (moneyId != null && moneyId > 0) path += 'money_id=$moneyId&';

      final response = await safeHttpGet(path);

      if (response.statusCode == 200) {
        return json.decode(utf8.decode(response.bodyBytes));
      } else {
        throw Exception('فشل جلب تقرير الإحصائية والحركة المالية اليومية');
      }
    } catch (e) {
      rethrow;
    }
  }

  // --- CASH MOVEMENT REPORT ---
  Future<Map<String, dynamic>> fetchCashMovementReport(String? startDate, String? endDate, {int? moneyId}) async {
    try {
      String path = '/api/reports/cash-movement?point_no=$_pointNo&';
      if (startDate != null && startDate.isNotEmpty) path += 'start_date=$startDate&';
      if (endDate != null && endDate.isNotEmpty) path += 'end_date=$endDate&';
      if (moneyId != null && moneyId > 0) path += 'money_id=$moneyId&';

      final response = await safeHttpGet(path);

      if (response.statusCode == 200) {
        return json.decode(utf8.decode(response.bodyBytes));
      } else {
        throw Exception('فشل جلب كشف حركة الصندوق النقدي');
      }
    } catch (e) {
      rethrow;
    }
  }

  Future<Map<String, dynamic>> fetchItemMovementReport({required String query, String? startDate, String? endDate}) async {
    try {
      String url = '$_baseUrl/api/reports/item-movement?point_no=$_pointNo&query=${Uri.encodeComponent(query)}';
      if (startDate != null && startDate.isNotEmpty) {
        url += '&start_date=$startDate';
      }
      if (endDate != null && endDate.isNotEmpty) {
        url += '&end_date=$endDate';
      }
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        return json.decode(utf8.decode(response.bodyBytes));
      }
      final err = json.decode(utf8.decode(response.bodyBytes))['detail'] ?? 'فشل جلب كشف حركة الصنف';
      throw Exception(err);
    } catch (e) {
      rethrow;
    }
  }

  // --- WHATSAPP REPORT PDF & TEXT SENDING ---
  Future<Map<String, dynamic>> sendWhatsAppReportPdf({
    required String phone,
    required String reportTitle,
    required String reportSummaryText,
    String? htmlContent,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/api/whatsapp/send-pdf'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'phone': phone,
          'reportTitle': reportTitle,
          'reportSummaryText': reportSummaryText,
          'htmlContent': htmlContent ?? '',
        }),
      );

      if (response.statusCode == 200) {
        return jsonDecode(utf8.decode(response.bodyBytes));
      } else {
        final err = jsonDecode(utf8.decode(response.bodyBytes))['detail'] ?? 'فشل إرسال التقرير عبر الواتساب';
        throw Exception(err);
      }
    } catch (e) {
      rethrow;
    }
  }

  Future<Map<String, dynamic>> sendWhatsAppTextMessage({
    required String phone,
    required String message,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/api/whatsapp/send-message'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'phone': phone,
          'message': message,
        }),
      );

      if (response.statusCode == 200) {
        return jsonDecode(utf8.decode(response.bodyBytes));
      } else {
        final err = jsonDecode(utf8.decode(response.bodyBytes))['detail'] ?? 'فشل إرسال الرسالة عبر الواتساب';
        throw Exception(err);
      }
    } catch (e) {
      rethrow;
    }
  }

  Future<Map<String, dynamic>> fetchWhatsAppStatus() async {
    try {
      final response = await http.get(Uri.parse('$_baseUrl/api/whatsapp/status'));
      if (response.statusCode == 200) {
        return jsonDecode(utf8.decode(response.bodyBytes));
      }
    } catch (_) {}
    return {"connected": false, "phone": "", "statusText": "جاري تجهيز سيرفر الواتساب 🔄", "hasQr": false};
  }

  Future<Map<String, dynamic>> fetchWhatsAppQr() async {
    try {
      final response = await http.get(Uri.parse('$_baseUrl/api/whatsapp/qr'));
      if (response.statusCode == 200) {
        return jsonDecode(utf8.decode(response.bodyBytes));
      }
    } catch (_) {}
    return {"status": "waiting", "qrDataUrl": "", "message": "فشل جلب رمز QR"};
  }

  Future<Map<String, dynamic>> getWhatsAppSettings() async {
    try {
      final response = await http.get(Uri.parse('$_baseUrl/api/whatsapp/settings'));
      if (response.statusCode == 200) {
        return jsonDecode(utf8.decode(response.bodyBytes));
      }
    } catch (_) {}
    return {
      "financialPhone": "",
      "auditPhone": "",
      "providerType": "baileys",
      "customApiUrl": "",
      "customToken": "",
      "autoSendFinancial": false,
      "autoSendAudit": false
    };
  }

  Future<Map<String, dynamic>> saveWhatsAppSettings(Map<String, dynamic> settings) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/api/whatsapp/settings'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(settings),
      );
      if (response.statusCode == 200) {
        return jsonDecode(utf8.decode(response.bodyBytes));
      } else {
        final err = jsonDecode(utf8.decode(response.bodyBytes))['detail'] ?? 'فشل حفظ الإعدادات';
        throw Exception(err);
      }
    } catch (e) {
      rethrow;
    }
  }

  // --- AUDIT TRAIL LOG API ---
  Future<Map<String, dynamic>> fetchAuditLogReport({
    String? startDate,
    String? endDate,
    int? userId,
    String? actionType,
  }) async {
    try {
      final queryParams = <String, String>{};
      if (startDate != null && startDate.isNotEmpty) queryParams['start_date'] = startDate;
      if (endDate != null && endDate.isNotEmpty) queryParams['end_date'] = endDate;
      if (userId != null) queryParams['user_id'] = userId.toString();
      if (actionType != null && actionType.isNotEmpty) queryParams['action_type'] = actionType;

      final uri = Uri.parse('$_baseUrl/api/reports/audit-log').replace(queryParameters: queryParams);
      final response = await http.get(uri);

      if (response.statusCode == 200) {
        return jsonDecode(utf8.decode(response.bodyBytes));
      } else {
        throw Exception('فشل جلب سجل حركات التدقيق');
      }
    } catch (e) {
      rethrow;
    }
  }

  Future<void> logAuditEvent({
    int? userId,
    String? userName,
    required String actionType,
    required String description,
    String? details,
  }) async {
    try {
      await http.post(
        Uri.parse('$_baseUrl/api/audit-log/add'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'userId': userId,
          'userName': userName ?? 'مستخدم',
          'actionType': actionType,
          'description': description,
          'details': details ?? '',
        }),
      );
    } catch (_) {}
  }

  // ==========================================================
  //          خدمة التحديث التلقائي (Auto Update Service)
  // ==========================================================

  Future<Map<String, dynamic>> checkSystemUpdate() async {
    try {
      final response = await http
          .get(Uri.parse('$_baseUrl/api/check_update'))
          .timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        return jsonDecode(utf8.decode(response.bodyBytes));
      }
    } catch (e) {
      debugPrint('Update check error: $e');
    }
    return {'status': 'error', 'has_update': false, 'message': 'تعذر فحص التحديثات'};
  }

  Future<Map<String, dynamic>> applySystemUpdate({String? updateUrl}) async {
    try {
      final response = await http
          .post(
            Uri.parse('$_baseUrl/api/apply_update'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'update_url': updateUrl ?? ''}),
          )
          .timeout(const Duration(minutes: 3));
      if (response.statusCode == 200) {
        return jsonDecode(utf8.decode(response.bodyBytes));
      } else {
        return {'status': 'error', 'message': 'خطأ من السيرفر: ${response.statusCode}'};
      }
    } catch (e) {
      debugPrint('Apply update error: $e');
      return {'status': 'error', 'message': 'حدث خطأ أثناء تنزيل التحديث: $e'};
    }
  }

  Future<Map<String, dynamic>> getSystemVersion() async {
    try {
      final response = await http
          .get(Uri.parse('$_baseUrl/api/system_version'))
          .timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
        return jsonDecode(utf8.decode(response.bodyBytes));
      }
    } catch (e) {
      debugPrint('System version error: $e');
    }
    return {'status': 'error', 'version': '1.0.0'};
  }
}



