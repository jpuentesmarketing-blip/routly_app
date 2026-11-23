import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'features/auth/presentation/login_screen.dart';
import 'features/auth/presentation/reset_password_screen.dart';
import 'features/home/presentation/home_screen.dart';

final navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: 'https://tsrlejeefhfcpykljrur.supabase.co',
    publishableKey: 'sb_publishable_JeyzLm9TIVHSBAQ0ZEic4Q_LgqEZai7',
  );

  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  bool _isPasswordRecovery = false;

  @override
  void initState() {
    super.initState();

    // 1. Detectar si la URL web contiene parámetros de recuperación o código PKCE al cargar
    final uri = Uri.base;
    if (uri.queryParameters.containsKey('code') || uri.toString().contains('recovery')) {
      setState(() {
        _isPasswordRecovery = true;
      });
    }

    // 2. Escuchar cambios de estado de autenticación (Deep Links y eventos de recuperación)
    Supabase.instance.client.auth.onAuthStateChange.listen((data) {
      final event = data.event;
      if (event == AuthChangeEvent.passwordRecovery) {
        setState(() {
          _isPasswordRecovery = true;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      title: 'Routly',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
        useMaterial3: true,
      ),
      // Si estamos en recuperación, se muestra ResetPasswordScreen obligatoriamente
      home: _isPasswordRecovery
          ? const ResetPasswordScreen()
          : (Supabase.instance.client.auth.currentUser != null
              ? const HomeScreen()
              : const LoginScreen()),
    );
  }
}