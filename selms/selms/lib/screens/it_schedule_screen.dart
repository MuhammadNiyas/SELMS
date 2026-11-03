// lib/screens/it_schedule_screen.dart
//
// IT's view of the same weekly calendar HR uses (Smart Schedule), shown
// inside IT's own shell. All the behaviour lives in SmartScheduleScreen;
// this just hands it IT's token and switches the IT-specific bits on.

import 'package:flutter/material.dart';
import 'smart_schedule_screen.dart';

class ItScheduleScreen extends StatelessWidget {
  const ItScheduleScreen({super.key, required this.apiBaseUrl, required this.itToken});

  final String apiBaseUrl;
  final String itToken;

  @override
  Widget build(BuildContext context) {
    return SmartScheduleScreen(apiBaseUrl: apiBaseUrl, hrToken: itToken, forIt: true);
  }
}
