import 'package:flutter/material.dart';

class StatusIndicator extends StatelessWidget {
  final String status;

  const StatusIndicator({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    Color color;
    switch (status.toUpperCase()) {
      case 'OK':
      case 'NORMAL':
        color = Colors.green;
        break;
      case 'WARNING':
        color = Colors.orange;
        break;
      case 'CRITICAL':
      case 'ANOMALY':
        color = Colors.red;
        break;
      default:
        color = Colors.grey;
    }

    return Container(
      width: 16,
      height: 16,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
      ),
    );
  }
}