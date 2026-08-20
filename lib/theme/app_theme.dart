import 'package:flutter/material.dart';

class AppTheme {
  // Princess (الأميرة للأحذية والشنط النسائية) Royal Magenta & Olive Green Palette
  static const Color primary = Color(0xFF9C0E62); // Royal Magenta from Logo
  static const Color primaryLight = Color(0xFFC2185B); // Bright Fuchsia / Rose
  static const Color primaryDark = Color(0xFF5E0539); // Deep Magenta Wine
  static const Color primaryAccent = Color(0xFFE91E63); // Vivid Accent
  
  static const Color secondary = Color(0xFF5B7B32); // Olive Green from Logo
  static const Color secondaryLight = Color(0xFF7CB342); // Leaf Green
  static const Color secondaryDark = Color(0xFF3E5421); // Dark Olive

  static const Color slateDark = Color(0xFF140813); // Deep Luxury Charcoal-Plum
  static const Color slateCard = Color(0xFF220E1E); // Card Surface
  static const Color slateBorder = Color(0xFF4A183C); // Plum Border
  
  static const Color redMaroon = Color(0xFF5E0539);
  static const Color redCard = Color(0xFF280E23);
  static const Color redBorder = Color(0xFF4E163E);
  static const Color redAccent = Color(0xFF9C0E62);
  static const Color redBright = Color(0xFFC2185B);
  
  static const Color textPrimary = Color(0xFFFDF2F8);
  static const Color textSecondary = Color(0xFFE8BCD9);
  static const Color textMuted = Color(0xFFAA88A0);

  // Background Gradient: Luxury Plum-Magenta Dark
  static const BoxDecoration backgroundDecoration = BoxDecoration(
    gradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        Color(0xFF140712), // Deep Plum Charcoal top
        Color(0xFF240B1E), // Transition
        Color(0xFF3B0C2B), // Deep Royal Magenta bottom
      ],
    ),
  );

  // Sidebar Drawer Gradient
  static const BoxDecoration sidebarDecoration = BoxDecoration(
    gradient: LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        Color(0xFF1B0718),
        Color(0xFF280C23),
        Color(0xFF380D2D),
      ],
    ),
  );

  // Card Decoration
  static BoxDecoration cardDecoration({Color? borderColor}) {
    return BoxDecoration(
      color: const Color(0xFF240E20),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: borderColor ?? const Color(0xFF4D183E), width: 1),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.3),
          blurRadius: 8,
          offset: const Offset(0, 4),
        ),
      ],
    );
  }
}

