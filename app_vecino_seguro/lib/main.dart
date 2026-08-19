import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

void main() {
  runApp(const VecinoSeguroApp());
}

class VecinoSeguroApp extends StatelessWidget {
  const VecinoSeguroApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Vecino Seguro',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const APIConnectionScreen(),
    );
  }
}

class APIConnectionScreen extends StatefulWidget {
  const APIConnectionScreen({super.key});

  @override
  State<APIConnectionScreen> createState() => _APIConnectionScreenState();
}

class _APIConnectionScreenState extends State<APIConnectionScreen> {
  String _apiResponse = "Presiona el botón para consultar tu Backend";
  bool _isLoading = false;


  final String apiUrl = 'http://10.0.2.2:3333/api/usuarios/token-prueba'; 
  
 
  final String miToken = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpZF91c3VhcmlvIjoxLCJpZF9jb211bmlkYWQiOjEsInJvbCI6IlZFQ0lOT19BQ1RJVk8iLCJpYXQiOjE3ODY5NDQ0MTQsImV4cCI6MTc4Njk1ODgxNH0.2uMcEdDJQ3PiFowEEgIW3YmgGSaRVnPBEu6ii1ohdJ4"; 

  Future<void> _fetchDataFromBackend() async {
    setState(() {
      _isLoading = true;
      _apiResponse = "Conectando con Node.js en localhost:3333...";
    });

    try {
      final response = await http.post( // Cambiado a POST por si tu ruta lo requiere
        Uri.parse(apiUrl),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $miToken', 
        },
        // Si tu endpoint requiere body, envíalo, si no, déjalo vacío
        body: jsonEncode({"id_usuario": 1, "id_comunidad": 1}),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        setState(() {
          _apiResponse = "¡ÉXITO! Status: ${response.statusCode}\n\nRespuesta:\n${response.body}";
        });
      } else {
        setState(() {
          _apiResponse = "ERROR: Status ${response.statusCode}\n\n${response.body}";
        });
      }
    } catch (e) {
      setState(() {
        _apiResponse = "Fallo de conexión: $e";
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: const Text('Vecino Seguro - Prueba de API'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              const Icon(Icons.security, size: 60, color: Colors.deepPurple),
              const SizedBox(height: 10),
              const Text(
                'Estado de la Conexión:',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
              ),
              const SizedBox(height: 10),
              // 🔥 EL ARREGLO VISUAL: Ahora el contenedor se expande y permite hacer scroll
              Expanded(
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey[200],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: SingleChildScrollView(
                    child: Text(
                      _apiResponse,
                      textAlign: TextAlign.left,
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: _isLoading ? null : _fetchDataFromBackend,
                icon: _isLoading 
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) 
                    : const Icon(Icons.cloud_sync),
                label: const Text('Probar Conexión al Backend'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  textStyle: const TextStyle(fontSize: 16),
                ),
              ),
              const SizedBox(height: 10),
            ],
          ),
        ),
      ),
    );
  }
}