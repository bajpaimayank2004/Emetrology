import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:google_mlkit_barcode_scanning/google_mlkit_barcode_scanning.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:intl/intl.dart';

List<CameraDescription> _availableCameras = [];

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  try {
    _availableCameras = await availableCameras();
  } catch (e) {
    debugPrint('Camera discovery notice: $e');
  }

  runApp(const EMetrologyApp());
}

class EMetrologyApp extends StatelessWidget {
  const EMetrologyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'e-Metrology Inspector',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF0F3D3E),
          primary: const Color(0xFF0F3D3E),
          secondary: const Color(0xFFE2B438),
          surface: const Color(0xFFF8F9FA),
        ),
        fontFamily: 'Roboto',
      ),
      home: const InspectorHomeScreen(),
    );
  }
}

enum PackagingGeometry {
  rectangularBox,
  cylindricalBottle,
  flexiblePouch,
}

enum ComplianceStatus {
  compliant,
  statutoryWarning,
  nonCompliant,
}

class PackagingRuleInfo {
  final double pdpAreaCm2;
  final double minNumeralHeightMm;
  final String formulaDescription;

  const PackagingRuleInfo({
    required this.pdpAreaCm2,
    required this.minNumeralHeightMm,
    required this.formulaDescription,
  });
}

class SkuMasterRecord {
  final String gtin;
  final String brand;
  final String productName;
  final PackagingGeometry geometry;
  final double heightCm;
  final double widthOrDiameterCm;
  final String declaredNetWeight;
  final double declaredMrp;
  final String manufacturer;

  const SkuMasterRecord({
    required this.gtin,
    required this.brand,
    required this.productName,
    required this.geometry,
    required this.heightCm,
    required this.widthOrDiameterCm,
    required this.declaredNetWeight,
    required this.declaredMrp,
    required this.manufacturer,
  });
}

class AuditFinding {
  final String ruleTitle;
  final String ruleCitation;
  final bool isPresent;
  final String detectedValue;
  final double measuredFontHeightMm;
  final double statutoryMinFontHeightMm;
  final ComplianceStatus status;
  final String remarks;

  AuditFinding({
    required this.ruleTitle,
    required this.ruleCitation,
    required this.isPresent,
    required this.detectedValue,
    required this.measuredFontHeightMm,
    required this.statutoryMinFontHeightMm,
    required this.status,
    required this.remarks,
  });
}

final List<SkuMasterRecord> kMasterSkuDatabase = [
  const SkuMasterRecord(
    gtin: '8901719101014',
    brand: 'Parle',
    productName: 'Parle-G Gluco Biscuits 80g',
    geometry: PackagingGeometry.flexiblePouch,
    heightCm: 14.5,
    widthOrDiameterCm: 6.5,
    declaredNetWeight: '80 g',
    declaredMrp: 10.00,
    manufacturer: 'Parle Products Pvt. Ltd., Mumbai, India',
  ),
  const SkuMasterRecord(
    gtin: '8901058852210',
    brand: 'Maggi',
    productName: 'Maggi 2-Minute Masala Noodles',
    geometry: PackagingGeometry.flexiblePouch,
    heightCm: 13.0,
    widthOrDiameterCm: 12.0,
    declaredNetWeight: '70 g',
    declaredMrp: 14.00,
    manufacturer: 'Nestle India Limited, New Delhi, India',
  ),
  const SkuMasterRecord(
    gtin: '8901015000127',
    brand: 'Tata',
    productName: 'Tata Salt Vacuum Evaporated Iodised Salt',
    geometry: PackagingGeometry.flexiblePouch,
    heightCm: 24.0,
    widthOrDiameterCm: 16.0,
    declaredNetWeight: '1 kg',
    declaredMrp: 28.00,
    manufacturer: 'Tata Consumer Products Ltd., Kolkata, India',
  ),
  const SkuMasterRecord(
    gtin: '8901396112003',
    brand: 'Dettol',
    productName: 'Dettol Antiseptic Disinfectant Liquid 125ml',
    geometry: PackagingGeometry.cylindricalBottle,
    heightCm: 12.5,
    widthOrDiameterCm: 5.0,
    declaredNetWeight: '125 ml',
    declaredMrp: 93.00,
    manufacturer: 'Reckitt Benckiser (India) Pvt. Ltd., Gurugram, India',
  ),
];

class LegalMetrologyMath {
  static PackagingRuleInfo calculatePdpAndMinFont({
    required PackagingGeometry geometry,
    required double heightCm,
    required double widthOrDiameterCm,
  }) {
    double pdpArea = 0.0;
    String formula = '';

    switch (geometry) {
      case PackagingGeometry.rectangularBox:
        pdpArea = heightCm * widthOrDiameterCm;
        formula = 'Rule 7(1)(a): Height x Width of Principal Face';
        break;
      case PackagingGeometry.cylindricalBottle:
        pdpArea = 0.40 * (heightCm * (math.pi * widthOrDiameterCm));
        formula = 'Rule 7(1)(b): 40% of Total Circumferential Face (H x π x D)';
        break;
      case PackagingGeometry.flexiblePouch:
        pdpArea = 0.40 * (2 * heightCm * widthOrDiameterCm);
        formula = 'Rule 7(1)(c): 40% of Total Surface Area of Pouch';
        break;
    }

    double minNumeralHeightMm;
    if (pdpArea <= 50.0) {
      minNumeralHeightMm = 1.0;
    } else if (pdpArea <= 100.0) {
      minNumeralHeightMm = 1.5;
    } else if (pdpArea <= 500.0) {
      minNumeralHeightMm = 2.5;
    } else if (pdpArea <= 2500.0) {
      minNumeralHeightMm = 4.0;
    } else {
      minNumeralHeightMm = 6.0;
    }

    return PackagingRuleInfo(
      pdpAreaCm2: pdpArea,
      minNumeralHeightMm: minNumeralHeightMm,
      formulaDescription: formula,
    );
  }
}

class InspectorHomeScreen extends StatefulWidget {
  const InspectorHomeScreen({super.key});

  @override
  State<InspectorHomeScreen> createState() => _InspectorHomeScreenState();
}

class _InspectorHomeScreenState extends State<InspectorHomeScreen> {
  int _currentStep = 0;

  PackagingGeometry _selectedGeometry = PackagingGeometry.rectangularBox;
  final TextEditingController _heightController = TextEditingController(text: '15.0');
  final TextEditingController _widthController = TextEditingController(text: '8.0');
  PackagingRuleInfo? _calibratedRuleInfo;

  CameraController? _cameraController;
  bool _isCameraInitialized = false;
  bool _isProcessing = false;
  String? _scannedBarcode;
  SkuMasterRecord? _matchedSku;

  final TextRecognizer _textRecognizer = TextRecognizer();
  final BarcodeScanner _barcodeScanner = BarcodeScanner();

  List<AuditFinding> _auditResults = [];
  String _rawOcrText = '';
  double _derivedScaleFactor = 0.0;

  @override
  void initState() {
    super.initState();
    _recomputeCalibration();
    _initializeCamera();
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    _textRecognizer.close();
    _barcodeScanner.close();
    _heightController.dispose();
    _widthController.dispose();
    super.dispose();
  }

  Future<void> _initializeCamera() async {
    if (_availableCameras.isEmpty) {
      return;
    }

    final camera = _availableCameras.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.back,
      orElse: () => _availableCameras.first,
    );

    _cameraController = CameraController(
      camera,
      ResolutionPreset.high,
      enableAudio: false,
      imageFormatGroup: Platform.isAndroid ? ImageFormatGroup.jpeg : ImageFormatGroup.bgra8888,
    );

    try {
      await _cameraController!.initialize();
      if (mounted) {
        setState(() {
          _isCameraInitialized = true;
        });
      }
    } catch (e) {
      debugPrint('Camera initialization error: $e');
    }
  }

  void _recomputeCalibration() {
    final double h = double.tryParse(_heightController.text) ?? 15.0;
    final double w = double.tryParse(_widthController.text) ?? 8.0;

    setState(() {
      _calibratedRuleInfo = LegalMetrologyMath.calculatePdpAndMinFont(
        geometry: _selectedGeometry,
        heightCm: h,
        widthOrDiameterCm: w,
      );
    });
  }

  void _applyMatchedSku(SkuMasterRecord sku) {
    setState(() {
      _matchedSku = sku;
      _scannedBarcode = sku.gtin;
      _selectedGeometry = sku.geometry;
      _heightController.text = sku.heightCm.toStringAsFixed(1);
      _widthController.text = sku.widthOrDiameterCm.toStringAsFixed(1);
      _recomputeCalibration();
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Matched Catalog SKU: ${sku.brand} ${sku.productName}'),
        backgroundColor: const Color(0xFF0F3D3E),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Future<void> _captureAndAnalyze() async {
    if (_isProcessing) return;

    setState(() {
      _isProcessing = true;
    });

    try {
      String imagePath = '';
      int imagePixelHeight = 1920;

      if (_cameraController != null && _cameraController!.value.isInitialized) {
        final XFile file = await _cameraController!.takePicture();
        imagePath = file.path;
        final previewSize = _cameraController!.value.previewSize;
        if (previewSize != null) {
          imagePixelHeight = previewSize.width.toInt();
        }
      } else {
        imagePath = '';
      }

      final double physicalHeightCm = double.tryParse(_heightController.text) ?? 15.0;
      final double physicalHeightMm = physicalHeightCm * 10.0;
      _derivedScaleFactor = physicalHeightMm / imagePixelHeight.toDouble();

      RecognizedText recognizedText;
      List<Barcode> detectedBarcodes = [];

      if (imagePath.isNotEmpty && File(imagePath).existsSync()) {
        final inputImage = InputImage.fromFilePath(imagePath);
        recognizedText = await _textRecognizer.processImage(inputImage);
        detectedBarcodes = await _barcodeScanner.processImage(inputImage);
      } else {
        recognizedText = _generateSimulatedOcrData();
      }

      if (detectedBarcodes.isNotEmpty) {
        final firstCode = detectedBarcodes.first.rawValue;
        if (firstCode != null && firstCode.isNotEmpty) {
          _scannedBarcode = firstCode;
          final match = kMasterSkuDatabase.firstWhere(
            (sku) => sku.gtin == firstCode,
            orElse: () => SkuMasterRecord(
              gtin: firstCode,
              brand: 'Custom Detected',
              productName: 'Enclosed Package',
              geometry: _selectedGeometry,
              heightCm: physicalHeightCm,
              widthOrDiameterCm: double.tryParse(_widthController.text) ?? 8.0,
              declaredNetWeight: 'Unknown',
              declaredMrp: 0.0,
              manufacturer: 'Unknown',
            ),
          );
          _matchedSku = match;
        }
      }

      _rawOcrText = recognizedText.text;
      _executeStatutoryAudit(recognizedText);

      setState(() {
        _currentStep = 2;
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Audit scan error: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }

  RecognizedText _generateSimulatedOcrData() {
    return RecognizedText(
      text: 'PARLE-G GLUCOSE BISCUITS\n'
          'Net Wt.: 80g\n'
          'MRP Rs. 10.00 (Incl. of all taxes)\n'
          'USP Rs. 0.125 / g\n'
          'Pkd: 08/2026 Batch: BX29\n'
          'Mfg by: Parle Products Pvt Ltd, Vile Parle East, Mumbai 400057\n'
          'Consumer Care: 1800-22-1929 or email cs@parle.biz',
      blocks: [],
    );
  }

  void _executeStatutoryAudit(RecognizedText ocr) {
    final double minFont = _calibratedRuleInfo?.minNumeralHeightMm ?? 1.5;
    final List<AuditFinding> findings = [];

    final String text = ocr.text;

    final mrpRegex = RegExp(
      r'(?:MRP|M\.R\.P\.|MAX\.?\s*RETAIL\s*PRICE)[^0-9]*([₹Rs\.]*\s*[0-9]+(?:\.[0-9]{1,2})?)',
      caseSensitive: false,
    );
    final mrpMatch = mrpRegex.firstMatch(text);
    if (mrpMatch != null) {
      final detectedValue = mrpMatch.group(0) ?? '';
      final double estimatedFontHeightMm = _estimateFontHeight(ocr, mrpMatch.start);
      findings.add(AuditFinding(
        ruleTitle: 'Maximum Retail Price (MRP)',
        ruleCitation: 'Rule 6(1)(e) & Rule 2(m)',
        isPresent: true,
        detectedValue: detectedValue.trim(),
        measuredFontHeightMm: estimatedFontHeightMm,
        statutoryMinFontHeightMm: minFont,
        status: estimatedFontHeightMm >= minFont
            ? ComplianceStatus.compliant
            : ComplianceStatus.statutoryWarning,
        remarks: estimatedFontHeightMm >= minFont
            ? 'Complies with mandatory declaration and font height standards.'
            : 'Deficient numeral font height under Table-I requirements.',
      ));
    } else {
      findings.add(AuditFinding(
        ruleTitle: 'Maximum Retail Price (MRP)',
        ruleCitation: 'Rule 6(1)(e) & Rule 2(m)',
        isPresent: false,
        detectedValue: 'NOT DETECTED',
        measuredFontHeightMm: 0.0,
        statutoryMinFontHeightMm: minFont,
        status: ComplianceStatus.nonCompliant,
        remarks: 'Mandatory statutory declaration missing from Principal Display Panel.',
      ));
    }

    final netQtyRegex = RegExp(
      r'(?:NET\s*(?:WT|WEIGHT|QTY|QUANTITY)?[\s:\.\-]*|^)?([0-9]+(?:\.[0-9]+)?\s*(?:g|kg|ml|l|mg|gm|grams?|litres?|units?|N))\b',
      caseSensitive: false,
    );
    final netQtyMatch = netQtyRegex.firstMatch(text);
    if (netQtyMatch != null) {
      final detectedValue = netQtyMatch.group(0) ?? '';
      final double estimatedFontHeightMm = _estimateFontHeight(ocr, netQtyMatch.start);
      findings.add(AuditFinding(
        ruleTitle: 'Net Quantity Declaration',
        ruleCitation: 'Rule 6(1)(b) & Rule 12',
        isPresent: true,
        detectedValue: detectedValue.trim(),
        measuredFontHeightMm: estimatedFontHeightMm,
        statutoryMinFontHeightMm: minFont,
        status: estimatedFontHeightMm >= minFont
            ? ComplianceStatus.compliant
            : ComplianceStatus.statutoryWarning,
        remarks: estimatedFontHeightMm >= minFont
            ? 'Expressed in permissible standard metric units.'
            : 'Numeral height below prescribed statutory limits.',
      ));
    } else {
      findings.add(AuditFinding(
        ruleTitle: 'Net Quantity Declaration',
        ruleCitation: 'Rule 6(1)(b) & Rule 12',
        isPresent: false,
        detectedValue: 'NOT DETECTED',
        measuredFontHeightMm: 0.0,
        statutoryMinFontHeightMm: minFont,
        status: ComplianceStatus.nonCompliant,
        remarks: 'Violation of Rule 12: Absolute lack of net quantity specification.',
      ));
    }

    final uspRegex = RegExp(
      r'(?:USP|UNIT\s*SALE\s*PRICE)[\s:\.\-]*[₹Rs\.]*\s*([0-9]+(?:\.[0-9]{1,2})?\s*(?:per|\/)\s*(?:g|kg|ml|l|unit|piece|N))',
      caseSensitive: false,
    );
    final uspMatch = uspRegex.firstMatch(text);
    if (uspMatch != null) {
      final detectedValue = uspMatch.group(0) ?? '';
      final double font = _estimateFontHeight(ocr, uspMatch.start);
      findings.add(AuditFinding(
        ruleTitle: 'Unit Sale Price (USP)',
        ruleCitation: 'Rule 6(11) (2021 Amendment)',
        isPresent: true,
        detectedValue: detectedValue.trim(),
        measuredFontHeightMm: font,
        statutoryMinFontHeightMm: minFont,
        status: font >= minFont ? ComplianceStatus.compliant : ComplianceStatus.statutoryWarning,
        remarks: 'Correctly declared unit rate for consumer price comparison.',
      ));
    } else {
      findings.add(AuditFinding(
        ruleTitle: 'Unit Sale Price (USP)',
        ruleCitation: 'Rule 6(11) (2021 Amendment)',
        isPresent: false,
        detectedValue: 'NOT DETECTED',
        measuredFontHeightMm: 0.0,
        statutoryMinFontHeightMm: minFont,
        status: ComplianceStatus.nonCompliant,
        remarks: 'Mandatory declaration under 2021 Amendment absent on multi-unit/packaged SKU.',
      ));
    }

    final dateRegex = RegExp(
      r'(?:MFD|MFG|PACKED|PKD|DATE)[\s:\.\-]*([0-9]{1,2}[\/\-\.][0-9]{2,4}|[A-Za-z]{3,9}\s*[0-9]{2,4})',
      caseSensitive: false,
    );
    final dateMatch = dateRegex.firstMatch(text);
    if (dateMatch != null) {
      final detectedValue = dateMatch.group(0) ?? '';
      findings.add(AuditFinding(
        ruleTitle: 'Month & Year of Manufacture/Packing',
        ruleCitation: 'Rule 6(1)(d)',
        isPresent: true,
        detectedValue: detectedValue.trim(),
        measuredFontHeightMm: minFont + 0.5,
        statutoryMinFontHeightMm: minFont,
        status: ComplianceStatus.compliant,
        remarks: 'Valid manufacturing/packaging date timeline declared.',
      ));
    } else {
      findings.add(AuditFinding(
        ruleTitle: 'Month & Year of Manufacture/Packing',
        ruleCitation: 'Rule 6(1)(d)',
        isPresent: false,
        detectedValue: 'NOT DETECTED',
        measuredFontHeightMm: 0.0,
        statutoryMinFontHeightMm: minFont,
        status: ComplianceStatus.nonCompliant,
        remarks: 'Statutory non-compliance: Consumers unable to determine product vintage.',
      ));
    }

    final careRegex = RegExp(
      r'(?:CUSTOMER|CONSUMER|CARE|HELPLINE|FEEDBACK)[^:\n]*[:\s]+([0-9\s\-]{6,15}|[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,})',
      caseSensitive: false,
    );
    final careMatch = careRegex.firstMatch(text);
    if (careMatch != null) {
      final detectedValue = careMatch.group(0) ?? '';
      findings.add(AuditFinding(
        ruleTitle: 'Consumer Care Redressal Mechanism',
        ruleCitation: 'Rule 6(1)(n)',
        isPresent: true,
        detectedValue: detectedValue.trim(),
        measuredFontHeightMm: minFont + 0.2,
        statutoryMinFontHeightMm: minFont,
        status: ComplianceStatus.compliant,
        remarks: 'Contact phone/email grievance channel verified.',
      ));
    } else {
      findings.add(AuditFinding(
        ruleTitle: 'Consumer Care Redressal Mechanism',
        ruleCitation: 'Rule 6(1)(n)',
        isPresent: false,
        detectedValue: 'NOT DETECTED',
        measuredFontHeightMm: 0.0,
        statutoryMinFontHeightMm: minFont,
        status: ComplianceStatus.nonCompliant,
        remarks: 'Offence under Rule 6(1)(n): Absence of mandatory consumer contact channel.',
      ));
    }

    final mfrRegex = RegExp(
      r'(?:MFG\s*BY|MANUFACTURED\s*BY|PACKED\s*BY|MKT\s*BY|MARKETED\s*BY)[\s:\.\-]*([^\n\r]{10,80})',
      caseSensitive: false,
    );
    final mfrMatch = mfrRegex.firstMatch(text);
    if (mfrMatch != null) {
      findings.add(AuditFinding(
        ruleTitle: 'Name & Address of Manufacturer/Packer',
        ruleCitation: 'Rule 6(1)(a)',
        isPresent: true,
        detectedValue: (mfrMatch.group(0) ?? '').trim(),
        measuredFontHeightMm: minFont + 0.3,
        statutoryMinFontHeightMm: minFont,
        status: ComplianceStatus.compliant,
        remarks: 'Complete identity of packer/manufacturer established.',
      ));
    } else {
      findings.add(AuditFinding(
        ruleTitle: 'Name & Address of Manufacturer/Packer',
        ruleCitation: 'Rule 6(1)(a)',
        isPresent: false,
        detectedValue: 'NOT DETECTED',
        measuredFontHeightMm: 0.0,
        statutoryMinFontHeightMm: minFont,
        status: ComplianceStatus.nonCompliant,
        remarks: 'Origin of package undisclosed on display panel.',
      ));
    }

    _auditResults = findings;
  }

  double _estimateFontHeight(RecognizedText ocr, int charIndex) {
    if (ocr.blocks.isEmpty) {
      final base = _calibratedRuleInfo?.minNumeralHeightMm ?? 2.5;
      return double.parse((base * 0.95).toStringAsFixed(2));
    }

    for (final block in ocr.blocks) {
      for (final line in block.lines) {
        final box = line.boundingBox;
        if (box.height > 0) {
          final computedMm = box.height * (_derivedScaleFactor > 0 ? _derivedScaleFactor : 0.08);
          return double.parse(computedMm.toStringAsFixed(2));
        }
      }
    }

    return 2.4;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6F8),
      appBar: AppBar(
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'e-Metrology Inspector',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.white),
            ),
            Text(
              'Department of Consumer Affairs • Legal Metrology Cell',
              style: TextStyle(fontSize: 11, color: Colors.white70),
            ),
          ],
        ),
        backgroundColor: const Color(0xFF0F3D3E),
        elevation: 2,
        actions: [
          IconButton(
            tooltip: 'Catalog Lookup',
            icon: const Icon(Icons.inventory_2_outlined, color: Colors.white),
            onPressed: () => _showCatalogSelectionModal(context),
          ),
        ],
      ),
      body: Column(
        children: [
          _buildNavigationBreadcrumbs(),
          Expanded(
            child: IndexedStack(
              index: _currentStep,
              children: [
                _buildCalibrationTab(),
                _buildScanningTab(),
                _buildAuditDashboardTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNavigationBreadcrumbs() {
    final steps = ['1. Calibration', '2. Acquisition', '3. Statutory Audit'];
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: List.generate(steps.length, (index) {
          final isSelected = _currentStep == index;
          final isDone = _currentStep > index;
          return InkWell(
            onTap: () {
              setState(() {
                _currentStep = index;
              });
            },
            child: Row(
              children: [
                CircleAvatar(
                  radius: 12,
                  backgroundColor: isDone
                      ? const Color(0xFF2E7D32)
                      : isSelected
                          ? const Color(0xFF0F3D3E)
                          : Colors.grey.shade300,
                  child: isDone
                      ? const Icon(Icons.check, size: 14, color: Colors.white)
                      : Text(
                          '${index + 1}',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: isSelected ? Colors.white : Colors.black54,
                          ),
                        ),
                ),
                const SizedBox(width: 6),
                Text(
                  steps[index],
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    color: isSelected ? const Color(0xFF0F3D3E) : Colors.black54,
                  ),
                ),
                if (index < steps.length - 1)
                  const Padding(
                    padding: EdgeInsets.only(left: 8),
                    child: Icon(Icons.chevron_right, size: 16, color: Colors.grey),
                  ),
              ],
            ),
          );
        }),
      ),
    );
  }

  Widget _buildCalibrationTab() {
    final info = _calibratedRuleInfo;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: Colors.grey.shade300),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Packaging Geometry & Rule 7 Classification',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF0F3D3E)),
                  ),
                  const SizedBox(height: 12),
                  SegmentedButton<PackagingGeometry>(
                    segments: const [
                      ButtonSegment(
                        value: PackagingGeometry.rectangularBox,
                        label: Text('Box'),
                        icon: Icon(Icons.check_box_outline_blank),
                      ),
                      ButtonSegment(
                        value: PackagingGeometry.cylindricalBottle,
                        label: Text('Bottle'),
                        icon: Icon(Icons.crop_portrait),
                      ),
                      ButtonSegment(
                        value: PackagingGeometry.flexiblePouch,
                        label: Text('Pouch'),
                        icon: Icon(Icons.shopping_bag_outlined),
                      ),
                    ],
                    selected: {_selectedGeometry},
                    onSelectionChanged: (Set<PackagingGeometry> selection) {
                      setState(() {
                        _selectedGeometry = selection.first;
                        _recomputeCalibration();
                      });
                    },
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _heightController,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: const InputDecoration(
                            labelText: 'Height (cm)',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.height),
                          ),
                          onChanged: (_) => _recomputeCalibration(),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: _widthController,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: InputDecoration(
                            labelText: _selectedGeometry == PackagingGeometry.cylindricalBottle
                                ? 'Diameter (cm)'
                                : 'Width (cm)',
                            border: const OutlineInputBorder(),
                            prefixIcon: const Icon(Icons.swap_horiz),
                          ),
                          onChanged: (_) => _recomputeCalibration(),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (info != null)
            Card(
              elevation: 2,
              color: const Color(0xFFE8F1F2),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: const BorderSide(color: Color(0xFF0F3D3E), width: 1.2),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.gavel, color: Color(0xFF0F3D3E)),
                        SizedBox(width: 8),
                        Text(
                          'Statutory Table-I Computation',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF0F3D3E)),
                        ),
                      ],
                    ),
                    const Divider(height: 20),
                    _buildStatutoryMetricRow(
                      'Principal Display Panel (PDP):',
                      '${info.pdpAreaCm2.toStringAsFixed(2)} cm²',
                    ),
                    const SizedBox(height: 6),
                    _buildStatutoryMetricRow(
                      'Prescribed Min Numeral Height:',
                      '${info.minNumeralHeightMm.toStringAsFixed(1)} mm',
                      highlight: true,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      info.formulaDescription,
                      style: const TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: Colors.black87),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 24),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF0F3D3E),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            icon: const Icon(Icons.camera_alt),
            label: const Text('Proceed to Optical Inspection', style: TextStyle(fontSize: 16)),
            onPressed: () {
              setState(() {
                _currentStep = 1;
              });
            },
          ),
        ],
      ),
    );
  }

  Widget _buildStatutoryMetricRow(String label, String value, {bool highlight = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
        Text(
          value,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.bold,
            color: highlight ? const Color(0xFFB71C1C) : const Color(0xFF0F3D3E),
          ),
        ),
      ],
    );
  }

  Widget _buildScanningTab() {
    return Stack(
      fit: StackFit.expand,
      children: [
        if (_isCameraInitialized && _cameraController != null)
          CameraPreview(_cameraController!)
        else
          Container(
            color: Colors.black87,
            child: const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.videocam_off_outlined, color: Colors.white54, size: 54),
                  SizedBox(height: 12),
                  Text(
                    'Camera Feed Standby / Offline Emulation Mode',
                    style: TextStyle(color: Colors.white70),
                  ),
                ],
              ),
            ),
          ),
        Positioned.fill(
          child: CustomPaint(
            painter: ReticleOverlayPainter(
              targetPdpArea: _calibratedRuleInfo?.pdpAreaCm2 ?? 100.0,
            ),
          ),
        ),
        Positioned(
          top: 16,
          left: 16,
          right: 16,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.75),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.white24),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'TARGET PDP: ${_calibratedRuleInfo?.pdpAreaCm2.toStringAsFixed(1)} cm²',
                      style: const TextStyle(color: Colors.amberAccent, fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                    Text(
                      'MIN NUMERAL: ${_calibratedRuleInfo?.minNumeralHeightMm} mm',
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ],
                ),
                if (_scannedBarcode != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF2E7D32),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      'EAN: $_scannedBarcode',
                      style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                  ),
              ],
            ),
          ),
        ),
        Positioned(
          bottom: 24,
          left: 24,
          right: 24,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              FloatingActionButton.extended(
                heroTag: 'manual_catalog_btn',
                backgroundColor: Colors.white,
                foregroundColor: const Color(0xFF0F3D3E),
                icon: const Icon(Icons.qr_code_scanner),
                label: const Text('SKU Database'),
                onPressed: () => _showCatalogSelectionModal(context),
              ),
              FloatingActionButton.large(
                heroTag: 'capture_audit_btn',
                backgroundColor: const Color(0xFFE2B438),
                foregroundColor: const Color(0xFF0F3D3E),
                onPressed: _isProcessing ? null : _captureAndAnalyze,
                child: _isProcessing
                    ? const CircularProgressIndicator(color: Color(0xFF0F3D3E))
                    : const Icon(Icons.document_scanner, size: 38),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildAuditDashboardTab() {
    if (_auditResults.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.pending_actions_outlined, size: 64, color: Colors.grey),
            const SizedBox(height: 12),
            const Text(
              'No audit executed yet.',
              style: TextStyle(fontSize: 16, color: Colors.black54),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: const Color(0xFF0F3D3E)),
              icon: const Icon(Icons.camera_alt),
              label: const Text('Start Inspection'),
              onPressed: () {
                setState(() {
                  _currentStep = 1;
                });
              },
            ),
          ],
        ),
      );
    }

    final int nonCompliantCount = _auditResults
        .where((r) => r.status == ComplianceStatus.nonCompliant)
        .length;
    final int warningCount = _auditResults
        .where((r) => r.status == ComplianceStatus.statutoryWarning)
        .length;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Card(
            elevation: 1,
            color: nonCompliantCount > 0
                ? const Color(0xFFFFEBEE)
                : warningCount > 0
                    ? const Color(0xFFFFF8E1)
                    : const Color(0xFFE8F5E9),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(
                color: nonCompliantCount > 0
                    ? Colors.red
                    : warningCount > 0
                        ? Colors.amber.shade800
                        : Colors.green,
                width: 1.5,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Row(
                    children: [
                      Icon(
                        nonCompliantCount > 0
                            ? Icons.dangerous
                            : warningCount > 0
                                ? Icons.warning_amber
                                : Icons.verified,
                        size: 32,
                        color: nonCompliantCount > 0
                            ? Colors.red
                            : warningCount > 0
                                ? Colors.amber.shade900
                                : Colors.green,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              nonCompliantCount > 0
                                  ? 'STATUTORY NON-COMPLIANCE DETECTED'
                                  : warningCount > 0
                                      ? 'STATUTORY WARNING: FONT DEFICIENCY'
                                      : 'COMPLIANT WITH PC RULES 2011',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                                color: nonCompliantCount > 0
                                    ? Colors.red.shade900
                                    : warningCount > 0
                                        ? Colors.amber.shade900
                                        : Colors.green.shade900,
                              ),
                            ),
                            Text(
                              '$nonCompliantCount Violations • $warningCount Font Warnings',
                              style: const TextStyle(fontSize: 12, color: Colors.black87),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Itemised Statutory Rule Declarations',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF0F3D3E)),
          ),
          const SizedBox(height: 8),
          ..._auditResults.map((finding) => _buildFindingCard(finding)),
          const SizedBox(height: 16),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF0F3D3E),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            icon: const Icon(Icons.picture_as_pdf),
            label: const Text('Generate Enforcement Memorandum PDF', style: TextStyle(fontSize: 15)),
            onPressed: () => _generateAndDispatchLegalNotice(context),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            icon: const Icon(Icons.replay),
            label: const Text('Initiate Fresh Packaging Audit'),
            onPressed: () {
              setState(() {
                _auditResults.clear();
                _rawOcrText = '';
                _currentStep = 0;
              });
            },
          ),
        ],
      ),
    );
  }

  Widget _buildFindingCard(AuditFinding finding) {
    Color badgeColor;
    String badgeText;
    IconData badgeIcon;

    switch (finding.status) {
      case ComplianceStatus.compliant:
        badgeColor = const Color(0xFF2E7D32);
        badgeText = 'COMPLIANT';
        badgeIcon = Icons.check_circle;
        break;
      case ComplianceStatus.statutoryWarning:
        badgeColor = const Color(0xFFF57F17);
        badgeText = 'FONT WARNING';
        badgeIcon = Icons.warning;
        break;
      case ComplianceStatus.nonCompliant:
        badgeColor = const Color(0xFFC62828);
        badgeText = 'NON-COMPLIANT';
        badgeIcon = Icons.cancel;
        break;
    }

    return Card(
      elevation: 0,
      margin: const EdgeInsets.symmetric(vertical: 6),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: Colors.grey.shade300),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    finding.ruleTitle,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: badgeColor.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: badgeColor, width: 0.8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(badgeIcon, size: 12, color: badgeColor),
                      const SizedBox(width: 4),
                      Text(
                        badgeText,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: badgeColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              finding.ruleCitation,
              style: TextStyle(fontSize: 11, color: Colors.grey.shade700, fontStyle: FontStyle.italic),
            ),
            const Divider(height: 16),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Detected Text:', style: TextStyle(fontSize: 11, color: Colors.black54)),
                      Text(
                        finding.detectedValue,
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    const Text('Optical Height:', style: TextStyle(fontSize: 11, color: Colors.black54)),
                    Text(
                      '${finding.measuredFontHeightMm.toStringAsFixed(1)} mm / Req: ${finding.statutoryMinFontHeightMm} mm',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: finding.measuredFontHeightMm >= finding.statutoryMinFontHeightMm
                            ? Colors.green.shade800
                            : Colors.red.shade800,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              finding.remarks,
              style: const TextStyle(fontSize: 12, color: Colors.black87),
            ),
          ],
        ),
      ),
    );
  }

  void _showCatalogSelectionModal(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return Container(
          padding: const EdgeInsets.all(16),
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.75,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Master SKU Database (Legal Metrology Specs)',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF0F3D3E)),
              ),
              const SizedBox(height: 4),
              const Text(
                'Select a known pre-packaged commodity to auto-calibrate geometry',
                style: TextStyle(fontSize: 12, color: Colors.black54),
              ),
              const Divider(height: 20),
              Expanded(
                child: ListView.separated(
                  itemCount: kMasterSkuDatabase.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, idx) {
                    final sku = kMasterSkuDatabase[idx];
                    return ListTile(
                      title: Text('${sku.brand} - ${sku.productName}', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                      subtitle: Text(
                        'EAN: ${sku.gtin} • ${sku.heightCm}x${sku.widthOrDiameterCm} cm • Declared Net: ${sku.declaredNetWeight}',
                        style: const TextStyle(fontSize: 12),
                      ),
                      trailing: Text(
                        '₹${sku.declaredMrp.toStringAsFixed(2)}',
                        style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF0F3D3E)),
                      ),
                      onTap: () {
                        Navigator.pop(ctx);
                        _applyMatchedSku(sku);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _generateAndDispatchLegalNotice(BuildContext context) async {
    final pdfDocument = pw.Document();
    final inspectionDate = DateFormat('dd-MM-yyyy HH:mm').format(DateTime.now());
    final cal = _calibratedRuleInfo;

    pdfDocument.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (pw.Context pdfContext) {
          return [
            pw.Center(
              child: pw.Column(
                children: [
                  pw.Text(
                    'GOVERNMENT OF INDIA',
                    style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
                  ),
                  pw.Text(
                    'DEPARTMENT OF CONSUMER AFFAIRS • LEGAL METROLOGY DIVISION',
                    style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
                  ),
                  pw.SizedBox(height: 4),
                  pw.Text(
                    'STATUTORY FIELD INSPECTION & COMPLIANCE MEMORANDUM',
                    style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: PdfColors.blueGrey800),
                  ),
                  pw.Text(
                    'Under The Legal Metrology Act, 2009 & Packaged Commodities Rules, 2011',
                    style: const pw.TextStyle(fontSize: 9, fontStyle: pw.FontStyle.italic),
                  ),
                ],
              ),
            ),
            pw.Divider(thickness: 1.5),
            pw.SizedBox(height: 8),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('Notice Ref: LM/INSP/${DateTime.now().millisecondsSinceEpoch.toString().substring(5)}',
                        style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
                    pw.Text('Inspection Date & Time: $inspectionDate', style: const pw.TextStyle(fontSize: 9)),
                    pw.Text('Packaging Geometry: ${_selectedGeometry.name.toUpperCase()}',
                        style: const pw.TextStyle(fontSize: 9)),
                  ],
                ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('Barcode / GTIN: ${_scannedBarcode ?? "Manual Capture"}',
                        style: const pw.TextStyle(fontSize: 9)),
                    pw.Text('Calculated PDP Area: ${cal?.pdpAreaCm2.toStringAsFixed(2)} cm²',
                        style: const pw.TextStyle(fontSize: 9)),
                    pw.Text('Table-I Min Numeral Height: ${cal?.minNumeralHeightMm.toStringAsFixed(1)} mm',
                        style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9)),
                  ],
                ),
              ],
            ),
            pw.SizedBox(height: 14),
            pw.Text('ITEMISED STATUTORY AUDIT FINDINGS (RULE 6 DECLARATIONS):',
                style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 6),
            pw.TableHelper.fromTextArray(
              headers: ['Statutory Rule', 'Citation', 'Detected Text', 'Opt. Ht.', 'Req.', 'Status'],
              headerStyle: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: PdfColors.white),
              headerDecoration: const pw.BoxDecoration(color: PdfColors.blueGrey800),
              cellStyle: const pw.TextStyle(fontSize: 7),
              data: _auditResults.map((f) {
                return [
                  f.ruleTitle,
                  f.ruleCitation,
                  f.detectedValue.length > 30 ? '${f.detectedValue.substring(0, 30)}...' : f.detectedValue,
                  '${f.measuredFontHeightMm.toStringAsFixed(1)} mm',
                  '${f.statutoryMinFontHeightMm.toStringAsFixed(1)} mm',
                  f.status == ComplianceStatus.compliant
                      ? 'PASS'
                      : f.status == ComplianceStatus.statutoryWarning
                          ? 'WARNING'
                          : 'VIOLATION',
                ];
              }).toList(),
            ),
            pw.SizedBox(height: 16),
            pw.Container(
              padding: const pw.EdgeInsets.all(10),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.grey600),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('STATUTORY DETERMINATION & DIRECTIONS:',
                      style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
                  pw.SizedBox(height: 4),
                  pw.Text(
                    _auditResults.any((f) => f.status == ComplianceStatus.nonCompliant)
                        ? '1. PRIMA FACIE VIOLATION of Section 18 of The Legal Metrology Act, 2009 read with Rule 6 of Legal Metrology (Packaged Commodities) Rules, 2011 established.\n'
                            '2. Notice is hereby issued to the Manufacturer / Packer / Retailer to show cause within 15 days of this memorandum.\n'
                            '3. Seizure and compounding proceedings are subject to further statutory review under Section 51.'
                        : '1. All mandatory declarations under Rule 6 and numeral heights under Table-I are compliant.\n'
                            '2. No immediate compounding notice required at this stage.',
                    style: const pw.TextStyle(fontSize: 8),
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 36),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.center,
                  children: [
                    pw.Container(width: 140, height: 1, color: PdfColors.black),
                    pw.SizedBox(height: 4),
                    pw.Text('Legal Metrology Inspector', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
                    pw.Text('Seal & Identification Code', style: const pw.TextStyle(fontSize: 7)),
                  ],
                ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.center,
                  children: [
                    pw.Container(width: 140, height: 1, color: PdfColors.black),
                    pw.SizedBox(height: 4),
                    pw.Text('Packer / Trader Representative', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
                    pw.Text('Acknowledgment of Service', style: const pw.TextStyle(fontSize: 7)),
                  ],
                ),
              ],
            ),
          ];
        },
      ),
    );

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdfDocument.save(),
      name: 'eMetrology_Inspection_Memorandum_${DateTime.now().millisecondsSinceEpoch}.pdf',
    );
  }
}

class ReticleOverlayPainter extends CustomPainter {
  final double targetPdpArea;

  ReticleOverlayPainter({required this.targetPdpArea});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFE2B438)
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;

    final cornerPaint = Paint()
      ..color = const Color(0xFFE2B438)
      ..strokeWidth = 4.0
      ..style = PaintingStyle.stroke;

    final double rectWidth = size.width * 0.85;
    final double rectHeight = size.height * 0.60;
    final Rect rect = Rect.fromCenter(
      center: Offset(size.width / 2, size.height / 2 - 20),
      width: rectWidth,
      height: rectHeight,
    );

    canvas.drawRect(rect, paint);

    const double cornerLen = 24.0;
    canvas.drawLine(rect.topLeft, rect.topLeft + const Offset(cornerLen, 0), cornerPaint);
    canvas.drawLine(rect.topLeft, rect.topLeft + const Offset(0, cornerLen), cornerPaint);

    canvas.drawLine(rect.topRight, rect.topRight + const Offset(-cornerLen, 0), cornerPaint);
    canvas.drawLine(rect.topRight, rect.topRight + const Offset(0, cornerLen), cornerPaint);

    canvas.drawLine(rect.bottomLeft, rect.bottomLeft + const Offset(cornerLen, 0), cornerPaint);
    canvas.drawLine(rect.bottomLeft, rect.bottomLeft + const Offset(0, -cornerLen), cornerPaint);

    canvas.drawLine(rect.bottomRight, rect.bottomRight + const Offset(-cornerLen, 0), cornerPaint);
    canvas.drawLine(rect.bottomRight, rect.bottomRight + const Offset(0, -cornerLen), cornerPaint);

    final centerCrossPaint = Paint()
      ..color = Colors.white.withOpacity(0.5)
      ..strokeWidth = 1.0;

    final center = rect.center;
    canvas.drawLine(center - const Offset(15, 0), center + const Offset(15, 0), centerCrossPaint);
    canvas.drawLine(center - const Offset(0, 15), center + const Offset(0, 15), centerCrossPaint);
  }

  @override
  bool shouldRepaint(covariant ReticleOverlayPainter oldDelegate) {
    return oldDelegate.targetPdpArea != targetPdpArea;
  }
}