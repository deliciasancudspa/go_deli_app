import 'dart:async';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'directions_service.dart';

/// Servicio de navegación por voz integrada.
///
/// Recibe actualizaciones de posición GPS desde OrderDetailScreen y
/// anuncia instrucciones de giro cuando el rider se aproxima a cada
/// paso de la ruta (~100m antes). No requiere llamadas de red adicionales
/// — los pasos ya vienen de la Directions API.
class VoiceNavigationService {
  final FlutterTts _tts = FlutterTts();
  List<NavStep> _steps = [];
  int _currentStepIndex = 0;
  bool _isActive = false;
  bool _isSpeaking = false;

  /// Distancia (metros) a la que se anuncia el próximo paso.
  double warningDistanceMeters = 100;

  /// Idioma TTS (es-ES, en-US, pt-BR).
  String language = "es-ES";

  /// Velocidad de habla (0.0 = lento, 1.0 = normal).
  double speechRate = 0.45;

  // ── Getters ──────────────────────────────────────────────────────

  bool get isActive => _isActive;
  int get currentStepIndex => _currentStepIndex;
  int get totalSteps => _steps.length;
  NavStep? get currentStep =>
      _steps.isEmpty || _currentStepIndex >= _steps.length
          ? null
          : _steps[_currentStepIndex];

  // ── Init ─────────────────────────────────────────────────────────

  Future<void> initialize() async {
    try {
      await _tts.setLanguage(language);
      await _tts.setSpeechRate(speechRate);
      await _tts.setVolume(1.0);
      await _tts.setPitch(1.0);
    } catch (_) {
      // TTS no disponible en este dispositivo — fail silently.
    }
  }

  // ── Navigation control ───────────────────────────────────────────

  /// Inicia la navegación por voz con los pasos extraídos de la ruta.
  Future<void> startNavigation(List<NavStep> steps) async {
    _steps = steps;
    _currentStepIndex = 0;
    _isActive = true;
    await initialize();

    if (_steps.isNotEmpty) {
      await _speak("Iniciando navegación. ${_steps[0].instruction}");
    }
  }

  /// Debe llamarse desde el timer GPS de OrderDetailScreen (~cada 8s).
  /// Compara la posición actual contra el próximo paso de la ruta y
  /// anuncia la instrucción cuando el rider está dentro de
  /// [warningDistanceMeters].
  Future<void> checkPosition(LatLng currentPosition) async {
    if (!_isActive || _currentStepIndex >= _steps.length) return;
    if (_isSpeaking) return; // evitar solapar instrucciones

    try {
      final step = _steps[_currentStepIndex];
      final distToStep = Geolocator.distanceBetween(
        currentPosition.latitude,
        currentPosition.longitude,
        step.startLocation.latitude,
        step.startLocation.longitude,
      );

      if (distToStep <= warningDistanceMeters) {
        await _speak(step.instruction);
        _currentStepIndex++;

        // Último paso → anunciar llegada
        if (_currentStepIndex >= _steps.length) {
          await _speak("Has llegado a tu destino.");
          stopNavigation();
        }
      }
    } catch (_) {
      // Error calculando distancia — continuar.
    }
  }

  Future<void> _speak(String text) async {
    _isSpeaking = true;
    try {
      await _tts.speak(text);
      await _tts.awaitSpeakCompletion(true);
    } catch (_) {
      // TTS falló — ignorar.
    }
    _isSpeaking = false;
  }

  /// Detiene la navegación por voz (el mapa sigue mostrando la ruta).
  void stopNavigation() {
    _isActive = false;
    try {
      _tts.stop();
    } catch (_) {}
    _isSpeaking = false;
  }

  /// Libera recursos. Llamar en dispose() de la pantalla.
  void dispose() {
    stopNavigation();
  }
}
