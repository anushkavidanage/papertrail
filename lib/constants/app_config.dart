/// App-wide configuration and constants for Papertrail.
///
/// Papertrail keeps track of purchase receipts, storing every receipt and its
/// attachment inside the user's own Solid Pod.
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

/// The human readable application title shown in the UI.
const String appTitle = 'Papertrail';

/// A short tagline used on the login screen.
//const String appTagline = 'Your receipts, in your own Pod.';

/// The directory name created on the Pod for this app.
///
/// All data lives under `<appDirectory>/data/...` on the Pod. Receipts are
/// written to `receipts/<id>.ttl` and attachments to `attachments/<id>`
/// (both relative to the data directory).
const String appDirectory = 'papertrail';

/// Sub-directory (relative to the Pod data directory) holding receipt files.
const String receiptsDir = 'receipts';

/// Sub-directory (relative to the Pod data directory) holding attachments.
const String attachmentsDir = 'attachments';

// ---------------------------------------------------------------------------
// Solid OIDC client configuration.
//
// These default to the publicly published example client registration used by
// the Solid demonstrator apps so that Papertrail authenticates out of the box
// during development. For a production release, register your own client
// profile document and replace the values below with your own client id and
// redirect URIs.
// ---------------------------------------------------------------------------

/// The OIDC client identifier (a URL to a hosted client profile document).
const String clientId =
    'https://anushkavidanage.github.io/apps/papertrail/client-profile.jsonld';

/// Redirect URIs registered for [clientId]. The loopback entry is used on
/// desktop/web; the custom scheme entry is used on mobile.
const List<String> redirectUris = [
  'http://localhost:4400/redirect',
  'com.example.papertrail://redirect',
  'https://anushkavidanage.github.io/apps/papertrail/redirect.html',
];

/// Post-logout redirect URIs.
const List<String> postLogoutRedirectUris = redirectUris;

// ---------------------------------------------------------------------------
// Domain vocabulary.
// ---------------------------------------------------------------------------

/// Suggested categories a receipt can belong to. Users may also add their own.
const List<String> defaultCategories = [
  'Grocery',
  'Electronics',
  'Garden',
  'Clothing',
  'Dining',
  'Health',
  'Transport',
  'Utilities',
  'Entertainment',
  'Home',
  'Pets',
  'Travel',
  'Education',
  'Gas',
  'Other',
];

/// Suggested flags a receipt can be tagged with. Users may also add their own.
const List<String> defaultFlags = [
  'Important',
  'Tax deductible',
  'Reimbursable',
  'Business',
  'Personal',
  'Gift',
  'Recurring',
  'Disputed',
];

/// Currencies offered in the receipt editor.
const List<String> currencies = [
  'AUD',
  'USD',
  'EUR',
  'GBP',
  'NZD',
  'JPY',
  'CAD',
  'INR',
  'CNY',
  'SGD',
];

/// File extensions accepted as receipt attachments.
const List<String> imageExtensions = [
  'jpg',
  'jpeg',
  'png',
  'gif',
  'webp',
  'heic',
];
const List<String> attachmentExtensions = [...imageExtensions, 'pdf'];

/// Maximum size of a receipt attachment (photo or PDF), in bytes.
const int maxAttachmentBytes = 1024 * 1024; // 1 MB

/// Brand seed colour used to derive the light/dark theme.
/// Matches the primary orange from the Papertrail logo (#ef6e37).
const Color seedColor = Color(0xFFEF6E37);

const Color lightOrage = Color(0xFFf99e77);

/// Cover photo shown on the Solid login screen.
const AssetImage loginCoverImage = AssetImage('assets/images/app_image.jpg');

/// App logo.
const AssetImage appLogo = AssetImage('assets/images/app_icon.png');
