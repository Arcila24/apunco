import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:file_picker/file_picker.dart';
import 'package:mime/mime.dart';
import 'package:path/path.dart' as path;
import 'dart:io';
import 'login_screen.dart';

class UploadScreen extends StatefulWidget {
  @override
  _UploadScreenState createState() => _UploadScreenState();
}

class _UploadScreenState extends State<UploadScreen> {
  final SupabaseClient _supabase = Supabase.instance.client;
  bool _isUploading = false;
  double _uploadProgress = 0;

  Future<void> _uploadFile() async {
    try {
      setState(() => _isUploading = true);

      final user = _supabase.auth.currentUser;
      if (user == null) throw Exception('Debes iniciar sesión primero');

      final result = await FilePicker.platform.pickFiles(
        allowMultiple: false,
        type: FileType.custom,
        allowedExtensions: ['jpg', 'jpeg', 'png', 'pdf'],
      );

      if (result == null || result.files.isEmpty) {
        setState(() => _isUploading = false);
        return;
      }

      final file = result.files.first;
      final filePath = file.path!;
      final fileExtension = path.extension(filePath).replaceAll('.', '');

      // Estructura organizada: usuarios/[user_email]/archivos
      final userFolder =
          user.email?.split('@').first ?? 'user_${user.id.substring(0, 6)}';
      final storagePath =
          'usuarios/$userFolder/${DateTime.now().millisecondsSinceEpoch}.$fileExtension';

      await _supabase.storage.from('useruploads').upload(
            storagePath,
            File(filePath),
            fileOptions: FileOptions(
              contentType:
                  lookupMimeType(filePath) ?? 'application/octet-stream',
            ),
          );

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('✅ Archivo subido exitosamente')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('❌ Error: ${e.toString()}')),
      );
    } finally {
      setState(() => _isUploading = false);
    }
  }

  @override
  void initState() {
    super.initState();
    _supabase.auth.onAuthStateChange.listen((event) {
      print('🔐 Auth event: ${event.event}');
    });
  }

  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Subir Archivos'),
        actions: [
          IconButton(
            icon: Icon(Icons.logout),
            onPressed: () async {
              await _supabase.auth.signOut();

              // Navegación forzada con verificación de contexto
              Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (_) => LoginScreen()),
                  (route) => false);
            },
          ),
        ],
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (_isUploading) ...[
              CircularProgressIndicator(value: _uploadProgress / 100),
              SizedBox(height: 20),
              Text('Subiendo: ${_uploadProgress.toStringAsFixed(1)}%'),
            ] else
              ElevatedButton.icon(
                onPressed: _uploadFile,
                icon: Icon(Icons.cloud_upload),
                label: Text('Seleccionar Archivo'),
                style: ElevatedButton.styleFrom(
                  padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
