import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:gal/gal.dart';
import 'package:comoteva/integrations/supabase_service.dart';
import 'package:comoteva/models/chat_room.dart';
import 'package:comoteva/models/chat_message.dart';
import 'package:comoteva/globals/app_state.dart';
import 'package:cached_network_image/cached_network_image.dart'; // <--- NUEVA DEPENDENCIA: Importamos cached_network_image

class ConversationScreen extends StatefulWidget {
  final String roomId;
  final ChatRoom? chatRoom; // El ChatRoom ya viene con la URL del fondo

  const ConversationScreen({
    super.key,
    required this.roomId,
    this.chatRoom,
  });

  @override
  State<ConversationScreen> createState() => _ConversationScreenState();
}

class _ConversationScreenState extends State<ConversationScreen> {
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _messageController = TextEditingController();

  static const String _fontStorageKey = 'chat_bubble_font_size';
  double _fontSizeBurbuja = 16.0;
  double _scaleStartFontSize = 16.0;

  String? _contactName;
  bool _isLoadingName = false;

  @override
  void initState() {
    super.initState();
    _cargarPreferenciaTamano();

    // Si el chatRoom ya viene (desde la lista), usamos su nombre.
    // Si no (ej. por notificación), lo buscamos.
    if (widget.chatRoom != null) {
      _contactName = widget.chatRoom?.otherUser?.displayName;
    } else {
      _fetchContactDetails();
    }

    // Usamos addPostFrameCallback para asegurarnos de que el BuildContext esté disponible
    // y para cargar el fondo del chat activo después de que el widget se haya montado.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (mounted) {
        final appState = AppState.of(context, listen: false);
        // Primero, intentamos obtener el fondo del chat directamente del chatRoom
        // (que ya fue precargado si venía de ChatListScreen).
        String? initialBackgroundUrl = widget.chatRoom?.backgroundImageUrl;

        // Si el chatRoom tiene un fondo, lo usamos directamente.
        // Si no, o si el usuario quiere un fondo persistente, consultamos Supabase.
        if (initialBackgroundUrl != null && initialBackgroundUrl.isNotEmpty) {
          appState.setChatWallpaper(initialBackgroundUrl);
          debugPrint('Fondo inicial establecido desde ChatRoom: $initialBackgroundUrl');
        } else {
          // Si no hay fondo en chatRoom, o si queremos el fondo activo guardado en Supabase,
          // lo consultamos. Este es el comportamiento existente para fondos persistentes.
          final fondoActivo = await SupabaseService().getActiveChatBackground(widget.roomId);
          if (fondoActivo != null && mounted) {
            appState.setChatWallpaper(fondoActivo['url'] as String?);
            debugPrint('Fondo activo establecido desde Supabase: ${fondoActivo['url']}');
          } else {
            // Si aún no hay fondo, establece uno por defecto si hay disponibles
            final fondos = await SupabaseService().getAvailableWallpapers();
            if (fondos.isNotEmpty && mounted && appState.currentChatWallpaper == null) {
              appState.setChatWallpaper(fondos.first['url'] as String?);
              debugPrint('Fondo por defecto establecido: ${fondos.first['url']}');
            }
          }
        }
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _fetchContactDetails() async {
    if (!mounted) return;
    setState(() => _isLoadingName = true);

    try {
      final supabase = Supabase.instance.client;
      final currentUserId = supabase.auth.currentUser?.id;

      if (currentUserId == null) throw Exception("Usuario no autenticado");

      final data = await supabase
          .from('room_members')
          .select('profiles:user_id(nombre)')
          .eq('room_id', widget.roomId)
          .neq('user_id', currentUserId)
          .maybeSingle();

      if (mounted) {
        setState(() {
          if (data != null && data['profiles'] != null) {
            _contactName = data['profiles']['nombre'] ?? 'Usuario';
          } else {
            _contactName = "Chat";
          }
          _isLoadingName = false;
        });
      }
    } catch (e) {
      debugPrint('Error al traer datos del contacto de Supabase: $e');
      if (mounted) {
        setState(() {
          _contactName = "Chat";
          _isLoadingName = false;
        });
      }
    }
  }

  Future<void> _cargarPreferenciaTamano() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final guardado = prefs.getDouble(_fontStorageKey);
      if (guardado != null && mounted) {
        setState(() {
          _fontSizeBurbuja = guardado;
        });
      }
    } catch (e) {
      debugPrint('Error al cargar tamaño de letra: $e');
    }
  }

  Future<void> _guardarPreferenciaTamano(double nuevoTamano) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(_fontStorageKey, nuevoTamano);
    } catch (e) {
      debugPrint('Error al guardar tamaño de letra: $e');
    }
  }

  Future<void> _sendKeyboardGif(KeyboardInsertedContent contenido) async {
    if (!mounted) return;

    try {
      final String nombreArchivo = 'gif_${DateTime.now().millisecondsSinceEpoch}.gif';

      await Supabase.instance.client.storage
          .from('temporary_media')
          .uploadBinary(
            'gifs/$nombreArchivo',
            contenido.data!,
          );

      final String urlPublicaFinal = Supabase.instance.client.storage
          .from('temporary_media')
          .getPublicUrl('gifs/$nombreArchivo');

      await SupabaseService().sendMessage(
        widget.roomId,
        urlPublicaFinal,
        type: 'gif',
      );
      _messageController.clear();
    } catch (error) {
      debugPrint("Error al procesar o subir el GIF del teclado: $error");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("No se pudo enviar el GIF del teclado")),
        );
      }
    }
  }

  Future<void> _downloadMediaFile(String url, String type) async {
    HapticFeedback.lightImpact();

    try {
      final hasAccess = await Gal.hasAccess();
      if (!hasAccess) {
        await Gal.requestAccess();
      }

      double progresoActual = 0.0;
      final theme = Theme.of(context);

      if (!mounted) return;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) {
          return StatefulBuilder(
            builder: (context, setDialogState) {
              return AlertDialog(
                backgroundColor: theme.colorScheme.surface,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                content: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(
                        value: progresoActual,
                        strokeWidth: 5,
                        valueColor: AlwaysStoppedAnimation<Color>(theme.primaryColor),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        'Guardando $type...',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      const SizedBox(height: 8),
                      Text('${(progresoActual * 100).toStringAsFixed(0)}%'),
                    ],
                  ),
                ),
              );
            },
          );
        },
      );

      final dio = Dio();
      final tempDir = await getTemporaryDirectory();
      final extension = type.toLowerCase() == 'video' ? 'mp4' : (type.toLowerCase() == 'gif' ? 'gif' : 'jpg');
      final tempPath = '${tempDir.path}/comoteva_${DateTime.now().millisecondsSinceEpoch}.$extension';

      await dio.download(
        url,
        tempPath,
        onReceiveProgress: (received, total) {
          if (total != -1 && mounted) {
            final double calculo = received / total;
            try {
              (context as Element).visitChildren((Element child) {
                if (child is StatefulElement && child.state is Object) {
                  child.state.setState(() {
                    progresoActual = calculo;
                  });
                }
              });
            } catch (_) {}
          }
        },
      );

      if (type.toLowerCase() == 'video') {
        await Gal.putVideo(tempPath);
      } else {
        await Gal.putImage(tempPath);
      }

      final file = File(tempPath);
      if (await file.exists()) {
        await file.delete();
      }

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$type guardado en la galería con éxito'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No se pudo completar la descarga'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
      debugPrint('Error en la descarga real: $e');
    }
  }

  void _onMessageTap(ChatMessage message) {
    final isMe = message.senderId == SupabaseService().currentUserId;
    final isVideo = message.messageType == 'video';
    final isImage = message.messageType == 'image';
    final isGif = message.messageType == 'gif';
    final isMedia = isImage || isVideo || isGif;
    final theme = Theme.of(context);

    List<Widget> options = [
      ListTile(
        leading: const Icon(Icons.info_outline, color: Colors.blue),
        title: const Text('Información del mensaje'),
        onTap: () {
          Navigator.pop(context);
          _showMsgInfo(message);
        },
      ),
      ListTile(
        leading: const Icon(Icons.reply, color: Colors.green),
        title: const Text('Reenviar mensaje'),
        onTap: () {
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Mensaje copiado para reenviar')),
          );
        },
      ),
    ];

    if (isMedia) {
      options.add(
        ListTile(
          leading: Icon(Icons.fullscreen, color: theme.primaryColor),
          title: Text(isVideo ? 'Ver Video' : (isGif ? 'Ver GIF' : 'Ver Imagen')),
          onTap: () {
            Navigator.pop(context);
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => MediaPreviewScreen(
                  message: message,
                  onDownload: _downloadMediaFile,
                  onDelete: (messageId) async {
                    await SupabaseService().deleteMessage(messageId);
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Mensaje eliminado.')),
                      );
                    }
                  },
                ),
              ),
            );
          },
        ),
      );
      options.add(
        ListTile(
          leading: const Icon(Icons.download, color: Colors.purple),
          title: const Text('Descargar a la galería'),
          onTap: () {
            Navigator.pop(context);
            _downloadMediaFile(message.content, isVideo ? 'Video' : (isGif ? 'GIF' : 'Imagen'));
          },
        ),
      );
    } else if (isMe && message.messageType == 'text') {
      options.add(
        ListTile(
          leading: const Icon(Icons.edit, color: Colors.orange),
          title: const Text('Editar mensaje'),
          onTap: () {
            Navigator.pop(context);
            _showEditDialog(message);
          },
        ),
      );
    }

    if (isMe) {
      options.add(
        ListTile(
          leading: const Icon(Icons.delete_outline, color: Colors.red),
          title: const Text('Eliminar para todos'),
          onTap: () async {
            Navigator.pop(context);
            await SupabaseService().deleteMessage(message.id);
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Mensaje eliminado para todos.')),
              );
            }
          },
        ),
      );
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: theme.colorScheme.surface,
      builder: (context) => SafeArea(
        child: Wrap(
          children: options,
        ),
      ),
    );
  }

  void _onMessageLongPress(ChatMessage message) {
    HapticFeedback.mediumImpact();
    final listaEmojis = ['👍', '🧉', '😂', '🤔', '😎', '🤭'];

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Theme.of(context).colorScheme.surface,
        title: const Text('Reaccionar', textAlign: TextAlign.center, style: TextStyle(fontSize: 16)),
        content: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: listaEmojis.map((emoji) {
            return GestureDetector(
              onTap: () async {
                Navigator.pop(context);
                await SupabaseService().updateMessageReaction(message.id, emoji);
              },
              child: Text(emoji, style: const TextStyle(fontSize: 28)),
            );
          }).toList(),
        ),
      ),
    );
  }

  void _showEditDialog(ChatMessage message) {
    final editController = TextEditingController(text: message.content);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Editar mensaje'),
        content: TextField(controller: editController, maxLines: null),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () async {
              if (editController.text.trim().isNotEmpty) {
                Navigator.pop(context);
                await SupabaseService().updateMessage(
                  message.id,
                  editController.text.trim(),
                );
              }
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
  }

  void _showMsgInfo(ChatMessage message) {
    final localTime = message.createdAt.toLocal();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Detalles'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Enviado: ${DateFormat('dd/MM/yyyy HH:mm').format(localTime)}'),
            const SizedBox(height: 8),
            Text('Tipo: ${message.messageType}'),
            const SizedBox(height: 8),
            Text('Estado: ${message.isRead == true ? "Leído" : "Entregado"}'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cerrar'),
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
      appBar: AppBar(
        title: _isLoadingName
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.blue),
              )
            : Text(
                _contactName ?? widget.chatRoom?.otherUser?.displayName ?? 'Chat',
                style: TextStyle(color: theme.colorScheme.onSurface),
              ),
        backgroundColor: theme.scaffoldBackgroundColor.withOpacity(0.8),
        actions: [
          PopupMenuButton<String>(
            icon: Icon(Icons.more_vert, color: theme.colorScheme.onSurface),
            onSelected: (value) {
              if (value == 'wallpaper') {
                showModalBottomSheet(
                  context: context,
                  backgroundColor: theme.colorScheme.surface,
                  shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                  ),
                  builder: (context) {
                    return SafeArea(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Padding(
                            padding: EdgeInsets.all(16.0),
                            child: Text(
                              'Seleccionar Fondo Dinámico',
                              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                            ),
                          ),
                          const Divider(),
                          SizedBox(
                            height: 160,
                            child: FutureBuilder<List<Map<String, dynamic>>>(
                              future: SupabaseService().getAvailableWallpapers(),
                              builder: (context, snapshot) {
                                if (snapshot.connectionState == ConnectionState.waiting) {
                                  return const Center(child: CircularProgressIndicator());
                                }
                                final wallpapers = snapshot.data ?? [];
                                if (wallpapers.isEmpty) {
                                  return const Center(child: Text('No hay fondos disponibles'));
                                }
                                return ListView.builder(
                                  scrollDirection: Axis.horizontal,
                                  padding: const EdgeInsets.symmetric(horizontal: 16),
                                  itemCount: wallpapers.length,
                                  itemBuilder: (context, index) {
                                    final wallpaper = wallpapers[index];
                                    final wpUrl = wallpaper['url'] as String? ?? '';
                                    final wpId = wallpaper['id'] as int;

                                    return GestureDetector(
                                      onTap: () async {
                                        appState.setChatWallpaper(wpUrl);
                                        await SupabaseService().updateChatBackground(widget.roomId, wpId);
                                        if (context.mounted) Navigator.pop(context);
                                      },
                                      child: Container(
                                        width: 100,
                                        margin: const EdgeInsets.only(right: 12, bottom: 20),
                                        decoration: BoxDecoration(
                                          borderRadius: BorderRadius.circular(12),
                                          border: Border.all(color: theme.dividerColor),
                                          image: wpUrl.isNotEmpty
                                              ? DecorationImage(
                                                  // <--- AQUI SE USARA NetworkImage (normal), ya que esto es para seleccionar nuevos fondos ---
                                                  // Estos no están precargados desde la ChatListScreen
                                                  image: NetworkImage(wpUrl),
                                                  fit: BoxFit.cover,
                                                )
                                              : null,
                                          color: Colors.grey,
                                        ),
                                        child: wpUrl.isEmpty
                                            ? const Center(child: Icon(Icons.image_not_supported, color: Colors.white24))
                                            : null,
                                      ),
                                    );
                                  },
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                );
              }
            },
            itemBuilder: (BuildContext context) => [
              const PopupMenuItem<String>(
                value: 'wallpaper',
                child: Row(
                  children: [
                    Icon(Icons.wallpaper, size: 20),
                    SizedBox(width: 12),
                    Text('Fondo dinámico'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),

      body: GestureDetector(
        onScaleStart: (details) {
          _scaleStartFontSize = _fontSizeBurbuja;
        },
        onScaleUpdate: (details) {
          setState(() {
            double calculado = _scaleStartFontSize * details.scale;
            _fontSizeBurbuja = calculado.clamp(13.0, 26.0);
          });
        },
        onScaleEnd: (details) {
          _guardarPreferenciaTamano(_fontSizeBurbuja);
        },
        child: Stack(
          children: [
            if (appState.currentChatWallpaper != null && appState.currentChatWallpaper!.isNotEmpty)
              Container(
                decoration: BoxDecoration(
                  image: DecorationImage(
                    image: CachedNetworkImageProvider(appState.currentChatWallpaper!), // <--- ¡CAMBIO AQUI!
                    fit: BoxFit.cover,
                  ),
                ),
              ),
            Column(
              children: [
                Expanded(
                  child: StreamBuilder<List<ChatMessage>>(
                    stream: SupabaseService().getMessagesStream(widget.roomId),
                    builder: (context, snapshot) {
                      if (!snapshot.hasData) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      final messages = snapshot.data;

                      return NotificationListener<ScrollNotification>(
                        onNotification: (ScrollNotification notification) {
                          if (notification.metrics.pixels < -60 && notification is ScrollUpdateNotification) {
                            HapticFeedback.lightImpact();
                            SupabaseService().markMessagesAsRead(widget.roomId);
                          }
                          return false;
                        },
                        child: ListView.builder(
                          controller: _scrollController,
                          physics: const AlwaysScrollableScrollPhysics(
                            parent: BouncingScrollPhysics(),
                          ),
                          reverse: true,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
                          itemCount: messages?.length ?? 0,
                          itemBuilder: (context, index) {
                            final message = messages![index];
                            final isMe = message.senderId == SupabaseService().currentUserId;
                            final isVideo = message.messageType == 'video';
                            final isImage = message.messageType == 'image';
                            final isGif = message.messageType == 'gif';
                            final isMedia = isImage || isVideo || isGif;
                            final localTime = message.createdAt.toLocal();
                            final tieneReaccion = message.reaction != null && message.reaction!.isNotEmpty;
                            final esLeido = message.isRead ?? false;

                            return Align(
                              alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                              child: GestureDetector(
                                onTap: () {
                                  _onMessageTap(message);
                                },
                                onLongPress: () => _onMessageLongPress(message),
                                child: Stack(
                                  clipBehavior: Clip.none,
                                  children: [
                                    Container(
                                      margin: EdgeInsets.only(bottom: tieneReaccion ? 16 : 8),
                                      padding: isMedia ? const EdgeInsets.all(4) : const EdgeInsets.fromLTRB(14, 8, 10, 6),
                                      constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
                                      decoration: BoxDecoration(
                                        color: isMe ? theme.primaryColor : theme.colorScheme.surface,
                                        borderRadius: BorderRadius.circular(18),
                                      ),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.end,
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          if (isImage || isGif)
                                            ClipRRect(
                                              borderRadius: BorderRadius.circular(14),
                                              // Aquí también puedes usar CachedNetworkImage si deseas para las miniaturas de imágenes/GIFs dentro del chat,
                                              // aunque el precargado era específicamente para el *fondo*.
                                              child: CachedNetworkImage( // <--- Opcional: Usar CachedNetworkImage aquí para mensajes de imagen/GIF
                                                imageUrl: message.content,
                                                fit: BoxFit.cover,
                                                placeholder: (context, url) => const CircularProgressIndicator(),
                                                errorWidget: (context, url, error) => const Icon(Icons.error),
                                              ),
                                            ),
                                          if (isVideo)
                                            Container(
                                              height: 180,
                                              decoration: BoxDecoration(
                                                color: Colors.black87,
                                                borderRadius: BorderRadius.circular(14),
                                              ),
                                              child: const Center(
                                                child: Icon(Icons.video_library, color: Colors.white, size: 50),
                                              ),
                                            ),
                                          if (!isMedia)
                                            AnimatedDefaultTextStyle(
                                              duration: const Duration(milliseconds: 100),
                                              curve: Curves.easeOutCubic,
                                              style: TextStyle(
                                                color: isMe ? Colors.white : theme.colorScheme.onSurface,
                                                fontSize: _fontSizeBurbuja,
                                              ),
                                              child: Text(message.content),
                                            ),
                                          const SizedBox(height: 2),
                                          Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Text(
                                                DateFormat('HH:mm').format(localTime),
                                                style: TextStyle(
                                                  color: isMe ? Colors.white70 : Colors.grey,
                                                  fontSize: 11,
                                                ),
                                              ),
                                              if (isMe) ...[
                                                const SizedBox(width: 4),
                                                Icon(
                                                  esLeido ? Icons.done_all : Icons.done,
                                                  size: 14,
                                                  color: isMe ? Colors.white70 : theme.primaryColor,
                                                ),
                                              ],
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                    if (tieneReaccion)
                                      Positioned(
                                        bottom: -(_fontSizeBurbuja * 0.4),
                                        right: isMe ? null : 12,
                                        left: isMe ? 12 : null,
                                        child: Container(
                                          padding: EdgeInsets.symmetric(
                                            horizontal: _fontSizeBurbuja * 0.45,
                                            vertical: _fontSizeBurbuja * 0.15,
                                          ),
                                          decoration: BoxDecoration(
                                            color: theme.colorScheme.surfaceVariant ?? Colors.grey,
                                            borderRadius: BorderRadius.circular(_fontSizeBurbuja * 0.7),
                                            boxShadow: const [
                                              BoxShadow(
                                                color: Colors.black26,
                                                blurRadius: 3,
                                                offset: Offset(0, 1.5),
                                              )
                                            ],
                                          ),
                                          child: Text(
                                            message.reaction!,
                                            style: TextStyle(
                                              fontSize: _fontSizeBurbuja + 2.0,
                                            ),
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      );
                    },
                  ),
                ),
                _buildChatBar(),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChatBar() {
    final theme = Theme.of(context);
    final picker = ImagePicker();

    Future<void> _adjuntarMultimedia(ImageSource source, String type) async {
      try {
        final XFile? file = type == 'video'
            ? await picker.pickVideo(source: source)
            : await picker.pickImage(source: source, imageQuality: 75);

        if (file != null) {
          final bytes = await file.readAsBytes();
          final publicUrl = await SupabaseService().uploadMedia(
            bytes,
            file.name,
            roomId: widget.roomId,
          );

          if (publicUrl != null) {
            await SupabaseService().sendMessage(
              widget.roomId,
              publicUrl,
              type: type,
            );
          }
        }
      } catch (e) {
        debugPrint('Error al adjuntar archivo: $e');
      }
    }

    void _procesarEnvio() {
      final texto = _messageController.text.trim();
      if (texto.isNotEmpty) {
        SupabaseService().sendMessage(widget.roomId, texto);
        _messageController.clear();
      }
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      color: theme.colorScheme.surface,
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            IconButton(
              icon: Icon(Icons.add, color: theme.primaryColor, size: 26),
              onPressed: () {
                showModalBottomSheet(
                  context: context,
                  backgroundColor: theme.colorScheme.surface,
                  shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                  ),
                  builder: (context) => SafeArea(
                    child: Wrap(
                      children: [
                        ListTile(
                          leading: const Icon(Icons.image, color: Colors.blue),
                          title: const Text('Enviar Imagen (Galería)'),
                          onTap: () {
                            Navigator.pop(context);
                            _adjuntarMultimedia(ImageSource.gallery, 'image');
                          },
                        ),
                        ListTile(
                          leading: const Icon(Icons.camera_alt, color: Colors.green),
                          title: const Text('Tomar Foto (Cámara)'),
                          onTap: () {
                            Navigator.pop(context);
                            _adjuntarMultimedia(ImageSource.camera, 'image');
                          },
                        ),
                        ListTile(
                          leading: const Icon(Icons.video_library, color: Colors.red),
                          title: const Text('Enviar Video'),
                          onTap: () {
                            Navigator.pop(context);
                            _adjuntarMultimedia(ImageSource.gallery, 'video');
                          },
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: theme.scaffoldBackgroundColor,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: TextField(
                  controller: _messageController,
                  maxLines: null,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _procesarEnvio(),
                  decoration: const InputDecoration(
                    hintText: 'Mensaje',
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(vertical: 10),
                  ),
                  contentInsertionConfiguration: ContentInsertionConfiguration(
                    allowedMimeTypes: const <String>['image/gif'],
                    onContentInserted: (KeyboardInsertedContent content) {
                      _sendKeyboardGif(content);
                    },
                  ),
                ),
              ),
            ),
            const SizedBox(width: 4),
            IconButton(
              icon: Icon(Icons.send, color: theme.primaryColor),
              onPressed: _procesarEnvio,
            ),
          ],
        ),
      ),
    );
  }
}

class MediaPreviewScreen extends StatelessWidget {
  final ChatMessage message;
  final Future<void> Function(String, String) onDownload;
  final Future<void> Function(String) onDelete;

  const MediaPreviewScreen({
    super.key,
    required this.message,
    required this.onDownload,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final isVideo = message.messageType.toLowerCase() == 'video';
    final isGif = message.messageType.toLowerCase() == 'gif';
    final isMe = message.senderId == SupabaseService().currentUserId;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(
          isVideo ? 'Video' : (isGif ? 'GIF' : 'Imagen'),
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.download, size: 26),
            onPressed: () => onDownload(message.content, isVideo ? 'Video' : (isGif ? 'GIF' : 'Imagen')),
            tooltip: 'Descargar a la galería',
          ),
          if (isMe)
            IconButton(
              icon: const Icon(Icons.delete_outline, size: 26, color: Colors.redAccent),
              onPressed: () async {
                final confirmDelete = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Eliminar mensaje'),
                    content: const Text('¿Estás seguro de que quieres eliminar este mensaje para todos?'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(ctx).pop(false),
                        child: const Text('Cancelar'),
                      ),
                      TextButton(
                        onPressed: () => Navigator.of(ctx).pop(true),
                        child: const Text('Eliminar'),
                      ),
                    ],
                  ),
                );
                if (confirmDelete == true) {
                  onDelete(message.id);
                  Navigator.of(context).pop();
                }
              },
              tooltip: 'Eliminar para todos',
            ),
        ],
      ),
      body: Center(
        child: isVideo
            ? Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.video_library, color: Colors.white60, size: 80),
                  const SizedBox(height: 20),
                  const Text(
                    'Previsualización de Video',
                    style: TextStyle(color: Colors.white70, fontSize: 16),
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white12,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    icon: const Icon(Icons.download, color: Colors.white),
                    label: const Text(
                      'Descargar para reproducir',
                      style: TextStyle(color: Colors.white),
                    ),
                    onPressed: () => onDownload(message.content, 'Video'),
                  ),
                ],
              )
            : InteractiveViewer(
                maxScale: 4.0,
                child: CachedNetworkImage( // <--- Opcional: Usar CachedNetworkImage aquí para la previsualización de imagen/GIF
                  imageUrl: message.content,
                  fit: BoxFit.contain,
                  placeholder: (context, url) => const Center(
                    child: CircularProgressIndicator(color: Colors.white),
                  ),
                  errorWidget: (context, url, error) {
                    return const Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.broken_image, color: Colors.white38, size: 48),
                        SizedBox(height: 12),
                        Text(
                          'No se pudo cargar el medio',
                          style: TextStyle(color: Colors.white38),
                        ),
                      ],
                    );
                  },
                ),
              ),
      ),
    );
  }
}