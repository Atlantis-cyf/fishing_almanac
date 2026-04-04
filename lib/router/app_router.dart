import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:fishing_almanac/auth/auth_session.dart';
import 'package:fishing_almanac/router/auth_redirect.dart';
import 'package:fishing_almanac/router/feed_detail_route_args.dart';
import 'package:fishing_almanac/screens/edit_catch_screen.dart';
import 'package:fishing_almanac/screens/encyclopedia_screen.dart';
import 'package:fishing_almanac/screens/feed_detail_screen.dart';
import 'package:fishing_almanac/screens/home_screen.dart';
import 'package:fishing_almanac/screens/login_screen.dart';
import 'package:fishing_almanac/screens/profile_screen.dart';
import 'package:fishing_almanac/screens/record_screen.dart';
import 'package:fishing_almanac/screens/register_screen.dart';
import 'package:fishing_almanac/screens/select_location_screen.dart';
import 'package:fishing_almanac/screens/species_detail_screen.dart';
import 'package:fishing_almanac/screens/welcome_screen.dart';

final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();

String? _parseEditCatchExtra(Object? extra) {
  if (extra is String && extra.isNotEmpty) return extra;
  return null;
}

String _parseSpeciesDetailExtra(Object? extra) {
  if (extra is String && extra.isNotEmpty) return extra;
  return 'Thunnus thynnus';
}

GoRouter createAppRouter({required AuthSession authSession}) {
  return GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: '/',
    refreshListenable: authSession,
    redirect: (context, state) => authRedirect(authSession, state),
    routes: [
      GoRoute(path: '/', builder: (c, s) => const WelcomeScreen()),
      GoRoute(path: '/login', builder: (c, s) => const LoginScreen()),
      GoRoute(path: '/register', builder: (c, s) => const RegisterScreen()),
      GoRoute(path: '/home', builder: (c, s) => const HomeScreen()),
      GoRoute(path: '/encyclopedia', builder: (c, s) => const EncyclopediaScreen()),
      GoRoute(
        path: '/species-detail',
        builder: (c, s) => SpeciesDetailScreen(speciesScientificName: _parseSpeciesDetailExtra(s.extra)),
      ),
      GoRoute(path: '/record', builder: (c, s) => const RecordScreen()),
      GoRoute(path: '/select-location', builder: (c, s) => const SelectLocationScreen()),
      GoRoute(
        path: '/edit-catch',
        builder: (c, s) => EditCatchScreen(editingPublishedId: _parseEditCatchExtra(s.extra)),
      ),
      GoRoute(
        path: '/feed-detail/:scientificName',
        builder: (c, s) {
          final args = parseFeedDetailRouteArgs(s);
          return FeedDetailScreen(
            initialIndex: args.initialIndex,
            speciesScientificName: args.speciesScientificName,
            anchorCatchId: args.anchorCatchId,
          );
        },
      ),
      GoRoute(
        path: '/feed-detail',
        builder: (c, s) {
          final args = parseFeedDetailRouteArgs(s);
          return FeedDetailScreen(
            initialIndex: args.initialIndex,
            speciesScientificName: args.speciesScientificName,
            anchorCatchId: args.anchorCatchId,
          );
        },
      ),
      GoRoute(path: '/profile', builder: (c, s) => const ProfileScreen()),
    ],
  );
}
