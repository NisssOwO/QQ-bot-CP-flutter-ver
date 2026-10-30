import 'package:flutter/material.dart';
import 'src/screens/home_shell.dart';
import 'src/theme/theme_controller.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const QqBotCpApp());
}

class QqBotCpApp extends StatefulWidget {
  const QqBotCpApp({super.key});
  @override State<QqBotCpApp> createState() => _QqBotCpAppState();
}

class _QqBotCpAppState extends State<QqBotCpApp> {
  ThemeSettings _settings = const ThemeSettings();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'QQ-bot-CP',
      debugShowCheckedModeBanner: false,
      themeMode: _settings.mode,
      theme: ThemeData(brightness: Brightness.light, colorSchemeSeed: _settings.seedColor, cardTheme: CardThemeData(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(_settings.cardRadius))), useMaterial3: true),
      darkTheme: ThemeData(brightness: Brightness.dark, colorSchemeSeed: _settings.seedColor, cardTheme: CardThemeData(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(_settings.cardRadius))), useMaterial3: true),
      home: HomeShell(onThemeChanged: (settings) => setState(() => _settings = settings)),
    );
  }
}
