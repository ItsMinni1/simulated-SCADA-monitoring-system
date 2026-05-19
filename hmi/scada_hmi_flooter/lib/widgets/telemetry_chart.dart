import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import '../utils/constants.dart';

class TelemetryChart extends StatelessWidget {
  final List<FlSpot> dataPoints;
  final String title;
  final String metricName;
  final String unit;

  const TelemetryChart({
    super.key,
    required this.dataPoints,
    required this.title,
    required this.metricName,
    required this.unit,
  });

  Color _getMetricColor() {
    switch (metricName) {
      case 'voltage':
        return Colors.blueAccent;
      case 'current':
        return Colors.orangeAccent;
      case 'frequency':
        return Colors.tealAccent;
      default:
        return AppConstants.primaryColor;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (dataPoints.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    final metricColor = _getMetricColor();

    double minY = dataPoints.map((spot) => spot.y).reduce((a, b) => a < b ? a : b);
    double maxY = dataPoints.map((spot) => spot.y).reduce((a, b) => a > b ? a : b);
    double minX = dataPoints.map((spot) => spot.x).reduce((a, b) => a < b ? a : b);
    double maxX = dataPoints.map((spot) => spot.x).reduce((a, b) => a > b ? a : b);

    // Add padding to Y axis
    final paddingY = (maxY - minY).abs() * 0.15;
    minY = minY - (paddingY == 0 ? 5.0 : paddingY);
    maxY = maxY + (paddingY == 0 ? 5.0 : paddingY);

    // Guard against identical X bounds to prevent divide-by-zero
    double xInterval = (maxX - minX) / 4;
    if (xInterval <= 0) {
      xInterval = 1000.0; // default 1 second
      maxX = minX + 5000.0; // pad X scale
    }

    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: metricColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: metricColor.withOpacity(0.3), width: 1),
              ),
              child: Text(
                'UNIT: $unit',
                style: TextStyle(
                  color: metricColor,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'monospace',
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        Expanded(
          child: LineChart(
            LineChartData(
              minX: minX,
              maxX: maxX,
              minY: minY,
              maxY: maxY,
              lineTouchData: LineTouchData(
                touchTooltipData: LineTouchTooltipData(
                  getTooltipColor: (touchedSpot) => AppConstants.secondaryColor,
                  tooltipBorder: BorderSide(
                    color: Colors.white.withOpacity(0.1),
                    width: 1,
                  ),
                  getTooltipItems: (List<LineBarSpot> touchedBarSpots) {
                    return touchedBarSpots.map((barSpot) {
                      final spot = barSpot;
                      final date = DateTime.fromMillisecondsSinceEpoch(spot.x.toInt());
                      final formattedTime = "${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}:${date.second.toString().padLeft(2, '0')}";
                      return LineTooltipItem(
                        '$formattedTime\n',
                        const TextStyle(
                          color: Colors.white70,
                          fontSize: 11,
                        ),
                        children: [
                          TextSpan(
                            text: '${spot.y.toStringAsFixed(2)} $unit',
                            style: TextStyle(
                              color: metricColor,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
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
                getDrawingHorizontalLine: (value) {
                  return FlLine(
                    color: Colors.white.withOpacity(0.05),
                    strokeWidth: 1,
                  );
                },
                getDrawingVerticalLine: (value) {
                  return FlLine(
                    color: Colors.white.withOpacity(0.05),
                    strokeWidth: 1,
                  );
                },
              ),
              titlesData: FlTitlesData(
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 45,
                    interval: (maxY - minY) / 4 > 0 ? (maxY - minY) / 4 : 1.0,
                    getTitlesWidget: (value, meta) {
                      return Padding(
                        padding: const EdgeInsets.only(right: 8.0),
                        child: Text(
                          value.toStringAsFixed(1),
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.4),
                            fontSize: 9,
                            fontFamily: 'monospace',
                          ),
                          textAlign: TextAlign.end,
                        ),
                      );
                    },
                  ),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 30,
                    interval: xInterval,
                    getTitlesWidget: (value, meta) {
                      final date = DateTime.fromMillisecondsSinceEpoch(value.toInt());
                      final formattedTime = "${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}:${date.second.toString().padLeft(2, '0')}";
                      return Padding(
                        padding: const EdgeInsets.only(top: 8.0),
                        child: Text(
                          formattedTime,
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.4),
                            fontSize: 9,
                            fontFamily: 'monospace',
                          ),
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
                border: Border.all(
                  color: Colors.white.withOpacity(0.05),
                  width: 1,
                ),
              ),
              lineBarsData: [
                LineChartBarData(
                  spots: dataPoints,
                  isCurved: true,
                  color: metricColor,
                  barWidth: 3,
                  dotData: const FlDotData(show: false),
                  belowBarData: BarAreaData(
                    show: true,
                    gradient: LinearGradient(
                      colors: [
                        metricColor.withOpacity(0.2),
                        metricColor.withOpacity(0.01),
                      ],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}