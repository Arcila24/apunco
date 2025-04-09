import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:file_picker/file_picker.dart';
import 'package:mime/mime.dart';

class StorageService {
  static final SupabaseClient _supabase = Supabase.instance.client;

  static Future<String?> uploadFile() async {
    try {
      // 1. Seleccionar archivo
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: false,
        type: FileType.any,
      );

      if (result == null) return null;

      final file = result.files.first;
      final bytes = file.bytes!;
      final extension = file.extension ?? 'bin';
      final mimeType = lookupMimeType(file.name) ?? 'application/octet-stream';

      // 2. Generar ruta única (ej: user_123/archivo.pdf)
      final userId = _supabase.auth.currentUser!.id;
      final filePath = '$userId/${DateTime.now().millisecondsSinceEpoch}.$extension';

      // 3. Subir a Supabase Storage
      await _supabase.storage
          .from('useruploads')  // Nombre del bucket
          .uploadBinary(filePath, bytes, fileOptions: FileOptions(contentType: mimeType));

      // 4. Obtener URL pública (si el bucket es público)
      final publicUrl = _supabase.storage
          .from('useruploads')
          .getPublicUrl(filePath);

      return publicUrl;
    } catch (e) {
      print('Error al subir archivo: $e');
      return null;
    }
  }
}