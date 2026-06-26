/// Root widget: themed [MaterialApp] gated behind Solid Pod login.
///
/// Copyright (C) 2026, Anushka Vidanage
///
/// Licensed under the GNU General Public License, Version 3 (the "License");
///
/// License: https://opensource.org/license/gpl-3-0
//
// This program is free software: you can redistribute it and/or modify it under
// the terms of the GNU General Public License as published by the Free Software
// Foundation, either version 3 of the License, or (at your option) any later
// version.
//
// This program is distributed in the hope that it will be useful, but WITHOUT
// ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
// FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more
// details.
//
// You should have received a copy of the GNU General Public License along with
// this program.  If not, see <https://opensource.org/license/gpl-3-0>.
///
/// Authors: Anushka Vidanage

// Add the library directive as we have doc entries above. We publish the above
// meta doc lines in the docs.

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
        loginButtonStyle: LoginButtonStyle(background: lightOrage),
        child: HomeShell(),
      ),
    );
  }
}
