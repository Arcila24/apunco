import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'screens/login_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Configuración inicial de Supabase
  await Supabase.initialize(
    url: 'https://qejemnblrhlpjnqjsukd.supabase.co',
    anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InFlamVtbmJscmhscGpucWpzdWtkIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NDM3MDYzMDEsImV4cCI6MjA1OTI4MjMwMX0.eZa3KVhZhPFNkkn-_Due38KEYwd2MGdoa-3hr4iYPWs',
  );
  
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: "ApunCo",
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: LoginScreen(),
    );
  }
}
  
  