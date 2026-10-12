/// Icons that stand for receipt categories.
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

/// Icons for the built-in categories in `defaultCategories`, keyed by
/// lower-case name so user-typed variants such as "grocery" still match.
const Map<String, IconData> _categoryIcons = {
  'grocery': Icons.shopping_basket_outlined,
  'electronics': Icons.devices_other_outlined,
  'garden': Icons.yard_outlined,
  'clothing': Icons.checkroom_outlined,
  'dining': Icons.restaurant_outlined,
  'health': Icons.health_and_safety_outlined,
  'transport': Icons.directions_bus_outlined,
  'utilities': Icons.bolt_outlined,
  'entertainment': Icons.movie_outlined,
  'home': Icons.chair_outlined,
  'pets': Icons.pets_outlined,
  'travel': Icons.flight_outlined,
  'education': Icons.school_outlined,
  'gas': Icons.local_gas_station_outlined,
};

/// The icon for [category], or null for "Other" and custom categories.
IconData? categoryIcon(String category) =>
    _categoryIcons[category.trim().toLowerCase()];
