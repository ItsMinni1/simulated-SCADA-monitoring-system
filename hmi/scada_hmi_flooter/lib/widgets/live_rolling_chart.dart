import 'dart:async';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import '../utils/constants.dart';

class LiveRollingChart extends StatefulWidget {
  final Stream<Map<String, dynamic>> telemetryStream;
  final String title;
  final String metricName;
  final String unit;

  const LiveRollingChart({
    super.key,
    required this.telemetryStream,
    required this.title,
    required this.metricName,
    required this.unit,
  });

  @override
  State<LiveRollingChart> createState() => _LiveRollingChartState();
}

class _LiveRollingChartState extends State<LiveRollingChart> {
  final List<FlSpot> _alphaSpots = [];
  final List<FlSpot> _betaSpots = [];
  final List<FlSpot> _gammaSpots = [];

  StreamSubscription<Map<String, dynamic>>? _streamSubscription;
  Timer? _viewportRollingTimer;

  Duration _windowDuration = const Duration(minutes: 15);
  int _selectedChipMinutes = 15;

  @override
  void initState() {
    super.initState();
    _subscribeToTelemetry();
    _startViewportRollingClock();
  }

  @override
  void didUpdateWidget(covariant LiveRollingChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.telemetryStream != widget.telemetryStream) {
      _streamSubscription?.cancel();
      _subscribeToTelemetry();
    }
  }

  @override
  void dispose() {
    _streamSubscription?.cancel();
    _viewportRollingTimer?.cancel();
    super.dispose();
  }

  void _subscribeToTelemetry() {
    _streamSubscription = widget.telemetryStream.listen(
      (packet) {
        final rawTime = packet['timestamp'];
        final DateTime time = rawTime is DateTime
            ? rawTime
            : (DateTime.tryParse(rawTime.toString()) ?? DateTime.now());

        final double x = time.millisecondsSinceEpoch.toDouble();
        final double alphaVal = (packet['alpha'] ?? 0.0).toDouble();
        final double betaVal = (packet['beta'] ?? 0.0).toDouble();
        final double gammaVal = (packet['gamma'] ?? 0.0).toDouble();

        if (mounted) {
          setState(() {
            _appendAndPrune(_alphaSpots, FlSpot(x, alphaVal));
            _appendAndPrune(_betaSpots, FlSpot(x, betaVal));
            _appendAndPrune(_gammaSpots, FlSpot(x, gammaVal));
          });
        }
      },
      onError: (err) {
        debugPrint("Telemetry Stream Error: $err");
      },
    );
  }

  void _appendAndPrune(List<FlSpot> series, FlSpot newSpot) {
    series.removeWhere((spot) => spot.x == newSpot.x);
    series.add(newSpot);
    series.sort((a, b) => a.x.compareTo(b.x));

    final double oldestAllowedX =
        DateTime.now().subtract(_windowDuration).millisecondsSinceEpoch.toDouble();
    series.removeWhere((spot) => spot.x < oldestAllowedX);

    if (series.length > 1000) {
      series.removeRange(0, series.length - 1000);
    }
  }

  void _startViewportRollingClock() {
    _viewportRollingTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          final oldestAllowedX =
              DateTime.now().subtract(_windowDuration).millisecondsSinceEpoch.toDouble();
          _alphaSpots.removeWhere((spot) => spot.x < oldestAllowedX);
          _betaSpots.removeWhere((spot) => spot.x < oldestAllowedX);
          _gammaSpots.removeWhere((spot) => spot.x < oldestAllowedX);
        });
      }
    });
  }

  void _changeTimeframe(int minutes) {
    setState(() {
      _selectedChipMinutes = minutes;
      _windowDuration = Duration(minutes: minutes);

      final double oldestAllowedX =
          DateTime.now().subtract(_windowDuration).millisecondsSinceEpoch.toDouble();
      _alphaSpots.removeWhere((spot) => spot.x < oldestAllowedX);
      _betaSpots.removeWhere((spot) => spot.x < oldestAllowedX);
      _gammaSpots.removeWhere((spot) => spot.x < oldestAllowedX);
    });
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final double maxX = now.millisecondsSinceEpoch.toDouble();
    final double minX = now.subtract(_windowDuration).millisecondsSinceEpoch.toDouble();

    final visibleSpots = [..._alphaSpots, ..._betaSpots, ..._gammaSpots]
        .where((spot) => spot.x >= minX && spot.x <= maxX)
        .toList();

    double minY = 200.0;
    double maxY = 240.0;

    if (visibleSpots.isNotEmpty) {
      final yValues = visibleSpots.map((s) => s.y).toList();
      double minVisibleY = yValues.reduce((a, b) => a < b ? a : b);
      double maxVisibleY = yValues.reduce((a, b) => a > b ? a : b);
      final padding = (maxVisibleY - minVisibleY).abs() * 0.15;
      minY = minVisibleY - (padding == 0 ? 5.0 : padding);
      maxY = maxVisibleY + (padding == 0 ? 5.0 : padding);
    }

    final double xInterval = (maxX - minX) / 4;

    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              widget.title,
              style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
            ),
            _buildTimeframeChips(),
          ],
        ),
        const SizedBox(height: 16),
        Expanded(
          child: LineChart(
            LineChartData(
              minX: minX,
              maxX: maxX,
              minY: minY,
              maxY: maxY,
              clipData: const FlClipData.all(),
              lineTouchData: LineTouchData(
                touchTooltipData: LineTouchTooltipData(
                  getTooltipColor: (touchedSpot) => AppConstants.secondaryColor,
                  getTooltipItems: (touchedSpots) {
                    return touchedSpots.map((barSpot) {
                      final time = DateTime.fromMillisecondsSinceEpoch(barSpot.x.toInt());
                      final formattedTime =
                          "${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}:${time.second.toString().padLeft(2, '0')}";
                      final branch =
                          barSpot.barIndex == 0 ? 'Alpha' : (barSpot.barIndex == 1 ? 'Beta' : 'Gamma');
                      final color = barSpot.bar.color ?? Colors.white;

                      return LineTooltipItem(
                        '$formattedTime\n',
                        const TextStyle(color: Colors.white54, fontSize: 11),
                        children: [
                          TextSpan(
                              text: '$branch: ',
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                          TextSpan(
                              text: '${barSpot.y.toStringAsFixed(2)} ${widget.unit}',
                              style: TextStyle(color: color, fontWeight: FontWeight.bold)),
                        ],
                      );
                    }).toList();
                  },
                ),
              ),
              gridData: FlGridData(
                show: true,
                drawVerticalLine: true,
                horizontalInterval: (maxY - minY) / 4 > 0 ? (maxY - minY) / 4 : 1.0,
                verticalInterval: xInterval,
                getDrawingHorizontalLine: (val) =>
                    FlLine(color: Colors.white.withOpacity(0.04), strokeWidth: 1),
                getDrawingVerticalLine: (val) =>
                    FlLine(color: Colors.white.withOpacity(0.04), strokeWidth: 1),
              ),
              titlesData: FlTitlesData(
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 45,
                    getTitlesWidget: (value, meta) => Padding(
                      padding: const EdgeInsets.only(right: 8.0),
                      child: Text(
                        value.toStringAsFixed(1),
                        style: TextStyle(
                            color: Colors.white.withOpacity(0.4), fontSize: 9, fontFamily: 'monospace'),
                        textAlign: TextAlign.end,
                      ),
                    ),
                  ),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 24,
                    interval: xInterval,
                    getTitlesWidget: (value, meta) {
                      final time = DateTime.fromMillisecondsSinceEpoch(value.toInt());
                      final formatted =
                          "${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}:${time.second.toString().padLeft(2, '0')}";
                      return Padding(
                        padding: const EdgeInsets.only(top: 6.0),
                        child: Text(
                          formatted,
                          style: TextStyle(
                              color: Colors.white.withOpacity(0.4), fontSize: 8, fontFamily: 'monospace'),
                        ),
                      );
                    },
                  ),
                ),
                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              ),
              borderData: FlBorderData(
                show: true,
                border: Border.all(color: Colors.white.withOpacity(0.05), width: 1),
              ),
              lineBarsData: [
                _buildBarData(_alphaSpots, Colors.blueAccent),
                _buildBarData(_betaSpots, Colors.orangeAccent),
                _buildBarData(_gammaSpots, Colors.tealAccent),
              ],
            ),
          ),
        ),
      ],
    );
  }

  LineChartBarData _buildBarData(List<FlSpot> spots, Color color) {
    return LineChartBarData(
      spots: spots,
      isCurved: true,
      curveMode: CurveMode.quadratic,
      color: color,
      barWidth: 2.5,
      dotData: const FlDotData(show: false),
      belowBarData: BarAreaData(
        show: true,
        gradient: LinearGradient(
          colors: [color.withOpacity(0.12), color.withOpacity(0.00)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
    );
  }

  Widget _buildTimeframeChips() {
    final timeframes = [
      {'minutes': 15, 'label': '15m'},
      {'minutes': 60, 'label': '1h'},
      {'minutes': 360, 'label': '6h'},
      {'minutes': 1440, 'label': '24h'},
    ];

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppConstants.secondaryColor,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: timeframes.map((tf) {
          final int mins = tf['minutes'] as int;
          final String label = tf['label'] as String;
          final isSelected = _selectedChipMinutes == mins;

          return GestureDetector(
            onTap: () => _changeTimeframe(mins),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: isSelected ? AppConstants.primaryColor : Colors.transparent,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                label,
                style: TextStyle(
                  color: isSelected ? Colors.white : Colors.white60,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
