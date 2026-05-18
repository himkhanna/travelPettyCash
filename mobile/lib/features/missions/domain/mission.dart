/// Diplomatic / operational mission grouping multiple [Trip]s. Matches
/// the server's [Mission] record (`/api/v1/missions`).
class Mission {
  const Mission({
    required this.id,
    required this.name,
    this.nameAr,
    required this.code,
    this.description,
    this.parentMissionId,
    required this.status,
    required this.createdById,
    required this.createdAt,
    this.closedAt,
  });

  final String id;
  final String name;
  final String? nameAr;
  final String code;
  final String? description;
  final String? parentMissionId;
  final MissionStatus status;
  final String createdById;
  final DateTime createdAt;
  final DateTime? closedAt;
}

enum MissionStatus {
  active,
  closed;

  static MissionStatus fromWire(String s) =>
      s == 'CLOSED' ? MissionStatus.closed : MissionStatus.active;
}
