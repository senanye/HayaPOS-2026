import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:universal_html/html.dart' as html;
import 'package:universal_html/js.dart' as js;

class PrintService {
  /// Sends raw HTML directly to the Python backend to print silently to the Windows printer without any preview dialog.
  static Future<bool> printHtmlDirect({
    required String htmlContent,
    required String baseUrl,
    String? printerName,
  }) async {
    if (kIsWeb) {
      try {
        final response = await http.post(
          Uri.parse('$baseUrl/api/print-direct'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'html_content': htmlContent,
            'printer_name': printerName,
          }),
        ).timeout(const Duration(seconds: 15));

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          if (data['status'] == 'success') {
            return true;
          }
        }
      } catch (e) {
        debugPrint("Direct server print error: $e");
      }
    }
    // Fallback if direct server print failed or unavailable
    printHtml(htmlContent);
    return false;
  }

  /// Prints raw HTML content safely using JS helper or active iframe strategy.
  static void printHtml(String htmlContent, {bool preferNewWindow = false}) {
    if (kIsWeb) {
      if (preferNewWindow) {
        _fallbackWindowOpen(htmlContent);
        return;
      }
      // Primary Strategy: Invoke JavaScript print handler
      try {
        if (js.context.hasProperty('printRawHtml')) {
          js.context.callMethod('printRawHtml', [htmlContent]);
          return;
        }
      } catch (e) {
        debugPrint("JS printRawHtml call error: $e");
      }

      // Secondary Strategy: Active Iframe in DOM
      _printViaActiveIframe(htmlContent);
    } else {
      debugPrint("PrintService fallback for non-web platforms.");
    }
  }

  static void _printViaActiveIframe(String htmlContent) {
    try {
      final existingFrame = html.document.getElementById('__hayapos_print_iframe__');
      if (existingFrame != null) {
        existingFrame.remove();
      }

      final iframe = html.IFrameElement()
        ..id = '__hayapos_print_iframe__'
        ..name = '__hayapos_print_iframe__'
        ..style.position = 'fixed'
        ..style.right = '0'
        ..style.bottom = '0'
        ..style.width = '10px'
        ..style.height = '10px'
        ..style.opacity = '0.01'
        ..style.border = 'none'
        ..style.zIndex = '-999';

      html.document.body!.children.add(iframe);

      final dynamic win = iframe.contentWindow;
      if (win != null) {
        final doc = win.document;
        doc.open();
        doc.write(htmlContent);
        doc.close();

        Future.delayed(const Duration(milliseconds: 250), () {
          try {
            win.focus();
            win.print();
          } catch (e) {
            debugPrint("Active iframe print error: $e");
            _fallbackWindowOpen(htmlContent);
          }
        });
      }
    } catch (e) {
      debugPrint("Error in _printViaActiveIframe: $e");
      _fallbackWindowOpen(htmlContent);
    }
  }

  static void _fallbackWindowOpen(String htmlContent) {
    try {
      final dynamic win = html.window.open('', '_blank', 'width=800,height=700,menubar=no,toolbar=no,location=no,status=no');
      if (win != null) {
        final doc = win.document;
        doc.open();
        doc.write(htmlContent);
        doc.close();
        win.focus();
        Future.delayed(const Duration(milliseconds: 250), () {
          try {
            win.print();
          } catch (_) {}
        });
      }
    } catch (e) {
      debugPrint("Window open fallback error: $e");
    }
  }
}
