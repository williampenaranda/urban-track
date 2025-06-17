import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'dart:ui';
import 'package:app/screens/rutas_screen.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:math';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:app/providers/auth_provider.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import '../main.dart';

class IrregularidadesScreen extends StatefulWidget {
  const IrregularidadesScreen({Key? key}) : super(key: key);

  @override
  State<IrregularidadesScreen> createState() => _IrregularidadesScreenState();
}

class _IrregularidadesScreenState extends State<IrregularidadesScreen> {
  final MapController _mapController = MapController();
  final TextEditingController _locationController = TextEditingController();
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  bool _isReporting = false;
  LatLng? _markerPosition;
  String? _loadingMessage;
  String? _titleErrorText;
  String? _locationErrorText;
  final GlobalKey _mapContainerKey = GlobalKey();

  // State for location search
  List<Location> _suggestions = [];
  List<String> _suggestionNames = [];
  bool _isSearching = false;
  final FocusNode _locationFocusNode = FocusNode();
  final _debouncer = Debouncer(milliseconds: 500);

  // State for Info Window
  OverlayEntry? _infoWindowOverlay;
  dynamic _selectedIrregularity;
  final LayerLink _markerLink = LayerLink();
  StreamSubscription? _mapEventSubscription;

  // State for active irregularities
  List<dynamic> _irregularities = [];

  @override
  void initState() {
    super.initState();
    _fetchIrregularities();

    // Listener to reposition the info window when the map moves
    _mapEventSubscription = _mapController.mapEventStream.listen((_) {
      if (_infoWindowOverlay != null) {
        _removeInfoWindow();
      }
    });

    _locationFocusNode.addListener(() {
      if (!_locationFocusNode.hasFocus) {
        setState(() {
          _suggestions = [];
          _suggestionNames = [];
        });
      }
    });
  }

  @override
  void dispose() {
    _mapEventSubscription?.cancel();
    _locationController.dispose();
    _titleController.dispose();
    _descriptionController.dispose();
    _locationFocusNode.dispose();
    _infoWindowOverlay?.remove();
    super.dispose();
  }

  void _removeInfoWindow() {
    _infoWindowOverlay?.remove();
    _infoWindowOverlay = null;
    if (mounted) {
      setState(() {
        _selectedIrregularity = null;
      });
    }
  }

  Future<void> _fetchIrregularities() async {
    try {
      final response = await http.get(
        Uri.parse('$apiBaseUrl/api/irregularities/active'),
      );

      if (response.statusCode == 200) {
        if (mounted) {
          final List<dynamic> data = jsonDecode(
            utf8.decode(response.bodyBytes),
          );
          setState(() {
            _irregularities = data;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al cargar irregularidades: ${e.toString()}'),
          ),
        );
      }
    }
  }

  List<Marker> _buildMarkers() {
    final List<Marker> markers = [];
    for (final irregularity in _irregularities) {
      final ubicacion = irregularity['ubicacion'];
      if (ubicacion != null &&
          ubicacion['latitude'] != null &&
          ubicacion['longitude'] != null) {
        markers.add(
          Marker(
            point: LatLng(ubicacion['latitude'], ubicacion['longitude']),
            width: 40,
            height: 40,
            child: GestureDetector(
              onTap: () => _handleMarkerTap(context, irregularity),
              child: CompositedTransformTarget(
                link: _selectedIrregularity?['id'] == irregularity['id']
                    ? _markerLink
                    : LayerLink(),
                child: Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.orange.withOpacity(0.9),
                    border: Border.all(
                      color: _selectedIrregularity?['id'] == irregularity['id']
                          ? Colors.blue
                          : Colors.white,
                      width: 2,
                    ),
                  ),
                  child: const Icon(
                    Icons.warning_amber_rounded,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
              ),
            ),
          ),
        );
      }
    }
    return markers;
  }

  void _handleMarkerTap(BuildContext context, dynamic irregularity) async {
    final isSelected = _selectedIrregularity?['id'] == irregularity['id'];

    // If the same marker's info window is already open, close it.
    if (isSelected && _infoWindowOverlay != null) {
      _removeInfoWindow();
      return;
    }

    // Otherwise, fetch fresh data and show the window.
    final freshIrregularity = await _updateIrregularityData(irregularity['id']);
    if (freshIrregularity != null) {
      _showInfoWindow(context, freshIrregularity);
    }
  }

  void _showInfoWindow(BuildContext context, dynamic irregularity) {
    _removeInfoWindow(); // Remove any existing overlay

    setState(() {
      _selectedIrregularity = irregularity;
    });

    _infoWindowOverlay = OverlayEntry(
      builder: (context) {
        return Positioned(
          width: 250,
          child: CompositedTransformFollower(
            link: _markerLink,
            showWhenUnlinked: false,
            offset: const Offset(-105, -150), // Adjust position above marker
            child: _buildInfoWindowContent(irregularity),
          ),
        );
      },
    );

    Overlay.of(context).insert(_infoWindowOverlay!);
  }

  Widget _buildInfoWindowContent(dynamic irregularity) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.8, end: 1.0),
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOutCubic,
      builder: (context, scale, child) {
        return Transform.scale(
          scale: scale,
          alignment: Alignment.bottomCenter,
          child: Opacity(opacity: scale, child: child),
        );
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.8),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white.withOpacity(0.2)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 30,
                  spreadRadius: 5,
                ),
              ],
            ),
            child: Stack(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(
                        right: 24.0,
                      ), // Space for close button
                      child: Text(
                        irregularity['titulo'] ?? 'Sin título',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      irregularity['descripcion'] ?? 'Sin descripción.',
                      style: const TextStyle(
                        fontSize: 14,
                        color: Colors.black54,
                      ),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const Divider(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton.icon(
                          onPressed: () =>
                              _voteForIrregularity(irregularity['id'], true),
                          icon: const Icon(
                            Icons.thumb_up_alt_outlined,
                            size: 18,
                            color: Colors.green,
                          ),
                          label: Text(
                            irregularity['likes']?.toString() ?? '0',
                            style: const TextStyle(color: Colors.black54),
                          ),
                        ),
                        const SizedBox(width: 8),
                        TextButton.icon(
                          onPressed: () =>
                              _voteForIrregularity(irregularity['id'], false),
                          icon: const Icon(
                            Icons.thumb_down_alt_outlined,
                            size: 18,
                            color: Colors.red,
                          ),
                          label: Text(
                            irregularity['dislikes']?.toString() ?? '0',
                            style: const TextStyle(color: Colors.black54),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                Positioned(
                  top: -8,
                  right: -8,
                  child: IconButton(
                    icon: const Icon(
                      Icons.close,
                      color: Colors.black54,
                      size: 20,
                    ),
                    onPressed: _removeInfoWindow,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _handleReportButton() async {
    _removeInfoWindow();
    setState(() {
      _isReporting = true;
      _loadingMessage = 'Obteniendo ubicación...';
      _markerPosition = null;
      _locationController.clear();
      _titleController.clear();
      _descriptionController.clear();
    });

    try {
      Position position = await _determinePosition();
      final newPosition = LatLng(position.latitude, position.longitude);
      _centerOnNewLocation(newPosition);
      if (_locationErrorText != null) {
        setState(() => _locationErrorText = null);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      if (mounted) {
        setState(() => _loadingMessage = null);
      }
    }
  }

  void _centerOnNewLocation(LatLng newPosition, {String? locationName}) {
    _updateMarkerState(newPosition, locationName: locationName);
    _mapController.move(newPosition, 16.0);
    if (_locationErrorText != null) {
      setState(() => _locationErrorText = null);
    }
  }

  void _updateMarkerState(LatLng newPosition, {String? locationName}) {
    setState(() {
      _markerPosition = newPosition;
      if (locationName != null) {
        _locationController.text = locationName;
      } else {
        _locationController.text =
            '${newPosition.latitude.toStringAsFixed(6)}, ${newPosition.longitude.toStringAsFixed(6)}';
      }
      // Hide suggestions when a location is set
      _suggestions = [];
      _suggestionNames = [];
      _locationFocusNode.unfocus();
    });
  }

  void _searchLocations(String query) {
    if (query.length < 3) {
      setState(() {
        _suggestions = [];
        _suggestionNames = [];
      });
      return;
    }
    _debouncer.run(() async {
      setState(() {
        _isSearching = true;
      });
      try {
        String searchQuery = query.trim();
        if (!searchQuery.toLowerCase().contains('cartagena')) {
          searchQuery = '$searchQuery, Cartagena, Bolívar, Colombia';
        }

        List<Location> locations = await locationFromAddress(
          searchQuery,
          localeIdentifier: 'es_CO',
        );
        List<String> names = [];
        List<Location> filteredLocations = [];

        // Bounding box for Cartagena
        const double minLat = 10.1;
        const double maxLat = 10.5;
        const double minLon = -75.6;
        const double maxLon = -75.3;

        for (var loc in locations) {
          if (loc.latitude >= minLat &&
              loc.latitude <= maxLat &&
              loc.longitude >= minLon &&
              loc.longitude <= maxLon) {
            try {
              List<Placemark> placemarks = await placemarkFromCoordinates(
                loc.latitude,
                loc.longitude,
              );
              if (placemarks.isNotEmpty) {
                final place = placemarks.first;
                String name =
                    '${place.street ?? ''}, ${place.subLocality ?? ''}, ${place.locality ?? ''}';
                // Remove leading commas if street is empty
                name = name.startsWith(', ') ? name.substring(2) : name;
                names.add(name);
                filteredLocations.add(loc);
              }
            } catch (e) {
              // Ignore placemark errors for now
            }
          }
        }
        if (mounted) {
          setState(() {
            _suggestions = filteredLocations;
            _suggestionNames = names;
          });
        }
      } catch (e) {
        // handle error
      } finally {
        if (mounted) {
          setState(() {
            _isSearching = false;
          });
        }
      }
    });
  }

  Future<void> _submitIrregularity() async {
    // Basic validation
    setState(() {
      if (_titleController.text.trim().isEmpty) {
        _titleErrorText = 'El título es requerido.';
      } else {
        _titleErrorText = null;
      }

      if (_markerPosition == null) {
        _locationErrorText = 'La ubicación es requerida.';
      } else {
        _locationErrorText = null;
      }
    });

    if (_titleErrorText != null || _locationErrorText != null) return;

    final authToken = Provider.of<AuthProvider>(context, listen: false).token;

    if (authToken == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Error de autenticación. Por favor, inicie sesión de nuevo.',
          ),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() {
      _loadingMessage = 'Publicando irregularidad...';
    });

    try {
      final reportData = {
        'titulo': _titleController.text.trim(),
        'descripcion': _descriptionController.text.trim(),
        'latitud': _markerPosition!.latitude,
        'longitud': _markerPosition!.longitude,
      };

      final response = await http.post(
        Uri.parse('$apiBaseUrl/api/irregularities/report'),
        headers: {
          'Content-Type': 'application/json; charset=UTF-8',
          'Authorization': 'Bearer $authToken',
        },
        body: jsonEncode(reportData),
      );

      if (mounted) {
        if (response.statusCode == 201) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Irregularidad reportada con éxito.'),
              backgroundColor: Colors.green,
            ),
          );
          setState(() {
            _isReporting = false;
            _markerPosition = null;
            _titleController.clear();
            _descriptionController.clear();
            _locationController.clear();
            _removeInfoWindow();
          });
          _fetchIrregularities(); // Refresh the list of irregularities
        } else {
          final responseBody = jsonDecode(utf8.decode(response.bodyBytes));
          final errorMessage =
              responseBody['detail']?[0]?['msg'] ??
              'Error desconocido al publicar';
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error: $errorMessage'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ocurrió un error de red: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _loadingMessage = null;
        });
      }
    }
  }

  Future<void> _voteForIrregularity(int irregularityId, bool isLike) async {
    final authToken = Provider.of<AuthProvider>(context, listen: false).token;
    if (authToken == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Error de autenticación. Por favor, inicie sesión de nuevo.',
          ),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final endpoint = isLike ? 'like' : 'dislike';
    try {
      final response = await http.post(
        Uri.parse('$apiBaseUrl/api/irregularities/$irregularityId/$endpoint'),
        headers: {'Authorization': 'Bearer $authToken'},
      );

      if (response.statusCode == 200) {
        final updatedIrregularity = jsonDecode(utf8.decode(response.bodyBytes));

        // Update local state to reflect the vote
        if (mounted) {
          setState(() {
            final index = _irregularities.indexWhere(
              (ir) => ir['id'] == irregularityId,
            );
            if (index != -1) {
              _irregularities[index] = updatedIrregularity;
            }
            // If the info window is open for this item, update it too
            if (_selectedIrregularity?['id'] == irregularityId) {
              _selectedIrregularity = updatedIrregularity;
              // This re-triggers the overlay build
              _showInfoWindow(context, updatedIrregularity);
            }
          });
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ocurrió un error de red: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<dynamic> _updateIrregularityData(int irregularityId) async {
    final authToken = Provider.of<AuthProvider>(context, listen: false).token;
    if (authToken == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Error de autenticación. Sesión expirada.'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return null;
    }

    try {
      final response = await http.get(
        Uri.parse('$apiBaseUrl/api/irregularities/search/$irregularityId'),
      );

      if (response.statusCode == 200) {
        return jsonDecode(utf8.decode(response.bodyBytes));
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No se pudo actualizar la información.'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return null;
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error de red: ${e.toString()}')),
        );
      }
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,
      body: Stack(
        children: [
          FlutterMap(
            key: _mapContainerKey,
            mapController: _mapController,
            options: const MapOptions(
              initialCenter: LatLng(10.3910, -75.4794), // Cartagena
              initialZoom: 14.5,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.app',
              ),
              MarkerLayer(markers: _buildMarkers()),
              if (_markerPosition != null)
                MarkerLayer(
                  markers: [
                    Marker(
                      point: _markerPosition!,
                      width: 80,
                      height: 80,
                      child: const Icon(
                        Icons.location_on,
                        size: 40,
                        color: Colors.red,
                      ),
                    ),
                  ],
                ),
            ],
          ),
          Positioned(
            top: MediaQuery.of(context).padding.top + 10,
            left: 20,
            right: 20,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeInOut,
                  padding: const EdgeInsets.all(20.0),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.9),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.15),
                        blurRadius: 20,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Expanded(
                            child: Text(
                              'Irregularidades',
                              style: TextStyle(
                                color: Colors.black87,
                                fontSize: 28,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          if (!_isReporting)
                            InkWell(
                              onTap: _handleReportButton,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.red,
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: const Row(
                                  children: [
                                    Icon(
                                      Icons.edit,
                                      color: Colors.white,
                                      size: 16,
                                    ),
                                    SizedBox(width: 4),
                                    Text(
                                      'Reportar',
                                      style: TextStyle(color: Colors.white),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ),
                      if (_loadingMessage != null) ...[
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 3),
                            ),
                            const SizedBox(width: 12),
                            Text(_loadingMessage!),
                          ],
                        ),
                      ],
                      if (_isReporting) ...[
                        const SizedBox(height: 20),
                        _buildTextField(
                          label: 'Título',
                          controller: _titleController,
                          errorText: _titleErrorText,
                          onChanged: (text) {
                            if (_titleErrorText != null) {
                              setState(() {
                                _titleErrorText = null;
                              });
                            }
                          },
                        ),
                        const SizedBox(height: 12),
                        _buildTextField(
                          label: 'Descripción',
                          maxLines: 3,
                          controller: _descriptionController,
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _locationController,
                          focusNode: _locationFocusNode,
                          onChanged: _searchLocations,
                          decoration: InputDecoration(
                            labelText: 'Ubicación',
                            errorText: _locationErrorText,
                            prefixIcon: const Icon(
                              Icons.location_on_outlined,
                              color: Colors.grey,
                            ),
                            filled: true,
                            fillColor: Colors.white.withOpacity(0.8),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide.none,
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            TextButton(
                              onPressed: () => setState(() {
                                _isReporting = false;
                                _markerPosition = null;
                                _titleController.clear();
                                _descriptionController.clear();
                                _locationController.clear();
                                _removeInfoWindow();
                              }),
                              child: const Text('Cancelar'),
                            ),
                            const SizedBox(width: 8),
                            ElevatedButton(
                              onPressed: _submitIrregularity,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.blue.shade700,
                                foregroundColor: Colors.white,
                              ),
                              child: const Text('Publicar'),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                if (_suggestions.isNotEmpty)
                  Material(
                    elevation: 4.0,
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      height: _suggestions.length > 3
                          ? 180
                          : _suggestions.length * 60.0,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: ListView.builder(
                        padding: EdgeInsets.zero,
                        itemCount: _suggestions.length,
                        itemBuilder: (context, index) {
                          return ListTile(
                            title: Text(_suggestionNames[index]),
                            onTap: () {
                              final location = _suggestions[index];
                              final newPosition = LatLng(
                                location.latitude,
                                location.longitude,
                              );
                              _centerOnNewLocation(
                                newPosition,
                                locationName: _suggestionNames[index],
                              );
                            },
                          );
                        },
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: _buildFloatingNavBar(),
    );
  }

  Widget _buildTextField({
    required String label,
    required TextEditingController controller,
    int maxLines = 1,
    IconData? icon,
    String? errorText,
    ValueChanged<String>? onChanged,
  }) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      onChanged: onChanged,
      decoration: InputDecoration(
        labelText: label,
        errorText: errorText,
        prefixIcon: icon != null ? Icon(icon, color: Colors.grey) : null,
        filled: true,
        fillColor: Colors.white.withOpacity(0.8),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(
          vertical: 16.0,
          horizontal: 12.0,
        ),
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
              currentIndex: 3,
              onTap: (index) {
                if (index == 3) return;

                switch (index) {
                  case 0:
                    Navigator.of(context).popUntil((route) => route.isFirst);
                    break;
                  case 2:
                    Navigator.pushReplacement(
                      context,
                      PageRouteBuilder(
                        pageBuilder: (_, __, ___) => const RutasScreen(),
                        transitionDuration: const Duration(seconds: 0),
                      ),
                    );
                    break;
                }
              },
            ),
          ),
        ),
      ),
    );
  }

  Future<Position> _determinePosition() async {
    bool serviceEnabled;
    LocationPermission permission;
    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return Future.error('Los servicios de ubicación están deshabilitados.');
    }
    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        return Future.error('Los permisos de ubicación fueron denegados');
      }
    }
    if (permission == LocationPermission.deniedForever) {
      return Future.error(
        'Los permisos de ubicación fueron denegados permanentemente.',
      );
    }
    return await Geolocator.getCurrentPosition();
  }
}

class Debouncer {
  final int milliseconds;
  VoidCallback? action;
  Timer? _timer;

  Debouncer({required this.milliseconds});

  run(VoidCallback action) {
    if (_timer != null) {
      _timer!.cancel();
    }
    _timer = Timer(Duration(milliseconds: milliseconds), action);
  }
}
