import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';

import 'firebase_options.dart';
import 'shell.dart';
import 'screens/login_screen.dart';
import 'services/user_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TaskBuddy',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: StreamBuilder<User?>(
        stream: FirebaseAuth.instance.authStateChanges(),
        builder: (context, snap) {
          // Firebase still deciding who the user is
          if (snap.connectionState == ConnectionState.waiting) {
            return const Scaffold(body: Center(child: CircularProgressIndicator()));
          }

          // Signed in → ensure users/{uid} exists, then show Shell
          if (snap.hasData && snap.data != null) {
            return FutureBuilder<void>(
              future: ensureUserDoc(), // Step 3 happens here
              builder: (context, profSnap) {
                if (profSnap.connectionState == ConnectionState.waiting) {
                  return const Scaffold(body: Center(child: CircularProgressIndicator()));
                }
                if (profSnap.hasError) {
                  return Scaffold(
                    body: Center(child: Text('Error creating user profile: ${profSnap.error}')),
                  );
                }
                return const Shell();
              },
            );
          }

          // Not signed in → show Login
          return const LoginScreen();
        },
      ),
      routes: {
        '/app': (_) => const Shell(),
        '/login': (_) => const LoginScreen(),
      },
    );
  }
}