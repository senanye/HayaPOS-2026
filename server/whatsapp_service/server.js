const express = require('express');
const cors = require('cors');
const QRCode = require('qrcode');
const pino = require('pino');
const {
  default: makeWASocket,
  useMultiFileAuthState,
  DisconnectReason,
  fetchLatestBaileysVersion
} = require('@whiskeysockets/baileys');

const app = express();
app.use(cors());
app.use(express.json({ limit: '50mb' }));

const PORT = 9001;

let sock = null;
let currentQrDataUrl = '';
let isConnected = false;
let connectedUser = '';
let connectionStatusText = 'جاري تشغيل سيرفر الواتساب الخفي... 🔄';

async function connectToWhatsApp() {
  try {
    const { state, saveCreds } = await useMultiFileAuthState('auth_info_baileys');
    const { version } = await fetchLatestBaileysVersion();

    sock = makeWASocket({
      version,
      auth: state,
      printQRInTerminal: true,
      logger: pino({ level: 'silent' }),
      browser: ['Haya POS Engine', 'Chrome', '1.0.0']
    });

    sock.ev.on('creds.update', saveCreds);

    sock.ev.on('connection.update', async (update) => {
      const { connection, lastDisconnect, qr } = update;

      if (qr) {
        try {
          currentQrDataUrl = await QRCode.toDataURL(qr);
          isConnected = false;
          connectionStatusText = 'يرجى مسح رمز QR لربط سيرفر الواتساب الخفي 📲';
          console.log('[WhatsApp Engine] New QR code generated for pairing.');
        } catch (qrErr) {
          console.error('[WhatsApp Engine] Error generating QR Data URL:', qrErr);
        }
      }

      if (connection === 'open') {
        isConnected = true;
        currentQrDataUrl = '';
        connectedUser = sock.user ? sock.user.id.split(':')[0] : 'مقترن';
        connectionStatusText = `سيرفر الواتساب متصل ومقترن بالرقم (+${connectedUser}) 🟢`;
        console.log(`[WhatsApp Engine] Connected successfully as +${connectedUser}`);
      }

      if (connection === 'close') {
        isConnected = false;
        const statusCode = lastDisconnect?.error?.output?.statusCode;
        const shouldReconnect = statusCode !== DisconnectReason.loggedOut;

        console.log(`[WhatsApp Engine] Connection closed. Reason code: ${statusCode}. Reconnecting: ${shouldReconnect}`);
        connectionStatusText = 'انقطع الاتصال بالسيرفر، جاري المحاولة لإعادة الربط... 🟡';

        if (shouldReconnect) {
          setTimeout(connectToWhatsApp, 3000);
        } else {
          connectionStatusText = 'تم تسجيل الخروج، يرجى إعادة مسح رمز QR 🔴';
        }
      }
    });
  } catch (err) {
    console.error('[WhatsApp Engine] Initialization error:', err);
    connectionStatusText = 'خطأ في تشغيل محرك الواتساب، جاري المحاولة... ⚠️';
    setTimeout(connectToWhatsApp, 5000);
  }
}

// REST Endpoints
app.get('/status', (req, res) => {
  res.json({
    connected: isConnected,
    phone: connectedUser ? `+${connectedUser}` : '',
    statusText: connectionStatusText,
    hasQr: !!currentQrDataUrl
  });
});

app.get('/qr', (req, res) => {
  res.json({
    status: isConnected ? 'connected' : (currentQrDataUrl ? 'qr_ready' : 'waiting'),
    qrDataUrl: currentQrDataUrl,
    message: isConnected ? 'سيرفر الواتساب مقترن وجاهز' : 'افتح الواتساب من الجوال واختَر الأجهزة المرتبطة لمسح الرمز'
  });
});

app.post('/send-message', async (req, res) => {
  try {
    if (!sock || !isConnected) {
      return res.status(400).json({ error: 'سيرفر الواتساب غير متصل. يرجى مسح رمز QR أولاً.' });
    }

    let { phone, message } = req.body;
    if (!phone || !message) {
      return res.status(400).json({ error: 'يرجى تحديد رقم الهاتف والرسالة' });
    }

    let cleanPhone = phone.toString().replace(/\D/g, '');
    let jid = `${cleanPhone}@s.whatsapp.net`;

    await sock.sendMessage(jid, { text: message });

    res.json({
      status: 'success',
      message: `تم إرسال الرسالة بنجاح إلى الرقم (+${cleanPhone}) عبر سيرفر الواتساب 🚀`
    });
  } catch (err) {
    console.error('[WhatsApp Engine] Send message error:', err);
    res.status(500).json({ error: `فشل الإرسال عبر الواتساب: ${err.message}` });
  }
});

app.post('/send-pdf', async (req, res) => {
  try {
    if (!sock || !isConnected) {
      return res.status(400).json({ error: 'سيرفر الواتساب غير متصل. يرجى مسح رمز QR أولاً.' });
    }

    let { phone, caption, pdfBase64, filename } = req.body;
    if (!phone) {
      return res.status(400).json({ error: 'يرجى إدخال رقم الهاتف' });
    }

    let cleanPhone = phone.toString().replace(/\D/g, '');
    let jid = `${cleanPhone}@s.whatsapp.net`;
    let docFileName = filename || `Report_${Date.now()}.pdf`;

    if (pdfBase64) {
      const buffer = Buffer.from(pdfBase64, 'base64');
      await sock.sendMessage(jid, {
        document: buffer,
        fileName: docFileName,
        mimetype: 'application/pdf',
        caption: caption || 'التقرير المالي - نظام هيا POS'
      });
    } else {
      // Send text report summary if no pdf binary attached
      await sock.sendMessage(jid, { text: caption || 'التقرير المالي' });
    }

    res.json({
      status: 'success',
      message: `تم تحويل التقرير إلى PDF وإرساله مباشرةً لرقم الواتساب (+${cleanPhone}) عبر السيرفر الخفي بنجاح! 🚀`
    });
  } catch (err) {
    console.error('[WhatsApp Engine] Send PDF error:', err);
    res.status(500).json({ error: `فشل إرسال ملف PDF عبر الواتساب: ${err.message}` });
  }
});

app.listen(PORT, () => {
  console.log(`=======================================================`);
  console.log(`[Haya POS] WhatsApp Direct Socket Engine running on port ${PORT}`);
  console.log(`=======================================================`);
  connectToWhatsApp();
});
