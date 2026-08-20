import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../services/api_service.dart';

class WhatsAppProviderDialog extends StatefulWidget {
  final ApiService apiService;

  const WhatsAppProviderDialog({super.key, required this.apiService});

  static Future<void> show(BuildContext context, ApiService apiService) async {
    return showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => WhatsAppProviderDialog(apiService: apiService),
    );
  }

  @override
  State<WhatsAppProviderDialog> createState() => _WhatsAppProviderDialogState();
}

class _WhatsAppProviderDialogState extends State<WhatsAppProviderDialog> {
  bool _isLoading = true;
  bool _isSaving = false;
  bool _isSendingTest = false;

  bool _isConnected = false;
  String _connectedPhone = '';
  String _statusText = 'جاري التحقق من حالة الواتساب... 🔄';
  String _qrDataUrl = '';
  bool _hasQr = false;

  final TextEditingController _financialPhoneController = TextEditingController();
  final TextEditingController _auditPhoneController = TextEditingController();
  final TextEditingController _testPhoneController = TextEditingController();
  final TextEditingController _testMessageController = TextEditingController(
      text: 'سلام عليكم، هذه رسالة تجريبية من نظام هيا POS لتأكيد ربط مزود الواتساب 🚀');

  Timer? _statusTimer;

  @override
  void initState() {
    super.initState();
    _loadAll();
    _statusTimer = Timer.periodic(const Duration(seconds: 4), (_) => _checkStatusAndQr());
  }

  @override
  void dispose() {
    _statusTimer?.cancel();
    _financialPhoneController.dispose();
    _auditPhoneController.dispose();
    _testPhoneController.dispose();
    _testMessageController.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    setState(() => _isLoading = true);
    await Future.wait([
      _checkStatusAndQr(),
      _loadSettings(),
    ]);
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _checkStatusAndQr() async {
    try {
      final statusRes = await widget.apiService.fetchWhatsAppStatus();
      final qrRes = await widget.apiService.fetchWhatsAppQr();

      if (mounted) {
        setState(() {
          _isConnected = statusRes['connected'] ?? false;
          _connectedPhone = statusRes['phone'] ?? '';
          _statusText = statusRes['statusText'] ?? statusRes['status_text'] ?? 'السيرفر جاهز';
          _qrDataUrl = qrRes['qrDataUrl'] ?? '';
          _hasQr = _qrDataUrl.isNotEmpty;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _statusText = 'خطأ في الاتصال بسيرفر الواتساب الخفي';
        });
      }
    }
  }

  Future<void> _loadSettings() async {
    try {
      final settings = await widget.apiService.getWhatsAppSettings();
      if (mounted) {
        _financialPhoneController.text = settings['financialPhone'] ?? '';
        _auditPhoneController.text = settings['auditPhone'] ?? '';
        if (_testPhoneController.text.isEmpty) {
          _testPhoneController.text = settings['financialPhone'] ?? settings['auditPhone'] ?? '';
        }
      }
    } catch (_) {}
  }

  Future<void> _saveSettings() async {
    setState(() => _isSaving = true);
    try {
      final res = await widget.apiService.saveWhatsAppSettings({
        'financialPhone': _financialPhoneController.text.trim(),
        'auditPhone': _auditPhoneController.text.trim(),
        'providerType': 'baileys',
        'autoSendFinancial': false,
        'autoSendAudit': false,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(res['message'] ?? 'تم حفظ الإعدادات بنجاح 💾',
                style: const TextStyle(fontFamily: 'Cairo')),
            backgroundColor: Colors.green.shade700,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ أثناء حفظ الإعدادات: $e', style: const TextStyle(fontFamily: 'Cairo')),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _sendTestMessage() async {
    final phone = _testPhoneController.text.trim();
    final msg = _testMessageController.text.trim();

    if (phone.isEmpty || msg.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('يرجى كتابة رقم الهاتف والرسالة التجريبية', style: TextStyle(fontFamily: 'Cairo')),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => _isSendingTest = true);
    try {
      final res = await widget.apiService.sendWhatsAppTextMessage(phone: phone, message: msg);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(res['message'] ?? 'تم إرسال الرسالة بنجاح 🚀',
                style: const TextStyle(fontFamily: 'Cairo')),
            backgroundColor: Colors.green.shade700,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('فشل الإرسال: $e', style: const TextStyle(fontFamily: 'Cairo')),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSendingTest = false);
    }
  }

  Uint8List? _getQrBytes() {
    if (_qrDataUrl.contains(',')) {
      try {
        final base64Str = _qrDataUrl.split(',').last;
        return base64Decode(base64Str);
      } catch (_) {}
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      backgroundColor: const Color(0xFF1E1E2E),
      child: Container(
        width: 720,
        height: 720,
        padding: const EdgeInsets.all(24),
        child: Directionality(
          textDirection: TextDirection.rtl,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.green.shade700.withOpacity(0.2),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.chat_bubble_outline_rounded, color: Colors.greenAccent, size: 28),
                  ),
                  const SizedBox(width: 14),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'مزود رسائل الواتساب وإدارة الاقتران 📱',
                          style: TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        Text(
                          'ربط واتساب المحل عبر رمز QR وإرسال التقارير المالية والتدقيق بنقرة زر',
                          style: TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 12,
                            color: Colors.white60,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close, color: Colors.white70),
                  ),
                ],
              ),
              const Divider(color: Colors.white24, height: 28),

              if (_isLoading)
                const Padding(
                  padding: EdgeInsets.all(40),
                  child: Center(
                    child: CircularProgressIndicator(color: Colors.greenAccent),
                  ),
                )
              else
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Status Card
                        _buildStatusCard(),
                        const SizedBox(height: 20),

                        // QR Code Scanner Box if waiting
                        if (!_isConnected && _hasQr) _buildQrSection(),

                        const SizedBox(height: 20),

                        // Default Phone Numbers Configuration
                        _buildSettingsSection(),

                        const SizedBox(height: 20),

                        // Test Message Section
                        _buildTestSection(),
                      ],
                    ),
                  ),
                ),

              const Divider(color: Colors.white24, height: 28),

              // Action buttons
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton.icon(
                    onPressed: _checkStatusAndQr,
                    icon: const Icon(Icons.refresh, color: Colors.cyanAccent),
                    label: const Text('تحديث الحالة 🔄',
                        style: TextStyle(fontFamily: 'Cairo', color: Colors.cyanAccent)),
                  ),
                  const Spacer(),
                  ElevatedButton.icon(
                    onPressed: _isSaving ? null : _saveSettings,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green.shade600,
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    icon: _isSaving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.save_rounded, color: Colors.white),
                    label: const Text(
                      'حفظ الإعدادات 💾',
                      style: TextStyle(
                          fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 14, color: Colors.white),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusCard() {
    final statusColor = _isConnected ? Colors.greenAccent : (_hasQr ? Colors.amberAccent : Colors.redAccent);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: statusColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: statusColor.withOpacity(0.4), width: 1.5),
      ),
      child: Row(
        children: [
          Icon(
            _isConnected ? Icons.check_circle_rounded : Icons.sensors_off_rounded,
            color: statusColor,
            size: 36,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      _isConnected ? 'سيرفر الواتساب مقترن ومتصل 🟢' : 'سيرفر الواتساب غير مقترن 🔴',
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: statusColor,
                      ),
                    ),
                    if (_connectedPhone.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.black38,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          _connectedPhone,
                          style: const TextStyle(fontFamily: 'Cairo', color: Colors.white, fontSize: 13),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  _statusText,
                  style: const TextStyle(fontFamily: 'Cairo', fontSize: 13, color: Colors.white70),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQrSection() {
    final qrBytes = _getQrBytes();

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        children: [
          const Text(
            'افتح الواتساب في الجوال > الأجهزة المرتبطة > ثم امسح هذا الرمز 📲',
            style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, color: Colors.amberAccent, fontSize: 14),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          if (qrBytes != null)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 10)],
              ),
              child: Image.memory(qrBytes, width: 220, height: 220, fit: BoxFit.contain),
            )
          else
            const CircularProgressIndicator(color: Colors.amberAccent),
          const SizedBox(height: 12),
          const Text(
            'يتم تحديث الرمز تلقائياً كل 4 ثوانٍ حتى اكتمال الاقتران',
            style: TextStyle(fontFamily: 'Cairo', color: Colors.white54, fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingsSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.04),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.contact_phone_rounded, color: Colors.blueAccent, size: 20),
              SizedBox(width: 8),
              Text(
                'أرقام المستلمبن الافتراضية للتقارير 📋',
                style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 15, color: Colors.white),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _financialPhoneController,
                  style: const TextStyle(fontFamily: 'Cairo', color: Colors.white),
                  decoration: InputDecoration(
                    labelText: 'رقم مسؤول التقارير المالية 💰',
                    labelStyle: const TextStyle(fontFamily: 'Cairo', color: Colors.white70),
                    hintText: 'مثال: 967770000000',
                    hintStyle: const TextStyle(fontFamily: 'Cairo', color: Colors.white30),
                    prefixIcon: const Icon(Icons.attach_money_rounded, color: Colors.greenAccent),
                    filled: true,
                    fillColor: Colors.black26,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  keyboardType: TextInputType.phone,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _auditPhoneController,
                  style: const TextStyle(fontFamily: 'Cairo', color: Colors.white),
                  decoration: InputDecoration(
                    labelText: 'رقم مسؤول تقارير التدقيق والمراقبة 🛡️',
                    labelStyle: const TextStyle(fontFamily: 'Cairo', color: Colors.white70),
                    hintText: 'مثال: 967770000000',
                    hintStyle: const TextStyle(fontFamily: 'Cairo', color: Colors.white30),
                    prefixIcon: const Icon(Icons.security_rounded, color: Colors.amberAccent),
                    filled: true,
                    fillColor: Colors.black26,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  keyboardType: TextInputType.phone,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTestSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.04),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.send_rounded, color: Colors.purpleAccent, size: 20),
              SizedBox(width: 8),
              Text(
                'اختبار إرسال رسالة مباشرة عبر الواتساب 🚀',
                style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 15, color: Colors.white),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                flex: 2,
                child: TextField(
                  controller: _testPhoneController,
                  style: const TextStyle(fontFamily: 'Cairo', color: Colors.white),
                  decoration: InputDecoration(
                    labelText: 'رقم التجربة (مع مفتاح الدولة)',
                    labelStyle: const TextStyle(fontFamily: 'Cairo', color: Colors.white70),
                    prefixIcon: const Icon(Icons.phone_android, color: Colors.purpleAccent),
                    filled: true,
                    fillColor: Colors.black26,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  keyboardType: TextInputType.phone,
                ),
              ),
              const SizedBox(width: 12),
              ElevatedButton.icon(
                onPressed: _isSendingTest || !_isConnected ? null : _sendTestMessage,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.purple.shade600,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                icon: _isSendingTest
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.send_rounded, color: Colors.white, size: 18),
                label: const Text('إرسال اختبار ⚡', style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, color: Colors.white)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _testMessageController,
            maxLines: 2,
            style: const TextStyle(fontFamily: 'Cairo', color: Colors.white, fontSize: 13),
            decoration: InputDecoration(
              labelText: 'نص الرسالة التجريبية',
              labelStyle: const TextStyle(fontFamily: 'Cairo', color: Colors.white70),
              filled: true,
              fillColor: Colors.black26,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ],
      ),
    );
  }
}
