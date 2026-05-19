import 'package:flutter/material.dart';

class AppConstants {
  static const String baseUrl = 'http://127.0.0.1:8000';
  static const String websocketUrl = 'ws://127.0.0.1:8000/ws/live';
  static const String historyEndpoint = '/api/history';
  static const String alertsEndpoint = '/api/alerts';

  // Design Constants
  static const primaryColor = Color(0xFF6B5AE0); // Sleek Purple
  static const secondaryColor = Color(0xFF242444); // Deep Blue-Purple
  static const bgColor = Color(0xFF1B1B2F); // Dark Night
  
  static const darkBlue = Color(0xFF2697FF);
  static const lightPurple = Color(0xFFA29BFE);
  
  static const defaultPadding = 16.0;
}

