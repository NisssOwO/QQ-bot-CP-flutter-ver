import 'package:flutter/material.dart';
import 'src/screens/home_shell.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const QqBotCpApp());
}

class QqBotCpApp extends StatelessWidget {
  const QqBotCpApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'QQ-bot-CP',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark,
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        colorSchemeSeed: const Color(0xff8290ff),
        useMaterial3: true,
      ),
      home: const HomeShell(),
    );
  }
}
