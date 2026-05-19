import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/alert.dart';
import '../utils/constants.dart';

class ApiService {
  Future<List<Map<String, dynamic>>> getHistory() async {
    final response = await http.get(
      Uri.parse('${AppConstants.baseUrl}${AppConstants.historyEndpoint}'),
    );
    if (response.statusCode == 200) {
      final decoded = jsonDecode(response.body);
      return List<Map<String, dynamic>>.from(decoded['data']);
    } else {
      throw Exception('Failed to load history');
    }
  }

  Future<List<Alert>> getAlerts() async {
    final response = await http.get(
      Uri.parse('${AppConstants.baseUrl}${AppConstants.alertsEndpoint}'),
    );
    if (response.statusCode == 200) {
      final decoded = jsonDecode(response.body);
      final List data = decoded['data'];
      return data.map((json) => Alert.fromJson(json)).toList();
    } else {
       throw Exception('Failed to load alerts');
    }
  }

  Future<List<Map<String, dynamic>>> getSensorHistory(String sensorId, {int minutes = 60}) async {
    final response = await http.get(
      Uri.parse('${AppConstants.baseUrl}/api/telemetry/history/$sensorId?minutes=$minutes'),
    );
    if (response.statusCode == 200) {
      final decoded = jsonDecode(response.body);
      return List<Map<String, dynamic>>.from(decoded['data']);
    } else {
      throw Exception('Failed to load sensor history');
    }
  }
}
