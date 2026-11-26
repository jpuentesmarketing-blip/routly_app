import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl_phone_field/intl_phone_field.dart';
import 'package:image_picker/image_picker.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _supabase = Supabase.instance.client;
  final _fullNameController = TextEditingController();
  final _phoneController = TextEditingController();

  bool _isDriver = false;
  bool _isLoading = true;
  bool _isUpdating = false;
  List<dynamic> _userCommunities = [];

  double _userRating = 5.0;
  int _totalRatings = 0;
  String? _avatarUrl;
  String _completePhoneNumber = '';

  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _loadProfileAndCommunities();
  }

  Future<void> _loadProfileAndCommunities() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) {
        if (mounted) {
          setState(() => _isLoading = false);
        }
        return;
      }

      final profileData = await _supabase
          .from('profiles')
          .select()
          .eq('id', user.id)
          .maybeSingle();

      final membershipsData = await _supabase
          .from('community_members')
          .select('status, is_admin, communities (name, invite_code)')
          .eq('user_id', user.id);

      if (mounted) {
        setState(() {
          if (profileData != null) {
            _fullNameController.text = profileData['full_name'] ?? '';
            String rawPhone = profileData['phone_number'] ?? '';
            _completePhoneNumber = rawPhone;
            if (rawPhone.startsWith('+57')) {
              rawPhone = rawPhone.replaceFirst('+57', '');
            } else if (rawPhone.startsWith('+')) {
              rawPhone = rawPhone.replaceFirst(RegExp(r'^\+\d+'), '');
            }
            _phoneController.text = rawPhone;
            _isDriver = profileData['is_driver'] ?? false;
            _userRating = (profileData['rating'] as num?)?.toDouble() ?? 5.0;
            _totalRatings = (profileData['total_ratings'] as int?) ?? 0;
            _avatarUrl = profileData['avatar_url'];
          } else {
            _fullNameController.text = '';
            _phoneController.text = '';
            _completePhoneNumber = '';
            _isDriver = false;
            _userRating = 5.0;
            _totalRatings = 0;
            _avatarUrl = null;
          }
          _userCommunities = membershipsData;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al cargar perfil o comunidades: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _pickAndUploadImage() async {
    try {
      final XFile? image = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 70,
      );
      if (image == null) return;

      setState(() => _isUpdating = true);
      final user = _supabase.auth.currentUser;
      if (user == null) return;

      String fileExt = 'jpg';
      if (image.name.contains('.')) {
        fileExt = image.name.split('.').last.toLowerCase();
      }
      final fileName =
          '${user.id}_${DateTime.now().millisecondsSinceEpoch}.$fileExt';
      final filePath = 'avatars/$fileName';

      final bytes = await image.readAsBytes();

      await _supabase.storage.from('profiles').uploadBinary(
            filePath,
            bytes,
            fileOptions: FileOptions(
              upsert: true,
              contentType: 'image/$fileExt',
            ),
          );

      final publicUrl = _supabase.storage.from('profiles').getPublicUrl(filePath);

      await _supabase.from('profiles').update({
        'avatar_url': publicUrl,
      }).eq('id', user.id);

      if (mounted) {
        setState(() {
          _avatarUrl = publicUrl;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('¡Foto de perfil actualizada con éxito!'),
            backgroundColor: Colors.teal,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al subir la imagen: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isUpdating = false);
    }
  }

  Future<void> _updateProfile() async {
    setState(() => _isUpdating = true);
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return;

      final phoneToSave = _completePhoneNumber.trim().isNotEmpty
          ? _completePhoneNumber.trim()
          : _phoneController.text.trim();

      await _supabase.from('profiles').upsert({
        'id': user.id,
        'full_name': _fullNameController.text.trim(),
        'phone_number': phoneToSave,
        'is_driver': _isDriver,
      });

      await _loadProfileAndCommunities();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('¡Perfil y rol actualizados con éxito!'),
            backgroundColor: Colors.teal,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al actualizar: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isUpdating = false);
    }
  }

  @override
  void dispose() {
    _fullNameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final userEmail = _supabase.auth.currentUser?.email ?? '';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mi Perfil y Comunidades'),
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.teal))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Stack(
                      children: [
                        CircleAvatar(
                          radius: 50,
                          backgroundColor: Colors.teal.shade100,
                          backgroundImage:
                              _avatarUrl != null && _avatarUrl!.isNotEmpty
                                  ? NetworkImage(_avatarUrl!)
                                  : null,
                          child: _avatarUrl == null || _avatarUrl!.isEmpty
                              ? const Icon(
                                  Icons.person,
                                  size: 50,
                                  color: Colors.teal,
                                )
                              : null,
                        ),
                        Positioned(
                          bottom: 0,
                          right: 0,
                          child: CircleAvatar(
                            backgroundColor: Colors.teal,
                            radius: 16,
                            child: IconButton(
                              padding: EdgeInsets.zero,
                              icon: const Icon(
                                Icons.camera_alt,
                                size: 16,
                                color: Colors.white,
                              ),
                              onPressed: _pickAndUploadImage,
                              tooltip: 'Cambiar foto de perfil',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    userEmail,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.grey, fontSize: 14),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.star, color: Colors.amber, size: 22),
                      const SizedBox(width: 6),
                      Text(
                        'Calificación: ${_userRating.toStringAsFixed(1)} / 5.0 ($_totalRatings ${_totalRatings == 1 ? 'reseña' : 'reseñas'})',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: Colors.teal,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  TextField(
                    controller: _fullNameController,
                    decoration: const InputDecoration(
                      labelText: 'Nombre completo',
                      prefixIcon: Icon(Icons.person_outline),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  IntlPhoneField(
                    controller: _phoneController,
                    decoration: const InputDecoration(
                      labelText: 'Teléfono',
                      border: OutlineInputBorder(),
                    ),
                    initialCountryCode: 'CO',
                    onChanged: (phone) {
                      _completePhoneNumber = phone.completeNumber;
                    },
                  ),
                  const SizedBox(height: 16),
                  Card(
                    elevation: 1,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                      side: BorderSide(color: Colors.grey.shade300),
                    ),
                    child: SwitchListTile(
                      title: const Text(
                        'Modo Conductor',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Text(
                        _isDriver
                            ? 'Activo: Puedes publicar y ofrecer viajes.'
                            : 'Inactivo: Actualmente eres pasajero.',
                        style: const TextStyle(fontSize: 12),
                      ),
                      value: _isDriver,
                      activeThumbColor: Colors.teal,
                      onChanged: (value) {
                        setState(() => _isDriver = value);
                      },
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'Mis Comunidades y Roles',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.teal,
                    ),
                  ),
                  const SizedBox(height: 10),
                  _userCommunities.isEmpty
                      ? const Card(
                          child: Padding(
                            padding: EdgeInsets.all(16.0),
                            child: Text(
                              'No estás inscrito en ninguna comunidad actualmente.',
                              style: TextStyle(color: Colors.grey),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        )
                      : ListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: _userCommunities.length,
                          itemBuilder: (context, index) {
                            final membership = _userCommunities[index];
                            final community = membership['communities'] ?? {};
                            final communityName =
                                community['name'] ?? 'Comunidad';
                            final inviteCode = community['invite_code'] ?? '';
                            final status = membership['status'] ?? 'pending';
                            final isAdmin = membership['is_admin'] ?? false;

                            Color statusColor = Colors.orange;
                            String statusLabel = 'Pendiente';
                            if (status == 'approved') {
                              statusColor =
                                  isAdmin ? Colors.purple : Colors.teal;
                              statusLabel = isAdmin
                                  ? 'Administrador'
                                  : 'Miembro Activo';
                            } else if (status == 'rejected') {
                              statusColor = Colors.red;
                              statusLabel = 'Rechazado';
                            }

                            return Card(
                              elevation: 2,
                              margin: const EdgeInsets.only(bottom: 8),
                              child: ListTile(
                                leading: CircleAvatar(
                                  backgroundColor:
                                      statusColor.withValues(alpha: 0.15),
                                  child: Icon(
                                    isAdmin
                                        ? Icons.admin_panel_settings
                                        : Icons.group,
                                    color: statusColor,
                                  ),
                                ),
                                title: Text(
                                  communityName,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                subtitle: Text(
                                  'Rol: $statusLabel ${inviteCode.isNotEmpty ? "(Código: $inviteCode)" : ""}',
                                ),
                                trailing: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: statusColor.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(color: statusColor),
                                  ),
                                  child: Text(
                                    statusLabel,
                                    style: TextStyle(
                                      color: statusColor,
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                  const SizedBox(height: 24),
                  Card(
                    elevation: 1,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                      side: BorderSide(color: Colors.teal.shade200),
                    ),
                    child: const Padding(
                      padding: EdgeInsets.all(12.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.help_outline, color: Colors.teal),
                              SizedBox(width: 8),
                              Text(
                                '¿Preguntas frecuentes?',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                  color: Colors.teal,
                                ),
                              ),
                            ],
                          ),
                          SizedBox(height: 6),
                          Text(
                            'Soporte técnico del app:',
                            style:
                                TextStyle(fontSize: 13, color: Colors.black87),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'jpuentesmarketing@genolabsas.com',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: Colors.teal,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),
                  _isUpdating
                      ? const Center(
                          child: CircularProgressIndicator(color: Colors.teal),
                        )
                      : ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.teal,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                          onPressed: _updateProfile,
                          child: const Text(
                            'Guardar Cambios',
                            style: TextStyle(fontSize: 16),
                          ),
                        ),
                  const SizedBox(height: 24),
                  const Divider(),
                  const SizedBox(height: 8),
                  Text(
                    '© ${DateTime.now().year} GENOLAB SAS. Todos los derechos reservados.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey.shade700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Esta aplicación y su código fuente están protegidos por leyes nacionales e internacionales de derechos de autor y propiedad industrial. Queda totalmente prohibida su reproducción, copia total o parcial, o distribución sin la autorización expresa y por escrito de GENOLAB SAS.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey.shade600,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}