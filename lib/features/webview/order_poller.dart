// import 'dart:async';
// import 'dart:convert';
//
// import 'package:audioplayers/audioplayers.dart';
// import 'package:flutter/material.dart';
// import 'package:flutter_inappwebview/flutter_inappwebview.dart';
// import 'package:http/http.dart' as http;
// import 'package:shared_preferences/shared_preferences.dart';
//
// class OrderPoller {
//   final InAppWebViewController webController;
//   final String baseApiUrl;
//   final Duration interval;
//
//   final Set<int> _alreadyShown = {};
//   final AudioPlayer _player = AudioPlayer();
//   Timer? _timer;
//   bool _dialogOpen = false;
//   bool _ringing = false;
//   int? _ringingOrderId;
//
//   OrderPoller({
//     required this.webController,
//     required this.baseApiUrl,
//     this.interval = const Duration(minutes: 1),
//   });
//
//   Future<void> _startRinging({required int orderId}) async {
//     if (_ringing && _ringingOrderId == orderId) return;
//
//     _ringingOrderId = orderId;
//     _ringing = true;
//
//     await _player.stop();
//     await _player.setReleaseMode(ReleaseMode.loop);
//     await _player.setVolume(1.0);
//
//     await _player.play(AssetSource('sounds/new_order.mp3'));
//   }
//
//   Future<void> _stopRinging() async {
//     _ringing = false;
//     _ringingOrderId = null;
//     try {
//       await _player.stop();
//     } catch (_) {}
//   }
//
//   void start(BuildContext context) {
//     _timer?.cancel();
//     _tick(context);
//     _timer = Timer.periodic(interval, (_) => _tick(context));
//   }
//
//   void stop() {
//     _timer?.cancel();
//     _timer = null;
//     _stopRinging();
//     _player.dispose();
//   }
//
//   Future<void> _tick(BuildContext context) async {
//     if (_dialogOpen) return;
//
//     try {
//       final sp = await SharedPreferences.getInstance();
//       final store = sp.getString('selected_store') ?? '';
//       if (store.isEmpty) return;
//
//       final uri = Uri.parse(baseApiUrl).replace(queryParameters: {
//         'store': store,
//         'limit': '5',
//       });
//
//       final resp = await http.get(uri);
//       print("Отправлено");
//       if (resp.statusCode < 200 || resp.statusCode >= 300) return;
//
//       final jsonBody = json.decode(resp.body) as Map<String, dynamic>;
//       final orders =
//           (jsonBody['orders'] as List?)?.cast<Map<String, dynamic>>() ?? [];
//       if (orders.isEmpty) return;
//
//       final firstNew = orders.firstWhere(
//             (o) => !_alreadyShown.contains(o['id']),
//         orElse: () => {},
//       );
//       if (firstNew.isEmpty) return;
//
//       final int orderId = firstNew['id'];
//       final String orderUrl = firstNew['url'];
//
//       _alreadyShown.add(orderId);
//
//       await _startRinging(orderId: orderId);
//
//       _dialogOpen = true;
//
//       // context.mounted тут будет работать только если ты на свежем Flutter,
//       // иначе следи за жизненным циклом снаружи.
//       if (!context.mounted) return;
//
//       await showDialog(
//         context: context,
//         barrierDismissible: false,
//         builder: (ctx) => AlertDialog(
//           title: const Text('Новый заказ'),
//           content: Text('Заказ #$orderId ($store)'),
//           actions: [
//             TextButton(
//               onPressed: () {
//                 _dialogOpen = false;
//                 Navigator.of(ctx).pop();
//               },
//               child: const Text('Позже'),
//             ),
//             ElevatedButton(
//               onPressed: () async {
//                 await webController.loadUrl(
//                   urlRequest: URLRequest(
//                     url: WebUri(orderUrl),
//                   ),
//                 );
//                 await _stopRinging();
//                 _dialogOpen = false;
//                 if (ctx.mounted) Navigator.of(ctx).pop();
//               },
//               child: const Text('Принять'),
//             ),
//           ],
//         ),
//       );
//     } catch (_) {
//       // можешь добавить логирование, если хочешь видеть фейлы запросов
//     }
//   }
// }
