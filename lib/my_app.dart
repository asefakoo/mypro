import 'package:flutter/material.dart';
import 'package:nevergiveup/splash.dart';



class MyApp extends StatelessWidget{
   MyApp({super.key});

  @override
  Widget build(BuildContext context) {

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'burka.com',
      home:  VideoSplashScreen(),
    );

  }//constructor


}

