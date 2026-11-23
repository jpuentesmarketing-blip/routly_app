import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'create_community_screen.dart';
import 'manage_community_screen.dart';

class CommunityScreen extends StatefulWidget {
  const CommunityScreen({super.key});

  @override
  State<CommunityScreen> createState() => _CommunityScreenState();
}

class _CommunityScreenState extends State<CommunityScreen> {
  final supabase = Supabase.instance.client;
  bool isLoading = true;
  List<dynamic> myMemberships = [];
  final codeController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadUserCommunities();
  }

  Future<void> _loadUserCommunities() async {
    try {
      setState(() => isLoading = true);
      final user = supabase.auth.currentUser;
      if (user == null) return;

      // Consultar todas las membresías del usuario con sus respectivas comunidades
      final response = await supabase
          .from('community_members')
          .select('id, status, is_admin, communities(*)')
          .eq('user_id', user.id);

      setState(() {
        myMemberships = response;
        isLoading = false;
      });
    } catch (e) {
      debugPrint('Error al cargar comunidades: $e');
      setState(() => isLoading = false);
    }
  }

  Future<void> _joinCommunity() async {
    final code = codeController.text.trim();
    if (code.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Por favor ingresa un código de comunidad.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    try {
      setState(() => isLoading = true);
      final user = supabase.auth.currentUser;
      if (user == null) return;

      // Buscar la comunidad por su código de invitación (invite_code)
      final community = await supabase
          .from('communities')
          .select()
          .eq('invite_code', code)
          .maybeSingle();

      if (community == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Código de comunidad inválido o no existe.'),
            backgroundColor: Colors.red,
          ),
        );
        setState(() => isLoading = false);
        return;
      }

      // Verificar si ya existe una solicitud previa para esta comunidad
      final existingMembership = await supabase
          .from('community_members')
          .select()
          .eq('community_id', community['id'])
          .eq('user_id', user.id)
          .maybeSingle();

      if (existingMembership != null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Ya formas parte o tienes una solicitud en esta comunidad.'),
            backgroundColor: Colors.orange,
          ),
        );
        setState(() => isLoading = false);
        return;
      }

      // Insertar nueva solicitud de membresía
      await supabase.from('community_members').insert({
        'community_id': community['id'],
        'user_id': user.id,
        'status': 'pending',
        'is_admin': false,
      });

      codeController.clear();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('¡Solicitud enviada con éxito! Espera la aprobación del administrador.'),
          backgroundColor: Colors.teal,
        ),
      );
      _loadUserCommunities();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al unirse: $e'), backgroundColor: Colors.red),
      );
      setState(() => isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mis Comunidades'),
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.teal))
          : RefreshIndicator(
              onRefresh: _loadUserCommunities,
              color: Colors.teal,
              child: ListView(
                padding: const EdgeInsets.all(20.0),
                children: [
                  // --- SECCIÓN: UNIRSE A NUEVA COMUNIDAD ---
                  Card(
                    elevation: 2,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Text(
                            'Unirse a otra comunidad',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.teal,
                            ),
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: codeController,
                            decoration: const InputDecoration(
                              labelText: 'Código de invitación',
                              border: OutlineInputBorder(),
                              prefixIcon: Icon(Icons.vpn_key, color: Colors.teal),
                              isDense: true,
                            ),
                          ),
                          const SizedBox(height: 12),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.teal,
                              foregroundColor: Colors.white,
                            ),
                            onPressed: _joinCommunity,
                            child: const Text('Enviar Solicitud'),
                          ),
                          const Divider(height: 24),
                          OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.orange.shade800,
                              side: BorderSide(color: Colors.orange.shade800),
                            ),
                            onPressed: () async {
                              final created = await Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => const CreateCommunityScreen(),
                                ),
                              );
                              if (created == true) {
                                _loadUserCommunities();
                              }
                            },
                            icon: const Icon(Icons.add_business),
                            label: const Text('Crear una Nueva Comunidad'),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'Tus Comunidades Actuales',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 10),

                  // --- LISTADO DE COMUNIDADES A LAS QUE PERTENECE ---
                  myMemberships.isEmpty
                      ? const Padding(
                          padding: EdgeInsets.symmetric(vertical: 40.0),
                          child: Center(
                            child: Text(
                              'Aún no estás inscrito en ninguna comunidad.\nUsa un código arriba o crea una.',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.grey, fontSize: 14),
                            ),
                          ),
                        )
                      : ListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: myMemberships.length,
                          itemBuilder: (context, index) {
                            final membership = myMemberships[index];
                            final status = membership['status'] ?? 'pending';
                            final isAdmin = membership['is_admin'] ?? false;
                            final community = membership['communities'] ?? {};
                            final communityName = community['name'] ?? 'Comunidad';
                            
                            // Corrección clave: usar 'invite_code' en lugar de 'code'
                            final communityCode = community['invite_code'] ?? '---';
                            final communityId = community['id'];

                            Color statusColor = Colors.orange;
                            String statusText = 'Pendiente de aprobación';
                            if (status == 'approved') {
                              statusColor = Colors.teal;
                              statusText = isAdmin ? 'Aprobado (Administrador)' : 'Miembro Activo';
                            } else if (status == 'rejected') {
                              statusColor = Colors.red;
                              statusText = 'Solicitud Rechazada';
                            }

                            return Card(
                              elevation: 2,
                              margin: const EdgeInsets.only(bottom: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(16.0),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        CircleAvatar(
                                          backgroundColor: statusColor.withValues(alpha: 0.15),
                                          child: Icon(Icons.group, color: statusColor),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Text(
                                            communityName,
                                            style: const TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 8, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: statusColor.withValues(alpha: 0.1),
                                            borderRadius: BorderRadius.circular(6),
                                            border: Border.all(color: statusColor),
                                          ),
                                          child: Text(
                                            status == 'approved'
                                                ? (isAdmin ? 'Admin' : 'Activo')
                                                : status,
                                            style: TextStyle(
                                              color: statusColor,
                                              fontSize: 11,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 12),
                                    Text(
                                      'Estado: $statusText',
                                      style: const TextStyle(
                                        fontSize: 13,
                                        color: Colors.black87,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Row(
                                      children: [
                                        const Text(
                                          'Código de invitación: ',
                                          style: TextStyle(
                                            fontSize: 13,
                                            color: Colors.grey,
                                          ),
                                        ),
                                        SelectableText(
                                          communityCode,
                                          style: const TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.teal,
                                          ),
                                        ),
                                      ],
                                    ),
                                    if (status == 'approved' && isAdmin) ...[
                                      const SizedBox(height: 12),
                                      SizedBox(
                                        width: double.infinity,
                                        child: OutlinedButton.icon(
                                          style: OutlinedButton.styleFrom(
                                            foregroundColor: Colors.orange.shade800,
                                            side: BorderSide(
                                              color: Colors.orange.shade800,
                                            ),
                                          ),
                                          onPressed: () {
                                            Navigator.push(
                                              context,
                                              MaterialPageRoute(
                                                builder: (context) => ManageCommunityScreen(
                                                  communityld: communityId.toString(),
                                                ),
                                              ),
                                            );
                                          },
                                          icon: const Icon(Icons.admin_panel_settings, size: 18),
                                          label: const Text('Gestionar Solicitudes de esta Comunidad'),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ],
              ),
            ),
    );
  }
}