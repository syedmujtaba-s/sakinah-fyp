import 'package:flutter/material.dart';

class CustomTextField extends StatelessWidget {
  final String label;
  final String hint;
  final TextEditingController controller;
  final String? Function(String?)? validator;
  final bool isPassword;
  final bool obscure;
  final VoidCallback? toggleCallback;
  final String? helperText;
  final bool isEmail;
  final bool isEmailValid;

  const CustomTextField({
    super.key,
    required this.label,
    required this.hint,
    required this.controller,
    this.validator,
    this.isPassword = false,
    this.obscure = false,
    this.toggleCallback,
    this.helperText,
    this.isEmail = false,
    this.isEmailValid = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: Colors.black87),
        ),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          obscureText: obscure,
          validator: validator,
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 14),
            helperText: helperText,
            helperMaxLines: 2,
            // Allow validation error text to wrap to multiple lines so it's fully visible
            errorMaxLines: 2,
            filled: true,
            fillColor: const Color(0xFFF3F4F6),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            suffixIcon: isPassword
                ? IconButton(
                    icon: Icon(obscure ? Icons.visibility_off : Icons.visibility, color: Colors.grey),
                    onPressed: toggleCallback,
                  )
                : (isEmail && controller.text.isNotEmpty)
                    ? Icon(
                        isEmailValid ? Icons.check_circle : Icons.cancel,
                        color: isEmailValid ? Colors.green : Colors.red,
                      )
                    : null,
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}