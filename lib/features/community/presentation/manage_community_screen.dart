import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ManageCommunityScreen extends StatefulWidget {
  final String communityld;
  const ManageCommunityScreen({super.key, required this.communityld});

  @override
  State<ManageCommunityScreen> createState() => _ManageCommunityScreenState();
}

class _ManageCommunityScreenState extends State<ManageCommunityScreen> {
  final supabase = Supabase.instance.client;
  bool isLoading = true;
  List<dynamic> pendingMembers = [];

  @override
  void initState() {
    super.initState();
    _loadPendingRequests();
  }

  Future<void> _loadPendingRequests() async {
    try {
      setState(() => isLoading = true);

      // 1. Consultar las membresías pendientes para esta comunidad
      final membersResponse = await supabase
          .from('community_members')
          .select('id, status, user_id')
          .eq('community_id', widget.communityld)
          .eq('status', 'pending');

      List<dynamic> loadedMembers = [];

      // 2. Obtener el nombre del perfil para cada usuario solicitante
      for (var member in membersResponse) {
        final userId = member['user_id'];
        Map<String, dynamic> profileData = {'full_name': 'Usuario'};

        try {
          final profileResponse = await supabase
              .from('profiles')
              .select('full_name')
              .eq('id', userId)
              .maybeSingle();

          if (profileResponse != null) {
            profileData = profileResponse;
          }
        } catch (profileError) {
          debugPrint('No se pudo cargar el perfil para $userId: $profileError');
        }

        loadedMembers.add({
          ...member,
          'profiles': profileData,
        });
      }

      setState(() {
        pendingMembers = loadedMembers;
        isLoading = false;
      });
    } catch (e) {
      debugPrint('Error al cargar solicitudes: $e');
      setState(() => isLoading = false);
    }
  }

  Future<void> _updateMemberStatus(String membershipId, String newStatus) async {
    try {
      await supabase
          .from('community_members')
          .update({'status': newStatus})
          .eq('id', membershipId);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            newStatus == 'approved'
                ? '¡Miembro aprobado con éxito!'
                : 'Solicitud rechazada.',
          ),
          backgroundColor: newStatus == 'approved' ? Colors.teal : Colors.red,
        ),
      );
      _loadPendingRequests();
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Gestionar Solicitudes'),
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.teal))
          : pendingMembers.isEmpty
              ? const Center(
                  child: Text(
                    'No hay solicitudes pendientes en este momento.',
                    style: TextStyle(color: Colors.grey, fontSize: 16),
                    textAlign: TextAlign.center,
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: pendingMembers.length,
                  itemBuilder: (context, index) {
                    final member = pendingMembers[index];
                    final profile = member['profiles'];
                    final userName = profile is Map
                        ? (profile['full_name'] ?? 'Usuario')
                        : 'Usuario';
                    final membershipId = member['id'];

                    return Card(
                      elevation: 2,
                      margin: const EdgeInsets.only(bottom: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: ListTile(
                        leading: const CircleAvatar(
                          backgroundColor: Colors.teal,
                          child: Icon(Icons.person, color: Colors.white),
                        ),
                        title: Text(
                          userName,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: const Text(
                          'Solicita unirse a la comunidad',
                          style: TextStyle(fontSize: 12),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.check_circle,
                                  color: Colors.teal, size: 28),
                              tooltip: 'Aprobar',
                              onPressed: () =>
                                  _updateMemberStatus(membershipId, 'approved'),
                            ),
                            IconButton(
                              icon: const Icon(Icons.cancel,
                                  color: Colors.red, size: 28),
                              tooltip: 'Rechazar',
                              onPressed: () =>
                                  _updateMemberStatus(membershipId, 'rejected'),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}