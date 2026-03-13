// import 'package:flutter/material.dart';
// import 'package:shared_preferences/shared_preferences.dart';
//
// class StorePickerPage extends StatefulWidget {
//   const StorePickerPage({super.key});
//
//   @override
//   State<StorePickerPage> createState() => _StorePickerPageState();
// }
//
// class _StorePickerPageState extends State<StorePickerPage> {
//   final List<String> stores = const [
//     'F-Mart Аэровокзал',
//     'F-Mart Фиркан Сити',
//     'F-Mart Shymkent Mall',
//     'F-Mart Адырбекова'
//   ];
//   String? _selected;
//
//   @override
//   void initState() {
//     super.initState();
//     _loadSelected();
//   }
//
//   Future<void> _loadSelected() async {
//     final sp = await SharedPreferences.getInstance();
//     setState(() {
//       _selected = sp.getString('selected_store');
//     });
//   }
//
//   Future<void> _saveAndContinue(String store) async {
//     final sp = await SharedPreferences.getInstance();
//     await sp.setString('selected_store', store);
//     if (!mounted) return;
//     Navigator.of(context).pushReplacementNamed('/webview');
//   }
//
//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       appBar: AppBar(title: const Text('Выберите магазин')),
//       body: ListView.separated(
//         padding: const EdgeInsets.all(12),
//         itemBuilder: (_, i) {
//           final s = stores[i];
//           return ListTile(
//             title: Text(s),
//             trailing: _selected == s ? const Icon(Icons.check, color: Colors.green) : null,
//             onTap: () => _saveAndContinue(s),
//           );
//         },
//         separatorBuilder: (_, __) => const Divider(height: 1),
//         itemCount: stores.length,
//       ),
//     );
//   }
// }
