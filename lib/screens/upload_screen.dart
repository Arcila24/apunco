import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:file_picker/file_picker.dart';
import 'package:mime/mime.dart';
import 'package:path/path.dart' as path;
import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'login_screen.dart';
import 'text_editor_screen.dart';
import 'my_files_screen.dart';

class UploadScreen extends StatefulWidget {
  @override
  _UploadScreenState createState() => _UploadScreenState();
}

class _UploadScreenState extends State<UploadScreen> {
  final SupabaseClient _supabase = Supabase.instance.client;
  int _selectedIndex = 0;
  bool _isUploading = false;
  double _uploadProgress = 0;

  static const List<Map<String, dynamic>> _menuOptions = [
    {'icon': Icons.cloud_upload, 'title': 'Subir Archivo'},
    {'icon': Icons.note_add, 'title': 'Crear Texto'},
    {'icon': Icons.folder, 'title': 'Mis Archivos'},
  ];

  Future<void> _uploadFile() async {
    try {
      setState(() {
        _isUploading = true;
        _uploadProgress = 0;
      });

      final user = _supabase.auth.currentUser;
      if (user == null) throw Exception('Debes iniciar sesión primero');

      final result = await FilePicker.platform.pickFiles(
        allowMultiple: false,
        type: FileType.custom,
        allowedExtensions: ['jpg', 'jpeg', 'png', 'pdf', 'txt', 'doc', 'docx'],
      );

      if (result == null || result.files.isEmpty) {
        setState(() => _isUploading = false);
        return;
      }

      final file = result.files.first;
      final filePath = file.path!;
      final fileExtension = path.extension(filePath).replaceAll('.', '').toLowerCase();
      final mimeType = lookupMimeType(filePath) ?? 'application/octet-stream';

      final userFolder = user.email?.split('@').first ?? 'user_${user.id.substring(0, 6)}';
      
      String typeFolder;
      if (fileExtension == 'txt' || fileExtension == 'doc' || fileExtension == 'docx') {
        typeFolder = 'documents';
      } else if (fileExtension == 'jpg' || fileExtension == 'jpeg' || fileExtension == 'png') {
        typeFolder = 'images';
      } else if (fileExtension == 'pdf') {
        typeFolder = 'pdfs';
      } else {
        typeFolder = 'others';
      }

      final storagePath = 'usuarios/$userFolder/$typeFolder/${DateTime.now().millisecondsSinceEpoch}.$fileExtension';

      final fileBytes = await File(filePath).readAsBytes();
      
      await _supabase.storage.from('useruploads').uploadBinary(
            storagePath,
            fileBytes,
            fileOptions: FileOptions(contentType: mimeType),
          );

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(Icons.check_circle, color: Colors.white),
              SizedBox(width: 8),
              Text('Archivo subido exitosamente a $typeFolder'),
            ],
          ),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(Icons.error_outline, color: Colors.white),
              SizedBox(width: 8),
              Text('Error: ${e.toString()}'),
            ],
          ),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isUploading = false);
      }
    }
  }

  Future<void> _downloadAndOpenFile(String filePath) async {
    try {
      final response = await _supabase.storage
          .from('useruploads')
          .download(filePath);

      final tempDir = await getTemporaryDirectory();
      final tempFile = File('${tempDir.path}/${path.basename(filePath)}');
      await tempFile.writeAsBytes(response);

      await OpenFile.open(tempFile.path);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al abrir el archivo: ${e.toString()}'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _navigateToTextEditor() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => TextEditorScreen(),
      ),
    );
  }

  Future<void> _logout() async {
    await _supabase.auth.signOut();
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => LoginScreen()),
      (route) => false,
    );
  }

  Widget _buildCurrentScreen() {
    final isWideScreen = MediaQuery.of(context).size.width > 600;

    switch (_selectedIndex) {
      case 0:
        return Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: 600),
            child: Card(
              margin: EdgeInsets.all(16),
              elevation: 4,
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_isUploading) ...[
                      CircularProgressIndicator(
                        value: _uploadProgress / 100,
                        strokeWidth: 6,
                      ),
                      SizedBox(height: 24),
                      Text(
                        'Subiendo archivo...',
                        style: Theme.of(context).textTheme.titleLarge, // Cambiado de headline6
                      ),
                      SizedBox(height: 8),
                      Text(
                        '${_uploadProgress.toStringAsFixed(1)}% completado',
                        style: TextStyle(color: Colors.grey),
                      ),
                    ] else ...[
                      Icon(
                        Icons.cloud_upload,
                        size: 64,
                        color: Theme.of(context).primaryColor,
                      ),
                      SizedBox(height: 24),
                      Text(
                        'Subir Archivo',
                        style: Theme.of(context).textTheme.headlineSmall, // Cambiado de headline5
                      ),
                      SizedBox(height: 16),
                      Text(
                        'Selecciona un archivo para subir a tu almacenamiento',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey),
                      ),
                      SizedBox(height: 32),
                      ElevatedButton.icon(
                        onPressed: _uploadFile,
                        icon: Icon(Icons.upload_file),
                        label: Text('SELECCIONAR ARCHIVO'),
                        style: ElevatedButton.styleFrom(
                          padding: EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      case 1:
        return Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: 600),
            child: Card(
              margin: EdgeInsets.all(16),
              elevation: 4,
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.note_add,
                      size: 64,
                      color: Theme.of(context).primaryColor,
                    ),
                    SizedBox(height: 24),
                    Text(
                      'Crear Nuevo Documento',
                      style: Theme.of(context).textTheme.headlineSmall, // Cambiado de headline5
                    ),
                    SizedBox(height: 16),
                    Text(
                      'Crea y edita documentos de texto directamente en la app',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey),
                    ),
                    SizedBox(height: 32),
                    ElevatedButton.icon(
                      onPressed: _navigateToTextEditor,
                      icon: Icon(Icons.edit),
                      label: Text('CREAR DOCUMENTO'),
                      style: ElevatedButton.styleFrom(
                        padding: EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      case 2:
        return MyFilesScreen(onFileTap: _downloadAndOpenFile);
      default:
        return Center(child: Text('Pantalla no implementada'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final isWideScreen = MediaQuery.of(context).size.width > 600;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _menuOptions[_selectedIndex]['title'],
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: !isWideScreen,
        actions: [
          if (isWideScreen) ...[
            ..._menuOptions.asMap().entries.map((entry) {
              final index = entry.key;
              final option = entry.value;
              return IconButton(
                icon: Icon(option['icon']),
                tooltip: option['title'],
                onPressed: () => setState(() => _selectedIndex = index),
              );
            }).toList(),
            SizedBox(width: 8),
          ],
          IconButton(
            icon: Icon(Icons.logout),
            tooltip: 'Cerrar sesión',
            onPressed: _logout,
          ),
        ],
      ),
      drawer: !isWideScreen ? Drawer(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            UserAccountsDrawerHeader(
              accountName: Text(_supabase.auth.currentUser?.email ?? 'Usuario'),
              accountEmail: null,
              currentAccountPicture: CircleAvatar(
                child: Icon(Icons.person),
              ),
              decoration: BoxDecoration(
                color: Theme.of(context).primaryColor,
              ),
            ),
            ..._menuOptions.asMap().entries.map((entry) {
              final index = entry.key;
              final option = entry.value;
              return ListTile(
                leading: Icon(option['icon']),
                title: Text(option['title']),
                selected: _selectedIndex == index,
                onTap: () {
                  setState(() => _selectedIndex = index);
                  Navigator.pop(context);
                },
              );
            }).toList(),
            Divider(),
            ListTile(
              leading: Icon(Icons.logout),
              title: Text('Cerrar Sesión'),
              onTap: _logout,
            ),
          ],
        ),
      ) : null,
      body: _buildCurrentScreen(),
      bottomNavigationBar: !isWideScreen ? BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: (index) => setState(() => _selectedIndex = index),
        items: _menuOptions.map((option) => BottomNavigationBarItem(
          icon: Icon(option['icon']),
          label: option['title'],
        )).toList(),
      ) : null,
    );
  }
}