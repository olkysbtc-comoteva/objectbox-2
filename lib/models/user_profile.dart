import 'package:nowa_runtime/nowa_runtime.dart';

@NowaGenerated()
class UserProfile {
  UserProfile({
    required this.id,
    this.nombre,
    this.preferenciaCanal,
    this.avatarUrl,
    required this.createdAt,
  });

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      id: json['id'] as String,
      nombre: json['nombre'] as String?,
      preferenciaCanal: json['preferencia_canal'] as int?,
      avatarUrl: json['avatar_url'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  final String id;

  final String? nombre;

  final int? preferenciaCanal;

  final String? avatarUrl;

  final DateTime createdAt;

  String? get displayName {
    return nombre;
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'nombre': nombre,
      'preferencia_canal': preferenciaCanal,
      'avatar_url': avatarUrl,
      'created_at': createdAt.toIso8601String(),
    };
  }
}
