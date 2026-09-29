import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:flutter/services.dart' show rootBundle;

class PdfHelper {
  static Future<Uint8List> generateReport({
    required String companyName,
    required List<Map<String, Object?>> sales,
    required List<Map<String, Object?>> expenses,
    required List<Map<String, Object?>> debts,
    required List<Map<String, Object?>> products,
    required int orderCount,
    required int customerCount,
    required double cashTotal,
    required double momoTotal,
  }) async {
    final pdf = pw.Document();
    final totalSales = _sum(sales);
    final totalExpenses = _sum(expenses);
    final totalDebts = _sum(debts);
    final logo = pw.MemoryImage(
      (await rootBundle.load(
        'assets/images/watermark2.png',
      )).buffer.asUint8List(),
    );

    pdf.addPage(
      pw.MultiPage(
        pageTheme: pw.PageTheme(
          theme: pw.ThemeData.withFont(base: pw.Font.helvetica()),
        ),
        build: (context) => [
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                companyName,
                style: pw.TextStyle(
                  fontSize: 18,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.Row(children: [pw.Image(logo, width: 42, height: 42)]),
            ],
          ),
          pw.SizedBox(height: 12),
          pw.Center(
            child: pw.Text(
              'REPORTS',
              style: pw.TextStyle(
                color: PdfColors.black,
                fontSize: 18,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ),
          pw.Center(child: pw.Text(_date(DateTime.now()))),
          pw.SizedBox(height: 16),
          _heading('Summary'),
          pw.Table.fromTextArray(
            headers: [
              'Sales',
              'Expenses',
              'Debts',
              'Orders',
              'Customers',
              'Cash',
              'Momo',
              'Profit',
            ],
            data: [
              [
                _money(totalSales),
                _money(totalExpenses),
                _money(totalDebts),
                orderCount.toString(),
                customerCount.toString(),
                _money(cashTotal),
                _money(momoTotal),
                _money(totalSales - totalExpenses),
              ],
            ],
            headerDecoration: const pw.BoxDecoration(color: PdfColors.orange),
            headerStyle: pw.TextStyle(
              color: PdfColors.white,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          _heading('Products Sold Today'),
          _salesTable(sales),
          _heading('Expenses Today'),
          _expensesTable(expenses),
          _heading('Debts Today'),
          _debtsTable(debts),
          _heading('Inventory'),
          pw.Table.fromTextArray(
            headers: ['Product', 'Price', 'Stock Remaining'],
            data: products
                .map(
                  (product) => [
                    product['name']?.toString() ?? '',
                    _money((product['price'] as num?)?.toDouble() ?? 0),
                    product['stock']?.toString() ?? '0',
                  ],
                )
                .toList(),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.orange),
            headerStyle: pw.TextStyle(
              color: PdfColors.white,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
        ],
      ),
    );
    return pdf.save();
  }

  static pw.Widget _heading(String title) => pw.Padding(
    padding: const pw.EdgeInsets.only(top: 16, bottom: 6),
    child: pw.Text(
      title,
      style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
    ),
  );

  static pw.Widget _salesTable(List<Map<String, Object?>> rows) =>
      pw.Table.fromTextArray(
        headers: ['Product', 'Quantity', 'Amount', 'Date'],
        data: rows
            .map(
              (row) => [
                row['product']?.toString() ?? '',
                row['quantity']?.toString() ?? '-',
                _money((row['amount'] as num?)?.toDouble() ?? 0),
                _date(row['date']),
              ],
            )
            .toList(),
        headerDecoration: const pw.BoxDecoration(color: PdfColors.orange),
        headerStyle: pw.TextStyle(
          color: PdfColors.white,
          fontWeight: pw.FontWeight.bold,
        ),
      );

  static pw.Widget _expensesTable(List<Map<String, Object?>> rows) =>
      pw.Table.fromTextArray(
        headers: ['Details', 'Amount', 'Date'],
        data: rows
            .map(
              (row) => [
                row['name']?.toString() ?? '',
                _money((row['amount'] as num?)?.toDouble() ?? 0),
                _date(row['date']),
              ],
            )
            .toList(),
        headerDecoration: const pw.BoxDecoration(color: PdfColors.orange),
        headerStyle: pw.TextStyle(
          color: PdfColors.white,
          fontWeight: pw.FontWeight.bold,
        ),
      );

  static pw.Widget _debtsTable(List<Map<String, Object?>> rows) =>
      pw.Table.fromTextArray(
        headers: ['Creditor', 'Amount', 'Date'],
        data: rows
            .map(
              (row) => [
                row['creditor']?.toString() ?? '',
                _money((row['amount'] as num?)?.toDouble() ?? 0),
                _date(row['date']),
              ],
            )
            .toList(),
        headerDecoration: const pw.BoxDecoration(color: PdfColors.orange),
        headerStyle: pw.TextStyle(
          color: PdfColors.white,
          fontWeight: pw.FontWeight.bold,
        ),
      );

  static double _sum(List<Map<String, Object?>> rows) => rows.fold<double>(
    0,
    (sum, row) => sum + ((row['amount'] as num?)?.toDouble() ?? 0),
  );

  static String _money(double amount) => 'GHS ${amount.toStringAsFixed(2)}';

  static String _date(Object? value) {
    final date = DateTime.tryParse(value?.toString() ?? '');
    if (date == null) return value?.toString() ?? '';
    return '${date.day}/${date.month}/${date.year}';
  }
}
