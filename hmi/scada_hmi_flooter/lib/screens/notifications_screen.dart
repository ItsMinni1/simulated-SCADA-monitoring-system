import 'dart:developer';
import 'package:flutter/material.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Notifications Setup')),
      body: Center(
        child: ElevatedButton(
          onPressed: () async {
            final messenger = ScaffoldMessenger.of(context);
            try {
              String? token = await FirebaseMessaging.instance.getToken();
              log('FCM Token: $token');
              messenger.showSnackBar(
                const SnackBar(content: Text('FCM Token fetched successfully')),
              );
            } catch (e) {
              log('Failed to fetch FCM Token: $e');
              messenger.showSnackBar(
                SnackBar(content: Text('FCM Token error: $e')),
              );
            }
          },
          child: const Text('Get FCM Token'),
        ),
      ),
    );
  }
}
