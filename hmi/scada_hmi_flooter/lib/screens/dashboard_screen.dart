import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:fl_chart/fl_chart.dart';
import '../services/websocket_service.dart';
import '../services/api_service.dart';
import '../widgets/sensor_card.dart';
import '../widgets/telemetry_chart.dart';
import '../widgets/multi_telemetry_chart.dart';
import '../widgets/status_indicator.dart';
import '../utils/constants.dart';
import 'sensor_detail_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final ApiService _apiService = ApiService();
  late WebSocketService _webSocketService;
  bool _isSubscribed = false;

  final Map<String, List<Map<String, dynamic>>> _substationHistories = {
    'SUBSTATION_ALPHA_01': [],
    'SUBSTATION_BETA_02': [],
    'SUBSTATION_GAMMA_03': [],
  };

  bool _isLoadingHistories = true;
  String _selectedMetric = 'voltage'; // 'voltage', 'current'
  int _selectedTimeframeMinutes = 60; // 15, 60, 360, 1440

  @override
  void initState() {
    super.initState();
    _loadHistories();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_isSubscribed) {
      _webSocketService = Provider.of<WebSocketService>(context, listen: false);
      _webSocketService.connect();
      _webSocketService.loadInitialSensors();
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

  Future<void> _loadHistories() async {
    setState(() {
      _isLoadingHistories = true;
    });
    try {
      final alpha = await _apiService.getSensorHistory('SUBSTATION_ALPHA_01', minutes: _selectedTimeframeMinutes);
      final beta = await _apiService.getSensorHistory('SUBSTATION_BETA_02', minutes: _selectedTimeframeMinutes);
      final gamma = await _apiService.getSensorHistory('SUBSTATION_GAMMA_03', minutes: _selectedTimeframeMinutes);

      setState(() {
        _substationHistories['SUBSTATION_ALPHA_01'] = alpha;
        _substationHistories['SUBSTATION_BETA_02'] = beta;
        _substationHistories['SUBSTATION_GAMMA_03'] = gamma;
        _isLoadingHistories = false;
      });
    } catch (e) {
      debugPrint('Error loading substation histories: $e');
      setState(() {
        _isLoadingHistories = false;
      });
    }
  }

  void _onWebSocketUpdate() {
    final substations = ['SUBSTATION_ALPHA_01', 'SUBSTATION_BETA_02', 'SUBSTATION_GAMMA_03'];
    setState(() {
      for (var subId in substations) {
        final sensor = _webSocketService.sensors[subId];
        if (sensor != null) {
          final newTelemetry = sensor.latestTelemetry;
          final timeStr = newTelemetry.timestamp;
          final time = DateTime.tryParse(timeStr) ?? DateTime.now();

          final historyList = _substationHistories[subId] ?? [];
          final exists = historyList.any((element) {
            final elementTime = DateTime.tryParse(element['time'] ?? '');
            return elementTime != null && elementTime.isAtSameMomentAs(time);
          });

          if (!exists) {
            historyList.add({
              'time': time.toIso8601String(),
              'voltage': newTelemetry.voltage,
              'current': newTelemetry.current,
              'frequency': newTelemetry.frequency,
            });

            // Ensure chronological sorting of the history buffer
            historyList.sort((a, b) {
              final ta = DateTime.tryParse(a['time'] ?? '') ?? DateTime.now();
              final tb = DateTime.tryParse(b['time'] ?? '') ?? DateTime.now();
              return ta.compareTo(tb);
            });

            if (historyList.length > 500) {
              historyList.removeAt(0);
            }
            _substationHistories[subId] = historyList;
          }
        }
      }
    });
  }

  String _getSubstationId(String idFilter) {
    if (idFilter.toUpperCase().contains('ALPHA')) {
      return 'SUBSTATION_ALPHA_01';
    } else if (idFilter.toUpperCase().contains('BETA')) {
      return 'SUBSTATION_BETA_02';
    } else if (idFilter.toUpperCase().contains('GAMMA')) {
      return 'SUBSTATION_GAMMA_03';
    }
    return '';
  }

  Map<String, List<FlSpot>> _getMultiSpots() {
    final Map<String, List<FlSpot>> result = {};
    _substationHistories.forEach((subId, history) {
      final List<FlSpot> spots = history.map((data) {
        final timeVal = DateTime.tryParse(data['time'] ?? '')?.millisecondsSinceEpoch.toDouble() ?? 0.0;
        final val = (data[_selectedMetric] ?? 0.0).toDouble();
        return FlSpot(timeVal, val);
      }).toList();

      // Sort strictly chronologically by x (timestamp)
      spots.sort((a, b) => a.x.compareTo(b.x));

      String key = 'Alpha';
      if (subId.contains('BETA')) key = 'Beta';
      if (subId.contains('GAMMA')) key = 'Gamma';

      result[key] = spots;
    });
    return result;
  }

  Widget _buildMetricSelector() {
    final metrics = [
      {'key': 'voltage', 'label': 'Voltage', 'unit': 'V'},
      {'key': 'current', 'label': 'Current', 'unit': 'A'},
    ];

    return Container(
      padding: const EdgeInsets.all(4),
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
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: isSelected ? AppConstants.primaryColor : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '${metric['label']} (${metric['unit']})',
                style: TextStyle(
                  color: isSelected ? Colors.white : Colors.white70,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
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
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppConstants.secondaryColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: timeframes.map((tf) {
          final mins = tf['minutes'] as int;
          final label = tf['label'] as String;
          final isSelected = _selectedTimeframeMinutes == mins;
          return GestureDetector(
            onTap: () {
              setState(() {
                _selectedTimeframeMinutes = mins;
              });
              _loadHistories();
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: isSelected ? AppConstants.primaryColor : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                label,
                style: TextStyle(
                  color: isSelected ? Colors.white : Colors.white70,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildControls() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Wrap(
        spacing: 12,
        runSpacing: 12,
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          _buildMetricSelector(),
          _buildTimeframeSelector(),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppConstants.bgColor,
      body: SafeArea(
        child: Consumer<WebSocketService>(
          builder: (context, wsService, child) {
            if (wsService.sensors.isEmpty) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.wifi_off_rounded,
                        size: 48,
                        color: Colors.white.withOpacity(0.3),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Telemetry Pipeline Idle',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Please verify your grid simulators and docker containers are online to stream readings.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.5),
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 30),
                      ElevatedButton.icon(
                        onPressed: () {
                          wsService.loadInitialSensors();
                          _loadHistories();
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

            Widget buildSubstationTab(String idFilter) {
              final subId = _getSubstationId(idFilter);
              final sensors = wsService.sensors.values
                  .where((s) => s.id.contains(idFilter))
                  .toList();

              final history = _substationHistories[subId] ?? [];
              final List<FlSpot> spots = history.map((data) {
                final timeVal = DateTime.tryParse(data['time'] ?? '')?.millisecondsSinceEpoch.toDouble() ?? 0.0;
                final val = (data[_selectedMetric] ?? 0.0).toDouble();
                return FlSpot(timeVal, val);
              }).toList();

              // Sort strictly chronologically by x (timestamp)
              spots.sort((a, b) => a.x.compareTo(b.x));

              final unit = _selectedMetric == 'voltage' ? 'V' : 'A';
              final label = _selectedMetric == 'voltage' ? 'Voltage' : 'Current';

              return SingleChildScrollView(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildControls(),
                    const SizedBox(height: 12),
                    Container(
                      height: 230,
                      margin: const EdgeInsets.symmetric(horizontal: 16),
                      padding: const EdgeInsets.only(top: 20, right: 16, left: 8, bottom: 8),
                      decoration: BoxDecoration(
                        color: AppConstants.secondaryColor.withOpacity(0.5),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: Colors.white.withOpacity(0.03),
                        ),
                      ),
                      child: _isLoadingHistories
                          ? const Center(child: CircularProgressIndicator())
                          : spots.isEmpty
                              ? const Center(
                                  child: Text('No telemetry history available',
                                      style: TextStyle(color: Colors.white54, fontSize: 13)),
                                )
                              : TelemetryChart(
                                  dataPoints: spots,
                                  title: '$idFilter Substation $label',
                                  metricName: _selectedMetric,
                                  unit: unit,
                                ),
                    ),
                    const SizedBox(height: 24),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16),
                      child: Text(
                        'Active Grid Sensors',
                        style: TextStyle(
                          color: Colors.white70,
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: sensors.length,
                      itemBuilder: (context, index) {
                        final sensor = sensors[index];
                        return Container(
                          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                          decoration: BoxDecoration(
                            color: AppConstants.secondaryColor.withOpacity(0.4),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: ListTile(
                            leading: StatusIndicator(status: sensor.status),
                            title: Text(
                              sensor.id,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            subtitle: Text(
                              'V: ${sensor.latestTelemetry.voltage.toStringAsFixed(1)}V | A: ${sensor.latestTelemetry.current.toStringAsFixed(1)}A | F: ${sensor.latestTelemetry.frequency.toStringAsFixed(1)}Hz',
                              style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12),
                            ),
                            trailing: Icon(
                              Icons.chevron_right,
                              color: Colors.white.withOpacity(0.3),
                            ),
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => SensorDetailScreen(sensorId: sensor.id),
                                ),
                              );
                            },
                          ),
                        );
                      },
                    ),
                  ],
                ),
              );
            }

            Widget buildCompareTab() {
              final multiSpots = _getMultiSpots();
              final unit = _selectedMetric == 'voltage' ? 'V' : 'A';
              final label = _selectedMetric == 'voltage' ? 'Voltage' : 'Current';

              return SingleChildScrollView(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Column(
                  children: [
                    _buildControls(),
                    const SizedBox(height: 12),
                    Container(
                      height: 380,
                      margin: const EdgeInsets.symmetric(horizontal: 16),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppConstants.secondaryColor.withOpacity(0.5),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: Colors.white.withOpacity(0.03),
                        ),
                      ),
                      child: _isLoadingHistories
                          ? const Center(child: CircularProgressIndicator())
                          : MultiTelemetryChart(
                              seriesData: multiSpots,
                              title: 'Overlaid Comparative $label Timeline',
                              metricName: _selectedMetric,
                              unit: unit,
                            ),
                    ),
                  ],
                ),
              );
            }

            return DefaultTabController(
              length: 4,
              child: Scaffold(
                backgroundColor: AppConstants.bgColor,
                appBar: AppBar(
                  backgroundColor: AppConstants.secondaryColor,
                  elevation: 0,
                  title: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppConstants.primaryColor.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(
                          Icons.analytics_outlined,
                          color: AppConstants.primaryColor,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Text(
                        'GRID MONITORING PANEL',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ],
                  ),
                  bottom: TabBar(
                    indicatorColor: AppConstants.primaryColor,
                    indicatorWeight: 3,
                    labelColor: Colors.white,
                    unselectedLabelColor: Colors.white60,
                    labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                    tabs: const [
                      Tab(text: 'ALPHA', icon: Icon(Icons.flash_on, size: 16)),
                      Tab(text: 'BETA', icon: Icon(Icons.flash_on, size: 16)),
                      Tab(text: 'GAMMA', icon: Icon(Icons.flash_on, size: 16)),
                      Tab(text: 'COMPARE', icon: Icon(Icons.compare_arrows, size: 16)),
                    ],
                  ),
                ),
                body: TabBarView(
                  children: [
                    buildSubstationTab('ALPHA'),
                    buildSubstationTab('BETA'),
                    buildSubstationTab('GAMMA'),
                    buildCompareTab(),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
