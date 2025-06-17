import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'dart:math';
import 'package:app/screens/irregularidades_screen.dart';

class RutaDetailScreen extends StatefulWidget {
  final Map<String, dynamic> ruta;

  const RutaDetailScreen({Key? key, required this.ruta}) : super(key: key);

  @override
  State<RutaDetailScreen> createState() => _RutaDetailScreenState();
}

class _RutaDetailScreenState extends State<RutaDetailScreen> {
  final MapController _mapController = MapController();
  MapCamera? _mapCamera;
  List<Marker> _markers = [];
  List<dynamic> _paradas = [];
  List<LatLng> _polylineCoordinates = [];

  @override
  void initState() {
    super.initState();
    _paradas = widget.ruta['paradas'] ?? [];
    _paradas.sort(
      (a, b) =>
          (a['orden_en_ruta'] as int).compareTo(b['orden_en_ruta'] as int),
    );
    _buildMarkers();
    _buildPolyline();
  }

  void _buildMarkers() {
    final List<Marker> markers = [];
    for (var parada in _paradas) {
      final ubicacion = parada['ubicacion'];
      if (ubicacion != null &&
          ubicacion['latitude'] != null &&
          ubicacion['longitude'] != null) {
        final lat = ubicacion['latitude'];
        final lon = ubicacion['longitude'];
        markers.add(
          Marker(
            point: LatLng(lat, lon),
            width: 40,
            height: 40,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.8),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
              ),
              child: const Icon(
                Icons.directions_bus,
                color: Colors.white,
                size: 20,
              ),
            ),
          ),
        );
      }
    }
    setState(() {
      _markers = markers;
    });
  }

  void _buildPolyline() {
    final List<LatLng> points = [];
    for (var parada in _paradas) {
      final ubicacion = parada['ubicacion'];
      if (ubicacion != null &&
          ubicacion['latitude'] != null &&
          ubicacion['longitude'] != null) {
        points.add(LatLng(ubicacion['latitude'], ubicacion['longitude']));
      }
    }
    setState(() {
      _polylineCoordinates = points;
    });
  }

  void _centerMapOnParada(dynamic parada) {
    final camera = _mapController.camera;
    final ubicacion = parada['ubicacion'];

    if (ubicacion != null &&
        ubicacion['latitude'] != null &&
        ubicacion['longitude'] != null) {
      final targetLatLng = LatLng(
        ubicacion['latitude'],
        ubicacion['longitude'],
      );

      final targetPoint = camera.project(targetLatLng);

      final screenHeight = MediaQuery.of(context).size.height;
      final verticalOffset = screenHeight * 0.25;

      final newCenterPoint = Point(
        targetPoint.x,
        targetPoint.y + verticalOffset,
      );

      final newCenterLatLng = camera.unproject(newCenterPoint);

      _mapController.move(newCenterLatLng, camera.zoom);
    }
  }

  LatLng get _mapCenter {
    if (_paradas.isNotEmpty) {
      final primeraParada = _paradas.first['ubicacion'];
      if (primeraParada != null) {
        return LatLng(primeraParada['latitude'], primeraParada['longitude']);
      }
    }
    return LatLng(10.3910, -75.4794);
  }

  @override
  Widget build(BuildContext context) {
    final nombreRuta = widget.ruta['nombre'] ?? 'Detalle de Ruta';

    return Scaffold(
      extendBodyBehindAppBar: true,
      body: Stack(
        children: [
          // CAPA 1: Mapa de fondo. Debe ser el primer hijo del Stack.
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(center: _mapCenter, zoom: 14.0),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.app',
              ),
              PolylineLayer(
                polylines: [
                  Polyline(
                    points: _polylineCoordinates,
                    strokeWidth: 4.0,
                    color: Colors.blue.withOpacity(0.8),
                    borderStrokeWidth: 2.0,
                    borderColor: Colors.white.withOpacity(0.6),
                  ),
                ],
              ),
              MarkerLayer(markers: _markers),
            ],
          ),

          // CAPA 2: "AppBar" flotante en formato de isla
          Positioned(
            top: MediaQuery.of(context).padding.top + 10,
            left: 20,
            right: 20,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.15),
                    blurRadius: 20,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 10.0, sigmaY: 10.0),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      vertical: 16.0,
                      horizontal: 16.0,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.75),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      children: [
                        IconButton(
                          icon: const Icon(
                            Icons.arrow_back,
                            color: Colors.black87,
                          ),
                          onPressed: () => Navigator.of(context).pop(),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Text(
                            nombreRuta,
                            style: const TextStyle(
                              color: Colors.black87,
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),

          // CAPA 3: Panel de paradas deslizable
          DraggableScrollableSheet(
            initialChildSize: 0.4,
            minChildSize: 0.15,
            maxChildSize: 0.5,
            builder: (BuildContext context, ScrollController scrollController) {
              return ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(24),
                ),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 10.0, sigmaY: 10.0),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.5),
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(24),
                      ),
                    ),
                    child: SingleChildScrollView(
                      controller: scrollController,
                      child: Column(
                        children: [
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8.0),
                            child: Container(
                              width: 40,
                              height: 5,
                              decoration: BoxDecoration(
                                color: Colors.grey.shade400,
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                          const Padding(
                            padding: EdgeInsets.only(bottom: 8.0),
                            child: Text(
                              'Paradas del Recorrido',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.black87,
                              ),
                            ),
                          ),
                          ListView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16.0,
                            ),
                            itemCount: _paradas.length,
                            itemBuilder: (context, index) {
                              final parada = _paradas[index];
                              return _buildStopItem(
                                parada,
                                index == 0,
                                index == _paradas.length - 1,
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        backgroundColor: Colors.white,
        elevation: 8, // Una ligera sombra para separarlo del contenido
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
          BottomNavigationBarItem(icon: Icon(Icons.alt_route), label: 'Rutas'),
          BottomNavigationBarItem(
            icon: Icon(Icons.report_problem),
            label: 'Irregularidades',
          ),
        ],
        currentIndex: 2, // Se mantiene en Rutas
        onTap: (index) {
          if (index == 0) {
            // Regresa a la pantalla de Direcciones
            Navigator.of(context).popUntil((route) => route.isFirst);
          } else if (index == 2) {
            // Regresa a la lista de Rutas
            Navigator.pop(context);
          } else if (index == 3) {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const IrregularidadesScreen(),
              ),
            );
          }
          // Aquí se podrían manejar las otras pestañas en el futuro
        },
      ),
    );
  }

  Widget _buildStopItem(dynamic parada, bool isFirst, bool isLast) {
    final nombreParada = parada['nombre'] ?? 'Parada sin nombre';
    return InkWell(
      onTap: () => _centerMapOnParada(parada),
      child: IntrinsicHeight(
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20.0),
              child: Column(
                children: [
                  Container(
                    width: 2,
                    height: 20,
                    color: isFirst ? Colors.transparent : Colors.grey.shade400,
                  ),
                  Container(
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    height: 16,
                    width: 16,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.blue.shade600, width: 3),
                    ),
                  ),
                  Expanded(
                    child: Container(
                      width: 2,
                      color: isLast ? Colors.transparent : Colors.grey.shade400,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Card(
                margin: const EdgeInsets.symmetric(
                  vertical: 8.0,
                  horizontal: 4.0,
                ),
                elevation: 2,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Text(
                    nombreParada,
                    style: const TextStyle(fontSize: 16),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
