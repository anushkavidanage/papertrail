/// Converts [Receipt] objects to and from Turtle (TTL) documents.
///
/// Each receipt is stored as one Turtle file on the Pod. To guarantee a
/// lossless round-trip (free-text titles/descriptions can contain quotes,
/// newlines and other characters that are awkward to escape in Turtle), the
/// canonical payload is a base64-encoded JSON string carried in a single
/// `pt:data` triple. Human-readable triples (label, price, dates, ...) are
/// emitted alongside it for transparency and so the file is meaningful when
/// browsed with other Solid tools, but only `pt:data` is read back.
library;

import 'dart:convert';

import '../models/receipt.dart';

class ReceiptSerializer {
  /// Vocabulary namespace for Papertrail-specific predicates.
  static const String ptNs = 'https://papertrail.anu.edu.au/ns#';

  /// Serialise [receipt] to a Turtle document string.
  static String toTurtle(Receipt receipt) {
    final json = jsonEncode(receipt.toJson());
    final data = base64.encode(utf8.encode(json));

    final buffer = StringBuffer()
      ..writeln('@prefix pt: <$ptNs> .')
      ..writeln('@prefix rdf: <http://www.w3.org/1999/02/22-rdf-syntax-ns#> .')
      ..writeln('@prefix rdfs: <http://www.w3.org/2000/01/rdf-schema#> .')
      ..writeln('@prefix schema: <https://schema.org/> .')
      ..writeln('@prefix xsd: <http://www.w3.org/2001/XMLSchema#> .')
      ..writeln()
      ..writeln('<#receipt> a pt:Receipt ;')
      ..writeln('    rdfs:label ${_lit(receipt.title)} ;')
      ..writeln('    schema:price "${receipt.amount}"^^xsd:decimal ;')
      ..writeln('    schema:priceCurrency ${_lit(receipt.currency)} ;')
      ..writeln(
          '    pt:purchaseDate "${_date(receipt.purchaseDate)}"^^xsd:date ;');

    if (receipt.vendor.isNotEmpty) {
      buffer.writeln('    schema:seller ${_lit(receipt.vendor)} ;');
    }
    for (final category in receipt.categories) {
      buffer.writeln('    pt:category ${_lit(category)} ;');
    }
    for (final flag in receipt.flags) {
      buffer.writeln('    pt:flag ${_lit(flag)} ;');
    }
    buffer.writeln('    pt:hasWarranty "${receipt.hasWarranty}"^^xsd:boolean ;');
    if (receipt.hasWarranty && receipt.warrantyExpiry != null) {
      buffer.writeln(
          '    pt:warrantyExpiry "${_date(receipt.warrantyExpiry!)}"^^xsd:date ;');
    }
    if (receipt.hasAttachment) {
      buffer.writeln('    pt:attachmentExtension ${_lit(receipt.attachmentExtension!)} ;');
    }

    // The canonical, machine-read payload. Always last.
    buffer.writeln('    pt:data "$data" .');

    return buffer.toString();
  }

  /// Parse a Turtle document produced by [toTurtle] back into a [Receipt].
  ///
  /// Throws [FormatException] when the canonical `pt:data` triple is missing
  /// or cannot be decoded.
  static Receipt fromTurtle(String turtle) {
    // base64 alphabet is [A-Za-z0-9+/=]; capture the literal after `pt:data`.
    final match =
        RegExp(r'pt:data\s+"([A-Za-z0-9+/=]+)"').firstMatch(turtle);
    if (match == null) {
      throw const FormatException('No pt:data payload found in receipt file.');
    }
    final json = utf8.decode(base64.decode(match.group(1)!));
    final map = jsonDecode(json) as Map<String, dynamic>;
    return Receipt.fromJson(map);
  }

  /// Format a [DateTime] as an `xsd:date` (YYYY-MM-DD).
  static String _date(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  /// Produce a safely-escaped Turtle string literal.
  static String _lit(String value) {
    final escaped = value
        .replaceAll('\\', r'\\')
        .replaceAll('"', r'\"')
        .replaceAll('\n', r'\n')
        .replaceAll('\r', r'\r')
        .replaceAll('\t', r'\t');
    return '"$escaped"';
  }
}
