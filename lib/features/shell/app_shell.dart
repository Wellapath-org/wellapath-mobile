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

  // The callback is a stable State method, and the tab index lives in the
  // State above — dependents never need to rebuild because of this widget.
  @override
  bool updateShouldNotify(ShellScope oldWidget) => false;
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
    // Android back on a secondary tab returns to Home rather than quitting
    // the app. Without this, Back from Learn or More drops the user out to
    // the launcher, which reads as the app crashing.
    return PopScope(
      canPop: _index == ShellTab.home.index,
      onPopInvokedWithResult: (bool didPop, Object? result) {
        if (didPop) return;
        setState(() => _index = ShellTab.home.index);
      },
      child: _buildScaffold(),
    );
  }

  void _select(ShellTab tab) => setState(() => _index = tab.index);

  Widget _buildScaffold() {
    return Scaffold(
      backgroundColor: Brand.surface,
      body: ShellScope(
        select: _select,
        // IndexedStack keeps every tab alive (that is how tab state
        // survives switching), which also keeps their ticks running.
        // TickerMode stops animations on tabs nobody is looking at, so
        // Wella breathes on exactly one screen at a time.
        child: IndexedStack(
          index: _index,
          children: [
            for (final ShellTab tab in ShellTab.values)
              TickerMode(
                enabled: _index == tab.index,
                child: switch (tab) {
                  ShellTab.home => const HomeScreen(),
                  ShellTab.learn => const LearnScreen(),
                  ShellTab.more => const MoreScreen(),
                },
              ),
          ],
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
