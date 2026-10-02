import 'package:flutter/material.dart';

class Constants {
  static String appName = "sIIr";
  static String version = "1.1.0";
  static String copyrightText = "© 2026 Sahil Raj";
  static String pathCircleDarkTop = "assets/images/gif/circle_dark_top.svg";
  static String pathCircleDarkMid = "assets/images/gif/circle_dark_mid.svg";
  static String pathCircleDarkBottom =
      "assets/images/gif/circle_dark_bottom.svg";
  static String pathCircleLightTop = "assets/images/gif/circle_light_top.svg";
  static String pathCircleLightMid = "assets/images/gif/circle_light_mid.svg";
  static String pathCircleLightBottom =
      "assets/images/gif/circle_light_bottom.svg";
  static String pathIconMenuAA = "assets/images/gif/icon_menu_aa.svg";
  static String pathIconMenuAG = "assets/images/gif/icon_menu_ag.svg";
  static String pathIconMenuAV = "assets/images/gif/icon_menu_av.svg";

  static String fontFamilyTitle = "Gwendolyne";
  static String fontFamilyBody = "Zain";
  static String fontFamilySubHead = "ElMessiri";

  static double fontSizeTitle = 80;
  static double fontSizeBody = 12;
  static double fontSizeDialog = 24;
  static double fontSizeSubHead = 32;

  static double widthCircleBottom = 150;
  static double widthCircleMid = 120;
  static double widthCircleTop = 100;

  static String routeMainMenu = "/mainmenu";
  static String routeAudioAnalyzer = "/aa";
  static String routeAudioGenerator = "/ag";
  static String routeAudioVisualizer = "/av";

  static String pathSoundChord1 = "sounds/guitar_chord_1.wav";
  static String pathSoundChord2 = "sounds/guitar_chord_2.wav";
  static String pathSoundChord3 = "sounds/guitar_chord_3.wav";

  static const int pcmBufferSize = 2048; // Number of Samples;
  static const int defaultSampleRate = 44100;
  static const int defaultNumChannels = 1;

  static const double bufferDuration = 0.2; // Seconds
  static const double bufferLapseFactor = 0.5;

  static const String decodedWavFileName = "__shir_temp.wav";

  static const String pathIconBtnDisk = "assets/images/gif/disk_btn_icon.svg";
  static const String pathIconBtnMic = "assets/images/gif/mic_btn_icon.svg";
  static const String pathIconBtnOptions =
      "assets/images/gif/options_btn_icon.svg";
  static const String pathIconBtnReset = "assets/images/gif/reset_btn_icon.svg";
  static const String pathIconBtnSave = "assets/images/gif/save_btn_icon.svg";
  static const String pathIconBtnHelp = "assets/images/gif/help_btn_icon.svg";
  static const String pathIconPlayLight =
      "assets/images/gif/play_button_light.svg";
  static const String pathIconPlayDark =
      "assets/images/gif/play_button_dark.svg";
  static const String pathIconBtnFocus = "assets/images/gif/focus_btn_icon.svg";
  static const String pathIconBtnInteract =
      "assets/images/gif/intr_btn_icon.svg";
}

GlobalKey repaintKey = GlobalKey();

enum MenuType { audioAnalyzer, audioGeneration, audioVisualization }
