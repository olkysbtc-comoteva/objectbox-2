import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'dart:async';
import 'package:nowa_runtime/nowa_runtime.dart';
import 'package:comoteva/integrations/supabase_service.dart';
import 'package:comoteva/app_theme.dart';
import 'package:go_router/go_router.dart';
import 'package:comoteva/models/user_profile.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:comoteva/components/apple_button.dart';
import 'package:image_picker/image_picker.dart' as picker_lib;

@NowaGenerated()
class ProfileScreen extends StatefulWidget {
  @NowaGenerated({'loader': 'auto-constructor'})
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() {
    return _ProfileScreenState();
  }
}

@NowaGenerated()
class _ProfileScreenState extends State<ProfileScreen> {
  bool _isScanning = false;
  String? _dynamicToken;
  Timer? _refreshTimer;
  bool _isLoadingToken = false;
  bool _isUploading = false;

  @override
  void initState() {
    super.initState();
    _startTokenRotation();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _startTokenRotation() async {
    await _refreshToken();
    _refreshTimer = Timer.periodic(const Duration(seconds: 120), (timer) async {
      await _refreshToken();
    });
  }

  Future<void> _refreshToken() async {
    if (!mounted) {
      return;
    }
    setState(() => _isLoadingToken = true);
    try {
      final token = await SupabaseService().generateDynamicToken();
      if (mounted) {
        setState(() {
          _dynamicToken = token;
          _isLoadingToken = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingToken = false);
      }
    }
  }
  
  
    void _showErrorModal(String message) {
    final theme = Theme.of(context);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: theme.colorScheme.surface,
        shape: const RoundedRectangleBorder(
          borderRadius: AppTheme.squircleRadius,
        ),
        title: const Text('Error', style: TextStyle(color: AppTheme.appleRed)),
        content: Text(message, style: TextStyle(color: theme.colorScheme.onSurface)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              'OK',
              style: TextStyle(color: AppTheme.appleBlue),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickAndUploadAvatar() async {
    final picker = picker_lib.ImagePicker();
    final picker_lib.XFile? image = await picker.pickImage(
      source: picker_lib.ImageSource.gallery,
      maxWidth: 512,
      maxHeight: 512,
      imageQuality: 75,
    );
    if (image != null) {
      setState(() => _isUploading = true);
      try {
        final bytes = await image.readAsBytes();
        await SupabaseService().updateAvatar(bytes, image.name);
        if (mounted) {
          setState(() => _isUploading = false);
        }
      } catch (e) {
        if (mounted) {
          setState(() => _isUploading = false);
          _showErrorModal('Error al subir la imagen: $e');
        }
      }
    }
  }

  void _confirmSignOut() {
    final theme = Theme.of(context);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: theme.colorScheme.surface,
        shape: const RoundedRectangleBorder(
          borderRadius: AppTheme.squircleRadius,
        ),
        title: Text('Cerrar Sesión', style: TextStyle(color: theme.colorScheme.onSurface)),
        content: Text('¿Estás seguro de que quieres salir?', style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.8))),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancelar', style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.6))),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await SupabaseService().signOut();
              if (mounted) {
                context.go('/auth');
              }
            },
            child: const Text(
              'Salir',
              style: TextStyle(color: AppTheme.appleRed),
            ),
          ),
        ],
      ),
    );
  }

  Future<void>? _showAppInfo() async {
    final config = await SupabaseService().getAppConfig();
    if (!mounted) {
      return;
    }
    final theme = Theme.of(context);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: theme.colorScheme.surface,
        shape: const RoundedRectangleBorder(
          borderRadius: AppTheme.squircleRadius,
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (config?.logo != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Image.network(config!.logo!, height: 80),
              ),
            Text(
              config?.appName ?? 'Mi App',
              style: TextStyle(
                color: theme.colorScheme.onSurface,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Versión ${config?.version ?? '1.0.0'}',
              style: const TextStyle(color: AppTheme.secondaryText),
            ),
            const Divider(color: Colors.white24, height: 24),
            if (config?.email != null)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.email, color: AppTheme.appleBlue),
                title: Text(
                  config!.email!,
                  style: TextStyle(color: theme.colorScheme.onSurface, fontSize: 14),
                ),
              ),
            if (config?.website != null)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.language, color: AppTheme.appleBlue),
                title: Text(
                  config!.website!,
                  style: TextStyle(color: theme.colorScheme.onSurface, fontSize: 14),
                ),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cerrar', style: TextStyle(color: theme.colorScheme.primary)),
          ),
        ],
      ),
    );
  }
  
  
    @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Perfil'),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline, color: AppTheme.appleBlue),
            onPressed: _showAppInfo,
          ),
          IconButton(
            icon: Icon(Icons.logout, color: theme.colorScheme.onSurface),
            onPressed: _confirmSignOut,
          ),
        ],
      ),
      body: FutureBuilder<UserProfile?>(
        future: SupabaseService().getMyProfile(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              !_isUploading) {
            return const Center(child: CircularProgressIndicator());
          }
          final profile = snapshot.data;
          if (profile == null) {
            return const Center(child: Text('Perfil no encontrado'));
          }
          return SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                GestureDetector(
                  onTap: _isUploading ? null : _pickAndUploadAvatar,
                  child: Stack(
                    children: [
                      CircleAvatar(
                        radius: 50,
                        backgroundColor: theme.colorScheme.surfaceContainerHighest,
                        backgroundImage: profile.avatarUrl != null
                            ? NetworkImage(profile.avatarUrl!)
                            : null,
                        child: profile.avatarUrl == null && !_isUploading
                            ? Icon(
                                Icons.person,
                                size: 50,
                                color: theme.colorScheme.onSurface.withOpacity(0.6),
                              )
                            : null,
                      ),
                      if (_isUploading)
                        const Positioned.fill(
                          child: CircularProgressIndicator(
                            color: AppTheme.appleBlue,
                          ),
                        ),
                      Positioned(
                        bottom: 0,
                        right: 0,
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: const BoxDecoration(
                            color: AppTheme.appleBlue,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.camera_alt,
                            size: 20,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                
                
                                const SizedBox(height: 16),
                Text(
                  profile.displayName ?? 'Sin Nombre',
                  style: theme.textTheme.headlineMedium?.copyWith(
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 32),
                if (_isScanning)
                  Column(
                    children: [
                      SizedBox(
                        height: 300,
                        child: ClipRRect(
                          borderRadius: AppTheme.squircleRadius,
                          child: MobileScanner(
                            onDetect: (capture) async {
                              final List<Barcode> barcodes = capture.barcodes;
                              if (barcodes.isNotEmpty) {
                                final String? rawValue = barcodes.first.rawValue;
                                if (rawValue != null) {
                                  setState(() => _isScanning = false);
                                  try {
                                    final room = await SupabaseService()
                                        .startChatWithDynamicToken(rawValue);
                                    if (room != null && mounted) {
                                      context.push('/chat/${room.supabaseId}', extra: room);
                                    }
                                  } catch (e) {
                                    if (mounted) {
                                      _showErrorModal(
                                        e.toString().replaceAll('Exception: ', ''),
                                      );
                                    }
                                  }
                                }
                              }
                            },
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextButton.icon(
                        icon: const Icon(
                          Icons.image,
                          color: AppTheme.appleBlue,
                        ),
                        label: const Text(
                          'Cargar imagen',
                          style: TextStyle(color: AppTheme.appleBlue),
                        ),
                        onPressed: () async {
                          final picker = picker_lib.ImagePicker();
                          final image = await picker.pickImage(
                            source: picker_lib.ImageSource.gallery,
                          );
                          if (image != null && mounted) {
                            setState(() => _isScanning = false);
                            try {
                              final controller = MobileScannerController();
                              final BarcodeCapture? capture = await controller.analyzeImage(image.path);
                              
                              if (capture != null && capture.barcodes.isNotEmpty) {
                                final String? rawValue = capture.barcodes.first.rawValue;
                                if (rawValue != null && mounted) {
                                  final room = await SupabaseService()
                                      .startChatWithDynamicToken(rawValue);
                                  if (room != null && mounted) {
                                    context.push('/chat/${room.supabaseId}', extra: room);
                                  }
                                }
                              } else {
                                if (mounted) _showErrorModal('No se encontró ningún código QR en la imagen.');
                              }
                            } catch (e) {
                              if (mounted) {
                                _showErrorModal(
                                  e.toString().replaceAll('Exception: ', ''),
                                );
                              }
                            }
                          }
                        },
                      ),
                    ],
                  )
                else
                  Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white, 
                          borderRadius: BorderRadius.circular(24),
                        ),
                        child: _isLoadingToken || _dynamicToken == null
                            ? const SizedBox(
                                width: 200,
                                height: 200,
                                child: Center(
                                  child: CircularProgressIndicator(
                                    color: Colors.black,
                                  ),
                                ),
                              )
                            : QrImageView(
                                data: _dynamicToken!,
                                version: QrVersions.auto,
                                size: 200,
                                gapless: false,
                                embeddedImageStyle: const QrEmbeddedImageStyle(
                                  size: Size(40, 40),
                                ),
                              ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.sync,
                            size: 16,
                            color: theme.colorScheme.onSurface.withOpacity(0.6),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Codigo dinamico (120s)',
                            style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.6)),
                          ),
                        ],
                      ),
                    ],
                  ),
                const SizedBox(height: 40),
                AppleButton(
                  text: _isScanning ? 'Cancelar Escaneo' : 'Escanear Codigo QR',
                  onPressed: () => setState(() => _isScanning = !_isScanning),
                  color: _isScanning
                      ? theme.colorScheme.surfaceContainerHighest
                      : AppTheme.appleBlue,
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

  