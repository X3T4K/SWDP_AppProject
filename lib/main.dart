import 'package:flutter/material.dart';
import 'package:smart_wearables_app/home_page.dart';
import 'package:smart_wearables_app/services/notification_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await NotificationService().init();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Smart Wearables App',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF005BFF),
          primary: const Color(0xFF005BFF),
          secondary: const Color(0xFF06F3FF),
        ),
        useMaterial3: true,
      ),
      home: const HomePage(title: 'Smart Wearables'),
    );
  }
}
