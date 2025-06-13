import 'dart:io';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:file_picker/file_picker.dart';
import 'package:mime/mime.dart';
import 'package:path/path.dart' as path;
import 'login_screen.dart';
import 'text_editor_screen.dart';
import 'my_files_screen.dart';
import 'explore_screen.dart';
import 'user_screen.dart'; // Nuevo

class UploadScreen extends StatefulWidget {
  const UploadScreen({Key? key}) : super(key: key);

  @override
  _UploadScreenState createState() => _UploadScreenState();
}

class _UploadScreenState extends State<UploadScreen> {
  final SupabaseClient _supabase = Supabase.instance.client;
  final TextEditingController _fileNameController = TextEditingController();
  final double _compactScreenThreshold = 350;
  bool get _isVerySmallScreen => 
      MediaQuery.of(context).size.width < _compactScreenThreshold;
  int _selectedIndex = 0;
  bool _isUploading = false;
  PlatformFile? _selectedFile;
  bool _isAdmin = false;
  bool _isCheckingAdmin = false;

  // Menú base (usuarios normales)
  static const List<Map<String, dynamic>> _baseMenuOptions = [
    {'icon': Icons.cloud_upload, 'title': 'Subir Archivo'},
    {'icon': Icons.note_add, 'title': 'Crear Texto'},
    {'icon': Icons.folder, 'title': 'Mis Archivos'},
    {'icon': Icons.explore, 'title': 'Explorar'},
  ];

  // Menú para admins
  static const List<Map<String, dynamic>> _adminMenuOptions = [
    {'icon': Icons.explore, 'title': 'Explorar'},
    {'icon': Icons.people, 'title': 'Usuarios'},
  ];

  List<Map<String, dynamic>> get _filteredMenuOptions => 
      _isAdmin ? _adminMenuOptions : _baseMenuOptions;

  @override
  void initState() {
    super.initState();
    _checkAdminStatus();
  }

  Future<void> _checkAdminStatus() async {
    setState(() => _isCheckingAdmin = true);
    final user = _supabase.auth.currentUser;
    if (user == null) {
      if (mounted) setState(() => _isAdmin = false);
      return;
    }

    final response = await _supabase
        .from('user_profiles')
        .select('role, is_active')
        .eq('id', user.id)
        .maybeSingle();

    if (mounted) {
      setState(() {
        _isAdmin = response != null && 
                  response['role'] == 'admin' && 
                  (response['is_active'] ?? true);
        _isCheckingAdmin = false;
        _selectedIndex = 0; // Resetear índice al cambiar rol
      });
    }
  }

  Future<void> _selectFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: false,
        type: FileType.custom,
        allowedExtensions: [
          'jpg', 'jpeg', 'png', 'pdf', 'txt',
          'doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx'
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

    final extension = path.extension(_selectedFile!.name).replaceAll('.', '');
    final newName = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Nombre del archivo'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _fileNameController,
              autofocus: true,
              decoration: InputDecoration(
                hintText: 'Ingrese el nombre',
                suffixText: '.$extension',
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Tamaño: ${(_selectedFile!.size / 1024).toStringAsFixed(2)} KB',
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
      ),
    );

    if (newName != null && newName.isNotEmpty) await _uploadFile();
  }

  Future<void> _uploadFile() async {
    if (_selectedFile == null) return;

    try {
      setState(() => _isUploading = true);
      final user = _supabase.auth.currentUser;
      if (user == null) throw Exception('Debes iniciar sesión');

      final extension = path.extension(_selectedFile!.name).replaceAll('.', '');
      final fileName = _fileNameController.text.trim().isEmpty
          ? _selectedFile!.name
          : '${_fileNameController.text}.$extension';

      final mimeType = 
          lookupMimeType(_selectedFile!.name) ?? 'application/octet-stream';
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

      _showSuccessSnackbar('¡Archivo subido!');
      _resetFileSelection();
    } catch (e) {
      _showErrorSnackbar('Error: ${e.toString()}');
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  String _getTypeFolder(String extension) {
    switch (extension.toLowerCase()) {
      case 'txt': case 'doc': case 'docx': return 'documentos';
      case 'jpg': case 'jpeg': case 'png': return 'imagenes';
      case 'pdf': return 'pdfs';
      case 'xls': case 'xlsx': return 'hojas_calculo';
      case 'ppt': case 'pptx': return 'presentaciones';
      default: return 'otros';
    }
  }

  Widget _buildCurrentScreen() {
    if (_isCheckingAdmin) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_isAdmin) {
      switch (_selectedIndex) {
        case 0: return const ExploreScreen();
        case 1: return const UserScreen(); // Nueva pantalla
        default: return const ExploreScreen();
      }
    } else {
      switch (_selectedIndex) {
        case 0: return _buildUploadScreen();
        case 1: return _buildTextEditorScreen();
        case 2: return const MyFilesScreen();
        case 3: return const ExploreScreen();
        default: return _buildUploadScreen();
      }
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
          const SizedBox(height: 24),
          if (_selectedFile != null) ...[
            const Text('Archivo seleccionado:', 
                style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(_selectedFile!.name, style: TextStyle(color: Colors.grey[600])),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ElevatedButton(
                  onPressed: _resetFileSelection,
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.grey[400]),
                  child: const Text('CANCELAR'),
                ),
                const SizedBox(width: 16),
                ElevatedButton(
                  onPressed: _uploadFile,
                  child: const Text('SUBIR AHORA'),
                ),
              ],
            ),
          ] else ...[
            ElevatedButton(
              onPressed: _selectFile,
              child: const Text('SELECCIONAR ARCHIVO'),
            ),
          ],
          if (_isUploading) ...[
            const SizedBox(height: 24),
            const CircularProgressIndicator(),
            const SizedBox(height: 8),
            const Text('Subiendo archivo...'),
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
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: () => Navigator.push(
              context, 
              MaterialPageRoute(builder: (_) => const TextEditorScreen()),
            ),
            child: const Text('CREAR DOCUMENTO'),
          ),
        ],
      ),
    );
  }

  Future<void> _logout() async {
    await _supabase.auth.signOut();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  void _showErrorSnackbar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  void _showSuccessSnackbar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.green),
    );
  }

  Widget _buildDrawer() {
    return Drawer(
      child: ListView(
        children: [
          UserAccountsDrawerHeader(
            accountName: Text(_supabase.auth.currentUser?.email ?? 'Usuario'),
            accountEmail: Text(
              _isAdmin ? 'Administrador' : 'Usuario normal',
              style: TextStyle(
                color: _isAdmin ? Colors.amber : Colors.grey[300],
                fontWeight: FontWeight.bold,
              ),
            ),
            currentAccountPicture: CircleAvatar(
              backgroundColor: _isAdmin ? Colors.amber : Colors.blue,
              child: Icon(
                _isAdmin ? Icons.admin_panel_settings : Icons.person,
                color: Colors.white,
              ),
            ),
            decoration: BoxDecoration(
              color: _isAdmin ? Colors.blue[900] : Colors.blue,
            ),
          ),
          ..._filteredMenuOptions.asMap().entries.map((entry) => ListTile(
            leading: Icon(entry.value['icon']),
            title: Text(entry.value['title']),
            selected: _selectedIndex == entry.key,
            onTap: () {
              setState(() => _selectedIndex = entry.key);
              Navigator.pop(context);
            },
          )),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.logout),
            title: const Text('Cerrar Sesión'),
            onTap: _logout,
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
        title: Text(_filteredMenuOptions[_selectedIndex]['title']),
        actions: [
          if (isWideScreen) ...[
            ..._filteredMenuOptions.asMap().entries.map((entry) => IconButton(
              icon: Icon(entry.value['icon']),
              onPressed: () => setState(() => _selectedIndex = entry.key),
            )),
            IconButton(
              icon: const Icon(Icons.logout),
              onPressed: _logout,
            ),
          ],
        ],
      ),
      drawer: !isWideScreen ? _buildDrawer() : null,
      body: _buildCurrentScreen(),
      bottomNavigationBar: !isWideScreen && !_isVerySmallScreen
          ? BottomNavigationBar(
              items: _filteredMenuOptions
                  .map((option) => BottomNavigationBarItem(
                        icon: Icon(option['icon']),
                        label: option['title'],
                      ))
                  .toList(),
              currentIndex: _selectedIndex,
              onTap: (index) => setState(() => _selectedIndex = index),
            )
          : null,
    );
  }

  void _resetFileSelection() {
    setState(() {
      _selectedFile = null;
      _fileNameController.clear();
    });
  }

  @override
  void dispose() {
    _fileNameController.dispose();
    super.dispose();
  }
}