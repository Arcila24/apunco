import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'text_editor_screen.dart';

class MyFilesScreen extends StatefulWidget {
  final Function(String)? onFileTap;

  const MyFilesScreen({Key? key, this.onFileTap}) : super(key: key);

  @override
  _MyFilesScreenState createState() => _MyFilesScreenState();
}

class _MyFilesScreenState extends State<MyFilesScreen> {
  final SupabaseClient _supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _files = [];
  bool _isLoading = true;
  String? _errorMessage;
  final List<String> _editableExtensions = ['txt', 'doc', 'docx'];

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

      final userFolder = 
          user.email?.split('@').first ?? 'user_${user.id.substring(0, 6)}';
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
              final fileExt = fileName.contains('.') 
                  ? fileName.split('.').last.toLowerCase()
                  : 'unknown';
                  
              allFiles.add({
                'name': fileName,
                'fullPath': '$basePath${folder.name}/$fileName',
                'displayPath': '${folder.name}/$fileName',
                'type': fileExt,
                'folder': folder.name,
                'isEditable': _editableExtensions.contains(fileExt),
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Archivo eliminado correctamente'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      await _fetchFiles();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al eliminar: ${e.toString()}'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _showFileActions(BuildContext context, Map<String, dynamic> file) {
    final isEditable = file['isEditable'] ?? false;

    showModalBottomSheet(
      context: context,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return SafeArea(
          child: Wrap(
            children: [
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text(
                  file['name'],
                  style: Theme.of(context).textTheme.titleLarge,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Divider(height: 1),
              ListTile(
                leading: Icon(Icons.open_in_new, color: Theme.of(context).primaryColor),
                title: Text('Abrir archivo'),
                onTap: () {
                  Navigator.pop(context);
                  _openFile(file);
                },
              ),
              if (isEditable) ListTile(
                leading: Icon(Icons.edit, color: Theme.of(context).primaryColor),
                title: Text('Editar contenido'),
                onTap: () => _editFile(context, file),
              ),
              ListTile(
                leading: Icon(Icons.delete, color: Colors.red),
                title: Text('Eliminar archivo', style: TextStyle(color: Colors.red)),
                onTap: () => _confirmDelete(context, file),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _openFile(Map<String, dynamic> file) async {
    // Aquí puedes implementar la lógica para abrir el archivo directamente
    // sin descargarlo localmente si es posible
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Función de abrir archivo en desarrollo'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _editFile(BuildContext context, Map<String, dynamic> file) async {
    try {
      final response = await _supabase.storage
          .from('useruploads')
          .download(file['fullPath']);
      
      final content = String.fromCharCodes(response);
      Navigator.pop(context);
      
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => TextEditorScreen(
            initialText: content,
            filePath: file['fullPath'],
          ),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al editar archivo: ${e.toString()}'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _confirmDelete(BuildContext context, Map<String, dynamic> file) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Confirmar eliminación'),
        content: Text('¿Estás seguro de eliminar "${file['name']}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancelar'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _deleteFile(file['fullPath']);
            },
            child: Text('Eliminar', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Mis Archivos', style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
        actions: [
          IconButton(
            icon: Icon(Icons.refresh),
            tooltip: 'Actualizar',
            onPressed: _fetchFiles,
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Cargando archivos...'),
          ],
        ),
      );
    }
    
    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, color: Colors.red, size: 48),
              SizedBox(height: 16),
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.red),
              ),
              SizedBox(height: 16),
              ElevatedButton(
                onPressed: _fetchFiles,
                child: Text('Reintentar'),
              ),
            ],
          ),
        ),
      );
    }
    
    if (_files.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.folder_open, size: 64, color: Colors.grey[400]),
            SizedBox(height: 16),
            Text(
              'No hay archivos disponibles',
              style: TextStyle(fontSize: 18, color: Colors.grey[600]),
            ),
            SizedBox(height: 8),
            Text(
              'Sube archivos para verlos aquí',
              style: TextStyle(color: Colors.grey[500]),
            ),
          ],
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWideScreen = constraints.maxWidth > 600;
        
        return isWideScreen ? _buildWideLayout() : _buildMobileLayout();
      },
    );
  }

  Widget _buildMobileLayout() {
    return ListView.builder(
      padding: EdgeInsets.all(8),
      itemCount: _files.length,
      itemBuilder: (context, index) {
        final file = _files[index];
        return Card(
          elevation: 2,
          margin: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => _showFileActions(context, file),
            child: Padding(
              padding: const EdgeInsets.all(12.0),
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
                  Icon(Icons.more_vert, color: Colors.grey),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildWideLayout() {
    return GridView.builder(
      padding: EdgeInsets.all(16),
      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 300,
        childAspectRatio: 3,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
      ),
      itemCount: _files.length,
      itemBuilder: (context, index) {
        final file = _files[index];
        return Card(
          elevation: 3,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => _showFileActions(context, file),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                children: [
                  Container(
                    padding: EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Theme.of(context).primaryColor.withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: _getFileIcon(file['type']),
                  ),
                  SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
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
                  PopupMenuButton(
                    icon: Icon(Icons.more_vert),
                    itemBuilder: (context) => [
                      PopupMenuItem(
                        child: Text('Abrir'),
                        onTap: () => _openFile(file),
                      ),
                      if (file['isEditable'] ?? false) PopupMenuItem(
                        child: Text('Editar'),
                        onTap: () => _editFile(context, file),
                      ),
                      PopupMenuItem(
                        child: Text('Eliminar', style: TextStyle(color: Colors.red)),
                        onTap: () => _confirmDelete(context, file),
                      ),
                    ],
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
    final iconSize = 24.0;
    final color = Theme.of(context).primaryColor;
    
    switch (fileType) {
      case 'txt': return Icon(Icons.text_snippet, size: iconSize, color: Colors.blue);
      case 'doc':
      case 'docx': return Icon(Icons.description, size: iconSize, color: Colors.blue);
      case 'pdf': return Icon(Icons.picture_as_pdf, size: iconSize, color: Colors.red);
      case 'jpg':
      case 'jpeg':
      case 'png': return Icon(Icons.image, size: iconSize, color: Colors.green);
      default: return Icon(Icons.insert_drive_file, size: iconSize, color: color);
    }
  }
}