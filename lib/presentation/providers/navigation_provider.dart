import 'package:flutter_riverpod/flutter_riverpod.dart';

class MainTabNotifier extends Notifier<int> {
  @override
  int build() => 0;

  void select(int index) {
    if (index >= 0 && index < 4) state = index;
  }
}

final mainTabProvider = NotifierProvider<MainTabNotifier, int>(
  MainTabNotifier.new,
);
