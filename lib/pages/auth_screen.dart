import 'package:flutter/material.dart';
import 'package:nowa_runtime/nowa_runtime.dart';
import 'package:comoteva/integrations/supabase_service.dart';
import 'package:comoteva/app_theme.dart';
import 'package:comoteva/components/glass_container.dart';
import 'package:comoteva/components/apple_button.dart';
// --- IMPORTANTE: Importamos shared_preferences y el main para acceder a sharedPrefs ---
import 'package:shared_preferences/shared_preferences.dart';
import 'package:comoteva/main.dart'; 

@NowaGenerated()
class AuthScreen extends StatefulWidget {
  @NowaGenerated({'loader': 'auto-constructor'})
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() {
    return _AuthScreenState();
  }
}

@NowaGenerated()
class _AuthScreenState extends State<AuthScreen> {
  final _emailController = TextEditingController();

  final _passwordController = TextEditingController();

  final _nameController = TextEditingController();

  bool _isLogin = true;

  bool _isLoading = false;

  String? _errorMessage;

  // Función interna para procesar el token guardado temporalmente
  Future<void> _syncPendingFcmToken() async {
    try {
      final pendingToken = sharedPrefs.getString('pending_fcm_token');
      if (pendingToken != null && pendingToken.isNotEmpty) {
        // Subimos el token a Supabase ahora que el usuario ya tiene sesión activa
        await SupabaseService().updateFcmToken(pendingToken);
        // Lo borramos de la memoria local para no repetir el proceso innecesariamente
        await sharedPrefs.remove('pending_fcm_token');
      }
    } catch (e) {
      debugPrint('Error al sincronizar el token FCM: $e');
    }
  }

  Future<void> _handleSubmit() async {
    if (_emailController.text.isEmpty || _passwordController.text.isEmpty) {
      setState(() => _errorMessage = 'Completa todos los campos');
      return;
    }
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      if (_isLogin) {
        await SupabaseService().signInAndSyncProfile(
          _emailController.text,
          _passwordController.text,
        );
      } else {
        await SupabaseService().signUpWithProfile(
          _emailController.text,
          _passwordController.text,
          nombre: _nameController.text.isNotEmpty ? _nameController.text : null,
        );
      }

      // ** CAMBIO CRÍTICO AQUÍ **
      // Si llegamos a este punto sin errores, el login/registro fue exitoso.
      // Sincronizamos el token inmediatamente.
      await _syncPendingFcmToken();

    } catch (e) {
      setState(() {
        final errorStr = e.toString().toLowerCase();
        if (errorStr.contains('invalid login credentials')) {
          _errorMessage = 'Email o contraseña incorrectos';
        } else if (errorStr.contains('already registered')) {
          _errorMessage =
              'Este email ya esta registrado. Intenta iniciar sesion.';
        } else {
          _errorMessage = 'Hubo un error. Intenta de nuevo.';
        }
      });
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(height: 60),
              Text(
                'ComoTeVa',
                style: textTheme.headlineLarge?.copyWith(
                  color: AppTheme.appleBlue,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _isLogin
                    ? '¡Empecemos!'
                    : 'Crea una cuenta y empieza a chatear',
                style: textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 48),
              if (!_isLogin) ...[
                GlassContainer(
                  opacity: 0.1,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: TextField(
                    controller: _nameController,
                    decoration: const InputDecoration(
                      hintText: 'Tu nombre',
                      border: InputBorder.none,
                      hintStyle: TextStyle(color: AppTheme.secondaryText),
                    ),
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
                const SizedBox(height: 16),
              ],
              GlassContainer(
                opacity: 0.1,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  controller: _emailController,
                  decoration: const InputDecoration(
                    hintText: 'Email',
                    border: InputBorder.none,
                    hintStyle: TextStyle(color: AppTheme.secondaryText),
                  ),
                  style: const TextStyle(color: Colors.white),
                  keyboardType: TextInputType.emailAddress,
                ),
              ),
              const SizedBox(height: 16),
              GlassContainer(
                opacity: 0.1,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  controller: _passwordController,
                  decoration: const InputDecoration(
                    hintText: 'Contraseña',
                    border: InputBorder.none,
                    hintStyle: TextStyle(color: AppTheme.secondaryText),
                  ),
                  style: const TextStyle(color: Colors.white),
                  obscureText: true,
                ),
              ),
              if (_errorMessage != null) ...[
                const SizedBox(height: 16),
                Text(
                  _errorMessage!,
                  style: const TextStyle(
                    color: AppTheme.appleRed,
                    fontSize: 13,
                  ),
                ),
              ],
              const SizedBox(height: 32),
              AppleButton(
                text: _isLogin ? 'Entrar' : 'Registrarse',
                isLoading: _isLoading,
                onPressed: _handleSubmit,
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () => setState(() {
                  _isLogin = !_isLogin;
                  _errorMessage = null;
                }),
                child: Text(
                  _isLogin
                      ? 'No tienes cuenta? Registrate'
                      : 'Ya tienes cuenta? Entra',
                  style: const TextStyle(color: AppTheme.appleBlue),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
