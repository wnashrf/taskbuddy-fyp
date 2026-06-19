import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'login_screen.dart';

class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final _formKey = GlobalKey<FormState>();

  final emailC = TextEditingController();
  final nameC = TextEditingController();
  final passC = TextEditingController();
  final confirmPassC = TextEditingController();

  bool showPass = false;
  bool showConfirmPass = false;
  bool loading = false;

  @override
  void dispose() {
    emailC.dispose();
    nameC.dispose();
    passC.dispose();
    confirmPassC.dispose();
    super.dispose();
  }

  Future<void> register() async {
    if (!_formKey.currentState!.validate()) return;
    if (passC.text.trim() != confirmPassC.text.trim()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Passwords do not match")),
      );
      return;
    }

    setState(() => loading = true);

    try {
      final userCred = await FirebaseAuth.instance
          .createUserWithEmailAndPassword(
        email: emailC.text.trim(),
        password: passC.text.trim(),
      );

      await FirebaseFirestore.instance
          .collection("users")
          .doc(userCred.user!.uid)
          .set({
        "displayName": nameC.text.trim(),
        "email": emailC.text.trim(),
        "createdAt": FieldValue.serverTimestamp(),
        "lastSeen": FieldValue.serverTimestamp(),
        "role": "student",
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Account created successfully!")),
      );

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const LoginScreen()),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Signup failed: $e")),
      );
    } finally {
      setState(() => loading = false);
    }
  }

  InputDecoration fieldStyle(String hint, IconData icon) {
    return InputDecoration(
      hintText: hint,
      hintStyle: GoogleFonts.inter(
        color: Colors.black54,
      ),
      filled: true,
      fillColor: const Color(0xFFF5F5F7),
      prefixIcon: Icon(icon, color: Colors.black54),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF2ECFF),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 30),
          child: Column(
            children: [
              // Title
              Text(
                "Create Account",
                style: GoogleFonts.inter(
                  fontSize: 30,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF2A2A2A),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                "Join TaskBuddy and start organizing!",
                style: GoogleFonts.inter(
                  fontSize: 15,
                  color: Colors.black54,
                ),
              ),
              const SizedBox(height: 35),

              Form(
                key: _formKey,
                child: Column(
                  children: [
                    // name
                    TextFormField(
                      controller: nameC,
                      decoration: fieldStyle("Full Name", Icons.person),
                      validator: (v) =>
                      v == null || v.isEmpty ? "Enter your name" : null,
                    ),
                    const SizedBox(height: 18),

                    // email
                    TextFormField(
                      controller: emailC,
                      decoration: fieldStyle("Email Address", Icons.email),
                      validator: (v) =>
                      v == null || v.isEmpty ? "Enter your email" : null,
                    ),
                    const SizedBox(height: 18),

                    // password
                    TextFormField(
                      controller: passC,
                      obscureText: !showPass,
                      decoration: fieldStyle("Password", Icons.lock).copyWith(
                        suffixIcon: IconButton(
                          icon: Icon(
                            showPass
                                ? Icons.visibility
                                : Icons.visibility_off,
                            color: Colors.black54,
                          ),
                          onPressed: () =>
                              setState(() => showPass = !showPass),
                        ),
                      ),
                      validator: (v) => v != null && v.length < 6
                          ? "Password must be at least 6 characters"
                          : null,
                    ),
                    const SizedBox(height: 18),

                    // confirm password
                    TextFormField(
                      controller: confirmPassC,
                      obscureText: !showConfirmPass,
                      decoration: fieldStyle(
                          "Confirm Password", Icons.lock).copyWith(
                        suffixIcon: IconButton(
                          icon: Icon(
                            showConfirmPass
                                ? Icons.visibility
                                : Icons.visibility_off,
                            color: Colors.black54,
                          ),
                          onPressed: () =>
                              setState(() => showConfirmPass = !showConfirmPass),
                        ),
                      ),
                      validator: (v) =>
                      v == null || v.isEmpty ? "Confirm your password" : null,
                    ),

                    const SizedBox(height: 30),

                    // signup button
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton(
                        onPressed: loading ? null : register,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF4C4CFF),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: loading
                            ? const CircularProgressIndicator(color: Colors.white)
                            : Text(
                          "Sign Up",
                          style: GoogleFonts.inter(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 20),

                    // login text
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          "Already have an account? ",
                          style: GoogleFonts.inter(color: Colors.black87),
                        ),
                        GestureDetector(
                          onTap: () {
                            Navigator.pushReplacement(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => const LoginScreen()),
                            );
                          },
                          child: Text(
                            "Login",
                            style: GoogleFonts.inter(
                                color: const Color(0xFF4C4CFF),
                                fontWeight: FontWeight.bold,
                                decoration: TextDecoration.underline),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
