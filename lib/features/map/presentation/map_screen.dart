import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class MapScreen extends StatefulWidget {
  final Map<String, dynamic>? tripData;
  final bool isDriver;

  const MapScreen({
    super.key,
    this.tripData,
    this.isDriver = false,
  });

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  // Ubicación por defecto (Bogotá/Chía, Colombia)
  static const LatLng _defaultCenter = LatLng(4.8615, -74.0339);

  Set<Marker> _markers = {};

  @override
  void initState() {
    super.initState();
    _setupMapMarkers();
  }

  void _setupMapMarkers() {
    if (widget.tripData != null) {
      final originName = widget.tripData!['origin'] ?? 'Origen';
      final destinationName = widget.tripData!['destination'] ?? 'Destino';
      final meetingPoint = widget.tripData!['meeting_point'] ?? 'Punto de encuentro';

      final double originLat = (widget.tripData!['origin_lat'] as num?)?.toDouble() ?? 4.8615;
      final double originLng = (widget.tripData!['origin_lng'] as num?)?.toDouble() ?? -74.0339;
      final double destLat = (widget.tripData!['dest_lat'] as num?)?.toDouble() ?? 4.7110;
      final double destLng = (widget.tripData!['dest_lng'] as num?)?.toDouble() ?? -74.0721;

      setState(() {
        _markers = {
          Marker(
            markerId: const MarkerId('origin'),
            position: LatLng(originLat, originLng),
            infoWindow: InfoWindow(
              title: 'Origen: $originName',
              snippet: 'Encuentro: $meetingPoint',
            ),
            icon: BitmapDescriptor.defaultMarkerWithHue(175.0),
          ),
          Marker(
            markerId: const MarkerId('destination'),
            position: LatLng(destLat, destLng),
            infoWindow: InfoWindow(title: 'Destino: $destinationName'),
            icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
          ),
        };
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasTrip = widget.tripData != null;
    final origin = widget.tripData?['origin'] ?? 'Origen no especificado';
    final destination = widget.tripData?['destination'] ?? 'Destino no especificado';
    final meetingPoint = widget.tripData?['meeting_point'] ?? 'No especificado';

    return Scaffold(
      appBar: AppBar(
        title: Text(hasTrip ? 'Mapa del Viaje' : 'Explorar Mapa'),
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
      ),
      body: Stack(
        children: [
          GoogleMap(
            initialCameraPosition: const CameraPosition(
              target: _defaultCenter,
              zoom: 12.5,
            ),
            markers: _markers,
            myLocationEnabled: true,
            myLocationButtonEnabled: true,
          ),
          Positioned(
            top: 16,
            left: 16,
            right: 16,
            child: Card(
              elevation: 4,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(14.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          widget.isDriver ? Icons.time_to_leave : Icons.person_pin_circle,
                          color: Colors.teal,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            hasTrip
                                ? '$origin ➔ $destination'
                                : 'Exploración de la Comunidad',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (hasTrip) ...[
                      const Divider(height: 14),
                      Text(
                        'Punto de encuentro: $meetingPoint',
                        style: const TextStyle(fontSize: 13, color: Colors.black87),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        widget.isDriver
                            ? '🚗 Eres el conductor. Dirígete al punto de encuentro para recoger a los pasajeros.'
                            : '🚶 Espere a que el conductor inicie el viaje o acércate al punto de encuentro.',
                        style: TextStyle(
                          fontSize: 12,
                          color: widget.isDriver ? Colors.teal.shade800 : Colors.blue.shade800,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            bottom: 24,
            left: 20,
            right: 20,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.teal,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.arrow_back),
              label: const Text('Volver al panel', style: TextStyle(fontSize: 16)),
            ),
          ),
        ],
      ),
    );
  }
}