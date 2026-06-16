/// Legal/practical guidance for the land-access category the user is standing
/// in. Pure data + a string classifier — no Flutter — so it is the single
/// source of truth for the access info modal and is unit-testable on its own.
///
/// Covers England/Wales (CRoW model: marked open-access land, otherwise no
/// mapped right) and Scotland (open-access model: right to roam by default,
/// with marked restriction zones — military land, camping byelaw zones). This
/// is plain-language general guidance (not legal advice); the UI shows a
/// disclaimer and points to the relevant access code and local signs.
library;

/// The access regimes the app can distinguish from the region-pack data and the
/// per-nation defaults (see AccessLandService.statusAt).
enum AccessCategory {
  /// CRoW Act 2000 "right to roam" open-access land (England/Wales).
  crowOpenAccess,

  /// The public forest estate managed by Forestry England.
  forestryEngland,

  /// Data is loaded but the point is in no open-access parcel (England/Wales) —
  /// access is limited to public rights of way.
  noMappedRight,

  /// Scotland's default: a right of responsible access ("right to roam") over
  /// most land and water, outside any marked restriction zone.
  scotlandOpenAccess,

  /// Ministry of Defence / military training land — access rights do not apply
  /// and live hazards may be present.
  militaryNoAccess,

  /// A camping management byelaw area (e.g. Loch Lomond & The Trossachs) where
  /// wild camping needs a permit in season.
  campingByelawZone,

  /// No access data for here — treat as private by default.
  unknown,
}

/// Map a raw status string (an AccessParcel.source, a per-nation default
/// sentinel, or null) to a category. Tolerant of label wording changes.
AccessCategory accessCategoryForStatus(String? status) {
  if (status == null || status.trim().isEmpty) return AccessCategory.unknown;
  final s = status.toLowerCase();
  // Scotland's open-access label also contains "open access", so match it (and
  // the marked restriction zones) before the England CRoW branch below.
  if (s.contains('right to roam') ||
      s.contains('scottish outdoor access') ||
      s.contains('scotland')) {
    return AccessCategory.scotlandOpenAccess;
  }
  if (s.contains('military') ||
      s.contains('ministry of defence') ||
      s.contains('danger area')) {
    return AccessCategory.militaryNoAccess;
  }
  if (s.contains('camping') || s.contains('byelaw')) {
    return AccessCategory.campingByelawZone;
  }
  if (s.contains('crow') || s.contains('open access')) {
    return AccessCategory.crowOpenAccess;
  }
  if (s.contains('forestry')) return AccessCategory.forestryEngland;
  if (s.contains('no mapped')) return AccessCategory.noMappedRight;
  return AccessCategory.unknown;
}

/// What the user can do, should take care over, and a closing note for one
/// access category.
class AccessGuidance {
  /// Short heading for the category, e.g. "Open Access land (CRoW)".
  final String title;

  /// One-line plain-language summary of the access right.
  final String summary;

  /// Things you're entitled to do here.
  final List<String> youCan;

  /// Restrictions / things to take care over or not do.
  final List<String> takeCare;

  /// A closing caveat (closures, litter, etc.). May be null.
  final String? note;

  const AccessGuidance({
    required this.title,
    required this.summary,
    required this.youCan,
    required this.takeCare,
    this.note,
  });
}

/// Guidance for [status] (classified via [accessCategoryForStatus]).
AccessGuidance guidanceForStatus(String? status) =>
    guidanceForCategory(accessCategoryForStatus(status));

/// Guidance for a category. Content kept concise and skimmable for field use.
AccessGuidance guidanceForCategory(AccessCategory category) {
  switch (category) {
    case AccessCategory.crowOpenAccess:
      return const AccessGuidance(
        title: 'Open Access land (CRoW)',
        summary: 'A right to roam on foot here for open-air recreation.',
        youCan: [
          'Walk, run, sightsee, birdwatch, climb and picnic — on foot.',
          'Leave the paths and roam freely across the access land.',
        ],
        takeCare: [
          'No cycling, horse-riding, camping, fires or vehicles unless separately signed.',
          'Dogs on a short lead near livestock, and everywhere from 1 Mar–31 Jul (ground-nesting birds).',
          'Excepted land is not included — gardens, cultivated/crop fields, quarries and building sites.',
        ],
        note:
            'Landowners may close access for up to 28 days a year, and for land management or safety — always follow local signs.',
      );
    case AccessCategory.forestryEngland:
      return const AccessGuidance(
        title: 'Forestry England land',
        summary:
            "One of the nation's forests — open for walking and generally free to roam on foot.",
        youCan: [
          'Walk freely on foot, including off the main trails in most open woodland.',
          'Cycle and ride horses on waymarked or permitted trails.',
        ],
        takeCare: [
          'No wild camping, fires or BBQs without permission.',
          'Keep dogs under control; on a lead where signed or near livestock and wildlife.',
          'Active forestry sites (felling) are closed for safety — obey signs and barriers.',
        ],
        note: 'Take litter home and do not damage trees or plants.',
      );
    case AccessCategory.scotlandOpenAccess:
      return const AccessGuidance(
        title: 'Open access — right to roam',
        summary:
            "Scotland's right of responsible access: you can be here on foot, and wild camp in most places, if you act responsibly.",
        youCan: [
          'Walk, cycle, ride, canoe, swim and roam across most land and inland water.',
          'Wild camp in small numbers for a night or two — lightweight and away from buildings and roads.',
        ],
        takeCare: [
          'Keep out of houses and their gardens, farmyards, fenced or cultivated fields with growing crops, and building or construction sites — access rights don’t apply there, even where unmarked.',
          'On military training areas and ranges, look for red flags or red lights: if they’re flying, live firing is on — turn back. Never touch any shell or metal debris on the ground.',
          'Leave no trace: take litter home, bury human waste, and remove any trace of a camp.',
          'Keep dogs under control near livestock and ground-nesting birds (Apr–Jul).',
          'Use a stove rather than an open fire; never light a fire on peat or near woodland in dry conditions.',
        ],
        note:
            'Some areas have local byelaws (e.g. camping management zones) — follow the Scottish Outdoor Access Code and local signs.',
      );
    case AccessCategory.militaryNoAccess:
      return const AccessGuidance(
        title: 'Military land — no public access',
        summary:
            'Ministry of Defence training land. Access rights do not apply and there may be live firing or unexploded hazards.',
        youCan: [
          'Use a public road or right of way that crosses it, where one exists and is open.',
        ],
        takeCare: [
          'Do not enter when red flags or red lamps are showing, or where signs and barriers prohibit access.',
          'Never touch any metal object or debris on the ground — it may be live ordnance.',
          'Obey all MOD byelaw signs; military byelaws override access rights.',
        ],
        note: 'When in doubt, stay out — and report anything suspicious to the authorities.',
      );
    case AccessCategory.campingByelawZone:
      return const AccessGuidance(
        title: 'Camping management zone',
        summary:
            'A camping management byelaw area (e.g. Loch Lomond & The Trossachs). Wild camping here needs a permit in season.',
        youCan: [
          'Walk and roam responsibly here, the same as elsewhere under access rights.',
          'Camp with a permit, or at a designated/booked campsite, during the managed season.',
        ],
        takeCare: [
          'Camping without a permit is an offence in the managed season (typically Mar–Sep) — book ahead, as permits are limited.',
          'Check the national park authority’s permit map before you set out.',
          'Outside the managed season, normal responsible wild camping applies.',
        ],
        note:
            'Byelaws apply only within the marked zones — follow local signs and the park authority’s guidance.',
      );
    case AccessCategory.noMappedRight:
      return const AccessGuidance(
        title: 'No mapped open-access right',
        summary: 'No right to roam here — access is limited to public rights of way.',
        youCan: [
          'Use public footpaths, bridleways and byways shown on the definitive map.',
        ],
        takeCare: [
          'Stay on the right of way; do not enter fields or woodland off it without permission.',
          'A fence, wall or hedge usually marks private land — do not cross unless a right of way goes through.',
          'Anything beyond a right of way needs the landowner’s permission.',
        ],
        note: 'Follow the Countryside Code and respect signs.',
      );
    case AccessCategory.unknown:
      return const AccessGuidance(
        title: 'Access status unknown',
        summary: 'No access data for here — treat the land as private by default.',
        youCan: [
          'Use public rights of way (footpaths, bridleways, byways) where they exist.',
        ],
        takeCare: [
          'Do not assume a right to roam or to leave the path.',
          'Keep out of fenced or enclosed areas without the landowner’s permission.',
        ],
        note:
            'When in doubt, stick to marked paths and follow the Countryside Code.',
      );
  }
}
