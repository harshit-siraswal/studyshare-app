import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../data/departments_data.dart';
import '../../screens/study/syllabus_screen.dart';

class DepartmentCard3D extends StatefulWidget {
  final DepartmentData dept;
  final String collegeId;
  final bool canUploadSyllabus;
  final Color textColor;
  final Color secondaryColor;
  final Color cardColor;
  final Color borderColor;

  const DepartmentCard3D({
    super.key,
    required this.dept,
    required this.collegeId,
    required this.canUploadSyllabus,
    required this.textColor,
    required this.secondaryColor,
    required this.cardColor,
    required this.borderColor,
  });

  @override
  State<DepartmentCard3D> createState() => _DepartmentCard3DState();
}

class _DepartmentCard3DState extends State<DepartmentCard3D>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<Matrix4> _transformAnimation;

  double _xRotation = 0.0;
  double _yRotation = 0.0;
  bool _isTapped = false;
  bool _isNavigating = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _transformAnimation = Matrix4Tween(
      begin: Matrix4.identity(),
      end: Matrix4.identity(),
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutBack));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onPanUpdate(DragUpdateDetails details, Size size) {
    final localPosition = details.localPosition;
    final halfWidth = size.width / 2;
    final halfHeight = size.height / 2;

    final xFactor = (localPosition.dx - halfWidth) / halfWidth;
    final yFactor = (localPosition.dy - halfHeight) / halfHeight;

    final clampedX = xFactor.clamp(-1.0, 1.0);
    final clampedY = yFactor.clamp(-1.0, 1.0);

    setState(() {
      _yRotation = clampedX * 0.15;
      _xRotation = -clampedY * 0.15;
    });
  }

  Matrix4 _createCurrentTransform() {
    final scale = _isTapped ? 0.95 : 1.0;
    return Matrix4.identity()
      ..setEntry(3, 2, 0.001)
      ..rotateX(_xRotation)
      ..rotateY(_yRotation)
      ..scale(scale, scale, scale);
  }

  void _resetTransform() {
    _transformAnimation = Matrix4Tween(
      begin: _createCurrentTransform(),
      end: Matrix4.identity(),
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutBack));

    setState(() {
      _xRotation = 0.0;
      _yRotation = 0.0;
      _isTapped = false;
    });
    _controller.forward(from: 0.0);
  }

  @override
  Widget build(BuildContext context) {
    final currentTransform = _createCurrentTransform();

    return LayoutBuilder(
      builder: (context, constraints) {
        final mediaSize = MediaQuery.of(context).size;
        final fallbackWidth = mediaSize.width > 0 ? mediaSize.width : 320.0;
        const fallbackHeight = 180.0;
        final width = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : (constraints.biggest.width.isFinite
                  ? constraints.biggest.width
                  : fallbackWidth);
        final height = constraints.maxHeight.isFinite
            ? constraints.maxHeight
            : (constraints.biggest.height.isFinite
                  ? constraints.biggest.height
                  : fallbackHeight);
        final size = Size(width <= 0 ? 1 : width, height <= 0 ? 1 : height);
        return GestureDetector(
          onPanDown: (details) {
            setState(() => _isTapped = true);
            _controller.stop();
          },
          onPanUpdate: (details) => _onPanUpdate(details, size),
          onPanEnd: (_) => _resetTransform(),
          onPanCancel: _resetTransform,
          onTapUp: (_) => _resetTransform(),
          onTap: () async {
            if (_isNavigating) return;
            if (mounted) setState(() => _isNavigating = true);

            try {
              await Future.delayed(const Duration(milliseconds: 150));
              if (!mounted) {
                _isNavigating = false;
                return;
              }

              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => SyllabusScreen(
                    collegeId: widget.collegeId,
                    department: widget.dept.name,
                    departmentName: widget.dept.full,
                    departmentColor: widget.dept.color,
                    canUploadSyllabus: widget.canUploadSyllabus,
                  ),
                ),
              );
            } finally {
              if (mounted) {
                setState(() => _isNavigating = false);
              } else {
                _isNavigating = false;
              }
            }
          },
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              return Transform(
                transform: _controller.isAnimating
                    ? _transformAnimation.value
                    : currentTransform,
                alignment: Alignment.center,
                child: child,
              );
            },
            child: Material(
              color: widget.cardColor,
              borderRadius: BorderRadius.circular(12),
              elevation: _isTapped ? 8 : 2,
              shadowColor: widget.borderColor.withValues(alpha: 0.5),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: widget.borderColor),
                ),
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: widget.dept.color.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        Icons.folder_outlined,
                        color: widget.dept.color,
                        size: 20,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      widget.dept.name,
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: widget.textColor,
                      ),
                    ),
                    Text(
                      widget.dept.full,
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        color: widget.secondaryColor,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
