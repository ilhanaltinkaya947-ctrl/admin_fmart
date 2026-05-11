import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// Shows Yandex's public courier-tracking page in a WebView.
///
/// The URL is the same `sharing_url` we already surface in the
/// delivery section's "Ссылка курьера" row — Yandex serves a
/// live-updating courier dot + route + ETA on that page. We just
/// load it inside the app so admin doesn't have to switch to Safari
/// or paste the link somewhere.
///
/// Pass the URL the cubit already fetched (DeliveryCubit.loadCourierLink)
/// so this widget doesn't have to know about the repo.
class CourierMapPage extends StatefulWidget {
  final String url;
  final int orderId;
  const CourierMapPage({super.key, required this.url, required this.orderId});

  @override
  State<CourierMapPage> createState() => _CourierMapPageState();
}

class _CourierMapPageState extends State<CourierMapPage> {
  late final WebViewController _controller;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.white)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) {
            if (mounted) setState(() => _loading = true);
          },
          onPageFinished: (_) {
            if (mounted) setState(() => _loading = false);
          },
          onWebResourceError: (_) {
            if (mounted) {
              setState(() {
                _loading = false;
                _error = 'Не удалось открыть карту';
              });
            }
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.url));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Курьер заказа #${widget.orderId}'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Обновить',
            onPressed: () => _controller.reload(),
          ),
        ],
      ),
      body: Stack(
        children: [
          WebViewWidget(controller: _controller),
          if (_error != null) _ErrorOverlay(message: _error!, onRetry: () {
            setState(() {
              _loading = true;
              _error = null;
            });
            _controller.reload();
          }),
          if (_loading)
            const Center(
              child: CircularProgressIndicator(color: Color(0xFFEE6F00)),
            ),
        ],
      ),
    );
  }
}

class _ErrorOverlay extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorOverlay({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.all(24),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.location_off_outlined,
                size: 48, color: Colors.grey.shade400),
            const SizedBox(height: 12),
            Text(message,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 15)),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Повторить'),
            ),
          ],
        ),
      ),
    );
  }
}
