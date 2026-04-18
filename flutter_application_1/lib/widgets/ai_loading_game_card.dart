import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/theme.dart';

class AiLoadingGameCard extends StatefulWidget {
  const AiLoadingGameCard({
    super.key,
    required this.loadingMessage,
    this.compact = false,
    this.initialGame = 0,
    this.showFullscreenToggle = true,
    this.headline = 'Beat the high score while AI works',
    this.subheadline =
        'Arcade-style distractions run while your answer renders.',
  });

  final String loadingMessage;
  final bool compact;
  final int initialGame;
  final bool showFullscreenToggle;
  final String headline;
  final String subheadline;

  @override
  State<AiLoadingGameCard> createState() => _AiLoadingGameCardState();
}

class _AiLoadingGameCardState extends State<AiLoadingGameCard> {
  static const _flappyKey = 'ai_loading_game_flappy_high_score';
  static const _brickKey = 'ai_loading_game_brick_high_score';
  static const _dinoKey = 'ai_loading_game_dino_high_score';
  static const _flappyHintKey = 'ai_loading_game_flappy_hint_seen';
  static const _brickHintKey = 'ai_loading_game_brick_hint_seen';
  static const _dinoHintKey = 'ai_loading_game_dino_hint_seen';
  static const _firstDinoObstacleDelayMs = 2800.0;
  static const _tick = Duration(milliseconds: 16);
  static const _flappyBackgroundAsset =
      'assets/images/mini_games/flappy/background-day.png';
  static const _flappyBaseAsset = 'assets/images/mini_games/flappy/base.png';
  static const _flappyPipeAsset =
      'assets/images/mini_games/flappy/pipe-green.png';
  static const _flappyBirdDownAsset =
      'assets/images/mini_games/flappy/bird-down.png';
  static const _flappyBirdMidAsset =
      'assets/images/mini_games/flappy/bird-mid.png';
  static const _flappyBirdUpAsset =
      'assets/images/mini_games/flappy/bird-up.png';
  static const _dinoCloudAsset = 'assets/images/mini_games/dino/cloud.png';
  static const _dinoHorizonAsset = 'assets/images/mini_games/dino/horizon.png';
  static const _dinoCactusAsset =
      'assets/images/mini_games/dino/cactus-small.png';
  static const _dinoWaitAsset = 'assets/images/mini_games/dino/dino-wait.png';
  static const _dinoRunOneAsset =
      'assets/images/mini_games/dino/dino-run-1.png';
  static const _dinoRunTwoAsset =
      'assets/images/mini_games/dino/dino-run-2.png';
  static const _dinoJumpAsset = 'assets/images/mini_games/dino/dino-jump.png';
  static const _dinoCrashAsset = 'assets/images/mini_games/dino/dino-crash.png';

  final math.Random _random = math.Random();
  final ValueNotifier<int> _overlayTick = ValueNotifier<int>(0);
  Timer? _loop;
  int _selected = 0;
  int _frameTick = 0;

  int _flappyScore = 0, _flappyHigh = 0;
  bool _flappyStarted = false, _flappyOver = false;
  double _birdY = 0.5, _birdVelocity = 0, _pipeX = 1.1, _gapY = 0.48;

  int _brickScore = 0, _brickHigh = 0, _brickLevel = 1;
  bool _brickStarted = false, _brickOver = false;
  double _paddleX = 0.5,
      _ballX = 0.5,
      _ballY = 0.72,
      _ballVX = 0.58,
      _ballVY = -0.74;
  final List<_BrickTile> _bricks = <_BrickTile>[];

  int _dinoScore = 0, _dinoHigh = 0;
  bool _dinoStarted = false, _dinoOver = false;
  double _dinoLift = 0, _dinoVelocity = 0, _obstacleX = 1.1, _cloudX = 0.9;
  double _dinoElapsedMs = 0;
  bool _hasSeenFlappyHint = false;
  bool _hasSeenBrickHint = false;
  bool _hasSeenDinoHint = false;

  @override
  void initState() {
    super.initState();
    _selected = widget.initialGame.clamp(0, 2);
    _resetFlappy();
    _resetBrick();
    _resetDino();
    _loadHighScores();
    _loop = Timer.periodic(_tick, (_) {
      if (!mounted) return;
      setState(() {
        _frameTick += 1;
        const dt = 1 / 60;
        _advanceFlappy(dt);
        _advanceBrick(dt);
        _advanceDino(dt);
      });
      _overlayTick.value += 1;
    });
  }

  @override
  void dispose() {
    _loop?.cancel();
    _overlayTick.dispose();
    super.dispose();
  }

  Future<void> _loadHighScores() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _flappyHigh = prefs.getInt(_flappyKey) ?? 0;
      _brickHigh = prefs.getInt(_brickKey) ?? 0;
      _dinoHigh = prefs.getInt(_dinoKey) ?? 0;
      _hasSeenFlappyHint = prefs.getBool(_flappyHintKey) ?? false;
      _hasSeenBrickHint = prefs.getBool(_brickHintKey) ?? false;
      _hasSeenDinoHint = prefs.getBool(_dinoHintKey) ?? false;
    });
  }

  void _persistHighScore(String key, int score) {
    unawaited(() async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(key, score);
    }());
  }

  Future<void> _markHintSeen(int gameIndex) async {
    final key = switch (gameIndex) {
      0 => _flappyHintKey,
      1 => _brickHintKey,
      _ => _dinoHintKey,
    };
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, true);
    if (!mounted) return;
    setState(() {
      if (gameIndex == 0) _hasSeenFlappyHint = true;
      if (gameIndex == 1) _hasSeenBrickHint = true;
      if (gameIndex == 2) _hasSeenDinoHint = true;
    });
    _overlayTick.value += 1;
  }

  void _resetFlappy() {
    _flappyScore = 0;
    _flappyStarted = false;
    _flappyOver = false;
    _birdY = 0.5;
    _birdVelocity = 0;
    _pipeX = 1.1;
    _gapY = 0.46;
  }

  void _advanceFlappy(double dt) {
    if (!_flappyStarted || _flappyOver) return;
    _birdVelocity += 1.75 * dt;
    _birdY += _birdVelocity * dt;
    _pipeX -= 0.62 * dt;
    const gap = 0.28, birdX = 0.24, birdR = 0.045, pipeW = 0.16;
    final hitPipe =
        _pipeX < birdX + birdR &&
        _pipeX + pipeW > birdX - birdR &&
        (_birdY < _gapY - gap / 2 || _birdY > _gapY + gap / 2);
    if (_birdY < 0.06 || _birdY > 0.94 || hitPipe) {
      _flappyOver = true;
      return;
    }
    if (_pipeX < -pipeW) {
      _pipeX = 1.1;
      _gapY = 0.28 + _random.nextDouble() * 0.42;
      _flappyScore += 1;
      if (_flappyScore > _flappyHigh) {
        _flappyHigh = _flappyScore;
        _persistHighScore(_flappyKey, _flappyHigh);
      }
    }
  }

  void _resetBrick() {
    _brickScore = 0;
    _brickLevel = 1;
    _brickStarted = false;
    _brickOver = false;
    _paddleX = 0.5;
    _ballX = 0.5;
    _ballY = 0.72;
    _ballVX = 0.58;
    _ballVY = -0.74;
    _spawnBricks();
  }

  void _spawnBricks() {
    const palette = <Color>[
      Color(0xFF38BDF8),
      Color(0xFF22C55E),
      Color(0xFFF97316),
      Color(0xFFFACC15),
      Color(0xFFA78BFA),
    ];
    _bricks
      ..clear()
      ..addAll(
        List<_BrickTile>.generate(18, (i) {
          final row = i ~/ 6;
          final col = i % 6;
          return _BrickTile(
            x: 0.08 + col * 0.145,
            y: 0.10 + row * 0.09,
            color: palette[(row + col + _brickLevel) % palette.length],
          );
        }),
      );
  }

  void _advanceBrick(double dt) {
    if (!_brickStarted || _brickOver) return;
    _ballX += _ballVX * dt;
    _ballY += _ballVY * dt;
    if (_ballX <= 0.04 || _ballX >= 0.96) _ballVX *= -1;
    if (_ballY <= 0.05) _ballVY = _ballVY.abs();
    if (_ballY >= 0.87 &&
        _ballY <= 0.91 &&
        _ballX >= _paddleX - 0.12 &&
        _ballX <= _paddleX + 0.12 &&
        _ballVY > 0) {
      _ballVY = -_ballVY.abs();
      _ballVX = (_ballVX + ((_ballX - _paddleX) * 1.8)).clamp(-0.95, 0.95);
    }
    for (final brick in _bricks) {
      if (!brick.active) continue;
      final hit =
          _ballX >= brick.x &&
          _ballX <= brick.x + 0.12 &&
          _ballY >= brick.y &&
          _ballY <= brick.y + 0.055;
      if (!hit) continue;
      brick.active = false;
      _ballVY *= -1;
      _brickScore += 5;
      if (_brickScore > _brickHigh) {
        _brickHigh = _brickScore;
        _persistHighScore(_brickKey, _brickHigh);
      }
      break;
    }
    if (_bricks.every((brick) => !brick.active)) {
      _brickLevel += 1;
      _brickScore += 20;
      _spawnBricks();
      _ballX = 0.5;
      _ballY = 0.72;
      _ballVX = 0.6 + (_brickLevel * 0.03);
      _ballVY = -0.8;
    }
    if (_ballY > 1.02) _brickOver = true;
  }

  void _resetDino() {
    _dinoScore = 0;
    _dinoStarted = false;
    _dinoOver = false;
    _dinoLift = 0;
    _dinoVelocity = 0;
    _obstacleX = 1.28;
    _cloudX = 0.9;
    _dinoElapsedMs = 0;
  }

  void _advanceDino(double dt) {
    _cloudX -= dt * 0.12;
    if (_cloudX < -0.18) _cloudX = 1.08;
    if (!_dinoStarted || _dinoOver) return;
    _dinoElapsedMs += dt * 1000;
    if (_dinoElapsedMs >= _firstDinoObstacleDelayMs) {
      _obstacleX -= dt * (0.86 + (_dinoScore / 40));
      if (_obstacleX < -0.12) {
        _obstacleX = 1.08 + _random.nextDouble() * 0.22;
        _dinoScore += 1;
        if (_dinoScore > _dinoHigh) {
          _dinoHigh = _dinoScore;
          _persistHighScore(_dinoKey, _dinoHigh);
        }
      }
    }
    _dinoVelocity += 2.4 * dt;
    _dinoLift += _dinoVelocity * dt;
    if (_dinoLift > 0) {
      _dinoLift = 0;
      _dinoVelocity = 0;
    }
    final dinoRect = Rect.fromLTWH(0.18, 0.68 + _dinoLift, 0.10, 0.14);
    final obstacleRect = Rect.fromLTWH(_obstacleX, 0.72, 0.08, 0.10);
    if (dinoRect.overlaps(obstacleRect)) _dinoOver = true;
  }

  void _primaryAction() {
    setState(() {
      if (_selected == 0) {
        if (_flappyOver) _resetFlappy();
        _flappyStarted = true;
        _birdVelocity = -0.72;
      } else if (_selected == 1) {
        if (_brickOver) _resetBrick();
        _brickStarted = true;
      } else {
        if (_dinoOver) _resetDino();
        _dinoStarted = true;
        if (_dinoLift == 0) _dinoVelocity = -1.08;
      }
    });
    _overlayTick.value += 1;
    final seen = switch (_selected) {
      0 => _hasSeenFlappyHint,
      1 => _hasSeenBrickHint,
      _ => _hasSeenDinoHint,
    };
    if (!seen) {
      unawaited(_markHintSeen(_selected));
    }
  }

  Future<void> _openFullscreen() async {
    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Close arcade game',
      barrierColor: Colors.black.withValues(alpha: 0.86),
      pageBuilder: (context, animation, secondaryAnimation) {
        return SafeArea(
          child: Material(
            color: Colors.transparent,
            child: ValueListenableBuilder<int>(
              valueListenable: _overlayTick,
              builder: (context, _, _) {
                final isDark = Theme.of(context).brightness == Brightness.dark;
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1040),
                      child: _buildFullscreenWindow(
                        isDark: isDark,
                        onClose: () => Navigator.of(context).pop(),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }

  Widget _buildArcadeControls({
    required bool fullscreen,
    required bool showModeTabs,
    VoidCallback? onClose,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showModeTabs) ...[
          _iconTab(0, Icons.flight_rounded, 'Flappy'),
          const SizedBox(width: 8),
          _iconTab(1, Icons.grid_view_rounded, 'Brick Blitz'),
          const SizedBox(width: 8),
          _iconTab(2, Icons.terrain_rounded, 'Dino'),
        ],
        if (fullscreen && onClose != null) ...[
          if (showModeTabs) const SizedBox(width: 8),
          _iconTab(
            _selected,
            Icons.close_rounded,
            'Close fullscreen',
            onPressed: onClose,
          ),
        ] else if (widget.showFullscreenToggle) ...[
          if (showModeTabs) const SizedBox(width: 8),
          _iconTab(
            _selected,
            Icons.open_in_full_rounded,
            'Open fullscreen',
            onPressed: _openFullscreen,
          ),
        ],
      ],
    );
  }

  bool get _hasSeenCurrentHint => _selected == 0
      ? _hasSeenFlappyHint
      : (_selected == 1 ? _hasSeenBrickHint : _hasSeenDinoHint);
  int get _score => _selected == 0
      ? _flappyScore
      : (_selected == 1 ? _brickScore : _dinoScore);
  int get _high =>
      _selected == 0 ? _flappyHigh : (_selected == 1 ? _brickHigh : _dinoHigh);
  bool get _showOverlay => _selected == 0
      ? (!_flappyStarted || _flappyOver)
      : (_selected == 1
            ? (!_brickStarted || _brickOver)
            : (!_dinoStarted || _dinoOver));
  String get _overlayTitle => _selected == 0
      ? (_flappyOver ? 'Run Over' : 'Tap To Fly')
      : (_selected == 1
            ? (_brickOver ? 'Round Over' : 'Tap To Serve')
            : (_dinoOver ? 'You Crashed' : 'Tap To Run'));
  String get _overlaySubtitle => _selected == 0
      ? (_flappyOver
            ? 'Restart and chase a cleaner pipe line.'
            : (_hasSeenCurrentHint
                  ? 'Tap once to keep the bird centered.'
                  : 'Tap to flap between the classic pipe gaps.'))
      : (_selected == 1
            ? (_brickOver
                  ? 'Reset and clear the wall again.'
                  : (_hasSeenCurrentHint
                        ? 'Tap to serve, then drag the paddle.'
                        : 'Tap to serve, drag to move the paddle.'))
            : (_dinoOver
                  ? 'Next jump needs to land earlier.'
                  : (_hasSeenCurrentHint
                        ? 'One tap jumps. Time it against the cactus.'
                        : 'You get a short runway before the first cactus.')));
  String get _flappyBirdAsset {
    final frame = (_frameTick ~/ 6) % 3;
    switch (frame) {
      case 0:
        return _flappyBirdUpAsset;
      case 1:
        return _flappyBirdMidAsset;
      default:
        return _flappyBirdDownAsset;
    }
  }

  String get _dinoAsset {
    if (_dinoOver) return _dinoCrashAsset;
    if (_dinoLift < -0.01) return _dinoJumpAsset;
    if (!_dinoStarted) return _dinoWaitAsset;
    return (_frameTick ~/ 8).isEven ? _dinoRunOneAsset : _dinoRunTwoAsset;
  }

  Widget _scene(bool isDark, {bool fullscreen = false}) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : 320.0;
        final targetHeight = fullscreen
            ? math.min(560.0, width * 0.66)
            : (widget.compact ? 208.0 : 228.0);
        final height = math.max(200.0, math.min(targetHeight, width * 0.78));
        return SizedBox(
          width: double.infinity,
          height: height,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _primaryAction,
            onHorizontalDragUpdate: _selected == 1
                ? (d) => setState(
                    () => _paddleX = (d.localPosition.dx / width).clamp(
                      0.16,
                      0.84,
                    ),
                  )
                : null,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(22),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _selected == 0
                      ? _flappyScene(width, height)
                      : (_selected == 1
                            ? _brickScene(width, height)
                            : _dinoScene(width, height)),
                  Positioned(
                    left: 14,
                    top: 12,
                    child: Row(
                      children: [
                        _hudChip('Score $_score'),
                        const SizedBox(width: 8),
                        _hudChip('High $_high'),
                      ],
                    ),
                  ),
                  if (_showOverlay)
                    Positioned.fill(
                      child: Container(
                        color: Colors.black.withValues(alpha: 0.30),
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                _overlayTitle,
                                style: GoogleFonts.inter(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w900,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                _overlaySubtitle,
                                textAlign: TextAlign.center,
                                style: GoogleFonts.inter(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white70,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _hudChip(String text) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: Colors.black.withValues(alpha: 0.34),
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text(
      text,
      style: GoogleFonts.inter(
        fontSize: 10.8,
        fontWeight: FontWeight.w800,
        color: Colors.white,
      ),
    ),
  );

  Widget _iconTab(
    int index,
    IconData icon,
    String tooltip, {
    VoidCallback? onPressed,
  }) {
    final selected = _selected == index;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap:
              onPressed ??
              () {
                setState(() => _selected = index);
                _overlayTick.value += 1;
              },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              gradient: selected
                  ? const LinearGradient(
                      colors: [Color(0xFF2563EB), Color(0xFFF97316)],
                    )
                  : null,
              color: selected ? null : Colors.black.withValues(alpha: 0.22),
              border: Border.all(
                color: selected
                    ? Colors.transparent
                    : Colors.white.withValues(alpha: 0.14),
              ),
            ),
            child: Icon(icon, size: 18, color: Colors.white),
          ),
        ),
      ),
    );
  }

  Widget _buildShell({
    required bool isDark,
    required bool fullscreen,
    VoidCallback? onClose,
  }) {
    final overlay = isDark ? const Color(0xFF111827) : Colors.white;
    final surface = isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FBFF);
    return Container(
      width: double.infinity,
      constraints: BoxConstraints(maxWidth: fullscreen ? 960 : 700),
      padding: EdgeInsets.all(fullscreen ? 20 : (widget.compact ? 16 : 18)),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(fullscreen ? 30 : 26),
        gradient: const LinearGradient(
          colors: [Color(0xFF0F172A), Color(0xFF1D4ED8), Color(0xFFF97316)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF2563EB).withValues(alpha: 0.22),
            blurRadius: 30,
            offset: const Offset(0, 18),
          ),
        ],
      ),
      child: Container(
        padding: EdgeInsets.all(fullscreen ? 20 : 16),
        decoration: BoxDecoration(
          color: overlay.withValues(alpha: 0.95),
          borderRadius: BorderRadius.circular(24),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: surface,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: isDark
                      ? Colors.white10
                      : Colors.black.withValues(alpha: 0.05),
                ),
              ),
              child: Row(
                children: [
                  const SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.2,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        AppTheme.primary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      widget.loadingMessage,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: isDark
                            ? Colors.white70
                            : const Color(0xFF334155),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            _buildGameWindow(
              isDark: isDark,
              fullscreen: fullscreen,
              showModeTabs: true,
              onClose: onClose,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGameWindow({
    required bool isDark,
    required bool fullscreen,
    required bool showModeTabs,
    VoidCallback? onClose,
  }) {
    final surface = isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FBFF);
    return Stack(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: surface,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: isDark
                  ? Colors.white10
                  : Colors.black.withValues(alpha: 0.05),
            ),
          ),
          child: _scene(isDark, fullscreen: fullscreen),
        ),
        Positioned(
          top: 18,
          right: 18,
          child: _buildArcadeControls(
            fullscreen: fullscreen,
            showModeTabs: showModeTabs,
            onClose: onClose,
          ),
        ),
      ],
    );
  }

  Widget _buildFullscreenWindow({
    required bool isDark,
    required VoidCallback onClose,
  }) {
    final frameColor = isDark
        ? const Color(0xFF020617)
        : const Color(0xFF0F172A);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: frameColor.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.32),
            blurRadius: 32,
            offset: const Offset(0, 18),
          ),
        ],
      ),
      child: _buildGameWindow(
        isDark: isDark,
        fullscreen: true,
        showModeTabs: false,
        onClose: onClose,
      ),
    );
  }

  Widget _sprite(
    String asset, {
    double? width,
    double? height,
    BoxFit fit = BoxFit.contain,
  }) {
    return Image.asset(
      asset,
      width: width,
      height: height,
      fit: fit,
      filterQuality: FilterQuality.none,
      gaplessPlayback: true,
      isAntiAlias: false,
      errorBuilder: (context, error, stackTrace) =>
          _spriteFallback(width: width, height: height),
    );
  }

  Widget _spriteFallback({double? width, double? height}) {
    final size = math.max(18.0, math.min(width ?? 28.0, height ?? 28.0));
    return Container(
      width: width,
      height: height,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Icon(
        Icons.broken_image_outlined,
        color: Colors.white70,
        size: size,
      ),
    );
  }

  Widget _flappyScene(double width, double height) {
    final baseHeight = math.max(28.0, height * 0.14);
    final bodyHeight = height - baseHeight;
    final gapTop = ((_gapY - 0.14).clamp(0.04, 0.78)) * bodyHeight;
    final gapBottom = ((_gapY + 0.14).clamp(0.22, 0.92)) * bodyHeight;
    final pipeWidth = math.max(44.0, width * 0.16);
    final pipeLeft = _pipeX * width;
    final birdWidth = width * 0.12;
    final birdHeight = birdWidth * (24 / 34);
    final birdLeft = width * 0.18;
    final birdTop = ((_birdY * (bodyHeight - birdHeight)).clamp(
      8.0,
      bodyHeight - birdHeight - 4,
    ));
    final baseTileWidth = baseHeight * 3;
    final baseShift =
        -((_flappyStarted && !_flappyOver ? _frameTick * 2.2 : 0) %
            baseTileWidth);
    final pipeCapOffset = pipeWidth * 0.06;

    return Container(
      color: const Color(0xFF4EC0CA),
      child: Stack(
        children: [
          Positioned.fill(
            child: _sprite(_flappyBackgroundAsset, fit: BoxFit.cover),
          ),
          Positioned(
            left: pipeLeft,
            top: -pipeCapOffset,
            child: Transform.rotate(
              angle: math.pi,
              child: _sprite(
                _flappyPipeAsset,
                width: pipeWidth,
                height: gapTop + pipeCapOffset,
                fit: BoxFit.fill,
              ),
            ),
          ),
          Positioned(
            left: pipeLeft,
            top: gapBottom,
            child: _sprite(
              _flappyPipeAsset,
              width: pipeWidth,
              height: math.max(0, bodyHeight - gapBottom) + pipeCapOffset,
              fit: BoxFit.fill,
            ),
          ),
          Positioned(
            left: birdLeft,
            top: birdTop,
            child: Transform.rotate(
              angle: _birdVelocity.clamp(-0.8, 0.9) * 0.48,
              child: _sprite(
                _flappyBirdAsset,
                width: birdWidth,
                height: birdHeight,
              ),
            ),
          ),
          for (var i = 0; i < 4; i++)
            Positioned(
              left: baseShift + (i * baseTileWidth),
              right: null,
              bottom: 0,
              child: _sprite(
                _flappyBaseAsset,
                width: baseTileWidth,
                height: baseHeight,
                fit: BoxFit.fill,
              ),
            ),
        ],
      ),
    );
  }

  Widget _brickScene(double width, double height) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF020617), Color(0xFF111827), Color(0xFF1E1B4B)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: Stack(
        children: [
          for (final brick in _bricks.where((b) => b.active))
            Positioned(
              left: brick.x * width,
              top: brick.y * height,
              child: Container(
                width: 40,
                height: 14,
                decoration: BoxDecoration(
                  color: brick.color,
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: [
                    BoxShadow(
                      color: brick.color.withValues(alpha: 0.35),
                      blurRadius: 12,
                    ),
                  ],
                ),
              ),
            ),
          Positioned(
            left: (_ballX * width) - 6,
            top: (_ballY * height) - 6,
            child: Container(
              width: 12,
              height: 12,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white,
              ),
            ),
          ),
          Positioned(
            left: (_paddleX * width) - 44,
            bottom: 16,
            child: Container(
              width: 88,
              height: 12,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(999),
                gradient: const LinearGradient(
                  colors: [Color(0xFF38BDF8), Color(0xFFF8FAFC)],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _dinoScene(double width, double height) {
    final groundTop = height * 0.82;
    final dinoHeight = math.max(46.0, height * 0.24);
    final dinoWidth = dinoHeight * (44 / 47);
    final dinoTop = (groundTop - dinoHeight + 2) + (_dinoLift * height);
    final cactusHeight = dinoHeight * 0.78;
    final cactusWidth = cactusHeight * (17 / 35);
    final cactusTop = groundTop - cactusHeight + 6;
    final horizonTileWidth = math.max(width, 240.0);
    final horizonShift =
        -((_dinoStarted && !_dinoOver ? _frameTick * 3.4 : 0) %
            horizonTileWidth);

    return Container(
      color: const Color(0xFFF7F7F7),
      child: Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    const Color(0xFFF9FAFB),
                    const Color(0xFFF9FAFB),
                    const Color(0xFFF3F4F6).withValues(alpha: 0.92),
                  ],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
            ),
          ),
          Positioned(
            left: _cloudX * width,
            top: height * 0.12,
            child: _sprite(_dinoCloudAsset, width: 46, height: 14),
          ),
          for (var i = 0; i < 3; i++)
            Positioned(
              left: horizonShift + (i * horizonTileWidth),
              bottom: height - groundTop - 2,
              child: _sprite(
                _dinoHorizonAsset,
                width: horizonTileWidth,
                height: 12,
                fit: BoxFit.fill,
              ),
            ),
          Positioned(
            left: width * 0.16,
            top: dinoTop,
            child: _sprite(_dinoAsset, width: dinoWidth, height: dinoHeight),
          ),
          Positioned(
            left: _obstacleX * width,
            top: cactusTop,
            child: _sprite(
              _dinoCactusAsset,
              width: cactusWidth,
              height: cactusHeight,
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            top: groundTop,
            bottom: 0,
            child: Container(color: const Color(0xFFF7F7F7)),
          ),
          Positioned(
            left: 0,
            right: 0,
            top: groundTop - 1.2,
            child: Container(height: 2.4, color: const Color(0xFF4B5563)),
          ),
          Positioned(
            right: 14,
            top: 16,
            child: Text(
              'HI ${_dinoHigh.toString().padLeft(5, '0')}',
              style: GoogleFonts.robotoMono(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: const Color(0xFF4B5563),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return _buildShell(isDark: isDark, fullscreen: false);
  }
}

class _BrickTile {
  _BrickTile({required this.x, required this.y, required this.color});
  final double x;
  final double y;
  final Color color;
  bool active = true;
}
