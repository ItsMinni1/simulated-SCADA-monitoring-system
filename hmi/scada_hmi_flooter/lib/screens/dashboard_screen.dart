import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/websocket_service.dart';
import '../widgets/sensor_card.dart';
import 'sensor_detail_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  late WebSocketService _webSocketService;

  @override
  void initState() {
    super.initState();
    _webSocketService = Provider.of<WebSocketService>(context, listen: false);
    _webSocketService.connect();
    _webSocketService.loadInitialSensors(); // Load initial sensor data from Postgres DSN history
  }

  @override
  void dispose() {
    _webSocketService.disconnect();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('SCADA Dashboard'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Alpha'),
              Tab(text: 'Beta'),
              Tab(text: 'Gamma'),
            ],
          ),
        ),
        body: Consumer<WebSocketService>(
          builder: (context, wsService, child) {
            // Only show loader if we are actively fetching history and have no local cache
            if (wsService.isLoadingHistory && wsService.sensors.isEmpty) {
              return const Center(child: CircularProgressIndicator());
            }

            // If history load is complete but no sensors are found, show standby card
            if (wsService.sensors.isEmpty) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.sensors_off_rounded,
                        size: 72,
                        color: Colors.white.withOpacity(0.25),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        'Telemetry Pipeline Idle',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.white.withOpacity(0.85),
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Database logs and live WebSocket feeds are currently empty. Start the SCADA simulators and pipeline to view real-time grid metrics.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.white.withOpacity(0.5),
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 30),
                      ElevatedButton.icon(
                        onPressed: () {
                          wsService.loadInitialSensors();
                        },
                        icon: const Icon(Icons.refresh),
                        label: const Text('Retry History Sync'),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }

            Widget buildSensorList(String idFilter) {
              final sensors = wsService.sensors.values
                  .where((s) => s.id.contains(idFilter))
                  .toList();
                  
              if (sensors.isEmpty) {
                return const Center(
                  child: Text(
                    'No active sensors on this grid branch.',
                    style: TextStyle(color: Colors.white54),
                  ),
                );
              }
              
              return ListView(
                padding: const EdgeInsets.symmetric(vertical: 8),
                children: sensors.map((sensor) {
                  return SensorCard(
                    sensor: sensor,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => SensorDetailScreen(sensorId: sensor.id),
                      ),
                    ),
                  );
                }).toList(),
              );
            }

            return TabBarView(
              children: [
                buildSensorList('ALPHA'),
                buildSensorList('BETA'),
                buildSensorList('GAMMA'),
              ],
            );
          },
        ),
      ),
    );
  }
}
