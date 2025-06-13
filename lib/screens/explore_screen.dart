import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:url_launcher/url_launcher.dart';

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
  final TextEditingController _commentController = TextEditingController();

  Map<String, List<Map<String, dynamic>>> _commentsMap = {};
  Map<String, int> _commentsCountMap = {};

  @override
  void initState() {
    super.initState();
    _fetchAllFiles();
    _searchController.addListener(_filterFiles);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _fetchAllFiles() async {
    try {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });

      // Obtener conteo de comentarios para todos los archivos
      final commentsCountResponse = await _supabase
          .from('file_comments_count')
          .select('file_path, count');

      if (commentsCountResponse != null) {
        for (var item in commentsCountResponse) {
          _commentsCountMap[item['file_path']] = item['count'];
        }
      }

      // Listar todos los usuarios
      final usersResponse =
          await _supabase.storage.from('useruploads').list(path: 'usuarios/');

      final userFolders = usersResponse.where((f) => f.id == null).toList();
      List<Map<String, dynamic>> allFiles = [];

      for (var userFolder in userFolders) {
        try {
          // Listar todas las carpetas de tipo de cada usuario
          final typeFoldersResponse = await _supabase.storage
              .from('useruploads')
              .list(path: 'usuarios/${userFolder.name}/');

          final typeFolders =
              typeFoldersResponse.where((f) => f.id == null).toList();

          for (var typeFolder in typeFolders) {
            try {
              // Listar todos los archivos de cada carpeta de tipo
              final filesResponse = await _supabase.storage
                  .from('useruploads')
                  .list(
                      path: 'usuarios/${userFolder.name}/${typeFolder.name}/');

              for (var file in filesResponse) {
                if (file.id != null) {
                  final fileName = file.name;
                  final fileExt = fileName.split('.').last.toLowerCase();
                  final fullPath =
                      'usuarios/${userFolder.name}/${typeFolder.name}/$fileName';

                  allFiles.add({
                    'name': fileName,
                    'fullPath': fullPath,
                    'type': fileExt,
                    'folder': typeFolder.name,
                    'user': userFolder.name,
                    'commentsCount': _commentsCountMap[fullPath] ?? 0,
                  });
                }
              }
            } catch (e) {
              debugPrint('Error al listar archivos en ${typeFolder.name}: $e');
            }
          }
        } catch (e) {
          debugPrint(
              'Error al listar carpetas de usuario ${userFolder.name}: $e');
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

  Future<void> _fetchCommentsForFile(String filePath) async {
    try {
      final response = await _supabase
          .from('file_comments')
          .select('*')
          .eq('file_path', filePath)
          .order('created_at', ascending: false);

      if (response != null) {
        setState(() {
          _commentsMap[filePath] = (response).cast<Map<String, dynamic>>();
        });
      }
    } catch (e) {
      debugPrint('Error al cargar comentarios: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al cargar comentarios')),
      );
    }
  }

  Future<void> _addComment(String filePath) async {
    if (_commentController.text.trim().isEmpty) return;

    final user = _supabase.auth.currentUser;
    if (user == null || user.email == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Debes iniciar sesión para comentar')),
      );
      return;
    }

    try {
      await _supabase.from('file_comments').insert({
        'file_path': filePath,
        'user_email': user.email,
        'comment': _commentController.text.trim(),
      });

      // Actualizar lista de comentarios
      await _fetchCommentsForFile(filePath);

      // Actualizar contador en la lista de archivos
      // Volver a obtener el conteo actualizado desde Supabase
      final updatedCountResponse = await _supabase
          .from('file_comments_count')
          .select('count')
          .eq('file_path', filePath)
          .single();

      final updatedCount = updatedCountResponse['count'];

      setState(() {
        final fileIndex =
            _allFiles.indexWhere((f) => f['fullPath'] == filePath);
        if (fileIndex != -1) {
          _allFiles[fileIndex]['commentsCount'] = updatedCount;
        }

        final filteredIndex =
            _filteredFiles.indexWhere((f) => f['fullPath'] == filePath);
        if (filteredIndex != -1) {
          _filteredFiles[filteredIndex]['commentsCount'] = updatedCount;
        }
      });

      _commentController.clear();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al agregar comentario: ${e.toString()}')),
      );
    }
  }

  void _showCommentsDialog(BuildContext context, Map<String, dynamic> file) {
    final filePath = file['fullPath'];

    // Cargar comentarios si no están en caché
    if (!_commentsMap.containsKey(filePath)) {
      _fetchCommentsForFile(filePath);
    }

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('Comentarios: ${file['name']}'),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Lista de comentarios
                Expanded(
                  child: _commentsMap[filePath] == null
                      ? Center(child: CircularProgressIndicator())
                      : _commentsMap[filePath]!.isEmpty
                          ? Center(child: Text('No hay comentarios aún'))
                          : ListView.builder(
                              shrinkWrap: true,
                              itemCount: _commentsMap[filePath]!.length,
                              itemBuilder: (context, index) {
                                final comment = _commentsMap[filePath]![index];
                                return Card(
                                  margin: EdgeInsets.symmetric(vertical: 4),
                                  child: ListTile(
                                    title: Text(comment['comment']),
                                    subtitle: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          comment['user_email'],
                                          style: TextStyle(
                                              fontWeight: FontWeight.bold),
                                        ),
                                        Text(
                                          _formatDate(comment['created_at']),
                                          style: TextStyle(fontSize: 12),
                                        ),
                                      ],
                                    ),
                                    leading: Icon(Icons.account_circle),
                                  ),
                                );
                              },
                            ),
                ),
                Divider(),
                // Campo para nuevo comentario
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _commentController,
                        decoration: InputDecoration(
                          hintText: 'Escribe un comentario...',
                          border: OutlineInputBorder(),
                          contentPadding: EdgeInsets.symmetric(horizontal: 10),
                        ),
                        maxLines: 2,
                        minLines: 1,
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.send, color: Colors.blue),
                      onPressed: () => _addComment(filePath),
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Cerrar'),
            ),
          ],
        );
      },
    );
  }

  String _formatDate(String dateString) {
    try {
      final date = DateTime.parse(dateString).toLocal();
      return '${date.day}/${date.month}/${date.year} ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
    } catch (e) {
      return dateString;
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
        const SnackBar(
          content: Text('Preparando archivo...'),
          duration: Duration(seconds: 2),
        ),
      );

      if (kIsWeb) {
        final url = await _supabase.storage
            .from('useruploads')
            .createSignedUrl(file['fullPath'], 60 * 5); // 5 min
        // Abre el archivo en una nueva pestaña
        await launchUrl(Uri.parse(url));
      } else {
        final response = await _supabase.storage
            .from('useruploads')
            .download(file['fullPath']);

        final tempDir = await getTemporaryDirectory();
        final tempFile = File('${tempDir.path}/${file['name']}');
        await tempFile.writeAsBytes(response);

        final result = await OpenFilex.open(tempFile.path);

        if (result.type != ResultType.done) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('No se pudo abrir el archivo: ${result.message}'),
              duration: Duration(seconds: 3),
            ),
          );
        }
      }
    } catch (e) {
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
      if (kIsWeb) {
        final url = await _supabase.storage
            .from('useruploads')
            .createSignedUrl(file['fullPath'], 60 * 10); // 10 min

        await Share.share(
          'Te comparto este archivo: ${file['name']}\n$url',
          subject: 'Compartiendo archivo',
        );
      } else {
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
      }
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
            ListTile(
              leading: const Icon(Icons.comment),
              title: const Text('Ver comentarios'),
              onTap: () {
                Navigator.pop(context);
                _showCommentsDialog(context, file);
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
      case 'txt':
        return Icon(Icons.text_snippet, size: iconSize, color: Colors.blue);
      case 'doc':
      case 'docx':
        return Icon(Icons.description, size: iconSize, color: Colors.blue);
      case 'pdf':
        return Icon(Icons.picture_as_pdf, size: iconSize, color: Colors.red);
      case 'jpg':
      case 'jpeg':
      case 'png':
        return Icon(Icons.image, size: iconSize, color: Colors.green);
      case 'xls':
      case 'xlsx':
        return Icon(Icons.table_chart, size: iconSize, color: Colors.green);
      case 'ppt':
      case 'pptx':
        return Icon(Icons.slideshow, size: iconSize, color: Colors.orange);
      case 'zip':
      case 'rar':
        return Icon(Icons.archive, size: iconSize, color: Colors.grey);
      default:
        return Icon(Icons.insert_drive_file, size: iconSize);
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
        final commentsCount = file['commentsCount'] ?? 0;

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
                  // Botón de comentarios con contador
                  IconButton(
                    icon: Badge(
                      label: Text(commentsCount.toString()),
                      isLabelVisible: commentsCount > 0,
                      child: Icon(Icons.comment_outlined),
                    ),
                    onPressed: () => _showCommentsDialog(context, file),
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
