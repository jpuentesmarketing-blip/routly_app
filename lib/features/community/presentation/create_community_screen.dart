import 'dart:math';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class CreateCommunityScreen extends StatefulWidget {
  const CreateCommunityScreen({super.key});

  @override
  State<CreateCommunityScreen> createState() => _CreateCommunityScreenState();
}

class _CreateCommunityScreenState extends State<CreateCommunityScreen> {
  final supabase = Supabase.instance.client;
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _codeController = TextEditingController();
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _generateRandomCode();
  }

  // Genera un código aleatorio de 6 caracteres alfanuméricos
  void _generateRandomCode() {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final random = Random();
    final generatedCode = List.generate(6, (index) => chars[random.nextInt(chars.length)]).join();
    setState(() {
      _codeController.text = generatedCode;
    });
  }

  Future<void> _createCommunity() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);
    try {
      final user = supabase.auth.currentUser;
      if (user == null) return;
      final communityName = _nameController.text.trim();
      final communityCode = _codeController.text.trim().toUpperCase();

      // 1. Insertar la comunidad en la tabla 'communities' (sin creator_id)
      final newCommunity = await supabase
          .from('communities')
          .insert({
            'name': communityName,
            'invite_code': communityCode,
          })
          .select()
          .single();

      final communityId = newCommunity['id'];

      // 2. Registrar al creador como miembro aprobado y administrador en 'community_members'
      await supabase.from('community_members').insert({
        'community_id': communityId,
        'user_id': user.id,
        'status': 'approved',
        'is_admin': true,
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('¡Comunidad creada con éxito!'),
          backgroundColor: Colors.teal,
        ),
      );
      Navigator.pop(context, true); // Retorna true para refrescar la pantalla anterior
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al crear la comunidad: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Crear Comunidad'),
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.group_add, size: 70, color: Colors.teal),
              const SizedBox(height: 16),
              const Text(
                'Registra tu Comunidad',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              const Text(
                'Asigna un nombre a la comunidad y genera un código único para compartirlo con los miembros.',
                style: TextStyle(color: Colors.grey, fontSize: 14),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Nombre de la Comunidad *',
                  hintText: 'Ej: Residencial El Roble / Empresa XYZ',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.business, color: Colors.teal),
                ),
                validator: (val) {
                  if (val == null || val.trim().isEmpty) {
                    return 'Ingresa un nombre para la comunidad';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _codeController,
                      decoration: const InputDecoration(
                        labelText: 'Código de Acceso',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.key, color: Colors.teal),
                      ),
                      validator: (val) {
                        if (val == null || val.trim().isEmpty) {
                          return 'Ingresa o genera un código';
                        }
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: _generateRandomCode,
                    icon: const Icon(Icons.refresh, color: Colors.teal),
                    tooltip: 'Generar nuevo código',
                  ),
                ],
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange.shade800,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onPressed: _isLoading ? null : _createCommunity,
                child: _isLoading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                      )
                    : const Text('Crear y Registrarme como Creador', style: TextStyle(fontSize: 16)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}