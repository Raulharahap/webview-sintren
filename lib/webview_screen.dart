import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:url_launcher/url_launcher.dart';
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
  // Variabel `_isLoadingPage` dihapus karena loading indicator Flutter tidak digunakan lagi

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeWebView();
    });
  }

  Future<void> _initializeWebView() async {
    // Cek GPS & Izin. Jika ditolak, aplikasi tetap lanjut.
    await _ensureLocationEnabledAndPermission();

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
          // onPageStarted dan onPageFinished dihapus untuk menghilangkan loading indicator Flutter
          onWebResourceError: (WebResourceError error) {
            if (error.isForMainFrame ?? false) {
              if (mounted)
                setState(() {
                  _isError = true;
                });
            }
          },
          // INI SOLUSI UNTUK LINK EKSTERNAL (FB, WA, DLL)
          onNavigationRequest: (NavigationRequest request) {
            final uri = Uri.parse(request.url);
            // Jika link BUKAN dari website utama, buka di luar.
            if (!uri.host.contains('sintren.indramayukab.go.id')) {
              launchUrl(uri, mode: LaunchMode.externalApplication);
              return NavigationDecision
                  .prevent; // Hentikan WebView membuka link
            }
            return NavigationDecision.navigate; // Izinkan WebView membuka link
          },
        ),
      );

    if (controller.platform is AndroidWebViewController) {
      (controller.platform as AndroidWebViewController)
        ..setGeolocationEnabled(true)
        ..setGeolocationPermissionsPromptCallbacks(
          onShowPrompt:
              (GeolocationPermissionsRequestParams requestParams) async {
                final status = await Permission.location.request();
                return GeolocationPermissionsResponse.new(
                  allow: status.isGranted,
                  retain: false,
                );
              },
        );
    }

    if (mounted) {
      setState(() {
        _controller = controller;
      });
    }

    await _controller?.loadRequest(
      Uri.parse('https://sintren.indramayukab.go.id/'),
    );
  }

  // == LOGIKA IZIN & GPS DIPERBAIKI TOTAL ==
  Future<void> _ensureLocationEnabledAndPermission() async {
    // 1. Minta izin lokasi aplikasi terlebih dahulu
    PermissionStatus permissionStatus = await Permission.location.request();

    if (permissionStatus.isPermanentlyDenied) {
      Fluttertoast.showToast(
        msg: 'Izin lokasi ditolak permanen. Aktifkan di pengaturan aplikasi.',
      );
      await openAppSettings();
      return;
    }

    if (!permissionStatus.isGranted) {
      Fluttertoast.showToast(
        msg: 'Aplikasi ini bekerja lebih baik dengan izin lokasi.',
      );
      // Tetap lanjutkan meskipun izin ditolak
    }

    // 2. Jika izin ada (atau baru diberikan), baru cek layanan GPS
    if (permissionStatus.isGranted) {
      final loc.Location locationService = loc.Location();
      bool serviceEnabled;
      try {
        serviceEnabled = await locationService.serviceEnabled();
        if (!serviceEnabled) {
          serviceEnabled = await locationService.requestService();
          if (!serviceEnabled) {
            // == PERBAIKAN: KATA-KATA TOAST DISESUAIKAN ==
            Fluttertoast.showToast(
              msg: 'Fitur cuaca akan lebih akurat jika Anda mengaktifkan GPS.',
            );
            // Tetap lanjutkan meskipun GPS tidak diaktifkan
          }
        }
      } catch (e) {
        debugPrint("Error checking location service: $e");
      }
    }
  }

  void _retryLoading() {
    setState(() {
      _isError = false;
      _controller = null; // Reset controller
    });
    // Panggil kembali fungsi setup utama
    _initializeWebView();
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
            Future.delayed(const Duration(seconds: 2), () {
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
          child: Stack(
            children: [
              // Tampilkan WebView jika sudah siap dan tidak error
              if (_controller != null && !_isError)
                WebViewWidget(controller: _controller!),

              // Tampilkan halaman error jika terjadi masalah
              if (_isError)
                Center(
                  child: Padding(
                    padding: const EdgeInsets.all(20.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.cloud_off_outlined,
                          size: 120,
                          color: Colors.grey,
                        ),
                        const SizedBox(height: 20),
                        const Text(
                          'Koneksi Gagal',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 10),
                        const Text(
                          'Periksa kembali koneksi internet Anda lalu coba lagi.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey),
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
            ],
          ),
        ),
      ),
    );
  }
}
