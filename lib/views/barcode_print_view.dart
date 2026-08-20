import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:barcode/barcode.dart' as bc_lib;
import 'package:universal_html/html.dart' as html;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import '../services/api_service.dart';
import '../services/print_service.dart';
import '../models/item.dart';

class BarcodePrintView extends StatefulWidget {
  final ItemModel? initialItem;
  const BarcodePrintView({super.key, this.initialItem});

  @override
  State<BarcodePrintView> createState() => _BarcodePrintViewState();
}

class _BatchPrintItem {
  final ItemModel item;
  int count;
  String customModel;
  double customPrice;
  _BatchPrintItem({
    required this.item,
    this.count = 1,
    double? price,
  })  : customModel = '',
        customPrice = price ?? item.salesPrice;
}

class _BarcodePrintViewState extends State<BarcodePrintView> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // Selected item & search
  ItemModel? _selectedItem;
  int _selectedGroupId = 0; // 0 = all groups
  String _searchQuery = '';
  final List<_BatchPrintItem> _batchQueue = [];

  // Editable price override for the printed label
  double? _customPriceOverride;
  final TextEditingController _customPriceController = TextEditingController(text: '48.78');

  // Field Vertical Ordering
  List<String> _fieldOrder = ['header', 'itemName', 'price', 'barcode', 'extraInfo'];

  // Manual free-entry mode
  bool _manualEntryMode = false;
  final TextEditingController _manualItemNameController = TextEditingController(text: 'مغلق لماع جنز');
  final TextEditingController _manualBarcodeController = TextEditingController(text: 'AG25-207');
  final TextEditingController _manualPriceController = TextEditingController(text: '48.78');

  // Thermal Dimensions & Margins
  double _paperWidth = 50.0;
  double _paperHeight = 30.0;
  double _labelPaddingMm = 1.2;
  String _selectedSizeTemplate = '50x30';

  // Typography
  String _fontFamily = 'Cairo';

  // --- Element 1: Store Name (اسم المحل) ---
  String _storeName = 'الأميرة';
  String _storeNameColorHex = '#7e0542';
  bool _showStoreName = true;
  String _storeNameAlign = 'right'; // 'right', 'center', 'left'
  double _storeNameFontSize = 12.5;
  bool _storeNameBold = true;

  // --- Element 2: Store Logo (شعار المحل) ---
  bool _showLogo = true;
  String _logoAlign = 'right'; // 'right', 'center', 'left'
  String? _logoBase64;
  double _logoHeight = 8.5; // in mm

  // --- Element 3: Model / Item Code (رقم الصنف / الموديل) ---
  String _modelNumber = 'AG25-207';
  String _modelPrefix = ''; // e.g., 'Mod: ', 'رمز: '
  bool _showModelNumber = true;
  String _modelAlign = 'left'; // 'left', 'center', 'right'
  double _modelFontSize = 10.5;
  bool _modelBold = true;

  // Header row layout: 'split' (side by side) or 'stacked' (two lines)
  String _headerLayout = 'split';

  // --- Element 4: Item Name (اسم وبيان الصنف) ---
  bool _showItemName = true;
  String _itemNameAlign = 'right'; // 'right', 'center', 'left'
  double _itemNameFontSize = 10.0;
  bool _itemNameWrap = false; // true = 2 lines, false = single line truncate

  // --- Element 5: Price & Currency (السعر والعملة) ---
  bool _showPrice = true;
  String _priceAlign = 'center'; // 'center', 'right', 'left'
  double _priceFontSize = 14.5;
  String _currencySymbol = 'RS';
  String _currencyPosition = 'prefix'; // 'prefix' (RS48), 'suffix' (48 RS), 'none'
  bool _showVatNote = false;
  String _vatNoteText = 'شامل الضريبة';

  // --- Element 6: Barcode Graphic & Text (الباركود) ---
  bool _showBarcodeGraphic = true;
  String _barcodeAlign = 'center'; // 'center', 'right', 'left'
  bool _showBarcodeText = false;
  double _barcodeHeight = 12.0; // in mm
  String _barcodeType = 'Code128'; // 'Code128', 'Code39', 'Code93', 'EAN13', 'EAN8', 'UPCA', 'QR Code'

  // --- Element 7: Extra Info Field (المقاس / اللون / بلد الصنع / الملاحظة) ---
  bool _showExtraInfo = false;
  String _extraInfoText = 'المقاس: 40 | اللون: أسود';
  String _extraInfoAlign = 'center';
  double _extraInfoFontSize = 8.5;

  // Print execution & hardware
  int _printCount = 1;
  String _printerName = 'Xprinter XP-365B';
  List<String> _printers = [];
  bool _isLoadingPrinters = false;

  // Preview options
  double _previewZoom = 1.0;
  String _previewMode = 'single'; // 'single', 'strip'

  // Controllers
  final _printerController = TextEditingController(text: 'Xprinter XP-365B');
  final _widthController = TextEditingController(text: '50');
  final _heightController = TextEditingController(text: '30');
  final _paddingController = TextEditingController(text: '1.2');
  final _storeNameController = TextEditingController(text: 'الأميرة');
  final _modelController = TextEditingController(text: 'AG25-207');
  final _modelPrefixController = TextEditingController(text: '');
  final _countController = TextEditingController(text: '1');
  final _currencyController = TextEditingController(text: 'RS');
  final _logoHeightController = TextEditingController(text: '8.5');
  final _extraInfoController = TextEditingController(text: 'المقاس: 40 | اللون: أسود');

  final List<String> _fontFamilies = [
    'Cairo',
    'Tajawal',
    'Almarai',
    'Amiri',
    'Arial',
    'Tahoma',
    'Segoe UI',
  ];

  final List<Map<String, dynamic>> _colorPresets = [
    {'name': 'خمري ملكي', 'hex': '#7e0542', 'color': Color(0xFF7E0542)},
    {'name': 'بنفسجي داكن', 'hex': '#880e4f', 'color': Color(0xFF880E4F)},
    {'name': 'أسود كلاسيكي', 'hex': '#000000', 'color': Colors.black},
    {'name': 'أزرق كحلي', 'hex': '#1e3a8a', 'color': Color(0xFF1E3A8A)},
    {'name': 'أحمر ياقوتي', 'hex': '#b91c1c', 'color': Color(0xFFB91C1C)},
    {'name': 'أخضر زمردي', 'hex': '#065f46', 'color': Color(0xFF065F46)},
    {'name': 'ذهبي برونزي', 'hex': '#b45309', 'color': Color(0xFFB45309)},
  ];

  final List<String> _barcodeTypes = [
    'Code128',
    'Code39',
    'Code93',
    'EAN13',
    'EAN8',
    'UPCA',
    'QR Code',
  ];

  final List<Map<String, dynamic>> _sizeTemplates = [
    {'id': '50x30', 'name': '50 × 30 مم (القياسي لملصقات الباركود)'},
    {'id': '50x25', 'name': '50 × 25 مم (ملصق متوسط للملابس والأحذية)'},
    {'id': '40x22', 'name': '40 × 22 مم (ملصق صغير للمجوهرات والإكسسوارات)'},
    {'id': '60x40', 'name': '60 × 40 مم (ملصق كراتين ومستودعات عريض)'},
    {'id': '38x28', 'name': '38 × 28 مم (ملصق مصغر مضغوط)'},
    {'id': '70x50', 'name': '70 × 50 مم (ملصق بطاقات أسعار شحن)'},
    {'id': 'custom', 'name': 'مقاس مخصص (أبعاد يدوية بالمليمتر)'},
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadSettingsAndPrinters();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _printerController.dispose();
    _widthController.dispose();
    _heightController.dispose();
    _paddingController.dispose();
    _storeNameController.dispose();
    _modelController.dispose();
    _modelPrefixController.dispose();
    _countController.dispose();
    _currencyController.dispose();
    _logoHeightController.dispose();
    _extraInfoController.dispose();
    _customPriceController.dispose();
    _manualItemNameController.dispose();
    _manualBarcodeController.dispose();
    _manualPriceController.dispose();
    super.dispose();
  }

  Future<void> _loadSettingsAndPrinters() async {
    final prefs = await SharedPreferences.getInstance();
    final savedLogo = prefs.getString('barcode_logo_base64');
    final savedOrder = prefs.getString('barcode_field_order');

    setState(() {
      if (savedOrder != null && savedOrder.isNotEmpty) {
        try {
          final List<dynamic> decoded = jsonDecode(savedOrder);
          _fieldOrder = decoded.map((e) => e.toString()).toList();
        } catch (_) {}
      }

      _paperWidth = prefs.getDouble('barcode_paper_width') ?? 50.0;
      _paperHeight = prefs.getDouble('barcode_paper_height') ?? 30.0;
      _labelPaddingMm = prefs.getDouble('barcode_label_padding') ?? 1.2;

      _storeName = prefs.getString('barcode_store_name') ?? 'الأميرة';
      _storeNameColorHex = prefs.getString('barcode_store_color') ?? '#7e0542';
      _showStoreName = prefs.getBool('barcode_show_store_name') ?? true;
      _storeNameAlign = prefs.getString('barcode_store_align') ?? 'right';
      _storeNameFontSize = prefs.getDouble('barcode_store_font_size') ?? 12.5;
      _storeNameBold = prefs.getBool('barcode_store_bold') ?? true;

      _showLogo = prefs.getBool('barcode_show_logo') ?? true;
      _logoAlign = prefs.getString('barcode_logo_align') ?? 'right';
      _logoBase64 = (savedLogo != null && savedLogo.isNotEmpty) ? savedLogo : null;
      _logoHeight = prefs.getDouble('barcode_logo_height') ?? 8.5;

      _modelNumber = prefs.getString('barcode_model_number') ?? 'AG25-207';
      _modelPrefix = prefs.getString('barcode_model_prefix') ?? '';
      _showModelNumber = prefs.getBool('barcode_show_model_number') ?? true;
      _modelAlign = prefs.getString('barcode_model_align') ?? 'left';
      _modelFontSize = prefs.getDouble('barcode_model_font_size') ?? 10.5;
      _modelBold = prefs.getBool('barcode_model_bold') ?? true;
      _headerLayout = prefs.getString('barcode_header_layout') ?? 'split';

      _showItemName = prefs.getBool('barcode_show_item_name') ?? true;
      _itemNameAlign = prefs.getString('barcode_item_align') ?? 'right';
      _itemNameFontSize = prefs.getDouble('barcode_item_font_size') ?? 10.0;
      _itemNameWrap = prefs.getBool('barcode_item_wrap') ?? false;

      _showPrice = prefs.getBool('barcode_show_price') ?? true;
      _priceAlign = prefs.getString('barcode_price_align') ?? 'center';
      _priceFontSize = prefs.getDouble('barcode_price_font_size') ?? 14.5;
      _currencySymbol = prefs.getString('barcode_currency_symbol') ?? 'RS';
      _currencyPosition = prefs.getString('barcode_currency_pos') ?? 'prefix';
      _showVatNote = prefs.getBool('barcode_show_vat_note') ?? false;
      _vatNoteText = prefs.getString('barcode_vat_note_text') ?? 'شامل الضريبة';

      _showBarcodeGraphic = prefs.getBool('barcode_show_barcode_graphic') ?? true;
      _barcodeAlign = prefs.getString('barcode_barcode_align') ?? 'center';
      _showBarcodeText = prefs.getBool('barcode_show_text') ?? false;
      _barcodeHeight = prefs.getDouble('barcode_graphic_height') ?? 12.0;
      _barcodeType = prefs.getString('barcode_type') ?? 'Code128';

      _showExtraInfo = prefs.getBool('barcode_show_extra_info') ?? false;
      _extraInfoText = prefs.getString('barcode_extra_info_text') ?? 'المقاس: 40 | اللون: أسود';
      _extraInfoAlign = prefs.getString('barcode_extra_info_align') ?? 'center';
      _extraInfoFontSize = prefs.getDouble('barcode_extra_info_font_size') ?? 8.5;

      _fontFamily = prefs.getString('barcode_font_family') ?? 'Cairo';
      _printerName = prefs.getString('barcode_printer_name') ?? 'Xprinter XP-365B';
      _printCount = prefs.getInt('barcode_print_count') ?? 1;

      // Update controllers
      _widthController.text = _paperWidth.toStringAsFixed(0);
      _heightController.text = _paperHeight.toStringAsFixed(0);
      _paddingController.text = _labelPaddingMm.toStringAsFixed(1);
      _storeNameController.text = _storeName;
      _modelController.text = _modelNumber;
      _modelPrefixController.text = _modelPrefix;
      _countController.text = _printCount.toString();
      _printerController.text = _printerName;
      _currencyController.text = _currencySymbol;
      _logoHeightController.text = _logoHeight.toStringAsFixed(1);
      _extraInfoController.text = _extraInfoText;

      _selectedSizeTemplate = _getTemplateFromDimensions(_paperWidth, _paperHeight);

      if (widget.initialItem != null) {
        _selectedItem = widget.initialItem;
        _customPriceOverride = widget.initialItem!.salesPrice;
        _customPriceController.text = widget.initialItem!.salesPrice.toStringAsFixed(2);
        _searchQuery = widget.initialItem!.barcode;
      }
    });

    if (_logoBase64 == null) {
      await _loadDefaultAssetLogo();
    }

    await _fetchPrinters();
  }

  String _getTemplateFromDimensions(double width, double height) {
    if (width == 50.0 && height == 30.0) return '50x30';
    if (width == 50.0 && height == 25.0) return '50x25';
    if (width == 40.0 && height == 22.0) return '40x22';
    if (width == 60.0 && height == 40.0) return '60x40';
    if (width == 38.0 && height == 28.0) return '38x28';
    if (width == 70.0 && height == 50.0) return '70x50';
    return 'custom';
  }

  Future<void> _loadDefaultAssetLogo() async {
    try {
      const floralShoeSvg = '''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100" width="100" height="100">
        <path d="M10,85 Q40,85 55,65 Q70,45 85,30 Q92,20 95,10 Q85,15 75,25 Q60,40 50,55 Q40,70 10,75 Z" fill="#7e0542" />
        <path d="M85,30 L95,85 L88,85 L80,40 Z" fill="#4a0025" />
        <circle cx="82" cy="22" r="7" fill="#e91e63" />
        <circle cx="75" cy="28" r="6" fill="#f06292" />
        <circle cx="88" cy="30" r="5" fill="#ad1457" />
        <circle cx="68" cy="36" r="6" fill="#ec407a" />
        <circle cx="60" cy="46" r="5" fill="#f48fb1" />
        <circle cx="52" cy="56" r="4.5" fill="#c2185b" />
        <circle cx="44" cy="65" r="4" fill="#e91e63" />
        <path d="M78,16 Q85,8 92,15 Q95,22 88,25 Z" fill="#4caf50" opacity="0.8" />
        <path d="M60,40 Q55,30 65,32 Z" fill="#66bb6a" opacity="0.8" />
      </svg>''';
      final base64Str = base64Encode(utf8.encode(floralShoeSvg));
      final dataUrl = 'data:image/svg+xml;base64,$base64Str';
      setState(() {
        _logoBase64 = dataUrl;
      });
      await _saveSetting('barcode_logo_base64', dataUrl);
    } catch (e) {
      debugPrint('Default logo loading error: $e');
    }
  }

  Future<void> _fetchPrinters({bool showToast = false}) async {
    if (!mounted) return;
    final apiService = Provider.of<ApiService>(context, listen: false);
    setState(() {
      _isLoadingPrinters = true;
    });
    try {
      final response = await http.get(Uri.parse('${apiService.baseUrl}/api/printers'));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final list = List<String>.from(data['printers'] ?? []);
        setState(() {
          _printers = list;
          if (_printers.isNotEmpty && !_printers.contains(_printerName)) {
            _printerName = _printers.first;
            _printerController.text = _printerName;
          }
        });
        if (showToast && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                _printers.isNotEmpty
                    ? 'تم جلب وتحديث قائمة الطابعات بنجاح (${_printers.length} طابعة متاحة)'
                    : 'لم يتم العثور على طابعات حرارية متصلة بالنظام',
                style: const TextStyle(fontFamily: 'Cairo'),
              ),
              backgroundColor: _printers.isNotEmpty ? Colors.green : Colors.orange,
              duration: const Duration(seconds: 2),
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('Error fetching printers: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingPrinters = false;
        });
      }
    }
  }

  Future<void> _saveSetting(String key, dynamic value) async {
    final prefs = await SharedPreferences.getInstance();
    if (value is double) {
      await prefs.setDouble(key, value);
    } else if (value is bool) {
      await prefs.setBool(key, value);
    } else if (value is String) {
      await prefs.setString(key, value);
    } else if (value is int) {
      await prefs.setInt(key, value);
    }
  }

  void _moveFieldUp(int index) {
    if (index > 0) {
      setState(() {
        final item = _fieldOrder.removeAt(index);
        _fieldOrder.insert(index - 1, item);
      });
      _saveSetting('barcode_field_order', jsonEncode(_fieldOrder));
    }
  }

  void _moveFieldDown(int index) {
    if (index < _fieldOrder.length - 1) {
      setState(() {
        final item = _fieldOrder.removeAt(index);
        _fieldOrder.insert(index + 1, item);
      });
      _saveSetting('barcode_field_order', jsonEncode(_fieldOrder));
    }
  }

  void _resetFieldOrder() {
    setState(() {
      _fieldOrder = ['header', 'itemName', 'price', 'barcode', 'extraInfo'];
    });
    _saveSetting('barcode_field_order', jsonEncode(_fieldOrder));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('تمت استعادة ترتيب الحقول الافتراضي بنجاح 🔄', style: TextStyle(fontFamily: 'Cairo')),
        backgroundColor: Colors.blueAccent,
        duration: Duration(seconds: 1),
      ),
    );
  }

  void _pickLogoImage() {
    try {
      final uploadInput = html.FileUploadInputElement();
      uploadInput.accept = 'image/*';
      uploadInput.click();

      uploadInput.onChange.listen((e) {
        final files = uploadInput.files;
        if (files != null && files.isNotEmpty) {
          final file = files[0];
          final reader = html.FileReader();
          reader.readAsDataUrl(file);
          reader.onLoadEnd.listen((e) {
            if (reader.result != null) {
              final base64String = reader.result as String;
              setState(() {
                _logoBase64 = base64String;
              });
              _saveSetting('barcode_logo_base64', base64String);
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('تم رفع وحفظ شعار المحل بنجاح 🖼️', style: TextStyle(fontFamily: 'Cairo')),
                  backgroundColor: Colors.green,
                ),
              );
            }
          });
        }
      });
    } catch (e) {
      debugPrint('Error picking file: $e');
    }
  }

  void _removeLogoImage() {
    _loadDefaultAssetLogo();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('تمت استعادة الشعار الافتراضي (الأميرة)', style: TextStyle(fontFamily: 'Cairo')),
        backgroundColor: Colors.orange,
      ),
    );
  }

  // Preset Layout Applications
  void _applyPreset(String presetKey) {
    setState(() {
      switch (presetKey) {
        case 'princess_royal':
          _paperWidth = 50.0;
          _paperHeight = 30.0;
          _fieldOrder = ['header', 'itemName', 'price', 'barcode', 'extraInfo'];
          _storeName = 'الأميرة';
          _storeNameColorHex = '#7e0542';
          _showStoreName = true;
          _storeNameAlign = 'right';
          _storeNameFontSize = 12.5;
          _showLogo = true;
          _logoAlign = 'right';
          _logoHeight = 8.5;
          _showModelNumber = true;
          _modelAlign = 'left';
          _modelFontSize = 10.5;
          _showItemName = true;
          _itemNameAlign = 'right';
          _itemNameFontSize = 10.0;
          _showPrice = true;
          _priceAlign = 'center';
          _priceFontSize = 14.5;
          _currencySymbol = 'RS';
          _currencyPosition = 'prefix';
          _showBarcodeGraphic = true;
          _barcodeAlign = 'center';
          _showBarcodeText = false;
          _barcodeHeight = 12.0;
          _barcodeType = 'Code128';
          _showExtraInfo = false;
          break;

        case 'apparel_shoes':
          _paperWidth = 50.0;
          _paperHeight = 25.0;
          _fieldOrder = ['header', 'itemName', 'price', 'extraInfo', 'barcode'];
          _showStoreName = true;
          _storeNameAlign = 'right';
          _storeNameFontSize = 10.5;
          _showLogo = true;
          _logoAlign = 'right';
          _logoHeight = 7.0;
          _showModelNumber = true;
          _modelAlign = 'left';
          _modelFontSize = 9.5;
          _showItemName = true;
          _itemNameAlign = 'right';
          _itemNameFontSize = 9.0;
          _showPrice = true;
          _priceAlign = 'center';
          _priceFontSize = 13.0;
          _currencySymbol = 'RS';
          _currencyPosition = 'prefix';
          _showBarcodeGraphic = true;
          _barcodeAlign = 'center';
          _showBarcodeText = false;
          _barcodeHeight = 9.0;
          _barcodeType = 'Code128';
          _showExtraInfo = true;
          _extraInfoText = 'المقاس: 41 | اللون: أسود';
          _extraInfoFontSize = 8.0;
          break;

        case 'supermarket_ean':
          _paperWidth = 50.0;
          _paperHeight = 30.0;
          _fieldOrder = ['header', 'itemName', 'price', 'barcode', 'extraInfo'];
          _showStoreName = true;
          _storeNameAlign = 'center';
          _storeNameFontSize = 11.0;
          _showLogo = false;
          _showModelNumber = false;
          _showItemName = true;
          _itemNameAlign = 'center';
          _itemNameFontSize = 11.0;
          _showPrice = true;
          _priceAlign = 'center';
          _priceFontSize = 16.0;
          _currencySymbol = 'د.أ';
          _currencyPosition = 'suffix';
          _showBarcodeGraphic = true;
          _barcodeAlign = 'center';
          _showBarcodeText = true;
          _barcodeHeight = 11.0;
          _barcodeType = 'EAN13';
          _showExtraInfo = false;
          break;

        case 'mini_jewelry':
          _paperWidth = 40.0;
          _paperHeight = 22.0;
          _fieldOrder = ['header', 'itemName', 'price', 'barcode', 'extraInfo'];
          _showStoreName = true;
          _storeNameAlign = 'right';
          _storeNameFontSize = 9.0;
          _showLogo = false;
          _showModelNumber = true;
          _modelAlign = 'left';
          _modelFontSize = 8.0;
          _showItemName = true;
          _itemNameAlign = 'right';
          _itemNameFontSize = 8.0;
          _showPrice = true;
          _priceAlign = 'center';
          _priceFontSize = 11.0;
          _currencySymbol = 'RS';
          _currencyPosition = 'prefix';
          _showBarcodeGraphic = true;
          _barcodeAlign = 'center';
          _showBarcodeText = false;
          _barcodeHeight = 7.5;
          _barcodeType = 'Code128';
          _showExtraInfo = false;
          break;

        case 'modern_qr':
          _paperWidth = 50.0;
          _paperHeight = 30.0;
          _fieldOrder = ['header', 'itemName', 'price', 'barcode', 'extraInfo'];
          _showStoreName = true;
          _storeNameAlign = 'right';
          _storeNameFontSize = 12.0;
          _showLogo = true;
          _logoAlign = 'right';
          _logoHeight = 8.0;
          _showModelNumber = true;
          _modelAlign = 'left';
          _modelFontSize = 10.0;
          _showItemName = true;
          _itemNameAlign = 'right';
          _itemNameFontSize = 9.5;
          _showPrice = true;
          _priceAlign = 'center';
          _priceFontSize = 13.5;
          _currencySymbol = 'RS';
          _currencyPosition = 'prefix';
          _showBarcodeGraphic = true;
          _barcodeAlign = 'center';
          _showBarcodeText = false;
          _barcodeHeight = 11.0;
          _barcodeType = 'QR Code';
          _showExtraInfo = false;
          break;

        case 'warehouse_wide':
          _paperWidth = 60.0;
          _paperHeight = 40.0;
          _fieldOrder = ['header', 'itemName', 'extraInfo', 'price', 'barcode'];
          _storeName = 'الأميرة';
          _storeNameColorHex = '#000000';
          _showStoreName = true;
          _storeNameAlign = 'right';
          _storeNameFontSize = 14.0;
          _showLogo = true;
          _logoAlign = 'right';
          _logoHeight = 10.0;
          _showModelNumber = true;
          _modelAlign = 'left';
          _modelFontSize = 12.0;
          _showItemName = true;
          _itemNameAlign = 'right';
          _itemNameFontSize = 12.0;
          _showPrice = true;
          _priceAlign = 'center';
          _priceFontSize = 18.0;
          _currencySymbol = 'RS';
          _currencyPosition = 'prefix';
          _showBarcodeGraphic = true;
          _barcodeAlign = 'center';
          _showBarcodeText = true;
          _barcodeHeight = 15.0;
          _barcodeType = 'Code128';
          _showExtraInfo = true;
          _extraInfoText = 'بلد الصنع: تركيا | كرتون: 12 حبة';
          _extraInfoFontSize = 9.5;
          break;
      }

      _widthController.text = _paperWidth.toStringAsFixed(0);
      _heightController.text = _paperHeight.toStringAsFixed(0);
      _storeNameController.text = _storeName;
      _modelController.text = _modelNumber;
      _currencyController.text = _currencySymbol;
      _logoHeightController.text = _logoHeight.toStringAsFixed(1);
      _extraInfoController.text = _extraInfoText;
      _selectedSizeTemplate = _getTemplateFromDimensions(_paperWidth, _paperHeight);
    });

    _saveAllSettings();

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('تم تطبيق القالب الجاهز بنجاح ✨', style: TextStyle(fontFamily: 'Cairo')),
        backgroundColor: Colors.blueAccent,
        duration: Duration(seconds: 1),
      ),
    );
  }

  Future<void> _saveAllSettings() async {
    await _saveSetting('barcode_field_order', jsonEncode(_fieldOrder));
    await _saveSetting('barcode_paper_width', _paperWidth);
    await _saveSetting('barcode_paper_height', _paperHeight);
    await _saveSetting('barcode_label_padding', _labelPaddingMm);
    await _saveSetting('barcode_store_name', _storeName);
    await _saveSetting('barcode_store_color', _storeNameColorHex);
    await _saveSetting('barcode_show_store_name', _showStoreName);
    await _saveSetting('barcode_store_align', _storeNameAlign);
    await _saveSetting('barcode_store_font_size', _storeNameFontSize);
    await _saveSetting('barcode_show_logo', _showLogo);
    await _saveSetting('barcode_logo_align', _logoAlign);
    await _saveSetting('barcode_logo_height', _logoHeight);
    await _saveSetting('barcode_show_model_number', _showModelNumber);
    await _saveSetting('barcode_model_align', _modelAlign);
    await _saveSetting('barcode_model_font_size', _modelFontSize);
    await _saveSetting('barcode_header_layout', _headerLayout);
    await _saveSetting('barcode_show_item_name', _showItemName);
    await _saveSetting('barcode_item_align', _itemNameAlign);
    await _saveSetting('barcode_item_font_size', _itemNameFontSize);
    await _saveSetting('barcode_show_price', _showPrice);
    await _saveSetting('barcode_price_align', _priceAlign);
    await _saveSetting('barcode_price_font_size', _priceFontSize);
    await _saveSetting('barcode_currency_symbol', _currencySymbol);
    await _saveSetting('barcode_currency_pos', _currencyPosition);
    await _saveSetting('barcode_show_barcode_graphic', _showBarcodeGraphic);
    await _saveSetting('barcode_barcode_align', _barcodeAlign);
    await _saveSetting('barcode_show_text', _showBarcodeText);
    await _saveSetting('barcode_graphic_height', _barcodeHeight);
    await _saveSetting('barcode_type', _barcodeType);
    await _saveSetting('barcode_font_family', _fontFamily);
    await _saveSetting('barcode_show_extra_info', _showExtraInfo);
    await _saveSetting('barcode_extra_info_text', _extraInfoText);
  }

  bc_lib.Barcode _getBarcodeType() {
    switch (_barcodeType) {
      case 'Code39':
        return bc_lib.Barcode.code39();
      case 'Code93':
        return bc_lib.Barcode.code93();
      case 'EAN13':
        return bc_lib.Barcode.ean13();
      case 'EAN8':
        return bc_lib.Barcode.ean8();
      case 'UPCA':
        return bc_lib.Barcode.upcA();
      case 'QR Code':
        return bc_lib.Barcode.qrCode();
      case 'Code128':
      default:
        return bc_lib.Barcode.code128();
    }
  }

  String _getActiveItemName() {
    if (_manualEntryMode) {
      return _manualItemNameController.text.trim().isEmpty ? 'صنف تجريبي' : _manualItemNameController.text.trim();
    }
    if (_selectedItem != null) {
      return _selectedItem!.itemName.trim();
    }
    return 'مغلق لماع جنز';
  }

  String _getActiveBarcode() {
    if (_manualEntryMode) {
      return _manualBarcodeController.text.trim().isEmpty ? 'AG25-207' : _manualBarcodeController.text.trim();
    }
    if (_selectedItem != null && _selectedItem!.barcode.trim().isNotEmpty) {
      return _selectedItem!.barcode.trim();
    }
    return _modelNumber.isNotEmpty ? _modelNumber : 'AG25-207';
  }

  double _getActivePrice() {
    if (_manualEntryMode) {
      return double.tryParse(_manualPriceController.text) ?? 48.78;
    }
    if (_customPriceOverride != null) {
      return _customPriceOverride!;
    }
    if (_selectedItem != null) {
      return _selectedItem!.salesPrice;
    }
    return 48.78;
  }

  String _buildFullItemName({String? overrideName, String? overrideModel}) {
    final baseName = overrideName ?? _getActiveItemName();
    final model = overrideModel ?? _modelNumber;
    if (model.isNotEmpty && !baseName.contains(model)) {
      return '$baseName $model';
    }
    return baseName;
  }

  String _buildFormattedPrice(double price) {
    final priceStr = price.toStringAsFixed(2);
    if (_currencyPosition == 'prefix') {
      return '$_currencySymbol$priceStr';
    } else if (_currencyPosition == 'suffix') {
      return '$priceStr $_currencySymbol';
    }
    return priceStr;
  }

  String _mapAlignToJustify(String align) {
    if (align == 'left') return 'flex-start';
    if (align == 'right') return 'flex-end';
    return 'center';
  }

  String _generateBarcodeSvg(String codeVal) {
    String finalBarcodeVal = codeVal;
    if (_barcodeType == 'EAN13') {
      final clean = codeVal.replaceAll(RegExp(r'\D'), '');
      finalBarcodeVal = clean.length < 12 ? clean.padRight(12, '0') : clean.substring(0, 12);
    } else if (_barcodeType == 'EAN8') {
      final clean = codeVal.replaceAll(RegExp(r'\D'), '');
      finalBarcodeVal = clean.length < 7 ? clean.padRight(7, '0') : clean.substring(0, 7);
    } else if (_barcodeType == 'UPCA') {
      final clean = codeVal.replaceAll(RegExp(r'\D'), '');
      finalBarcodeVal = clean.length < 11 ? clean.padRight(11, '0') : clean.substring(0, 11);
    }

    try {
      final bc = _getBarcodeType();
      return bc.toSvg(
        finalBarcodeVal.isEmpty ? '123456' : finalBarcodeVal,
        width: _barcodeType == 'QR Code' ? 90 : 260,
        height: _barcodeType == 'QR Code' ? 90 : 75,
        fontHeight: 0,
      );
    } catch (e) {
      try {
        final bc = bc_lib.Barcode.code128();
        return bc.toSvg(
          codeVal.isEmpty ? '123456' : codeVal,
          width: 260,
          height: 75,
          fontHeight: 0,
        );
      } catch (_) {
        return '';
      }
    }
  }

  String _generateHtmlContent({bool isBatch = false}) {
    final double paperW = _paperWidth;
    final double paperH = _paperHeight;
    final double pad = _labelPaddingMm;
    final String logoSrc = _logoBase64 ?? '';

    List<({String itemName, String barcode, double price, String model, int count})> printList = [];

    if (isBatch && _batchQueue.isNotEmpty) {
      for (final b in _batchQueue) {
        printList.add((
          itemName: b.item.itemName,
          barcode: b.item.barcode.isNotEmpty ? b.item.barcode : '123456',
          price: b.customPrice,
          model: b.customModel.isNotEmpty ? b.customModel : (b.item.barcode.isNotEmpty ? b.item.barcode : _modelNumber),
          count: b.count,
        ));
      }
    } else {
      printList.add((
        itemName: _getActiveItemName(),
        barcode: _getActiveBarcode(),
        price: _getActivePrice(),
        model: _modelNumber,
        count: _printCount,
      ));
    }

    final List<String> pages = [];

    for (final itm in printList) {
      final fullItemName = _buildFullItemName(overrideName: itm.itemName, overrideModel: itm.model);
      final formattedPrice = _buildFormattedPrice(itm.price);
      final svgString = _generateBarcodeSvg(itm.barcode);
      final String base64Svg = base64Encode(utf8.encode(svgString));

      for (int i = 0; i < itm.count; i++) {
        // Build modular HTML blocks in the user's custom order
        final Map<String, String> rowHtmlMap = {};

        // 1. Header block (Store name, logo, model)
        if (_showStoreName || _showLogo || _showModelNumber) {
          final modelText = _showModelNumber ? '${_modelPrefix.isNotEmpty ? '$_modelPrefix ' : ''}${itm.model}' : '';
          final storeNameHtml = _showStoreName ? '<span class="store-name">$_storeName</span>' : '';
          final logoHtml = _showLogo && logoSrc.isNotEmpty ? '<img class="store-logo" src="$logoSrc" />' : '';

          if (_headerLayout == 'stacked') {
            rowHtmlMap['header'] = """
            <div class="top-row-stacked">
              <div class="store-group" style="justify-content: ${_mapAlignToJustify(_storeNameAlign)}; width: 100%;">
                $storeNameHtml
                $logoHtml
              </div>
              ${modelText.isNotEmpty ? '<div class="model-code" style="text-align: $_modelAlign; width: 100%;">$modelText</div>' : ''}
            </div>
            """;
          } else {
            rowHtmlMap['header'] = """
            <div class="top-row">
              <div class="store-group" style="justify-content: ${_mapAlignToJustify(_storeNameAlign)};">
                $storeNameHtml
                $logoHtml
              </div>
              <div class="model-code" style="text-align: $_modelAlign;">
                $modelText
              </div>
            </div>
            """;
          }
        }

        // 2. Item Name block
        if (_showItemName) {
          rowHtmlMap['itemName'] = '<div class="item-name-row" style="text-align: $_itemNameAlign; direction: ${_itemNameAlign == 'left' ? 'ltr' : 'rtl'};">$fullItemName</div>';
        }

        // 3. Price block
        if (_showPrice) {
          final vatHtml = _showVatNote ? ' <span class="vat-note">$_vatNoteText</span>' : '';
          rowHtmlMap['price'] = '<div class="price-row" style="text-align: $_priceAlign; justify-content: ${_mapAlignToJustify(_priceAlign)};">$formattedPrice$vatHtml</div>';
        }

        // 4. Extra info block
        if (_showExtraInfo && _extraInfoText.isNotEmpty) {
          rowHtmlMap['extraInfo'] = '<div class="extra-info-row" style="text-align: $_extraInfoAlign;">$_extraInfoText</div>';
        }

        // 5. Barcode block
        if (_showBarcodeGraphic || _showBarcodeText) {
          final barcodeGraphicHtml = _showBarcodeGraphic ? '<div class="barcode-row" style="justify-content: ${_mapAlignToJustify(_barcodeAlign)};"><img src="data:image/svg+xml;base64,$base64Svg" /></div>' : '';
          final barcodeTextHtml = _showBarcodeText ? '<div class="barcode-text-val" style="text-align: $_barcodeAlign;">${itm.barcode}</div>' : '';
          rowHtmlMap['barcode'] = '$barcodeGraphicHtml\n$barcodeTextHtml';
        }

        // Assemble page according to _fieldOrder
        final List<String> pageBlocks = [];
        for (final k in _fieldOrder) {
          if (rowHtmlMap.containsKey(k)) {
            pageBlocks.add(rowHtmlMap[k]!);
          }
        }

        pages.add("""
        <div class="label-page">
          ${pageBlocks.join('\n')}
        </div>
        """);
      }
    }

    final pagesHtml = pages.join('\n');

    return """
<!DOCTYPE html>
<html lang="ar" dir="rtl">
<head>
  <meta charset="UTF-8">
  <title>طباعة ملصقات الباركود - POS</title>
  <style>
    @import url('https://fonts.googleapis.com/css2?family=Cairo:wght@400;700;900&family=Tajawal:wght@400;700;900&family=Almarai:wght@400;700;800&family=Amiri:wght@700&display=swap');

    @page {
      size: ${paperW}mm ${paperH}mm !important;
      margin: 0mm !important;
    }
    @media print {
      @page {
        size: ${paperW}mm ${paperH}mm !important;
        margin: 0mm !important;
      }
      html, body {
        width: ${paperW}mm !important;
        height: ${paperH}mm !important;
        margin: 0mm !important;
        padding: 0mm !important;
        overflow: hidden !important;
        -webkit-print-color-adjust: exact !important;
        print-color-adjust: exact !important;
      }
      .label-page {
        width: ${paperW}mm !important;
        height: ${paperH}mm !important;
        max-width: ${paperW}mm !important;
        max-height: ${paperH}mm !important;
        margin: 0mm !important;
        padding: ${pad}mm !important;
        page-break-before: auto !important;
        page-break-after: always !important;
        break-after: page !important;
        page-break-inside: avoid !important;
        overflow: hidden !important;
        box-sizing: border-box !important;
      }
      .label-page:last-child {
        page-break-after: avoid !important;
        break-after: avoid !important;
      }
    }
    * {
      box-sizing: border-box !important;
      -webkit-print-color-adjust: exact !important;
      print-color-adjust: exact !important;
    }
    html, body {
      margin: 0;
      padding: 0;
      width: ${paperW}mm;
      height: ${paperH}mm;
      background-color: #ffffff;
      font-family: '$_fontFamily', 'Cairo', 'Segoe UI', Tahoma, sans-serif;
      direction: rtl;
    }
    .label-page {
      width: ${paperW}mm;
      height: ${paperH}mm;
      max-width: ${paperW}mm;
      max-height: ${paperH}mm;
      display: flex;
      flex-direction: column;
      justify-content: space-between;
      box-sizing: border-box;
      padding: ${pad}mm;
      overflow: hidden;
      background-color: #ffffff;
    }

    /* 1. Top Row */
    .top-row {
      width: 100%;
      display: flex;
      flex-direction: row;
      justify-content: space-between;
      align-items: center;
      line-height: 1;
      margin-bottom: 0.2mm;
    }
    .top-row-stacked {
      width: 100%;
      display: flex;
      flex-direction: column;
      gap: 1px;
      margin-bottom: 0.2mm;
    }
    .model-code {
      font-size: ${_modelFontSize}pt;
      font-weight: ${_modelBold ? 'bold' : 'normal'};
      color: #000000;
      font-family: '$_fontFamily', 'Segoe UI', Arial, sans-serif;
      direction: ltr;
      white-space: nowrap;
      overflow: hidden;
      text-overflow: ellipsis;
      flex: 1;
    }
    .store-group {
      display: flex;
      flex-direction: row;
      align-items: center;
      gap: 3px;
      flex: 1.5;
    }
    .store-name {
      font-size: ${_storeNameFontSize}pt;
      font-weight: ${_storeNameBold ? '900' : 'bold'};
      color: $_storeNameColorHex;
      font-family: '$_fontFamily', 'Cairo', sans-serif;
      letter-spacing: 0.5px;
      white-space: nowrap;
    }
    .store-logo {
      height: ${_logoHeight}mm;
      max-height: ${_logoHeight}mm;
      width: auto;
      object-fit: contain;
      display: inline-block;
    }

    /* 2. Item Name Row */
    .item-name-row {
      width: 100%;
      font-size: ${_itemNameFontSize}pt;
      font-weight: bold;
      color: #000000;
      white-space: ${_itemNameWrap ? 'normal' : 'nowrap'};
      overflow: hidden;
      text-overflow: ellipsis;
      line-height: 1.15;
      font-family: '$_fontFamily', 'Cairo', Arial, sans-serif;
      margin-bottom: 0.2mm;
    }

    /* 3. Price Row */
    .price-row {
      width: 100%;
      font-size: ${_priceFontSize}pt;
      font-weight: 900;
      color: #000000;
      line-height: 1;
      font-family: '$_fontFamily', 'Segoe UI', Arial, sans-serif;
      margin-bottom: 0.2mm;
      letter-spacing: 0.5px;
    }
    .vat-note {
      font-size: 7pt;
      font-weight: normal;
      color: #444;
      margin-right: 4px;
    }

    /* 4. Extra info row */
    .extra-info-row {
      width: 100%;
      font-size: ${_extraInfoFontSize}pt;
      font-weight: bold;
      color: #222;
      line-height: 1;
      margin-bottom: 0.2mm;
      white-space: nowrap;
      overflow: hidden;
    }

    /* 5. Barcode Graphic */
    .barcode-row {
      width: 100%;
      max-height: ${_barcodeHeight}mm;
      display: flex;
      align-items: center;
      overflow: hidden;
      flex-grow: 1;
    }
    .barcode-row img {
      width: ${_barcodeType == 'QR Code' ? 'auto' : '100%'};
      height: ${_barcodeType == 'QR Code' ? '${_barcodeHeight}mm' : 'auto'};
      max-height: 100%;
      object-fit: contain;
      display: block;
      margin: 0 auto;
    }
    .barcode-text-val {
      font-size: 8pt;
      font-weight: bold;
      font-family: monospace;
      letter-spacing: 2px;
      margin-top: 0.3mm;
    }
  </style>
</head>
<body onload="setTimeout(function(){ try { window.focus(); window.print(); } catch(e){} }, 350);">
  $pagesHtml
</body>
</html>
""";
  }

  void _printLabelsBrowser({bool isBatch = false}) {
    final htmlContent = _generateHtmlContent(isBatch: isBatch);
    if (htmlContent.isEmpty) return;

    PrintService.printHtml(htmlContent);

    final totalCount = isBatch
        ? _batchQueue.fold<int>(0, (sum, i) => sum + i.count)
        : _printCount;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('تم فتح نافذة الطباعة لـ $totalCount ملصق...', style: const TextStyle(fontFamily: 'Cairo')),
        backgroundColor: Colors.green,
      ),
    );
  }

  Future<void> _printLabelsDirect(String baseUrl, {bool isBatch = false}) async {
    final htmlContent = _generateHtmlContent(isBatch: isBatch);
    if (htmlContent.isEmpty) return;

    final totalCount = isBatch
        ? _batchQueue.fold<int>(0, (sum, i) => sum + i.count)
        : _printCount;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('جاري إرسال $totalCount ملصق للطابعة ($_printerName)...', style: const TextStyle(fontFamily: 'Cairo')),
        backgroundColor: Colors.blueAccent,
        duration: const Duration(seconds: 2),
      ),
    );

    final success = await PrintService.printHtmlDirect(
      htmlContent: htmlContent,
      baseUrl: baseUrl,
      printerName: _printerName,
    );

    if (!mounted) return;
    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('تمت الطباعة المباشرة بنجاح على $_printerName ✅', style: const TextStyle(fontFamily: 'Cairo')),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  Widget _buildLogoWidget() {
    if (!_showLogo) return const SizedBox.shrink();
    if (_logoBase64 != null && _logoBase64!.isNotEmpty) {
      if (_logoBase64!.startsWith('data:image/svg+xml;base64,')) {
        try {
          final svgCode = utf8.decode(base64Decode(_logoBase64!.split(',')[1]));
          return SvgPicture.string(
            svgCode,
            height: _logoHeight * 3.0,
            fit: BoxFit.contain,
          );
        } catch (_) {}
      }
      return Image.memory(
        base64Decode(_logoBase64!.split(',').length > 1 ? _logoBase64!.split(',')[1] : _logoBase64!),
        height: _logoHeight * 3.0,
        fit: BoxFit.contain,
        errorBuilder: (_, _, _) => const Icon(Icons.image, size: 24, color: Colors.grey),
      );
    }
    return const Icon(Icons.shopping_bag_outlined, color: Color(0xFF7E0542), size: 24);
  }

  TextAlign _mapStringToTextAlign(String align) {
    if (align == 'left') return TextAlign.left;
    if (align == 'right') return TextAlign.right;
    return TextAlign.center;
  }

  Alignment _mapStringToAlignment(String align) {
    if (align == 'left') return Alignment.centerLeft;
    if (align == 'right') return Alignment.centerRight;
    return Alignment.center;
  }

  MainAxisAlignment _mapStringToMainAxisAlignment(String align) {
    if (align == 'left') return MainAxisAlignment.start;
    if (align == 'right') return MainAxisAlignment.end;
    return MainAxisAlignment.center;
  }

  // --- Modular Preview Widget Generator ---
  Widget _buildLabelPreviewCard({
    required String fullItemName,
    required String formattedPrice,
    required String barcodeVal,
    required String previewSvg,
    required Color currentColor,
  }) {
    final List<Widget> renderedRows = [];

    for (final fieldKey in _fieldOrder) {
      switch (fieldKey) {
        case 'header':
          if (_showStoreName || _showLogo || _showModelNumber) {
            if (_headerLayout == 'stacked') {
              renderedRows.add(
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_showStoreName || _showLogo)
                      Row(
                        mainAxisAlignment: _mapStringToMainAxisAlignment(_storeNameAlign),
                        children: [
                          if (_showStoreName)
                            Text(
                              _storeName,
                              style: TextStyle(
                                color: currentColor,
                                fontSize: _storeNameFontSize * 1.15,
                                fontWeight: _storeNameBold ? FontWeight.w900 : FontWeight.bold,
                                fontFamily: _fontFamily,
                                letterSpacing: 0.5,
                              ),
                            ),
                          const SizedBox(width: 4),
                          if (_showLogo) _buildLogoWidget(),
                        ],
                      ),
                    if (_showModelNumber)
                      Align(
                        alignment: _mapStringToAlignment(_modelAlign),
                        child: Text(
                          '${_modelPrefix.isNotEmpty ? '$_modelPrefix ' : ''}$_modelNumber',
                          style: TextStyle(
                            color: Colors.black,
                            fontSize: _modelFontSize * 1.1,
                            fontWeight: _modelBold ? FontWeight.bold : FontWeight.normal,
                            fontFamily: _fontFamily,
                          ),
                        ),
                      ),
                  ],
                ),
              );
            } else {
              renderedRows.add(
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // RIGHT in RTL: Store Name + Logo
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: _mapStringToMainAxisAlignment(_storeNameAlign),
                      children: [
                        if (_showStoreName)
                          Text(
                            _storeName,
                            style: TextStyle(
                              color: currentColor,
                              fontSize: _storeNameFontSize * 1.2,
                              fontWeight: _storeNameBold ? FontWeight.w900 : FontWeight.bold,
                              fontFamily: _fontFamily,
                              letterSpacing: 0.5,
                            ),
                          ),
                        const SizedBox(width: 4),
                        if (_showLogo) _buildLogoWidget(),
                      ],
                    ),

                    // LEFT in RTL: Model Code
                    if (_showModelNumber)
                      Align(
                        alignment: _mapStringToAlignment(_modelAlign),
                        child: Text(
                          '${_modelPrefix.isNotEmpty ? '$_modelPrefix ' : ''}$_modelNumber',
                          style: TextStyle(
                            color: Colors.black,
                            fontSize: _modelFontSize * 1.15,
                            fontWeight: _modelBold ? FontWeight.bold : FontWeight.normal,
                            fontFamily: _fontFamily,
                          ),
                        ),
                      )
                    else
                      const SizedBox.shrink(),
                  ],
                ),
              );
            }
          }
          break;

        case 'itemName':
          if (_showItemName) {
            renderedRows.add(
              Align(
                alignment: _mapStringToAlignment(_itemNameAlign),
                child: Text(
                  fullItemName,
                  textAlign: _mapStringToTextAlign(_itemNameAlign),
                  textDirection: _itemNameAlign == 'left' ? TextDirection.ltr : TextDirection.rtl,
                  maxLines: _itemNameWrap ? 2 : 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.black,
                    fontSize: _itemNameFontSize * 1.15,
                    fontWeight: FontWeight.bold,
                    fontFamily: _fontFamily,
                    height: 1.1,
                  ),
                ),
              ),
            );
          }
          break;

        case 'price':
          if (_showPrice) {
            renderedRows.add(
              Align(
                alignment: _mapStringToAlignment(_priceAlign),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: _mapStringToMainAxisAlignment(_priceAlign),
                  children: [
                    Text(
                      formattedPrice,
                      textAlign: _mapStringToTextAlign(_priceAlign),
                      style: TextStyle(
                        color: Colors.black,
                        fontSize: _priceFontSize * 1.15,
                        fontWeight: FontWeight.w900,
                        fontFamily: _fontFamily,
                        letterSpacing: 0.5,
                      ),
                    ),
                    if (_showVatNote) ...[
                      const SizedBox(width: 4),
                      Text(
                        _vatNoteText,
                        style: const TextStyle(color: Colors.black54, fontSize: 8.5, fontWeight: FontWeight.normal),
                      ),
                    ],
                  ],
                ),
              ),
            );
          }
          break;

        case 'extraInfo':
          if (_showExtraInfo && _extraInfoText.isNotEmpty) {
            renderedRows.add(
              Align(
                alignment: _mapStringToAlignment(_extraInfoAlign),
                child: Text(
                  _extraInfoText,
                  textAlign: _mapStringToTextAlign(_extraInfoAlign),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.black87,
                    fontSize: _extraInfoFontSize * 1.1,
                    fontWeight: FontWeight.bold,
                    fontFamily: _fontFamily,
                  ),
                ),
              ),
            );
          }
          break;

        case 'barcode':
          if (_showBarcodeGraphic || _showBarcodeText) {
            renderedRows.add(
              Align(
                alignment: _mapStringToAlignment(_barcodeAlign),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_showBarcodeGraphic && previewSvg.isNotEmpty)
                      SizedBox(
                        height: _barcodeHeight * 2.1,
                        width: _barcodeType == 'QR Code' ? _barcodeHeight * 2.1 : double.infinity,
                        child: SvgPicture.string(
                          previewSvg,
                          fit: BoxFit.contain,
                          alignment: _mapStringToAlignment(_barcodeAlign),
                        ),
                      ),
                    if (_showBarcodeText)
                      Padding(
                        padding: const EdgeInsets.only(top: 2.0),
                        child: Text(
                          barcodeVal,
                          style: const TextStyle(
                            color: Colors.black,
                            fontSize: 10.5,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'monospace',
                            letterSpacing: 2,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            );
          }
          break;
      }
    }

    return Container(
      width: _paperWidth * 6.5,
      height: _paperHeight * 6.5,
      padding: EdgeInsets.all(_labelPaddingMm * 3.8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: const Color(0xFF9E9E9E), width: 1.2),
        boxShadow: const [
          BoxShadow(
            color: Colors.black87,
            blurRadius: 24,
            spreadRadius: 6,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: renderedRows,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final apiService = Provider.of<ApiService>(context);
    final allItems = apiService.items;
    final groups = apiService.groups;

    final filteredItems = allItems.where((item) {
      final matchesGroup = _selectedGroupId == 0 || item.groupId == _selectedGroupId;
      final matchesSearch = _searchQuery.isEmpty ||
          item.itemName.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          item.barcode.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          item.itemId.toString().contains(_searchQuery);
      return matchesGroup && matchesSearch;
    }).toList();

    final fullItemName = _buildFullItemName();
    final priceVal = _getActivePrice();
    final barcodeVal = _getActiveBarcode();
    final formattedPrice = _buildFormattedPrice(priceVal);

    final previewSvg = _generateBarcodeSvg(barcodeVal);
    final currentColor = Color(int.parse(_storeNameColorHex.replaceFirst('#', '0xFF')));

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      body: Directionality(
        textDirection: TextDirection.rtl,
        child: Row(
          children: [
            // ==========================================
            // --- LEFT PANEL: Settings & Studio Controls (48%) ---
            // ==========================================
            Expanded(
              flex: 5,
              child: Container(
                color: const Color(0xFF181B22),
                child: Column(
                  children: [
                    // Header Bar
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Color(0xFF1F2937), Color(0xFF111827)],
                        ),
                        border: Border(bottom: BorderSide(color: Colors.white12)),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: const Color(0xFFE11D48).withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: const Color(0xFFE11D48).withValues(alpha: 0.3)),
                            ),
                            child: const Icon(Icons.qr_code_scanner_rounded, color: Color(0xFFF43F5E), size: 22),
                          ),
                          const SizedBox(width: 12),
                          const Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'استوديو تصميم وطباعة ملصقات الباركود',
                                style: TextStyle(
                                  fontFamily: 'Cairo',
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                  color: Colors.white,
                                ),
                              ),
                              Text(
                                'تحكم متقدم بالمحاذاة، الترتيب الرأسي، والطباعة المباشرة',
                                style: TextStyle(
                                  fontFamily: 'Cairo',
                                  fontSize: 11,
                                  color: Colors.white60,
                                ),
                              ),
                            ],
                          ),
                          const Spacer(),
                          // Refresh printers button
                          Tooltip(
                            message: 'تحديث قائمة الطابعات الحرارية',
                            child: IconButton(
                              icon: _isLoadingPrinters
                                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.cyanAccent))
                                  : const Icon(Icons.sync_rounded, color: Colors.cyanAccent, size: 22),
                              onPressed: () => _fetchPrinters(showToast: true),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Studio Tab Navigation Bar
                    Container(
                      color: const Color(0xFF1E232D),
                      child: TabBar(
                        controller: _tabController,
                        indicatorColor: const Color(0xFFE11D48),
                        indicatorWeight: 3,
                        labelColor: Colors.white,
                        unselectedLabelColor: Colors.white54,
                        labelStyle: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 12),
                        tabs: const [
                          Tab(icon: Icon(Icons.tune_rounded, size: 17), text: 'العناصر والمحاذاة والترتيب'),
                          Tab(icon: Icon(Icons.auto_awesome_mosaic_rounded, size: 17), text: 'القوالب والأبعاد'),
                          Tab(icon: Icon(Icons.inventory_2_rounded, size: 17), text: 'البحث والطباعة وتعديل السعر'),
                          Tab(icon: Icon(Icons.dynamic_feed_rounded, size: 17), text: 'الطباعة المجمعة'),
                        ],
                      ),
                    ),

                    // Scrollable Tab Content
                    Expanded(
                      child: TabBarView(
                        controller: _tabController,
                        children: [
                          // -------------------------------------------------------------
                          // TAB 1: Elements, Alignments, Ordering (العناصر والمحاذاة والترتيب)
                          // -------------------------------------------------------------
                          ListView(
                            padding: const EdgeInsets.all(16),
                            children: [
                              // Quick Order Notice & Reset Button
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                margin: const EdgeInsets.only(bottom: 12),
                                decoration: BoxDecoration(
                                  color: Colors.blueAccent.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: Colors.blueAccent.withValues(alpha: 0.3)),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(Icons.swap_vert_rounded, color: Colors.blueAccent, size: 20),
                                    const SizedBox(width: 8),
                                    const Expanded(
                                      child: Text(
                                        'استخدم أزرار (⬆️ فوق / ⬇️ تحت) لتغيير الترتيب الرأسي للحقول في الملصق',
                                        style: TextStyle(color: Colors.white70, fontFamily: 'Cairo', fontSize: 11),
                                      ),
                                    ),
                                    TextButton.icon(
                                      icon: const Icon(Icons.restore_rounded, size: 16, color: Colors.amberAccent),
                                      label: const Text('إعادة الترتيب', style: TextStyle(color: Colors.amberAccent, fontFamily: 'Cairo', fontSize: 11)),
                                      onPressed: _resetFieldOrder,
                                    ),
                                  ],
                                ),
                              ),

                              // Render element cards in dynamic vertical order
                              ..._fieldOrder.asMap().entries.map((entry) {
                                final index = entry.key;
                                final fieldKey = entry.value;
                                return _buildDynamicFieldCard(
                                  fieldKey: fieldKey,
                                  index: index,
                                  currentColor: currentColor,
                                );
                              }),
                            ],
                          ),

                          // -------------------------------------------------------------
                          // TAB 2: Presets, Dimensions & Fonts (القوالب والخطوط والأبعاد)
                          // -------------------------------------------------------------
                          ListView(
                            padding: const EdgeInsets.all(16),
                            children: [
                              // 1. One-Click Quick Presets
                              const Row(
                                children: [
                                  Icon(Icons.auto_awesome_rounded, color: Colors.amberAccent, size: 20),
                                  SizedBox(width: 8),
                                  Text(
                                    'القوالب الجاهزة بنقرة واحدة (One-Click Presets):',
                                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontFamily: 'Cairo', fontSize: 13),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  _buildPresetButton(
                                    title: 'قالب الأميرة الملكي (50×30 مم)',
                                    subtitle: 'الشعار والاسم والموديل والسعر',
                                    color: const Color(0xFF7E0542),
                                    onTap: () => _applyPreset('princess_royal'),
                                  ),
                                  _buildPresetButton(
                                    title: 'قالب الملابس والأحذية (50×25 مم)',
                                    subtitle: 'مع المقاس واللون والموديل',
                                    color: const Color(0xFF1E3A8A),
                                    onTap: () => _applyPreset('apparel_shoes'),
                                  ),
                                  _buildPresetButton(
                                    title: 'قالب السوبرماركت والتجزئة (EAN13)',
                                    subtitle: 'باركود EAN بارز وسعر كبير',
                                    color: const Color(0xFF065F46),
                                    onTap: () => _applyPreset('supermarket_ean'),
                                  ),
                                  _buildPresetButton(
                                    title: 'قالب المجوهرات المصغر (40×22 مم)',
                                    subtitle: 'ملصق فائق الصغر للإكسسوارات',
                                    color: const Color(0xFFB45309),
                                    onTap: () => _applyPreset('mini_jewelry'),
                                  ),
                                  _buildPresetButton(
                                    title: 'قالب رمز الاستجابة السريعة (QR Code)',
                                    subtitle: 'باركود 2D ذكي مع تفاصيل الصنف',
                                    color: const Color(0xFF4C1D95),
                                    onTap: () => _applyPreset('modern_qr'),
                                  ),
                                  _buildPresetButton(
                                    title: 'قالب المستودعات والكراتين (60×40 مم)',
                                    subtitle: 'ملصق عريض يشمل كافة التفاصيل والبيانات',
                                    color: const Color(0xFF0F766E),
                                    onTap: () => _applyPreset('warehouse_wide'),
                                  ),
                                ],
                              ),

                              const SizedBox(height: 20),
                              const Divider(color: Colors.white12),
                              const SizedBox(height: 10),

                              // 2. Paper Dimensions
                              const Text('أبعاد وقالب ورقة الملصق الحراري (Dimensions):', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontFamily: 'Cairo', fontSize: 13)),
                              const SizedBox(height: 8),
                              DropdownButtonFormField<String>(
                                initialValue: _selectedSizeTemplate,
                                dropdownColor: const Color(0xFF0F172A),
                                style: const TextStyle(color: Colors.white, fontFamily: 'Cairo', fontSize: 13),
                                decoration: InputDecoration(
                                  fillColor: const Color(0xFF0F172A),
                                  filled: true,
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                ),
                                items: _sizeTemplates.map((t) => DropdownMenuItem<String>(value: t['id'], child: Text(t['name']))).toList(),
                                onChanged: (val) {
                                  if (val != null) {
                                    setState(() {
                                      _selectedSizeTemplate = val;
                                      if (val == '50x30') {
                                        _paperWidth = 50.0; _paperHeight = 30.0;
                                      } else if (val == '50x25') {
                                        _paperWidth = 50.0; _paperHeight = 25.0;
                                      } else if (val == '40x22') {
                                        _paperWidth = 40.0; _paperHeight = 22.0;
                                      } else if (val == '60x40') {
                                        _paperWidth = 60.0; _paperHeight = 40.0;
                                      } else if (val == '38x28') {
                                        _paperWidth = 38.0; _paperHeight = 28.0;
                                      } else if (val == '70x50') {
                                        _paperWidth = 70.0; _paperHeight = 50.0;
                                      }
                                      _widthController.text = _paperWidth.toStringAsFixed(0);
                                      _heightController.text = _paperHeight.toStringAsFixed(0);
                                    });
                                    _saveSetting('barcode_paper_width', _paperWidth);
                                    _saveSetting('barcode_paper_height', _paperHeight);
                                  }
                                },
                              ),
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  Expanded(
                                    child: TextFormField(
                                      controller: _widthController,
                                      keyboardType: TextInputType.number,
                                      style: const TextStyle(color: Colors.white, fontSize: 12),
                                      decoration: InputDecoration(
                                        labelText: 'العرض (مم)',
                                        labelStyle: const TextStyle(color: Colors.white70, fontFamily: 'Cairo', fontSize: 11),
                                        fillColor: const Color(0xFF0F172A),
                                        filled: true,
                                        isDense: true,
                                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                      ),
                                      onChanged: (val) {
                                        final parsed = double.tryParse(val) ?? 50.0;
                                        setState(() => _paperWidth = parsed);
                                        _saveSetting('barcode_paper_width', parsed);
                                      },
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: TextFormField(
                                      controller: _heightController,
                                      keyboardType: TextInputType.number,
                                      style: const TextStyle(color: Colors.white, fontSize: 12),
                                      decoration: InputDecoration(
                                        labelText: 'الارتفاع (مم)',
                                        labelStyle: const TextStyle(color: Colors.white70, fontFamily: 'Cairo', fontSize: 11),
                                        fillColor: const Color(0xFF0F172A),
                                        filled: true,
                                        isDense: true,
                                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                      ),
                                      onChanged: (val) {
                                        final parsed = double.tryParse(val) ?? 30.0;
                                        setState(() => _paperHeight = parsed);
                                        _saveSetting('barcode_paper_height', parsed);
                                      },
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: TextFormField(
                                      controller: _paddingController,
                                      keyboardType: TextInputType.number,
                                      style: const TextStyle(color: Colors.white, fontSize: 12),
                                      decoration: InputDecoration(
                                        labelText: 'الهامش الداخلي (مم)',
                                        labelStyle: const TextStyle(color: Colors.white70, fontFamily: 'Cairo', fontSize: 11),
                                        fillColor: const Color(0xFF0F172A),
                                        filled: true,
                                        isDense: true,
                                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                      ),
                                      onChanged: (val) {
                                        final parsed = double.tryParse(val) ?? 1.2;
                                        setState(() => _labelPaddingMm = parsed);
                                        _saveSetting('barcode_label_padding', parsed);
                                      },
                                    ),
                                  ),
                                ],
                              ),

                              const SizedBox(height: 20),
                              const Divider(color: Colors.white12),
                              const SizedBox(height: 10),

                              // 3. Typography & Font Family
                              const Text('نوع الخط العام (Font Family):', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontFamily: 'Cairo', fontSize: 13)),
                              const SizedBox(height: 8),
                              DropdownButtonFormField<String>(
                                initialValue: _fontFamily,
                                dropdownColor: const Color(0xFF0F172A),
                                style: const TextStyle(color: Colors.white, fontFamily: 'Cairo', fontSize: 13),
                                decoration: InputDecoration(
                                  fillColor: const Color(0xFF0F172A),
                                  filled: true,
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                ),
                                items: _fontFamilies.map((f) => DropdownMenuItem(value: f, child: Text(f, style: TextStyle(fontFamily: f)))).toList(),
                                onChanged: (val) {
                                  if (val != null) {
                                    setState(() => _fontFamily = val);
                                    _saveSetting('barcode_font_family', val);
                                  }
                                },
                              ),

                              const SizedBox(height: 16),

                              // 4. Sliders for Font Sizes & Element Heights
                              _buildSliderRow(
                                title: 'حجم خط اسم المحل (Store Name Font Size)',
                                value: _storeNameFontSize,
                                min: 7.0,
                                max: 22.0,
                                onChanged: (val) {
                                  setState(() => _storeNameFontSize = val);
                                  _saveSetting('barcode_store_font_size', val);
                                },
                              ),
                              _buildSliderRow(
                                title: 'حجم خط رمز الموديل (Model Font Size)',
                                value: _modelFontSize,
                                min: 6.0,
                                max: 20.0,
                                onChanged: (val) {
                                  setState(() => _modelFontSize = val);
                                  _saveSetting('barcode_model_font_size', val);
                                },
                              ),
                              _buildSliderRow(
                                title: 'حجم خط بيان الصنف (Item Name Font Size)',
                                value: _itemNameFontSize,
                                min: 6.0,
                                max: 20.0,
                                onChanged: (val) {
                                  setState(() => _itemNameFontSize = val);
                                  _saveSetting('barcode_item_font_size', val);
                                },
                              ),
                              _buildSliderRow(
                                title: 'حجم خط السعر (Price Font Size)',
                                value: _priceFontSize,
                                min: 8.0,
                                max: 28.0,
                                onChanged: (val) {
                                  setState(() => _priceFontSize = val);
                                  _saveSetting('barcode_price_font_size', val);
                                },
                              ),
                              _buildSliderRow(
                                title: 'ارتفاع رسم الباركود (Barcode Height mm)',
                                value: _barcodeHeight,
                                min: 5.0,
                                max: 26.0,
                                unit: 'مم',
                                onChanged: (val) {
                                  setState(() => _barcodeHeight = val);
                                  _saveSetting('barcode_graphic_height', val);
                                },
                              ),
                              _buildSliderRow(
                                title: 'ارتفاع الشعار (Logo Height mm)',
                                value: _logoHeight,
                                min: 4.0,
                                max: 18.0,
                                unit: 'مم',
                                onChanged: (val) {
                                  setState(() => _logoHeight = val);
                                  _saveSetting('barcode_logo_height', val);
                                },
                              ),
                              if (_showExtraInfo)
                                _buildSliderRow(
                                  title: 'حجم خط النص الإضافي (Extra Info Font)',
                                  value: _extraInfoFontSize,
                                  min: 6.0,
                                  max: 16.0,
                                  onChanged: (val) {
                                    setState(() => _extraInfoFontSize = val);
                                    _saveSetting('barcode_extra_info_font_size', val);
                                  },
                                ),
                            ],
                          ),

                          // -------------------------------------------------------------
                          // TAB 3: Unified Search, Item Selection, Custom Price & Printing
                          // -------------------------------------------------------------
                          ListView(
                            padding: const EdgeInsets.all(16),
                            children: [
                              // Toggle Manual Entry vs DB Search
                              Container(
                                padding: const EdgeInsets.all(4),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF0F172A),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: Colors.white12),
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: InkWell(
                                        onTap: () => setState(() => _manualEntryMode = false),
                                        borderRadius: BorderRadius.circular(8),
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(vertical: 8),
                                          decoration: BoxDecoration(
                                            color: !_manualEntryMode ? Colors.blueAccent : Colors.transparent,
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                          child: Center(
                                            child: Text(
                                              'البحث في دليل الأصناف',
                                              style: TextStyle(
                                                color: !_manualEntryMode ? Colors.white : Colors.white60,
                                                fontFamily: 'Cairo',
                                                fontWeight: FontWeight.bold,
                                                fontSize: 12,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                    Expanded(
                                      child: InkWell(
                                        onTap: () => setState(() => _manualEntryMode = true),
                                        borderRadius: BorderRadius.circular(8),
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(vertical: 8),
                                          decoration: BoxDecoration(
                                            color: _manualEntryMode ? Colors.blueAccent : Colors.transparent,
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                          child: Center(
                                            child: Text(
                                              'إدخال يدوي حر مخصص',
                                              style: TextStyle(
                                                color: _manualEntryMode ? Colors.white : Colors.white60,
                                                fontFamily: 'Cairo',
                                                fontWeight: FontWeight.bold,
                                                fontSize: 12,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                              const SizedBox(height: 14),

                              if (!_manualEntryMode) ...[
                                // Group selector & search bar
                                Row(
                                  children: [
                                    Expanded(
                                      flex: 2,
                                      child: DropdownButtonFormField<int>(
                                        initialValue: _selectedGroupId,
                                        dropdownColor: const Color(0xFF0F172A),
                                        style: const TextStyle(color: Colors.white, fontFamily: 'Cairo', fontSize: 12),
                                        decoration: InputDecoration(
                                          labelText: 'المجموعة',
                                          labelStyle: const TextStyle(color: Colors.white70, fontFamily: 'Cairo', fontSize: 11),
                                          fillColor: const Color(0xFF0F172A),
                                          filled: true,
                                          isDense: true,
                                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                        ),
                                        items: [
                                          const DropdownMenuItem(value: 0, child: Text('جميع المجموعات')),
                                          ...groups.map((g) => DropdownMenuItem(value: g.id, child: Text(g.name))),
                                        ],
                                        onChanged: (val) => setState(() => _selectedGroupId = val ?? 0),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      flex: 3,
                                      child: TextFormField(
                                        style: const TextStyle(color: Colors.white, fontSize: 12, fontFamily: 'Cairo'),
                                        decoration: InputDecoration(
                                          hintText: 'ابحث بالاسم أو الباركود...',
                                          hintStyle: const TextStyle(color: Colors.white38, fontSize: 11, fontFamily: 'Cairo'),
                                          prefixIcon: const Icon(Icons.search, color: Colors.blueAccent, size: 20),
                                          fillColor: const Color(0xFF0F172A),
                                          filled: true,
                                          isDense: true,
                                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                        ),
                                        onChanged: (val) => setState(() => _searchQuery = val),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Container(
                                  height: 120,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF0F172A),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: Colors.white12),
                                  ),
                                  child: filteredItems.isEmpty
                                      ? const Center(child: Text('لا توجد أصناف مطابقة للبحث', style: TextStyle(color: Colors.white38, fontFamily: 'Cairo', fontSize: 12)))
                                      : ListView.separated(
                                          separatorBuilder: (_, _) => const Divider(color: Colors.white10, height: 1),
                                          itemCount: filteredItems.length,
                                          itemBuilder: (context, idx) {
                                            final itm = filteredItems[idx];
                                            final isSelected = _selectedItem?.itemId == itm.itemId;
                                            return ListTile(
                                              dense: true,
                                              selected: isSelected,
                                              selectedTileColor: Colors.blueAccent.withValues(alpha: 0.2),
                                              title: Text(
                                                itm.itemName,
                                                style: TextStyle(
                                                  color: isSelected ? Colors.cyanAccent : Colors.white,
                                                  fontFamily: 'Cairo',
                                                  fontSize: 12,
                                                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                                ),
                                              ),
                                              subtitle: Text('باركود: ${itm.barcode}', style: const TextStyle(color: Colors.white54, fontSize: 11)),
                                              trailing: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Text('${itm.salesPrice} $_currencySymbol', style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold, fontSize: 12)),
                                                  const SizedBox(width: 6),
                                                  IconButton(
                                                    icon: const Icon(Icons.add_shopping_cart_rounded, color: Colors.amberAccent, size: 18),
                                                    tooltip: 'إضافة لقائمة الطباعة المجمعة',
                                                    onPressed: () {
                                                      setState(() {
                                                        _batchQueue.add(_BatchPrintItem(item: itm, count: 1, price: _getActivePrice()));
                                                      });
                                                      ScaffoldMessenger.of(context).showSnackBar(
                                                        SnackBar(
                                                          content: Text('تمت إضافة ${itm.itemName} لقائمة الطباعة المجمعة 📥', style: const TextStyle(fontFamily: 'Cairo')),
                                                          backgroundColor: Colors.amber[800],
                                                          duration: const Duration(milliseconds: 1200),
                                                        ),
                                                      );
                                                    },
                                                  ),
                                                ],
                                              ),
                                              onTap: () {
                                                setState(() {
                                                  _selectedItem = itm;
                                                  _customPriceOverride = itm.salesPrice;
                                                  _customPriceController.text = itm.salesPrice.toStringAsFixed(2);
                                                  if (itm.barcode.isNotEmpty) {
                                                    _modelNumber = itm.barcode;
                                                    _modelController.text = _modelNumber;
                                                  }
                                                });
                                              },
                                            );
                                          },
                                        ),
                                ),

                                const SizedBox(height: 12),

                                // Selected Item Action & Price Modification Card
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: [const Color(0xFF1E3A8A).withValues(alpha: 0.3), const Color(0xFF0F172A)],
                                      begin: Alignment.topRight,
                                      end: Alignment.bottomLeft,
                                    ),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(color: Colors.blueAccent.withValues(alpha: 0.4)),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          const Icon(Icons.check_circle_outline_rounded, color: Colors.cyanAccent, size: 18),
                                          const SizedBox(width: 6),
                                          Expanded(
                                            child: Text(
                                              _selectedItem != null ? 'الصنف المحدد: ${_selectedItem!.itemName}' : 'الصنف الافتراضي: مغلق لماع جنز',
                                              style: const TextStyle(color: Colors.cyanAccent, fontWeight: FontWeight.bold, fontFamily: 'Cairo', fontSize: 12),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                          if (_selectedItem != null)
                                            Text(
                                              'السعر الأصلي: ${_selectedItem!.salesPrice} $_currencySymbol',
                                              style: const TextStyle(color: Colors.white54, fontFamily: 'Cairo', fontSize: 10),
                                            ),
                                        ],
                                      ),
                                      const SizedBox(height: 10),
                                      Row(
                                        children: [
                                          // Editable Custom Price for Label
                                          Expanded(
                                            flex: 3,
                                            child: TextFormField(
                                              controller: _customPriceController,
                                              keyboardType: TextInputType.number,
                                              style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold, fontSize: 13),
                                              decoration: InputDecoration(
                                                labelText: 'السعر المطبوع على الملصق ($_currencySymbol)',
                                                labelStyle: const TextStyle(color: Colors.white70, fontFamily: 'Cairo', fontSize: 11),
                                                suffixIcon: _selectedItem != null && _customPriceOverride != _selectedItem!.salesPrice
                                                    ? IconButton(
                                                        icon: const Icon(Icons.restore_rounded, color: Colors.amberAccent, size: 18),
                                                        tooltip: 'استعادة السعر الأصلي في قاعدة البيانات',
                                                        onPressed: () {
                                                          setState(() {
                                                            _customPriceOverride = _selectedItem!.salesPrice;
                                                            _customPriceController.text = _selectedItem!.salesPrice.toStringAsFixed(2);
                                                          });
                                                        },
                                                      )
                                                    : null,
                                                fillColor: const Color(0xFF0F172A),
                                                filled: true,
                                                isDense: true,
                                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                              ),
                                              onChanged: (val) {
                                                final parsed = double.tryParse(val);
                                                setState(() {
                                                  _customPriceOverride = parsed ?? (_selectedItem?.salesPrice ?? 48.78);
                                                });
                                              },
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          // Editable Model/Barcode text on label
                                          Expanded(
                                            flex: 2,
                                            child: TextFormField(
                                              controller: _modelController,
                                              style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                                              decoration: InputDecoration(
                                                labelText: 'كود / باركود الملصق',
                                                labelStyle: const TextStyle(color: Colors.white70, fontFamily: 'Cairo', fontSize: 10),
                                                fillColor: const Color(0xFF0F172A),
                                                filled: true,
                                                isDense: true,
                                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                              ),
                                              onChanged: (val) {
                                                setState(() {
                                                  _modelNumber = val;
                                                });
                                                _saveSetting('barcode_model_number', val);
                                              },
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ] else ...[
                                // Manual text fields
                                TextFormField(
                                  controller: _manualItemNameController,
                                  style: const TextStyle(color: Colors.white, fontFamily: 'Cairo', fontSize: 13),
                                  decoration: InputDecoration(
                                    labelText: 'اسم وبيان الصنف اليدوي المطبوع',
                                    labelStyle: const TextStyle(color: Colors.white70, fontFamily: 'Cairo', fontSize: 11),
                                    fillColor: const Color(0xFF0F172A),
                                    filled: true,
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                  ),
                                  onChanged: (_) => setState(() {}),
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    Expanded(
                                      child: TextFormField(
                                        controller: _manualBarcodeController,
                                        style: const TextStyle(color: Colors.white, fontSize: 13),
                                        decoration: InputDecoration(
                                          labelText: 'رمز الباركود / الموديل',
                                          labelStyle: const TextStyle(color: Colors.white70, fontFamily: 'Cairo', fontSize: 11),
                                          fillColor: const Color(0xFF0F172A),
                                          filled: true,
                                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                        ),
                                        onChanged: (val) {
                                          setState(() {
                                            _modelNumber = val;
                                            _modelController.text = val;
                                          });
                                        },
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: TextFormField(
                                        controller: _manualPriceController,
                                        keyboardType: TextInputType.number,
                                        style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold, fontSize: 13),
                                        decoration: InputDecoration(
                                          labelText: 'السعر المطبوع ($_currencySymbol)',
                                          labelStyle: const TextStyle(color: Colors.white70, fontFamily: 'Cairo', fontSize: 11),
                                          fillColor: const Color(0xFF0F172A),
                                          filled: true,
                                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                        ),
                                        onChanged: (_) => setState(() {}),
                                      ),
                                    ),
                                  ],
                                ),
                              ],

                              const SizedBox(height: 14),
                              const Divider(color: Colors.white12),
                              const SizedBox(height: 8),

                              // Printer Selector
                              Row(
                                children: [
                                  const Icon(Icons.print_outlined, color: Colors.blueAccent, size: 18),
                                  const SizedBox(width: 6),
                                  const Text('طابعة الباركود الحرارية:', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontFamily: 'Cairo', fontSize: 12)),
                                  const Spacer(),
                                  TextButton.icon(
                                    icon: const Icon(Icons.sync_rounded, size: 14, color: Colors.cyanAccent),
                                    label: const Text('تحديث الطابعات', style: TextStyle(color: Colors.cyanAccent, fontFamily: 'Cairo', fontSize: 10)),
                                    onPressed: () => _fetchPrinters(showToast: true),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              DropdownButtonFormField<String>(
                                initialValue: _printers.contains(_printerName) ? _printerName : (_printers.isNotEmpty ? _printers.first : null),
                                dropdownColor: const Color(0xFF0F172A),
                                style: const TextStyle(color: Colors.white, fontFamily: 'Cairo', fontSize: 12),
                                decoration: InputDecoration(
                                  fillColor: const Color(0xFF0F172A),
                                  filled: true,
                                  isDense: true,
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                  hintText: _isLoadingPrinters ? 'جاري جلب الطابعات...' : 'اختر طابعة الباركود',
                                  hintStyle: const TextStyle(color: Colors.white38, fontSize: 12, fontFamily: 'Cairo'),
                                ),
                                items: _printers.map((p) => DropdownMenuItem(value: p, child: Text(p, overflow: TextOverflow.ellipsis))).toList(),
                                onChanged: (val) {
                                  if (val != null) {
                                    setState(() {
                                      _printerName = val;
                                      _printerController.text = val;
                                    });
                                    _saveSetting('barcode_printer_name', val);
                                  }
                                },
                              ),

                              const SizedBox(height: 12),

                              // Enhanced Print Count Controller (0 to 10,000)
                              _buildEnhancedCountController(),

                              const SizedBox(height: 16),

                              // Combined Quick Print Actions
                              ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF2563EB),
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(vertical: 14),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                  elevation: 4,
                                ),
                                icon: const Icon(Icons.print_rounded),
                                label: Text(
                                  'طباعة فورية عبر المتصفح ($_printCount ملصق بسعر ${_getActivePrice().toStringAsFixed(2)} $_currencySymbol)',
                                  style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 13),
                                ),
                                onPressed: () => _printLabelsBrowser(isBatch: false),
                              ),
                              const SizedBox(height: 8),
                              OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.cyanAccent,
                                  side: const BorderSide(color: Colors.cyanAccent),
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                ),
                                icon: const Icon(Icons.flash_on_rounded),
                                label: Text('طباعة صامتة ومباشرة لطابعة ($_printerName)', style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 12)),
                                onPressed: () => _printLabelsDirect(apiService.baseUrl, isBatch: false),
                              ),
                            ],
                          ),

                          // -------------------------------------------------------------
                          // TAB 4: Batch Print Queue (الطباعة المجمعة لعدة أصناف)
                          // -------------------------------------------------------------
                          Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    const Icon(Icons.dynamic_feed_rounded, color: Colors.amberAccent, size: 22),
                                    const SizedBox(width: 8),
                                    const Text('قائمة انتظار الطباعة المجمعة (Batch Queue):', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontFamily: 'Cairo', fontSize: 13)),
                                    const Spacer(),
                                    if (_batchQueue.isNotEmpty)
                                      TextButton.icon(
                                        icon: const Icon(Icons.delete_sweep_rounded, color: Colors.redAccent, size: 18),
                                        label: const Text('تفريغ القائمة', style: TextStyle(color: Colors.redAccent, fontFamily: 'Cairo', fontSize: 11)),
                                        onPressed: () => setState(() => _batchQueue.clear()),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Expanded(
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF0F172A),
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(color: Colors.white12),
                                    ),
                                    child: _batchQueue.isEmpty
                                        ? Center(
                                            child: Column(
                                              mainAxisAlignment: MainAxisAlignment.center,
                                              children: [
                                                Icon(Icons.layers_clear_rounded, size: 48, color: Colors.white.withValues(alpha: 0.2)),
                                                const SizedBox(height: 10),
                                                const Text('قائمة الطباعة المجمعة فارغة', style: TextStyle(color: Colors.white38, fontFamily: 'Cairo', fontSize: 13)),
                                                const SizedBox(height: 4),
                                                const Text('انتقل لتبويب "البحث والطباعة وتعديل السعر" واضغط زر 🛒 لإضافة أصناف', style: TextStyle(color: Colors.white24, fontFamily: 'Cairo', fontSize: 11)),
                                              ],
                                            ),
                                          )
                                        : ListView.separated(
                                            itemCount: _batchQueue.length,
                                            separatorBuilder: (_, _) => const Divider(color: Colors.white10, height: 1),
                                            itemBuilder: (context, idx) {
                                              final b = _batchQueue[idx];
                                              return ListTile(
                                                dense: true,
                                                title: Text(b.item.itemName, style: const TextStyle(color: Colors.white, fontFamily: 'Cairo', fontSize: 12, fontWeight: FontWeight.bold)),
                                                subtitle: Text('باركود: ${b.item.barcode} | السعر: ${b.customPrice.toStringAsFixed(2)} $_currencySymbol', style: const TextStyle(color: Colors.white54, fontSize: 11)),
                                                trailing: Row(
                                                  mainAxisSize: MainAxisSize.min,
                                                  children: [
                                                    IconButton(
                                                      icon: const Icon(Icons.remove_circle_outline, color: Colors.blueAccent, size: 20),
                                                      onPressed: () {
                                                        if (b.count > 0) {
                                                          setState(() => b.count--);
                                                        }
                                                      },
                                                    ),
                                                    InkWell(
                                                      onTap: () => _showBatchItemCountDialog(b),
                                                      borderRadius: BorderRadius.circular(4),
                                                      child: Container(
                                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                        decoration: BoxDecoration(
                                                          color: const Color(0xFF1E293B),
                                                          borderRadius: BorderRadius.circular(4),
                                                          border: Border.all(color: Colors.cyanAccent.withValues(alpha: 0.5)),
                                                        ),
                                                        child: Row(
                                                          mainAxisSize: MainAxisSize.min,
                                                          children: [
                                                            Text('${b.count}', style: const TextStyle(color: Colors.cyanAccent, fontWeight: FontWeight.bold, fontSize: 13)),
                                                            const SizedBox(width: 3),
                                                            const Icon(Icons.edit, color: Colors.cyanAccent, size: 12),
                                                          ],
                                                        ),
                                                      ),
                                                    ),
                                                    IconButton(
                                                      icon: const Icon(Icons.add_circle_outline, color: Colors.blueAccent, size: 20),
                                                      onPressed: () {
                                                        if (b.count < 10000) {
                                                          setState(() => b.count++);
                                                        }
                                                      },
                                                    ),
                                                    IconButton(
                                                      icon: const Icon(Icons.close_rounded, color: Colors.redAccent, size: 18),
                                                      onPressed: () {
                                                        setState(() => _batchQueue.removeAt(idx));
                                                      },
                                                    ),
                                                  ],
                                                ),
                                              );
                                            },
                                          ),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                if (_batchQueue.isNotEmpty) ...[
                                  ElevatedButton.icon(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.green,
                                      foregroundColor: Colors.white,
                                      minimumSize: const Size(double.infinity, 48),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                    ),
                                    icon: const Icon(Icons.print_rounded),
                                    label: Text(
                                      'طباعة القائمة المجمعة بالكامل (${_batchQueue.fold<int>(0, (sum, i) => sum + i.count)} ملصق)',
                                      style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 13),
                                    ),
                                    onPressed: () => _printLabelsBrowser(isBatch: true),
                                  ),
                                  const SizedBox(height: 6),
                                  OutlinedButton.icon(
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: Colors.cyanAccent,
                                      side: const BorderSide(color: Colors.cyanAccent),
                                      minimumSize: const Size(double.infinity, 44),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                    ),
                                    icon: const Icon(Icons.flash_on_rounded),
                                    label: const Text('طباعة صامتة ومباشرة للطابعة', style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 12)),
                                    onPressed: () => _printLabelsDirect(apiService.baseUrl, isBatch: true),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // ==========================================
            // --- RIGHT PANEL: Live Interactive Design Preview (52%) ---
            // ==========================================
            Expanded(
              flex: 5,
              child: Container(
                color: const Color(0xFF0D1117),
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    // Studio Toolbar (Zoom & Modes)
                    Row(
                      children: [
                        const Icon(Icons.visibility_rounded, color: Colors.cyanAccent, size: 22),
                        const SizedBox(width: 8),
                        const Text(
                          'المعاينة الحية التفاعلية للملصق الحراري',
                          style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold, fontFamily: 'Cairo'),
                        ),
                        const Spacer(),

                        // Single vs Strip Mode Toggle
                        Container(
                          padding: const EdgeInsets.all(3),
                          decoration: BoxDecoration(
                            color: Colors.white10,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.white12),
                          ),
                          child: Row(
                            children: [
                              InkWell(
                                onTap: () => setState(() => _previewMode = 'single'),
                                borderRadius: BorderRadius.circular(6),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: _previewMode == 'single' ? Colors.blueAccent : Colors.transparent,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: const Text('ملصق مفرد', style: TextStyle(color: Colors.white, fontSize: 10.5, fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
                                ),
                              ),
                              InkWell(
                                onTap: () => setState(() => _previewMode = 'strip'),
                                borderRadius: BorderRadius.circular(6),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: _previewMode == 'strip' ? Colors.blueAccent : Colors.transparent,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: const Text('شريط رول متتالي', style: TextStyle(color: Colors.white, fontSize: 10.5, fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
                                ),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(width: 10),

                        // Zoom scale chips
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.white10,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.white12),
                          ),
                          child: Row(
                            children: [
                              IconButton(
                                icon: const Icon(Icons.zoom_out_rounded, color: Colors.white70, size: 18),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                                onPressed: () {
                                  if (_previewZoom > 0.75) {
                                    setState(() => _previewZoom -= 0.25);
                                  }
                                },
                              ),
                              const SizedBox(width: 6),
                              Text(
                                '${(_previewZoom * 100).toInt()}%',
                                style: const TextStyle(color: Colors.cyanAccent, fontWeight: FontWeight.bold, fontSize: 11),
                              ),
                              const SizedBox(width: 6),
                              IconButton(
                                icon: const Icon(Icons.zoom_in_rounded, color: Colors.white70, size: 18),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                                onPressed: () {
                                  if (_previewZoom < 2.0) {
                                    setState(() => _previewZoom += 0.25);
                                  }
                                },
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),
                        // Paper dimensions badge
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: const Color(0xFFE11D48).withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0xFFE11D48).withValues(alpha: 0.4)),
                          ),
                          child: Text(
                            '${_paperWidth.toStringAsFixed(0)} × ${_paperHeight.toStringAsFixed(0)} مم',
                            style: const TextStyle(color: Color(0xFFF43F5E), fontWeight: FontWeight.bold, fontSize: 12),
                          ),
                        ),
                      ],
                    ),

                    const Divider(color: Colors.white12, height: 24),

                    // Realistic Thermal Label Preview Box
                    Expanded(
                      child: Center(
                        child: SingleChildScrollView(
                          child: Transform.scale(
                            scale: _previewZoom,
                            child: _previewMode == 'single'
                                ? _buildLabelPreviewCard(
                                    fullItemName: fullItemName,
                                    formattedPrice: formattedPrice,
                                    barcodeVal: barcodeVal,
                                    previewSvg: previewSvg,
                                    currentColor: currentColor,
                                  )
                                : Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      _buildLabelPreviewCard(
                                        fullItemName: fullItemName,
                                        formattedPrice: formattedPrice,
                                        barcodeVal: barcodeVal,
                                        previewSvg: previewSvg,
                                        currentColor: currentColor,
                                      ),
                                      Padding(
                                        padding: const EdgeInsets.symmetric(vertical: 6.0),
                                        child: Row(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            const Icon(Icons.content_cut_rounded, color: Colors.white30, size: 16),
                                            Text(
                                              ' - - - - - - - - - خط الفصل بين الملصقات - - - - - - - - - ',
                                              style: TextStyle(color: Colors.white.withValues(alpha: 0.3), fontSize: 10),
                                            ),
                                          ],
                                        ),
                                      ),
                                      _buildLabelPreviewCard(
                                        fullItemName: fullItemName,
                                        formattedPrice: formattedPrice,
                                        barcodeVal: barcodeVal,
                                        previewSvg: previewSvg,
                                        currentColor: currentColor,
                                      ),
                                    ],
                                  ),
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 12),

                    // Quick Action Bar Below Preview
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E232D),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white12),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.3),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.check_circle_rounded, color: Colors.greenAccent, size: 22),
                              const SizedBox(width: 10),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'الملصق جاهز للطباعة: $fullItemName',
                                    style: const TextStyle(color: Colors.white, fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 13),
                                  ),
                                  Text(
                                    'السعر: $formattedPrice | المقاس: ${_paperWidth.toInt()}×${_paperHeight.toInt()} مم | النسخ: $_printCount',
                                    style: const TextStyle(color: Colors.white54, fontFamily: 'Cairo', fontSize: 11),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green[600],
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 13),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              elevation: 4,
                            ),
                            icon: const Icon(Icons.print_rounded, size: 20),
                            label: Text('طباعة الملصق الآن ($_printCount نسخة)', style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 13)),
                            onPressed: () => _printLabelsBrowser(isBatch: false),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- Dynamic Field Control Card for Tab 1 with Reordering Arrows ---
  Widget _buildDynamicFieldCard({
    required String fieldKey,
    required int index,
    required Color currentColor,
  }) {
    switch (fieldKey) {
      case 'header':
        return _buildElementControlCard(
          title: 'ترويسة المتجر والموديل (Store & Model Header)',
          icon: Icons.storefront_rounded,
          index: index,
          totalCount: _fieldOrder.length,
          onMoveUp: () => _moveFieldUp(index),
          onMoveDown: () => _moveFieldDown(index),
          isVisible: _showStoreName || _showLogo || _showModelNumber,
          onVisibilityChanged: (val) {
            setState(() {
              _showStoreName = val;
              _showLogo = val;
              _showModelNumber = val;
            });
            _saveSetting('barcode_show_store_name', val);
            _saveSetting('barcode_show_logo', val);
            _saveSetting('barcode_show_model_number', val);
          },
          currentAlign: _storeNameAlign,
          onAlignChanged: (val) {
            setState(() => _storeNameAlign = val);
            _saveSetting('barcode_store_align', val);
          },
          extraWidget: Column(
            children: [
              const SizedBox(height: 8),
              // Layout Choice: Split vs Stacked
              Row(
                children: [
                  const Text('تخطيط الترويسة:', style: TextStyle(color: Colors.white70, fontFamily: 'Cairo', fontSize: 11)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _headerLayout,
                      dropdownColor: const Color(0xFF0F172A),
                      style: const TextStyle(color: Colors.white, fontSize: 11, fontFamily: 'Cairo'),
                      decoration: InputDecoration(
                        fillColor: const Color(0xFF0F172A),
                        filled: true,
                        isDense: true,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'split', child: Text('سطر واحد متقابل (الموديل في طرف والمتجر في الآخر)')),
                        DropdownMenuItem(value: 'stacked', child: Text('أسطر منفصلة (المتجر في سطر والموديل تحته)')),
                      ],
                      onChanged: (val) {
                        if (val != null) {
                          setState(() => _headerLayout = val);
                          _saveSetting('barcode_header_layout', val);
                        }
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // Store Name Row & Controls
              Row(
                children: [
                  Checkbox(
                    value: _showStoreName,
                    activeColor: Colors.blueAccent,
                    onChanged: (val) {
                      setState(() => _showStoreName = val ?? false);
                      _saveSetting('barcode_show_store_name', val ?? false);
                    },
                  ),
                  const Text('إظهار اسم المحل', style: TextStyle(color: Colors.white, fontFamily: 'Cairo', fontSize: 11)),
                  const Spacer(),
                  _buildAlignmentSelector(
                    currentAlign: _storeNameAlign,
                    onAlignChanged: (val) {
                      setState(() => _storeNameAlign = val);
                      _saveSetting('barcode_store_align', val);
                    },
                  ),
                ],
              ),
              if (_showStoreName) ...[
                TextFormField(
                  controller: _storeNameController,
                  style: TextStyle(color: currentColor, fontSize: 13, fontWeight: FontWeight.bold, fontFamily: _fontFamily),
                  decoration: InputDecoration(
                    labelText: 'نص اسم المحل المطبوع',
                    labelStyle: const TextStyle(color: Colors.white70, fontFamily: 'Cairo', fontSize: 11),
                    fillColor: const Color(0xFF0F172A),
                    filled: true,
                    isDense: true,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onChanged: (val) {
                    setState(() => _storeName = val);
                    _saveSetting('barcode_store_name', val);
                  },
                ),
                const SizedBox(height: 8),
                // Color Presets for store name
                Row(
                  children: [
                    const Text('لون الخط:', style: TextStyle(color: Colors.white70, fontFamily: 'Cairo', fontSize: 11)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: _colorPresets.map((c) {
                            final isSel = _storeNameColorHex.toLowerCase() == c['hex'].toString().toLowerCase();
                            return Padding(
                              padding: const EdgeInsets.only(left: 6),
                              child: InkWell(
                                onTap: () {
                                  setState(() => _storeNameColorHex = c['hex']);
                                  _saveSetting('barcode_store_color', c['hex']);
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: c['color'] as Color,
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(color: isSel ? Colors.white : Colors.white24, width: isSel ? 2 : 1),
                                  ),
                                  child: Text(
                                    c['name'],
                                    style: const TextStyle(color: Colors.white, fontSize: 10, fontFamily: 'Cairo', fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    ),
                  ],
                ),
              ],

              const Divider(color: Colors.white12, height: 16),

              // Logo Row & Controls
              Row(
                children: [
                  Checkbox(
                    value: _showLogo,
                    activeColor: Colors.blueAccent,
                    onChanged: (val) {
                      setState(() => _showLogo = val ?? false);
                      _saveSetting('barcode_show_logo', val ?? false);
                    },
                  ),
                  const Text('إظهار الشعار (Logo)', style: TextStyle(color: Colors.white, fontFamily: 'Cairo', fontSize: 11)),
                  const Spacer(),
                  if (_showLogo)
                    Row(
                      children: [
                        Container(
                          width: 38,
                          height: 30,
                          decoration: BoxDecoration(
                            color: Colors.white12,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: Colors.white24),
                          ),
                          child: Center(child: _buildLogoWidget()),
                        ),
                        const SizedBox(width: 6),
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blueAccent,
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                          ),
                          icon: const Icon(Icons.upload_file_rounded, size: 14, color: Colors.white),
                          label: const Text('رفع شعار', style: TextStyle(color: Colors.white, fontFamily: 'Cairo', fontSize: 10)),
                          onPressed: _pickLogoImage,
                        ),
                        const SizedBox(width: 4),
                        OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.orangeAccent,
                            side: const BorderSide(color: Colors.orangeAccent),
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                          ),
                          onPressed: _removeLogoImage,
                          child: const Text('افتراضي', style: TextStyle(fontFamily: 'Cairo', fontSize: 10)),
                        ),
                      ],
                    ),
                ],
              ),

              const Divider(color: Colors.white12, height: 16),

              // Model Number Row & Controls
              Row(
                children: [
                  Checkbox(
                    value: _showModelNumber,
                    activeColor: Colors.blueAccent,
                    onChanged: (val) {
                      setState(() => _showModelNumber = val ?? false);
                      _saveSetting('barcode_show_model_number', val ?? false);
                    },
                  ),
                  const Text('إظهار رقم الموديل/الرمز', style: TextStyle(color: Colors.white, fontFamily: 'Cairo', fontSize: 11)),
                  const Spacer(),
                  _buildAlignmentSelector(
                    currentAlign: _modelAlign,
                    onAlignChanged: (val) {
                      setState(() => _modelAlign = val);
                      _saveSetting('barcode_model_align', val);
                    },
                  ),
                ],
              ),
              if (_showModelNumber) ...[
                Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: TextFormField(
                        controller: _modelController,
                        style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                        decoration: InputDecoration(
                          labelText: 'نص رقم الموديل',
                          labelStyle: const TextStyle(color: Colors.white70, fontFamily: 'Cairo', fontSize: 10),
                          fillColor: const Color(0xFF0F172A),
                          filled: true,
                          isDense: true,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        onChanged: (val) {
                          setState(() => _modelNumber = val);
                          _saveSetting('barcode_model_number', val);
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 1,
                      child: TextFormField(
                        controller: _modelPrefixController,
                        style: const TextStyle(color: Colors.white, fontSize: 11),
                        decoration: InputDecoration(
                          labelText: 'البادئة',
                          hintText: 'Mod:',
                          hintStyle: const TextStyle(color: Colors.white24, fontSize: 10),
                          labelStyle: const TextStyle(color: Colors.white70, fontFamily: 'Cairo', fontSize: 10),
                          fillColor: const Color(0xFF0F172A),
                          filled: true,
                          isDense: true,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        onChanged: (val) {
                          setState(() => _modelPrefix = val);
                          _saveSetting('barcode_model_prefix', val);
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        );

      case 'itemName':
        return _buildElementControlCard(
          title: 'اسم وبيان الصنف (Item Description)',
          icon: Icons.shopping_bag_outlined,
          index: index,
          totalCount: _fieldOrder.length,
          onMoveUp: () => _moveFieldUp(index),
          onMoveDown: () => _moveFieldDown(index),
          isVisible: _showItemName,
          onVisibilityChanged: (val) {
            setState(() => _showItemName = val);
            _saveSetting('barcode_show_item_name', val);
          },
          currentAlign: _itemNameAlign,
          onAlignChanged: (val) {
            setState(() => _itemNameAlign = val);
            _saveSetting('barcode_item_align', val);
          },
          extraWidget: Padding(
            padding: const EdgeInsets.only(top: 6.0),
            child: Row(
              children: [
                Checkbox(
                  value: _itemNameWrap,
                  activeColor: Colors.blueAccent,
                  onChanged: (val) {
                    setState(() => _itemNameWrap = val ?? false);
                    _saveSetting('barcode_item_wrap', val ?? false);
                  },
                ),
                const Text('السماح بالتفاف النص على سطرين (Wrap)', style: TextStyle(color: Colors.white70, fontFamily: 'Cairo', fontSize: 11)),
              ],
            ),
          ),
        );

      case 'price':
        return _buildElementControlCard(
          title: 'السعر والعملة (Price & Currency)',
          icon: Icons.monetization_on_outlined,
          index: index,
          totalCount: _fieldOrder.length,
          onMoveUp: () => _moveFieldUp(index),
          onMoveDown: () => _moveFieldDown(index),
          isVisible: _showPrice,
          onVisibilityChanged: (val) {
            setState(() => _showPrice = val);
            _saveSetting('barcode_show_price', val);
          },
          currentAlign: _priceAlign,
          onAlignChanged: (val) {
            setState(() => _priceAlign = val);
            _saveSetting('barcode_price_align', val);
          },
          extraWidget: Padding(
            padding: const EdgeInsets.only(top: 8.0),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _currencyController,
                        style: const TextStyle(color: Colors.white, fontSize: 12),
                        decoration: InputDecoration(
                          labelText: 'رمز العملة',
                          labelStyle: const TextStyle(color: Colors.white70, fontFamily: 'Cairo', fontSize: 11),
                          fillColor: const Color(0xFF0F172A),
                          filled: true,
                          isDense: true,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        onChanged: (val) {
                          setState(() => _currencySymbol = val);
                          _saveSetting('barcode_currency_symbol', val);
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: _currencyPosition,
                        dropdownColor: const Color(0xFF0F172A),
                        style: const TextStyle(color: Colors.white, fontSize: 12),
                        decoration: InputDecoration(
                          labelText: 'موضع الرمز',
                          labelStyle: const TextStyle(color: Colors.white70, fontFamily: 'Cairo', fontSize: 11),
                          fillColor: const Color(0xFF0F172A),
                          filled: true,
                          isDense: true,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        items: const [
                          DropdownMenuItem(value: 'prefix', child: Text('قبل السعر (RS48)')),
                          DropdownMenuItem(value: 'suffix', child: Text('بعد السعر (48 RS)')),
                          DropdownMenuItem(value: 'none', child: Text('بدون رمز (48)')),
                        ],
                        onChanged: (val) {
                          if (val != null) {
                            setState(() => _currencyPosition = val);
                            _saveSetting('barcode_currency_pos', val);
                          }
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Checkbox(
                      value: _showVatNote,
                      activeColor: Colors.blueAccent,
                      onChanged: (val) {
                        setState(() => _showVatNote = val ?? false);
                        _saveSetting('barcode_show_vat_note', val ?? false);
                      },
                    ),
                    const Text('إظهار عبارة (شامل الضريبة)', style: TextStyle(color: Colors.white70, fontFamily: 'Cairo', fontSize: 11)),
                  ],
                ),
              ],
            ),
          ),
        );

      case 'barcode':
        return _buildElementControlCard(
          title: 'رسم وتشفير الباركود (Barcode Graphic)',
          icon: Icons.qr_code_2_rounded,
          index: index,
          totalCount: _fieldOrder.length,
          onMoveUp: () => _moveFieldUp(index),
          onMoveDown: () => _moveFieldDown(index),
          isVisible: _showBarcodeGraphic || _showBarcodeText,
          onVisibilityChanged: (val) {
            setState(() {
              _showBarcodeGraphic = val;
              _showBarcodeText = val;
            });
            _saveSetting('barcode_show_barcode_graphic', val);
            _saveSetting('barcode_show_text', val);
          },
          currentAlign: _barcodeAlign,
          onAlignChanged: (val) {
            setState(() => _barcodeAlign = val);
            _saveSetting('barcode_barcode_align', val);
          },
          extraWidget: Padding(
            padding: const EdgeInsets.only(top: 8.0),
            child: Column(
              children: [
                DropdownButtonFormField<String>(
                  initialValue: _barcodeType,
                  dropdownColor: const Color(0xFF0F172A),
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                  decoration: InputDecoration(
                    labelText: 'نوع التشفير والباركود',
                    labelStyle: const TextStyle(color: Colors.white70, fontFamily: 'Cairo', fontSize: 11),
                    fillColor: const Color(0xFF0F172A),
                    filled: true,
                    isDense: true,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  items: _barcodeTypes.map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
                  onChanged: (val) {
                    if (val != null) {
                      setState(() => _barcodeType = val);
                      _saveSetting('barcode_type', val);
                    }
                  },
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Checkbox(
                      value: _showBarcodeGraphic,
                      activeColor: Colors.blueAccent,
                      onChanged: (val) {
                        setState(() => _showBarcodeGraphic = val ?? false);
                        _saveSetting('barcode_show_barcode_graphic', val ?? false);
                      },
                    ),
                    const Text('رسم خطوط الباركود', style: TextStyle(color: Colors.white70, fontFamily: 'Cairo', fontSize: 11)),
                    const Spacer(),
                    Checkbox(
                      value: _showBarcodeText,
                      activeColor: Colors.blueAccent,
                      onChanged: (val) {
                        setState(() => _showBarcodeText = val ?? false);
                        _saveSetting('barcode_show_text', val ?? false);
                      },
                    ),
                    const Text('أرقام الباركود نصياً', style: TextStyle(color: Colors.white70, fontFamily: 'Cairo', fontSize: 11)),
                  ],
                ),
              ],
            ),
          ),
        );

      case 'extraInfo':
        return _buildElementControlCard(
          title: 'بيانات إضافية (المقاس / اللون / ملاحظة)',
          icon: Icons.notes_rounded,
          index: index,
          totalCount: _fieldOrder.length,
          onMoveUp: () => _moveFieldUp(index),
          onMoveDown: () => _moveFieldDown(index),
          isVisible: _showExtraInfo,
          onVisibilityChanged: (val) {
            setState(() => _showExtraInfo = val);
            _saveSetting('barcode_show_extra_info', val);
          },
          currentAlign: _extraInfoAlign,
          onAlignChanged: (val) {
            setState(() => _extraInfoAlign = val);
            _saveSetting('barcode_extra_info_align', val);
          },
          extraWidget: Padding(
            padding: const EdgeInsets.only(top: 8.0),
            child: TextFormField(
              controller: _extraInfoController,
              style: const TextStyle(color: Colors.white, fontSize: 12),
              decoration: InputDecoration(
                labelText: 'النص الإضافي (مثال: المقاس: 41 | اللون: أسود)',
                labelStyle: const TextStyle(color: Colors.white70, fontFamily: 'Cairo', fontSize: 11),
                fillColor: const Color(0xFF0F172A),
                filled: true,
                isDense: true,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onChanged: (val) {
                setState(() => _extraInfoText = val);
                _saveSetting('barcode_extra_info_text', val);
              },
            ),
          ),
        );

      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildPresetButton({
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.6)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontFamily: 'Cairo', fontSize: 11)),
            Text(subtitle, style: const TextStyle(color: Colors.white60, fontFamily: 'Cairo', fontSize: 10)),
          ],
        ),
      ),
    );
  }

  Widget _buildElementControlCard({
    required String title,
    required IconData icon,
    required int index,
    required int totalCount,
    required VoidCallback onMoveUp,
    required VoidCallback onMoveDown,
    required bool isVisible,
    required ValueChanged<bool> onVisibilityChanged,
    required String currentAlign,
    required ValueChanged<String> onAlignChanged,
    Widget? extraWidget,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: isVisible ? Colors.blueAccent.withValues(alpha: 0.35) : Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Position Badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.blueAccent.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.blueAccent.withValues(alpha: 0.4)),
                ),
                child: Text(
                  '#${index + 1}',
                  style: const TextStyle(color: Colors.cyanAccent, fontWeight: FontWeight.bold, fontSize: 11),
                ),
              ),
              const SizedBox(width: 8),
              // Up / Down Reordering Buttons
              IconButton(
                icon: const Icon(Icons.arrow_upward_rounded, size: 16),
                color: index > 0 ? Colors.white70 : Colors.white24,
                tooltip: 'تحريك الحقل للأعلى ⬆️',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: index > 0 ? onMoveUp : null,
              ),
              const SizedBox(width: 4),
              IconButton(
                icon: const Icon(Icons.arrow_downward_rounded, size: 16),
                color: index < totalCount - 1 ? Colors.white70 : Colors.white24,
                tooltip: 'تحريك الحقل للأسفل ⬇️',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: index < totalCount - 1 ? onMoveDown : null,
              ),
              const SizedBox(width: 8),
              Icon(icon, color: isVisible ? Colors.blueAccent : Colors.white38, size: 18),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(color: isVisible ? Colors.white : Colors.white38, fontWeight: FontWeight.bold, fontFamily: 'Cairo', fontSize: 12),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              // Visibility Toggle
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(isVisible ? 'إظهار' : 'إخفاء', style: TextStyle(color: isVisible ? Colors.greenAccent : Colors.white38, fontFamily: 'Cairo', fontSize: 10)),
                  Switch(
                    value: isVisible,
                    activeTrackColor: Colors.blueAccent,
                    onChanged: onVisibilityChanged,
                  ),
                ],
              ),
            ],
          ),
          if (isVisible) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                const Text('المحاذاة العامة:', style: TextStyle(color: Colors.white70, fontFamily: 'Cairo', fontSize: 11)),
                const Spacer(),
                _buildAlignmentSelector(
                  currentAlign: currentAlign,
                  onAlignChanged: onAlignChanged,
                ),
              ],
            ),
            ?extraWidget,
          ],
        ],
      ),
    );
  }

  Widget _buildAlignmentSelector({
    required String currentAlign,
    required ValueChanged<String> onAlignChanged,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1E232D),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.white24),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildAlignBtn(label: 'يمين ➡', value: 'right', current: currentAlign, onSelect: onAlignChanged),
          Container(width: 1, height: 18, color: Colors.white12),
          _buildAlignBtn(label: 'وسط ⏺', value: 'center', current: currentAlign, onSelect: onAlignChanged),
          Container(width: 1, height: 18, color: Colors.white12),
          _buildAlignBtn(label: 'يسار ⬅', value: 'left', current: currentAlign, onSelect: onAlignChanged),
        ],
      ),
    );
  }

  Widget _buildAlignBtn({
    required String label,
    required String value,
    required String current,
    required ValueChanged<String> onSelect,
  }) {
    final isSel = current == value;
    return InkWell(
      onTap: () => onSelect(value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: isSel ? Colors.blueAccent : Colors.transparent,
          borderRadius: BorderRadius.circular(5),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSel ? Colors.white : Colors.white70,
            fontSize: 10.5,
            fontFamily: 'Cairo',
            fontWeight: isSel ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  Widget _buildSliderRow({
    required String title,
    required double value,
    required double min,
    required double max,
    String unit = 'pt',
    required ValueChanged<double> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(title, style: const TextStyle(color: Colors.white70, fontFamily: 'Cairo', fontSize: 11)),
              Text('${value.toStringAsFixed(1)} $unit', style: const TextStyle(color: Colors.cyanAccent, fontWeight: FontWeight.bold, fontSize: 12)),
            ],
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: Colors.blueAccent,
              thumbColor: Colors.cyanAccent,
              overlayColor: Colors.blueAccent.withValues(alpha: 0.2),
              trackHeight: 3,
            ),
            child: Slider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }

  // --- ENHANCED PRINT COUNT CONTROL (0 TO 10,000) ---
  void _setPrintCount(int newCount, {bool updateText = true}) {
    final clamped = newCount.clamp(0, 10000);
    setState(() {
      _printCount = clamped;
      if (updateText) {
        _countController.text = clamped.toString();
      }
    });
    _saveSetting('barcode_print_count', clamped);
  }

  Widget _buildEnhancedCountController() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.cyanAccent.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Row 1: Title & Direct editable text input with quick steppers
          Row(
            children: [
              const Icon(Icons.tag_rounded, color: Colors.cyanAccent, size: 18),
              const SizedBox(width: 6),
              const Expanded(
                child: Text(
                  'عدد النسخ (0 إلى 10,000):',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'Cairo',
                    fontSize: 12,
                  ),
                ),
              ),
              // Fast decrements: -100, -10
              InkWell(
                onTap: () => _setPrintCount(_printCount - 100),
                borderRadius: BorderRadius.circular(4),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E293B),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: Colors.white24),
                  ),
                  child: const Text('-100', style: TextStyle(color: Colors.orangeAccent, fontSize: 10, fontWeight: FontWeight.bold)),
                ),
              ),
              InkWell(
                onTap: () => _setPrintCount(_printCount - 10),
                borderRadius: BorderRadius.circular(4),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E293B),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: Colors.white24),
                  ),
                  child: const Text('-10', style: TextStyle(color: Colors.orangeAccent, fontSize: 10, fontWeight: FontWeight.bold)),
                ),
              ),
              IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                icon: const Icon(Icons.remove_circle_outline, color: Colors.blueAccent, size: 22),
                onPressed: () => _setPrintCount(_printCount - 1),
              ),
              // Direct Input Field Box
              Container(
                width: 76,
                height: 36,
                margin: const EdgeInsets.symmetric(horizontal: 4),
                child: TextFormField(
                  controller: _countController,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.cyanAccent,
                    fontWeight: FontWeight.w900,
                    fontSize: 15,
                  ),
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: InputDecoration(
                    contentPadding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                    fillColor: const Color(0xFF1E293B),
                    filled: true,
                    isDense: true,
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: const BorderSide(color: Colors.cyanAccent, width: 1.2),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: const BorderSide(color: Colors.cyan, width: 1.8),
                    ),
                  ),
                  onTap: () {
                    _countController.selection = TextSelection(
                      baseOffset: 0,
                      extentOffset: _countController.text.length,
                    );
                  },
                  onChanged: (val) {
                    final v = int.tryParse(val) ?? 0;
                    _setPrintCount(v, updateText: false);
                  },
                ),
              ),
              IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                icon: const Icon(Icons.add_circle_outline, color: Colors.blueAccent, size: 22),
                onPressed: () => _setPrintCount(_printCount + 1),
              ),
              // Fast increments: +10, +100
              InkWell(
                onTap: () => _setPrintCount(_printCount + 10),
                borderRadius: BorderRadius.circular(4),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E293B),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: Colors.white24),
                  ),
                  child: const Text('+10', style: TextStyle(color: Colors.greenAccent, fontSize: 10, fontWeight: FontWeight.bold)),
                ),
              ),
              InkWell(
                onTap: () => _setPrintCount(_printCount + 100),
                borderRadius: BorderRadius.circular(4),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E293B),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: Colors.white24),
                  ),
                  child: const Text('+100', style: TextStyle(color: Colors.greenAccent, fontSize: 10, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Row 2: Interactive Linear Slider from 0 to 10,000
          Row(
            children: [
              const Text('0', style: TextStyle(color: Colors.white38, fontSize: 10, fontFamily: 'Cairo')),
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 3,
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                    overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                  ),
                  child: Slider(
                    value: _printCount.toDouble().clamp(0.0, 10000.0),
                    min: 0.0,
                    max: 10000.0,
                    activeColor: Colors.cyanAccent,
                    inactiveColor: Colors.white24,
                    onChanged: (val) {
                      _setPrintCount(val.round());
                    },
                  ),
                ),
              ),
              const Text('10,000', style: TextStyle(color: Colors.white38, fontSize: 10, fontFamily: 'Cairo')),
            ],
          ),
          const SizedBox(height: 6),

          // Row 3: Direct Quick Jump Buttons
          Wrap(
            spacing: 4,
            runSpacing: 4,
            children: [
              _buildCountChip(label: '0 (تصفير)', value: 0, isSpecial: true),
              _buildCountChip(label: '1', value: 1),
              _buildCountChip(label: '5', value: 5),
              _buildCountChip(label: '10', value: 10),
              _buildCountChip(label: '25', value: 25),
              _buildCountChip(label: '50', value: 50),
              _buildCountChip(label: '100', value: 100),
              _buildCountChip(label: '250', value: 250),
              _buildCountChip(label: '500', value: 500),
              _buildCountChip(label: '1,000', value: 1000),
              _buildCountChip(label: '2,500', value: 2500),
              _buildCountChip(label: '5,000', value: 5000),
              _buildCountChip(label: '10,000', value: 10000),
              _buildActionCountChip(
                label: '+500',
                color: Colors.tealAccent,
                onTap: () => _setPrintCount(_printCount + 500),
              ),
              _buildActionCountChip(
                label: '+1,000',
                color: Colors.tealAccent,
                onTap: () => _setPrintCount(_printCount + 1000),
              ),
              _buildActionCountChip(
                label: '×2 (مضاعفة)',
                color: Colors.amberAccent,
                onTap: () => _setPrintCount(_printCount * 2),
              ),
              _buildActionCountChip(
                label: '÷2 (نصف)',
                color: Colors.blueAccent,
                onTap: () => _setPrintCount((_printCount / 2).round()),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCountChip({required String label, required int value, bool isSpecial = false}) {
    final isSelected = _printCount == value;
    return InkWell(
      onTap: () => _setPrintCount(value),
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: isSelected ? Colors.cyanAccent : (isSpecial ? Colors.redAccent.withValues(alpha: 0.15) : const Color(0xFF1E293B)),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: isSelected ? Colors.cyanAccent : (isSpecial ? Colors.redAccent.withValues(alpha: 0.4) : Colors.white24),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 10.5,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            color: isSelected ? Colors.black : (isSpecial ? Colors.redAccent : Colors.white70),
            fontFamily: 'Cairo',
          ),
        ),
      ),
    );
  }

  Widget _buildActionCountChip({required String label, required Color color, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.bold,
            color: color,
            fontFamily: 'Cairo',
          ),
        ),
      ),
    );
  }

  void _showBatchItemCountDialog(_BatchPrintItem item) {
    final textCtrl = TextEditingController(text: item.count.toString());
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDlgState) => Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            backgroundColor: const Color(0xFF0F172A),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: const BorderSide(color: Colors.cyanAccent, width: 1.5),
            ),
            title: Row(
              children: [
                const Icon(Icons.pin_rounded, color: Colors.cyanAccent, size: 24),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'تعديل عدد نسخ [${item.item.itemName}]',
                    style: const TextStyle(fontFamily: 'Cairo', color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            content: SizedBox(
              width: 380,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.remove_circle_outline, color: Colors.blueAccent),
                        onPressed: () {
                          if (item.count > 0) {
                            setDlgState(() {
                              item.count--;
                              textCtrl.text = item.count.toString();
                            });
                            setState(() {});
                          }
                        },
                      ),
                      Expanded(
                        child: TextFormField(
                          controller: textCtrl,
                          keyboardType: TextInputType.number,
                          textAlign: TextAlign.center,
                          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                          style: const TextStyle(color: Colors.cyanAccent, fontWeight: FontWeight.bold, fontSize: 20),
                          decoration: InputDecoration(
                            fillColor: const Color(0xFF1E293B),
                            filled: true,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          onChanged: (val) {
                            final v = (int.tryParse(val) ?? 0).clamp(0, 10000);
                            setDlgState(() => item.count = v);
                            setState(() {});
                          },
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.add_circle_outline, color: Colors.blueAccent),
                        onPressed: () {
                          if (item.count < 10000) {
                            setDlgState(() {
                              item.count++;
                              textCtrl.text = item.count.toString();
                            });
                            setState(() {});
                          }
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Slider(
                    value: item.count.toDouble().clamp(0.0, 10000.0),
                    min: 0,
                    max: 10000,
                    activeColor: Colors.cyanAccent,
                    onChanged: (v) {
                      setDlgState(() {
                        item.count = v.round();
                        textCtrl.text = item.count.toString();
                      });
                      setState(() {});
                    },
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    children: [0, 1, 5, 10, 50, 100, 500, 1000, 5000, 10000].map((c) {
                      return InkWell(
                        onTap: () {
                          setDlgState(() {
                            item.count = c;
                            textCtrl.text = c.toString();
                          });
                          setState(() {});
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: item.count == c ? Colors.cyanAccent : const Color(0xFF1E293B),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: item.count == c ? Colors.cyanAccent : Colors.white24),
                          ),
                          child: Text(
                            '$c',
                            style: TextStyle(
                              color: item.count == c ? Colors.black : Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              fontFamily: 'Cairo',
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
            actions: [
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.cyanAccent, foregroundColor: Colors.black),
                onPressed: () => Navigator.pop(ctx),
                child: const Text('تم', style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
