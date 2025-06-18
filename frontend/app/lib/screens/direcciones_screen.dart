import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geocoding/geocoding.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:ui'; // Necesario para ImageFilter
import 'package:app/screens/rutas_screen.dart';
import 'package:app/screens/irregularidades_screen.dart';
import 'package:app/screens/modo_viaje_screen.dart';
import 'package:provider/provider.dart';
import '../main.dart';
import 'package:app/providers/auth_provider.dart';
import 'estaciones_screen.dart';

class DireccionesScreen extends StatefulWidget {
  final Position? initialPosition;
  const DireccionesScreen({super.key, this.initialPosition});

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
  bool _isFetchingRutas = false;
  bool _trackingSessionStarted = false;

  // Nuevas variables de estado para la ruta dibujada en el mapa
  List<Polyline> _routePolylines = [];
  List<Marker> _routeStopMarkers = [];

  // Se convierte en una variable de estado que se llenará desde la API.
  List<Map<String, dynamic>> _rutasDisponibles = [];

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
    _fetchRutasDisponibles(); // Llama al método para obtener las rutas al iniciar.
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

  Future<void> _fetchRutasDisponibles() async {
    setState(() {
      _isFetchingRutas = true;
    });

    try {
      final response = await http.get(
        Uri.parse('$apiBaseUrl/api/ruta/rutas'),
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(utf8.decode(response.bodyBytes));
        // Guardar la lista completa de rutas (objetos con id y nombre)
        final List<Map<String, dynamic>> rutas =
            List<Map<String, dynamic>>.from(data);
        setState(() {
          _rutasDisponibles = rutas;
        });
      } else {
        // Manejar el error, tal vez mostrando un SnackBar.
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No se pudieron cargar las rutas.')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al obtener rutas: ${e.toString()}')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isFetchingRutas = false;
        });
      }
    }
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
                    _isFetchingRutas
                        ? const Center(child: CircularProgressIndicator())
                        : DropdownButtonFormField<String>(
                            value: selectedRoute,
                            hint: const Text('Selecciona tu ruta'),
                            isExpanded: true,
                            onChanged: (String? newValue) {
                              setModalState(() {
                                selectedRoute = newValue;
                              });
                            },
                            items: _rutasDisponibles.map<DropdownMenuItem<String>>((
                              Map<String, dynamic> ruta,
                            ) {
                              return DropdownMenuItem<String>(
                                value:
                                    ruta['nombre']
                                        as String, // El valor sigue siendo el nombre
                                child: Text(ruta['nombre'] as String),
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
                            ? () async {
                                // Capturamos el Navigator y el ScaffoldMessenger ANTES de cualquier operación asíncrona
                                // o de cerrar el modal.
                                final navigator = Navigator.of(context);
                                final scaffoldMessenger = ScaffoldMessenger.of(
                                  context,
                                );

                                final auth = Provider.of<AuthProvider>(
                                  context,
                                  listen: false,
                                );
                                final user = auth.user;
                                final token = auth.token;

                                if (user == null || token == null) {
                                  navigator
                                      .pop(); // Usamos la referencia capturada
                                  scaffoldMessenger.showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'Error de autenticación. Vuelva a iniciar sesión.',
                                      ),
                                    ),
                                  );
                                  return;
                                }

                                final routeData = _rutasDisponibles.firstWhere(
                                  (ruta) => ruta['nombre'] == selectedRoute,
                                  orElse: () => {},
                                );
                                final routeId = routeData['id'];

                                if (routeId == null) {
                                  navigator
                                      .pop(); // Usamos la referencia capturada
                                  scaffoldMessenger.showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'No se pudo encontrar el ID de la ruta seleccionada.',
                                      ),
                                    ),
                                  );
                                  return;
                                }

                                // Cerrar el modal antes de la operación asíncrona
                                navigator.pop();

                                setState(() {
                                  _isLoading = true;
                                  _loadingMessage = 'Iniciando modo viaje...';
                                });

                                try {
                                  final response = await http.post(
                                    Uri.parse(
                                      '$apiBaseUrl/api/tracking/set-on-bus',
                                    ),
                                    headers: {
                                      'Content-Type':
                                          'application/json; charset=UTF-8',
                                      'Authorization': 'Bearer $token',
                                    },
                                    body: jsonEncode({
                                      'user_id': user.id,
                                      'reported_route_id': routeId,
                                    }),
                                  );

                                  if (mounted) {
                                    if (response.statusCode == 200) {
                                      // Usamos la referencia capturada para navegar
                                      navigator.push(
                                        MaterialPageRoute(
                                          builder: (context) => ModoViajeScreen(
                                            rutaSeleccionada: selectedRoute!,
                                          ),
                                        ),
                                      );
                                    } else {
                                      final errorBody = jsonDecode(
                                        utf8.decode(response.bodyBytes),
                                      );
                                      // Usamos la referencia capturada para mostrar el error
                                      scaffoldMessenger.showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            'Error: ${errorBody['detail']}',
                                          ),
                                        ),
                                      );
                                    }
                                  }
                                } catch (e) {
                                  if (mounted) {
                                    scaffoldMessenger.showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          'Error de red: ${e.toString()}',
                                        ),
                                      ),
                                    );
                                  }
                                } finally {
                                  if (mounted) {
                                    setState(() => _isLoading = false);
                                  }
                                }
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

      final response = await http.post(
        Uri.parse('$apiBaseUrl/api/ruta/calculate_route'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(requestBody),
      );

      final responseData = jsonDecode(response.body);

      if (response.statusCode == 200 &&
          responseData.containsKey('paradas_trayecto') &&
          (responseData['paradas_trayecto'] as List).isNotEmpty) {
        // --- PROCESAMIENTO DE LA RUTA PARA EL MAPA ---
        final List<dynamic> paradas = responseData['paradas_trayecto'];
        final Map<String, List<LatLng>> routeSegments = {};
        final Map<String, Color> routeColors = {};
        final List<Marker> stopMarkers = [];
        final List<LatLng> allPointsForBounds = [
          LatLng(_latitude!, _longitude!),
          LatLng(_endLatitude!, _endLongitude!),
        ];

        final List<Color> colors = [
          Colors.blue.shade700,
          Colors.green.shade600,
          Colors.purple.shade600,
        ];
        int colorIndex = 0;

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
                    border: Border.all(
                      color: routeColors[rutaNombre]!,
                      width: 4,
                    ),
                  ),
                ),
              ),
            );
          }
        }

        final List<Polyline> polylines = routeSegments.entries.map((entry) {
          return Polyline(
            points: entry.value,
            strokeWidth: 5.0,
            color: routeColors[entry.key]!,
          );
        }).toList();

        final LatLngBounds bounds = LatLngBounds.fromPoints(allPointsForBounds);
        // --- FIN DEL PROCESAMIENTO ---

        setState(() {
          showRouteResult = true;
          routeResult = responseData;
          _routePolylines = polylines;
          _routeStopMarkers = stopMarkers;
        });

        // Mover el mapa para que se ajuste a la ruta
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _mapController.fitCamera(
            CameraFit.bounds(bounds: bounds, padding: const EdgeInsets.all(50)),
          );
        });

        _startTrackingSession();
      } else {
        setState(() {
          showRouteResult = true;
          routeResult = null;
        });
      }
    } catch (e) {
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
      _trackingSessionStarted = false; // Reiniciar al buscar otra ruta
      // Limpiar las capas del mapa
      _routePolylines = [];
      _routeStopMarkers = [];
    });
  }

  Future<void> _startTrackingSession() async {
    if (_trackingSessionStarted) return;

    final auth = Provider.of<AuthProvider>(context, listen: false);
    final user = auth.user;
    final token = auth.token;

    if (user == null || token == null) {
      print("startTrackingSession: El usuario no está autenticado. Abortando.");
      return;
    }

    final firstRouteName =
        routeResult?['paradas_trayecto']?.first?['ruta_nombre'] as String?;

    if (firstRouteName == null) {
      print(
        "startTrackingSession: No se pudo extraer 'ruta_nombre' del resultado del cálculo de ruta.",
      );
      return;
    }

    print(
      "startTrackingSession: Buscando ID para la ruta '$firstRouteName'...",
    );

    Map<String, dynamic>? routeData;
    try {
      routeData = _rutasDisponibles.firstWhere(
        (ruta) => ruta['nombre'] == firstRouteName,
      );
    } catch (e) {
      routeData = null;
      print(
        "startTrackingSession: Ocurrió un error al buscar la ruta en la lista: $e",
      );
    }

    if (routeData == null) {
      print(
        "startTrackingSession: No se encontró la ruta '$firstRouteName' en la lista de rutas precargadas (_rutasDisponibles).",
      );
      return;
    }

    final routeId = routeData['id'];

    if (routeId == null) {
      print(
        "startTrackingSession: La ruta '$firstRouteName' se encontró, pero no tiene un 'id'.",
      );
      return;
    }

    print(
      "startTrackingSession: Ruta encontrada. ID: $routeId. Realizando la llamada a la API...",
    );

    try {
      final response = await http.post(
        Uri.parse('$apiBaseUrl/api/tracking/start-session'),
        headers: {
          'Content-Type': 'application/json; charset=UTF-8',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({'user_id': user.id, 'selected_route_id': routeId}),
      );
      if (response.statusCode == 200 || response.statusCode == 201) {
        print(
          'startTrackingSession: ÉXITO. Sesión de seguimiento iniciada para la ruta $routeId.',
        );
        if (mounted) {
          // Usamos un Post-Frame Callback para actualizar el estado DESPUÉS
          // de que el build actual se complete, evitando así la excepción.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              setState(() => _trackingSessionStarted = true);
            }
          });
        }
      } else {
        print(
          'startTrackingSession: FALLO. El servidor respondió con ${response.statusCode}. Body: ${response.body}',
        );
      }
    } catch (e) {
      print("startTrackingSession: Excepción al realizar la llamada HTTP: $e");
    }
  }

  Future<void> _setUserOnBus() async {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final user = auth.user;
    final token = auth.token;
    final firstRouteName =
        routeResult?['paradas_trayecto']?.first?['ruta_nombre'] as String?;

    if (user == null || token == null || firstRouteName == null) return;

    Map<String, dynamic>? routeData;
    try {
      routeData = _rutasDisponibles.firstWhere(
        (ruta) => ruta['nombre'] == firstRouteName,
      );
    } catch (e) {
      routeData = null;
    }

    if (routeData == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'No se pudieron encontrar los detalles de la ruta $firstRouteName.',
          ),
        ),
      );
      return;
    }
    final routeId = routeData['id'];
    if (routeId == null) return;

    setState(() {
      _isLoading = true;
      _loadingMessage = 'Confirmando que estás a bordo...';
    });

    try {
      final response = await http.post(
        Uri.parse('$apiBaseUrl/api/tracking/set-on-bus'),
        headers: {
          'Content-Type': 'application/json; charset=UTF-8',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({'user_id': user.id, 'reported_route_id': routeId}),
      );

      if (mounted) {
        if (response.statusCode == 200) {
          // Navegamos a la pantalla de modo viaje.
          // En un futuro, aquí es donde se conectaría el WebSocket.
          setState(() {
            _isInBusMode = true;
            _currentBusRoute = firstRouteName;
          });
        } else {
          final errorBody = jsonDecode(utf8.decode(response.bodyBytes));
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error al confirmar: ${errorBody['detail']}'),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error de red: ${e.toString()}')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true, // Permite que el cuerpo se extienda detrás de la barra
      body: Stack(
        children: [
          // CAPA 1: El mapa siempre está de fondo
          _buildMapView(),

          // CAPA 2: Contenido que cambia según el estado
          SafeArea(
            bottom: false,
            child: _isInBusMode
                ? _buildInBusModeOverlay()
                : showRouteResult
                ? _buildResultView()
                : _buildSearchView(),
          ),

          // CAPA 3: El indicador de carga siempre va encima de todo
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
      bottomNavigationBar: _buildBottomBar(),
      floatingActionButton: _buildFab(),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }

  // Widget para construir la barra de navegación inferior dinámicamente
  Widget? _buildBottomBar() {
    if (showRouteResult && !_isInBusMode) return _buildSolidNavBar();
    return _buildFloatingNavBar();
  }

  // Widget para construir el FAB dinámicamente
  Widget? _buildFab() {
    if (_isInBusMode || showRouteResult) return null;

    return FloatingActionButton.extended(
      onPressed: _showBusTrackingModal,
      label: const Text('Estoy en el Bus'),
      icon: const Icon(Icons.directions_bus),
      backgroundColor: Colors.blue,
    );
  }

  Widget _buildInBusModeOverlay() {
    return Stack(
      children: [
        // Panel superior
        Positioned(
          top: 10,
          left: 20,
          right: 20,
          child: _buildGlassmorphismContainer(
            color: Colors.lightBlue.shade300,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Viajando en ruta',
                        style: TextStyle(fontSize: 16, color: Colors.white70),
                      ),
                      Text(
                        _currentBusRoute ?? 'Desconocida',
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),

        // Elementos inferiores
        Positioned(
          bottom:
              140, // Elevado para no superponerse con la barra de navegación
          left: 20,
          right: 20,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              // Panel de velocidad
              _buildGlassmorphismContainer(
                color: Colors.lightBlue.shade300,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.speed_outlined,
                      color: Colors.white,
                      size: 24,
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      '42', // Velocidad de ejemplo
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Text(
                      'km/h',
                      style: TextStyle(fontSize: 14, color: Colors.white70),
                    ),
                  ],
                ),
              ),
              ElevatedButton(
                onPressed: () => _showEndTripConfirmationDialog(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red.shade400,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                ),
                child: const Text('Finalizar'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _showEndTripConfirmationDialog(BuildContext context) async {
    return showDialog<void>(
      context: context,
      barrierDismissible: true, // user can tap outside to dismiss
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          backgroundColor: Colors.grey[850],
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16.0),
          ),
          title: const Text(
            'Finalizar Viaje',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          content: const SingleChildScrollView(
            child: ListBody(
              children: <Widget>[
                Text(
                  '¿Estás seguro de que deseas finalizar el viaje?',
                  style: TextStyle(color: Colors.white70),
                ),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(); // Dismiss the dialog
              },
              style: TextButton.styleFrom(foregroundColor: Colors.white70),
              child: const Text('No'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(); // Dismiss the dialog
                setState(() {
                  _isInBusMode = false;
                  resetToSearch();
                });
              },
              style: TextButton.styleFrom(
                foregroundColor: Colors.red.shade400,
                backgroundColor: Colors.red.shade400.withOpacity(0.1),
              ),
              child: const Text('Sí, Finalizar'),
            ),
          ],
        );
      },
    );
  }

  // Helper para crear los contenedores con efecto de vidrio
  Widget _buildGlassmorphismContainer({required Widget child, Color? color}) {
    final bgColor = color ?? Colors.white;
    final isBlue = color != null;

    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8.0, sigmaY: 8.0),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 20),
          decoration: BoxDecoration(
            color: bgColor.withOpacity(isBlue ? 0.4 : 0.6),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withOpacity(0.2)),
          ),
          child: child,
        ),
      ),
    );
  }

  Widget _buildFloatingNavBar() {
    // Determinar el estilo basado en el modo actual
    final bool isBusMode = _isInBusMode;
    final Color navBarColor = isBusMode
        ? Colors.lightBlue.shade300.withOpacity(0.4)
        : Colors.white.withOpacity(0.8);
    final Color selectedColor = isBusMode ? Colors.white : Colors.blue.shade700;
    final Color unselectedColor = isBusMode ? Colors.white70 : Colors.black54;

    return SafeArea(
      child: Container(
        padding: const EdgeInsets.all(12.0),
        margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        decoration: BoxDecoration(
          color: navBarColor,
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
              selectedItemColor: selectedColor,
              unselectedItemColor: unselectedColor,
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
                if (index == 1) {
                  Navigator.pushNamed(context, '/estaciones');
                } else if (index == 2) {
                  Navigator.pushNamed(context, '/rutas');
                } else if (index == 3) {
                  Navigator.pushNamed(context, '/irregularidades');
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
      backgroundColor: Colors.lightBlue.shade300,
      elevation: 8,
      type: BottomNavigationBarType.fixed,
      selectedItemColor: Colors.white,
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

  Widget _buildMapView() {
    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(initialCenter: _mapCenter, initialZoom: 15.0),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.example.app',
        ),
        // Dibuja las polilíneas de la ruta si existen
        if (_routePolylines.isNotEmpty)
          PolylineLayer(polylines: _routePolylines),
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
            // Dibuja los marcadores de las paradas de la ruta si existen
            ..._routeStopMarkers,
          ],
        ),
      ],
    );
  }

  Widget _buildSearchView() {
    // La UI de búsqueda flota encima del mapa.
    return SingleChildScrollView(
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

    // --- PROCESAMIENTO PARA LA LÍNEA DE TIEMPO ---
    final List<dynamic> paradas = routeResult!['paradas_trayecto'];
    final Map<String, Color> routeColors = {};
    final List<Color> colors = [
      Colors.blue.shade700,
      Colors.green.shade600,
      Colors.purple.shade600,
    ];
    int colorIndex = 0;
    for (var parada in paradas) {
      final String rutaNombre = parada['ruta_nombre'] ?? 'Ruta Desconocida';
      if (!routeColors.containsKey(rutaNombre)) {
        routeColors[rutaNombre] = colors[colorIndex % colors.length];
        colorIndex++;
      }
    }

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
    // --- FIN DEL PROCESAMIENTO DE LÍNEA DE TIEMPO ---

    return DraggableScrollableSheet(
      initialChildSize: 0.5,
      minChildSize: 0.2,
      maxChildSize: 0.8,
      builder: (BuildContext context, ScrollController scrollController) {
        return Container(
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
            children: [
              // "Handle" para indicar que es deslizable
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8.0),
                child: Container(
                  width: 40,
                  height: 5,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
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
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Stack(
                  children: [
                    RouteTimeline(
                      controller: scrollController, // Usar el scroll controller
                      segments: segments,
                      onStopTap: (point) {
                        _mapController.move(point, 17.0);
                      },
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                    ),
                    Positioned(
                      bottom: 0,
                      left: 0,
                      right: 0,
                      child: Container(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.white.withOpacity(0.0),
                              Colors.white.withOpacity(0.7),
                              Colors.white,
                            ],
                            stops: const [0.0, 0.5, 1.0],
                          ),
                        ),
                        child: ElevatedButton.icon(
                          onPressed: _isLoading ? null : _setUserOnBus,
                          icon: const Icon(
                            Icons.directions_bus,
                            color: Colors.white,
                          ),
                          label: const Text(
                            'Estoy en el Bus',
                            style: TextStyle(fontSize: 18, color: Colors.white),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green.shade600,
                            minimumSize: const Size(double.infinity, 50),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
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
        );
      },
    );
  }
}

// Widget para la línea de tiempo completa
class RouteTimeline extends StatelessWidget {
  final List<Map<String, dynamic>> segments;
  final Function(LatLng)? onStopTap;
  final EdgeInsetsGeometry? padding;
  final ScrollController? controller; // Añadir el controller

  const RouteTimeline({
    super.key,
    required this.segments,
    this.onStopTap,
    this.padding,
    this.controller, // Aceptar el controller
  });

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      controller: controller, // Usar el controller
      padding: padding ?? const EdgeInsets.symmetric(horizontal: 16.0),
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
    super.key,
    required this.description,
    this.rutaNombre,
    required this.color,
    required this.type,
    this.isFirst = false,
    this.isLast = false,
    this.onTap,
  });

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
