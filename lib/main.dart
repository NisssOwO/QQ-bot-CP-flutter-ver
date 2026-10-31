import 'package:flutter/material.dart';
import 'src/screens/home_shell.dart';
import 'src/theme/theme_controller.dart';
import 'src/theme/theme_bridge.dart';
import 'src/theme/app_theme_tokens.dart';
import 'src/services/ui_jank_monitor.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const QqBotCpApp());
}

class QqBotCpApp extends StatefulWidget {
  const QqBotCpApp({super.key});
  @override
  State<QqBotCpApp> createState() => _QqBotCpAppState();
}

class _QqBotCpAppState extends State<QqBotCpApp> {
  ThemeSettings _settings = const ThemeSettings();
  bool _ready = false;
  final UiJankMonitor _jankMonitor = UiJankMonitor();
  @override
  void initState() {
    super.initState();
    _jankMonitor.start();
    WidgetsBinding.instance.addPostFrameCallback((_) => _finishStartup());
  }

  @override
  void dispose() {
    _jankMonitor.stop();
    super.dispose();
  }

  Future<void> _finishStartup() async {
    try {
      final settings = await ThemeBridge.load();
      if (mounted) setState(() { _settings = settings; _ready = true; });
    } catch (_) {}
    if (mounted && !_ready) setState(() => _ready = true);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'QQ-bot-CP',
      debugShowCheckedModeBanner: false,
      themeMode: _settings.mode,
      theme: ThemeData(
          brightness: Brightness.light,
          colorSchemeSeed: _settings.seedColor,
          scaffoldBackgroundColor:
              _settings.tintedBackground ? const Color(0xfff3f5ff) : null,
          cardTheme: CardThemeData(
              color:
                  Colors.white.withAlpha((_settings.cardOpacity * 255).round()),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(_settings.cardRadius))),
          extensions: const [
            AppThemeTokens(
                muted: Color(0xff687080),
                success: Color(0xff16794a),
                warning: Color(0xff9a6500),
                error: Color(0xffb3261e))
          ],
          useMaterial3: true),
      darkTheme: ThemeData(
          brightness: Brightness.dark,
          colorSchemeSeed: _settings.seedColor,
          scaffoldBackgroundColor:
              _settings.tintedBackground ? const Color(0xff151827) : null,
          cardTheme: CardThemeData(
              color: const Color(0xff242632)
                  .withAlpha((_settings.cardOpacity * 255).round()),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(_settings.cardRadius))),
          extensions: const [
            AppThemeTokens(
                muted: Color(0xffb9c0d0),
                success: Color(0xff8fe3b2),
                warning: Color(0xffffc46b),
                error: Color(0xffffb4ab))
          ],
          useMaterial3: true),
      home: _ready ? HomeShell(onThemeChanged: (settings) {
        setState(() => _settings = settings);
        ThemeBridge.save(settings);
      }) : const _StartupPage(),
    );
  }
}

class _StartupPage extends StatelessWidget {
  const _StartupPage();

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.smart_toy_outlined, size: 56, color: Theme.of(context).colorScheme.primary),
              const SizedBox(height: 18),
              Text('QQ-bot-CP', style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 10),
              Text('正在打开应用…', style: Theme.of(context).textTheme.bodyMedium),
              const SizedBox(height: 18),
              const SizedBox(width: 140, child: LinearProgressIndicator()),
            ],
          ),
        ),
      );
}
