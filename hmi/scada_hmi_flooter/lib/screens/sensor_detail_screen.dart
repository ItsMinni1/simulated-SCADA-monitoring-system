import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:provider/provider.dart';
import '../services/websocket_service.dart';
import '../services/api_service.dart';
import '../widgets/telemetry_chart.dart';
import '../widgets/status_indicator.dart';
import '../models/sensor.dart';
import '../utils/constants.dart';

class SensorDetailScreen extends StatefulWidget {
  final String sensorId;
  const SensorDetailScreen({super.key, required this.sensorId});

  @override
  State<SensorDetailScreen> createState() => _SensorDetailScreenState();
}

class _SensorDetailScreenState extends State<SensorDetailScreen> {
  final ApiService _apiService = ApiService();
  late WebSocketService _webSocketService;
  
  List<Map<String, dynamic>> _historyData = [];
  bool _isLoadingHistory = true;
  bool _isSubscribed = false;
  
  String _selectedMetric = 'voltage'; // 'voltage', 'current', 'frequency'
  int _selectedTimeframeMinutes = 60; // 15, 60, 360, 1440

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_isSubscribed) {
      _webSocketService = Provider.of<WebSocketService>(context, listen: false);
      _webSocketService.addListener(_onWebSocketUpdate);
      _isSubscribed = true;
    }
  }

  @override
  void dispose() {
    if (_isSubscribed) {
      _webSocketService.removeListener(_onWebSocketUpdate);
    }
    super.dispose();
  }

  Future<void> _loadHistory() async {
    try {
      final history = await _apiService.getSensorHistory(
        widget.sensorId,
        minutes: _selectedTimeframeMinutes,
      );
      setState(() {
        _historyData = history;
        _isLoadingHistory = false;
      });
    } catch (e) {
      debugPrint('Error loading history: $e');
      setState(() {
        _isLoadingHistory = false;
      });
    }
  }

  void _onWebSocketUpdate() {
    final sensor = _webSocketService.sensors[widget.sensorId];
    if (sensor != null) {
      final newTelemetry = sensor.latestTelemetry;
      final timeStr = newTelemetry.timestamp;
      final time = DateTime.tryParse(timeStr) ?? DateTime.now();

      setState(() {
        // Prevent duplicate logs for the same timestamp
        final exists = _historyData.any((element) {
          final elementTime = DateTime.tryParse(element['time'] ?? '');
          return elementTime != null && elementTime.isAtSameMomentAs(time);
        });

        if (!exists) {
          _historyData.add({
            'time': time.toIso8601String(),
            'voltage': newTelemetry.voltage,
            'current': newTelemetry.current,
            'frequency': newTelemetry.frequency,
          });

          // Limit local cache size for performance
          if (_historyData.length > 500) {
            _historyData.removeAt(0);
          }
        }
      });
    }
  }

  List<FlSpot> _getSelectedSpots() {
    return _historyData.map((data) {
      final timeVal = DateTime.tryParse(data['time'] ?? '')?.millisecondsSinceEpoch.toDouble() ?? 0.0;
      final val = (data[_selectedMetric] ?? 0.0).toDouble();
      return FlSpot(timeVal, val);
    }).toList();
  }

  String _getMetricUnit() {
    switch (_selectedMetric) {
      case 'voltage':
        return 'V';
      case 'current':
        return 'A';
      case 'frequency':
        return 'Hz';
      default:
        return '';
    }
  }

  String _getMetricTitle() {
    switch (_selectedMetric) {
      case 'voltage':
        return 'Voltage';
      case 'current':
        return 'Current';
      case 'frequency':
        return 'Frequency';
      default:
        return '';
    }
  }

  Widget _buildMetricSelector() {
    final metrics = [
      {'key': 'voltage', 'label': 'Voltage', 'unit': 'V'},
      {'key': 'current', 'label': 'Current', 'unit': 'A'},
      {'key': 'frequency', 'label': 'Frequency', 'unit': 'Hz'},
    ];

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
      decoration: BoxDecoration(
        color: AppConstants.secondaryColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: metrics.map((metric) {
          final isSelected = _selectedMetric == metric['key'];
          return GestureDetector(
            onTap: () {
              setState(() {
                _selectedMetric = metric['key']!;
              });
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeInOut,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: isSelected ? AppConstants.primaryColor : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
                boxShadow: isSelected
                    ? [
                        BoxShadow(
                          color: AppConstants.primaryColor.withOpacity(0.4),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        )
                      ]
                    : [],
              ),
              child: Text(
                '${metric['label']} (${metric['unit']})',
                style: TextStyle(
                  color: isSelected ? Colors.white : Colors.white70,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildTimeframeSelector() {
    final timeframes = [
      {'minutes': 15, 'label': '15m'},
      {'minutes': 60, 'label': '1h'},
      {'minutes': 360, 'label': '6h'},
      {'minutes': 1440, 'label': '24h'},
    ];

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
      decoration: BoxDecoration(
        color: AppConstants.secondaryColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: timeframes.map((tf) {
          final isSelected = _selectedTimeframeMinutes == tf['minutes'];
          return GestureDetector(
            onTap: () {
              if (_selectedTimeframeMinutes != tf['minutes']) {
                setState(() {
                  _selectedTimeframeMinutes = tf['minutes'] as int;
                  _isLoadingHistory = true;
                });
                _loadHistory();
              }
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeInOut,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: isSelected ? AppConstants.primaryColor : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                tf['label'] as String,
                style: TextStyle(
                  color: isSelected ? Colors.white : Colors.white70,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildStatusCard(Sensor? sensor) {
    final status = sensor?.status ?? 'UNKNOWN';
    final latest = sensor?.latestTelemetry;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppConstants.secondaryColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.white.withOpacity(0.05),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Substation Sensor Readout',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.6),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.2,
                ),
              ),
              Row(
                children: [
                  StatusIndicator(status: status),
                  const SizedBox(width: 8),
                  Text(
                    status.toUpperCase(),
                    style: TextStyle(
                      color: status.toUpperCase() == 'CRITICAL' || status.toUpperCase() == 'ANOMALY'
                          ? Colors.redAccent
                          : status.toUpperCase() == 'WARNING'
                              ? Colors.orangeAccent
                              : Colors.greenAccent,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            widget.sensorId,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
            ),
          ),
          if (latest != null) ...[
            const SizedBox(height: 16),
            const Divider(color: Colors.white12, height: 1),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildReadoutItem('VOLTAGE', latest.voltage, 'V', Colors.blueAccent),
                _buildReadoutItem('CURRENT', latest.current, 'A', Colors.orangeAccent),
                _buildReadoutItem('FREQUENCY', latest.frequency, 'Hz', Colors.tealAccent),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildReadoutItem(String label, double value, String unit, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withOpacity(0.5),
            fontSize: 10,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(height: 4),
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              value.toStringAsFixed(2),
              style: TextStyle(
                color: color,
                fontSize: 18,
                fontWeight: FontWeight.bold,
                fontFamily: 'monospace',
              ),
            ),
            const SizedBox(width: 2),
            Text(
              unit,
              style: TextStyle(
                color: Colors.white.withOpacity(0.7),
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppConstants.bgColor,
      appBar: AppBar(
        title: Text('Sensor Detail - ${widget.sensorId}'),
        backgroundColor: AppConstants.bgColor,
        elevation: 0,
      ),
      body: Consumer<WebSocketService>(
        builder: (context, wsService, child) {
          final sensor = wsService.sensors[widget.sensorId];

          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 8),
                _buildStatusCard(sensor),
                const SizedBox(height: 24),
                
                // Controls Row
                LayoutBuilder(
                  builder: (context, constraints) {
                    final bool isWide = constraints.maxWidth > 600;
                    if (isWide) {
                      return Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          _buildMetricSelector(),
                          _buildTimeframeSelector(),
                        ],
                      );
                    } else {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildMetricSelector(),
                          const SizedBox(height: 12),
                          _buildTimeframeSelector(),
                        ],
                      );
                    }
                  },
                ),
                const SizedBox(height: 24),

                // Chart Container
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.only(top: 20, right: 16, left: 8, bottom: 8),
                    decoration: BoxDecoration(
                      color: AppConstants.secondaryColor.withOpacity(0.5),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: Colors.white.withOpacity(0.03),
                      ),
                    ),
                    child: _isLoadingHistory
                        ? const Center(child: CircularProgressIndicator())
                        : _historyData.isEmpty
                            ? const Center(
                                child: Text(
                                  'No data available',
                                  style: TextStyle(color: Colors.white70),
                                ),
                              )
                            : TelemetryChart(
                                dataPoints: _getSelectedSpots(),
                                title: '${_getMetricTitle()} Timeline',
                                metricName: _selectedMetric,
                                unit: _getMetricUnit(),
                              ),
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
          );
        },
      ),
    );
  }
}