import 'package:auto_route/auto_route.dart';
import 'package:supervecina/common/router/route_guards.dart';
import 'package:supervecina/features/account/screens/account_screen.dart';
import 'package:supervecina/features/account/screens/done_backup_screen.dart';
import 'package:supervecina/features/account/screens/profile.dart';
import 'package:supervecina/features/account/screens/protect_your_wallet.dart';
import 'package:supervecina/features/account/screens/settings.dart';
import 'package:supervecina/features/account/screens/show_mnemonic.dart';
import 'package:supervecina/features/account/screens/verify_mnemonic.dart';

const accountTab = AutoRoute(
  path: 'account',
  name: 'accountTab',
  page: EmptyRouterPage,
  guards: [AuthGuard],
  children: [
    AutoRoute(
      page: AccountScreen,
      name: 'accountScreen',
      initial: true,
      guards: [AuthGuard],
    ),
    AutoRoute(
      page: ShowMnemonic,
      guards: [AuthGuard],
    ),
    AutoRoute(
      page: VerifyMnemonic,
      guards: [AuthGuard],
    ),
    AutoRoute(
      page: DoneBackup,
      guards: [AuthGuard],
    ),
    AutoRoute(
      page: SettingsScreen,
      guards: [AuthGuard],
    ),
    AutoRoute(
      page: ProtectYourWallet,
      guards: [AuthGuard],
    ),
    AutoRoute(
      page: ProfileScreen,
      guards: [AuthGuard],
    ),
  ],
);
