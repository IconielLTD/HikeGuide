/// Legal/practical guidance for the land-access category the user is standing
/// in. Pure data + a string classifier — no Flutter — so it is the single
/// source of truth for the access info modal and is unit-testable on its own.
///
/// England-specific. This is plain-language general guidance (not legal advice);
/// the UI shows a disclaimer and tells the user to follow local signs and the
/// Countryside Code.
library;

/// The access regimes the app can distinguish from the bundled CRoW / Forestry
/// England data (see AccessLandService.statusAt).
enum AccessCategory {
  /// CRoW Act 2000 "right to roam" open-access land.
  crowOpenAccess,

  /// The public forest estate managed by Forestry England.
  forestryEngland,

  /// Data is loaded but the point is in no open-access parcel — access is
  /// limited to public rights of way.
  noMappedRight,

  /// No access data for here — treat as private by default.
  unknown,
}

/// Map a raw status string (an AccessParcel.source, the "no mapped" sentinel, or
/// null) to a category. Tolerant of label wording changes.
AccessCategory accessCategoryForStatus(String? status) {
  if (status == null || status.trim().isEmpty) return AccessCategory.unknown;
  final s = status.toLowerCase();
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
