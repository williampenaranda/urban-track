import 'dart:convert';
import 'dart:ui'; // Necesario para el BackdropFilter
import 'package:app/screens/ruta_detail_screen.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:app/screens/irregularidades_screen.dart';
import '../main.dart';

class RutasScreen extends StatefulWidget {
  const RutasScreen({Key? key}) : super(key: key);

  @override
  State<RutasScreen> createState() => _RutasScreenState();
}

class _RutasScreenState extends State<RutasScreen> {
  final TextEditingController _searchController = TextEditingController();
  bool _isLoading = true;
  List<dynamic> _allRutas = [];
  List<dynamic> _filteredRutas = [];

  @override
  void initState() {
    super.initState();
    _fetchRutas();
    _searchController.addListener(_filterRutas);
  }

  Future<void> _fetchRutas() async {
    try {
      final response = await http.get(Uri.parse('$apiBaseUrl/api/bus/rutas'));
      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(utf8.decode(response.bodyBytes));

        // Lógica de ordenamiento personalizado
        data.sort((a, b) {
          final nombreA = a['nombre'] as String? ?? '';
          final nombreB = b['nombre'] as String? ?? '';

          // Helper para extraer la letra y el número de la ruta
          Map<String, dynamic> getRouteParts(String nombre) {
            if (nombre.isEmpty) return {'letter': '', 'number': 999};
            String letter = nombre[0].toUpperCase();
            String numberString = nombre.replaceAll(RegExp(r'[^0-9]'), '');
            int number = int.tryParse(numberString) ?? 999;
            return {'letter': letter, 'number': number};
          }

          // Helper para asignar prioridad a las letras (T > X > A)
          int getLetterPriority(String letter) {
            switch (letter) {
              case 'T':
                return 0;
              case 'X':
                return 1;
              case 'A':
                return 2;
              default:
                return 3; // Otras rutas van al final
            }
          }

          final partsA = getRouteParts(nombreA);
          final partsB = getRouteParts(nombreB);

          final priorityA = getLetterPriority(partsA['letter']);
          final priorityB = getLetterPriority(partsB['letter']);

          // 1. Ordenar por prioridad de letra
          if (priorityA != priorityB) {
            return priorityA.compareTo(priorityB);
          }

          // 2. Si las letras son iguales, ordenar por número
          return (partsA['number'] as int).compareTo(partsB['number'] as int);
        });

        setState(() {
          _allRutas = data;
          _filteredRutas = data;
          _isLoading = false;
        });
      } else {
        setState(() {
          _isLoading = false;
        });
        // Aquí se podría mostrar un mensaje de error
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      // Aquí se podría mostrar un mensaje de error por conexión
    }
  }

  void _filterRutas() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      _filteredRutas = _allRutas.where((ruta) {
        final nombre = (ruta['nombre'] as String? ?? '').toLowerCase();
        return nombre.contains(query);
      }).toList();
    });
  }

  @override
  void dispose() {
    _searchController.removeListener(_filterRutas);
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,
      body: Stack(
        children: [
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.blue.shade800, Colors.blue.shade400],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                // Tarjeta de búsqueda con efecto de desenfoque
                Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                      child: Container(
                        padding: const EdgeInsets.all(24.0),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: Colors.white.withOpacity(0.3),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'UrbanTrack',
                              style: TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'Consulta todas las rutas',
                              style: TextStyle(
                                fontSize: 18,
                                color: Colors.white70,
                              ),
                            ),
                            const SizedBox(height: 24),
                            TextField(
                              controller: _searchController,
                              style: const TextStyle(color: Colors.white),
                              decoration: InputDecoration(
                                hintText: 'Buscar ruta...',
                                hintStyle: TextStyle(
                                  color: Colors.white.withOpacity(0.7),
                                ),
                                prefixIcon: const Icon(
                                  Icons.search,
                                  color: Colors.white,
                                ),
                                filled: true,
                                fillColor: Colors.white.withOpacity(0.3),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12.0),
                                  borderSide: BorderSide.none,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                // Contenedor para la lista de rutas
                Expanded(
                  child: ClipRRect(
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(20),
                      topRight: Radius.circular(20),
                    ),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.3),
                          borderRadius: const BorderRadius.only(
                            topLeft: Radius.circular(20),
                            topRight: Radius.circular(20),
                          ),
                        ),
                        child: _isLoading
                            ? const Center(
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                ),
                              )
                            : ListView.builder(
                                padding: const EdgeInsets.all(10),
                                itemCount: _filteredRutas.length,
                                itemBuilder: (context, index) {
                                  final ruta = _filteredRutas[index];
                                  final nombre = ruta['nombre'] ?? 'Sin nombre';
                                  return Card(
                                    color: Colors.white.withOpacity(0.85),
                                    elevation: 2,
                                    margin: const EdgeInsets.symmetric(
                                      vertical: 6,
                                      horizontal: 8,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: ListTile(
                                      leading: CircleAvatar(
                                        backgroundColor: _getRouteColor(nombre),
                                        child: Text(
                                          _getRouteInitial(nombre),
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                      title: Text(
                                        nombre,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      trailing: const Icon(
                                        Icons.arrow_forward_ios,
                                        size: 14,
                                      ),
                                      onTap: () {
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (context) =>
                                                RutaDetailScreen(ruta: ruta),
                                          ),
                                        );
                                      },
                                    ),
                                  );
                                },
                              ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Container(
          padding: const EdgeInsets.all(12.0),
          margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.1),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.white.withOpacity(0.2)),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
              child: BottomNavigationBar(
                backgroundColor: Colors.transparent,
                elevation: 0,
                type: BottomNavigationBarType.fixed,
                selectedItemColor: Colors.white,
                unselectedItemColor: Colors.white70,
                showUnselectedLabels: true,
                items: const [
                  BottomNavigationBarItem(
                    icon: Icon(Icons.place),
                    label: 'Direcciones',
                  ),
                  BottomNavigationBarItem(
                    icon: Icon(Icons.location_city),
                    label: 'Estaciones',
                  ),
                  BottomNavigationBarItem(
                    icon: Icon(Icons.alt_route),
                    label: 'Rutas',
                  ),
                  BottomNavigationBarItem(
                    icon: Icon(Icons.report_problem),
                    label: 'Irregularidades',
                  ),
                ],
                currentIndex: 2,
                onTap: (index) {
                  if (index == 0) {
                    Navigator.pop(context);
                  } else if (index == 3) {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const IrregularidadesScreen(),
                      ),
                    );
                  }
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  Color _getRouteColor(String nombre) {
    if (nombre.startsWith('T')) return Colors.red.shade700;
    if (nombre.startsWith('X')) return Colors.orange.shade700;
    if (nombre.startsWith('A')) return Colors.green.shade700;
    return Colors.grey.shade600;
  }

  String _getRouteInitial(String nombre) {
    if (nombre.startsWith('T')) return 'T';
    if (nombre.startsWith('X')) return 'X';
    if (nombre.startsWith('A')) return 'A';
    return '?';
  }
}
