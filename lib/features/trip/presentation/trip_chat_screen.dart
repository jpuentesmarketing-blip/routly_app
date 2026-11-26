import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class TripChatScreen extends StatefulWidget {
  final String tripId;
  final String tripTitle;
  final String otherUserId;
  final String otherUserName;

  const TripChatScreen({
    super.key,
    required this.tripId,
    required this.tripTitle,
    required this.otherUserId,
    required this.otherUserName,
  });

  @override
  State<TripChatScreen> createState() => _TripChatScreenState();
}

class _TripChatScreenState extends State<TripChatScreen> {
  final SupabaseClient _supabase = Supabase.instance.client;
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  List<dynamic> _messages = [];
  bool _isLoading = true;
  bool _isSending = false;
  RealtimeChannel? _channel;

  String get _currentUserId => _supabase.auth.currentUser?.id ?? '';

  @override
  void initState() {
    super.initState();
    _loadMessages();
    _subscribeToMessages();
  }

  Future<void> _loadMessages() async {
    if (_currentUserId.isEmpty) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    try {
      final response = await _supabase
          .from('trip_messages')
          .select()
          .eq('trip_id', widget.tripId)
          .order('created_at', ascending: true);

      final List<dynamic> filtered = [];
      for (final item in response) {
        final sender = item['sender_id']?.toString() ?? '';
        final receiver = item['receiver_id']?.toString() ?? '';
        final isBetweenPair =
            (sender == _currentUserId && receiver == widget.otherUserId) ||
            (sender == widget.otherUserId && receiver == _currentUserId);
        if (isBetweenPair) {
          filtered.add(Map<String, dynamic>.from(item));
        }
      }

      if (!mounted) return;
      setState(() {
        _messages = filtered;
        _isLoading = false;
      });
      _scrollToBottom();
    } catch (e) {
      debugPrint('Error al cargar mensajes del viaje: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _subscribeToMessages() {
    _channel = _supabase
        .channel('trip_chat_${widget.tripId}_$_currentUserId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'trip_messages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'trip_id',
            value: widget.tripId,
          ),
          callback: (payload) {
            final newRow = payload.newRecord;
            if (newRow.isEmpty) return;

            final sender = newRow['sender_id']?.toString() ?? '';
            final receiver = newRow['receiver_id']?.toString() ?? '';
            final isBetweenPair =
                (sender == _currentUserId && receiver == widget.otherUserId) ||
                (sender == widget.otherUserId && receiver == _currentUserId);

            if (!isBetweenPair || !mounted) return;

            final exists = _messages.any(
              (m) => m['id']?.toString() == newRow['id']?.toString(),
            );
            if (!exists) {
              setState(() {
                _messages.add(Map<String, dynamic>.from(newRow));
              });
              _scrollToBottom();
            }
          },
        )
        .subscribe();
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty || _isSending || _currentUserId.isEmpty) return;

    setState(() => _isSending = true);
    _messageController.clear();

    try {
      final inserted = await _supabase
          .from('trip_messages')
          .insert({
            'trip_id': widget.tripId,
            'sender_id': _currentUserId,
            'receiver_id': widget.otherUserId,
            'message': text,
          })
          .select()
          .maybeSingle();

      if (inserted != null && mounted) {
        final exists = _messages.any(
          (m) => m['id']?.toString() == inserted['id']?.toString(),
        );
        if (!exists) {
          setState(() {
            _messages.add(Map<String, dynamic>.from(inserted));
          });
          _scrollToBottom();
        }
      }
    } catch (e) {
      if (mounted) {
        _messageController.text = text;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('No se pudo enviar el mensaje: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSending = false);
      }
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent + 80,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  String _formatHour(String? iso) {
    if (iso == null || iso.isEmpty) return '';
    try {
      final dt = DateTime.parse(iso).toLocal();
      final h = dt.hour.toString().padLeft(2, '0');
      final m = dt.minute.toString().padLeft(2, '0');
      return '$h:$m';
    } catch (_) {
      return '';
    }
  }

  @override
  void dispose() {
    if (_channel != null) {
      _supabase.removeChannel(_channel!);
    }
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.otherUserName,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            Text(
              widget.tripTitle,
              style: const TextStyle(fontSize: 12, color: Colors.white70),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: Colors.teal),
                  )
                : _messages.isEmpty
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24.0),
                      child: Text(
                        'Aún no hay mensajes en este viaje.\nCoordina aquí el punto de encuentro o detalles del trayecto.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey),
                      ),
                    ),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(16),
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
                      final msg = _messages[index] as Map;
                      final isMine =
                          msg['sender_id']?.toString() == _currentUserId;
                      final content = (msg['message'] ?? '').toString();
                      final hour = _formatHour(msg['created_at']?.toString());

                      return Align(
                        alignment: isMine
                            ? Alignment.centerRight
                            : Alignment.centerLeft,
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                          constraints: BoxConstraints(
                            maxWidth: MediaQuery.of(context).size.width * 0.76,
                          ),
                          decoration: BoxDecoration(
                            color: isMine ? Colors.teal : Colors.grey.shade200,
                            borderRadius: BorderRadius.only(
                              topLeft: const Radius.circular(14),
                              topRight: const Radius.circular(14),
                              bottomLeft: Radius.circular(isMine ? 14 : 2),
                              bottomRight: Radius.circular(isMine ? 2 : 14),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                content,
                                style: TextStyle(
                                  color: isMine ? Colors.white : Colors.black87,
                                  fontSize: 14,
                                ),
                              ),
                              if (hour.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text(
                                  hour,
                                  style: TextStyle(
                                    color: isMine
                                        ? Colors.white70
                                        : Colors.grey.shade600,
                                    fontSize: 10,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
          SafeArea(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border(top: BorderSide(color: Colors.grey.shade300)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _messageController,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _sendMessage(),
                      decoration: InputDecoration(
                        hintText: 'Escribe un mensaje...',
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                        ),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  CircleAvatar(
                    backgroundColor: Colors.teal,
                    child: IconButton(
                      icon: _isSending
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.send, color: Colors.white, size: 18),
                      onPressed: _isSending ? null : _sendMessage,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}