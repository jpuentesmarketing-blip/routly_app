import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../auth/presentation/login_screen.dart';
import '../../map/presentation/map_screen.dart';
import '../../profile/presentation/profile_screen.dart';
import '../../trip/presentation/publish_trip_screen.dart';
import '../../trip/presentation/trip_chat_screen.dart';
import '../../community/presentation/community_screen.dart';
import '../../../widgets/legal_footer.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final supabase = Supabase.instance.client;
  bool isDriver = false;
  bool _isUpdatingRole = false;
  String userName = 'Usuario';
  String? userAvatarUrl;
  bool isLoading = true;
  List<dynamic> activeTrips = [];

  List<dynamic> _userCommunities = [];
  String? _selectedCommunityFilterId;

  Map<String, String> userTripRequests = {};
  Map<String, String> userRequestIds = {};
  Map<String, String> tripCancellationReasons = {};
  Map<String, bool> userSupportCompleted = {};

  final Set<String> _ratedKeys = {};

  Map<String, int> pendingRequestsCounts = {};
  Map<String, int> withdrawnRequestsCounts = {};
  DateTime _selectedFilterDate = DateTime.now();

  @override
  void initState() {
    super.initState();
    _initializeData();
    _setupRealtimeSubscription();
  }

  Future<void> _initializeData() async {
    await _loadUserCommunities();
    await _loadDashboardData();
  }

  Future<void> _toggleUserRole(bool driverSelected) async {
    if (_isUpdatingRole || isDriver == driverSelected) return;
    final user = supabase.auth.currentUser;
    if (user == null) return;

    final previousRole = isDriver;
    setState(() {
      isDriver = driverSelected;
      _isUpdatingRole = true;
    });

    try {
      await supabase
          .from('profiles')
          .update({'is_driver': driverSelected})
          .eq('id', user.id);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            driverSelected
                ? 'Ingresaste en modo Conductor: ya puedes publicar viajes.'
                : 'Ingresaste en modo Pasajero: puedes buscar y solicitar cupos.',
          ),
          backgroundColor: Colors.teal,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        isDriver = previousRole;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No se pudo actualizar el modo de ingreso: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isUpdatingRole = false;
        });
      }
    }
  }

  Set<String> _activeCommunityIds() {
    final validIds = <String>{};
    for (final item in _userCommunities) {
      final comm = item['communities'];
      if (comm is Map && comm['id'] != null) {
        final isActive = comm['is_active'] ?? true;
        if (isActive == true) {
          validIds.add(comm['id'].toString());
        }
      }
    }
    return validIds;
  }

  Future<void> _loadUserCommunities() async {
    try {
      final user = supabase.auth.currentUser;
      if (user == null) {
        if (mounted) {
          setState(() {
            _userCommunities = [];
            _selectedCommunityFilterId = null;
          });
        }
        return;
      }

      final response = await supabase
          .from('community_members')
          .select('community_id, communities (id, name, is_active)')
          .eq('user_id', user.id)
          .eq('status', 'approved');

      final activeCommunities = [];
      for (final item in response) {
        final comm = item['communities'];
        if (comm is Map) {
          final isActive = comm['is_active'] ?? true;
          if (isActive == true) {
            activeCommunities.add(item);
          }
        }
      }

      if (!mounted) return;
      setState(() {
        _userCommunities = activeCommunities;
        final validIds = _activeCommunityIds();

        if (_selectedCommunityFilterId == null ||
            !validIds.contains(_selectedCommunityFilterId)) {
          if (_userCommunities.isNotEmpty) {
            final firstComm = _userCommunities.first['communities'];
            _selectedCommunityFilterId =
                firstComm is Map ? firstComm['id'].toString() : null;
          } else {
            _selectedCommunityFilterId = null;
          }
        }
      });
    } catch (e) {
      debugPrint('Error al cargar comunidades en Home: $e');
    }
  }

  void _setupRealtimeSubscription() {
    supabase
        .channel('public:trip_requests')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'trip_requests',
          callback: (payload) {
            if (mounted) {
              _loadDashboardData();
            }
          },
        )
        .subscribe();

    supabase
        .channel('public:trips')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'trips',
          callback: (payload) {
            if (mounted) {
              _loadDashboardData();
            }
          },
        )
        .subscribe();
  }

  Future<void> _loadDashboardData() async {
    try {
      final user = supabase.auth.currentUser;
      if (user != null) {
        final profileData = await supabase
            .from('profiles')
            .select()
            .eq('id', user.id)
            .maybeSingle();

        if (profileData != null) {
          userName = profileData['full_name'] ?? 'Usuario';
          isDriver = profileData['is_driver'] ?? false;
          userAvatarUrl = profileData['avatar_url'];
        }

        final requestsData = await supabase
            .from('trip_requests')
            .select(
              'id, trip_id, status, cancellation_reason, support_completed',
            )
            .eq('passenger_id', user.id);

        userTripRequests.clear();
        userRequestIds.clear();
        tripCancellationReasons.clear();
        userSupportCompleted.clear();

        for (var req in requestsData) {
          final tId = req['trip_id'].toString();
          userTripRequests[tId] = req['status'] ?? 'pending';
          userRequestIds[tId] = req['id'].toString();
          if (req['cancellation_reason'] != null) {
            tripCancellationReasons[tId] = req['cancellation_reason'];
          }
          userSupportCompleted[tId] = req['support_completed'] ?? false;
        }

        final ratingsData = await supabase
            .from('trip_ratings')
            .select('trip_id, target_user_id')
            .eq('rater_id', user.id);

        _ratedKeys.clear();
        for (var r in ratingsData) {
          _ratedKeys.add('${r['trip_id']}_${r['target_user_id']}');
        }
      }

      final validActiveCommunityIds = _activeCommunityIds();
      String? communityId = _selectedCommunityFilterId;
      if (communityId != null && !validActiveCommunityIds.contains(communityId)) {
        communityId = validActiveCommunityIds.isNotEmpty
            ? validActiveCommunityIds.first
            : null;
        if (mounted) {
          setState(() {
            _selectedCommunityFilterId = communityId;
          });
        }
      }

      final startOfDay = DateTime(
        _selectedFilterDate.year,
        _selectedFilterDate.month,
        _selectedFilterDate.day,
        0,
        0,
        0,
      ).toIso8601String();

      final endOfDay = DateTime(
        _selectedFilterDate.year,
        _selectedFilterDate.month,
        _selectedFilterDate.day,
        23,
        59,
        59,
      ).toIso8601String();

      var query = supabase
          .from('trips')
          .select(
            '*, profiles!trips_driver_id_fkey(full_name, rating, avatar_url), communities!trips_community_id_fkey(is_active)',
          )
          .gte('departure_time', startOfDay)
          .lte('departure_time', endOfDay);

      if (communityId != null) {
        query = query.eq('community_id', communityId);
      } else {
        query = query.eq(
          'community_id',
          '00000000-0000-0000-0000-000000000000',
        );
      }

      final rawTripsData = await query.order('departure_time', ascending: true);
      final tripsData = rawTripsData.where((trip) {
        final commField = trip['communities'];
        if (commField is Map) {
          return (commField['is_active'] ?? true) == true;
        }
        return true;
      }).toList();

      pendingRequestsCounts.clear();
      withdrawnRequestsCounts.clear();

      if (tripsData.isNotEmpty) {
        final tripIds = tripsData.map((t) => t['id'].toString()).toList();
        final allRequests = await supabase
            .from('trip_requests')
            .select('trip_id, status')
            .inFilter('trip_id', tripIds)
            .inFilter('status', ['pending', 'withdrawn']);

        for (var req in allRequests) {
          final tId = req['trip_id'].toString();
          final status = req['status'];
          if (status == 'pending') {
            pendingRequestsCounts[tId] = (pendingRequestsCounts[tId] ?? 0) + 1;
          } else if (status == 'withdrawn') {
            withdrawnRequestsCounts[tId] =
                (withdrawnRequestsCounts[tId] ?? 0) + 1;
          }
        }
      }

      if (mounted) {
        setState(() {
          activeTrips = tripsData;
          isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error al cargar datos del tablero: $e');
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    }
  }

  Future<void> _pickFilterDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedFilterDate,
      firstDate: DateTime.now().subtract(const Duration(days: 7)),
      lastDate: DateTime.now().add(const Duration(days: 60)),
    );
    if (picked != null && mounted) {
      setState(() {
        _selectedFilterDate = picked;
        isLoading = true;
      });
      await _loadDashboardData();
    }
  }

  Future<void> _requestToJoin(String tripId) async {
    try {
      final user = supabase.auth.currentUser;
      if (user == null) return;

      final existing = await supabase
          .from('trip_requests')
          .select()
          .eq('trip_id', tripId)
          .eq('passenger_id', user.id)
          .maybeSingle();

      if (existing != null) {
        await supabase
            .from('trip_requests')
            .update({'status': 'pending'})
            .eq('id', existing['id']);
      } else {
        await supabase.from('trip_requests').insert({
          'trip_id': tripId,
          'passenger_id': user.id,
          'status': 'pending',
        });
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('¡Solicitud enviada al conductor con éxito!'),
          backgroundColor: Colors.teal,
        ),
      );
      await _loadDashboardData();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al enviar la solicitud: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _cancelRequest(
    String tripId,
    String requestId,
    bool wasAccepted,
  ) async {
    try {
      await supabase.rpc(
        'cancel_passenger_request',
        params: {
          'p_request_id': requestId,
          'p_trip_id': tripId,
          'p_was_accepted': wasAccepted,
        },
      );

      if (!mounted) return;
      setState(() {
        userTripRequests.remove(tripId);
        userRequestIds.remove(tripId);
        userSupportCompleted.remove(tripId);
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Has desistido del viaje exitosamente. Cupo liberado.'),
          backgroundColor: Colors.orange,
        ),
      );
      await _loadDashboardData();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al desistir del viaje: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _markSupportCompleted(String requestId, bool completed) async {
    try {
      await supabase
          .from('trip_requests')
          .update({'support_completed': completed})
          .eq('id', requestId);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            completed
                ? 'Apoyo registrado como realizado con éxito.'
                : 'Se ha desmarcado el registro de apoyo.',
          ),
          backgroundColor: Colors.teal,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al actualizar el estado de apoyo: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _openTripChat({
    required String tripId,
    required String tripTitle,
    required String otherUserId,
    required String otherUserName,
  }) {
    if (otherUserId.isEmpty) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => TripChatScreen(
          tripId: tripId,
          tripTitle: tripTitle,
          otherUserId: otherUserId,
          otherUserName: otherUserName,
        ),
      ),
    );
  }

  Future<void> _showDriverChatPickerDialog(Map<String, dynamic> trip) async {
    final tripId = trip['id'].toString();
    final tripTitle =
        '${trip['origin'] ?? ''} → ${trip['destination'] ?? ''}';

    final requests = await supabase
        .from('trip_requests')
        .select(
          'id, status, passenger_id, profiles!trip_requests_passenger_id_fkey(full_name)',
        )
        .eq('trip_id', tripId)
        .inFilter('status', ['pending', 'accepted']);

    if (!mounted) return;

    if (requests.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Aún no hay pasajeros con solicitud o aceptados en este viaje.',
          ),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text(
            'Chatear con pasajero del viaje',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: requests.length,
              itemBuilder: (context, index) {
                final req = requests[index];
                final passengerId = req['passenger_id']?.toString() ?? '';
                final status = req['status']?.toString() ?? 'pending';
                final profileField = req['profiles'];
                String passengerName = 'Pasajero';
                if (profileField is Map) {
                  passengerName = profileField['full_name'] ?? 'Pasajero';
                } else if (profileField is List && profileField.isNotEmpty) {
                  passengerName = profileField.first['full_name'] ?? 'Pasajero';
                }

                return ListTile(
                  leading: const CircleAvatar(
                    backgroundColor: Colors.teal,
                    child: Icon(Icons.person, color: Colors.white),
                  ),
                  title: Text(passengerName),
                  subtitle: Text(
                    status == 'accepted' ? 'Aceptado' : 'Pendiente',
                    style: TextStyle(
                      fontSize: 12,
                      color: status == 'accepted'
                          ? Colors.green
                          : Colors.orange.shade800,
                    ),
                  ),
                  trailing: const Icon(Icons.chat, color: Colors.teal),
                  onTap: () {
                    Navigator.pop(dialogContext);
                    _openTripChat(
                      tripId: tripId,
                      tripTitle: tripTitle,
                      otherUserId: passengerId,
                      otherUserName: passengerName,
                    );
                  },
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cerrar'),
            ),
          ],
        );
      },
    );
  }

  void _showRatingDialog(
    String tripId,
    String targetUserId,
    String targetUserName, {
    VoidCallback? onRatedSuccess,
  }) {
    double selectedRating = 5.0;
    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateModal) {
            return AlertDialog(
              title: Text('Calificar a $targetUserName'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Selecciona una puntuación de 1 a 5 estrellas:'),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(5, (index) {
                      int starValue = index + 1;
                      return IconButton(
                        icon: Icon(
                          starValue <= selectedRating
                              ? Icons.star
                              : Icons.star_border,
                          color: Colors.amber,
                          size: 32,
                        ),
                        onPressed: () {
                          setStateModal(() {
                            selectedRating = starValue.toDouble();
                          });
                        },
                      );
                    }),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${selectedRating.toInt()} Estrellas',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancelar'),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.teal,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () async {
                    Navigator.pop(context);
                    await _submitRatingToSupabase(
                      tripId,
                      targetUserId,
                      selectedRating,
                      onRatedSuccess: onRatedSuccess,
                    );
                  },
                  child: const Text('Enviar Calificación'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _submitRatingToSupabase(
    String tripId,
    String targetUserId,
    double newRating, {
    VoidCallback? onRatedSuccess,
  }) async {
    try {
      final user = supabase.auth.currentUser;
      if (user == null) return;

      await supabase.rpc(
        'update_user_rating',
        params: {
          'target_user_id': targetUserId,
          'new_rating': newRating,
        },
      );

      await supabase.from('trip_ratings').insert({
        'trip_id': tripId,
        'rater_id': user.id,
        'target_user_id': targetUserId,
        'rating': newRating,
      });

      if (mounted) {
        setState(() {
          _ratedKeys.add('${tripId}_$targetUserId');
        });
      }

      if (onRatedSuccess != null) {
        onRatedSuccess();
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('¡Calificación enviada con éxito!'),
          backgroundColor: Colors.teal,
        ),
      );
      await _loadDashboardData();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al enviar calificación: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _showRequestsDialog(Map<String, dynamic> trip) async {
    final tripId = trip['id'].toString();
    final tripTitle =
        '${trip['origin'] ?? ''} → ${trip['destination'] ?? ''}';
    await supabase
        .from('trip_requests')
        .update({'status': 'withdrawn_read'})
        .eq('trip_id', tripId)
        .eq('status', 'withdrawn');

    if (!mounted) return;
    showDialog(
      context: context,
      builder: (dialogContext) {
        return DefaultTabController(
          length: 2,
          child: AlertDialog(
            title: const TabBar(
              labelColor: Colors.teal,
              unselectedLabelColor: Colors.grey,
              indicatorColor: Colors.teal,
              tabs: [
                Tab(text: 'Solicitudes'),
                Tab(text: 'Desistidos'),
              ],
            ),
            content: SizedBox(
              width: double.maxFinite,
              height: 380,
              child: TabBarView(
                children: [
                  FutureBuilder<List<dynamic>>(
                    future: supabase
                        .from('trip_requests')
                        .select(
                          'id, status, support_completed, passenger_id, profiles!trip_requests_passenger_id_fkey(full_name, rating, avatar_url)',
                        )
                        .eq('trip_id', tripId)
                        .inFilter('status', ['pending', 'accepted']),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(
                          child: CircularProgressIndicator(color: Colors.teal),
                        );
                      }
                      if (snapshot.hasError) {
                        return Text('Error al cargar: ${snapshot.error}');
                      }
                      final requests = snapshot.data ?? [];
                      if (requests.isEmpty) {
                        return const Center(
                          child: Text(
                            'No hay solicitudes activas para este viaje.',
                            style: TextStyle(color: Colors.grey),
                          ),
                        );
                      }
                      return StatefulBuilder(
                        builder: (context, setStateModal) {
                          return ListView.builder(
                            shrinkWrap: true,
                            itemCount: requests.length,
                            itemBuilder: (context, index) {
                              final req = requests[index];
                              String passengerName = 'Miembro de la Comunidad';
                              double passengerRating = 5.0;
                              String? passengerAvatarUrl;

                              final profileField = req['profiles'];
                              if (profileField is Map) {
                                passengerName = profileField['full_name'] ??
                                    'Miembro de la Comunidad';
                                passengerRating =
                                    (profileField['rating'] as num?)
                                            ?.toDouble() ??
                                        5.0;
                                passengerAvatarUrl = profileField['avatar_url'];
                              } else if (profileField is List &&
                                  profileField.isNotEmpty) {
                                passengerName = profileField.first['full_name'] ??
                                    'Miembro de la Comunidad';
                                passengerRating =
                                    (profileField.first['rating'] as num?)
                                            ?.toDouble() ??
                                        5.0;
                                passengerAvatarUrl =
                                    profileField.first['avatar_url'];
                              }

                              final status = req['status'];
                              final requestId = req['id'].toString();
                              final passengerId =
                                  req['passenger_id']?.toString() ?? '';
                              final bool isSupportDone =
                                  req['support_completed'] ?? false;
                              final bool isPassengerRated =
                                  _ratedKeys.contains('${tripId}_$passengerId');

                              return Card(
                                margin: const EdgeInsets.symmetric(vertical: 4),
                                child: Padding(
                                  padding: const EdgeInsets.all(8.0),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      CircleAvatar(
                                        backgroundColor: status == 'accepted'
                                            ? Colors.green.shade100
                                            : Colors.orange.shade100,
                                        backgroundImage:
                                            passengerAvatarUrl != null &&
                                                    passengerAvatarUrl.isNotEmpty
                                                ? NetworkImage(
                                                    passengerAvatarUrl,
                                                  )
                                                : null,
                                        child: passengerAvatarUrl == null ||
                                                passengerAvatarUrl.isEmpty
                                            ? Icon(
                                                status == 'accepted'
                                                    ? Icons.check
                                                    : Icons.person,
                                                color: status == 'accepted'
                                                    ? Colors.green
                                                    : Colors.orange,
                                              )
                                            : null,
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              passengerName,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 14,
                                              ),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              'Estado: ${status == 'accepted' ? 'Aceptado' : 'Pendiente'}',
                                              style: TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.bold,
                                                color: status == 'accepted'
                                                    ? Colors.green
                                                    : Colors.orange.shade800,
                                              ),
                                            ),
                                            const SizedBox(height: 2),
                                            Row(
                                              children: [
                                                const Icon(
                                                  Icons.star,
                                                  size: 12,
                                                  color: Colors.amber,
                                                ),
                                                const SizedBox(width: 2),
                                                Expanded(
                                                  child: Text(
                                                    'Calificación: ${passengerRating.toStringAsFixed(1)} / 5.0',
                                                    style: const TextStyle(
                                                      fontSize: 11,
                                                      color: Colors.grey,
                                                    ),
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                  ),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 4),
                                            TextButton.icon(
                                              style: TextButton.styleFrom(
                                                foregroundColor: Colors.teal,
                                                padding: EdgeInsets.zero,
                                                minimumSize: Size.zero,
                                                tapTargetSize:
                                                    MaterialTapTargetSize
                                                        .shrinkWrap,
                                              ),
                                              icon: const Icon(
                                                Icons.chat_bubble_outline,
                                                size: 14,
                                              ),
                                              label: const Text(
                                                'Chat del viaje',
                                                style: TextStyle(fontSize: 11),
                                              ),
                                              onPressed: () {
                                                if (dialogContext.mounted) {
                                                  Navigator.pop(dialogContext);
                                                }
                                                _openTripChat(
                                                  tripId: tripId,
                                                  tripTitle: tripTitle,
                                                  otherUserId: passengerId,
                                                  otherUserName: passengerName,
                                                );
                                              },
                                            ),
                                            if (status == 'accepted' &&
                                                isSupportDone) ...[
                                              const SizedBox(height: 4),
                                              TextButton.icon(
                                                style: TextButton.styleFrom(
                                                  foregroundColor:
                                                      isPassengerRated
                                                          ? Colors.grey
                                                          : Colors.amber.shade800,
                                                  padding: EdgeInsets.zero,
                                                  minimumSize: Size.zero,
                                                  tapTargetSize:
                                                      MaterialTapTargetSize
                                                          .shrinkWrap,
                                                ),
                                                icon: Icon(
                                                  isPassengerRated
                                                      ? Icons.check_circle
                                                      : Icons.star,
                                                  size: 14,
                                                ),
                                                label: Text(
                                                  isPassengerRated
                                                      ? 'Pasajero Calificado'
                                                      : 'Calificar pasajero',
                                                  style: const TextStyle(
                                                    fontSize: 11,
                                                  ),
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                                onPressed: isPassengerRated
                                                    ? null
                                                    : () {
                                                        _showRatingDialog(
                                                          tripId,
                                                          passengerId,
                                                          passengerName,
                                                          onRatedSuccess: () {
                                                            setStateModal(() {});
                                                          },
                                                        );
                                                      },
                                              ),
                                            ],
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                      status == 'pending'
                                          ? Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                IconButton(
                                                  constraints:
                                                      const BoxConstraints(),
                                                  padding:
                                                      const EdgeInsets.all(4),
                                                  icon: const Icon(
                                                    Icons.check_circle,
                                                    color: Colors.green,
                                                    size: 22,
                                                  ),
                                                  tooltip: 'Aceptar',
                                                  onPressed: () async {
                                                    if (dialogContext.mounted &&
                                                        Navigator.canPop(
                                                          dialogContext,
                                                        )) {
                                                      Navigator.pop(
                                                        dialogContext,
                                                      );
                                                    }
                                                    await _updateRequestStatus(
                                                      requestId,
                                                      tripId,
                                                      'accepted',
                                                      trip,
                                                    );
                                                  },
                                                ),
                                                IconButton(
                                                  constraints:
                                                      const BoxConstraints(),
                                                  padding:
                                                      const EdgeInsets.all(4),
                                                  icon: const Icon(
                                                    Icons.cancel,
                                                    color: Colors.red,
                                                    size: 22,
                                                  ),
                                                  tooltip: 'Rechazar',
                                                  onPressed: () async {
                                                    if (dialogContext.mounted &&
                                                        Navigator.canPop(
                                                          dialogContext,
                                                        )) {
                                                      Navigator.pop(
                                                        dialogContext,
                                                      );
                                                    }
                                                    await _updateRequestStatus(
                                                      requestId,
                                                      tripId,
                                                      'rejected',
                                                      trip,
                                                    );
                                                  },
                                                ),
                                              ],
                                            )
                                          : ElevatedButton(
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor: isSupportDone
                                                    ? Colors.teal
                                                    : Colors.grey.shade200,
                                                foregroundColor: isSupportDone
                                                    ? Colors.white
                                                    : Colors.black87,
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                  horizontal: 8,
                                                  vertical: 4,
                                                ),
                                                minimumSize: Size.zero,
                                                tapTargetSize:
                                                    MaterialTapTargetSize
                                                        .shrinkWrap,
                                              ),
                                              onPressed: () async {
                                                final newState = !isSupportDone;
                                                await _markSupportCompleted(
                                                  requestId,
                                                  newState,
                                                );
                                                setStateModal(() {
                                                  req['support_completed'] =
                                                      newState;
                                                });
                                              },
                                              child: Text(
                                                isSupportDone
                                                    ? 'Apoyo OK'
                                                    : 'Apoyo',
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.bold,
                                                  color: isSupportDone
                                                      ? Colors.white
                                                      : Colors.teal.shade800,
                                                ),
                                              ),
                                            ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          );
                        },
                      );
                    },
                  ),
                  FutureBuilder<List<dynamic>>(
                    future: supabase
                        .from('trip_requests')
                        .select(
                          'id, status, passenger_id, profiles!trip_requests_passenger_id_fkey(full_name, rating, avatar_url)',
                        )
                        .eq('trip_id', tripId)
                        .inFilter('status', ['withdrawn', 'withdrawn_read']),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(
                          child: CircularProgressIndicator(color: Colors.teal),
                        );
                      }
                      if (snapshot.hasError) {
                        return Text(
                          'Error al cargar desistidos: ${snapshot.error}',
                        );
                      }
                      final withdrawnRequests = snapshot.data ?? [];
                      if (withdrawnRequests.isEmpty) {
                        return const Center(
                          child: Text(
                            'Ningún pasajero ha desistido de este viaje.',
                            style: TextStyle(color: Colors.grey),
                          ),
                        );
                      }
                      return ListView.builder(
                        shrinkWrap: true,
                        itemCount: withdrawnRequests.length,
                        itemBuilder: (context, index) {
                          final req = withdrawnRequests[index];
                          String passengerName = 'Miembro de la Comunidad';
                          double passengerRating = 5.0;
                          String? passengerAvatarUrl;

                          final profileField = req['profiles'];
                          if (profileField is Map) {
                            passengerName = profileField['full_name'] ??
                                'Miembro de la Comunidad';
                            passengerRating =
                                (profileField['rating'] as num?)?.toDouble() ??
                                    5.0;
                            passengerAvatarUrl = profileField['avatar_url'];
                          } else if (profileField is List &&
                              profileField.isNotEmpty) {
                            passengerName = profileField.first['full_name'] ??
                                'Miembro de la Comunidad';
                            passengerRating =
                                (profileField.first['rating'] as num?)
                                        ?.toDouble() ??
                                    5.0;
                            passengerAvatarUrl =
                                profileField.first['avatar_url'];
                          }

                          return Card(
                            color: Colors.grey.shade100,
                            margin: const EdgeInsets.symmetric(vertical: 4),
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor: Colors.red.shade100,
                                backgroundImage: passengerAvatarUrl != null &&
                                        passengerAvatarUrl.isNotEmpty
                                    ? NetworkImage(passengerAvatarUrl)
                                    : null,
                                child: passengerAvatarUrl == null ||
                                        passengerAvatarUrl.isEmpty
                                    ? const Icon(
                                        Icons.person_remove,
                                        color: Colors.red,
                                      )
                                    : null,
                              ),
                              title: Text(
                                passengerName,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'El pasajero desistió de la reserva (Cupo liberado)',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.red,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Row(
                                    children: [
                                      const Icon(
                                        Icons.star,
                                        size: 14,
                                        color: Colors.amber,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        'Calificación: ${passengerRating.toStringAsFixed(1)} / 5.0',
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () async {
                  if (dialogContext.mounted) {
                    Navigator.pop(dialogContext);
                  }
                  if (mounted) {
                    await _loadDashboardData();
                  }
                },
                child: const Text('Cerrar'),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _updateRequestStatus(
    String requestId,
    String tripId,
    String newStatus,
    Map<String, dynamic> trip,
  ) async {
    try {
      await supabase
          .from('trip_requests')
          .update({'status': newStatus})
          .eq('id', requestId);

      if (newStatus == 'accepted') {
        final currentAccepted = trip['accepted_passengers_count'] ?? 0;
        final currentSeats = trip['available_seats'] ?? 1;
        if (currentSeats > 0) {
          await supabase.from('trips').update({
            'accepted_passengers_count': currentAccepted + 1,
            'available_seats': currentSeats - 1,
          }).eq('id', tripId);
        }
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            newStatus == 'accepted'
                ? 'Pasajero aceptado con éxito.'
                : 'Solicitud rechazada.',
          ),
          backgroundColor: Colors.teal,
        ),
      );
      await _loadDashboardData();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al actualizar estado: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _showCancelTripDialog(
    String tripId,
    bool hasPassengers,
  ) async {
    final reasonController = TextEditingController();
    return showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text(
            'Cancelar Viaje por Fuerza Mayor',
            style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                hasPassengers
                    ? '¡Este viaje ya cuenta con pasajeros confirmados. Al cancelar, se notificará a los pasajeros.'
                    : '¿Estás seguro de cancelar este viaje?',
                style: const TextStyle(fontSize: 14),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: reasonController,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Motivo de la cancelación *',
                  hintText: 'Ej: Falla mecánica imprevista en el vehículo...',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                if (dialogContext.mounted) {
                  Navigator.pop(dialogContext);
                }
              },
              child: const Text('Volver'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              onPressed: () async {
                final reason = reasonController.text.trim();
                if (reason.isEmpty) {
                  if (!dialogContext.mounted) return;
                  ScaffoldMessenger.of(dialogContext).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Por favor escribe el motivo de la cancelación.',
                      ),
                      backgroundColor: Colors.red,
                    ),
                  );
                  return;
                }
                if (dialogContext.mounted) {
                  Navigator.pop(dialogContext);
                }
                await _cancelTripInDatabase(tripId, reason, hasPassengers);
              },
              child: const Text('Confirmar Cancelación'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _cancelTripInDatabase(
    String tripId,
    String reason,
    bool hasPassengers,
  ) async {
    try {
      await supabase.rpc(
        'cancel_trip_by_driver',
        params: {
          'p_trip_id': tripId,
          'p_reason': reason,
        },
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            hasPassengers
                ? 'Viaje cancelado. Se notificó a los pasajeros con el motivo: "$reason"'
                : 'Viaje cancelado con éxito.',
          ),
          backgroundColor: Colors.orange.shade800,
          duration: const Duration(seconds: 4),
        ),
      );
      await _loadDashboardData();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al cancelar el viaje: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _editTrip(Map<String, dynamic> trip, bool hasPassengers) async {
    if (hasPassengers) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No se pueden modificar las condiciones porque el viaje ya tiene pasajeros confirmados.',
          ),
          backgroundColor: Colors.amber,
          duration: Duration(seconds: 4),
        ),
      );
      return;
    }

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PublishTripScreen(tripData: trip),
      ),
    );
    if (mounted) {
      await _loadDashboardData();
    }
  }

  void _signOut() async {
    await supabase.auth.signOut();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (context) => const LoginScreen()),
    );
  }

  String _formatDateTime(String? isoString) {
    if (isoString == null || isoString.isEmpty) return 'Fecha no especificada';
    try {
      final dt = DateTime.parse(isoString);
      final day = dt.day.toString().padLeft(2, '0');
      final month = dt.month.toString().padLeft(2, '0');
      final year = dt.year;
      final hour = dt.hour.toString().padLeft(2, '0');
      final minute = dt.minute.toString().padLeft(2, '0');
      return '$day/$month/$year a las $hour:$minute';
    } catch (_) {
      return isoString;
    }
  }

  @override
  Widget build(BuildContext context) {
    final userEmail = supabase.auth.currentUser?.email ?? '';
    final currentUserId = supabase.auth.currentUser?.id ?? '';
    final dateFormatted =
        '${_selectedFilterDate.day}/${_selectedFilterDate.month}/${_selectedFilterDate.year}';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Routly - Comunidad'),
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.group_outlined),
            tooltip: 'Gestión de Comunidad',
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const CommunityScreen(),
                ),
              );
              if (mounted) {
                await _loadUserCommunities();
                await _loadDashboardData();
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.person_outline),
            tooltip: 'Mi Perfil y Rol',
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const ProfileScreen()),
              );
              if (mounted) {
                await _loadDashboardData();
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Cerrar Sesión',
            onPressed: _signOut,
          ),
        ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.teal))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Card(
                    elevation: 3,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              CircleAvatar(
                                radius: 30,
                                backgroundColor: Colors.teal.shade100,
                                backgroundImage: userAvatarUrl != null &&
                                        userAvatarUrl!.isNotEmpty
                                    ? NetworkImage(userAvatarUrl!)
                                    : null,
                                child: userAvatarUrl == null ||
                                        userAvatarUrl!.isEmpty
                                    ? const Icon(
                                        Icons.person,
                                        size: 32,
                                        color: Colors.teal,
                                      )
                                    : null,
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '¡Hola, $userName!',
                                      style: const TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      userEmail,
                                      style: const TextStyle(
                                        color: Colors.grey,
                                        fontSize: 13,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: isDriver
                                            ? Colors.teal.shade50
                                            : Colors.blue.shade50,
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(
                                          color: isDriver
                                              ? Colors.teal
                                              : Colors.blue,
                                        ),
                                      ),
                                      child: Text(
                                        isDriver
                                            ? 'Rol actual: Conductor'
                                            : 'Rol actual: Pasajero',
                                        style: TextStyle(
                                          color: isDriver
                                              ? Colors.teal.shade800
                                              : Colors.blue.shade800,
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          const Divider(height: 1),
                          const SizedBox(height: 12),
                          const Text(
                            '¿Cómo deseas ingresar hoy a la aplicación?',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: Colors.black87,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: _isUpdatingRole
                                      ? null
                                      : () => _toggleUserRole(false),
                                  icon: Icon(
                                    Icons.person_search,
                                    size: 18,
                                    color: !isDriver
                                        ? Colors.white
                                        : Colors.blue.shade800,
                                  ),
                                  label: const Text('Pasajero'),
                                  style: OutlinedButton.styleFrom(
                                    backgroundColor: !isDriver
                                        ? Colors.blue.shade700
                                        : Colors.white,
                                    foregroundColor: !isDriver
                                        ? Colors.white
                                        : Colors.blue.shade800,
                                    side: BorderSide(
                                      color: Colors.blue.shade700,
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 10,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: _isUpdatingRole
                                      ? null
                                      : () => _toggleUserRole(true),
                                  icon: Icon(
                                    Icons.directions_car,
                                    size: 18,
                                    color: isDriver
                                        ? Colors.white
                                        : Colors.teal.shade800,
                                  ),
                                  label: const Text('Conductor'),
                                  style: OutlinedButton.styleFrom(
                                    backgroundColor: isDriver
                                        ? Colors.teal
                                        : Colors.white,
                                    foregroundColor: isDriver
                                        ? Colors.white
                                        : Colors.teal.shade800,
                                    side: const BorderSide(color: Colors.teal),
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 10,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => MapScreen(
                                  tripData: activeTrips.isNotEmpty
                                      ? activeTrips.first
                                      : null,
                                  isDriver: isDriver,
                                ),
                              ),
                            );
                          },
                          icon: const Icon(Icons.map, color: Colors.white),
                          label: const Text('Ver Mapa'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.teal,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                      if (isDriver) ...[
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () async {
                              await Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) =>
                                      const PublishTripScreen(),
                                ),
                              );
                              if (mounted) {
                                await _loadDashboardData();
                              }
                            },
                            icon: const Icon(
                              Icons.add_road,
                              color: Colors.white,
                            ),
                            label: const Text('Publicar Viaje'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.orange.shade800,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (_userCommunities.isNotEmpty) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.teal.shade50,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.teal.shade200),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.group, color: Colors.teal),
                          const SizedBox(width: 12),
                          Expanded(
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<String>(
                                value: _selectedCommunityFilterId,
                                isExpanded: true,
                                hint: const Text('Filtrar por comunidad'),
                                items: _userCommunities
                                    .map<DropdownMenuItem<String>>((item) {
                                  final comm = item['communities'] ?? {};
                                  return DropdownMenuItem<String>(
                                    value: comm['id'].toString(),
                                    child: Text(
                                      (comm['name'] ?? 'Comunidad').toString(),
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: Colors.teal,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  );
                                }).toList(),
                                onChanged: (val) async {
                                  if (val != null &&
                                      !_activeCommunityIds().contains(val)) {
                                    return;
                                  }
                                  setState(() {
                                    _selectedCommunityFilterId = val;
                                    isLoading = true;
                                  });
                                  await _loadDashboardData();
                                },
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.teal.shade50,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.teal.shade200),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(
                              Icons.calendar_month,
                              color: Colors.teal,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Viajes para: $dateFormatted',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.teal,
                                  fontSize: 13,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton.icon(
                            onPressed: _pickFilterDate,
                            icon: const Icon(Icons.edit_calendar, size: 18),
                            label: const Text(
                              'Buscar Fecha',
                              style: TextStyle(fontSize: 12),
                            ),
                            style: TextButton.styleFrom(
                              foregroundColor: Colors.teal.shade800,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  activeTrips.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(32.0),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(
                                  Icons.event_busy_rounded,
                                  size: 70,
                                  color: Colors.grey,
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  _userCommunities.isEmpty
                                      ? 'No estás inscrito en ninguna comunidad activa aprobada.'
                                      : 'No hay viajes programados para esta comunidad el $dateFormatted',
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w500,
                                    color: Colors.grey,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                      : ListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: activeTrips.length,
                          itemBuilder: (context, index) {
                            final trip = activeTrips[index];
                            final tripId = trip['id']?.toString() ?? '';
                            final driverId = trip['driver_id']?.toString() ?? '';
                            final origin = trip['origin'] ?? '';
                            final destination = trip['destination'] ?? '';
                            final meetingPoint =
                                trip['meeting_point'] ?? 'No especificado';
                            final seats = trip['available_seats'] ?? 1;
                            final acceptedCount =
                                trip['accepted_passengers_count'] ?? 0;
                            final totalCost =
                                (trip['total_cost'] as num?)?.toDouble() ?? 0.0;
                            final tripStatus = trip['status'] ?? 'active';
                            final totalCapacity = seats + acceptedCount;
                            final costPerPerson = totalCapacity > 0
                                ? (totalCost / totalCapacity)
                                : 0.0;
                            final departureTimeFormatted =
                                _formatDateTime(trip['departure_time']);

                            double driverRating = 5.0;
                            String driverName = 'Conductor';
                            String? driverAvatarUrl;

                            final driverProfileField = trip['profiles'];
                            if (driverProfileField is Map) {
                              driverRating =
                                  (driverProfileField['rating'] as num?)
                                          ?.toDouble() ??
                                      5.0;
                              driverName =
                                  driverProfileField['full_name'] ?? 'Conductor';
                              driverAvatarUrl = driverProfileField['avatar_url'];
                            } else if (driverProfileField is List &&
                                driverProfileField.isNotEmpty) {
                              driverRating =
                                  (driverProfileField.first['rating'] as num?)
                                          ?.toDouble() ??
                                      5.0;
                              driverName = driverProfileField.first['full_name'] ??
                                  'Conductor';
                              driverAvatarUrl =
                                  driverProfileField.first['avatar_url'];
                            }

                            final isMyTrip = driverId.isNotEmpty &&
                                currentUserId.isNotEmpty &&
                                driverId == currentUserId;
                            final bool hasAcceptedPassengers = acceptedCount > 0;
                            final passengerRequestStatus =
                                userTripRequests[tripId];
                            final passengerRequestId = userRequestIds[tripId];
                            final bool isSupportDone =
                                userSupportCompleted[tripId] ?? false;
                            final bool isDriverRated =
                                _ratedKeys.contains('${tripId}_$driverId');
                            final isTripCancelled = tripStatus == 'cancelled' ||
                                passengerRequestStatus == 'trip_cancelled';
                            final cancelReason = trip['cancellation_reason'] ??
                                tripCancellationReasons[tripId] ??
                                'Motivo de fuerza mayor no especificado.';
                            final pendingCount =
                                pendingRequestsCounts[tripId] ?? 0;
                            final withdrawnCount =
                                withdrawnRequestsCounts[tripId] ?? 0;
                            final hasAlert =
                                pendingCount > 0 || withdrawnCount > 0;
                            final vehicleBrand = trip['vehicle_brand'];
                            final vehicleColor = trip['vehicle_color'];
                            final tripNotes = trip['trip_notes'];

                            final bool canPassengerChat =
                                passengerRequestStatus == 'accepted' ||
                                    passengerRequestStatus == 'pending';

                            return Container(
                              margin: const EdgeInsets.only(bottom: 12),
                              decoration: BoxDecoration(
                                color: isTripCancelled
                                    ? Colors.red.shade50
                                    : Colors.white,
                                borderRadius: BorderRadius.circular(12),
                                border: isTripCancelled
                                    ? Border.all(color: Colors.red, width: 1.5)
                                    : Border.all(
                                        color: Colors.grey.shade300,
                                        width: 1,
                                      ),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(12.0),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        CircleAvatar(
                                          backgroundColor: isTripCancelled
                                              ? Colors.red.shade100
                                              : Colors.teal.shade50,
                                          backgroundImage:
                                              driverAvatarUrl != null &&
                                                      driverAvatarUrl.isNotEmpty
                                                  ? NetworkImage(driverAvatarUrl)
                                                  : null,
                                          child: driverAvatarUrl == null ||
                                                  driverAvatarUrl.isEmpty
                                              ? Icon(
                                                  isTripCancelled
                                                      ? Icons.cancel
                                                      : Icons.directions_car,
                                                  color: isTripCancelled
                                                      ? Colors.red
                                                      : Colors.teal,
                                                )
                                              : null,
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Text(
                                            '$origin → $destination',
                                            style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 16,
                                              color: isTripCancelled
                                                  ? Colors.red.shade900
                                                  : Colors.black,
                                            ),
                                          ),
                                        ),
                                        if (!isTripCancelled)
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8,
                                              vertical: 4,
                                            ),
                                            decoration: BoxDecoration(
                                              color: Colors.teal.shade50,
                                              borderRadius:
                                                  BorderRadius.circular(6),
                                            ),
                                            child: Text(
                                              'Cupos: $seats',
                                              style: const TextStyle(
                                                color: Colors.teal,
                                                fontWeight: FontWeight.bold,
                                                fontSize: 12,
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                    const Divider(height: 16),
                                    if (isTripCancelled) ...[
                                      Container(
                                        padding: const EdgeInsets.all(10),
                                        decoration: BoxDecoration(
                                          color: Colors.white,
                                          borderRadius:
                                              BorderRadius.circular(8),
                                          border: Border.all(
                                            color: Colors.red.shade200,
                                          ),
                                        ),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            const Row(
                                              children: [
                                                Icon(
                                                  Icons.warning_amber_rounded,
                                                  color: Colors.red,
                                                  size: 18,
                                                ),
                                                SizedBox(width: 6),
                                                Expanded(
                                                  child: Text(
                                                    'VIAJE CANCELADO POR EL CONDUCTOR',
                                                    style: TextStyle(
                                                      color: Colors.red,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      fontSize: 12,
                                                    ),
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    maxLines: 2,
                                                  ),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              'Motivo: $cancelReason',
                                              style: const TextStyle(
                                                fontSize: 13,
                                                color: Colors.black87,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ] else ...[
                                      if (!isMyTrip &&
                                          passengerRequestStatus ==
                                              'accepted') ...[
                                        Container(
                                          margin:
                                              const EdgeInsets.only(bottom: 8),
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 10,
                                            vertical: 8,
                                          ),
                                          decoration: BoxDecoration(
                                            color: isSupportDone
                                                ? Colors.green.shade50
                                                : Colors.orange.shade50,
                                            borderRadius:
                                                BorderRadius.circular(8),
                                            border: Border.all(
                                              color: isSupportDone
                                                  ? Colors.green.shade300
                                                  : Colors.orange.shade300,
                                            ),
                                          ),
                                          child: Row(
                                            children: [
                                              Icon(
                                                isSupportDone
                                                    ? Icons.check_circle
                                                    : Icons.hourglass_top,
                                                size: 18,
                                                color: isSupportDone
                                                    ? Colors.green
                                                    : Colors.orange.shade800,
                                              ),
                                              const SizedBox(width: 8),
                                              Expanded(
                                                child: Text(
                                                  isSupportDone
                                                      ? 'Apoyo Confirmado por el Conductor'
                                                      : 'Pendiente realizar Apoyo (Acordar con conductor)',
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.bold,
                                                    color: isSupportDone
                                                        ? Colors.green.shade800
                                                        : Colors.orange.shade900,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                      if (isSupportDone) ...[
                                        Align(
                                          alignment: Alignment.centerLeft,
                                          child: Padding(
                                            padding: const EdgeInsets.only(
                                              bottom: 8.0,
                                            ),
                                            child: ElevatedButton.icon(
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor: isDriverRated
                                                    ? Colors.grey.shade300
                                                    : Colors.amber.shade700,
                                                foregroundColor: isDriverRated
                                                    ? Colors.grey.shade700
                                                    : Colors.white,
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                  horizontal: 10,
                                                  vertical: 6,
                                                ),
                                                minimumSize: Size.zero,
                                              ),
                                              icon: Icon(
                                                isDriverRated
                                                    ? Icons.check_circle
                                                    : Icons.star,
                                                size: 16,
                                              ),
                                              label: Text(
                                                isDriverRated
                                                    ? 'Conductor Calificado'
                                                    : 'Calificar Conductor',
                                                style: const TextStyle(
                                                  fontSize: 12,
                                                ),
                                              ),
                                              onPressed: isDriverRated
                                                  ? null
                                                  : () {
                                                      _showRatingDialog(
                                                        tripId,
                                                        driverId,
                                                        driverName,
                                                      );
                                                    },
                                            ),
                                          ),
                                        ),
                                      ],
                                      Row(
                                        children: [
                                          const Icon(
                                            Icons.access_time,
                                            size: 16,
                                            color: Colors.grey,
                                          ),
                                          const SizedBox(width: 6),
                                          Text(
                                            'Salida: $departureTimeFormatted',
                                            style: const TextStyle(
                                              fontSize: 13,
                                              color: Colors.black87,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      Row(
                                        children: [
                                          const Icon(
                                            Icons.star,
                                            size: 16,
                                            color: Colors.amber,
                                          ),
                                          const SizedBox(width: 6),
                                          Text(
                                            'Conductor - Calificación: ${driverRating.toStringAsFixed(1)} / 5.0',
                                            style: const TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w600,
                                              color: Colors.teal,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      Row(
                                        children: [
                                          const Icon(
                                            Icons.place,
                                            size: 16,
                                            color: Colors.grey,
                                          ),
                                          const SizedBox(width: 6),
                                          Expanded(
                                            child: Text(
                                              'Punto de encuentro: $meetingPoint',
                                              style: const TextStyle(
                                                fontSize: 13,
                                                color: Colors.black87,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 6),
                                      if (vehicleBrand != null &&
                                          vehicleBrand.toString().isNotEmpty) ...[
                                        Row(
                                          children: [
                                            const Icon(
                                              Icons.directions_car,
                                              size: 16,
                                              color: Colors.teal,
                                            ),
                                            const SizedBox(width: 6),
                                            Expanded(
                                              child: Text(
                                                'Vehículo: $vehicleBrand ${vehicleColor != null && vehicleColor.toString().isNotEmpty ? '($vehicleColor)' : ''}',
                                                style: const TextStyle(
                                                  fontSize: 13,
                                                  fontWeight: FontWeight.w600,
                                                  color: Colors.teal,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                      const SizedBox(height: 4),
                                      if (tripNotes != null &&
                                          tripNotes.toString().isNotEmpty) ...[
                                        Row(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            const Icon(
                                              Icons.note_alt,
                                              size: 16,
                                              color: Colors.teal,
                                            ),
                                            const SizedBox(width: 6),
                                            Expanded(
                                              child: Text(
                                                'Notas: $tripNotes',
                                                style: const TextStyle(
                                                  fontSize: 13,
                                                  fontStyle: FontStyle.italic,
                                                  color: Colors.black87,
                                                ),
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                      const SizedBox(height: 6),
                                      Row(
                                        children: [
                                          const Icon(
                                            Icons.volunteer_activism,
                                            size: 16,
                                            color: Colors.teal,
                                          ),
                                          const SizedBox(width: 6),
                                          Expanded(
                                            child: Text(
                                              'Colaboración compartida por pasajero: \$${costPerPerson.toStringAsFixed(0)}',
                                              style: const TextStyle(
                                                fontSize: 13,
                                                fontWeight: FontWeight.bold,
                                                color: Colors.teal,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 12),
                                      Wrap(
                                        alignment: WrapAlignment.end,
                                        spacing: 6,
                                        runSpacing: 6,
                                        children: [
                                          if (isMyTrip) ...[
                                            if (!isTripCancelled) ...[
                                              OutlinedButton.icon(
                                                style: OutlinedButton.styleFrom(
                                                  foregroundColor: Colors.teal,
                                                  side: const BorderSide(
                                                    color: Colors.teal,
                                                  ),
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                    horizontal: 10,
                                                    vertical: 8,
                                                  ),
                                                ),
                                                onPressed: () =>
                                                    _showDriverChatPickerDialog(
                                                  trip,
                                                ),
                                                icon: const Icon(
                                                  Icons.chat,
                                                  size: 18,
                                                ),
                                                label: const Text(
                                                  'Chat pasajeros',
                                                ),
                                              ),
                                              Container(
                                                decoration: BoxDecoration(
                                                  color: hasAlert
                                                      ? Colors.deepOrange.shade50
                                                      : null,
                                                  borderRadius:
                                                      BorderRadius.circular(8),
                                                  border: Border.all(
                                                    color: hasAlert
                                                        ? Colors.deepOrange
                                                        : Colors.teal,
                                                    width: hasAlert ? 1.5 : 1.0,
                                                  ),
                                                ),
                                                child: ElevatedButton.icon(
                                                  onPressed: () =>
                                                      _showRequestsDialog(trip),
                                                  icon: Icon(
                                                    hasAlert
                                                        ? Icons
                                                            .notification_important
                                                        : Icons.group_outlined,
                                                    size: 18,
                                                    color: hasAlert
                                                        ? Colors.deepOrange
                                                        : Colors.teal,
                                                  ),
                                                  label: Text(
                                                    hasAlert
                                                        ? 'Solicitudes (${pendingCount + withdrawnCount})'
                                                        : 'Solicitudes',
                                                    style: TextStyle(
                                                      color: hasAlert
                                                          ? Colors.deepOrange
                                                          : Colors.teal,
                                                      fontWeight: hasAlert
                                                          ? FontWeight.bold
                                                          : FontWeight.normal,
                                                    ),
                                                  ),
                                                  style: ElevatedButton.styleFrom(
                                                    backgroundColor:
                                                        Colors.transparent,
                                                    shadowColor:
                                                        Colors.transparent,
                                                    padding:
                                                        const EdgeInsets
                                                            .symmetric(
                                                      horizontal: 10,
                                                      vertical: 8,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                              Container(
                                                decoration: BoxDecoration(
                                                  borderRadius:
                                                      BorderRadius.circular(8),
                                                  border: Border.all(
                                                    color: hasAcceptedPassengers
                                                        ? Colors.grey.shade300
                                                        : Colors.teal,
                                                  ),
                                                ),
                                                child: ElevatedButton.icon(
                                                  onPressed: hasAcceptedPassengers
                                                      ? () =>
                                                          _editTrip(trip, true)
                                                      : () => _editTrip(
                                                          trip,
                                                          false,
                                                        ),
                                                  icon: Icon(
                                                    Icons.edit_outlined,
                                                    size: 18,
                                                    color: hasAcceptedPassengers
                                                        ? Colors.grey
                                                        : Colors.teal,
                                                  ),
                                                  label: Text(
                                                    'Editar',
                                                    style: TextStyle(
                                                      color:
                                                          hasAcceptedPassengers
                                                              ? Colors.grey
                                                              : Colors.teal,
                                                    ),
                                                  ),
                                                  style: ElevatedButton.styleFrom(
                                                    backgroundColor:
                                                        Colors.transparent,
                                                    shadowColor:
                                                        Colors.transparent,
                                                    padding:
                                                        const EdgeInsets
                                                            .symmetric(
                                                      horizontal: 10,
                                                      vertical: 8,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                              Container(
                                                decoration: BoxDecoration(
                                                  borderRadius:
                                                      BorderRadius.circular(8),
                                                  border: Border.all(
                                                    color: Colors.red,
                                                  ),
                                                ),
                                                child: ElevatedButton.icon(
                                                  onPressed: () =>
                                                      _showCancelTripDialog(
                                                    tripId,
                                                    hasAcceptedPassengers,
                                                  ),
                                                  icon: const Icon(
                                                    Icons.cancel_outlined,
                                                    size: 18,
                                                    color: Colors.red,
                                                  ),
                                                  label: const Text(
                                                    'Cancelar',
                                                    style: TextStyle(
                                                      color: Colors.red,
                                                    ),
                                                  ),
                                                  style: ElevatedButton.styleFrom(
                                                    backgroundColor:
                                                        Colors.transparent,
                                                    shadowColor:
                                                        Colors.transparent,
                                                    padding:
                                                        const EdgeInsets
                                                            .symmetric(
                                                      horizontal: 10,
                                                      vertical: 8,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ] else ...[
                                              const Text(
                                                'Viaje Cancelado',
                                                style: TextStyle(
                                                  color: Colors.red,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ],
                                          ] else ...[
                                            if (isTripCancelled) ...[
                                              const Text(
                                                'Notificado',
                                                style: TextStyle(
                                                  color: Colors.red,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ] else ...[
                                              OutlinedButton.icon(
                                                style: OutlinedButton.styleFrom(
                                                  foregroundColor:
                                                      canPassengerChat
                                                          ? Colors.teal
                                                          : Colors.grey,
                                                  side: BorderSide(
                                                    color: canPassengerChat
                                                        ? Colors.teal
                                                        : Colors.grey.shade400,
                                                  ),
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                    horizontal: 10,
                                                    vertical: 8,
                                                  ),
                                                ),
                                                onPressed: canPassengerChat
                                                    ? () => _openTripChat(
                                                          tripId: tripId,
                                                          tripTitle:
                                                              '$origin → $destination',
                                                          otherUserId: driverId,
                                                          otherUserName:
                                                              driverName,
                                                        )
                                                    : () {
                                                        ScaffoldMessenger.of(
                                                          context,
                                                        ).showSnackBar(
                                                          const SnackBar(
                                                            content: Text(
                                                              'Pulsa "Unirme" primero para iniciar el chat con el conductor.',
                                                            ),
                                                            backgroundColor:
                                                                Colors.orange,
                                                          ),
                                                        );
                                                      },
                                                icon: const Icon(
                                                  Icons.chat,
                                                  size: 18,
                                                ),
                                                label: const Text(
                                                  'Chat con conductor',
                                                ),
                                              ),
                                              if (passengerRequestStatus ==
                                                  'accepted') ...[
                                                ElevatedButton.icon(
                                                  style: ElevatedButton.styleFrom(
                                                    backgroundColor:
                                                        Colors.green,
                                                    foregroundColor:
                                                        Colors.white,
                                                    padding:
                                                        const EdgeInsets
                                                            .symmetric(
                                                      horizontal: 12,
                                                      vertical: 8,
                                                    ),
                                                  ),
                                                  onPressed: null,
                                                  icon: const Icon(
                                                    Icons.check_circle,
                                                    size: 18,
                                                    color: Colors.white,
                                                  ),
                                                  label: const Text(
                                                    'Viaje Aceptado',
                                                    style: TextStyle(
                                                      color: Colors.white,
                                                    ),
                                                  ),
                                                ),
                                                Container(
                                                  decoration: BoxDecoration(
                                                    borderRadius:
                                                        BorderRadius.circular(8),
                                                    border: Border.all(
                                                      color: Colors.red,
                                                    ),
                                                  ),
                                                  child: ElevatedButton.icon(
                                                    onPressed: () =>
                                                        _cancelRequest(
                                                      tripId,
                                                      passengerRequestId!,
                                                      true,
                                                    ),
                                                    icon: const Icon(
                                                      Icons.exit_to_app,
                                                      size: 18,
                                                      color: Colors.red,
                                                    ),
                                                    label: const Text(
                                                      'Desistir',
                                                      style: TextStyle(
                                                        color: Colors.red,
                                                      ),
                                                    ),
                                                    style:
                                                        ElevatedButton.styleFrom(
                                                      backgroundColor:
                                                          Colors.transparent,
                                                      shadowColor:
                                                          Colors.transparent,
                                                      padding:
                                                          const EdgeInsets
                                                              .symmetric(
                                                        horizontal: 10,
                                                        vertical: 8,
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              ] else if (passengerRequestStatus ==
                                                  'pending') ...[
                                                Container(
                                                  decoration: BoxDecoration(
                                                    borderRadius:
                                                        BorderRadius.circular(8),
                                                    border: Border.all(
                                                      color: Colors.orange,
                                                    ),
                                                  ),
                                                  child: ElevatedButton.icon(
                                                    onPressed: null,
                                                    icon: const Icon(
                                                      Icons.hourglass_top,
                                                      size: 18,
                                                      color: Colors.orange,
                                                    ),
                                                    label: const Text(
                                                      'Pendiente',
                                                      style: TextStyle(
                                                        color: Colors.orange,
                                                      ),
                                                    ),
                                                    style:
                                                        ElevatedButton.styleFrom(
                                                      backgroundColor:
                                                          Colors.transparent,
                                                      shadowColor:
                                                          Colors.transparent,
                                                      padding:
                                                          const EdgeInsets
                                                              .symmetric(
                                                        horizontal: 10,
                                                        vertical: 8,
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                                Container(
                                                  decoration: BoxDecoration(
                                                    borderRadius:
                                                        BorderRadius.circular(8),
                                                    border: Border.all(
                                                      color: Colors.red,
                                                    ),
                                                  ),
                                                  child: ElevatedButton.icon(
                                                    onPressed: () =>
                                                        _cancelRequest(
                                                      tripId,
                                                      passengerRequestId!,
                                                      false,
                                                    ),
                                                    icon: const Icon(
                                                      Icons.cancel_outlined,
                                                      size: 18,
                                                      color: Colors.red,
                                                    ),
                                                    label: const Text(
                                                      'Desistir',
                                                      style: TextStyle(
                                                        color: Colors.red,
                                                      ),
                                                    ),
                                                    style:
                                                        ElevatedButton.styleFrom(
                                                      backgroundColor:
                                                          Colors.transparent,
                                                      shadowColor:
                                                          Colors.transparent,
                                                      padding:
                                                          const EdgeInsets
                                                              .symmetric(
                                                        horizontal: 10,
                                                        vertical: 8,
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              ] else ...[
                                                ElevatedButton(
                                                  style:
                                                      ElevatedButton.styleFrom(
                                                    backgroundColor:
                                                        Colors.teal,
                                                    foregroundColor:
                                                        Colors.white,
                                                    padding:
                                                        const EdgeInsets
                                                            .symmetric(
                                                      horizontal: 16,
                                                      vertical: 8,
                                                    ),
                                                  ),
                                                  onPressed: () =>
                                                      _requestToJoin(tripId),
                                                  child: const Text('Unirme'),
                                                ),
                                              ],
                                            ],
                                          ],
                                        ],
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
      bottomNavigationBar: const LegalFooter(showSupport: true),
    );
  }
}