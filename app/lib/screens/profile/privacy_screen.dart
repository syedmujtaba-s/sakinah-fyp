import 'package:flutter/material.dart';

class PrivacyScreen extends StatelessWidget {
  const PrivacyScreen({super.key});

  static final List<Map<String, dynamic>> _content = [
    {
      'heading': "Privacy Policy",
      'text': "At Sakinah, your privacy is our priority. This Privacy Policy describes how we collect, use, and protect your information."
    },
    {
      'heading': "1. Information We Collect",
      'text': "We collect your name, email address, and optional profile photo when you create an account. We also store your journal entries and mood data securely."
    },
    {
      'heading': "2. How We Use Your Information",
      'text': "We use your data to personalize your experience, provide Seerah guidance, and improve our app."
    },
    {
      'heading': "3. Data Security",
      'text': "We use industry-standard security measures and rely on Google Firebase to protect your information."
    },
    {
      'heading': "4. Your Choices",
      'text': "You can view and update your profile information in the app or delete your account by contacting support."
    },
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text("Privacy Policy", style: TextStyle(color: Color(0xFF15803D), fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black87),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: ListView.separated(
        padding: const EdgeInsets.all(20),
        itemCount: _content.length,
        separatorBuilder: (_, __) => const SizedBox(height: 20),
        itemBuilder: (context, index) {
          final section = _content[index];
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                section['heading'],
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF15803D)),
              ),
              const SizedBox(height: 8),
              Text(
                section['text'],
                style: const TextStyle(fontSize: 14, color: Colors.black87, height: 1.5),
              ),
            ],
          );
        },
      ),
    );
  }
}