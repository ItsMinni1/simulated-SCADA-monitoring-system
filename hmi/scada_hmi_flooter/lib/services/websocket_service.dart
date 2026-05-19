import 'dart:convert';
import 'dart:developer';
import 'package:flutter/material.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../models/sensor.dart';
import '../models/telemetry.dart';
import '../utils/constants.dart';
import 'api_service.dart';

class WebSocketService extends ChangeNotifier {
  late WebSocketChannel _channel;
  Map<String, Sensor> sensors = {};
  
  final ApiService _apiService = ApiService();
  bool isLoadingHistory = true;

  Future<void> loadInitialSensors() async {
    Future.microtask(() {
      if (!isLoadingHistory) {
        isLoadingHistory = true;
        notifyListeners();
      }
    });

    try {
      final history = await _apiService.getHistory();
      
      // Seed with the latest known telemetry for each unique sensor
      for (var record in history) {
        final String sensorId = record['sensor_id'];
        if (!sensors.containsKey(sensorId)) {
          sensors[sensorId] = Sensor(
            id: sensorId,
            status: record['status'] ?? 'OK',
            latestTelemetry: Telemetry.fromJson(record),
          );
        }
      }
    } catch (e) {
      log("Failed to load initial history: $e");
    } finally {
      isLoadingHistory = false;
      notifyListeners();
    }
  }

  void connect() {
    _channel = WebSocketChannel.connect(Uri.parse(AppConstants.websocketUrl));
    _channel.stream.listen(
      (message) {
        final data = jsonDecode(message);
        final String sensorId = data['sensor_id'];

        final telemetry = Telemetry.fromJson(data);
        final status = data['status'] ?? 'OK';

        if (sensors.containsKey(sensorId)) {
          sensors[sensorId]!.latestTelemetry = telemetry;
          sensors[sensorId]!.status = status;
        } else {
          sensors[sensorId] = Sensor(
            id: sensorId,
            status: status,
            latestTelemetry: telemetry,
          );
        }
        notifyListeners();
      },
      onError: (error) {
        log('WebSocket Error: $error');
      },
    );
  }

  void disconnect() {
    _channel.sink.close();
  }
}
