class AppConfig {
  static const String brokerUrl = String.fromEnvironment(
    'BROKER_URL',
    defaultValue: 'https://drivenet-broker.onrender.com',
  );

  static const String googleClientId = String.fromEnvironment(
    'GOOGLE_CLIENT_ID',
    defaultValue: '901086875987-nekpj2rk5i3ep4shve7m6nou73qs1gfb.apps.googleusercontent.com',
  );

  static const String googleServerClientId = String.fromEnvironment(
    'GOOGLE_SERVER_CLIENT_ID',
    defaultValue: '901086875987-462a9467nqo682h4cqne48e1mmgrt5qm.apps.googleusercontent.com',
  );
}
