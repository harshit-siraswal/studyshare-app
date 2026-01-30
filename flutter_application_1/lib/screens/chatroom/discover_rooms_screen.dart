import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter/services.dart';
import '../../config/theme.dart';
import '../../services/supabase_service.dart';

import '../../services/backend_api_service.dart';
import 'chatroom_screen.dart';

class DiscoverRoomsScreen extends StatefulWidget {
  final String collegeId;
  final String collegeDomain;
  final String userEmail;

  const DiscoverRoomsScreen({
    super.key,
    required this.collegeId,
    required this.collegeDomain,
    required this.userEmail,
  });

  @override
  State<DiscoverRoomsScreen> createState() => _DiscoverRoomsScreenState();
}

class _DiscoverRoomsScreenState extends State<DiscoverRoomsScreen> {
  final SupabaseService _supabaseService = SupabaseService();
  final TextEditingController _searchController = TextEditingController();
  
  List<Map<String, dynamic>> _rooms = [];
  List<Map<String, dynamic>> _filteredRooms = [];
  Set<String> _joinedRoomIds = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _supabaseService.attachContext(context);
    });
    _loadRooms();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadRooms() async {
    try {
      final rooms = await _supabaseService.getChatRooms(
        widget.userEmail,
        widget.collegeId,
      );
      final joinedIds = await _supabaseService.getUserRoomIds(widget.userEmail);
      
      // Filter strictly for public rooms
      final publicRooms = rooms.where((r) => r['is_private'] != true).toList();
      
      if (mounted) {
        setState(() {
          _rooms = publicRooms;
          _filteredRooms = publicRooms;
          _joinedRoomIds = joinedIds;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _filterRooms(String query) {
    setState(() {
      _filteredRooms = _rooms.where((room) {
        final name = room['name']?.toString().toLowerCase() ?? '';
        return name.contains(query.toLowerCase());
      }).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? Colors.black : const Color(0xFFF2F2F7);
    final cardColor = isDark ? const Color(0xFF1C1C1E) : Colors.white;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: bgColor,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_rounded, color: isDark ? Colors.white : Colors.black),
          onPressed: () => Navigator.pop(context, true), // Return true to refresh parent
        ),
        title: Text(
          'Discover Rooms',
          style: GoogleFonts.inter(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: isDark ? Colors.white : Colors.black,
          ),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.lock_open_rounded, color: isDark ? Colors.white : Colors.black),
            onPressed: _showJoinRoomDialog,
            tooltip: 'Join by Code',
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            child: TextField(
              controller: _searchController,
              onChanged: _filterRooms,
              style: TextStyle(color: isDark ? Colors.white : Colors.black),
              decoration: InputDecoration(
                hintText: 'Search rooms...',
                prefixIcon: Icon(Icons.search, color: isDark ? Colors.grey : Colors.black54),
                filled: true,
                fillColor: cardColor,
                contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 20),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: isDark ? const BorderSide(color: Colors.white24) : const BorderSide(color: Colors.black12),
                ),
              ),
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _filteredRooms.isEmpty
                    ? Center(child: Text('No public rooms found', style: TextStyle(color: isDark ? Colors.white54 : Colors.grey)))
                    : GridView.builder(
                        padding: const EdgeInsets.all(20),
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          childAspectRatio: 0.85, // Taller cards for more info
                          crossAxisSpacing: 16,
                          mainAxisSpacing: 16,
                        ),
                        itemCount: _filteredRooms.length,
                        itemBuilder: (context, index) {
                          return _buildRoomCard(_filteredRooms[index], isDark, cardColor);
                        },
                      ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showCreateRoomDialog,
        backgroundColor: AppTheme.primary,
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }

  Widget _buildRoomCard(Map<String, dynamic> room, bool isDark, Color cardColor) {
    final isJoined = _joinedRoomIds.contains(room['id']?.toString());
    final memberCount = room['members_count'] ?? 0; // Assuming backend sends this or we default to 0
    final createdAtStr = room['created_at'];
    String timeAgo = '';
    if (createdAtStr != null) {
      final created = DateTime.parse(createdAtStr);
      final diff = DateTime.now().difference(created);
      if (diff.inDays > 0) timeAgo = '${diff.inDays}d ago';
      else if (diff.inHours > 0) timeAgo = '${diff.inHours}h ago';
      else timeAgo = 'Just now';
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  room['name'] ?? 'Untitled',
                  style: GoogleFonts.inter(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.black,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (timeAgo.isNotEmpty)
                Text(
                  timeAgo,
                  style: TextStyle(fontSize: 10, color: isDark ? Colors.white38 : Colors.black38),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${memberCount} members',
            style: TextStyle(fontSize: 12, color: AppTheme.primary),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: Text(
              room['description'] ?? 'No description',
              style: TextStyle(
                fontSize: 12,
                color: isDark ? Colors.white60 : Colors.black54,
                height: 1.4,
              ),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(height: 12),

            SizedBox(
            width: double.infinity,
            height: 36,
            child: ElevatedButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => ChatRoomScreen(
                      roomId: room['id'].toString(),
                      roomName: room['name'] ?? 'Untitled',
                      description: room['description'] ?? '',
                      userEmail: widget.userEmail,
                      collegeDomain: widget.collegeDomain,
                    ),
                  ),
                ).then((_) => _loadRooms()); // Refresh on return
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: isJoined ? Colors.transparent : (isDark ? Colors.white10 : Colors.black12),
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                padding: EdgeInsets.zero,
                side: isJoined ? BorderSide(color: isDark ? Colors.greenAccent.withOpacity(0.5) : Colors.green.withOpacity(0.5)) : BorderSide.none,
              ),
              child: Text(
                isJoined ? 'Open' : 'View',
                style: TextStyle(
                  color: isJoined ? (isDark ? Colors.greenAccent : Colors.green) : (isDark ? Colors.white : Colors.black),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Removed _joinRoom as we now navigate to detail screen


  void _showJoinRoomDialog() {
     final isDark = Theme.of(context).brightness == Brightness.dark;
     final codeController = TextEditingController();
     
     showDialog(
       context: context,
       builder: (context) => AlertDialog(
         backgroundColor: isDark ? const Color(0xFF1C1C1E) : Colors.white,
         title: Text('Join Room', style: TextStyle(color: isDark ? Colors.white : Colors.black)),
         content: TextField(
           controller: codeController,
           style: TextStyle(color: isDark ? Colors.white : Colors.black),
           decoration: InputDecoration(
             hintText: 'Enter Code',
             filled: true,
             fillColor: isDark ? Colors.black45 : Colors.grey.shade100,
             border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
           ),
         ),
         actions: [
           TextButton(onPressed: ()=>Navigator.pop(context), child: const Text('Cancel')),
           TextButton(
             onPressed: () async {
                if(codeController.text.isNotEmpty) {
                    try {
                        await BackendApiService().joinChatRoom(codeController.text.trim(), widget.userEmail, widget.collegeId);
                        if(mounted) { 
                          Navigator.pop(context); 
                          _loadRooms(); 
                        }
                    } catch(e) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
                    }
                }
             }, 
             child: const Text('Join'),
           ),
         ],
       ),
     );
  }
  
  void _showCreateRoomDialog() {
      final isDark = Theme.of(context).brightness == Brightness.dark;
      final nameCtrl = TextEditingController();
      final descCtrl = TextEditingController(); // Added description controller
      bool isPrivate = false;
      
      showDialog(
       context: context,
       builder: (context) => StatefulBuilder(
         builder: (context, setDialogState) => AlertDialog(
           backgroundColor: isDark ? const Color(0xFF1C1C1E) : Colors.white,
           title: Text('Create Room', style: TextStyle(color: isDark ? Colors.white : Colors.black)),
           content: Column(
             mainAxisSize: MainAxisSize.min,
             children: [
               TextField(
                 controller: nameCtrl,
                 style: TextStyle(color: isDark ? Colors.white : Colors.black),
                 decoration: InputDecoration(
                   hintText: 'Room Name', 
                   filled: true, 
                   fillColor: isDark ? Colors.black45 : Colors.grey.shade100, 
                   border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none)
                 ),
               ),
               const SizedBox(height: 12),
               TextField( // Added Description Field
                 controller: descCtrl,
                 style: TextStyle(color: isDark ? Colors.white : Colors.black),
                 maxLines: 3,
                 decoration: InputDecoration(
                   hintText: 'Description', 
                   filled: true, 
                   fillColor: isDark ? Colors.black45 : Colors.grey.shade100, 
                   border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none)
                 ),
               ),
               const SizedBox(height: 8),
               SwitchListTile(
                 title: Text('Private', style: TextStyle(color: isDark ? Colors.white : Colors.black)),
                 value: isPrivate,
                 onChanged: (v) => setDialogState(() => isPrivate = v),
               ),
             ],
           ),
           actions: [
              TextButton(onPressed: ()=>Navigator.pop(context), child: const Text('Cancel')),
              TextButton(
                 onPressed: () async {
                    if(nameCtrl.text.isNotEmpty) {
                        try {
                           final res = await _supabaseService.createChatRoom(
                             name: nameCtrl.text, 
                             description: descCtrl.text, // Pass description
                             isPrivate: isPrivate, 
                             userEmail: widget.userEmail, 
                             collegeId: widget.collegeId
                           );
                           if(mounted) { 
                             Navigator.pop(context); 
                             _loadRooms();
                             if (res['joinCode'] != null) {
                                Clipboard.setData(ClipboardData(text: res['joinCode'].toString()));
                                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Room Created! Code copied: ${res['joinCode']}')));
                             }
                           }
                        } catch (e) {
                           ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
                        }
                    }
                 },
                 child: const Text('Create'),
              )
           ],
         ),
       ),
      );
  }
}
