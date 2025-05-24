import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'text_editor_screen.dart'; // Asegúrate de importar el editor de texto

class MyFilesScreen extends StatefulWidget {
  const MyFilesScreen({Key? key}) : super(key: key);

  @override
  _MyFilesScreenState createState() => _MyFilesScreenState();
}

class _MyFilesScreenState extends State<MyFilesScreen> {
  final SupabaseClient _supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _files = [];
  bool _isLoading = true;
  String? _errorMessage;
  bool _isOpeningFile = false;

  @override
  void initState() {
    super.initState();
    _fetchFiles();
  }

  Future<void> _fetchFiles() async {
    try {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });

      final user = _supabase.auth.currentUser;
      if (user == null) throw Exception('Usuario no autenticado');

      final userFolder = user.email?.split('@').first ?? 'user_${user.id.substring(0, 6)}';
      final basePath = 'usuarios/$userFolder/';

      final foldersResponse = await _supabase.storage
          .from('useruploads')
          .list(path: basePath);

      final folders = foldersResponse.where((f) => f.id == null).toList();
      List<Map<String, dynamic>> allFiles = [];

      for (var folder in folders) {
        try {
          final filesResponse = await _supabase.storage
              .from('useruploads')
              .list(path: '$basePath${folder.name}/');

          for (var file in filesResponse) {
            if (file.id != null) {
              final fileName = file.name;
              final fileExt = fileName.split('.').last.toLowerCase();
              
              allFiles.add({
                'name': fileName,
                'fullPath': '$basePath${folder.name}/$fileName',
                'type': fileExt,
                'folder': folder.name,
              });
            }
          }
        } catch (e) {
          debugPrint('Error al listar archivos en ${folder.name}: $e');
        }
      }

      setState(() {
        _files = allFiles;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Error al cargar archivos: ${e.toString()}';
        _isLoading = false;
      });
    }
  }

  Future<void> _deleteFile(String fullPath) async {
    try {
      await _supabase.storage.from('useruploads').remove([fullPath]);
      await _fetchFiles();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Archivo eliminado correctamente'),
          duration: Duration(seconds: 2),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al eliminar: ${e.toString()}'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _openFileWithExternalApp(Map<String, dynamic> file) async {
    if (_isOpeningFile) return;
    
    setState(() => _isOpeningFile = true);
    
    try {
      // Mostrar indicador de progreso
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              CircularProgressIndicator(),
              SizedBox(width: 20),
              Text('Preparando archivo...'),
            ],
          ),
          duration: Duration(minutes: 1),
        ),
      );

      // Descargar archivo
      final response = await _supabase.storage
          .from('useruploads')
          .download(file['fullPath']);

      // Crear archivo temporal
      final tempDir = await getTemporaryDirectory();
      final tempFile = File('${tempDir.path}/${file['name']}');
      await tempFile.writeAsBytes(response);

      // Cerrar el SnackBar de progreso
      ScaffoldMessenger.of(context).hideCurrentSnackBar();

      // Abrir con aplicación externa
      final result = await OpenFilex.open(tempFile.path);

      // Manejar resultado
      if (result.type != ResultType.done) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('No se pudo abrir el archivo: ${result.message}'),
            duration: Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al abrir archivo: ${e.toString()}'),
          duration: Duration(seconds: 3),
        ),
      );
    } finally {
      setState(() => _isOpeningFile = false);
    }
  }

  Future<void> _editTextFile(Map<String, dynamic> file) async {
    try {
      // Descargar el contenido del archivo
      final response = await _supabase.storage
          .from('useruploads')
          .download(file['fullPath']);
      
      final fileContent = String.fromCharCodes(response);
      
      // Navegar a la pantalla de edición
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => TextEditorScreen(
            initialText: fileContent,
            filePath: file['fullPath'],
            fileName: file['name'],
          ),
        ),
      );
      
      // Actualizar la lista después de editar
      await _fetchFiles();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al editar archivo: ${e.toString()}'),
          duration: Duration(seconds: 3),
        ),
      );
    }
  }

  void _confirmDelete(BuildContext context, Map<String, dynamic> file) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirmar eliminación'),
        content: Text('¿Estás seguro de eliminar "${file['name']}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _deleteFile(file['fullPath']);
            },
            child: const Text('Eliminar', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _showFileOptions(BuildContext context, Map<String, dynamic> file) {
    final isTextFile = file['type'] == 'txt';
    
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.open_in_new),
              title: const Text('Abrir'),
              onTap: () {
                Navigator.pop(context);
                _openFileWithExternalApp(file);
              },
            ),
            if (isTextFile) ListTile(
              leading: const Icon(Icons.edit),
              title: const Text('Editar'),
              onTap: () {
                Navigator.pop(context);
                _editTextFile(file);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete, color: Colors.red),
              title: const Text('Eliminar archivo', style: TextStyle(color: Colors.red)),
              onTap: () {
                Navigator.pop(context);
                _confirmDelete(context, file);
              },
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mis Archivos'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _isLoading ? null : _fetchFiles,
            tooltip: 'Actualizar lista',
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 20),
            Text('Cargando archivos...'),
          ],
        ),
      );
    }
    
    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, color: Colors.red, size: 50),
            SizedBox(height: 20),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.red, fontSize: 16),
              ),
            ),
            SizedBox(height: 20),
            ElevatedButton(
              onPressed: _fetchFiles,
              child: Text('Reintentar'),
            ),
          ],
        ),
      );
    }
    
    if (_files.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.folder_open, size: 60, color: Colors.grey[400]),
            SizedBox(height: 20),
            Text(
              'No hay archivos disponibles',
              style: TextStyle(fontSize: 18, color: Colors.grey[600]),
            ),
            SizedBox(height: 10),
            Text(
              'Sube archivos para verlos aquí',
              style: TextStyle(color: Colors.grey[500]),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: _files.length,
      itemBuilder: (context, index) {
        final file = _files[index];
        final isTextFile = file['type'] == 'txt';
        
        return Card(
          elevation: 2,
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: isTextFile 
                ? () => _editTextFile(file)
                : () => _openFileWithExternalApp(file),
            onLongPress: () => _showFileOptions(context, file),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  _getFileIcon(file['type']),
                  SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          file['name'],
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        SizedBox(height: 4),
                        Text(
                          '${file['type'].toUpperCase()} • ${file['folder']}',
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (isTextFile) IconButton(
                    icon: Icon(Icons.edit),
                    onPressed: () => _editTextFile(file),
                    tooltip: 'Editar archivo',
                  ),
                  IconButton(
                    icon: Icon(Icons.more_vert),
                    onPressed: () => _showFileOptions(context, file),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _getFileIcon(String fileType) {
    final iconSize = 28.0;
    switch (fileType) {
      case 'txt': return Icon(Icons.text_snippet, size: iconSize, color: Colors.blue);
      case 'doc': 
      case 'docx': return Icon(Icons.description, size: iconSize, color: Colors.blue);
      case 'pdf': return Icon(Icons.picture_as_pdf, size: iconSize, color: Colors.red);
      case 'jpg':
      case 'jpeg':
      case 'png': return Icon(Icons.image, size: iconSize, color: Colors.green);
      case 'xls':
      case 'xlsx': return Icon(Icons.table_chart, size: iconSize, color: Colors.green);
      case 'ppt':
      case 'pptx': return Icon(Icons.slideshow, size: iconSize, color: Colors.orange);
      case 'zip':
      case 'rar': return Icon(Icons.archive, size: iconSize, color: Colors.grey);
      default: return Icon(Icons.insert_drive_file, size: iconSize);
    }
  }
}