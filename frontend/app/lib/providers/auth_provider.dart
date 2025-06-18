import 'package:flutter/material.dart';

class User {
  final int id;
  final String username;
  final String? firstName;
  final String? lastName;

  User({
    required this.id,
    required this.username,
    this.firstName,
    this.lastName,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'],
      username: json['username'],
      firstName: json['first_name'],
      lastName: json['last_name'],
    );
  }
}

class AuthProvider with ChangeNotifier {
  String? _token;
  User? _user;

  String? get token => _token;
  User? get user => _user;

  void setAuth(String? token, User? user) {
    _token = token;
    _user = user;
    notifyListeners();
  }

  void clearAuth() {
    _token = null;
    _user = null;
    notifyListeners();
  }
}
