import 'package:go_router/go_router.dart';
import 'package:comoteva/globals/supabase_auth_state_notifier.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:comoteva/pages/auth_screen.dart';
import 'package:comoteva/pages/chat_list_screen.dart';
import 'package:comoteva/models/chat_room.dart';
import 'package:comoteva/pages/conversation_screen.dart';
import 'package:comoteva/pages/profile_screen.dart';
import 'package:nowa_runtime/nowa_runtime.dart';

@NowaGenerated()
final appRouter = GoRouter(
  initialLocation: '/',
  refreshListenable: SupabaseAuthStateNotifier(),
  redirect: (context, state) {
    final session = Supabase.instance.client.auth.currentSession;
    final isLoggingIn = state.matchedLocation == '/auth';
    if (session == null && !isLoggingIn) {
      return '/auth';
    }
    if (session != null && isLoggingIn) {
      return '/';
    }
    return null;
  },
  routes: [
    GoRoute(path: '/auth', builder: (context, state) => const AuthScreen()),
    GoRoute(
      path: '/',
      builder: (context, state) => const ChatListScreen(),
      routes: [
        GoRoute(
          path: 'chat/:roomId',
          builder: (context, state) {
            final roomId = state.pathParameters['roomId'];
            final room = state.extra as ChatRoom?;
            return ConversationScreen(roomId: roomId!, chatRoom: room);
          },
        ),
        GoRoute(
          path: 'profile',
          builder: (context, state) => const ProfileScreen(),
        ),
      ],
    ),
  ],
);
