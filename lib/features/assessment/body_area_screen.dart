import 'package:flutter/material.dart';
import 'assessment_controller.dart';
import 'symptom_selection_screen.dart';

class BodyAreaScreen extends StatelessWidget {
  final AssessmentController assessmentController;
  final VoidCallback onCancel;

  const BodyAreaScreen({
    super.key,
    required this.assessmentController,
    required this.onCancel,
  });

  static const Color _primary = Color(0xFF6B4EFF);

  static const List<String> _bodyAreas = [
    'Skin symptoms',
    'Head',
    'Neck',
    'Chest',
    'Arms',
    'Abdomen',
    'Pelvis',
    'Back',
    'Buttocks',
    'Legs',
  ];

  void _onAreaSelected(BuildContext context, String area) {
    assessmentController.setBodyArea(area);
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SymptomSelectionScreen(
          assessmentController: assessmentController,
          onCancel: onCancel,
        ),
      ),
    );
  }

  void _onNext(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SymptomSelectionScreen(
          assessmentController: assessmentController,
          onCancel: onCancel,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child: Column(
            children: [
              _buildHeader(),
              const TabBar(
                labelColor: _primary,
                unselectedLabelColor: Colors.black54,
                indicatorColor: _primary,
                tabs: [
                  Tab(text: 'Search'),
                  Tab(text: 'Point on the body'),
                ],
              ),
              Expanded(
                child: TabBarView(
                  children: [
                    _SearchTab(
                      areas: _bodyAreas,
                      onAreaSelected: (area) => _onAreaSelected(context, area),
                    ),
                    _BodyDiagramTab(
                      onAreaSelected: (area) => _onAreaSelected(context, area),
                    ),
                  ],
                ),
              ),
              _buildBottomButtons(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 8, 8),
          child: Row(
            children: [
              const Text(
                'Symptom assessment 15%',
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.black54,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.close, size: 22),
                onPressed: onCancel,
              ),
            ],
          ),
        ),
        LinearProgressIndicator(
          value: 0.15,
          backgroundColor: const Color(0xFFEEEEEE),
          color: _primary,
          minHeight: 3,
        ),
      ],
    );
  }

  Widget _buildBottomButtons(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: () => Navigator.of(context).pop(),
              style: OutlinedButton.styleFrom(
                foregroundColor: _primary,
                side: const BorderSide(color: _primary),
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text(
                'Back',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: ElevatedButton(
              onPressed: () => _onNext(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: _primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text(
                'Next',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Private tab widgets ──────────────────────────────────────────────────────

class _SearchTab extends StatefulWidget {
  final List<String> areas;
  final void Function(String area) onAreaSelected;

  const _SearchTab({required this.areas, required this.onAreaSelected});

  @override
  State<_SearchTab> createState() => _SearchTabState();
}

class _SearchTabState extends State<_SearchTab> {
  final TextEditingController _queryController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _queryController.dispose();
    super.dispose();
  }

  List<String> get _filtered {
    if (_query.isEmpty) return widget.areas;
    final q = _query.toLowerCase();
    return widget.areas.where((a) => a.toLowerCase().contains(q)).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
          child: TextField(
            controller: _queryController,
            onChanged: (v) => setState(() => _query = v),
            decoration: InputDecoration(
              hintText: 'Search symptoms eg. headache',
              hintStyle: const TextStyle(color: Colors.black38, fontSize: 14),
              prefixIcon: const Icon(Icons.search, color: Colors.black38),
              filled: true,
              fillColor: const Color(0xFFF5F5F5),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        ),
        Expanded(
          child: ListView.separated(
            itemCount: _filtered.length,
            separatorBuilder: (_, _) => const Divider(height: 1, indent: 20),
            itemBuilder: (context, index) {
              final area = _filtered[index];
              return ListTile(
                title: Text(area, style: const TextStyle(fontSize: 15)),
                trailing: const Icon(
                  Icons.chevron_right,
                  color: Colors.black38,
                ),
                onTap: () => widget.onAreaSelected(area),
                contentPadding: const EdgeInsets.symmetric(horizontal: 20),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _BodyDiagramTab extends StatefulWidget {
  final void Function(String area) onAreaSelected;

  const _BodyDiagramTab({required this.onAreaSelected});

  @override
  State<_BodyDiagramTab> createState() => _BodyDiagramTabState();
}

class _BodyDiagramTabState extends State<_BodyDiagramTab> {
  bool _showFront = true;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const SizedBox(height: 20),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildToggleButton('Front', _showFront, () {
              setState(() => _showFront = true);
            }),
            const SizedBox(width: 12),
            _buildToggleButton('Back', !_showFront, () {
              setState(() => _showFront = false);
            }),
          ],
        ),
        const SizedBox(height: 32),
        Expanded(
          child: Center(
            child: Icon(Icons.person, size: 220, color: Colors.grey[300]),
          ),
        ),
      ],
    );
  }

  Widget _buildToggleButton(String label, bool isActive, VoidCallback onTap) {
    const primary = Color(0xFF6B4EFF);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 10),
        decoration: BoxDecoration(
          color: isActive ? primary : Colors.transparent,
          border: Border.all(color: isActive ? primary : Colors.grey[300]!),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isActive ? Colors.white : Colors.black54,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
