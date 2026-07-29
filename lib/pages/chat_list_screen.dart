// chat_list_screen.dart
// Importa tu archivo main para que las pantallas reconozcan la variable global
import 'package:comoteva/main.dart';

import 'package:flutter/material.dart';
import 'package:nowa_runtime/nowa_runtime.dart';
import 'package:comoteva/globals/app_state.dart';
import 'package:comoteva/app_theme_mode.dart';
import 'package:comoteva/models/user_profile.dart';
import 'package:comoteva/integrations/supabase_service.dart';
import 'package:go_router/go_router.dart';
import 'package:comoteva/models/chat_room.dart';
import 'package:comoteva/app_theme.dart';
import 'package:intl/intl.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart'; // <--- NUEVA DEPENDENCIA: Añadido para la precarga

@NowaGenerated()
class ChatListScreen extends StatefulWidget {
  @NowaGenerated({'loader': 'auto-constructor'})
  const ChatListScreen({super.key});

  @override
  State<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends State<ChatListScreen> {
  Stream<List<ChatRoom>>? _roomsStream;
  late final Future<UserProfile?> _profileFuture;
  late final String? _currentUserId;
  // Conjunto para almacenar las URLs de las imágenes que ya se han intentado precargar.
  // Esto evita llamadas redundantes a precacheImage si el StreamBuilder se reconstruye.
  final Set<String> _precachedImageUrls = {};

  @override
  void initState() {
    super.initState();
    _inicializarStream();
    _profileFuture = SupabaseService().getMyProfile();
    _currentUserId = SupabaseService().currentUserId;
  }

  void _inicializarStream() {
    // La lógica de precarga se integrará dentro del StreamBuilder una vez que los datos estén disponibles.
    // Esto asegura que tengamos el BuildContext y los datos de las salas al día.
    _roomsStream = SupabaseService().getMyRoomsStream();
  }

  void _confirmarEliminacionChat(BuildContext context, ChatRoom room) {
    HapticFeedback.mediumImpact();
    final theme = Theme.of(context);
    final nombreContacto = room.otherUser.target?.displayName ?? 'este usuario'; // Acceso a ToOne

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: const [
            Icon(Icons.warning_amber_rounded, color: AppTheme.appleRed, size: 28),
            SizedBox(width: 10),
            Text('¿Eliminar chat?'),
          ],
        ),
        content: RichText(
          text: TextSpan(
            style: TextStyle(color: theme.colorScheme.onSurface, fontSize: 15, height: 1.4),
            children: [
              const TextSpan(text: '¿Estás seguro de que deseas eliminar la conversación con '),
              TextSpan(text: '$nombreContacto?\n\n', style: const TextStyle(fontWeight: FontWeight.bold)),
              const TextSpan(
                text: '⚠️ ADVERTENCIA: ',
                style: TextStyle(color: AppTheme.appleRed, fontWeight: FontWeight.bold),
              ),
              const TextSpan(
                text: 'Dado que los enlaces de invitación expiran, si eliminas este contacto ',
              ),
              const TextSpan(
                text: 'deberás escanear un nuevo código QR dinámico ',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const TextSpan(text: 'para poder volver a enviarle mensajes en el futuro.'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancelar', style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.6))),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.appleRed,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () async {
              Navigator.pop(context);
              // Llamar a la versión offline-first
              await SupabaseService().deleteRoom(room.supabaseId);
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Conversación marcada para eliminación.')),
              );
            },
            child: const Text('Eliminar de todos modos'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final appState = AppState.of(context);
    final theme = Theme.of(context);
    
    // 🔥 VALIDACIÓN INTEGRADA CON TU LOGO: Mantiene la estética de la imagen enviada
    if (objectbox == null) {
      return Scaffold(
        backgroundColor: const Color(0xFF070708), // El color de fondo negro/oscuro de tu app
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Contenedor cuadrado con tu logo del doble check
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: const Color(0xFF161522), // El tono morado/oscuro de fondo del logo
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.done_all, // Icono nativo de doble check estilo WhatsApp
                  color: Color(0xFF7A7893), // Color grisáceo del icono original
                  size: 40,
                ),
              ),
              const SizedBox(height: 24),
              // Indicador de carga sutil abajo con tus colores
              SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  valueColor: AlwaysStoppedAnimation<Color>(theme.colorScheme.primary),
                ),
              ),
            ],
          ),
        ),
      );
    }
    
    return Scaffold(
      body: RefreshIndicator(
        color: theme.colorScheme.primary,
        backgroundColor: theme.colorScheme.surface,
        onRefresh: () async {
          debugPrint('Forzando reinicialización manual del Stream de salas...');
          setState(() {
            _inicializarStream();
            _precachedImageUrls.clear(); // Limpiar el conjunto de URLs precargadas en el refresco
          });
          await Future.delayed(const Duration(milliseconds: 800));
        },
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics(),
          ),
          slivers: [
            SliverAppBar(
              expandedHeight: 120,
              floating: false,
              pinned: true,
              flexibleSpace: FlexibleSpaceBar(
                titlePadding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 16,
                ),
                title: Text(
                  'Mensajes',
                  style: theme.textTheme.headlineLarge?.copyWith(
                    fontSize: 28,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                centerTitle: false,
              ),
              actions: [
                PopupMenuButton<AppThemeMode>(
                  icon: Icon(Icons.more_vert, color: theme.colorScheme.onSurface),
                  onSelected: (mode) {
                    appState.setTheme(mode);
                  },
                  itemBuilder: (context) => <PopupMenuEntry<AppThemeMode>>[
                    const PopupMenuItem<AppThemeMode>(
                      value: AppThemeMode.light,
                      child: Text('Tema Claro'),
                    ),
                    const PopupMenuItem<AppThemeMode>(
                      value: AppThemeMode.amoled,
                      child: Text('Tema Oscuro AMOLED'),
                    ),
                    const PopupMenuItem<AppThemeMode>(
                      value: AppThemeMode.plus,
                      child: Text('Tema Plus'),
                    ),
                  ],
                ),
                FutureBuilder<UserProfile?>(
                  future: _profileFuture,
                  builder: (context, snapshot) {
                    final profile = snapshot.data;
                    return Padding(
                      padding: const EdgeInsets.only(right: 16),
                      child: GestureDetector(
                        onTap: () => context.push('/profile'),
                        child: CircleAvatar(
                          radius: 18,
                          backgroundColor: theme.colorScheme.surfaceContainerHighest,
                          backgroundImage: profile?.avatarUrl != null
                              ? NetworkImage(profile!.avatarUrl!)
                              : null,
                          child: profile?.avatarUrl == null
                              ? const Icon(
                                  Icons.person,
                                  size: 20,
                                  color: Colors.white,
                                )
                              : null,
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
            StreamBuilder<List<ChatRoom>>(
              stream: _roomsStream,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
                  return const SliverFillRemaining(
                    child: Center(child: CircularProgressIndicator()),
                  );
                }

                if (snapshot.hasError) {
                  return SliverFillRemaining(
                    child: Center(
                      child: Text(
                        'Error al cargar salas: ${snapshot.error}',
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                  );
                }

                final rooms = snapshot.data ?? [];

                // --- NUEVA LÓGICA: Pre-cargar imágenes de fondo ---
                // Solo precargamos si hay salas y el widget sigue montado.
                // Esto se ejecuta cada vez que el stream emite nuevos datos,
                // pero `_precachedImageUrls` evita precargas redundantes para la misma URL.
                if (rooms.isNotEmpty && mounted) {
                  _precacheChatBackgrounds(rooms, context);
                }
                // --- FIN NUEVA LÓGICA ---

                if (rooms.isEmpty) {
                  return SliverFillRemaining(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.chat_bubble_outline,
                          size: 64,
                          color: AppTheme.secondaryText,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No hay chats todavía',
                          style: theme.textTheme.bodyMedium,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Escanea un QR para empezar a hablar',
                          style: theme.textTheme.bodyMedium,
                        ),
                      ],
                    ),
                  );
                }

                return SliverList(
                  delegate: SliverChildBuilderDelegate((context, index) {
                    final room = rooms[index];
                    final otherUser = room.otherUser.target; // Acceso a ToOne
                    final lastMessage = room.lastMessage.target; // Acceso a ToOne

                    // Si la sala está marcada para eliminación, no la mostramos
                    if (room.isDeletePending) return const SizedBox.shrink();

                    return ListTile(
                      // Al hacer tap, ya se pasa el objeto 'room' completo como 'extra',
                      // lo cual es ideal para que ConversationScreen acceda a backgroundImageUrl.
                      onTap: () async {
  // 1. Abre el chat y espera a que el usuario regrese
  await context.push('/chat/${room.supabaseId}', extra: room);
  
  // 2. Al regresar, refrescamos el Stream automáticamente sin que el usuario estire la pantalla
  debugPrint('Regresó del chat. Actualizando estado de lectura...');
  setState(() {
    _inicializarStream();
  });
},
                      onLongPress: () => _confirmarEliminacionChat(context, room),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 8,
                      ),
                      leading: CircleAvatar(
                        radius: 28,
                        backgroundColor: theme.colorScheme.surfaceContainerHighest,
                        backgroundImage: otherUser?.avatarUrl != null
                            ? NetworkImage(otherUser!.avatarUrl!)
                            : null,
                        child: otherUser?.avatarUrl == null
                            ? (Text(
                                otherUser?.displayName?.toUpperCase() ?? '?',
                                style: TextStyle(
                                  color: theme.colorScheme.onSurface,
                                  fontSize: 20,
                                ),
                              ))
                            : null,
                      ),
                      title: Row(
                        children: [
                          Expanded(
                            child: Text(
                              otherUser?.displayName ?? 'Usuario desconocido',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 17,
                                color: theme.colorScheme.onSurface,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (lastMessage != null)
                            Text(
                              DateFormat('HH:mm').format(lastMessage.createdAt),
                              style: const TextStyle(
                                color: AppTheme.secondaryText,
                                fontSize: 13,
                              ),
                            ),
                        ],
                      ),
                      subtitle: Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          lastMessage?.content ?? 'Chat nuevo',
                          style: TextStyle(
                            color: lastMessage?.isRead == false &&
                                    lastMessage?.senderId != _currentUserId
                                ? theme.colorScheme.primary
                                : AppTheme.secondaryText,
                            fontSize: 15,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    );
                  }, childCount: rooms.length),
                );
              },
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.push('/profile'), // Revisa si esto debería ir al perfil o escanear QR
        backgroundColor: theme.primaryColor,
        child: const Icon(Icons.qr_code_scanner, color: Colors.white),
      ),
    );
  }

  // --- Método para pre-cargar los fondos de chat ---
  void _precacheChatBackgrounds(List<ChatRoom> rooms, BuildContext context) {
    for (var room in rooms) {
      final String? backgroundUrl = room.backgroundImageUrl;

      if (backgroundUrl != null && backgroundUrl.isNotEmpty && !_precachedImageUrls.contains(backgroundUrl)) {
        try {
          final ImageProvider imageProvider = CachedNetworkImageProvider(backgroundUrl);
          precacheImage(imageProvider, context)
            .then((_) {
              if (mounted) { // Asegura que el widget sigue montado antes de actualizar el estado
                _precachedImageUrls.add(backgroundUrl);
                // Si quieres ver las precargas, puedes descomentar la siguiente línea:
                // debugPrint('Precargada imagen para chat ID ${room.supabaseId} (${room.otherUser?.displayName ?? 'Desconocido'}): $backgroundUrl');
              }
            })
            .catchError((error) {
              debugPrint('Error precargando imagen para chat ID ${room.supabaseId} ($backgroundUrl): $error');
            });
        } catch (e) {
          debugPrint('Error al crear CachedNetworkImageProvider para URL $backgroundUrl: $e');
        }
      }
    }
  }
}