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
  final Set<String> _busyCommunityIds = {};

  @override
  void initState() {
    super.initState();
    _loadUserCommunities();
  }

  Future<void> _loadUserCommunities() async {
    try {
      setState(() => isLoading = true);
      final user = supabase.auth.currentUser;
      if (user == null) {
        if (!mounted) return;
        setState(() => isLoading = false);
        return;
      }

      final response = await supabase
          .from('community_members')
          .select('id, status, is_admin, request_message, communities(*)')
          .eq('user_id', user.id);

      if (!mounted) return;
      setState(() {
        myMemberships = response;
        isLoading = false;
      });
    } catch (e) {
      debugPrint('Error al cargar comunidades: $e');
      if (!mounted) return;
      setState(() => isLoading = false);
    }
  }

  Future<String?> _askRequestMessageDialog(String communityName) async {
    final messageController = TextEditingController();
    String? errorText;

    final result = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(
                'Presentación para $communityName',
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                  color: Colors.teal,
                ),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Por seguridad de la comunidad, escribe un mensaje breve para el administrador indicando cómo te identificas:',
                    style: TextStyle(fontSize: 13, color: Colors.black87),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: messageController,
                    maxLines: 3,
                    maxLength: 250,
                    decoration: InputDecoration(
                      labelText: 'Mensaje de presentación *',
                      hintText:
                          'Ej: Soy vecino de la casa/apto 204, hago parte del grupo XX o estoy en tu clase de historia.',
                      border: const OutlineInputBorder(),
                      errorText: errorText,
                    ),
                    onChanged: (_) {
                      if (errorText != null) {
                        setDialogState(() => errorText = null);
                      }
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(null),
                  child: const Text(
                    'Cancelar',
                    style: TextStyle(color: Colors.grey),
                  ),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.teal,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () {
                    final text = messageController.text.trim();
                    if (text.length < 8) {
                      setDialogState(() {
                        errorText =
                            'Escribe una referencia clara (mínimo 8 caracteres).';
                      });
                      return;
                    }
                    Navigator.of(dialogContext).pop(text);
                  },
                  child: const Text('Enviar Solicitud'),
                ),
              ],
            );
          },
        );
      },
    );

    messageController.dispose();
    return result;
  }

  Future<void> _joinCommunity() async {
    final code = codeController.text.trim().toUpperCase();
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
      if (user == null) {
        if (!mounted) return;
        setState(() => isLoading = false);
        return;
      }

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

      final isActive = community['is_active'] ?? true;
      if (isActive == false) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Esta comunidad se encuentra desactivada.'),
            backgroundColor: Colors.orange,
          ),
        );
        setState(() => isLoading = false);
        return;
      }

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
            content: Text(
              'Ya formas parte o tienes una solicitud en esta comunidad.',
            ),
            backgroundColor: Colors.orange,
          ),
        );
        setState(() => isLoading = false);
        return;
      }

      if (!mounted) return;
      setState(() => isLoading = false);

      final communityName =
          (community['name'] ?? 'la comunidad').toString();
      final requestMessage = await _askRequestMessageDialog(communityName);
      if (requestMessage == null || !mounted) return;

      setState(() => isLoading = true);

      await supabase.from('community_members').insert({
        'community_id': community['id'],
        'user_id': user.id,
        'status': 'pending',
        'is_admin': false,
        'request_message': requestMessage,
      });

      codeController.clear();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            '¡Solicitud y presentación enviadas con éxito! Espera la aprobación del administrador.',
          ),
          backgroundColor: Colors.teal,
        ),
      );
      await _loadUserCommunities();
    } catch (e) {
      debugPrint('Error al unirse: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al unirse: $e'),
          backgroundColor: Colors.red,
        ),
      );
      setState(() => isLoading = false);
    }
  }

  Future<void> _toggleCommunityActive({
    required String communityId,
    required String communityName,
    required bool currentlyActive,
  }) async {
    final nextActiveState = !currentlyActive;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          nextActiveState ? 'Reactivar comunidad' : 'Desactivar comunidad',
        ),
        content: Text(
          nextActiveState
              ? '¿Deseas reactivar "$communityName"? Volverá a estar disponible para los miembros.'
              : '¿Deseas desactivar "$communityName"? Se pausará la comunidad sin borrar su historial.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor:
                  nextActiveState ? Colors.teal : Colors.orange.shade800,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(nextActiveState ? 'Reactivar' : 'Desactivar'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;
    final currentUserId = supabase.auth.currentUser?.id;
    if (currentUserId == null) return;

    setState(() => _busyCommunityIds.add(communityId));
    try {
      final updatedRows = await supabase
          .from('communities')
          .update({
            'is_active': nextActiveState,
            'deactivated_at': nextActiveState
                ? null
                : DateTime.now().toUtc().toIso8601String(),
            'deactivated_by': nextActiveState ? null : currentUserId,
          })
          .eq('id', communityId)
          .select();

      debugPrint('Filas actualizadas en communities: $updatedRows');
      if (!mounted) return;
      if (updatedRows.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'No se actualizó ninguna fila. Revisa tus permisos de admin o políticas RLS en Supabase.',
            ),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            nextActiveState
                ? 'Comunidad "$communityName" reactivada.'
                : 'Comunidad "$communityName" desactivada.',
          ),
          backgroundColor: Colors.teal,
        ),
      );
      await _loadUserCommunities();
    } catch (e) {
      debugPrint('Error al cambiar estado de la comunidad: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al cambiar estado de la comunidad: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _busyCommunityIds.remove(communityId));
      }
    }
  }

  Future<void> _deleteCommunity({
    required String communityId,
    required String communityName,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Eliminar comunidad'),
        content: Text(
          '¿Seguro que deseas eliminar definitivamente "$communityName"? Esta acción borrará la comunidad y no se puede deshacer.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;
    setState(() => _busyCommunityIds.add(communityId));

    try {
      final deleted = await supabase.rpc(
        'delete_community_as_admin',
        params: {'p_community_id': communityId},
      );

      debugPrint('Resultado delete_community_as_admin: $deleted');
      if (!mounted) return;
      if (deleted != true) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'No se eliminó ninguna fila. Revisa tus permisos de admin o políticas RLS en Supabase.',
            ),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Comunidad "$communityName" eliminada.'),
          backgroundColor: Colors.teal,
        ),
      );
      await _loadUserCommunities();
    } catch (e) {
      debugPrint('Error al eliminar la comunidad: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al eliminar la comunidad: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _busyCommunityIds.remove(communityId));
      }
    }
  }

  @override
  void dispose() {
    codeController.dispose();
    super.dispose();
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
                            textCapitalization: TextCapitalization.characters,
                            decoration: const InputDecoration(
                              labelText: 'Código de invitación',
                              border: OutlineInputBorder(),
                              prefixIcon: Icon(
                                Icons.vpn_key,
                                color: Colors.teal,
                              ),
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
                              final created = await Navigator.push<bool>(
                                context,
                                MaterialPageRoute(
                                  builder: (context) =>
                                      const CreateCommunityScreen(),
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
                  myMemberships.isEmpty
                      ? const Padding(
                          padding: EdgeInsets.symmetric(vertical: 40.0),
                          child: Center(
                            child: Text(
                              'Aún no estás inscrito en ninguna comunidad.\nUsa un código arriba o crea una.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.grey,
                                fontSize: 14,
                              ),
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
                            final requestMessage =
                                (membership['request_message'] ?? '')
                                    .toString()
                                    .trim();
                            final community = membership['communities'] ?? {};
                            final communityId =
                                community['id']?.toString() ?? '';
                            final communityName =
                                community['name'] ?? 'Comunidad';
                            final communityCode =
                                community['invite_code'] ?? '---';
                            final isActive = community['is_active'] ?? true;
                            final isBusy =
                                _busyCommunityIds.contains(communityId);

                            Color statusColor = Colors.orange;
                            String statusText = 'Pendiente de aprobación';
                            if (!isActive) {
                              statusColor = Colors.grey;
                              statusText = 'Comunidad Desactivada';
                            } else if (status == 'approved') {
                              statusColor = Colors.teal;
                              statusText = isAdmin
                                  ? 'Aprobado (Administrador)'
                                  : 'Miembro Activo';
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
                                          backgroundColor:
                                              statusColor.withValues(
                                            alpha: 0.15,
                                          ),
                                          child: Icon(
                                            Icons.group,
                                            color: statusColor,
                                          ),
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
                                            horizontal: 8,
                                            vertical: 4,
                                          ),
                                          decoration: BoxDecoration(
                                            color: statusColor.withValues(
                                              alpha: 0.1,
                                            ),
                                            borderRadius:
                                                BorderRadius.circular(6),
                                            border: Border.all(
                                              color: statusColor,
                                            ),
                                          ),
                                          child: Text(
                                            !isActive
                                                ? 'Inactiva'
                                                : (status == 'approved'
                                                    ? (isAdmin
                                                        ? 'Admin'
                                                        : 'Activo')
                                                    : status),
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
                                    if (status == 'pending' &&
                                        requestMessage.isNotEmpty) ...[
                                      const SizedBox(height: 8),
                                      Container(
                                        width: double.infinity,
                                        padding: const EdgeInsets.all(8),
                                        decoration: BoxDecoration(
                                          color: Colors.orange.shade50,
                                          borderRadius:
                                              BorderRadius.circular(6),
                                          border: Border.all(
                                            color: Colors.orange.shade200,
                                          ),
                                        ),
                                        child: Text(
                                          'Tu mensaje de presentación: "$requestMessage"',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.orange.shade900,
                                            fontStyle: FontStyle.italic,
                                          ),
                                        ),
                                      ),
                                    ],
                                    if (status == 'approved' &&
                                        isAdmin &&
                                        communityId.isNotEmpty) ...[
                                      const SizedBox(height: 12),
                                      SizedBox(
                                        width: double.infinity,
                                        child: OutlinedButton.icon(
                                          style: OutlinedButton.styleFrom(
                                            foregroundColor:
                                                Colors.orange.shade800,
                                            side: BorderSide(
                                              color: Colors.orange.shade800,
                                            ),
                                          ),
                                          onPressed: isBusy
                                              ? null
                                              : () {
                                                  Navigator.push(
                                                    context,
                                                    MaterialPageRoute(
                                                      builder: (context) =>
                                                          ManageCommunityScreen(
                                                        communityId:
                                                            communityId,
                                                      ),
                                                    ),
                                                  );
                                                },
                                          icon: const Icon(
                                            Icons.admin_panel_settings,
                                            size: 18,
                                          ),
                                          label: const Text(
                                            'Gestionar Solicitudes de esta Comunidad',
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      Row(
                                        children: [
                                          Expanded(
                                            child: OutlinedButton.icon(
                                              style: OutlinedButton.styleFrom(
                                                foregroundColor: isActive
                                                    ? Colors.orange.shade800
                                                    : Colors.teal,
                                                side: BorderSide(
                                                  color: isActive
                                                      ? Colors.orange.shade800
                                                      : Colors.teal,
                                                ),
                                              ),
                                              onPressed: isBusy
                                                  ? null
                                                  : () =>
                                                      _toggleCommunityActive(
                                                        communityId:
                                                            communityId,
                                                        communityName:
                                                            communityName,
                                                        currentlyActive:
                                                            isActive,
                                                      ),
                                              icon: Icon(
                                                isActive
                                                    ? Icons.pause_circle_outline
                                                    : Icons.play_circle_outline,
                                                size: 18,
                                              ),
                                              label: Text(
                                                isActive
                                                    ? 'Desactivar'
                                                    : 'Reactivar',
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: OutlinedButton.icon(
                                              style: OutlinedButton.styleFrom(
                                                foregroundColor: Colors.red,
                                                side: const BorderSide(
                                                  color: Colors.red,
                                                ),
                                              ),
                                              onPressed: isBusy
                                                  ? null
                                                  : () => _deleteCommunity(
                                                        communityId:
                                                            communityId,
                                                        communityName:
                                                            communityName,
                                                      ),
                                              icon: const Icon(
                                                Icons.delete_outline,
                                                size: 18,
                                              ),
                                              label: const Text('Eliminar'),
                                            ),
                                          ),
                                        ],
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