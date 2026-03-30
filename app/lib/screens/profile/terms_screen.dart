import 'package:flutter/material.dart';

class TermsScreen extends StatelessWidget {
  const TermsScreen({super.key});

  static final List<Map<String, dynamic>> _content = [
    {
      'heading': "Welcome to Sakinah!",
      'text': "Please read these Terms of Use ('Terms') carefully before using the Sakinah application operated by us."
    },
    {
      'heading': "1. Acceptance of Terms",
      'text': "By accessing or using our Service, you agree to be bound by these Terms. If you disagree with any part of the terms, you may not access the Service."
    },
    {
      'heading': "2. User Responsibilities",
      'text': "You must provide accurate information and keep your account secure. You agree not to use the Service for any unlawful purpose."
    },
    {
      'heading': "3. Intellectual Property",
      'text': "The Service and its original content, features, and functionality are and will remain the exclusive property of Sakinah."
    },
    {
      'heading': "4. Termination",
      'text': "We may terminate or suspend your account immediately if you breach the Terms."
    },
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text("Terms of Use", style: TextStyle(color: Color(0xFF15803D), fontWeight: FontWeight.bold)),
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