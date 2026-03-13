// import 'package:flutter/material.dart';
// import 'package:flutter_inappwebview/flutter_inappwebview.dart';
// import 'package:shared_preferences/shared_preferences.dart';
//
// import 'order_poller.dart';
//
// class WebViewContainer extends StatefulWidget {
//   const WebViewContainer({super.key});
//
//   @override
//   State<WebViewContainer> createState() => _WebViewContainerState();
// }
//
// class _WebViewContainerState extends State<WebViewContainer> {
//   int loadingPercentage = 0;
//   InAppWebViewController? _webViewController;
//   OrderPoller? poller;
//
//   @override
//   void initState() {
//     super.initState();
//     _initAfterBuild();
//   }
//
//   Future<void> _initAfterBuild() async {
//     // ждём, пока будет контекст
//     WidgetsBinding.instance.addPostFrameCallback((_) async {
//       final sp = await SharedPreferences.getInstance();
//       final store = sp.getString('selected_store');
//
//       if (!mounted) return;
//
//       if (store == null || store.isEmpty) {
//         Navigator.of(context).pushReplacementNamed('/pick-store');
//         return;
//       }
//
//       // Ждём, пока создастся webViewController
//       // Если этот код срабатывает раньше onWebViewCreated —
//       // poller не создастся, поэтому делаем проверку.
//       if (_webViewController != null) {
//         _createAndStartPoller();
//       }
//     });
//   }
//
//   void _createAndStartPoller() {
//     if (poller != null || _webViewController == null) return;
//
//     poller = OrderPoller(
//       webController: _webViewController!,
//       baseApiUrl: 'https://testfmart.site/wp-json/fmart/v1/new-orders',
//       interval: const Duration(minutes: 1),
//     );
//     poller!.start(context);
//   }
//
//   @override
//   void dispose() {
//     poller?.stop();
//     super.dispose();
//   }
//
//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       appBar: PreferredSize(
//         preferredSize: Size.fromHeight(10),
//         child: AppBar(elevation: 0),
//       ),
//       body: Stack(
//         children: [
//           InAppWebView(
//             initialUrlRequest: URLRequest(
//               url: WebUri('https://testfmart.site/wp-admin'),
//             ),
//             initialSettings: InAppWebViewSettings(
//               javaScriptEnabled: true,
//               javaScriptCanOpenWindowsAutomatically: true,
//               // useShouldOverrideUrlLoading: true,
//               transparentBackground: true,
//             ),
//             onWebViewCreated: (controller) {
//               _webViewController = controller;
//               // Если store уже выбран и initAfterBuild успел отработать —
//               // можно тут же поднять poller
//               _createAndStartPoller();
//             },
//             onLoadStart: (controller, url) {
//               debugPrint('InAppWebView: onLoadStart = $url');
//               setState(() => loadingPercentage = 0);
//             },
//             onProgressChanged: (controller, progress) {
//               // progress 0–100
//               setState(() => loadingPercentage = progress);
//             },
//             onLoadStop: (controller, url) async {
//               debugPrint('InAppWebView: onLoadStop = $url');
//
//               // Вставка meta viewport
//               try {
//                 await controller.evaluateJavascript(source: """
//                   (function() {
//                     var meta = document.querySelector('meta[name="viewport"]');
//                     if (!meta) {
//                       meta = document.createElement('meta');
//                       meta.name = 'viewport';
//                       meta.content = 'width=device-width, initial-scale=1.0, user-scalable=no';
//                       document.head.appendChild(meta);
//                     } else {
//                       meta.content = 'width=device-width, initial-scale=1.0, user-scalable=no';
//                     }
//                   })();
//                 """);
//               } catch (e) {
//                 debugPrint('InAppWebView: error injecting viewport meta: $e');
//               }
//
//               setState(() => loadingPercentage = 100);
//             },
//
//             // ЛОВИМ ОШИБКИ, ЧТОБЫ НЕ ХОДИТЬ В ТЕМНОТЕ
//
//             onReceivedError: (controller, request, error) {
//               debugPrint(
//                   'InAppWebView ERROR: ${error.type} - ${error.description} for ${request.url}');
//               // чтобы не висел прогрессбар вечно
//               setState(() => loadingPercentage = 100);
//             },
//             onReceivedHttpError: (controller, request, errorResponse) {
//               debugPrint(
//                   'InAppWebView HTTP ERROR: ${errorResponse.statusCode} for ${request.url}');
//             },
//
//             // JS-диалоги
//
//             onJsAlert: (controller, jsAlertRequest) async {
//               await showDialog(
//                 context: context,
//                 builder: (ctx) => AlertDialog(
//                   title: const Text('Сообщение'),
//                   content: Text(jsAlertRequest.message!),
//                   actions: [
//                     TextButton(
//                       onPressed: () => Navigator.of(ctx).pop(),
//                       child: const Text('OK'),
//                     ),
//                   ],
//                 ),
//               );
//
//               return JsAlertResponse(
//                 handledByClient: true,
//                 action: JsAlertResponseAction.CONFIRM,
//               );
//             },
//             onJsConfirm: (controller, jsConfirmRequest) async {
//               final result = await showDialog<bool>(
//                 context: context,
//                 builder: (ctx) => AlertDialog(
//                   title: const Text('Подтверждение'),
//                   content: Text(jsConfirmRequest.message!),
//                   actions: [
//                     TextButton(
//                       onPressed: () => Navigator.of(ctx).pop(false),
//                       child: const Text('Отмена'),
//                     ),
//                     TextButton(
//                       onPressed: () => Navigator.of(ctx).pop(true),
//                       child: const Text('OK'),
//                     ),
//                   ],
//                 ),
//               );
//
//               return JsConfirmResponse(
//                 handledByClient: true,
//                 action: (result ?? false)
//                     ? JsConfirmResponseAction.CONFIRM
//                     : JsConfirmResponseAction.CANCEL,
//               );
//             },
//           ),
//
//           if (loadingPercentage < 100)
//             const LinearProgressIndicator(
//               color: Color(0xFFEE6F00),
//             ),
//         ],
//       ),
//     );
//   }
// }
