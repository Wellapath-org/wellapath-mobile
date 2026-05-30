import 'package:flutter/foundation.dart';
import 'models/assessment_input.dart';

class AssessmentController extends ChangeNotifier {
  String? _sex;
  String? _ageToken;
  final List<String> _demographicTokens = [];
  final List<String> _symptomTokens = [];
  final List<String> _severityTokens = [];
  final List<String> _durationTokens = [];
  String? _selectedBodyArea;

  String? get sex => _sex;
  String? get ageToken => _ageToken;
  List<String> get demographicTokens => List.unmodifiable(_demographicTokens);
  List<String> get symptomTokens => List.unmodifiable(_symptomTokens);
  List<String> get severityTokens => List.unmodifiable(_severityTokens);
  List<String> get durationTokens => List.unmodifiable(_durationTokens);
  String? get selectedBodyArea => _selectedBodyArea;

  bool get shouldShowPregnancyScreen => _sex == 'female';

  static const Map<String, String> _ageTokenMap = {
    '0–12': 'children_under_5',
    '13–17': 'children_school_age',
    '18–40': 'adults',
    '41–60': 'over_40',
    '60+': 'elderly',
  };

  static const Map<String, String> _medicalConditionTokenMap = {
    'Diabetes': 'diabetes_known',
    'Smoking': 'smoker',
    'Hypertension': 'hypertension_known',
    'Allergy history': 'known_allergy',
  };

  void setSex(String sex) {
    _sex = sex;
    if (sex != 'female') {
      _demographicTokens.remove('pregnancy');
    }
    notifyListeners();
  }

  void setAgeRange(String displayLabel) {
    if (_ageToken != null) {
      _demographicTokens.remove(_ageToken);
    }
    _ageToken = _ageTokenMap[displayLabel];
    if (_ageToken != null) {
      _demographicTokens.add(_ageToken!);
    }
    notifyListeners();
  }

  void setMedicalCondition(String condition, bool isYes) {
    final token = _medicalConditionTokenMap[condition];
    if (token == null) return;
    if (isYes) {
      if (!_demographicTokens.contains(token)) {
        _demographicTokens.add(token);
      }
    } else {
      _demographicTokens.remove(token);
    }
    notifyListeners();
  }

  void setPregnancy(bool isPregnant) {
    if (isPregnant) {
      if (!_demographicTokens.contains('pregnancy')) {
        _demographicTokens.add('pregnancy');
      }
    } else {
      _demographicTokens.remove('pregnancy');
    }
    notifyListeners();
  }

  void addSymptomToken(String token) {
    if (!_symptomTokens.contains(token)) {
      _symptomTokens.add(token);
      notifyListeners();
    }
  }

  void removeSymptomToken(String token) {
    if (_symptomTokens.remove(token)) {
      notifyListeners();
    }
  }

  void setSeverityToken(String token) {
    _severityTokens
      ..clear()
      ..add(token);
    notifyListeners();
  }

  void setDurationToken(String token) {
    _durationTokens
      ..clear()
      ..add(token);
    notifyListeners();
  }

  void setBodyArea(String area) {
    _selectedBodyArea = area;
    notifyListeners();
  }

  void clearAll() {
    _sex = null;
    _ageToken = null;
    _demographicTokens.clear();
    _symptomTokens.clear();
    _severityTokens.clear();
    _durationTokens.clear();
    _selectedBodyArea = null;
    notifyListeners();
  }

  AssessmentInput buildInput() {
    return AssessmentInput(
      symptomTokens: List.of(_symptomTokens),
      demographicTokens: List.of(_demographicTokens),
      severityTokens: List.of(_severityTokens),
      durationTokens: List.of(_durationTokens),
    );
  }
}
