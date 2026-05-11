import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import 'screens/dashboard_screen.dart';
import 'services/printer_calibration_repository.dart';

const String _trayIconPath = 'assets/icons/tray_icon.ico';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();
  // Preload per-printer calibrations so the HTTP /print handler can read
  // them synchronously on every request.
  await PrinterCalibrationRepository.instance.ensureLoaded();

  const windowOptions = WindowOptions(
    size: Size(900, 600),
    center: true,
    title: 'Gabooth Assistant',
    skipTaskbar: true,
    fullScreen: false,
  );
  // Apply options but do not show — the app launches hidden in the tray.
  await windowManager.waitUntilReadyToShow(windowOptions, () async {});
  await windowManager.setPreventClose(true);

  runApp(const ProviderScope(child: MyApp()));
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WindowListener, TrayListener {
  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    trayManager.addListener(this);
    _initTray();
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    trayManager.removeListener(this);
    super.dispose();
  }

  Future<void> _showWindow() async {
    await windowManager.setSkipTaskbar(false);
    if (await windowManager.isFullScreen()) {
      await windowManager.setFullScreen(false);
    }
    if (await windowManager.isMaximized()) {
      await windowManager.unmaximize();
    }
    await windowManager.show();
    await windowManager.focus();
  }

  Future<void> _hideWindow() async {
    await windowManager.hide();
    await windowManager.setSkipTaskbar(true);
  }

  Future<void> _initTray() async {
    await trayManager.setIcon(_trayIconPath);
    await trayManager.setToolTip('Gabooth Assistant — Print Server');
    await trayManager.setContextMenu(
      Menu(
        items: [
          MenuItem(key: 'show_window', label: 'Show Window'),
          MenuItem.separator(),
          MenuItem(key: 'quit', label: 'Quit'),
        ],
      ),
    );
  }

  @override
  void onWindowClose() async {
    if (await windowManager.isPreventClose()) {
      await _hideWindow();
    }
  }

  @override
  void onTrayIconMouseDown() async {
    await _showWindow();
  }

  @override
  void onTrayIconRightMouseDown() {
    trayManager.popUpContextMenu();
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) async {
    switch (menuItem.key) {
      case 'show_window':
        await _showWindow();
        break;
      case 'quit':
        await trayManager.destroy();
        await windowManager.setPreventClose(false);
        await windowManager.destroy();
        exit(0);
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Gabooth Assistant',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF42B883)),
        useMaterial3: true,
      ),
      home: const DashboardScreen(),
    );
  }
}
