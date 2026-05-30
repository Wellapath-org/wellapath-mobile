const Map<String, String> kSymptomDisplayMap = {
  'Headache': 'headache',
  'Fever': 'fever',
  'Chills': 'chills',
  'Body pain': 'body_pain',
  'Weakness': 'weakness',
  'Nausea': 'nausea',
  'Sweating': 'sweating',
  'Cough': 'cough',
  'Fast breathing': 'fast_breathing_child',
  'Watery stool': 'watery_stool',
  'Vomiting': 'vomiting',
  'Abdominal cramps': 'abdominal_cramps',
  'Dizziness': 'dizziness',
  'Fatigue': 'fatigue',
  'Wrist pain': 'pain',
  'Swollen hands': 'swelling',
  'Dark urine': 'dark_urine',
  'Feeling sick or queasy': 'nausea',
  'Muscle pain': 'body_pain',
};

/// Maps each selectable body area to the display names of relevant symptoms.
/// Keys must match the area strings used in body_area_screen.dart and
/// AssessmentController.setBodyArea(). A null or absent key shows all symptoms.
const Map<String, List<String>> kBodyAreaSymptoms = {
  'Head': ['Headache', 'Dizziness', 'Fever'],
  'Neck': ['Headache', 'Fever', 'Weakness'],
  'Chest': ['Cough', 'Fast breathing', 'Fever', 'Weakness'],
  'Abdomen': ['Nausea', 'Vomiting', 'Abdominal cramps', 'Watery stool'],
  'Arms': ['Swollen hands', 'Wrist pain', 'Weakness'],
  'Legs': ['Weakness', 'Fatigue'],
  'Back': ['Weakness', 'Fatigue', 'Body pain'],
  'Pelvis': ['Abdominal cramps', 'Weakness'],
  'Buttocks': ['Weakness', 'Fatigue'],
  'Skin symptoms': ['Sweating', 'Fever', 'Chills'],
};
