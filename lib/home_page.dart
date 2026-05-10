import 'dart:io';
import 'dart:math';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:nevergiveup/text_form_widget.dart';
import 'package:path_provider/path_provider.dart';

class HomePage extends StatefulWidget {
  @override
  State<StatefulWidget> createState() {
    return _homePageState();
  }
}

class _homePageState extends State<HomePage> {
  final ImagePicker _picker=ImagePicker();
  File?_imageFile;

  Future<File?> _pickFile(ImageSource source) async {
    // 1. Pick the file
    final XFile? pickedFile = await _picker.pickImage(
      source: source,
      imageQuality: 80,
    );

    // 2. Check for null immediately to prevent errors
    if (pickedFile == null) return null;

    // 3. Update the UI state
    setState(() {
      _imageFile = File(pickedFile.path);
    });

    // 4. Prepare the permanent save location
    final Directory appDir = await getApplicationCacheDirectory();
    final String filename = "IMG_${DateTime.now().millisecondsSinceEpoch}.jpg";
    final String savePath = "${appDir.path}/$filename";

    // 5. Use copy (async) instead of copySync for better performance
    final File savedImage = await File(pickedFile.path).copy(savePath);

    return savedImage;
  }

  void _showPickerOptions(){
    showModalBottomSheet(context: context, builder: (context){
      return SafeArea(child: Wrap(
        children: [
          ListTile(
            leading: const Icon(Icons.photo_library),
            title: const Text('Gallery'),
            onTap: (){
              Navigator.pop(context);
              _pickFile(ImageSource.gallery);

            },
          ),
          ListTile(
            leading: const Icon(Icons.camera_alt),
            title: const Text('Camera'),
            onTap: (){
              Navigator.pop(context);
              _pickFile(ImageSource.camera);

            },

          )
        ],
      ));
    });
  }

  @override
  void initState() {
    // TODO: implement initState
    super.initState();
  }

  int count = 0;
  // bool isClicked=false;
  bool isEnabled = false;
  void _increment() {
    setState(() {
      count++;
      isEnabled = true;
    });
  }

  void _x() {
    setState(() {
      // isClicked=true;
    });
  }

  TextEditingController email_address = TextEditingController();
  TextEditingController password = TextEditingController();
  void _checkLogin() {
    print(email_address.text);
    print(password.text);
  }

  @override
  Widget build(BuildContext context) {
    final _formKey = GlobalKey<FormState>();
    return Scaffold(
      appBar: AppBar(backgroundColor: Colors.lightGreen, title: Text('Hello')),
      body: Form(
        key: _formKey,
        child: Column(
          children: [
            false ? Text('Clicked') : Text('Not clicked'),
            TextFormWidget(
              controller: email_address,
              hint: 'Email Address',
              prefix: Icons.email_outlined,
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Email cannot be empty';
                }
                if (value.length < 12) {
                  return 'The length must be 12';
                }
                return null;
              },
            ),
            SizedBox(),
            TextFormWidget(
              controller: password,
              obscureText: true,
              hint: 'Password',
              prefix: Icons.lock_outline,
              suffix: Icons.visibility,
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Please enter your password';
                }
                if (value.length < 6) {
                  return 'Password must be at least 6 characters';
                }
                return null; // Return null if the input is valid
              },
            ),
            SizedBox(height: 10),
            // Displaying the image
            Container(
              height: 200, // Give it a fixed height or it might vanish
              width: double.infinity,
              margin: EdgeInsets.symmetric(vertical: 20),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey),
                borderRadius: BorderRadius.circular(10),
              ),
              // FIX: Access selected_file directly, not via 'widget'
              child: _imageFile == null
                  ? Center(child: Text('No selected Image'))
                  : ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Image.file(_imageFile!, fit: BoxFit.cover),
                    ),
            ),

            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor:
                      Colors.blueAccent, // Solid modern primary color
                  foregroundColor: Colors.white, // Text color
                  elevation: 2, // Subtle shadow
                  shape: StadiumBorder(), // Makes it a "pill" shape
                  padding: EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                ),
                onPressed: () {
                  if (_formKey.currentState!.validate()) {
                    print("Form is valid!");
                  }
                },
                child: Text(
                  'Log in',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.1,
                  ),
                ),
              ),
            ),
            SizedBox(height: 10),
            ElevatedButton(onPressed: _showPickerOptions, child: Icon(Icons.camera)),
          ],
        ),
      ),
    );
  }
}
