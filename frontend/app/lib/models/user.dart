class User {
  final int id;
  final String username;
  String password;
  final String firstName;
  final String lastName;
  final String email;

  User({
    required this.id,
    required this.username,
    this.password = '',
    required this.firstName,
    required this.lastName,
    required this.email,
  });

  // Create a User from JSON
  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'] as int,
      username: json['username'] as String,
      firstName: json['first_name'] as String,
      lastName: json['last_name'] as String,
      email: json['email'] as String,
    );
  }

  // Convert User to JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'username': username,
      'password': password,
      'first_name': firstName,
      'last_name': lastName,
      'email': email,
    };
  }

  // Create a copy of User with some fields updated
  User copyWith({
    int? id,
    String? username,
    String? password,
    String? firstName,
    String? lastName,
    String? email,
  }) {
    return User(
      id: id ?? this.id,
      username: username ?? this.username,
      password: password ?? this.password,
      firstName: firstName ?? this.firstName,
      lastName: lastName ?? this.lastName,
      email: email ?? this.email,
    );
  }

  @override
  String toString() {
    return 'User(id: $id, username: $username, firstName: $firstName, lastName: $lastName, email: $email)';
  }
}
