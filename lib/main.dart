import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'features/home/home_screen.dart';
import 'core/app_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Configure system UI to not overlap app content
  SystemChrome.setEnabledSystemUIMode(
    SystemUiMode.edgeToEdge,
  );
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Colors.transparent,
    ),
  );
  
  print("APP STARTING...");
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.dumpErrorToConsole(details);
    runApp(MaterialApp(home: Scaffold(body: Center(child: Text("Startup Error: ${details.exception}")))));
  };
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    print("Building MyApp");
    return MaterialApp(
      title: 'Planar GPS',
      theme: AppTheme.darkTheme,
      home: const HomeScreen(),
    );
  }
}



