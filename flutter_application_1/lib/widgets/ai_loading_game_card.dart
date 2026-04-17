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
    this.subheadline = 'Arcade-style distractions run while your answer renders.',
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
  static const _tick = Duration(milliseconds: 16);
  static const _flappyBackgroundAsset =
      'assets/images/mini_games/flappy/background-day.png';
  static const _flappyBaseAsset =
      'assets/images/mini_games/flappy/base.png';
  static const _flappyPipeAsset =
      'assets/images/mini_games/flappy/pipe-green.png';
  static const _flappyBirdDownAsset =
      'assets/images/mini_games/flappy/bird-down.png';
  static const _flappyBirdMidAsset =
      'assets/images/mini_games/flappy/bird-mid.png';
  static const _flappyBirdUpAsset =
      'assets/images/mini_games/flappy/bird-up.png';
  static const _dinoCloudAsset =
      'assets/images/mini_games/dino/cloud.png';
  static const _dinoHorizonAsset =
      'assets/images/mini_games/dino/horizon.png';
  static const _dinoCactusAsset =
      'assets/images/mini_games/dino/cactus-small.png';
  static const _dinoWaitAsset =
      'assets/images/mini_games/dino/dino-wait.png';
  static const _dinoRunOneAsset =
      'assets/images/mini_games/dino/dino-run-1.png';
  static const _dinoRunTwoAsset =
      'assets/images/mini_games/dino/dino-run-2.png';
  static const _dinoJumpAsset =
      'assets/images/mini_games/dino/dino-jump.png';
  static const _dinoCrashAsset =
      'assets/images/mini_games/dino/dino-crash.png';

  final math.Random _random = math.Random();
  Timer? _loop;
  int _selected = 0;
  int _frameTick = 0;

  int _flappyScore = 0, _flappyHigh = 0;
  bool _flappyStarted = false, _flappyOver = false;
  double _birdY = 0.5, _birdVelocity = 0, _pipeX = 1.1, _gapY = 0.48;

  int _brickScore = 0, _brickHigh = 0, _brickLevel = 1;
  bool _brickStarted = false, _brickOver = false;
  double _paddleX = 0.5, _ballX = 0.5, _ballY = 0.72, _ballVX = 0.58, _ballVY = -0.74;
  final List<_BrickTile> _bricks = <_BrickTile>[];

  int _dinoScore = 0, _dinoHigh = 0;
  bool _dinoStarted = false, _dinoOver = false;
  double _dinoLift = 0, _dinoVelocity = 0, _obstacleX = 1.1, _cloudX = 0.9;

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
    });
  }

  @override
  void dispose() {
    _loop?.cancel();
    super.dispose();
  }

  Future<void> _loadHighScores() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _flappyHigh = prefs.getInt(_flappyKey) ?? 0;
      _brickHigh = prefs.getInt(_brickKey) ?? 0;
      _dinoHigh = prefs.getInt(_dinoKey) ?? 0;
    });
  }

  void _persistHighScore(String key, int score) {
    unawaited(() async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(key, score);
    }());
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
    _obstacleX = 1.1;
    _cloudX = 0.9;
  }

  void _advanceDino(double dt) {
    _cloudX -= dt * 0.12;
    if (_cloudX < -0.18) _cloudX = 1.08;
    if (!_dinoStarted || _dinoOver) return;
    _obstacleX -= dt * (0.86 + (_dinoScore / 40));
    if (_obstacleX < -0.12) {
      _obstacleX = 1.08 + _random.nextDouble() * 0.22;
      _dinoScore += 1;
      if (_dinoScore > _dinoHigh) {
        _dinoHigh = _dinoScore;
        _persistHighScore(_dinoKey, _dinoHigh);
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
            child: Stack(
              children: [
                Positioned.fill(
                  child: Center(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 28,
                      ),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 940),
                        child: AiLoadingGameCard(
                          compact: false,
                          initialGame: _selected,
                          loadingMessage: widget.loadingMessage,
                          headline: widget.headline,
                          subheadline: widget.subheadline,
                          showFullscreenToggle: false,
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: 10,
                  right: 10,
                  child: IconButton.filledTonal(
                    onPressed: () => Navigator.of(context).pop(),
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.white.withValues(alpha: 0.12),
                      foregroundColor: Colors.white,
                    ),
                    icon: const Icon(Icons.close_rounded),
                    tooltip: 'Close game',
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _pill(String label, String value, bool isDark) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.05),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: GoogleFonts.inter(fontSize: 10.5, fontWeight: FontWeight.w600, color: isDark ? Colors.white60 : const Color(0xFF64748B))),
            const SizedBox(height: 2),
            Text(value, style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w800, color: isDark ? Colors.white : const Color(0xFF0F172A))),
          ],
        ),
      ),
    );
  }

  Widget _switch(int index, String label, bool isDark) {
    final selected = _selected == index;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _selected = index),
        borderRadius: BorderRadius.circular(14),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            gradient: selected ? const LinearGradient(colors: [Color(0xFF2563EB), Color(0xFFF97316)]) : null,
            color: selected ? null : (isDark ? Colors.white.withValues(alpha: 0.06) : Colors.white.withValues(alpha: 0.78)),
            border: Border.all(color: selected ? Colors.transparent : (isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.05))),
          ),
          child: Center(
            child: Text(label, style: GoogleFonts.inter(fontSize: 11.2, fontWeight: FontWeight.w700, color: selected ? Colors.white : (isDark ? Colors.white70 : const Color(0xFF334155)))),
          ),
        ),
      ),
    );
  }

  String get _title => _selected == 0
      ? 'Flappy Flight'
      : (_selected == 1 ? 'Brick Blitz' : 'Chrome Dash');
  String get _instruction => _selected == 0
      ? 'Tap to flap between the classic pipe gaps.'
      : (_selected == 1
            ? 'Tap to serve, drag to move the paddle.'
            : 'Tap to jump the cactus line like the offline runner.');
  int get _score => _selected == 0 ? _flappyScore : (_selected == 1 ? _brickScore : _dinoScore);
  int get _high => _selected == 0 ? _flappyHigh : (_selected == 1 ? _brickHigh : _dinoHigh);
  String get _thirdLabel => _selected == 0 ? 'Gap' : (_selected == 1 ? 'Level' : 'Speed');
  String get _thirdValue => _selected == 0 ? '${(_pipeX * 10).clamp(0, 10).round()}m' : (_selected == 1 ? '$_brickLevel' : '${(1 + (_dinoScore / 6)).toStringAsFixed(1)}x');
  bool get _showOverlay => _selected == 0 ? (!_flappyStarted || _flappyOver) : (_selected == 1 ? (!_brickStarted || _brickOver) : (!_dinoStarted || _dinoOver));
  String get _overlayTitle => _selected == 0 ? (_flappyOver ? 'Run Over' : 'Tap To Fly') : (_selected == 1 ? (_brickOver ? 'Round Over' : 'Tap To Serve') : (_dinoOver ? 'You Crashed' : 'Tap To Run'));
  String get _overlaySubtitle => _selected == 0 ? (_flappyOver ? 'Restart and chase a cleaner pipe line.' : 'Keep the bird centered in each gap.') : (_selected == 1 ? (_brickOver ? 'Reset and clear the wall again.' : 'Break every tile to climb levels.') : (_dinoOver ? 'Next jump needs to land earlier.' : 'One tap jumps. Time it against the cactus.'));
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

  Widget _scene(bool isDark) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth.isFinite ? constraints.maxWidth : 320.0;
        final targetHeight = widget.compact ? 208.0 : 228.0;
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
                    right: 14,
                    top: 12,
                    child: Row(
                      children: [
                        _hudChip(_title),
                        const Spacer(),
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
    decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.34), borderRadius: BorderRadius.circular(999)),
    child: Text(text, style: GoogleFonts.inter(fontSize: 10.8, fontWeight: FontWeight.w800, color: Colors.white)),
  );

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
      errorBuilder: (context, error, stackTrace) => _spriteFallback(
        width: width,
        height: height,
      ),
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
            child: _sprite(
              _flappyBackgroundAsset,
              fit: BoxFit.cover,
            ),
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
      decoration: const BoxDecoration(gradient: LinearGradient(colors: [Color(0xFF020617), Color(0xFF111827), Color(0xFF1E1B4B)], begin: Alignment.topCenter, end: Alignment.bottomCenter)),
      child: Stack(
        children: [
          for (final brick in _bricks.where((b) => b.active))
            Positioned(
              left: brick.x * width,
              top: brick.y * height,
              child: Container(width: 40, height: 14, decoration: BoxDecoration(color: brick.color, borderRadius: BorderRadius.circular(10), boxShadow: [BoxShadow(color: brick.color.withValues(alpha: 0.35), blurRadius: 12)])),
            ),
          Positioned(left: (_ballX * width) - 6, top: (_ballY * height) - 6, child: Container(width: 12, height: 12, decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.white))),
          Positioned(left: (_paddleX * width) - 44, bottom: 16, child: Container(width: 88, height: 12, decoration: BoxDecoration(borderRadius: BorderRadius.circular(999), gradient: const LinearGradient(colors: [Color(0xFF38BDF8), Color(0xFFF8FAFC)])))),
        ],
      ),
    );
  }

  Widget _dinoScene(double width, double height) {
    final groundTop = height * 0.82;
    final dinoHeight = math.max(46.0, height * 0.24);
    final dinoWidth = dinoHeight * (44 / 47);
    final dinoTop =
        (groundTop - dinoHeight + 2) + (_dinoLift * height);
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
            child: _sprite(
              _dinoCloudAsset,
              width: 46,
              height: 14,
            ),
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
            child: _sprite(
              _dinoAsset,
              width: dinoWidth,
              height: dinoHeight,
            ),
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
            child: Container(
              color: const Color(0xFFF7F7F7),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            top: groundTop - 1.2,
            child: Container(
              height: 2.4,
              color: const Color(0xFF4B5563),
            ),
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
    final surface = isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FBFF);
    final overlay = isDark ? const Color(0xFF111827) : Colors.white;
    return Container(
      width: double.infinity,
      constraints: BoxConstraints(maxWidth: widget.compact ? 540 : 700),
      padding: EdgeInsets.all(widget.compact ? 16 : 18),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(26), gradient: const LinearGradient(colors: [Color(0xFF0F172A), Color(0xFF1D4ED8), Color(0xFFF97316)], begin: Alignment.topLeft, end: Alignment.bottomRight), boxShadow: [BoxShadow(color: const Color(0xFF2563EB).withValues(alpha: 0.22), blurRadius: 30, offset: const Offset(0, 18))]),
      child: Container(
        padding: EdgeInsets.all(widget.compact ? 14 : 16),
        decoration: BoxDecoration(color: overlay.withValues(alpha: 0.92), borderRadius: BorderRadius.circular(22)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(width: 42, height: 42, decoration: const BoxDecoration(shape: BoxShape.circle, gradient: LinearGradient(colors: [Color(0xFF22D3EE), Color(0xFFF97316)])), child: const Icon(Icons.sports_esports_rounded, color: Colors.white, size: 22)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(widget.headline, style: GoogleFonts.inter(fontSize: widget.compact ? 15 : 16, fontWeight: FontWeight.w800, color: isDark ? Colors.white : const Color(0xFF0F172A))),
                    const SizedBox(height: 2),
                    Text(widget.subheadline, style: GoogleFonts.inter(fontSize: 11.5, fontWeight: FontWeight.w500, color: isDark ? Colors.white70 : const Color(0xFF475569))),
                  ]),
                ),
                if (widget.showFullscreenToggle) ...[
                  const SizedBox(width: 12),
                  IconButton(
                    onPressed: _openFullscreen,
                    tooltip: 'Open game fullscreen',
                    style: IconButton.styleFrom(
                      backgroundColor: surface,
                      foregroundColor:
                          isDark ? Colors.white : const Color(0xFF0F172A),
                    ),
                    icon: const Icon(Icons.fullscreen_rounded),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(color: surface, borderRadius: BorderRadius.circular(18), border: Border.all(color: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.05))),
              child: Row(children: [
                const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2.2, valueColor: AlwaysStoppedAnimation<Color>(AppTheme.primary))),
                const SizedBox(width: 10),
                Expanded(child: Text(widget.loadingMessage, style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: isDark ? Colors.white70 : const Color(0xFF334155)))),
              ]),
            ),
            const SizedBox(height: 14),
            Row(children: [_switch(0, 'Flappy', isDark), const SizedBox(width: 10), _switch(1, 'Brick Blitz', isDark), const SizedBox(width: 10), _switch(2, 'Dino', isDark)]),
            const SizedBox(height: 14),
            Row(children: [_pill('Score', '$_score', isDark), const SizedBox(width: 10), _pill('High score', '$_high', isDark), const SizedBox(width: 10), _pill(_thirdLabel, _thirdValue, isDark)]),
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: surface, borderRadius: BorderRadius.circular(22), border: Border.all(color: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.05))),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(_instruction, style: GoogleFonts.inter(fontSize: 12.4, fontWeight: FontWeight.w700, color: isDark ? Colors.white : const Color(0xFF0F172A))),
                const SizedBox(height: 4),
                Text('Tap or drag inside the arena and try to beat your saved high score.', style: GoogleFonts.inter(fontSize: 11.4, fontWeight: FontWeight.w500, color: isDark ? Colors.white70 : const Color(0xFF475569))),
                const SizedBox(height: 14),
                _scene(isDark),
              ]),
            ),
          ],
        ),
      ),
    );
  }
}

class _BrickTile {
  _BrickTile({required this.x, required this.y, required this.color});
  final double x;
  final double y;
  final Color color;
  bool active = true;
}
