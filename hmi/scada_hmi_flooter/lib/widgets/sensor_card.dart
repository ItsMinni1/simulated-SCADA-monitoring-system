import 'package:flutter/material.dart';
import '../models/sensor.dart';
import 'status_indicator.dart';

class SensorCard extends StatelessWidget {
  final Sensor sensor;
  final VoidCallback onTap;

  const SensorCard({super.key, required this.sensor, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = sensor.latestTelemetry;
    return Card(
      elevation: 3,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: ListTile(
        onTap: onTap,
        leading: StatusIndicator(status: sensor.status),
        title: Text('Sensor ID: ${sensor.id}', style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text('V: ${t.voltage.toStringAsFixed(2)} | F: ${t.frequency.toStringAsFixed(2)} | C: ${t.current.toStringAsFixed(2)}'),
        trailing: const Icon(Icons.chevron_right),
      ),
    );
  }
}