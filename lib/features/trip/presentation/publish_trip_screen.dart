import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class PublishTripScreen extends StatefulWidget {
  final Map<String, dynamic>? tripData;

  const PublishTripScreen({super.key, this.tripData});

  @override
  State<PublishTripScreen> createState() => _PublishTripScreenState();
}

class _PublishTripScreenState extends State<PublishTripScreen> {
  final _supabase = Supabase.instance.client;
  late final TextEditingController _originController;
  late final TextEditingController _destinationController;
  late final TextEditingController _meetingPointController;
  late final TextEditingController _seatsController;
  late final TextEditingController _costController;
  late final TextEditingController _vehicleBrandController;
  late final TextEditingController _vehicleColorController;
  late final TextEditingController _tripNotesController;

  DateTime? _selectedDate;
  TimeOfDay? _selectedTime;
  bool _isLoading = false;
  bool _isLoadingCommunities = true;

  String? _selectedCommunityId;
  List<dynamic> _approvedCommunities = [];

  bool get _isEditing => widget.tripData != null;

  @override
  void initState() {
    super.initState();
    final data = widget.tripData;
    _originController = TextEditingController(text: data?['origin'] ?? '');
    _destinationController =
        TextEditingController(text: data?['destination'] ?? '');
    _meetingPointController =
        TextEditingController(text: data?['meeting_point'] ?? '');
    _seatsController = TextEditingController(
      text: (data?['available_seats'] ?? 3).toString(),
    );
    _costController = TextEditingController(
      text: (data?['total_cost'] ?? '').toString(),
    );
    _vehicleBrandController =
        TextEditingController(text: data?['vehicle_brand'] ?? '');
    _vehicleColorController =
        TextEditingController(text: data?['vehicle_color'] ?? '');
    _tripNotesController =
        TextEditingController(text: data?['trip_notes'] ?? '');
    _selectedCommunityId = data?['community_id']?.toString();

    if (data != null && data['departure_time'] != null) {
      try {
        final dt = DateTime.parse(data['departure_time'].toString());
        _selectedDate = dt;
        _selectedTime = TimeOfDay(hour: dt.hour, minute: dt.minute);
      } catch (_) {}
    }

    _loadUserCommunities();
  }

  Future<void> _loadUserCommunities() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) {
        if (mounted) {
          setState(() {
            _approvedCommunities = [];
            _selectedCommunityId = null;
            _isLoadingCommunities = false;
          });
        }
        return;
      }

      final response = await _supabase
          .from('community_members')
          .select('community_id, communities (id, name, is_active)')
          .eq('user_id', user.id)
          .eq('status', 'approved');

      final activeOnly = [];
      for (final item in response) {
        final comm = item['communities'];
        if (comm is Map) {
          final isActive = comm['is_active'] ?? true;
          if (isActive == true) {
            activeOnly.add(item);
          }
        }
      }

      if (!mounted) return;
      setState(() {
        _approvedCommunities = activeOnly;
        _isLoadingCommunities = false;

        final validIds = <String>{};
        for (final item in _approvedCommunities) {
          final comm = item['communities'];
          if (comm is Map && comm['id'] != null) {
            validIds.add(comm['id'].toString());
          }
        }

        if (_selectedCommunityId == null ||
            !validIds.contains(_selectedCommunityId)) {
          if (_approvedCommunities.isNotEmpty) {
            final firstComm = _approvedCommunities.first['communities'];
            _selectedCommunityId =
                firstComm is Map ? firstComm['id'].toString() : null;
          } else {
            _selectedCommunityId = null;
          }
        }
      });
    } catch (e) {
      debugPrint('Error al cargar comunidades para publicar: $e');
      if (mounted) {
        setState(() {
          _approvedCommunities = [];
          _selectedCommunityId = null;
          _isLoadingCommunities = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _originController.dispose();
    _destinationController.dispose();
    _meetingPointController.dispose();
    _seatsController.dispose();
    _costController.dispose();
    _vehicleBrandController.dispose();
    _vehicleColorController.dispose();
    _tripNotesController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 90)),
    );
    if (picked != null && mounted) {
      setState(() => _selectedDate = picked);
    }
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _selectedTime ?? TimeOfDay.now(),
    );
    if (picked != null && mounted) {
      setState(() => _selectedTime = picked);
    }
  }

  Future<void> _saveTrip() async {
    final origin = _originController.text.trim();
    final destination = _destinationController.text.trim();
    final meetingPoint = _meetingPointController.text.trim();
    final seatsStr = _seatsController.text.trim();
    final costStr = _costController.text.trim();
    final vehicleBrand = _vehicleBrandController.text.trim();
    final vehicleColor = _vehicleColorController.text.trim();
    final tripNotes = _tripNotesController.text.trim();

    final validIds = <String>{};
    for (final item in _approvedCommunities) {
      final comm = item['communities'];
      if (comm is Map && comm['id'] != null) {
        validIds.add(comm['id'].toString());
      }
    }

    if (_selectedCommunityId == null ||
        !validIds.contains(_selectedCommunityId)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Debes seleccionar una comunidad activa para publicar.',
          ),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (origin.isEmpty ||
        destination.isEmpty ||
        meetingPoint.isEmpty ||
        seatsStr.isEmpty ||
        costStr.isEmpty ||
        vehicleBrand.isEmpty ||
        vehicleColor.isEmpty ||
        _selectedDate == null ||
        _selectedTime == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Por favor completa todos los campos obligatorios (incluyendo marca y color).',
          ),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final seats = int.tryParse(seatsStr);
    final totalCost = double.tryParse(costStr);
    if (seats == null || seats <= 0 || totalCost == null || totalCost < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Ingresa valores numéricos válidos.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final departureDateTime = DateTime(
      _selectedDate!.year,
      _selectedDate!.month,
      _selectedDate!.day,
      _selectedTime!.hour,
      _selectedTime!.minute,
    );

    setState(() => _isLoading = true);
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) throw 'No hay una sesión activa.';

      final payload = {
        'driver_id': user.id,
        'community_id': _selectedCommunityId,
        'origin': origin,
        'destination': destination,
        'meeting_point': meetingPoint,
        'available_seats': seats,
        'total_cost': totalCost,
        'departure_time': departureDateTime.toIso8601String(),
        'vehicle_brand': vehicleBrand,
        'vehicle_color': vehicleColor,
        'trip_notes': tripNotes,
        'status': 'active',
      };

      if (_isEditing) {
        await _supabase
            .from('trips')
            .update(payload)
            .eq('id', widget.tripData!['id']);
      } else {
        await _supabase.from('trips').insert(payload);
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _isEditing
                ? '¡Viaje actualizado con éxito!'
                : '¡Viaje publicado con éxito!',
          ),
          backgroundColor: Colors.teal,
        ),
      );
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al guardar el viaje: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateText = _selectedDate == null
        ? 'Seleccionar Fecha'
        : '${_selectedDate!.day}/${_selectedDate!.month}/${_selectedDate!.year}';
    final timeText = _selectedTime == null
        ? 'Seleccionar Hora'
        : _selectedTime!.format(context);
    final seats = int.tryParse(_seatsController.text) ?? 1;
    final totalCost = double.tryParse(_costController.text) ?? 0.0;
    final costPerPerson = seats > 0 ? (totalCost / seats) : 0.0;

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'Editar Viaje' : 'Publicar Nuevo Viaje'),
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
      ),
      body: _isLoadingCommunities
          ? const Center(child: CircularProgressIndicator(color: Colors.teal))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    _isEditing
                        ? 'Modificar Detalles del Viaje'
                        : 'Detalles de la Ruta y Gasto Compartido',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.teal,
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (_approvedCommunities.isEmpty) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.orange),
                      ),
                      child: const Text(
                        'No perteneces a ninguna comunidad activa aprobada. Debes unirte o activar/crear una comunidad para publicar viajes.',
                        style: TextStyle(
                          color: Colors.orange,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(height: 16),
                  ] else ...[
                    DropdownButtonFormField<String>(
                      key: ValueKey(_selectedCommunityId),
                      initialValue: _selectedCommunityId,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Seleccionar Comunidad *',
                        prefixIcon: Icon(Icons.group, color: Colors.teal),
                        border: OutlineInputBorder(),
                      ),
                      items: _approvedCommunities
                          .map<DropdownMenuItem<String>>((item) {
                        final comm = item['communities'] ?? {};
                        final commName = comm['name'] ?? 'Comunidad';
                        return DropdownMenuItem<String>(
                          value: comm['id'].toString(),
                          child: Text(
                            commName.toString(),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          ),
                        );
                      }).toList(),
                      onChanged: (val) {
                        setState(() {
                          _selectedCommunityId = val;
                        });
                      },
                    ),
                    const SizedBox(height: 16),
                  ],
                  TextField(
                    controller: _originController,
                    decoration: const InputDecoration(
                      labelText: 'Origen',
                      prefixIcon: Icon(Icons.my_location, color: Colors.teal),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _destinationController,
                    decoration: const InputDecoration(
                      labelText: 'Destino',
                      prefixIcon: Icon(Icons.location_on, color: Colors.teal),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _meetingPointController,
                    decoration: const InputDecoration(
                      labelText: 'Punto de Encuentro',
                      prefixIcon: Icon(Icons.place, color: Colors.teal),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _pickDate,
                          icon: const Icon(
                            Icons.calendar_month,
                            color: Colors.teal,
                          ),
                          label: Text(dateText),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _pickTime,
                          icon: const Icon(
                            Icons.access_time,
                            color: Colors.teal,
                          ),
                          label: Text(timeText),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _seatsController,
                    keyboardType: TextInputType.number,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      labelText: 'Cupos Disponibles',
                      prefixIcon: Icon(Icons.event_seat, color: Colors.teal),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _costController,
                    keyboardType: TextInputType.number,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      labelText: 'Gasto Total Estimado (\$)',
                      prefixIcon: Icon(
                        Icons.monetization_on_outlined,
                        color: Colors.teal,
                      ),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Información del Vehículo',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.teal,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _vehicleBrandController,
                    decoration: const InputDecoration(
                      labelText: 'Marca del vehículo (Ej. Chevrolet, Renault)',
                      prefixIcon: Icon(Icons.directions_car, color: Colors.teal),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _vehicleColorController,
                    decoration: const InputDecoration(
                      labelText: 'Color del vehículo (Ej. Gris plata, Blanco)',
                      prefixIcon: Icon(Icons.palette, color: Colors.teal),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Notas y Recomendaciones',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.teal,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _tripNotesController,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText:
                          'Observaciones (Equipaje, música, tolerancia de espera...)',
                      prefixIcon: Icon(Icons.note_alt, color: Colors.teal),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.teal.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.teal.shade200),
                    ),
                    child: Text(
                      'Apoyo estimado por pasajero: \$${costPerPerson.toStringAsFixed(0)}',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.teal.shade800,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  _isLoading
                      ? const Center(
                          child: CircularProgressIndicator(color: Colors.teal),
                        )
                      : ElevatedButton.icon(
                          onPressed:
                              _approvedCommunities.isEmpty ? null : _saveTrip,
                          icon: Icon(
                            _isEditing ? Icons.save : Icons.send_rounded,
                            color: Colors.white,
                          ),
                          label: Text(
                            _isEditing ? 'Guardar Cambios' : 'Publicar Viaje',
                            style: const TextStyle(
                              fontSize: 16,
                              color: Colors.white,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.orange.shade800,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                        ),
                ],
              ),
            ),
    );
  }
}