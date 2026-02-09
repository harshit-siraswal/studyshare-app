import 'package:flutter/material.dart';

/// Global navigator key for performing navigation outside the widget tree.
/// 
/// Assign this key to [MaterialApp.navigatorKey] in your app's root widget.
/// Usage: `appNavigatorKey.currentState?.pushNamed('/route')`
final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();