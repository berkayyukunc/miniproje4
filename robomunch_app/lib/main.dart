import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:permission_handler/permission_handler.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'RoboMunch Client',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        primaryColor: const Color(0xFFE6A15C),
        fontFamily: 'Georgia',
      ),
      home: const ChatScreen(),
    );
  }
}

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  // Configurable URLs
  String localServerUrl = "http://localhost:8000";
  String cloudServerUrl = "http://13.61.176.214:8000";

  // State variables for Chat
  final TextEditingController _chatController = TextEditingController();
  final List<Map<String, String>> _chatHistory = [];
  bool _isChatLoading = false;

  // State variables for Painting
  final TextEditingController _promptController = TextEditingController();
  Uint8List? _generatedImageBytes;
  bool _isImageLoading = false;

  // State variables for Grayscale conversion/Resolution check
  bool _isProcessingCloudImage = false;

  // Speech to Text variables
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _isListening = false;
  String _lastWords = '';

  @override
  void initState() {
    super.initState();
    _initSpeech();
  }

  void _initSpeech() async {
    try {
      await _speech.initialize(
        onStatus: (val) {
          if (val == 'done' || val == 'notListening') {
            setState(() => _isListening = false);
          }
        },
        onError: (val) => debugPrint('Speech Init Error: $val'),
      );
    } catch (e) {
      debugPrint('Speech Initialize Exception: $e');
    }
  }

  // Handle Speech recording
  void _listen() async {
    if (!_isListening) {
      var status = await Permission.microphone.status;
      if (status.isDenied || status.isPermanentlyDenied) {
        status = await Permission.microphone.request();
        if (!status.isGranted) {
          _showSnackBar("Microphone permission is required for voice input");
          return;
        }
      }

      bool available = await _speech.initialize();
      if (available) {
        setState(() => _isListening = true);
        _speech.listen(
          onResult: (val) => setState(() {
            _lastWords = val.recognizedWords;
            _chatController.text = _lastWords;
          }),
        );
      }
    } else {
      setState(() => _isListening = false);
      _speech.stop();
    }
  }

  // Send message to local backend
  Future<void> _sendMessage() async {
    final text = _chatController.text.trim();
    if (text.isEmpty) return;

    setState(() {
      _chatHistory.add({"role": "user", "content": text});
      _chatController.clear();
      _isChatLoading = true;
    });

    try {
      final response = await http.post(
        Uri.parse('$localServerUrl/chat'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "message": text,
          "history": _chatHistory.sublist(0, _chatHistory.length - 1).map((m) => {
            "role": m["role"]!,
            "content": m["content"]!
          }).toList(),
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        setState(() {
          _chatHistory.add({"role": "assistant", "content": data["reply"]});
        });
      } else {
        _showSnackBar("Server returned error: ${response.statusCode}");
      }
    } catch (e) {
      _showSnackBar("Failed to connect to local server: $e");
    } finally {
      setState(() => _isChatLoading = false);
    }
  }

  // Send prompt to local backend for image generation
  Future<void> _paintImage() async {
    final prompt = _promptController.text.trim();
    if (prompt.isEmpty) {
      _showSnackBar("Please enter a prompt first!");
      return;
    }

    setState(() {
      _isImageLoading = true;
    });

    try {
      final response = await http.post(
        Uri.parse('$localServerUrl/paint'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "prompt": prompt,
          "steps": 20,
          "format": "binary",
        }),
      );

      if (response.statusCode == 200) {
        setState(() {
          _generatedImageBytes = response.bodyBytes;
        });
      } else {
        _showSnackBar("Image generation server error: ${response.statusCode}");
      }
    } catch (e) {
      _showSnackBar("Failed to connect to local server: $e");
    } finally {
      setState(() => _isImageLoading = false);
    }
  }

  // Send generated image to cloud server for grayscale conversion
  Future<void> _convertGrayscale() async {
    if (_generatedImageBytes == null) {
      _showSnackBar("No AI-generated image to convert! Generate an image first.");
      return;
    }

    setState(() {
      _isProcessingCloudImage = true;
    });

    try {
      // Create multipart request
      final uri = Uri.parse('$cloudServerUrl/convert/grayscale');
      final request = http.MultipartRequest('POST', uri);
      
      request.files.add(
        http.MultipartFile.fromBytes(
          'image',
          _generatedImageBytes!,
          filename: 'artwork.png',
        ),
      );

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        setState(() {
          _generatedImageBytes = response.bodyBytes;
        });
        _showSnackBar("Successfully converted image to grayscale!");
      } else {
        _showSnackBar("Cloud Server returned error: ${response.statusCode} - ${response.body}");
      }
    } catch (e) {
      _showSnackBar("Failed to connect to Cloud VM: $e");
    } finally {
      setState(() => _isProcessingCloudImage = false);
    }
  }

  // Get generated image's resolution from Cloud Server
  Future<void> _getResolution() async {
    if (_generatedImageBytes == null) {
      _showSnackBar("No AI-generated image to query! Generate an image first.");
      return;
    }

    setState(() {
      _isProcessingCloudImage = true;
    });

    try {
      final uri = Uri.parse('$cloudServerUrl/get/resolution');
      final request = http.MultipartRequest('POST', uri);
      
      request.files.add(
        http.MultipartFile.fromBytes(
          'image',
          _generatedImageBytes!,
          filename: 'artwork.png',
        ),
      );

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        _showResultDialog("Image Resolution", "Width: ${data['width']}px\nHeight: ${data['height']}px\nFormat: ${data['format']}");
      } else {
        _showSnackBar("Cloud Server returned error: ${response.statusCode} - ${response.body}");
      }
    } catch (e) {
      _showSnackBar("Failed to connect to Cloud VM: $e");
    } finally {
      setState(() => _isProcessingCloudImage = false);
    }
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: const TextStyle(fontFamily: 'Georgia')),
        backgroundColor: const Color(0xFF5A3825),
      ),
    );
  }

  void _showResultDialog(String title, String content) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title, style: const TextStyle(fontFamily: 'Georgia', color: Color(0xFFE6A15C))),
        content: Text(content, style: const TextStyle(fontFamily: 'Georgia', fontSize: 16)),
        backgroundColor: const Color(0xFF1C1210),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("OK", style: TextStyle(color: Color(0xFFE6A15C))),
          )
        ],
      ),
    );
  }

  // Settings configuration modal dialog
  void _openSettingsDialog() {
    final localController = TextEditingController(text: localServerUrl);
    final cloudController = TextEditingController(text: cloudServerUrl);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Connection Settings", style: TextStyle(fontFamily: 'Georgia', color: Color(0xFFE6A15C))),
        backgroundColor: const Color(0xFF1C1210),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: localController,
              decoration: const InputDecoration(
                labelText: "Localhost Backend 1 (TGI)",
                labelStyle: TextStyle(color: Color(0xFFE6A15C)),
                focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFFE6A15C))),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: cloudController,
              decoration: const InputDecoration(
                labelText: "Cloud VM Backend 2 (Django)",
                labelStyle: TextStyle(color: Color(0xFFE6A15C)),
                focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFFE6A15C))),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Cancel", style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () {
              setState(() {
                localServerUrl = localController.text.trim();
                cloudServerUrl = cloudController.text.trim();
              });
              Navigator.pop(ctx);
              _showSnackBar("Settings saved successfully!");
            },
            child: const Text("Save", style: TextStyle(color: Color(0xFFE6A15C))),
          )
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF1C1210),
              Color(0xFF5A3825),
              Color(0xFF3A2010),
            ],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // Header Row
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        const Text(
                          "ROBO ",
                          style: TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 2.0,
                          ),
                        ),
                        Text(
                          "MUNCH",
                          style: TextStyle(
                            fontSize: 26,
                            color: const Color(0xFFE6A15C),
                            fontWeight: FontWeight.bold,
                            letterSpacing: 2.0,
                          ),
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.settings, color: Color(0xFFE6A15C)),
                          onPressed: _openSettingsDialog,
                        ),
                        const SizedBox(width: 8),
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: const Color(0xFFE6A15C), width: 2.0),
                            image: const DecorationImage(
                              image: AssetImage("assets/avatar.png"),
                              fit: BoxFit.cover,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  children: [
                    // Section 1: Art Studio
                    const Center(
                      child: Text(
                        "Art Studio",
                        style: TextStyle(
                          fontSize: 18,
                          color: Color(0xFFF0DCC8),
                          letterSpacing: 1.0,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),

                    // Image Output Box
                    Center(
                      child: Container(
                        height: 320,
                        width: 320,
                        decoration: BoxDecoration(
                          color: const Color(0xFF0D0604),
                          borderRadius: BorderRadius.circular(18),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.5),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            )
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(18),
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              if (_generatedImageBytes != null)
                                Image.memory(
                                  _generatedImageBytes!,
                                  width: double.infinity,
                                  height: double.infinity,
                                  fit: BoxFit.cover,
                                )
                            else
                              const Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.palette_outlined, size: 48, color: Color(0xFF5A3825)),
                                  SizedBox(height: 8),
                                  Text(
                                    "No Artwork Paint Yet",
                                    style: TextStyle(color: Colors.grey, fontSize: 14),
                                  ),
                                ],
                              ),
                            if (_isImageLoading || _isProcessingCloudImage)
                              Container(
                                color: Colors.black.withOpacity(0.5),
                                child: const Center(
                                  child: CircularProgressIndicator(
                                    valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFE6A15C)),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Prompt Input Row
                    Container(
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF3D2215), Color(0xFF1A0C07)],
                        ),
                        borderRadius: BorderRadius.circular(32),
                        border: Border.all(color: Colors.white.withOpacity(0.1)),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                      child: Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _promptController,
                              style: const TextStyle(fontSize: 14),
                              decoration: const InputDecoration(
                                hintText: "Type your prompt here.",
                                hintStyle: TextStyle(color: Colors.grey),
                                border: InputBorder.none,
                                isDense: true,
                              ),
                            ),
                          ),
                          InkWell(
                            onTap: _isImageLoading ? null : _paintImage,
                            child: Padding(
                              padding: const EdgeInsets.all(4.0),
                              child: Image.asset(
                                "assets/paint.png",
                                width: 28,
                                height: 28,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),

                    // Colorize / Grayscale / Resolution Action Buttons
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        ElevatedButton.icon(
                          onPressed: (_isProcessingCloudImage || _generatedImageBytes == null) ? null : _convertGrayscale,
                          icon: const Icon(Icons.color_lens_outlined, size: 16),
                          label: const Text("Convert Grayscale"),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF5A3825),
                            foregroundColor: const Color(0xFFFFF2E5),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20),
                            ),
                          ),
                        ),
                        ElevatedButton.icon(
                          onPressed: (_isProcessingCloudImage || _generatedImageBytes == null) ? null : _getResolution,
                          icon: const Icon(Icons.aspect_ratio, size: 16),
                          label: const Text("Get Resolution"),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF3A2010),
                            foregroundColor: const Color(0xFFFFF2E5),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20),
                            ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 24),

                    // Section 2: Chat Studio
                    const Center(
                      child: Text(
                        "Chat Studio",
                        style: TextStyle(
                          fontSize: 18,
                          color: Color(0xFFF0DCC8),
                          letterSpacing: 1.0,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),

                    // Chat Output Box (ListView wrapper)
                    Container(
                      height: 220,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Color(0xFF3D2215), Color(0xFF1A0C07)],
                        ),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: Colors.white.withOpacity(0.07)),
                      ),
                      padding: const EdgeInsets.all(12),
                      child: _chatHistory.isEmpty
                          ? const Center(
                              child: Text(
                                "No conversation yet. Talk to RoboMunch!",
                                style: TextStyle(color: Colors.grey, fontStyle: FontStyle.italic),
                              ),
                            )
                          : ListView.builder(
                              itemCount: _chatHistory.length,
                              itemBuilder: (context, index) {
                                final message = _chatHistory[index];
                                final isUser = message["role"] == "user";
                                return Align(
                                  alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
                                  child: Container(
                                    margin: const EdgeInsets.symmetric(vertical: 4),
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                    decoration: BoxDecoration(
                                      color: isUser
                                          ? const Color(0xFFE6A15C).withOpacity(0.18)
                                          : Colors.white.withOpacity(0.06),
                                      borderRadius: BorderRadius.only(
                                        topLeft: const Radius.circular(12),
                                        topRight: const Radius.circular(12),
                                        bottomLeft: isUser ? const Radius.circular(12) : const Radius.circular(4),
                                        bottomRight: isUser ? const Radius.circular(4) : const Radius.circular(12),
                                      ),
                                    ),
                                    child: Text(
                                      "${isUser ? "YOU" : "MUNCH"}: ${message["content"]}",
                                      style: TextStyle(
                                        color: isUser ? const Color(0xFFFFF2E5) : const Color(0xFFE8C89A),
                                        fontStyle: isUser ? FontStyle.normal : FontStyle.italic,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),
                    const SizedBox(height: 12),

                    // Chat Input Bar
                    Container(
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF3D2215), Color(0xFF1A0C07)],
                        ),
                        borderRadius: BorderRadius.circular(32),
                        border: Border.all(color: Colors.white.withOpacity(0.1)),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      child: Row(
                        children: [
                          InkWell(
                            onTap: _listen,
                            child: Padding(
                              padding: const EdgeInsets.all(4.0),
                              child: Image.asset(
                                "assets/Mic.png",
                                width: 26,
                                height: 26,
                                color: _isListening ? Colors.red : null,
                              ),
                            ),
                          ),
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 8.0),
                              child: TextField(
                                controller: _chatController,
                                style: const TextStyle(fontSize: 14),
                                decoration: const InputDecoration(
                                  hintText: "Type your message here.",
                                  hintStyle: TextStyle(color: Colors.grey),
                                  border: InputBorder.none,
                                  isDense: true,
                                ),
                                onSubmitted: (_) => _sendMessage(),
                              ),
                            ),
                          ),
                          InkWell(
                            onTap: _isChatLoading ? null : _sendMessage,
                            child: Padding(
                              padding: const EdgeInsets.all(4.0),
                              child: Image.asset(
                                "assets/Send.png",
                                width: 26,
                                height: 26,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 6),

                    // Clear Chat Button
                    Center(
                      child: TextButton.icon(
                        onPressed: () {
                          setState(() {
                            _chatHistory.clear();
                          });
                        },
                        icon: const Icon(Icons.delete_outline, size: 16, color: Colors.grey),
                        label: const Text(
                          "Clear Chat",
                          style: TextStyle(color: Colors.grey, fontSize: 12),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
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
