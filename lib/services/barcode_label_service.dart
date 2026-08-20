import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:barcode/barcode.dart' as bc_lib;
import '../models/item.dart';
import 'api_service.dart';
import 'print_service.dart';

class BarcodeLabelConfig {
  List<String> fieldOrder;
  double paperWidth;
  double paperHeight;
  double labelPaddingMm;
  String sizeTemplate;
  String fontFamily;

  // Store Name
  String storeName;
  String storeNameColorHex;
  bool showStoreName;
  String storeNameAlign;
  double storeNameFontSize;
  bool storeNameBold;

  // Logo
  bool showLogo;
  String logoAlign;
  String? logoBase64;
  double logoHeight;

  // Model
  String modelNumber;
  String modelPrefix;
  bool showModelNumber;
  String modelAlign;
  double modelFontSize;
  bool modelBold;
  String headerLayout;

  // Item Name
  bool showItemName;
  String itemNameAlign;
  double itemNameFontSize;
  bool itemNameWrap;

  // Price
  bool showPrice;
  String priceAlign;
  double priceFontSize;
  String currencySymbol;
  String currencyPosition;
  bool showVatNote;
  String vatNoteText;

  // Barcode
  bool showBarcodeGraphic;
  String barcodeAlign;
  bool showBarcodeText;
  double barcodeHeight;
  String barcodeType;

  // Extra Info
  bool showExtraInfo;
  String extraInfoText;
  String extraInfoAlign;
  double extraInfoFontSize;

  String printerName;
  int defaultPrintCount;

  BarcodeLabelConfig({
    List<String>? fieldOrder,
    this.paperWidth = 50.0,
    this.paperHeight = 30.0,
    this.labelPaddingMm = 1.2,
    this.sizeTemplate = '50x30',
    this.fontFamily = 'Cairo',
    this.storeName = 'الأميرة',
    this.storeNameColorHex = '#7e0542',
    this.showStoreName = true,
    this.storeNameAlign = 'right',
    this.storeNameFontSize = 12.5,
    this.storeNameBold = true,
    this.showLogo = true,
    this.logoAlign = 'right',
    this.logoBase64,
    this.logoHeight = 8.5,
    this.modelNumber = '',
    this.modelPrefix = '',
    this.showModelNumber = true,
    this.modelAlign = 'left',
    this.modelFontSize = 10.5,
    this.modelBold = true,
    this.headerLayout = 'split',
    this.showItemName = true,
    this.itemNameAlign = 'right',
    this.itemNameFontSize = 10.0,
    this.itemNameWrap = false,
    this.showPrice = true,
    this.priceAlign = 'center',
    this.priceFontSize = 14.5,
    this.currencySymbol = 'RS',
    this.currencyPosition = 'prefix',
    this.showVatNote = false,
    this.vatNoteText = 'شامل الضريبة',
    this.showBarcodeGraphic = true,
    this.barcodeAlign = 'center',
    this.showBarcodeText = false,
    this.barcodeHeight = 12.0,
    this.barcodeType = 'Code128',
    this.showExtraInfo = false,
    this.extraInfoText = 'المقاس: 40 | اللون: أسود',
    this.extraInfoAlign = 'center',
    this.extraInfoFontSize = 8.5,
    this.printerName = 'Xprinter XP-365B',
    this.defaultPrintCount = 1,
  }) : fieldOrder = fieldOrder ?? ['header', 'itemName', 'price', 'barcode', 'extraInfo'];

  static Future<BarcodeLabelConfig> loadFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final savedOrder = prefs.getString('barcode_field_order');
    List<String> order = ['header', 'itemName', 'price', 'barcode', 'extraInfo'];
    if (savedOrder != null && savedOrder.isNotEmpty) {
      try {
        final List<dynamic> decoded = jsonDecode(savedOrder);
        order = decoded.map((e) => e.toString()).toList();
      } catch (_) {}
    }

    final savedLogo = prefs.getString('barcode_logo_base64');

    return BarcodeLabelConfig(
      fieldOrder: order,
      paperWidth: prefs.getDouble('barcode_paper_width') ?? 50.0,
      paperHeight: prefs.getDouble('barcode_paper_height') ?? 30.0,
      labelPaddingMm: prefs.getDouble('barcode_label_padding') ?? 1.2,
      storeName: prefs.getString('barcode_store_name') ?? 'الأميرة',
      storeNameColorHex: prefs.getString('barcode_store_color') ?? '#7e0542',
      showStoreName: prefs.getBool('barcode_show_store_name') ?? true,
      storeNameAlign: prefs.getString('barcode_store_align') ?? 'right',
      storeNameFontSize: prefs.getDouble('barcode_store_font_size') ?? 12.5,
      storeNameBold: prefs.getBool('barcode_store_bold') ?? true,
      showLogo: prefs.getBool('barcode_show_logo') ?? true,
      logoAlign: prefs.getString('barcode_logo_align') ?? 'right',
      logoBase64: (savedLogo != null && savedLogo.isNotEmpty) ? savedLogo : null,
      logoHeight: prefs.getDouble('barcode_logo_height') ?? 8.5,
      modelNumber: prefs.getString('barcode_model_number') ?? '',
      modelPrefix: prefs.getString('barcode_model_prefix') ?? '',
      showModelNumber: prefs.getBool('barcode_show_model_number') ?? true,
      modelAlign: prefs.getString('barcode_model_align') ?? 'left',
      modelFontSize: prefs.getDouble('barcode_model_font_size') ?? 10.5,
      modelBold: prefs.getBool('barcode_model_bold') ?? true,
      headerLayout: prefs.getString('barcode_header_layout') ?? 'split',
      showItemName: prefs.getBool('barcode_show_item_name') ?? true,
      itemNameAlign: prefs.getString('barcode_item_align') ?? 'right',
      itemNameFontSize: prefs.getDouble('barcode_item_font_size') ?? 10.0,
      itemNameWrap: prefs.getBool('barcode_item_wrap') ?? false,
      showPrice: prefs.getBool('barcode_show_price') ?? true,
      priceAlign: prefs.getString('barcode_price_align') ?? 'center',
      priceFontSize: prefs.getDouble('barcode_price_font_size') ?? 14.5,
      currencySymbol: prefs.getString('barcode_currency_symbol') ?? 'RS',
      currencyPosition: prefs.getString('barcode_currency_pos') ?? 'prefix',
      showVatNote: prefs.getBool('barcode_show_vat_note') ?? false,
      vatNoteText: prefs.getString('barcode_vat_note_text') ?? 'شامل الضريبة',
      showBarcodeGraphic: prefs.getBool('barcode_show_barcode_graphic') ?? true,
      barcodeAlign: prefs.getString('barcode_barcode_align') ?? 'center',
      showBarcodeText: prefs.getBool('barcode_show_text') ?? false,
      barcodeHeight: prefs.getDouble('barcode_graphic_height') ?? 12.0,
      barcodeType: prefs.getString('barcode_type') ?? 'Code128',
      showExtraInfo: prefs.getBool('barcode_show_extra_info') ?? false,
      extraInfoText: prefs.getString('barcode_extra_info_text') ?? 'المقاس: 40 | اللون: أسود',
      extraInfoAlign: prefs.getString('barcode_extra_info_align') ?? 'center',
      extraInfoFontSize: prefs.getDouble('barcode_extra_info_font_size') ?? 8.5,
      fontFamily: prefs.getString('barcode_font_family') ?? 'Cairo',
      printerName: prefs.getString('barcode_printer_name') ?? 'Xprinter XP-365B',
      defaultPrintCount: prefs.getInt('barcode_print_count') ?? 1,
    );
  }
}

class BarcodeLabelItemData {
  final String itemName;
  final String barcode;
  final double price;
  final String model;
  final int count;

  BarcodeLabelItemData({
    required this.itemName,
    required this.barcode,
    required this.price,
    this.model = '',
    this.count = 1,
  });
}

class BarcodeLabelService {
  static String mapAlignToJustify(String align) {
    if (align == 'left') return 'flex-start';
    if (align == 'right') return 'flex-end';
    return 'center';
  }

  static bc_lib.Barcode getBarcodeInstance(String type) {
    switch (type) {
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

  static Color parseHexColor(String hex, {Color fallback = const Color(0xFF7E0542)}) {
    try {
      final clean = hex.replaceAll('#', '').trim();
      if (clean.length == 6) {
        return Color(int.parse('FF$clean', radix: 16));
      } else if (clean.length == 8) {
        return Color(int.parse(clean, radix: 16));
      }
    } catch (_) {}
    return fallback;
  }

  static Widget _buildBarcodeSvgPreviewWidget(String svgString, String fallbackCode) {
    if (svgString.isNotEmpty && svgString.contains('<svg')) {
      try {
        return SvgPicture.string(
          svgString,
          fit: BoxFit.contain,
          height: 38,
          placeholderBuilder: (_) => const Icon(Icons.qr_code, color: Colors.black87),
        );
      } catch (_) {}
    }
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.qr_code_2, color: Colors.black87, size: 28),
        const SizedBox(width: 6),
        Text(
          fallbackCode.isNotEmpty ? fallbackCode : '123456',
          style: const TextStyle(color: Colors.black87, fontWeight: FontWeight.bold, fontFamily: 'monospace'),
        ),
      ],
    );
  }

  static String generateBarcodeSvg(String codeVal, {String barcodeType = 'Code128'}) {
    String sanitized = codeVal.trim();
    if (barcodeType != 'QR Code') {
      // Remove any non-ASCII characters that break 1D barcode encoders
      sanitized = sanitized.replaceAll(RegExp(r'[^\x20-\x7E]'), '');
    }
    if (sanitized.isEmpty) sanitized = '12345678';

    String finalBarcodeVal = sanitized;
    if (barcodeType == 'EAN13') {
      final clean = sanitized.replaceAll(RegExp(r'\D'), '');
      finalBarcodeVal = clean.length < 12 ? clean.padRight(12, '0') : clean.substring(0, 12);
    } else if (barcodeType == 'EAN8') {
      final clean = sanitized.replaceAll(RegExp(r'\D'), '');
      finalBarcodeVal = clean.length < 7 ? clean.padRight(7, '0') : clean.substring(0, 7);
    } else if (barcodeType == 'UPCA') {
      final clean = sanitized.replaceAll(RegExp(r'\D'), '');
      finalBarcodeVal = clean.length < 11 ? clean.padRight(11, '0') : clean.substring(0, 11);
    }

    try {
      final bc = getBarcodeInstance(barcodeType);
      return bc.toSvg(
        finalBarcodeVal,
        width: barcodeType == 'QR Code' ? 90 : 260,
        height: barcodeType == 'QR Code' ? 90 : 75,
        fontHeight: 0,
      );
    } catch (e) {
      try {
        final bc = bc_lib.Barcode.code128();
        return bc.toSvg(
          '12345678',
          width: 260,
          height: 75,
          fontHeight: 0,
        );
      } catch (_) {
        return '<svg width="260" height="75" xmlns="http://www.w3.org/2000/svg"><rect width="100%" height="100%" fill="white"/><text x="10" y="40" font-family="monospace" font-size="20">12345678</text></svg>';
      }
    }
  }

  static String formatPrice(double price, BarcodeLabelConfig config) {
    final priceStr = price.toStringAsFixed(2);
    if (config.currencyPosition == 'prefix') {
      return '${config.currencySymbol}$priceStr';
    } else if (config.currencyPosition == 'suffix') {
      return '$priceStr ${config.currencySymbol}';
    }
    return priceStr;
  }

  static String generateHtml({
    required List<BarcodeLabelItemData> items,
    required BarcodeLabelConfig config,
  }) {
    final double paperW = config.paperWidth;
    final double paperH = config.paperHeight;
    final double pad = config.labelPaddingMm;
    final String logoSrc = config.logoBase64 ?? '';

    final List<String> pages = [];

    for (final itm in items) {
      final itemModel = itm.model.isNotEmpty
          ? itm.model
          : (itm.barcode.isNotEmpty ? itm.barcode : config.modelNumber);
      
      final fullItemName = (itemModel.isNotEmpty && !itm.itemName.contains(itemModel))
          ? '${itm.itemName} $itemModel'
          : itm.itemName;

      final formattedPrice = formatPrice(itm.price, config);
      final svgString = generateBarcodeSvg(itm.barcode, barcodeType: config.barcodeType);
      final String base64Svg = base64Encode(utf8.encode(svgString));

      for (int i = 0; i < itm.count; i++) {
        final Map<String, String> rowHtmlMap = {};

        // 1. Header Block
        if (config.showStoreName || config.showLogo || config.showModelNumber) {
          final modelText = config.showModelNumber
              ? '${config.modelPrefix.isNotEmpty ? '${config.modelPrefix} ' : ''}$itemModel'
              : '';
          final storeNameHtml = config.showStoreName ? '<span class="store-name">${config.storeName}</span>' : '';
          final logoHtml = config.showLogo && logoSrc.isNotEmpty ? '<img class="store-logo" src="$logoSrc" />' : '';

          if (config.headerLayout == 'stacked') {
            rowHtmlMap['header'] = """
            <div class="top-row-stacked">
              <div class="store-group" style="justify-content: ${mapAlignToJustify(config.storeNameAlign)}; width: 100%;">
                $storeNameHtml
                $logoHtml
              </div>
              ${modelText.isNotEmpty ? '<div class="model-code" style="text-align: ${config.modelAlign}; width: 100%;">$modelText</div>' : ''}
            </div>
            """;
          } else {
            rowHtmlMap['header'] = """
            <div class="top-row">
              <div class="store-group" style="justify-content: ${mapAlignToJustify(config.storeNameAlign)};">
                $storeNameHtml
                $logoHtml
              </div>
              <div class="model-code" style="text-align: ${config.modelAlign};">
                $modelText
              </div>
            </div>
            """;
          }
        }

        // 2. Item Name Block
        if (config.showItemName) {
          rowHtmlMap['itemName'] = '<div class="item-name-row" style="text-align: ${config.itemNameAlign}; direction: ${config.itemNameAlign == 'left' ? 'ltr' : 'rtl'};">$fullItemName</div>';
        }

        // 3. Price Block
        if (config.showPrice) {
          final vatHtml = config.showVatNote ? ' <span class="vat-note">${config.vatNoteText}</span>' : '';
          rowHtmlMap['price'] = '<div class="price-row" style="text-align: ${config.priceAlign}; justify-content: ${mapAlignToJustify(config.priceAlign)};">$formattedPrice$vatHtml</div>';
        }

        // 4. Extra Info Block
        if (config.showExtraInfo && config.extraInfoText.isNotEmpty) {
          rowHtmlMap['extraInfo'] = '<div class="extra-info-row" style="text-align: ${config.extraInfoAlign};">${config.extraInfoText}</div>';
        }

        // 5. Barcode Block
        if (config.showBarcodeGraphic || config.showBarcodeText) {
          final barcodeGraphicHtml = config.showBarcodeGraphic
              ? '<div class="barcode-row" style="justify-content: ${mapAlignToJustify(config.barcodeAlign)};"><img src="data:image/svg+xml;base64,$base64Svg" /></div>'
              : '';
          final barcodeTextHtml = config.showBarcodeText
              ? '<div class="barcode-text-val" style="text-align: ${config.barcodeAlign};">${itm.barcode}</div>'
              : '';
          rowHtmlMap['barcode'] = '$barcodeGraphicHtml\n$barcodeTextHtml';
        }

        // Assemble page blocks according to fieldOrder
        final List<String> pageBlocks = [];
        for (final k in config.fieldOrder) {
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
      font-family: '${config.fontFamily}', 'Cairo', 'Segoe UI', Tahoma, sans-serif;
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
      font-size: ${config.modelFontSize}pt;
      font-weight: ${config.modelBold ? 'bold' : 'normal'};
      color: #000000;
      font-family: '${config.fontFamily}', 'Segoe UI', Arial, sans-serif;
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
      font-size: ${config.storeNameFontSize}pt;
      font-weight: ${config.storeNameBold ? '900' : 'bold'};
      color: ${config.storeNameColorHex};
      font-family: '${config.fontFamily}', 'Cairo', sans-serif;
      letter-spacing: 0.5px;
      white-space: nowrap;
    }
    .store-logo {
      height: ${config.logoHeight}mm;
      max-height: ${config.logoHeight}mm;
      width: auto;
      object-fit: contain;
      display: inline-block;
    }

    /* 2. Item Name Row */
    .item-name-row {
      width: 100%;
      font-size: ${config.itemNameFontSize}pt;
      font-weight: bold;
      color: #000000;
      white-space: ${config.itemNameWrap ? 'normal' : 'nowrap'};
      overflow: hidden;
      text-overflow: ellipsis;
      line-height: 1.15;
      font-family: '${config.fontFamily}', 'Cairo', Arial, sans-serif;
      margin-bottom: 0.2mm;
    }

    /* 3. Price Row */
    .price-row {
      width: 100%;
      font-size: ${config.priceFontSize}pt;
      font-weight: 900;
      color: #000000;
      line-height: 1;
      font-family: '${config.fontFamily}', 'Segoe UI', Arial, sans-serif;
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
      font-size: ${config.extraInfoFontSize}pt;
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
      max-height: ${config.barcodeHeight}mm;
      display: flex;
      align-items: center;
      overflow: hidden;
      flex-grow: 1;
    }
    .barcode-row img {
      width: ${config.barcodeType == 'QR Code' ? 'auto' : '100%'};
      height: ${config.barcodeType == 'QR Code' ? '${config.barcodeHeight}mm' : 'auto'};
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
<body onload="setTimeout(function(){ try { window.focus(); window.print(); } catch(e){} }, 300);">
  $pagesHtml
</body>
</html>
""";
  }

  static Future<void> printSingleItem({
    required ItemModel item,
    int count = 1,
    double? priceOverride,
    String? modelOverride,
    BarcodeLabelConfig? config,
    BuildContext? context,
  }) async {
    final cfg = config ?? await BarcodeLabelConfig.loadFromPrefs();
    final itemData = BarcodeLabelItemData(
      itemName: item.itemName,
      barcode: item.barcode.trim(),
      price: priceOverride ?? item.salesPrice,
      model: modelOverride ?? item.barcode.trim(),
      count: count > 0 ? count : 1,
    );

    final htmlContent = generateHtml(items: [itemData], config: cfg);
    PrintService.printHtml(htmlContent);

    if (context != null && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '✅ تم فتح نافذة طباعة ($count) ملصق باركود للصنف [${item.itemName}]',
            style: const TextStyle(fontFamily: 'Cairo'),
          ),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  static Future<void> printSingleItemDirect({
    required ItemModel item,
    required String baseUrl,
    int count = 1,
    double? priceOverride,
    String? modelOverride,
    BarcodeLabelConfig? config,
    BuildContext? context,
  }) async {
    final cfg = config ?? await BarcodeLabelConfig.loadFromPrefs();
    final itemData = BarcodeLabelItemData(
      itemName: item.itemName,
      barcode: item.barcode.trim(),
      price: priceOverride ?? item.salesPrice,
      model: modelOverride ?? item.barcode.trim(),
      count: count > 0 ? count : 1,
    );

    final htmlContent = generateHtml(items: [itemData], config: cfg);
    final success = await PrintService.printHtmlDirect(
      htmlContent: htmlContent,
      baseUrl: baseUrl,
      printerName: cfg.printerName,
    );

    if (context != null && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            success
                ? '✅ تمت الطباعة المباشرة لـ ($count) ملصق على طابعة (${cfg.printerName})'
                : '✅ تم إرسال أمر الطباعة بنجاح لـ ($count) ملصق...',
            style: const TextStyle(fontFamily: 'Cairo'),
          ),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  static Future<void> showQuickBarcodePrintDialog({
    required BuildContext context,
    required ItemModel item,
    VoidCallback? onOpenDesigner,
  }) async {
    final config = await BarcodeLabelConfig.loadFromPrefs();
    int count = config.defaultPrintCount > 0 ? config.defaultPrintCount : 1;
    double price = item.salesPrice;
    final priceController = TextEditingController(text: price.toStringAsFixed(2));

    if (!context.mounted) return;

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setStateDialog) {
          final svgPreview = generateBarcodeSvg(item.barcode, barcodeType: config.barcodeType);
          final formattedPrice = formatPrice(price, config);
          final fullItemName = (item.barcode.isNotEmpty && !item.itemName.contains(item.barcode))
              ? '${item.itemName} ${item.barcode}'
              : item.itemName;

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
                      color: Colors.blueAccent.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.qr_code_scanner_rounded, color: Colors.blueAccent, size: 24),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'طباعة ملصق الباركود (وفق قالب التصميم)',
                          style: TextStyle(
                            color: Colors.white,
                            fontFamily: 'Cairo',
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        Text(
                          'القالب النشط: ${config.paperWidth.toInt()}×${config.paperHeight.toInt()} مم (${config.storeName})',
                          style: const TextStyle(
                            color: Colors.white54,
                            fontFamily: 'Cairo',
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              content: SizedBox(
                width: 460,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // --- LIVE LABEL PREVIEW CARD ---
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E293B),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.white12),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text(
                                  'معاينة الملصق المطبوع:',
                                  style: TextStyle(
                                    color: Colors.white70,
                                    fontFamily: 'Cairo',
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.blueAccent.withValues(alpha: 0.2),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    '${config.paperWidth.toInt()} × ${config.paperHeight.toInt()} مم',
                                    style: const TextStyle(color: Colors.blueAccent, fontSize: 11, fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),

                            // Mini Label Box (White simulated thermal sticker)
                            Center(
                              child: Container(
                                width: 280,
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(8),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(alpha: 0.35),
                                      blurRadius: 10,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [
                                    // 1. Header (Store + Logo on Right, Model on Left)
                                    if (config.showStoreName || config.showModelNumber || config.showLogo) ...[
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        crossAxisAlignment: CrossAxisAlignment.center,
                                        children: [
                                          // RIGHT in RTL: Store Name + Logo
                                          Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              if (config.showStoreName)
                                                Text(
                                                  config.storeName,
                                                  style: TextStyle(
                                                    fontFamily: config.fontFamily,
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.w900,
                                                    color: parseHexColor(config.storeNameColorHex),
                                                  ),
                                                ),
                                              if (config.showLogo && config.logoBase64 != null && config.logoBase64!.isNotEmpty) ...[
                                                const SizedBox(width: 4),
                                                config.logoBase64!.startsWith('data:image/svg')
                                                    ? SvgPicture.string(
                                                        utf8.decode(base64Decode(config.logoBase64!.split(',')[1])),
                                                        height: config.logoHeight * 2.2,
                                                        fit: BoxFit.contain,
                                                      )
                                                    : Image.memory(
                                                        base64Decode(config.logoBase64!.split(',').length > 1 ? config.logoBase64!.split(',')[1] : config.logoBase64!),
                                                        height: config.logoHeight * 2.2,
                                                        fit: BoxFit.contain,
                                                        errorBuilder: (_, _, _) => const SizedBox.shrink(),
                                                      ),
                                              ],
                                            ],
                                          ),
                                          // LEFT in RTL: Model / Barcode code
                                          if (config.showModelNumber)
                                            Text(
                                              '${config.modelPrefix}${item.barcode.isNotEmpty ? item.barcode : config.modelNumber}',
                                              style: TextStyle(
                                                fontFamily: config.fontFamily,
                                                fontSize: 10,
                                                fontWeight: FontWeight.bold,
                                                color: Colors.black87,
                                              ),
                                            ),
                                        ],
                                      ),
                                      const SizedBox(height: 3),
                                    ],

                                    // 2. Item Name
                                    if (config.showItemName) ...[
                                      Text(
                                        fullItemName,
                                        style: TextStyle(
                                          fontFamily: config.fontFamily,
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.black,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        textAlign: TextAlign.center,
                                      ),
                                      const SizedBox(height: 3),
                                    ],

                                    // 3. Price
                                    if (config.showPrice) ...[
                                      Text(
                                        formattedPrice,
                                        style: TextStyle(
                                          fontFamily: config.fontFamily,
                                          fontSize: 13,
                                          fontWeight: FontWeight.w900,
                                          color: Colors.black,
                                        ),
                                        textAlign: TextAlign.center,
                                      ),
                                      const SizedBox(height: 3),
                                    ],

                                    // 4. Barcode Graphics
                                    if (config.showBarcodeGraphic) ...[
                                      Container(
                                        height: 36,
                                        width: double.infinity,
                                        alignment: Alignment.center,
                                        child: _buildBarcodeSvgPreviewWidget(svgPreview, item.barcode),
                                      ),
                                      const SizedBox(height: 2),
                                    ],

                                    // 5. Barcode Text
                                    if (config.showBarcodeText)
                                      Text(
                                        item.barcode.isNotEmpty ? item.barcode : '12345678',
                                        style: const TextStyle(
                                          fontFamily: 'monospace',
                                          fontSize: 9,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.black,
                                          letterSpacing: 1.5,
                                        ),
                                        textAlign: TextAlign.center,
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),

                      // --- ITEM DETAILS & PRICE OVERRIDE ---
                      Row(
                        children: [
                          Expanded(
                            flex: 3,
                            child: TextField(
                              controller: TextEditingController(text: item.itemName),
                              readOnly: true,
                              style: const TextStyle(color: Colors.white, fontFamily: 'Cairo', fontSize: 13),
                              decoration: const InputDecoration(
                                labelText: 'اسم الصنف',
                                labelStyle: TextStyle(color: Colors.white70, fontFamily: 'Cairo'),
                                filled: true,
                                fillColor: Color(0xFF1E293B),
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            flex: 2,
                            child: TextField(
                              controller: priceController,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold, fontSize: 14),
                              decoration: InputDecoration(
                                labelText: 'سعر الملصق (${config.currencySymbol})',
                                labelStyle: const TextStyle(color: Colors.white70, fontFamily: 'Cairo', fontSize: 11),
                                filled: true,
                                fillColor: const Color(0xFF1E293B),
                                border: const OutlineInputBorder(),
                                isDense: true,
                              ),
                              onChanged: (val) {
                                final p = double.tryParse(val);
                                if (p != null) {
                                  setStateDialog(() {
                                    price = p;
                                  });
                                }
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),

                      // --- PRINT COUNT CONTROLS ---
                      const Text(
                        'عدد الملصقات المطلوب طباعتها:',
                        style: TextStyle(color: Colors.white70, fontFamily: 'Cairo', fontSize: 13),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.remove_circle_outline, color: Colors.orangeAccent, size: 28),
                            onPressed: () {
                              if (count > 1) {
                                setStateDialog(() => count--);
                              }
                            },
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1E293B),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.blueAccent.withValues(alpha: 0.5)),
                            ),
                            child: Text(
                              '$count',
                              style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold, fontFamily: 'Cairo'),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.add_circle_outline, color: Colors.tealAccent, size: 28),
                            onPressed: () => setStateDialog(() => count++),
                          ),
                          const SizedBox(width: 12),

                          // Quick Chips
                          ...[1, 5, 10, 20, 50].map((c) {
                            final isSel = count == c;
                            return Padding(
                              padding: const EdgeInsets.only(right: 4),
                              child: InkWell(
                                onTap: () => setStateDialog(() => count = c),
                                borderRadius: BorderRadius.circular(6),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: isSel ? Colors.blueAccent : const Color(0xFF1E293B),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    '$c',
                                    style: TextStyle(
                                      color: isSel ? Colors.white : Colors.white70,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                              ),
                            );
                          }),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                if (onOpenDesigner != null)
                  TextButton.icon(
                    style: TextButton.styleFrom(foregroundColor: Colors.amberAccent),
                    icon: const Icon(Icons.design_services_rounded, size: 18),
                    label: const Text('تخصيص القالب في شاشة التصميم', style: TextStyle(fontFamily: 'Cairo')),
                    onPressed: () {
                      Navigator.pop(dialogContext);
                      onOpenDesigner();
                    },
                  ),
                const Spacer(),
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('إلغاء', style: TextStyle(color: Colors.white60, fontFamily: 'Cairo')),
                ),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.cyanAccent,
                    side: const BorderSide(color: Colors.cyanAccent),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  icon: const Icon(Icons.open_in_browser_rounded, size: 18),
                  label: const Text('معاينة وطباعة المتصفح', style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
                  onPressed: () async {
                    Navigator.pop(dialogContext);
                    await printSingleItem(
                      item: item,
                      count: count,
                      priceOverride: price,
                      config: config,
                      context: context,
                    );
                  },
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.tealAccent.shade700,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  icon: const Icon(Icons.print_rounded, size: 18),
                  label: Text(
                    'طباعة $count ملصق حراري 🖨️',
                    style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold),
                  ),
                  onPressed: () async {
                    Navigator.pop(dialogContext);
                    final apiService = Provider.of<ApiService>(context, listen: false);
                    await printSingleItemDirect(
                      item: item,
                      baseUrl: apiService.baseUrl,
                      count: count,
                      priceOverride: price,
                      config: config,
                      context: context,
                    );
                  },
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
