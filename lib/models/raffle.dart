class Raffle {
  final String id;
  final String title;
  final String description;
  final String sponsorStore;
  final int tokensRequired;
  final DateTime endDate;
  final String prize;
  final int userEntries;

  Raffle({
    required this.id,
    required this.title,
    required this.description,
    required this.sponsorStore,
    required this.tokensRequired,
    required this.endDate,
    required this.prize,
    this.userEntries = 0,
  });

  factory Raffle.fromJson(Map<String, dynamic> json) {
    return Raffle(
      id: json['id'],
      title: json['title'],
      description: json['description'],
      sponsorStore: json['sponsorStore'],
      tokensRequired: json['tokensRequired'],
      endDate: DateTime.parse(json['endDate']),
      prize: json['prize'],
      userEntries: json['userEntries'] ?? 0,
    );
  }
}