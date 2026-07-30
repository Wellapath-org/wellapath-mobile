import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:latlong2/latlong.dart' as latlong;
import 'package:url_launcher/url_launcher.dart';
import '../../core/network/staged_artifact_loader.dart';
import 'facility_card.dart';
import 'facility_locator_service.dart';
import 'nigeria_coverage.dart';

class LocatorScreen extends StatefulWidget {
  final String urgency;

  const LocatorScreen({super.key, required this.urgency});

  @override
  State<LocatorScreen> createState() => _LocatorScreenState();
}

class _LocatorScreenState extends State<LocatorScreen> {
  static const Color _primary = Color(0xFF6B4EFF);
  static const List<String> _states = ['Lagos', 'FCT', 'Kano'];

  static const latlong.LatLng _fallbackCenter = latlong.LatLng(9.0820, 8.6753);

  /// Facility names are drawn on the pins themselves so a caregiver can read
  /// them without tapping. Two limits keep 30 pins legible:
  ///
  ///  * only the nearest [_maxLabelledPins] are labelled — results arrive
  ///    distance-sorted, and the far ones are the ones that overlap. Tuned
  ///    down to 5 after 8 was measured overlapping on-device in dense
  ///    central Lagos, where facilities sit a few hundred metres apart;
  ///  * labels disappear below [_labelZoomThreshold], where pins converge to
  ///    the point that any label overlaps its neighbours.
  ///
  /// A tapped pin is always labelled regardless of either limit.
  static const int _maxLabelledPins = 5;
  static const double _labelZoomThreshold = 12.5;
  static const double _labelMaxWidth = 116;

  final MapController _mapController = MapController();

  FacilityLocatorService? _service;
  List<Map<String, dynamic>> _allFacilities = [];
  List<Map<String, dynamic>> _results = [];
  Map<String, dynamic>? _selectedFacility;

  bool _loading = true;
  bool _locationDenied = false;
  bool _isMapView = true;
  latlong.LatLng? _userLatLng;

  /// Drives label visibility. Updated only when it actually flips, not on
  /// every camera frame — onPositionChanged fires continuously while panning.
  bool _labelsVisible = true;

  /// Set when a successful location fix lands outside Nigeria. Distinct from
  /// [_locationDenied]: we know where the user is, and it is out of coverage.
  bool _outsideCoverage = false;

  // True while facilities are still being fetched in the background (kicked
  // off from loading_screen.dart as part of the staged artifact pipeline —
  // facilities are the largest artifact and are intentionally not waited on
  // before the assessment result screen is shown). The user can reach this
  // screen ("Find Nearby Care") before that background download finishes.
  bool _waitingForFacilities = false;
  bool _facilitiesLoadFailed = false;

  String? _selectedState;
  String? _selectedCityArea;
  List<Map<String, dynamic>> _manualResults = [];
  bool _manualSearched = false;

  @override
  void initState() {
    super.initState();
    _initLocator();
  }

  void _adoptFacilities(List<Map<String, dynamic>> facilities) {
    _allFacilities = facilities;
    _service = FacilityLocatorService(facilities);
  }

  Future<List<Map<String, dynamic>>> _readFacilitiesFromCache() async {
    final box = Hive.isBoxOpen(ArtifactCacheKeys.facilityBox)
        ? Hive.box(ArtifactCacheKeys.facilityBox)
        : await Hive.openBox(ArtifactCacheKeys.facilityBox);
    final raw = box.get(ArtifactCacheKeys.facilityData) as List?;
    return raw?.map((e) => Map<String, dynamic>.from(e as Map)).toList() ??
        <Map<String, dynamic>>[];
  }

  Future<void> _initLocator() async {
    final cached = await _readFacilitiesFromCache();
    if (cached.isNotEmpty) {
      _adoptFacilities(cached);
      await _requestLocation();
      return;
    }

    final loader = StagedArtifactLoader.instance;
    if (loader.facilitiesFailed.value) {
      if (!mounted) return;
      setState(() {
        _facilitiesLoadFailed = true;
        _loading = false;
      });
      return;
    }

    if (!loader.facilitiesReady.value) {
      // Not in cache, not yet flagged ready or failed — the background
      // download kicked off from the assessment loading screen is still in
      // flight. Show a loading state instead of an empty map and wait for
      // it to finish.
      if (!mounted) return;
      setState(() => _waitingForFacilities = true);
      await _awaitBackgroundFacilities(loader);
      if (!mounted) return;
      if (loader.facilitiesFailed.value) {
        setState(() {
          _facilitiesLoadFailed = true;
          _waitingForFacilities = false;
          _loading = false;
        });
        return;
      }
    }

    final facilities = await _readFacilitiesFromCache();
    _adoptFacilities(facilities);
    if (mounted) setState(() => _waitingForFacilities = false);
    await _requestLocation();
  }

  /// Resolves once the background facilities download (kicked off from
  /// loading_screen.dart) reports either success or failure.
  Future<void> _awaitBackgroundFacilities(StagedArtifactLoader loader) async {
    if (loader.facilitiesReady.value || loader.facilitiesFailed.value) return;

    final completer = Completer<void>();
    void listener() {
      if (loader.facilitiesReady.value || loader.facilitiesFailed.value) {
        if (!completer.isCompleted) completer.complete();
      }
    }

    loader.facilitiesReady.addListener(listener);
    loader.facilitiesFailed.addListener(listener);
    await completer.future;
    loader.facilitiesReady.removeListener(listener);
    loader.facilitiesFailed.removeListener(listener);
  }

  Future<void> _requestLocation() async {
    setState(() => _loading = true);

    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (!mounted) return;
      setState(() {
        _locationDenied = true;
        _loading = false;
      });
      return;
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      final shouldRequest = await _showLocationRationale();
      if (!shouldRequest) {
        if (!mounted) return;
        setState(() {
          _locationDenied = true;
          _loading = false;
        });
        return;
      }
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      if (!mounted) return;
      setState(() {
        _locationDenied = true;
        _loading = false;
      });
      return;
    }

    try {
      final position = await Geolocator.getCurrentPosition();

      // Out of coverage: show the region message instead of a map full of
      // facilities the user cannot reach.
      if (!isWithinNigeria(position.latitude, position.longitude)) {
        if (!mounted) return;
        setState(() {
          _outsideCoverage = true;
          _results = const [];
          _locationDenied = false;
          _loading = false;
        });
        return;
      }

      final results = _service!.getNearbyFacilities(
        userLat: position.latitude,
        userLon: position.longitude,
        urgency: widget.urgency,
      );
      if (!mounted) return;
      setState(() {
        _userLatLng = latlong.LatLng(position.latitude, position.longitude);
        _results = results;
        _locationDenied = false;
        _outsideCoverage = false;
        _loading = false;
      });
      // FlutterMap's initialCenter/initialZoom only apply on first mount —
      // the map is already showing (with the fallback center) while
      // location is being resolved, so once the real position lands the
      // camera must be moved explicitly or it silently stays put.
      _mapController.move(_userLatLng!, 15);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _locationDenied = true;
        _loading = false;
      });
    }
  }

  Future<bool> _showLocationRationale() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Allow location access',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        content: const Text(
          'WellaPath uses your location to show nearby health facilities. '
          'Your location never leaves your device.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Maybe later'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: _primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Allow location access'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  List<String> _cityAreasForState(String state) {
    final areas =
        _allFacilities
            .where(
              (facility) =>
                  (facility['state'] as String?)?.toLowerCase() ==
                  state.toLowerCase(),
            )
            .map((facility) => facility['city_area'] as String?)
            .whereType<String>()
            .toSet()
            .toList()
          ..sort();
    return areas;
  }

  void _runManualSearch() {
    if (_selectedState == null || _service == null) return;
    final results = _service!.getFacilitiesByLocation(
      state: _selectedState!,
      cityArea: _selectedCityArea ?? '',
      urgency: widget.urgency,
    );
    setState(() {
      _manualResults = results;
      _manualSearched = true;
    });
  }

  Future<void> _openDirections(Map<String, dynamic> facility) async {
    final lat = (facility['latitude'] as num?)?.toDouble();
    final lon = (facility['longitude'] as num?)?.toDouble();
    if (lat == null || lon == null) return;
    final uri = Uri.parse(
      'https://www.google.com/maps/dir/?api=1&destination=$lat,$lon',
    );
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _callFacility(String phone) async {
    final uri = Uri(scheme: 'tel', path: phone);
    await launchUrl(uri);
  }

  void _selectFacility(Map<String, dynamic> facility) {
    setState(() => _selectedFacility = facility);
  }

  void _dismissSelectedFacility() {
    setState(() => _selectedFacility = null);
  }

  void _recenter() {
    if (_userLatLng == null) return;
    _mapController.move(_userLatLng!, 15);
  }

  int get _shownCount =>
      _locationDenied ? _manualResults.length : _results.length;

  String get _locationLabel {
    if (_locationDenied) {
      if (_manualSearched && _selectedState != null) {
        return _selectedCityArea != null
            ? '$_selectedCityArea, $_selectedState'
            : _selectedState!;
      }
      return 'Select location';
    }
    if (_results.isNotEmpty) {
      final state = _results.first['state'] as String?;
      if (state != null && state.isNotEmpty) return '$state, Nigeria';
    }
    return 'Your location';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            _buildSearchHeader(),
            // Out of coverage there is neither a map nor a list to switch
            // between, so the toggle would be a control that does nothing.
            if (!_locationDenied && !_outsideCoverage) _buildViewToggle(),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 16, 8),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.of(context).pop(),
          ),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: const Color(0xFFF5F5F7),
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: const Color(0xFFE5E7EB)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.search, size: 18, color: Colors.black38),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _locationLabel,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15,
                        color: Colors.black87,
                      ),
                    ),
                  ),
                  IconButton(
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    icon: const Icon(
                      Icons.my_location,
                      size: 18,
                      color: _primary,
                    ),
                    onPressed: _requestLocation,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildViewToggle() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
      child: Row(
        children: [
          // In map view the count is already shown as a floating pill on
          // the map itself (matching the Figma design) — showing it here
          // too would just duplicate it. List view has no map overlay, so
          // it still needs this text.
          if (!_isMapView)
            Text(
              '$_shownCount of 30 shown',
              style: const TextStyle(fontSize: 13, color: Colors.black54),
            ),
          const Spacer(),
          SegmentedButton<bool>(
            style: SegmentedButton.styleFrom(
              visualDensity: VisualDensity.compact,
            ),
            segments: const [
              ButtonSegment(
                value: true,
                label: Text('Map'),
                icon: Icon(Icons.map_outlined, size: 16),
              ),
              ButtonSegment(
                value: false,
                label: Text('List'),
                icon: Icon(Icons.list_alt, size: 16),
              ),
            ],
            selected: {_isMapView},
            onSelectionChanged: (selection) =>
                setState(() => _isMapView = selection.first),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    // Checked first: if the user is out of coverage there is nothing useful
    // to show them, whatever the facilities download is doing.
    if (_outsideCoverage) {
      return _buildOutsideCoverageView();
    }
    if (_waitingForFacilities) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: _primary),
            SizedBox(height: 16),
            Text(
              'Finding nearby facilities... please wait',
              style: TextStyle(fontSize: 14, color: Colors.black54),
            ),
          ],
        ),
      );
    }
    if (_facilitiesLoadFailed) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 32),
          child: Text(
            'We could not load nearby facilities. Please check your '
            'connection and try again later.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: Colors.black54),
          ),
        ),
      );
    }
    if (_locationDenied) {
      return _buildManualFallback();
    }
    return _buildLocationResults();
  }

  Widget _buildOutsideCoverageView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.public_off_rounded,
              size: 56,
              color: _primary.withValues(alpha: 0.7),
            ),
            const SizedBox(height: 20),
            const Text(
              'WellaPath Clinic Locator is not yet available in your '
              'region. We are currently serving Nigeria and will expand '
              'to more countries soon.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                height: 1.5,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).pop(),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  'Back to Results',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLocationResults() {
    if (!_loading && _results.isEmpty) {
      return const Center(child: Text('No nearby facilities found.'));
    }
    return _isMapView ? _buildMapView(_results) : _buildListView(_results);
  }

  Widget _buildMapView(List<Map<String, dynamic>> facilities) {
    final markers = <Marker>[
      for (final facility in facilities)
        if ((facility['latitude'] as num?) != null &&
            (facility['longitude'] as num?) != null)
          _facilityMarker(
            facility,
            showLabel:
                _labelsVisible &&
                facilities.indexOf(facility) < _maxLabelledPins,
          ),
      if (_userLatLng != null)
        Marker(
          point: _userLatLng!,
          width: 20,
          height: 20,
          child: Container(
            decoration: const BoxDecoration(
              color: Colors.blue,
              shape: BoxShape.circle,
              border: Border.fromBorderSide(
                BorderSide(color: Colors.white, width: 2),
              ),
            ),
          ),
        ),
    ];

    return Stack(
      children: [
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: _userLatLng ?? _fallbackCenter,
            initialZoom: 13,
            onTap: (_, _) => _dismissSelectedFacility(),
            onPositionChanged: (camera, _) {
              final zoom = camera.zoom;
              if (zoom == null) return;
              final shouldShow = zoom >= _labelZoomThreshold;
              if (shouldShow != _labelsVisible) {
                setState(() => _labelsVisible = shouldShow);
              }
            },
          ),
          children: [
            TileLayer(
              urlTemplate:
                  'https://basemaps.cartocdn.com/light_all/{z}/{x}/{y}.png',
              userAgentPackageName: 'org.wellapath.wellapathMobile',
            ),
            if (_userLatLng != null)
              CircleLayer(
                circles: [
                  CircleMarker(
                    point: _userLatLng!,
                    radius: 60,
                    useRadiusInMeter: true,
                    color: Colors.blue.withValues(alpha: 0.15),
                    borderColor: Colors.blue.withValues(alpha: 0.3),
                    borderStrokeWidth: 1,
                  ),
                ],
              ),
            MarkerLayer(markers: markers),
          ],
        ),
        if (!_loading)
          Positioned(
            left: 20,
            top: 12,
            child: _pillBadge('$_shownCount of 30 shown'),
          ),
        if (_loading)
          Center(
            child: _pillBadge(
              'Checking nearby care centers',
              icon: const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: _primary,
                ),
              ),
            ),
          ),
        Positioned(
          right: 16,
          bottom: _selectedFacility != null ? 220 : 20,
          child: _buildRecenterButton(),
        ),
        if (_selectedFacility != null)
          Positioned(
            left: 16,
            right: 16,
            bottom: 16,
            child: FacilityCard(
              facility: _selectedFacility!,
              onDirectionsTap: () => _openDirections(_selectedFacility!),
              onCallTap: (_selectedFacility!['phone'] as String?) != null
                  ? () => _callFacility(_selectedFacility!['phone'] as String)
                  : null,
            ),
          ),
      ],
    );
  }

  Marker _facilityMarker(
    Map<String, dynamic> facility, {
    required bool showLabel,
  }) {
    final isSelected =
        _selectedFacility != null &&
        _selectedFacility!['facility_id'] == facility['facility_id'];
    final pinSize = isSelected ? 40.0 : 32.0;
    // A selected pin is always labelled — the user has just asked about it.
    final withLabel = showLabel || isSelected;
    final name = (facility['name'] as String?)?.trim();
    final hasName = name != null && name.isNotEmpty;

    // The marker box must fit the widest of pin and label, and be tall
    // enough for both stacked. flutter_map centres the box on the point, so
    // the extra height is split above and below; the alignment below pins
    // the circle to the coordinate and lets the label hang under it.
    final width = withLabel && hasName ? _labelMaxWidth : pinSize;
    final height = withLabel && hasName ? pinSize + 34 : pinSize;

    return Marker(
      point: latlong.LatLng(
        (facility['latitude'] as num).toDouble(),
        (facility['longitude'] as num).toDouble(),
      ),
      width: width,
      height: height,
      alignment: Alignment.topCenter,
      child: GestureDetector(
        onTap: () => _selectFacility(facility),
        behavior: HitTestBehavior.opaque,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: pinSize,
              height: pinSize,
              decoration: BoxDecoration(
                color: isSelected ? const Color(0xFF4A2FCC) : _primary,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.2),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Center(
                child: Text(
                  'H',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: isSelected ? 16 : 13,
                  ),
                ),
              ),
            ),
            if (withLabel && hasName) ...[
              const SizedBox(height: 3),
              Flexible(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.94),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: const Color(0xFFE0E0E0)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.12),
                        blurRadius: 3,
                        offset: const Offset(0, 1),
                      ),
                    ],
                  ),
                  child: Text(
                    name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 10,
                      height: 1.15,
                      fontWeight: isSelected
                          ? FontWeight.w700
                          : FontWeight.w600,
                      color: const Color(0xFF1A1A2E),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _pillBadge(String text, {Widget? icon}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[icon, const SizedBox(width: 8)],
          Text(
            text,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: _primary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecenterButton() {
    return Material(
      shape: const CircleBorder(),
      color: Colors.white,
      elevation: 3,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: _recenter,
        child: const Padding(
          padding: EdgeInsets.all(12),
          child: Icon(Icons.my_location, color: _primary, size: 20),
        ),
      ),
    );
  }

  Widget _buildListView(List<Map<String, dynamic>> facilities) {
    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      itemCount: facilities.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final facility = facilities[index];
        final phone = facility['phone'] as String?;
        return FacilityCard(
          facility: facility,
          onDirectionsTap: () => _openDirections(facility),
          onCallTap: phone != null ? () => _callFacility(phone) : null,
        );
      },
    );
  }

  Widget _buildManualFallback() {
    final cityAreas = _selectedState != null
        ? _cityAreasForState(_selectedState!)
        : <String>[];

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'We could not access your location. Select your area to find '
            'nearby facilities instead.',
            style: TextStyle(fontSize: 14, color: Colors.black54),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            initialValue: _selectedState,
            decoration: const InputDecoration(
              labelText: 'State',
              border: OutlineInputBorder(),
            ),
            items: [
              for (final state in _states)
                DropdownMenuItem(value: state, child: Text(state)),
            ],
            onChanged: (value) => setState(() {
              _selectedState = value;
              _selectedCityArea = null;
            }),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _selectedCityArea,
            decoration: const InputDecoration(
              labelText: 'City / Area',
              border: OutlineInputBorder(),
            ),
            items: [
              for (final area in cityAreas)
                DropdownMenuItem(value: area, child: Text(area)),
            ],
            onChanged: _selectedState == null
                ? null
                : (value) => setState(() => _selectedCityArea = value),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              onPressed: _selectedState == null ? null : _runManualSearch,
              style: ElevatedButton.styleFrom(
                backgroundColor: _primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: const Text('Search'),
            ),
          ),
          const SizedBox(height: 20),
          if (_manualSearched)
            if (_manualResults.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: Text('No facilities found in this area.')),
              )
            else
              Column(
                children: [
                  for (final facility in _manualResults) ...[
                    FacilityCard(
                      facility: facility,
                      onDirectionsTap: () => _openDirections(facility),
                      onCallTap: (facility['phone'] as String?) != null
                          ? () => _callFacility(facility['phone'] as String)
                          : null,
                    ),
                    const SizedBox(height: 12),
                  ],
                ],
              ),
        ],
      ),
    );
  }
}
