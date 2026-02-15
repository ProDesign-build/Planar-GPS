
import 'package:flutter/material.dart';
import 'app_theme.dart';

class UiUtils {
  static void showSuccessSnackBar(BuildContext context, String message) {
    _showSnackBar(
      context, 
      message, 
      color: AppTheme.success, 
      icon: Icons.check_circle_outline
    );
  }

  static void showErrorSnackBar(BuildContext context, String message) {
    _showSnackBar(
      context, 
      message, 
      color: AppTheme.error, 
      icon: Icons.error_outline
    );
  }

  static void showInfoSnackBar(BuildContext context, String message) {
    _showSnackBar(
      context, 
      message, 
      color: AppTheme.accent, 
      icon: Icons.info_outline
    );
  }

  static void _showSnackBar(
    BuildContext context, 
    String message, {
    required Color color,
    required IconData icon,
    Duration duration = const Duration(seconds: 3),
  }) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(icon, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
        margin: const EdgeInsets.all(16),
        duration: duration,
        elevation: 4,
        showCloseIcon: true,
        closeIconColor: Colors.white,
      ),
    );
  }
}
