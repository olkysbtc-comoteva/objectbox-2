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

  @override
  void initState() {
    super.initState();
    _inicializarStream();
    _profileFuture = SupabaseService().getMyProfile();
    _currentUserId = SupabaseService().currentUserId;
  }

  void _inicializarStream() {
    _roomsStream = SupabaseService().getMyRoomsStream();
  }

  void _confirmarEliminacionChat(BuildContext context, ChatRoom room) {
    HapticFeedback.mediumImpact(); 
    final theme = Theme.of(context);
    final nombreContacto = room.otherUser?.displayName ?? 'este usuario';

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
              await SupabaseService().deleteRoom(room.id); 
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Conversación eliminada con éxito')),
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
    return Scaffold(
      body: RefreshIndicator(
        color: theme.colorScheme.primary,
        backgroundColor: theme.colorScheme.surface,
        onRefresh: () async {
          debugPrint('Forzando reinicialización manual del Stream de salas...');
          setState(() {
            _inicializarStream();
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
                    final otherUser = room.otherUser;
                    return ListTile(
                      onTap: () => context.push('/chat/${room.id}', extra: room),
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
                          if (room.lastMessage != null)
                            Text(
                              DateFormat('HH:mm').format(room.lastMessage!.createdAt),
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
                          room.lastMessage?.content ?? 'Chat nuevo',
                          style: TextStyle(
                            color: room.lastMessage?.isRead == false &&
                                    room.lastMessage?.senderId != _currentUserId
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
        onPressed: () => context.push('/profile'),
        backgroundColor: theme.primaryColor,
        child: const Icon(Icons.qr_code_scanner, color: Colors.white),
      ),
    );
  }
}
