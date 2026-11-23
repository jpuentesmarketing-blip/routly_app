import 'package:flutter/material.dart';

class LegalFooter extends StatelessWidget {
  final bool showSupport;

  const LegalFooter({
    super.key,
    this.showSupport = false, // Por defecto solo muestra el copyright; ponlo en true si quieres el correo
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16.0, horizontal: 8.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showSupport) ...[
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
                      style: TextStyle(fontSize: 13, color: Colors.black87),
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
            const SizedBox(height: 16),
          ],
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
    );
  }
}