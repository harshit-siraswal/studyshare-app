import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter/services.dart';
import '../../config/theme.dart';
import '../../services/supabase_service.dart';

import '../../services/backend_api_service.dart';
import '../../widgets/advanced_search_bar.dart';
import '../../widgets/room_card.dart';
import '../common/search_screen.dart';

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
  
  List<Map<String, dynamic>> _rooms = [];
  bool _isLoading = true;
  
  bool get _isReadOnly {
    final email = widget.userEmail;
    final domain = widget.collegeDomain;
    if (domain.isEmpty) return true;
    return !email.endsWith(domain);
  }

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
    super.dispose();
  }

  Future<void> _loadRooms() async {
    try {
      final rooms = await _supabaseService.getChatRooms(
        widget.userEmail,
        widget.collegeId,
      );
      final joinedIds = await _supabaseService.getUserRoomIds(widget.userEmail);
      
      // Show only public rooms that the user hasn't joined yet
      final publicRooms = rooms.where((r) {
        final isPrivate = r['is_private'] == true;
        final roomId = r['id'];
        return !isPrivate && roomId != null && !joinedIds.contains(roomId.toString());
      }).toList();

      if (mounted) {
        setState(() {
          _rooms = publicRooms;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
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
          if (!_isReadOnly)
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
            child: AdvancedSearchBar(
              onTap: () {
                 Navigator.of(context).push(
                   PageRouteBuilder(
                     transitionDuration: const Duration(milliseconds: 500),
                     pageBuilder: (context, animation, secondaryAnimation) {
                       return FadeTransition(
                         opacity: animation,
                         child: SearchScreen(
                           allRooms: _rooms,
                           userEmail: widget.userEmail,
                           collegeId: widget.collegeId,
                           collegeDomain: widget.collegeDomain,
                         ),
                       );
                     },
                   ),
                 ).then((_) {
                   // Optional: Reload rooms explicitly if needed
                   // _loadRooms();
                 });
              },
            ),
          ),

          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _rooms.isEmpty
                    ? Center(child: Text('No public rooms found', style: TextStyle(color: isDark ? Colors.white54 : Colors.grey)))
                    : GridView.builder(
                        padding: const EdgeInsets.fromLTRB(20, 20, 20, 120),
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          childAspectRatio: 0.85, // Adjusted for RoomCard content
                          crossAxisSpacing: 16,
                          mainAxisSpacing: 16,
                        ),
                        itemCount: _rooms.length,
                        itemBuilder: (context, index) {
                          return RoomCard(
                            room: _rooms[index],
                            userEmail: widget.userEmail,
                            collegeDomain: widget.collegeDomain,
                            onReturn: _loadRooms,
                          );
                        },
                      ),
          ),
        ],
      ),
      floatingActionButton: _isReadOnly
          ? null
          : FloatingActionButton(
              heroTag: 'fab_main',
              onPressed: _showCreateRoomDialog,
              backgroundColor: AppTheme.primary,
              child: const Icon(Icons.add, color: Colors.white),
            ),
    );
  }



  void _showJoinRoomDialog() {
     if (_isReadOnly) {
       ScaffoldMessenger.of(context).showSnackBar(
         const SnackBar(content: Text('Read-only access. Use your college email to join rooms.')),
       );
       return;
     }
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
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
                        }
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
      if (_isReadOnly) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Read-only access. Use your college email to create rooms.')),
        );
        return;
      }
      final isDark = Theme.of(context).brightness == Brightness.dark;
      final nameCtrl = TextEditingController();
      final descCtrl = TextEditingController();
      final tagCtrl = TextEditingController();
      List<String> selectedTags = [];
      bool isPrivate = false;
      
      showDialog(
       context: context,
       builder: (context) => StatefulBuilder(
         builder: (context, setDialogState) => AlertDialog(
           backgroundColor: isDark ? const Color(0xFF1C1C1E) : Colors.white,
           title: Row(
             mainAxisAlignment: MainAxisAlignment.spaceBetween,
             children: [
               Text('Create Room', style: TextStyle(color: isDark ? Colors.white : Colors.black)),
               IconButton(
                 icon: Icon(Icons.info_outline_rounded, size: 20, color: isDark ? Colors.white70 : Colors.black54),
                 onPressed: () {
                   showDialog(
                     context: context,
                     builder: (ctx) => AlertDialog(
                       backgroundColor: isDark ? const Color(0xFF2C2C2E) : Colors.white,
                       title: Text('About Tags', style: TextStyle(color: isDark ? Colors.white : Colors.black)),
                       content: Text(
                         'Tags help other students find your room.\n\nAdd at least one tag like #placement, #hackathon, #dsa, etc.\n\nTags will be displayed on the room card.',
                         style: TextStyle(color: isDark ? Colors.white70 : Colors.black87),
                       ),
                       actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Got it'))],
                     ),
                   );
                 },
               ),
             ],
           ),
           content: SizedBox(
             width: double.maxFinite,
             child: SingleChildScrollView(
               child: Column(
                 mainAxisSize: MainAxisSize.min,
                 crossAxisAlignment: CrossAxisAlignment.start,
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
                   TextField(
                     controller: descCtrl,
                     style: TextStyle(color: isDark ? Colors.white : Colors.black),
                     maxLines: 2,
                     decoration: InputDecoration(
                       hintText: 'Description', 
                       filled: true, 
                       fillColor: isDark ? Colors.black45 : Colors.grey.shade100, 
                       border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none)
                     ),
                   ),
                   const SizedBox(height: 16),
                   
                   // TAGS SECTION
                   // TAGS SECTION
                   Text('Tags (Required)', style: TextStyle(color: isDark ? Colors.white70 : Colors.black54, fontSize: 13, fontWeight: FontWeight.bold)),
                   const SizedBox(height: 8),
                   Row(
                     children: [
                       Expanded(
                         child: TextField(
                           controller: tagCtrl,
                           style: TextStyle(color: isDark ? Colors.white : Colors.black),
                           decoration: InputDecoration(
                             hintText: 'Add a tag (e.g. #dsa)', 
                             isDense: true,
                             filled: true, 
                             fillColor: isDark ? Colors.black45 : Colors.grey.shade100, 
                             border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none)
                           ),
                           onSubmitted: (val) {
                             if (val.trim().isNotEmpty) {
                               setDialogState(() {
                                 selectedTags.add(val.trim().startsWith('#') ? val.trim() : '#${val.trim()}');
                                 tagCtrl.clear();
                               });
                             }
                           },
                         ),
                       ),
                       IconButton(
                         icon: const Icon(Icons.add_circle_outline),
                         color: AppTheme.primary,
                         onPressed: () {
                           if (tagCtrl.text.trim().isNotEmpty) {
                             setDialogState(() {
                               selectedTags.add(tagCtrl.text.trim().startsWith('#') ? tagCtrl.text.trim() : '#${tagCtrl.text.trim()}');
                               tagCtrl.clear();
                             });
                           }
                         },
                       ),
                     ],
                   ),
                   const SizedBox(height: 8),
                   Wrap(
                     spacing: 8,
                     runSpacing: 4,
                     children: [
                       ...selectedTags.map((tag) => Chip(
                         label: Text(tag, style: const TextStyle(fontSize: 12)),
                         onDeleted: () => setDialogState(() => selectedTags.remove(tag)),
                         backgroundColor: AppTheme.primary.withValues(alpha: 0.1),
                         deleteIconColor: AppTheme.primary,
                         side: BorderSide.none,
                         shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                       )),
                       if (selectedTags.isEmpty)
                         Padding(
                           padding: const EdgeInsets.symmetric(vertical: 4),
                           child: Text('Suggestions: ', style: TextStyle(color: isDark ? Colors.white54 : Colors.grey, fontSize: 12)),
                         ),
                       if (selectedTags.isEmpty) ...['#placement', '#hackathon', '#dsa'].map((t) => 
                         GestureDetector(
                           onTap: () => setDialogState(() => selectedTags.add(t)),
                           child: Container(
                             margin: const EdgeInsets.only(right: 8),
                             padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                             decoration: BoxDecoration(
                               color: isDark ? Colors.white10 : Colors.grey.shade200,
                               borderRadius: BorderRadius.circular(12),
                             ),
                             child: Text(t, style: TextStyle(color: isDark ? Colors.white70 : Colors.black87, fontSize: 12)),
                           ),
                         )
                       ),
                     ],
                   ),
                   const SizedBox(height: 12),

                   Text('Visibility', style: TextStyle(color: isDark ? Colors.white70 : Colors.black54, fontSize: 13, fontWeight: FontWeight.bold)),
                   const SizedBox(height: 8),
                   Row(
                     children: [
                       ChoiceChip(
                         label: const Text('Public'),
                         selected: !isPrivate,
                         onSelected: (selected) {
                           if (selected) setDialogState(() => isPrivate = false);
                         },
                         selectedColor: AppTheme.primary,
                         labelStyle: TextStyle(
                           color: !isPrivate ? Colors.white : (isDark ? Colors.white70 : Colors.black87),
                           fontWeight: !isPrivate ? FontWeight.bold : FontWeight.normal,
                         ),
                         backgroundColor: isDark ? Colors.black45 : Colors.grey.shade100,
                         side: BorderSide.none,
                         shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                       ),
                       const SizedBox(width: 12),
                       ChoiceChip(
                         label: const Text('Private'),
                         selected: isPrivate,
                         onSelected: (selected) {
                           if (selected) setDialogState(() => isPrivate = true);
                         },
                         selectedColor: AppTheme.primary,
                         labelStyle: TextStyle(
                           color: isPrivate ? Colors.white : (isDark ? Colors.white70 : Colors.black87),
                           fontWeight: isPrivate ? FontWeight.bold : FontWeight.normal,
                         ),
                         backgroundColor: isDark ? Colors.black45 : Colors.grey.shade100,
                         side: BorderSide.none,
                         shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                       ),
                     ],
                   ),
                 ],
               ),
             ),
           ),
           actions: [
              TextButton(onPressed: ()=>Navigator.pop(context), child: const Text('Cancel')),
              TextButton(
                 onPressed: () async {
                    if (nameCtrl.text.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Room name is required')));
                      return;
                    }
                    if (selectedTags.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please add at least one tag')));
                      return;
                    }
                    
                    try {
                       final res = await _supabaseService.createChatRoom(
                         name: nameCtrl.text, 
                         description: descCtrl.text, 
                         isPrivate: isPrivate, 
                         userEmail: widget.userEmail, 
                         collegeId: widget.collegeId,
                         tags: selectedTags,
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
                       if (mounted) {
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
