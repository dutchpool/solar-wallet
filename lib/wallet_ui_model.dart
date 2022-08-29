class WalletUIModel {
  final String label;
  final String address;
  final String? votingFor;
  final double? percentage;
  final String balance;

  WalletUIModel({
    required this.label,
    required this.address,
    required this.votingFor,
    required this.percentage,
    required this.balance,
  });
}
