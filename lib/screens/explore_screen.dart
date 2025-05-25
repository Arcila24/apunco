import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'dart:io';

class ExploreScreen extends StatefulWidget {
  const ExploreScreen({Key? key}) : super(key: key);

  @override
  _ExploreScreenState createState() => _ExploreScreenState();
}

class _ExploreScreenState extends State<ExploreScreen> {
  final SupabaseClient _supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _allFiles = [];
  List<Map<String, dynamic>> _filteredFiles = [];
  bool _isLoading = true;
  String? _errorMessage;
  bool _isOpeningFile = false;
  bool _isSharingFile = false;
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _fetchAllFiles();
    _searchController.addListener(_filterFiles);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _fetchAllFiles() async {
    try {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });

      // Listar todos los usuarios
      final usersResponse = await _supabase.storage
          .from('useruploads')
          .list(path: 'usuarios/');

      final userFolders = usersResponse.where((f) => f.id == null).toList();
      List<Map<String, dynamic>> allFiles = [];

      for (var userFolder in userFolders) {
        try {
          // Listar todas las carpetas de tipo de cada usuario
          final typeFoldersResponse = await _supabase.storage
              .from('useruploads')
              .list(path: 'usuarios/${userFolder.name}/');

          final typeFolders = typeFoldersResponse.where((f) => f.id == null).toList();

          for (var typeFolder in typeFolders) {
            try {
              // Listar todos los archivos de cada carpeta de tipo
              final filesResponse = await _supabase.storage
                  .from('useruploads')
                  .list(path: 'usuarios/${userFolder.name}/${typeFolder.name}/');

              for (var file in filesResponse) {
                if (file.id != null) {
                  final fileName = file.name;
                  final fileExt = fileName.split('.').last.toLowerCase();
                  
                  allFiles.add({
                    'name': fileName,
                    'fullPath': 'usuarios/${userFolder.name}/${typeFolder.name}/$fileName',
                    'type': fileExt,
                    'folder': typeFolder.name,
                    'user': userFolder.name,
                  });
                }
              }
            } catch (e) {
              debugPrint('Error al listar archivos en ${typeFolder.name}: $e');
            }
          }
        } catch (e) {
          debugPrint('Error al listar carpetas de usuario ${userFolder.name}: $e');
        }
      }

      setState(() {
        _allFiles = allFiles;
        _filteredFiles = allFiles;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Error al cargar archivos: ${e.toString()}';
        _isLoading = false;
      });
    }
  }

  void _filterFiles() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      _filteredFiles = _allFiles.where((file) {
        return file['name'].toLowerCase().contains(query) ||
               file['user'].toLowerCase().contains(query) ||
               file['type'].toLowerCase().contains(query);
      }).toList();
    });
  }

  Future<void> _openFileWithExternalApp(Map<String, dynamic> file) async {
    if (_isOpeningFile) return;
    
    setState(() => _isOpeningFile = true);
    
    try {
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

      final response = await _supabase.storage
          .from('useruploads')
          .download(file['fullPath']);

      final tempDir = await getTemporaryDirectory();
      final tempFile = File('${tempDir.path}/${file['name']}');
      await tempFile.writeAsBytes(response);

      ScaffoldMessenger.of(context).hideCurrentSnackBar();

      final result = await OpenFilex.open(tempFile.path);

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

  Future<void> _shareFile(Map<String, dynamic> file) async {
    if (_isSharingFile) return;
    
    setState(() => _isSharingFile = true);
    
    try {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Preparando archivo para compartir...'),
          duration: Duration(seconds: 2),
        ),
      );

      final response = await _supabase.storage
          .from('useruploads')
          .download(file['fullPath']);

      final tempDir = await getTemporaryDirectory();
      final tempFile = File('${tempDir.path}/${file['name']}');
      await tempFile.writeAsBytes(response);

      await Share.shareXFiles(
        [XFile(tempFile.path)],
        text: 'Te comparto este archivo: ${file['name']}',
        subject: 'Compartiendo archivo',
      );

    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al compartir archivo: ${e.toString()}'),
          duration: Duration(seconds: 3),
        ),
      );
    } finally {
      setState(() => _isSharingFile = false);
    }
  }

  void _showFileOptions(BuildContext context, Map<String, dynamic> file) {
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
            ListTile(
              leading: const Icon(Icons.share),
              title: const Text('Compartir'),
              onTap: () {
                Navigator.pop(context);
                _shareFile(file);
              },
            ),
          ],
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Explorar Archivos'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _isLoading ? null : _fetchAllFiles,
            tooltip: 'Actualizar lista',
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(60),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Buscar archivos...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                filled: true,
                fillColor: Colors.white,
              ),
            ),
          ),
        ),
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
              onPressed: _fetchAllFiles,
              child: Text('Reintentar'),
            ),
          ],
        ),
      );
    }
    
    if (_filteredFiles.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search_off, size: 60, color: Colors.grey[400]),
            SizedBox(height: 20),
            Text(
              _searchController.text.isEmpty
                  ? 'No hay archivos disponibles para explorar'
                  : 'No se encontraron resultados',
              style: TextStyle(fontSize: 18, color: Colors.grey[600]),
            ),
            if (_searchController.text.isNotEmpty) ...[
              SizedBox(height: 10),
              ElevatedButton(
                onPressed: () {
                  _searchController.clear();
                  _filterFiles();
                },
                child: Text('Limpiar búsqueda'),
              ),
            ],
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: _filteredFiles.length,
      itemBuilder: (context, index) {
        final file = _filteredFiles[index];
        
        return Card(
          elevation: 2,
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => _openFileWithExternalApp(file),
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
                          '${file['type'].toUpperCase()} • ${file['user']}',
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
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
}