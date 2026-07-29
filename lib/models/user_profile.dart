import 'package:nowa_runtime/nowa_runtime.dart';
import 'package:objectbox/objectbox.dart';

@NowaGenerated()
@Entity()
class UserProfile {
  @Id()
  int obxId = 0;

  UserProfile({
    this.obxId = 0, // CORREGIDO: Añadir obxId al constructor con valor por defecto
    required this.supabaseId,
    this.nombre,
    this.preferenciaCanal,
    this.avatarUrl,
    required this.createdAt,
  });

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      supabaseId: json['id'] as String,
      nombre: json['nombre'] as String?,
      preferenciaCanal: json['preferencia_canal'] as int?,
      avatarUrl: json['avatar_url'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  @Unique(onConflict: ConflictStrategy.replace)
  @Index()
  final String supabaseId;

  final String? nombre;
  final int? preferenciaCanal;
  final String? avatarUrl;
  final DateTime createdAt;

  String? get displayName {
    return nombre;
  }

  Map<String, dynamic> toJson() {
    return {
      'id': supabaseId,
      'nombre': nombre,
      'preferencia_canal': preferenciaCanal,
      'avatar_url': avatarUrl,
      'created_at': createdAt.toIso8601String(),
    };
  }

  // copyWith se mantiene, ahora el constructor lo acepta
  UserProfile copyWith({
    int? obxId,
    String? supabaseId,
    String? nombre,
    int? preferenciaCanal,
    String? avatarUrl,
    DateTime? createdAt,
  }) {
    return UserProfile(
      obxId: obxId ?? this.obxId,
      supabaseId: supabaseId ?? this.supabaseId,
      nombre: nombre ?? this.nombre,
      preferenciaCanal: preferenciaCanal ?? this.preferenciaCanal,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}