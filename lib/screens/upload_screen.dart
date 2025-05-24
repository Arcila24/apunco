import 'dart:io';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:file_picker/file_picker.dart';
import 'package:mime/mime.dart';
import 'package:path/path.dart' as path;
import 'login_screen.dart';
import 'text_editor_screen.dart';
import 'my_files_screen.dart';

class UploadScreen extends StatefulWidget {
  @override
  _UploadScreenState createState() => _UploadScreenState();
}

class _UploadScreenState extends State<UploadScreen> {
  final SupabaseClient _supabase = Supabase.instance.client;
  final TextEditingController _fileNameController = TextEditingController();
  int _selectedIndex = 0;
  bool _isUploading = false;
  PlatformFile? _selectedFile;

  static const List<Map<String, dynamic>> _menuOptions = [
    {'icon': Icons.cloud_upload, 'title': 'Subir Archivo'},
    {'icon': Icons.note_add, 'title': 'Crear Texto'},
    {'icon': Icons.folder, 'title': 'Mis Archivos'},
  ];

  Future<void> _selectFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: false,
        type: FileType.custom,
        allowedExtensions: [
          'jpg',
          'jpeg',
          'png',
          'pdf',
          'txt',
          'doc',
          'docx',
          'xls',
          'xlsx',
          'ppt',
          'pptx'
        ],
      );

      if (result == null || result.files.isEmpty) return;

      setState(() {
        _selectedFile = result.files.first;
        _fileNameController.text = _selectedFile!.name.split('.').first;
      });

      await _showFileNameDialog();
    } catch (e) {
      _showErrorSnackbar('Error al seleccionar archivo: ${e.toString()}');
    }
  }

  Future<void> _showFileNameDialog() async {
    if (_selectedFile == null) return;

    final extension = path.extension(_selectedFile!.name!).replaceAll('.', '');
    final newName = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Nombre del archivo'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _fileNameController,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: 'Ingrese el nombre del archivo',
                  suffixText: '.$extension',
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Tamaño: ${(_selectedFile!.size! / 1024).toStringAsFixed(2)} KB',
                style: const TextStyle(color: Colors.grey),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('CANCELAR'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, _fileNameController.text),
              child: const Text('SUBIR'),
            ),
          ],
        );
      },
    );

    if (newName != null && newName.isNotEmpty) {
      await _uploadFile();
    }
  }

  Future<void> _uploadFile() async {
    if (_selectedFile == null) return;

    try {
      setState(() => _isUploading = true);
      final user = _supabase.auth.currentUser;
      if (user == null) throw Exception('Debes iniciar sesión primero');

      final extension =
          path.extension(_selectedFile!.name!).replaceAll('.', '');
      final fileName = _fileNameController.text.trim().isEmpty
          ? _selectedFile!.name!
          : '${_fileNameController.text}.$extension';

      final mimeType =
          lookupMimeType(_selectedFile!.name!) ?? 'application/octet-stream';
      final userFolder =
          user.email?.split('@').first ?? 'user_${user.id.substring(0, 6)}';
      final typeFolder = _getTypeFolder(extension);
      final storagePath = 'usuarios/$userFolder/$typeFolder/$fileName';

      final fileBytes = await File(_selectedFile!.path!).readAsBytes();

      await _supabase.storage.from('useruploads').uploadBinary(
            storagePath,
            fileBytes,
            fileOptions: FileOptions(contentType: mimeType, upsert: true),
          );

      _showSuccessSnackbar('Archivo subido exitosamente');
      _resetFileSelection();
    } catch (e) {
      _showErrorSnackbar('Error al subir archivo: ${e.toString()}');
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  void _resetFileSelection() {
    setState(() {
      _selectedFile = null;
      _fileNameController.clear();
    });
  }

  String _getTypeFolder(String extension) {
    switch (extension.toLowerCase()) {
      case 'txt':
      case 'doc':
      case 'docx':
        return 'documentos';
      case 'jpg':
      case 'jpeg':
      case 'png':
      case 'gif':
        return 'imagenes';
      case 'pdf':
        return 'pdfs';
      case 'xls':
      case 'xlsx':
        return 'hojas_calculo';
      case 'ppt':
      case 'pptx':
        return 'presentaciones';
      default:
        return 'otros';
    }
  }

  void _navigateToTextEditor() {
    Navigator.push(
        context, MaterialPageRoute(builder: (_) => TextEditorScreen()));
  }

  Future<void> _logout() async {
    await _supabase.auth.signOut();
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => LoginScreen()),
      (route) => false,
    );
  }

  void _showErrorSnackbar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
      ),
    );
  }

  void _showSuccessSnackbar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
      ),
    );
  }

  Widget _buildCurrentScreen() {
    switch (_selectedIndex) {
      case 0:
        return _buildUploadScreen();
      case 1:
        return _buildTextEditorScreen();
      case 2:
        return MyFilesScreen();
      default:
        return Center(child: Text('Pantalla no implementada'));
    }
  }

  Widget _buildUploadScreen() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            _selectedFile != null ? Icons.file_present : Icons.cloud_upload,
            size: 64,
            color: Theme.of(context).primaryColor,
          ),
          SizedBox(height: 24),
          if (_selectedFile != null) ...[
            Text(
              'Archivo seleccionado:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 8),
            Text(
              _selectedFile!.name!,
              style: TextStyle(color: Colors.grey[600]),
            ),
            SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ElevatedButton(
                  onPressed: _resetFileSelection,
                  child: Text('CANCELAR'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.grey[400],
                  ),
                ),
                SizedBox(width: 16),
                ElevatedButton(
                  onPressed: _uploadFile,
                  child: Text('SUBIR AHORA'),
                ),
              ],
            ),
          ] else ...[
            ElevatedButton(
              onPressed: _selectFile,
              child: Text('SELECCIONAR ARCHIVO'),
            ),
          ],
          if (_isUploading) ...[
            SizedBox(height: 24),
            CircularProgressIndicator(),
            SizedBox(height: 8),
            Text('Subiendo archivo...'),
          ],
        ],
      ),
    );
  }

  Widget _buildTextEditorScreen() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.note_add, size: 64, color: Theme.of(context).primaryColor),
          SizedBox(height: 24),
          ElevatedButton(
            onPressed: _navigateToTextEditor,
            child: Text('CREAR DOCUMENTO'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isWideScreen = MediaQuery.of(context).size.width > 600;

    return Scaffold(
      appBar: AppBar(
        title: Text(_menuOptions[_selectedIndex]['title']),
        actions: [
          if (isWideScreen) ...[
            ..._menuOptions.asMap().entries.map((entry) => IconButton(
                  icon: Icon(entry.value['icon']),
                  onPressed: () => setState(() => _selectedIndex = entry.key),
                )),
            IconButton(icon: Icon(Icons.logout), onPressed: _logout),
          ],
        ],
      ),
      drawer: !isWideScreen ? _buildDrawer() : null,
      body: _buildCurrentScreen(),
      bottomNavigationBar: !isWideScreen
          ? BottomNavigationBar(
              currentIndex: _selectedIndex,
              onTap: (index) => setState(() => _selectedIndex = index),
              items: _menuOptions
                  .map((option) => BottomNavigationBarItem(
                        icon: Icon(option['icon']),
                        label: option['title'],
                      ))
                  .toList(),
            )
          : null,
    );
  }

  Widget _buildDrawer() {
    return Drawer(
      child: ListView(
        children: [
          UserAccountsDrawerHeader(
            accountName: Text(_supabase.auth.currentUser?.email ?? 'Usuario'),
            accountEmail: Text(''),
            currentAccountPicture: CircleAvatar(child: Icon(Icons.person)),
          ),
          ..._menuOptions.asMap().entries.map((entry) => ListTile(
                leading: Icon(entry.value['icon']),
                title: Text(entry.value['title']),
                selected: _selectedIndex == entry.key,
                onTap: () {
                  setState(() => _selectedIndex = entry.key);
                  Navigator.pop(context);
                },
              )),
          Divider(),
          ListTile(
            leading: Icon(Icons.logout),
            title: Text('Cerrar Sesión'),
            onTap: _logout,
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _fileNameController.dispose();
    super.dispose();
  }
}
