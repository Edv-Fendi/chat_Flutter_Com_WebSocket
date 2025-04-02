import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_chat_ui/flutter_chat_ui.dart';
import 'package:flutter_chat_types/flutter_chat_types.dart' as types;
import 'package:web_socket_client/web_socket_client.dart';
import 'package:mime/mime.dart';
import 'package:open_filex/open_filex.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';

class ChatPage extends StatefulWidget {
  const ChatPage({Key? key, required this.name, required this.id})
      : super(key: key);

  final String name;
  final String id;

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final socket = WebSocket(Uri.parse('ws://127.0.0.1:8765'));
  final List<types.Message> _messages = [];
  final TextEditingController _messageController = TextEditingController();
  late types.User otherUser;
  late types.User me;

  @override
  void initState() {
    super.initState();

    me = types.User(
      id: widget.id,
      firstName: widget.name,
    );

    // Initialize otherUser with default values to avoid late initialization error
    otherUser = types.User(
      id: 'default',
      firstName: 'Other User',
    );

    socket.messages.listen((incomingMessage) {
      if (incomingMessage is String) {
        // Ensure the message is a String
        try {
          List<String> parts = incomingMessage.split(' from ');
          String jsonString = parts[0];

          Map<String, dynamic> data = jsonDecode(jsonString);
          String id = data['id'];
          String msg = data['msg'];
          String nick = data['nick'] ?? id;
          String type =
              data['type'] ?? 'text'; // Default to text if not specified

          if (id != me.id) {
            setState(() {
              otherUser = types.User(
                id: id,
                firstName: nick,
              );
            });
            onMessageReceived(msg, type);
          }
        } catch (e) {
          print("Error processing message: $e");
        }
      }
    }, onError: (error) {
      print("WebSocket error: $error");
    });
  }

  String randomString() {
    final random = Random.secure();
    final values = List<int>.generate(16, (i) => random.nextInt(255));
    return base64UrlEncode(values);
  }

  void onMessageReceived(String message, String type) {
    types.Message newMessage;

    if (type == 'image') {
      final imageMessage = types.ImageMessage(
        author: otherUser,
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        uri: '', // continua vazio
        createdAt: DateTime.now().millisecondsSinceEpoch,
        name: 'Image',
        size: 0,
        width: 0,
        height: 0,
        metadata: {
          'base64': message, // aqui vem do campo 'msg'
          'mimeType': 'image/jpeg',
        },
      );
      newMessage = imageMessage;
    } else {
      newMessage = types.TextMessage(
        author: otherUser,
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        text: message,
        createdAt: DateTime.now().millisecondsSinceEpoch,
      );
    }

    _addMessage(newMessage);
  }

  void _addMessage(types.Message message) {
    setState(() {
      _messages.insert(0, message);
    });
  }

  void _sendMessageCommon(types.Message message) {
    String msgContent;
    String type;

    if (message is types.TextMessage) {
      msgContent = message.text;
      type = 'text';
    } else if (message is types.ImageMessage) {
      msgContent = message.metadata?['base64'] ?? '';
      type = 'image';
    } else if (message is types.FileMessage) {
      msgContent = message.uri;
      type = 'file';
    } else {
      print("Unsupported message type");
      return;
    }

    var payload = {
      'id': me.id,
      'msg': msgContent,
      'nick': me.firstName,
      'timestamp': DateTime.now().millisecondsSinceEpoch.toString(),
      'type': type,
    };

    socket.send(json.encode(payload));
    _addMessage(message);
  }

  void _handleSendPressed(types.PartialText message) {
    final textMessage = types.TextMessage(
      author: me,
      createdAt: DateTime.now().millisecondsSinceEpoch,
      id: randomString(),
      text: message.text,
      metadata: {
        'senderName': me.firstName,
      },
    );
    _sendMessageCommon(textMessage);
  }

  void _handleAttachmentPressed() {
    showModalBottomSheet<void>(
      context: context,
      builder: (BuildContext context) => SafeArea(
        child: SizedBox(
          height: 144,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  _handleImageSelection();
                },
                child: const Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Text('Foto'),
                ),
              ),
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  _handleFileSelection();
                },
                child: const Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Text('Arquivo'),
                ),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Text('Cancelar'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _handleFileSelection() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.any,
    );

    if (result != null && result.files.single.path != null) {
      final message = types.FileMessage(
        author: me,
        createdAt: DateTime.now().millisecondsSinceEpoch,
        id: randomString(),
        mimeType: lookupMimeType(result.files.single.path!) ??
            'application/octet-stream',
        name: result.files.single.name,
        size: result.files.single.size,
        uri: result.files.single.path!,
      );

      _sendMessageCommon(message);
    }
  }

  void _handleImageSelection() async {
    final result = await ImagePicker().pickImage(
      imageQuality: 70,
      maxWidth: 1440,
      source: ImageSource.gallery,
    );

    if (result != null) {
      final bytes = await result.readAsBytes();
      final image = await decodeImageFromList(bytes);
      final base64String = base64Encode(bytes); // Codifica em base64
      final mimeType =
          lookupMimeType(result.path!) ?? 'image/jpeg'; // Detecta o tipo

      final message = types.ImageMessage(
        author: me,
        createdAt: DateTime.now().millisecondsSinceEpoch,
        height: image.height.toDouble(),
        id: randomString(),
        name: result.name,
        size: bytes.length,
        uri: '', // URI vazio
        width: image.width.toDouble(),
        metadata: {
          'base64': base64Encode(bytes),
          'mimeType': mimeType,
        },
      );

      _sendMessageCommon(message);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Seu Chat: ${widget.name}',
            style: const TextStyle(
              color: Colors.white,
            )),
        backgroundColor: Colors.deepPurple,
      ),
      body: Chat(
          onAttachmentPressed: _handleAttachmentPressed,
          messages: _messages,
          user: me,
          showUserAvatars: true,
          showUserNames: true,
          onSendPressed: _handleSendPressed,
          imageMessageBuilder: (types.ImageMessage message,
              {required int messageWidth}) {
            final base64String = message.metadata?['base64'];
            if (base64String != null) {
              try {
                final bytes = base64Decode(base64String);
                return Image.memory(
                  bytes,
                  width: messageWidth.toDouble(),
                  fit: BoxFit.cover,
                );
              } catch (e) {
                return const Text('Erro ao decodificar imagem');
              }
            } else {
              // Caso não haja base64, exibe uma imagem padrão ou um placeholder
              return const Text('Imagem não disponível');
            }
          }),
    );
  }

  @override
  void dispose() {
    _messageController.dispose();
    socket.close();
    super.dispose();
  }
}
