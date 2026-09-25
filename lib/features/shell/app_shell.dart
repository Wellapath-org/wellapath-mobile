/// The app shell: Home, Learn and More behind a labelled bottom bar.
///
/// Three tabs, every one of them a finished screen. The bar is deliberately
/// short — a tab that opens an empty or half-built page costs more trust than
/// it buys, so nothing is listed here that does not work today.
///
/// Labels are always visible. Icon-only navigation asks people to guess, and
/// this app is used by people who are unwell and in a hurry.
///
/// An [IndexedStack] keeps each tab's state alive, so switching to Learn and
/// back does not rebuild or reset the home screen.
library;

import 'package:flutter/material.dart';

import '../../shared/theme/brand.dart';
import '../home/home_screen.dart';
import '../learn/learn_screen.dart';
import '../more/more_screen.dart';

enum ShellTab { home, learn, more }

/// Lets a tab's content switch tabs — so Home's *How WellaPath works* card
/// moves to the Learn tab instead of pushing a second copy of it on top.
///
/// Lookup is nullable on purpose: every tab screen also works standalone (in
/// tests, and if one is ever pushed as an ordinary route), and falls back to
/// pushing a route when no shell is above it.
class ShellScope extends InheritedWidget {
  const ShellScope({super.key, required this.select, required super.child});

  final ValueChanged<ShellTab> select;

  static ShellScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ShellScope>();

  @override
  bool updateShouldNotify(ShellScope oldWidget) => select != oldWidget.select;
}

class AppShell extends StatefulWidget {
  const AppShell({super.key, this.initialTab = ShellTab.home});

  final ShellTab initialTab;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  late int _index = widget.initialTab.index;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Brand.surface,
      body: ShellScope(
        select: (tab) => setState(() => _index = tab.index),
        child: IndexedStack(
          index: _index,
          children: const [HomeScreen(), LearnScreen(), MoreScreen()],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        backgroundColor: Brand.surface,
        indicatorColor: Brand.primaryTint,
        surfaceTintColor: Colors.transparent,
        elevation: 3,
        height: 68,
        // Labels always visible — see the library comment.
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home_rounded, color: Brand.primary),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.lightbulb_outline_rounded),
            selectedIcon: Icon(Icons.lightbulb_rounded, color: Brand.primary),
            label: 'Learn',
          ),
          NavigationDestination(
            icon: Icon(Icons.more_horiz_rounded),
            selectedIcon: Icon(Icons.more_horiz_rounded, color: Brand.primary),
            label: 'More',
          ),
        ],
      ),
    );
  }
}
