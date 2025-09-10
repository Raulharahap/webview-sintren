import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:location/location.dart' as loc;

class WebViewScreen extends StatefulWidget {
  const WebViewScreen({super.key});

  @override
  State<WebViewScreen> createState() => _WebViewScreenState();
}

class _WebViewScreenState extends State<WebViewScreen> {
  WebViewController? _controller;
  bool _isError = false;
  bool _isExitPressed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Panggil satu fungsi utama untuk semua proses setup
      _initializeWebView();
    });
  }

  // Fungsi async utama untuk setup yang lebih terstruktur
  Future<void> _initializeWebView() async {
    // Langkah 1: Pastikan GPS dan Izin sudah siap.
    // Jika tidak, proses akan berhenti dan menampilkan halaman error.
    final bool locationReady = await _ensureLocationEnabledAndPermission();
    if (!locationReady) {
      if (mounted) {
        setState(() {
          _isError = true;
        });
      }
      return;
    }

    // Langkah 2: Jika lokasi sudah siap, baru setup WebView Controller.
    late final PlatformWebViewControllerCreationParams params;
    if (WebViewPlatform.instance is AndroidWebViewPlatform) {
      params = AndroidWebViewControllerCreationParams();
    } else {
      params = const PlatformWebViewControllerCreationParams();
    }

    final WebViewController controller =
        WebViewController.fromPlatformCreationParams(
          params,
          onPermissionRequest: (WebViewPermissionRequest request) async {
            if (request.types.contains(WebViewPermissionResourceType.camera)) {
              final status = await Permission.camera.request();
              status.isGranted ? await request.grant() : await request.deny();
              return;
            }
            if (request.types.contains(
              WebViewPermissionResourceType.microphone,
            )) {
              final status = await Permission.microphone.request();
              status.isGranted ? await request.grant() : await request.deny();
              return;
            }
            await request.deny();
          },
        );

    controller
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0x00000000))
      ..setNavigationDelegate(
        NavigationDelegate(
          onWebResourceError: (WebResourceError error) {
            if (error.isForMainFrame ?? false) {
              if (mounted) {
                setState(() {
                  _isError = true;
                });
              }
            }
          },
        ),
      );

    if (controller.platform is AndroidWebViewController) {
      final androidController = controller.platform as AndroidWebViewController;
      androidController.setGeolocationEnabled(true);
      // Handler izin lokasi dari webview sekarang menggunakan permission_handler
      androidController.setGeolocationPermissionsPromptCallbacks(
        onShowPrompt:
            (GeolocationPermissionsRequestParams requestParams) async {
              final status = await Permission.location.request();
              return GeolocationPermissionsResponse.new(
                allow: status.isGranted,
                retain: false,
              );
            },
        onHidePrompt: () {},
      );
    }

    // Langkah 3: Simpan controller ke state untuk menampilkan UI WebView
    if (mounted) {
      setState(() {
        _controller = controller;
      });
    }

    // Langkah 4: Terakhir, muat URL-nya
    await _controller?.loadRequest(
      Uri.parse('https://sintren.indramayukab.go.id/'),
    );
  }

  // == FUNGSI INI DIPERBAIKI SECARA TOTAL UNTUK MENGATASI RACE CONDITION ==
  Future<bool> _ensureLocationEnabledAndPermission() async {
    // Langkah 1: Minta Izin Aplikasi terlebih dahulu. Ini harus jadi yang pertama.
    PermissionStatus permissionStatus = await Permission.location.status;
    if (permissionStatus.isDenied) {
      // isDenied berarti belum pernah ditanya atau ditolak sekali.
      // Minta izin sekarang. Ini akan menampilkan dialog sistem untuk izin aplikasi.
      permissionStatus = await Permission.location.request();
    }

    if (permissionStatus.isPermanentlyDenied) {
      // Pengguna menolak permanen. Beri tahu dan ajak ke pengaturan.
      Fluttertoast.showToast(
        msg: 'Izin lokasi ditolak permanen. Aktifkan di pengaturan aplikasi.',
      );
      await openAppSettings();
      return false;
    }

    if (!permissionStatus.isGranted) {
      // Pengguna menolak izin (tapi bukan permanen).
      Fluttertoast.showToast(
        msg: 'Aplikasi membutuhkan izin lokasi untuk berfungsi.',
      );
      return false;
    }

    // --- Jika sampai sini, berarti izin aplikasi SUDAH DIBERIKAN ---

    // Langkah 2: BARU setelah izin aplikasi ada, cek layanan GPS perangkat.
    final loc.Location locationService = loc.Location();
    bool serviceEnabled;
    try {
      serviceEnabled = await locationService.serviceEnabled();
      if (!serviceEnabled) {
        // Minta pengguna untuk menyalakan GPS-nya.
        // Ini akan menampilkan dialog sistem kedua (untuk mengaktifkan GPS).
        serviceEnabled = await locationService.requestService();
        if (!serviceEnabled) {
          // Pengguna menolak menyalakan GPS.
          Fluttertoast.showToast(
            msg:
                'Untuk pengalaman yang lebih baik, aktifkan GPS di perangkat Anda.',
          );
          return false;
        }
      }
    } catch (e) {
      // Menangani jika ada error tak terduga saat mengecek service GPS
      Fluttertoast.showToast(msg: 'Gagal memeriksa status layanan lokasi.');
      return false;
    }

    // Jika semua berhasil (izin diberikan DAN GPS aktif)
    return true;
  }

  void _retryLoading() {
    setState(() {
      _isError = false;
      // Panggil kembali fungsi setup utama untuk mencoba lagi dari awal
      _initializeWebView();
    });
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) async {
        if (didPop) return;
        if (await _controller?.canGoBack() ?? false) {
          _controller?.goBack();
        } else {
          if (_isExitPressed) {
            SystemNavigator.pop();
          } else {
            setState(() {
              _isExitPressed = true;
            });
            Fluttertoast.showToast(
              msg: "Tekan sekali lagi untuk keluar",
              toastLength: Toast.LENGTH_SHORT,
              gravity: ToastGravity.BOTTOM,
              backgroundColor: Colors.grey.shade800,
              textColor: Colors.white,
              fontSize: 16.0,
            );
            Future.delayed(const Duration(seconds: 5), () {
              if (mounted) {
                setState(() {
                  _isExitPressed = false;
                });
              }
            });
          }
        }
      },
      child: Scaffold(
        body: SafeArea(
          child: _controller == null && !_isError
              ? const Center(child: CircularProgressIndicator())
              : !_isError
              ? WebViewWidget(controller: _controller!)
              : Center(
                  child: Padding(
                    padding: const EdgeInsets.all(20.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.cloud_off_outlined,
                          size: 120,
                          color: Colors.grey[600],
                        ),
                        const SizedBox(height: 20),
                        const Text(
                          'Gagal Memuat Halaman',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'Periksa kembali koneksi internet Anda lalu coba lagi.', /////mundur dulu
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey[600],
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 30),
                        ElevatedButton.icon(
                          onPressed: _retryLoading,
                          icon: const Icon(Icons.refresh),
                          label: const Text('Coba Lagi'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Theme.of(context).primaryColor,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 30,
                              vertical: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
        ),
      ),
    );
  }
}
