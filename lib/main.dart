
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/scheduler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'widgets/desktop_ad_banner.dart';
import 'src/game/game.dart';
import 'src/core/constants.dart';


void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ShadowJumperApp());
}

class ShadowJumperApp extends StatelessWidget {
  const ShadowJumperApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Shadow Jumper ($TOTAL_LEVELS Levels)',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true),
      home: Scaffold(
        body: SafeArea(
          top: false,
          bottom: false,
          child: ShadowJumperGame(),
        ),
      ),
    );
  }
}

