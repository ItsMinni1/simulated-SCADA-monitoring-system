import 'package:flutter/material.dart';
import '../models/alert.dart';
import '../services/api_service.dart';

class AlertsScreen extends StatefulWidget {
  const AlertsScreen({super.key});

  @override
  State<AlertsScreen> createState() => _AlertsScreenState();
}

class _AlertsScreenState extends State<AlertsScreen> {
  final ApiService apiService = ApiService();
  late Future<List<Alert>> _alertsFuture;

  @override
  void initState() {
    super.initState();
    _alertsFuture = apiService.getAlerts();
  }

  Color _getSeverityColor(String severity) {
    switch (severity.toUpperCase()) {
      case 'CRITICAL':
        return Colors.red;
      case 'WARNING':
        return Colors.orange;
      case 'NORMAL':
      case 'INFO':
        return Colors.green;
      default:
        return Colors.blue;
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Alerts Log'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Alpha'),
              Tab(text: 'Beta'),
              Tab(text: 'Gamma'),
            ],
          ),
        ),
        body: FutureBuilder<List<Alert>>(
          future: _alertsFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            } else if (snapshot.hasError) {
              return Center(child: Text('Error: ${snapshot.error}'));
            } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
              return const Center(child: Text('No alerts found.'));
            }

            final alerts = snapshot.data!;

            Widget buildAlertList(String idFilter) {
              final filteredAlerts = alerts.where((a) => a.sensorId.contains(idFilter)).toList();

              if (filteredAlerts.isEmpty) {
                return const Center(child: Text('No alerts for this substation.'));
              }

              return ListView.builder(
                itemCount: filteredAlerts.length,
                itemBuilder: (context, index) {
                  final alert = filteredAlerts[index];
                  final severityColor = _getSeverityColor(alert.severity);

                  return Card(
                    margin: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
                    child: ListTile(
                      leading: Icon(Icons.warning, color: severityColor),
                      title: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(child: Text('Sensor: ${alert.sensorId}', overflow: TextOverflow.ellipsis)),
                          Chip(
                            label: Text(
                              alert.severity,
                              style: const TextStyle(color: Colors.white, fontSize: 12),
                            ),
                            backgroundColor: severityColor,
                            padding: EdgeInsets.zero,
                          ),
                        ],
                      ),
                      subtitle: Text('Time: ${alert.eventTime}\nVoltage: ${alert.voltageVal} V | Current: ${alert.currentVal} A'),
                      isThreeLine: true,
                    ),
                  );
                },
              );
            }

            return TabBarView(
              children: [
                buildAlertList('ALPHA'),
                buildAlertList('BETA'),
                buildAlertList('GAMMA'),
              ],
            );
          },
        ),
      ),
    );
  }
}