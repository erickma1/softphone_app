class SipAccount {
  final String username;
  final String password;
  final String domain;
  final String status;

  SipAccount({
    required this.username,
    required this.password,
    required this.domain,
    required this.status,
  });

  factory SipAccount.fromJson(Map<String, dynamic> json) {
    return SipAccount(
      username: json['username']?.toString() ?? '',
      password: json['password']?.toString() ?? '',
      domain: json['domain']?.toString() ?? '',
      status: json['status']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'username': username,
      'password': password,
      'domain': domain,
      'status': status,
    };
  }
}

class BalanceInfo {
  final String amount;
  final String currency;

  BalanceInfo({required this.amount, required this.currency});

  factory BalanceInfo.fromJson(Map<String, dynamic> json) {
    return BalanceInfo(
      amount: json['amount']?.toString() ?? '0',
      currency: json['currency']?.toString() ?? 'USD',
    );
  }

  Map<String, dynamic> toJson() {
    return {'amount': amount, 'currency': currency};
  }
}

class User {
  final int userId;
  final String username;
  final String email;
  final String token;
  final String? refreshToken;
  final SipAccount? sip;
  final BalanceInfo? balance;

  User({
    required this.userId,
    required this.username,
    required this.email,
    required this.token,
    this.refreshToken,
    this.sip,
    this.balance,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      userId:
          int.tryParse(json['userId']?.toString() ?? '') ??
          int.tryParse(json['id']?.toString() ?? '') ??
          0,
      username: json['username']?.toString() ?? '',
      email: json['email']?.toString() ?? '',
      token: json['token']?.toString() ?? '',
      refreshToken: json['refreshToken']?.toString(),
      sip: json['sip'] is Map<String, dynamic>
          ? SipAccount.fromJson(json['sip'])
          : null,
      balance: json['balance'] is Map<String, dynamic>
          ? BalanceInfo.fromJson(json['balance'])
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'userId': userId,
      'username': username,
      'email': email,
      'token': token,
      'refreshToken': refreshToken,
      'sip': sip?.toJson(),
      'balance': balance?.toJson(),
    };
  }
}
