import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:fishing_almanac/app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Use only fonts bundled in assets/fonts/; never fetch from fonts.googleapis.com.
  // This is critical for China where Google services are blocked.
  GoogleFonts.config.allowRuntimeFetching = false;
  runApp(const FishingAlmanacApp());
}
