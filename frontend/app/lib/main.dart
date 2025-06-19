import 'package:app/providers/auth_provider.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'screens/login_screen.dart';
import 'package:app/screens/direcciones_screen.dart';
import 'package:app/screens/estaciones_screen.dart';
import 'package:app/screens/irregularidades_screen.dart';
import 'package:app/screens/rutas_screen.dart';

const String apiBaseUrl = 'http://56.124.36.40';
final String wsApiBaseUrl = apiBaseUrl.replaceFirst('http', 'ws');

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    ChangeNotifierProvider(
      create: (context) => AuthProvider(),
      child: const UrbanTrackApp(),
    ),
  );
}

class UrbanTrackApp extends StatelessWidget {
  const UrbanTrackApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'UrbanTrack',
      theme: ThemeData(primarySwatch: Colors.blue, fontFamily: 'Roboto'),
      // Definimos las rutas de la aplicación
      initialRoute: '/',
      routes: {
        '/': (context) => const LoginScreen(),
        '/direcciones': (context) => const DireccionesScreen(),
        '/estaciones': (context) => const EstacionesScreen(),
        '/rutas': (context) => const RutasScreen(),
        '/irregularidades': (context) => const IrregularidadesScreen(),
      },
    );
  }
}
