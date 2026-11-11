import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:csv/csv.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

/// Simple table data used by every report and by the backup export.
class TableData {
  final String title;
  final List<String> headers;
  final List<List<String>> rows;

  const TableData({
    required this.title,
    required this.headers,
    required this.rows,
  });
}

/// Builds CSV/PDF files and saves them:
/// - Android: written to a temp folder, then shared (save/share sheet)
/// - Desktop: user picks a folder and the file is saved there
class ExportService {
  static String toCsv(TableData table) {
    return Csv(lineDelimiter: '\n').encode([table.headers, ...table.rows]);
  }

  static Future<Uint8List> toPdf(TableData table, {String? subtitle}) async {
    final doc = pw.Document();
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(28),
        build: (context) => [
          pw.Text(
            'CatchUP - ${table.title}',
            style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
          ),
          if (subtitle != null) pw.Text(subtitle),
          pw.SizedBox(height: 12),
          pw.TableHelper.fromTextArray(
            headers: table.headers,
            // The default PDF font has no peso sign, so print PHP instead.
            data: table.rows.map((r) => r.map((c) => c.replaceAll('₱', 'PHP ')).toList()).toList(),
            headerStyle: pw.TextStyle(
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.white,
              fontSize: 9,
            ),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.blue900),
            cellStyle: const pw.TextStyle(fontSize: 8),
          ),
        ],
      ),
    );
    return doc.save();
  }

  /// Saves [bytes] as [fileName]. Returns a message describing what happened,
  /// or null if the user cancelled.
  static Future<String?> saveOrShare(String fileName, Uint8List bytes) async {
    if (kIsWeb) {
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile.fromData(bytes, name: fileName)],
        ),
      );
      return 'Downloaded $fileName';
    }
    if (Platform.isAndroid) {
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/$fileName');
      await file.writeAsBytes(bytes);
      await SharePlus.instance.share(ShareParams(files: [XFile(file.path)]));
      return 'Shared $fileName';
    }
    final folder = await FilePicker.getDirectoryPath(
      dialogTitle: 'Choose a folder to save $fileName',
    );
    if (folder == null) return null;
    final path = '$folder${Platform.pathSeparator}$fileName';
    await File(path).writeAsBytes(bytes);
    return 'Saved to $path';
  }

  static Future<String?> exportCsv(TableData table, String fileName) {
    // UTF-8 BOM so Excel shows the peso sign correctly.
    final bytes =
        Uint8List.fromList([0xEF, 0xBB, 0xBF, ...utf8.encode(toCsv(table))]);
    return saveOrShare(fileName, bytes);
  }

  static Future<String?> exportPdf(TableData table, String fileName,
      {String? subtitle}) async {
    final bytes = await toPdf(table, subtitle: subtitle);
    if (kIsWeb) {
      await Printing.sharePdf(bytes: bytes, filename: fileName);
      return 'Downloaded $fileName';
    }
    return saveOrShare(fileName, bytes);
  }
}

