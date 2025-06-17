import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geocoding/geocoding.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:developer';
import 'dart:ui'; // Necesario para ImageFilter
import 'package:app/screens/rutas_screen.dart';
import 'package:app/screens/irregularidades_screen.dart';
import '../main.dart';

class DireccionesScreen extends StatefulWidget {
  final Position? initialPosition;
  const DireccionesScreen({Key? key, this.initialPosition}) : super(key: key);

  @override
  State<DireccionesScreen> createState() => _DireccionesScreenState();
}

class _DireccionesScreenState extends State<DireccionesScreen> {
  final TextEditingController _startController = TextEditingController();
  final TextEditingController _endController = TextEditingController();
  final MapController _mapController = MapController();
  double? _latitude;
  double? _longitude;
  double? _endLatitude;
  double? _endLongitude;
  bool _isLoading = false;
  List<Location> _suggestions = [];
  List<String> _locationNames = [];
  bool _isSearching = false;
  bool _showSuggestions = false;
  bool showRouteResult = false;
  Map<String, dynamic>? routeResult;
  String _loadingMessage = '';
  bool _isInBusMode = false;
  String? _currentBusRoute;

  // Lista de ejemplo de rutas. En una implementación real, esto vendría de una API.
  final List<String> _rutasDisponibles = [
    'Ruta 101',
    'Ruta 102',
    'Ruta 203',
    'Ruta Circular',
    'Ruta Express',
  ];

  Widget _buildLocationMarker({bool isDestination = false}) {
    return Container(
      decoration: BoxDecoration(
        color: (isDestination ? Colors.green : Colors.red).withOpacity(0.3),
        shape: BoxShape.circle,
      ),
      child: Icon(
        isDestination ? Icons.location_on : Icons.person_pin_circle,
        color: isDestination ? Colors.green : Colors.red,
        size: 40,
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    if (widget.initialPosition != null) {
      _latitude = widget.initialPosition!.latitude;
      _longitude = widget.initialPosition!.longitude;
      _startController.text =
          '${_latitude!.toStringAsFixed(5)}, ${_longitude!.toStringAsFixed(5)}';
    }
  }

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  LatLng get _mapCenter {
    if (_latitude != null && _longitude != null) {
      return LatLng(_latitude!, _longitude!);
    }
    // Centro por defecto: Cartagena
    return LatLng(10.3910, -75.4794);
  }

  Future<void> _getCurrentLocation() async {
    try {
      setState(() {
        _isLoading = true;
        _loadingMessage = 'Obteniendo ubicación...';
      });

      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Activa la ubicación en tu dispositivo.'),
            ),
          );
        }
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Permiso de ubicación denegado.')),
            );
          }
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Permiso de ubicación denegado permanentemente.'),
            ),
          );
        }
        return;
      }

      final position = await Geolocator.getCurrentPosition();

      if (mounted) {
        setState(() {
          _latitude = position.latitude;
          _longitude = position.longitude;
          _startController.text =
              '${_latitude!.toStringAsFixed(5)}, ${_longitude!.toStringAsFixed(5)}';
        });

        // Animar el mapa a la nueva ubicación
        _mapController.move(LatLng(_latitude!, _longitude!), 15);

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Ubicación actualizada'),
            duration: Duration(seconds: 1),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al obtener la ubicación: ${e.toString()}'),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _showBusTrackingModal() {
    String? selectedRoute; // Variable para almacenar la ruta seleccionada

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setModalState) {
            return BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
              child: Container(
                padding: const EdgeInsets.all(24.0),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(24.0),
                    topRight: Radius.circular(24.0),
                  ),
                ),
                child: Wrap(
                  alignment: WrapAlignment.center,
                  runSpacing: 20,
                  children: [
                    const Icon(
                      Icons.directions_bus,
                      size: 40,
                      color: Colors.blue,
                    ),
                    const Text(
                      'Confirmar Viaje en Bus',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const Text(
                      'Al confirmar, tu ubicación será compartida en tiempo real para mejorar el sistema de seguimiento de buses.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 14, color: Colors.grey),
                    ),
                    DropdownButtonFormField<String>(
                      value: selectedRoute,
                      hint: const Text('Selecciona tu ruta'),
                      isExpanded: true,
                      onChanged: (String? newValue) {
                        setModalState(() {
                          selectedRoute = newValue;
                        });
                      },
                      items: _rutasDisponibles.map<DropdownMenuItem<String>>((
                        String value,
                      ) {
                        return DropdownMenuItem<String>(
                          value: value,
                          child: Text(value),
                        );
                      }).toList(),
                      decoration: InputDecoration(
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        prefixIcon: const Icon(Icons.route),
                      ),
                    ),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: selectedRoute != null
                            ? () {
                                // Lógica para iniciar el tracking
                                Navigator.pop(context);
                                setState(() {
                                  _isInBusMode = true;
                                  _currentBusRoute = selectedRoute;
                                });
                              }
                            : null, // Deshabilitado si no hay ruta
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text('Confirmar e Iniciar Viaje'),
                      ),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancelar'),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _searchLocations(String query) async {
    if (query.isEmpty) {
      setState(() {
        _suggestions = [];
        _locationNames = [];
        _isSearching = false;
        _showSuggestions = false;
      });
      return;
    }

    setState(() {
      _isSearching = true;
      _showSuggestions = true;
    });

    try {
      String searchQuery = query.trim();
      if (!searchQuery.toLowerCase().contains('cartagena')) {
        searchQuery = '$searchQuery, Cartagena, Colombia';
      }

      List<Location> locations = await locationFromAddress(searchQuery);
      List<String> names = [];
      List<Location> filteredLocations = [];

      for (var location in locations) {
        try {
          List<Placemark> placemarks = await placemarkFromCoordinates(
            location.latitude,
            location.longitude,
          );

          if (placemarks.isNotEmpty) {
            Placemark place = placemarks.first;
            String? adminArea = place.administrativeArea?.toLowerCase();
            String? locality = place.locality?.toLowerCase();

            bool isInCartagena =
                (adminArea?.contains('bolívar') ?? false) &&
                (locality?.contains('cartagena') ?? false);

            if (isInCartagena) {
              // Construir el nombre de la ubicación con un formato más amigable
              List<String> nameParts = [];

              // Agregar el nombre del lugar si existe
              if (place.name?.isNotEmpty ?? false) {
                nameParts.add(place.name!);
              }

              // Agregar la dirección
              if (place.street?.isNotEmpty ?? false) {
                nameParts.add(place.street!);
              }

              // Agregar el barrio si existe
              if (place.subLocality?.isNotEmpty ?? false) {
                nameParts.add(place.subLocality!);
              }

              // Agregar la ciudad
              if (place.locality?.isNotEmpty ?? false) {
                nameParts.add(place.locality!);
              }

              String name = nameParts.join(', ');

              names.add(name);
              filteredLocations.add(location);
            }
          }
        } catch (e) {
          // Si hay error al obtener el placemark, agregamos la ubicación de todos modos
          String name =
              '${location.latitude.toStringAsFixed(5)}, ${location.longitude.toStringAsFixed(5)}';
          names.add(name);
          filteredLocations.add(location);
        }
      }

      setState(() {
        _suggestions = filteredLocations;
        _locationNames = names;
        _isSearching = false;
        _showSuggestions = true;
      });
    } catch (e) {
      setState(() {
        _suggestions = [];
        _locationNames = [];
        _isSearching = false;
        _showSuggestions = false;
      });
    }
  }

  void _selectLocation(Location location, String name) {
    setState(() {
      _endController.text = name;
      _endLatitude = location.latitude;
      _endLongitude = location.longitude;
      _suggestions = [];
      _locationNames = [];
      _showSuggestions = false;
    });

    // Centrar el mapa en la ubicación seleccionada
    _mapController.move(LatLng(location.latitude, location.longitude), 15);
  }

  Future<void> calculateRoute() async {
    if (_latitude == null ||
        _longitude == null ||
        _endLatitude == null ||
        _endLongitude == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Por favor selecciona origen y destino')),
      );
      return;
    }

    setState(() {
      _isLoading = true;
      _loadingMessage = 'Calculando ruta...';
    });

    try {
      final requestBody = {
        'origen_lat': _latitude,
        'origen_lon': _longitude,
        'destino_lat': _endLatitude,
        'destino_lon': _endLongitude,
      };

      // 1. Imprimir el cuerpo de la solicitud en la consola de depuración
      debugPrint('--- REQUEST BODY ---');
      debugPrint(jsonEncode(requestBody));
      debugPrint('--------------------');

      final response = await http.post(
        Uri.parse('$apiBaseUrl/api/bus/calculate_route'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(requestBody),
      );

      // 2. Imprimir la respuesta completa de la API
      debugPrint('--- API RESPONSE ---');
      debugPrint('Status Code: ${response.statusCode}');
      debugPrint('Body: ${response.body}');
      debugPrint('--------------------');

      // Independientemente del código de estado, intentamos decodificar el cuerpo
      // por si contiene un mensaje de error útil.
      final responseData = jsonDecode(response.body);

      // Una ruta es válida solo si el estado es 200 y contiene paradas.
      if (response.statusCode == 200 &&
          responseData.containsKey('paradas_trayecto') &&
          (responseData['paradas_trayecto'] as List).isNotEmpty) {
        setState(() {
          showRouteResult = true;
          routeResult = responseData;
        });
      } else {
        // Para cualquier otro caso (error 500, 404, o 200 sin paradas),
        // mostramos la vista de "ruta no encontrada".
        setState(() {
          showRouteResult = true;
          routeResult = null;
        });
      }
    } catch (e) {
      // Esto captura errores de red o si el cuerpo de la respuesta no es un JSON válido.
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Error de conexión o respuesta inválida: ${e.toString()}',
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void resetToSearch() {
    setState(() {
      showRouteResult = false;
      routeResult = null;
      _endController.clear();
      _endLatitude = null;
      _endLongitude = null;
      _suggestions = [];
      _locationNames = [];
      _showSuggestions = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: !showRouteResult && !_isInBusMode,
      body: SafeArea(
        bottom: false,
        child: Stack(
          children: [
            // Elige la vista principal a mostrar
            if (_isInBusMode)
              _buildInBusModeView()
            else if (showRouteResult)
              _buildResultView()
            else
              _buildSearchView(),

            // El indicador de carga siempre va encima
            if (_isLoading)
              Container(
                color: Colors.black.withOpacity(0.3),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(color: Colors.blue),
                      const SizedBox(height: 16),
                      Text(
                        _loadingMessage,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
      bottomNavigationBar: _buildBottomBar(),
      floatingActionButton: _buildFab(),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }

  // Widget para construir la barra de navegación inferior dinámicamente
  Widget? _buildBottomBar() {
    if (_isInBusMode) return null; // Sin barra de navegación en modo bus
    if (showRouteResult) return _buildSolidNavBar();
    return _buildFloatingNavBar();
  }

  // Widget para construir el FAB dinámicamente
  Widget? _buildFab() {
    if (_isInBusMode || showRouteResult)
      return null; // Sin FAB si se muestran resultados o en modo bus

    return FloatingActionButton.extended(
      onPressed: _showBusTrackingModal,
      label: const Text('Estoy en el Bus'),
      icon: const Icon(Icons.directions_bus),
      backgroundColor: Colors.blue,
    );
  }

  Widget _buildInBusModeView() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.blue.shade800, Colors.lightBlue.shade500],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Sección superior con información de la ruta
              Column(
                children: [
                  const SizedBox(height: 40),
                  const Text(
                    'Viajando en',
                    style: TextStyle(fontSize: 22, color: Colors.white70),
                  ),
                  Text(
                    _currentBusRoute ?? 'Ruta Desconocida',
                    style: const TextStyle(
                      fontSize: 42,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),

              // Indicador de velocidad
              _buildSpeedIndicator(),

              // Botones de acción inferiores
              _buildActionButtons(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSpeedIndicator() {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.black.withOpacity(0.1),
            border: Border.all(color: Colors.white.withOpacity(0.3), width: 2),
          ),
          child: const Column(
            children: [
              Text(
                '42', // Velocidad de ejemplo
                style: TextStyle(
                  fontSize: 72,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              Text(
                'km/h',
                style: TextStyle(fontSize: 24, color: Colors.white70),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          'Velocidad Actual',
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _buildActionButtons() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 30),
      child: Column(
        children: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () {
                // Lógica para reportar irregularidad
              },
              icon: const Icon(Icons.warning_amber_rounded),
              label: const Text('Reportar Irregularidad'),
              style: ElevatedButton.styleFrom(
                foregroundColor: Colors.amber,
                backgroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                textStyle: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: () {
                setState(() {
                  _isInBusMode = false;
                  _currentBusRoute = null;
                });
              },
              child: const Text('Finalizar Viaje'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: const BorderSide(color: Colors.white, width: 2),
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                textStyle: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFloatingNavBar() {
    return SafeArea(
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
              selectedItemColor: Colors.black,
              unselectedItemColor: Colors.black87,
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
              currentIndex: 0,
              onTap: (index) {
                if (index == 2) {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const RutasScreen(),
                    ),
                  );
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
    );
  }

  Widget _buildSolidNavBar() {
    return BottomNavigationBar(
      backgroundColor: Colors.white,
      elevation: 8,
      type: BottomNavigationBarType.fixed,
      selectedItemColor: Colors.black,
      unselectedItemColor: Colors.black87,
      showUnselectedLabels: true,
      items: const [
        BottomNavigationBarItem(icon: Icon(Icons.place), label: 'Direcciones'),
        BottomNavigationBarItem(
          icon: Icon(Icons.location_city),
          label: 'Estaciones',
        ),
        BottomNavigationBarItem(icon: Icon(Icons.alt_route), label: 'Rutas'),
        BottomNavigationBarItem(
          icon: Icon(Icons.report_problem),
          label: 'Irregularidades',
        ),
      ],
      currentIndex: 0,
      onTap: (index) {
        if (index == 2) {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const RutasScreen()),
          );
        } else if (index == 3) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => const IrregularidadesScreen(),
            ),
          );
        }
      },
    );
  }

  Widget _buildSearchView() {
    // Usamos un Stack para superponer la UI de búsqueda sobre el mapa.
    return Stack(
      children: [
        // CAPA 1: El mapa ocupa todo el fondo.
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(center: _mapCenter, zoom: 15.0),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.example.app',
            ),
            MarkerLayer(
              markers: [
                if (_latitude != null && _longitude != null)
                  Marker(
                    point: LatLng(_latitude!, _longitude!),
                    width: 40,
                    height: 40,
                    child: _buildLocationMarker(),
                  ),
                if (_endLatitude != null && _endLongitude != null)
                  Marker(
                    point: LatLng(_endLatitude!, _endLongitude!),
                    width: 40,
                    height: 40,
                    child: _buildLocationMarker(isDestination: true),
                  ),
              ],
            ),
          ],
        ),

        // CAPA 2: La UI de búsqueda flota encima del mapa.
        SingleChildScrollView(
          child: Column(
            children: [
              // Contenedor para la sombra y el margen
              Container(
                margin: const EdgeInsets.only(top: 40, left: 20, right: 20),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 15,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                // ClipRRect para que el desenfoque respete los bordes redondeados
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 8.0, sigmaY: 8.0),
                    child: Container(
                      padding: const EdgeInsets.all(24.0),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.7),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text(
                            'UrbanTrack',
                            style: TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.bold,
                              color: Colors.black87,
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            '¿A dónde vamos?',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w500,
                              color: Colors.black54,
                            ),
                          ),
                          const SizedBox(height: 24),
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _startController,
                                  decoration: InputDecoration(
                                    hintText: 'Ubicación de inicio',
                                    prefixIcon: Icon(
                                      Icons.my_location,
                                      color: Colors.blue,
                                    ),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide: BorderSide.none,
                                    ),
                                    filled: true,
                                    fillColor: Colors.white.withOpacity(0.8),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Container(
                                decoration: BoxDecoration(
                                  color: Colors.blue,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: IconButton(
                                  icon: const Icon(
                                    Icons.gps_fixed,
                                    color: Colors.white,
                                  ),
                                  onPressed: _getCurrentLocation,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _endController,
                                  decoration: InputDecoration(
                                    hintText: 'Destino',
                                    prefixIcon: Icon(
                                      Icons.location_on,
                                      color: Colors.green,
                                    ),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide: BorderSide.none,
                                    ),
                                    filled: true,
                                    fillColor: Colors.white.withOpacity(0.8),
                                  ),
                                  onChanged: _searchLocations,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Container(
                                decoration: BoxDecoration(
                                  color: Colors.green,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: IconButton(
                                  icon: const Icon(
                                    Icons.search,
                                    color: Colors.white,
                                  ),
                                  onPressed: _isLoading ? null : calculateRoute,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

              // Las sugerencias aparecen debajo de la tarjeta
              if (_showSuggestions && _suggestions.isNotEmpty)
                Container(
                  height: 150,
                  margin: const EdgeInsets.symmetric(horizontal: 20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 8,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: ListView.builder(
                    shrinkWrap: true,
                    padding: EdgeInsets.zero,
                    itemCount: _suggestions.length,
                    itemBuilder: (context, index) {
                      return ListTile(
                        title: Text(_locationNames[index]),
                        onTap: () => _selectLocation(
                          _suggestions[index],
                          _locationNames[index],
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildResultView() {
    // Caso 1: No se encontró una ruta de autobús
    if (routeResult == null) {
      return Column(
        children: [
          // Encabezado simple
          Padding(
            padding: const EdgeInsets.symmetric(
              vertical: 16.0,
              horizontal: 24.0,
            ),
            child: Row(
              children: [
                Container(
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    shape: BoxShape.circle,
                  ),
                  padding: const EdgeInsets.all(12),
                  child: Icon(
                    Icons.error_outline,
                    size: 40,
                    color: Colors.blue.shade700,
                  ),
                ),
                const SizedBox(width: 16),
                const Text(
                  'UrbanTrack',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
              ],
            ),
          ),
          // Mensaje de error y botón para volver
          Expanded(
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(24),
                  topRight: Radius.circular(24),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 10,
                    spreadRadius: 5,
                  ),
                ],
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text(
                    'No se encontró una ruta de autobús.',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Intenta con otro destino.',
                    style: TextStyle(fontSize: 16, color: Colors.black54),
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton.icon(
                    onPressed: resetToSearch,
                    icon: const Icon(Icons.arrow_back),
                    label: const Text('Buscar otra ruta'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue.shade700,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 12,
                      ),
                      textStyle: const TextStyle(fontSize: 16),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }

    // Caso 2: Se encontró una ruta, construir la vista de resultados
    final List<dynamic> paradas = routeResult!['paradas_trayecto'];
    final Map<String, List<LatLng>> routeSegments = {};
    final Map<String, Color> routeColors = {};
    final List<Marker> stopMarkers = [];
    final List<LatLng> allPointsForBounds = [];

    // Paleta de colores para las rutas
    final List<Color> colors = [
      Colors.blue.shade700,
      Colors.green.shade600,
      Colors.purple.shade600,
      Colors.orange.shade800,
      Colors.teal.shade500,
      Colors.red.shade600,
    ];
    int colorIndex = 0;

    // Agregar punto de origen a los límites del mapa
    if (_latitude != null && _longitude != null) {
      allPointsForBounds.add(LatLng(_latitude!, _longitude!));
    }

    // Procesar paradas para agrupar por ruta, asignar colores y crear marcadores
    for (var parada in paradas) {
      final String rutaNombre = parada['ruta_nombre'] ?? 'Ruta Desconocida';
      if (!routeSegments.containsKey(rutaNombre)) {
        routeSegments[rutaNombre] = [];
        routeColors[rutaNombre] = colors[colorIndex % colors.length];
        colorIndex++;
      }

      final lat = parada['latitude'];
      final lon = parada['longitude'];
      if (lat != null && lon != null) {
        final point = LatLng(lat, lon);
        routeSegments[rutaNombre]!.add(point);
        allPointsForBounds.add(point);
        stopMarkers.add(
          Marker(
            point: point,
            width: 20,
            height: 20,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                border: Border.all(color: routeColors[rutaNombre]!, width: 4),
              ),
            ),
          ),
        );
      }
    }

    // Agregar punto de destino a los límites del mapa
    if (_endLatitude != null && _endLongitude != null) {
      allPointsForBounds.add(LatLng(_endLatitude!, _endLongitude!));
    }

    // Construir las polilíneas para el mapa
    final List<Polyline> polylines = routeSegments.entries.map((entry) {
      return Polyline(
        points: entry.value,
        strokeWidth: 5.0,
        color: routeColors[entry.key]!,
      );
    }).toList();

    // Construir los límites del mapa a partir de todos los puntos.
    final LatLngBounds? bounds = allPointsForBounds.isNotEmpty
        ? LatLngBounds.fromPoints(allPointsForBounds)
        : null;

    // Construir los segmentos para la línea de tiempo
    final List<Map<String, dynamic>> segments = [];
    final double distOrigen =
        routeResult!['distancia_origen_primera_parada_metros'] ?? 0.0;
    final double distDestino =
        routeResult!['distancia_ultima_parada_destino_metros'] ?? 0.0;

    segments.add({
      'tipo': 'caminar',
      'descripcion':
          'Camina ${distOrigen.toStringAsFixed(0)}m hasta la parada "${paradas.first['nombre']}".',
      'color': Colors.grey.shade600,
    });

    for (final parada in paradas) {
      final String rutaNombre = parada['ruta_nombre'] ?? 'Ruta Desconocida';
      final lat = parada['latitude'];
      final lon = parada['longitude'];
      LatLng? point;
      if (lat != null && lon != null) {
        point = LatLng(lat, lon);
      }

      segments.add({
        'tipo': 'bus_stop',
        'descripcion': parada['nombre'] ?? 'Parada sin nombre',
        'ruta_nombre': rutaNombre,
        'color': routeColors[rutaNombre]!,
        'point': point,
      });
    }

    segments.add({
      'tipo': 'caminar',
      'descripcion':
          'Desde "${paradas.last['nombre']}", camina ${distDestino.toStringAsFixed(0)}m hasta tu destino.',
      'color': Colors.grey.shade600,
    });

    return Column(
      children: [
        // 1. Mapa
        SizedBox(
          height: MediaQuery.of(context).size.height * 0.4,
          width: double.infinity,
          child: FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCameraFit: bounds != null
                  ? CameraFit.bounds(
                      bounds: bounds,
                      padding: const EdgeInsets.all(30),
                    )
                  : null,
              initialCenter: _mapCenter,
              initialZoom: 14,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.app',
              ),
              PolylineLayer(polylines: polylines),
              MarkerLayer(
                markers: [
                  // Marcador de Origen
                  if (_latitude != null && _longitude != null)
                    Marker(
                      point: LatLng(_latitude!, _longitude!),
                      width: 40,
                      height: 40,
                      child: _buildLocationMarker(),
                    ),
                  // Marcador de Destino
                  if (_endLatitude != null && _endLongitude != null)
                    Marker(
                      point: LatLng(_endLatitude!, _endLongitude!),
                      width: 40,
                      height: 40,
                      child: _buildLocationMarker(isDestination: true),
                    ),
                  // Marcadores de Paradas
                  ...stopMarkers,
                ],
              ),
            ],
          ),
        ),
        // 2. Zona de información con el contenido de la ruta
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(24),
                topRight: Radius.circular(24),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 10,
                  spreadRadius: 5,
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Tu Ruta Sugerida',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      TextButton.icon(
                        onPressed: resetToSearch,
                        icon: const Icon(Icons.arrow_back, size: 18),
                        label: const Text('Otra ruta'),
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.blue.shade700,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: RouteTimeline(
                    segments: segments,
                    onStopTap: (point) {
                      _mapController.move(point, 17.0);
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// Widget para la línea de tiempo completa
class RouteTimeline extends StatelessWidget {
  final List<Map<String, dynamic>> segments;
  final Function(LatLng)? onStopTap;

  const RouteTimeline({Key? key, required this.segments, this.onStopTap})
    : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      itemCount: segments.length,
      itemBuilder: (context, index) {
        final segment = segments[index];
        final point = segment['point'] as LatLng?;
        return RouteStepItem(
          description: segment['descripcion'] ?? 'Paso sin descripción',
          rutaNombre: segment['ruta_nombre'],
          color: segment['color'] ?? Colors.blue,
          type: segment['tipo'] ?? 'bus_stop',
          isFirst: index == 0,
          isLast: index == segments.length - 1,
          onTap: onStopTap != null && point != null
              ? () => onStopTap!(point)
              : null,
        );
      },
    );
  }
}

// Widget para cada paso de la ruta
class RouteStepItem extends StatelessWidget {
  final String description;
  final String? rutaNombre;
  final Color color;
  final String type;
  final bool isFirst;
  final bool isLast;
  final VoidCallback? onTap;

  const RouteStepItem({
    Key? key,
    required this.description,
    this.rutaNombre,
    required this.color,
    required this.type,
    this.isFirst = false,
    this.isLast = false,
    this.onTap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    Widget content = IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Columna de la línea y el ícono
          Column(
            children: [
              Container(
                width: 2,
                height: 20,
                color: isFirst ? Colors.transparent : color,
              ),
              _buildIcon(),
              Expanded(
                child: Container(
                  width: 2,
                  color: isLast ? Colors.transparent : color,
                ),
              ),
            ],
          ),
          const SizedBox(width: 16),
          // Descripción del paso
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(description, style: const TextStyle(fontSize: 16)),
                  if (rutaNombre != null && rutaNombre!.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      rutaNombre!,
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey.shade700,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );

    if (type == 'bus_stop' && onTap != null) {
      return InkWell(onTap: onTap, child: content);
    }

    return content;
  }

  Widget _buildIcon() {
    if (type == 'caminar') {
      return Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color, width: 2),
        ),
        child: Icon(Icons.directions_walk, color: color, size: 24),
      );
    }
    return Container(
      width: 20,
      height: 20,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 3),
      ),
    );
  }
}
