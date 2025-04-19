import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:typed_data';

class TextEditorScreen extends StatefulWidget {
  final String? initialText;
  final String? filePath;
  final String? fileName;

  const TextEditorScreen({
    Key? key,
    this.initialText,
    this.filePath,
    this.fileName,
  }) : super(key: key);

  @override
  _TextEditorScreenState createState() => _TextEditorScreenState();
}

class _TextEditorScreenState extends State<TextEditorScreen> {
  final SupabaseClient _supabase = Supabase.instance.client;
  final TextEditingController _textController = TextEditingController();
  final FocusNode _textFocusNode = FocusNode();
  bool _isSaving = false;
  late String _fileName;
  bool _showFileName = false;

  @override
  void initState() {
    super.initState();
    _fileName = widget.fileName ?? 'documento_${DateTime.now().millisecondsSinceEpoch}.txt';
    if (widget.initialText != null) {
      _textController.text = widget.initialText!;
    } else if (widget.filePath != null) {
      _loadExistingFile();
    }
  }

  Future<void> _loadExistingFile() async {
    try {
      final fileData = await _supabase.storage
          .from('useruploads')
          .download(widget.filePath!);
      
      setState(() {
        _textController.text = String.fromCharCodes(fileData);
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al cargar el archivo: ${e.toString()}'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _saveFile() async {
    if (_textController.text.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('El texto no puede estar vacío'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }

    try {
      setState(() => _isSaving = true);

      final user = _supabase.auth.currentUser;
      if (user == null) throw Exception('Debes iniciar sesión primero');

      final Uint8List bytes = Uint8List.fromList(_textController.text.codeUnits);

      if (widget.filePath != null) {
        // Actualizar archivo existente
        await _supabase.storage.from('useruploads').updateBinary(
          widget.filePath!,
          bytes,
          fileOptions: FileOptions(contentType: 'text/plain'),
        );
      } else {
        // Crear nuevo archivo
        final userFolder = 
            user.email?.split('@').first ?? 'user_${user.id.substring(0, 6)}';
        final storagePath = 'usuarios/$userFolder/textos/$_fileName';

        await _supabase.storage.from('useruploads').uploadBinary(
          storagePath,
          bytes,
          fileOptions: FileOptions(contentType: 'text/plain', upsert: true),
        );
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(Icons.check_circle, color: Colors.white),
                SizedBox(width: 8),
                Text('Documento guardado como $_fileName'),
              ],
            ),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Colors.green,
          ),
        );
      }
      
      // Regresar a la pantalla anterior después de guardar
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
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
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Future<void> _showFileNameDialog() async {
    final newName = await showDialog<String>(
      context: context,
      builder: (context) {
        final controller = TextEditingController(text: _fileName.replaceFirst('.txt', ''));
        return AlertDialog(
          title: Text('Nombre del archivo', style: TextStyle(fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: controller,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: 'Ingrese el nombre del archivo',
                  suffixText: '.txt',
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                ),
                onChanged: (value) => _fileName = value.endsWith('.txt') 
                    ? value 
                    : '$value.txt',
              ),
              SizedBox(height: 8),
              Text(
                'El archivo se guardará con extensión .txt',
                style: TextStyle(color: Colors.grey, fontSize: 12),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('CANCELAR'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, _fileName),
              child: Text('GUARDAR'),
            ),
          ],
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        );
      },
    );

    if (newName != null && newName.isNotEmpty) {
      setState(() => _fileName = newName);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isWideScreen = MediaQuery.of(context).size.width > 600;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.filePath != null ? 'Editar Documento' : 'Nuevo Documento',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: !isWideScreen,
        actions: [
          if (isWideScreen) _buildSaveButton(),
          if (widget.filePath == null && isWideScreen)
            IconButton(
              icon: Icon(Icons.edit_note),
              onPressed: _showFileNameDialog,
              tooltip: 'Cambiar nombre',
            ),
        ],
      ),
      floatingActionButton: !isWideScreen ? FloatingActionButton(
        onPressed: _isSaving ? null : _saveFile,
        child: _isSaving 
            ? CircularProgressIndicator(color: Colors.white)
            : Icon(Icons.save),
        tooltip: 'Guardar documento',
      ) : null,
      body: Column(
        children: [
          if (_isSaving) LinearProgressIndicator(minHeight: 2),
          Expanded(
            child: Padding(
              padding: isWideScreen 
                  ? EdgeInsets.symmetric(horizontal: 32, vertical: 16)
                  : EdgeInsets.all(16),
              child: Container(
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: EdgeInsets.all(16),
                child: TextField(
                  controller: _textController,
                  focusNode: _textFocusNode,
                  maxLines: null,
                  expands: true,
                  keyboardType: TextInputType.multiline,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    hintText: 'Escribe tu texto aquí...',
                    border: InputBorder.none,
                    hintStyle: TextStyle(color: Colors.grey),
                  ),
                  style: TextStyle(fontSize: 16, height: 1.5),
                ),
              ),
            ),
          ),
          if (!isWideScreen || _showFileName) _buildFileNameSection(isWideScreen),
        ],
      ),
      bottomNavigationBar: isWideScreen ? null : _buildBottomBar(),
    );
  }

  Widget _buildSaveButton() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8.0),
      child: ElevatedButton.icon(
        onPressed: _isSaving ? null : _saveFile,
        icon: _isSaving 
            ? SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              )
            : Icon(Icons.save, size: 20),
        label: Text('GUARDAR'),
        style: ElevatedButton.styleFrom(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
      ),
    );
  }

  Widget _buildFileNameSection(bool isWideScreen) {
    return Padding(
      padding: isWideScreen 
          ? EdgeInsets.all(16)
          : EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          if (isWideScreen) ...[
            Text(
              'Guardar como: ',
              style: TextStyle(color: Colors.grey, fontSize: 14),
            ),
            SizedBox(width: 8),
          ],
          Expanded(
            child: InkWell(
              onTap: widget.filePath == null ? () {
                if (isWideScreen) {
                  _showFileNameDialog();
                } else {
                  setState(() => _showFileName = true);
                }
              } : null,
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: widget.filePath == null
                      ? Theme.of(context).colorScheme.surfaceVariant
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.insert_drive_file, size: 20, color: Colors.grey),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _fileName,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurface,
                          decoration: widget.filePath == null 
                              ? TextDecoration.underline 
                              : null,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (widget.filePath == null && !isWideScreen && _showFileName)
                      IconButton(
                        icon: Icon(Icons.edit, size: 20),
                        onPressed: _showFileNameDialog,
                        padding: EdgeInsets.zero,
                        constraints: BoxConstraints(),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomBar() {
    return BottomAppBar(
      padding: EdgeInsets.symmetric(horizontal: 16),
      height: 56,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            icon: Icon(Icons.keyboard),
            onPressed: () {
              _textFocusNode.requestFocus();
            },
            tooltip: 'Mostrar teclado',
          ),
          if (widget.filePath == null) IconButton(
            icon: Icon(Icons.edit_note),
            onPressed: _showFileNameDialog,
            tooltip: 'Cambiar nombre',
          ),
          IconButton(
            icon: Icon(Icons.format_size),
            onPressed: () {
              // Podrías implementar un diálogo para cambiar el tamaño de fuente
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Ajustes de formato en desarrollo'),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            },
            tooltip: 'Formato',
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _textController.dispose();
    _textFocusNode.dispose();
    super.dispose();
  }
}