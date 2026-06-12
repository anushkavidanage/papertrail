/// Root widget: themed [MaterialApp] gated behind Solid Pod login.
library;

import 'package:flutter/material.dart';
import 'package:solidui/solidui.dart';

import 'constants/app_config.dart';
import 'screens/home_shell.dart';

class PapertrailApp extends StatelessWidget {
  const PapertrailApp({super.key});

  @override
  Widget build(BuildContext context) {
    return SolidThemeApp(
      title: appTitle,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: seedColor),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: seedColor,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      // SolidLogin handles the OIDC flow and only shows [child] once the user
      // is authenticated against their Pod.
      home: const SolidLogin(
        appDirectory: appDirectory,
        title: 'PaperTrail',
        image: loginCoverImage,
        logo: appLogo,
        link: 'https://solidproject.org',
        clientId: clientId,
        redirectUris: redirectUris,
        postLogoutRedirectUris: postLogoutRedirectUris,
        autoLogin: true,
        child: HomeShell(),
      ),
    );
  }
}
