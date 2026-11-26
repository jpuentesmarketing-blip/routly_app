import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ManageCommunityScreen extends StatefulWidget {
  final String communityId;
  const ManageCommunityScreen({super.key, required this.communityId});

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
      if (!mounted) return;
      setState(() => isLoading = true);

      final membersResponse = await supabase
          .from('community_members')
          .select('id, status, user_id, request_message')
          .eq('community_id', widget.communityId)
          .eq('status', 'pending');

      List<dynamic> loadedMembers = [];
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
          debugPrint(
            'No se pudo cargar el perfil para $userId: $profileError',
          );
        }

        loadedMembers.add({
          ...member,
          'profiles': profileData,
        });
      }

      if (!mounted) return;
      setState(() {
        pendingMembers = loadedMembers;
        isLoading = false;
      });
    } catch (e) {
      debugPrint('Error al cargar solicitudes: $e');
      if (!mounted) return;
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
      await _loadPendingRequests();
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
                    final requestMessage =
                        (member['request_message'] ?? '').toString().trim();

                    return Card(
                      elevation: 2,
                      margin: const EdgeInsets.only(bottom: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const CircleAvatar(
                                  backgroundColor: Colors.teal,
                                  child: Icon(Icons.person, color: Colors.white),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        userName.toString(),
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 15,
                                        ),
                                      ),
                                      const Text(
                                        'Solicita unirse a la comunidad',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(
                                    Icons.check_circle,
                                    color: Colors.teal,
                                    size: 28,
                                  ),
                                  tooltip: 'Aprobar',
                                  onPressed: () => _updateMemberStatus(
                                    membershipId.toString(),
                                    'approved',
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(
                                    Icons.cancel,
                                    color: Colors.red,
                                    size: 28,
                                  ),
                                  tooltip: 'Rechazar',
                                  onPressed: () => _updateMemberStatus(
                                    membershipId.toString(),
                                    'rejected',
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: Colors.teal.shade50,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.teal.shade100),
                              ),
                              child: Text(
                                requestMessage.isNotEmpty
                                    ? 'Identificación / Mensaje: "$requestMessage"'
                                    : 'Sin mensaje de presentación adicional.',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: requestMessage.isNotEmpty
                                      ? Colors.black87
                                      : Colors.grey.shade700,
                                  fontStyle: requestMessage.isNotEmpty
                                      ? FontStyle.normal
                                      : FontStyle.italic,
                                ),
                              ),
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