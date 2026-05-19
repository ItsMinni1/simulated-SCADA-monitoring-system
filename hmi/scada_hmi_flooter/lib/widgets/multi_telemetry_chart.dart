import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import '../utils/constants.dart';

class MultiTelemetryChart extends StatelessWidget {
  final Map<String, List<FlSpot>> seriesData;
  final String title;
  final String metricName;
  final String unit;

  const MultiTelemetryChart({
    super.key,
    required this.seriesData,
    required this.title,
    required this.metricName,
    required this.unit,
  });

  Color _getSeriesColor(String key) {
    if (key.toUpperCase().contains('ALPHA')) {
      return Colors.blueAccent;
    } else if (key.toUpperCase().contains('BETA')) {
      return Colors.orangeAccent;
    } else if (key.toUpperCase().contains('GAMMA')) {
      return Colors.tealAccent;
    } else {
      return AppConstants.primaryColor;
    }
  }

  @override
  Widget build(BuildContext context) {
    final allSpots = seriesData.values.expand((element) => element).toList();

    if (allSpots.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 12),
            Text(
              'Synchronizing comparative telemetry...',
              style: TextStyle(color: Colors.white54, fontSize: 13),
            ),
          ],
        ),
      );
    }

    double minY = allSpots.map((spot) => spot.y).reduce((a, b) => a < b ? a : b);
    double maxY = allSpots.map((spot) => spot.y).reduce((a, b) => a > b ? a : b);
    double minX = allSpots.map((spot) => spot.x).reduce((a, b) => a < b ? a : b);
    double maxX = allSpots.map((spot) => spot.x).reduce((a, b) => a > b ? a : b);

    final paddingY = (maxY - minY).abs() * 0.15;
    minY = minY - (paddingY == 0 ? 5.0 : paddingY);
    maxY = maxY + (paddingY == 0 ? 5.0 : paddingY);

    double xInterval = (maxX - minX) / 4;
    if (xInterval <= 0) {
      xInterval = 1000.0;
      maxX = minX + 5000.0;
    }

    final List<LineChartBarData> lineBars = [];
    seriesData.forEach((key, spots) {
      if (spots.isNotEmpty) {
        final color = _getSeriesColor(key);
        lineBars.add(
          LineChartBarData(
            spots: spots,
            isCurved: true,
            color: color,
            barWidth: 3,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                colors: [
                  color.withOpacity(0.15),
                  color.withOpacity(0.01),
                ],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
          ),
        );
      }
    });

    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.05),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.white12, width: 1),
              ),
              child: Text(
                'UNIT: $unit',
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'monospace',
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.start,
          children: seriesData.keys.map((key) {
            final color = _getSeriesColor(key);
            return Padding(
              padding: const EdgeInsets.only(right: 20.0),
              child: Row(
                children: [
                  Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    key,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
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
                      final formattedTime =
                          "${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}:${date.second.toString().padLeft(2, '0')}";

                      String seriesName = 'Substation';
                      seriesData.forEach((k, spots) {
                        if (spots.any((s) => s.x == spot.x && s.y == spot.y)) {
                          seriesName = k;
                        }
                      });

                      final color = _getSeriesColor(seriesName);
                      return LineTooltipItem(
                        '$formattedTime\n',
                        const TextStyle(color: Colors.white70, fontSize: 11),
                        children: [
                          TextSpan(
                            text: '$seriesName: ',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                          TextSpan(
                            text: '${spot.y.toStringAsFixed(2)} $unit',
                            style: TextStyle(
                              color: color,
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
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
                getDrawingHorizontalLine: (value) =>
                    FlLine(color: Colors.white.withOpacity(0.05), strokeWidth: 1),
                getDrawingVerticalLine: (value) =>
                    FlLine(color: Colors.white.withOpacity(0.05), strokeWidth: 1),
              ),
              titlesData: FlTitlesData(
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 45,
                    interval: (maxY - minY) / 4 > 0 ? (maxY - minY) / 4 : 1.0,
                    getTitlesWidget: (value, meta) => Padding(
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
                    ),
                  ),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 30,
                    interval: xInterval,
                    getTitlesWidget: (value, meta) {
                      final date = DateTime.fromMillisecondsSinceEpoch(value.toInt());
                      return Padding(
                        padding: const EdgeInsets.only(top: 8.0),
                        child: Text(
                          "${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}:${date.second.toString().padLeft(2, '0')}",
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
                border: Border.all(color: Colors.white.withOpacity(0.05), width: 1),
              ),
              lineBarsData: lineBars,
            ),
          ),
        ),
      ],
    );
  }
}
