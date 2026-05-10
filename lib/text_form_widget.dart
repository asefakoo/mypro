import 'package:flutter/material.dart';

class TextFormWidget extends StatefulWidget {
  final TextEditingController controller;
  final String hint;
  final IconData prefix;
  final IconData? suffix;
  final bool obscureText;
  final String? Function(String?)? validator;
  const TextFormWidget({
    super.key,
    required this.controller,
    required this.hint,
    this.obscureText = false,
    required this.prefix,
    this.suffix,
    this.validator,
  });

  @override
  State<TextFormWidget> createState() => _TextFormWidgetState();
}

class _TextFormWidgetState extends State<TextFormWidget> {
  late bool _hidden;
  @override
  void initState() {
    super.initState();
    _hidden = widget.obscureText;
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12.0),
      child: TextFormField(
        controller: widget.controller,
        validator: widget.validator,
        obscureText: _hidden,
        decoration: InputDecoration(
          prefixIcon: Icon(widget.prefix),
          suffixIcon: widget.suffix != null
              ? IconButton(
                  onPressed: () {
                    setState(() {
                      _hidden = !_hidden;
                    });
                  },
                  icon: Icon(_hidden ? widget.suffix : Icons.visibility_off),
                )
              : null,
          hint: Text(widget.hint),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        ),
      ),
    );
  }
}
