class Raffle {
  final String id;
  final DateTime start;
  final DateTime end;
  final bool status;
  final String prize;
  final int entryFee;
  final String winner;
  
  Raffle({
    required this.id,
    required this.start,
    required this.end,
    required this.status,
    required this.prize,
    required this.entryFee,
    required this.winner,
  });

  factory Raffle.fromJson(Map<String, dynamic> json) {
    final winner = (json['winner'] != null) ? json['winner'] : '';
    
    return Raffle(
      id: json['id'],
      start: DateTime.parse(json['start']),
      end: DateTime.parse(json['end']),
      status: json['status'],
      prize: json['prize'],
      entryFee: json['entry_fee'],
      winner: winner
    );
  }
}