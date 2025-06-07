class TennisCourt {
  final String clusterId;
  final double lat;
  final double lon;
  final int totalCourts;
  final int courtsInUse;
  final String access;
  final String surface;
  final bool lights;
  final String name;
  final DateTime? lastUpdated;
  final int timeSinceLastUpdate;
  final CourtStatus status;

  TennisCourt({
    required this.clusterId,
    required this.lat,
    required this.lon,
    required this.totalCourts,
    required this.courtsInUse,
    required this.access,
    required this.surface,
    required this.lights,
    required this.name,
    this.lastUpdated,
    required this.timeSinceLastUpdate,
    required this.status,
  });

  factory TennisCourt.fromJson(Map<String, dynamic> json) {
    final lastUpdated = json['last_updated'] != null
          ? DateTime.parse(json['last_updated'])
          : null;

    final timeSinceLastUpdate = lastUpdated != null
        ? DateTime.now().toUtc().difference(lastUpdated).inMinutes
        : -1;

    final status = _getStatusFromData(
      json['courts_in_use'] ?? 0,
      json['total_courts'],
      timeSinceLastUpdate,
    );

    final courtsInUse = status == CourtStatus.noRecentReport
        ? 0
        : (json['courts_in_use'] as int? ?? 0);

    return TennisCourt(
      clusterId: json['cluster_id'],
      lat: json['lat'].toDouble(),
      lon: json['lon'].toDouble(),
      totalCourts: json['total_courts'] as int,
      courtsInUse: courtsInUse,
      access: json['access'] as String,
      surface: json['surface'] as String,
      lights: json['lights'] ?? false,
      name: json['name'] as String,
      lastUpdated: lastUpdated,
      timeSinceLastUpdate: timeSinceLastUpdate,
      status: status,

    );
  }

  static CourtStatus _getStatusFromData(int inUse, int total, int timeSinceLastUpdate) {
    if (timeSinceLastUpdate == -1) return CourtStatus.noRecentReport;

    if (timeSinceLastUpdate > 60) return CourtStatus.noRecentReport;

    if (inUse == 0) return CourtStatus.empty;
    if (inUse == total) return CourtStatus.full;
    return CourtStatus.partiallyFull;
  }
}

enum CourtStatus {
  noRecentReport,
  empty,
  partiallyFull,
  full,
}

class PartnerStore {
  final String id;
  final double lat;
  final double lon;
  final String name;

  PartnerStore({
    required this.id,
    required this.lat,
    required this.lon,
    required this.name,
  });

  factory PartnerStore.fromJson(Map<String, dynamic> json) {
    return PartnerStore(
      id: json['id'],
      lat: json['lat'].toDouble(),
      lon: json['lon'].toDouble(),
      name: json['name'],
    );
  }
}