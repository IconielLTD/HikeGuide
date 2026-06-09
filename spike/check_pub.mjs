// throwaway: find the newest versions of key packages that are compatible with
// the installed SDK (Flutter 3.24.5 / Dart 3.5.4), so we pin deliberately.
const DART = "3.5.4";
const pkgs = ["flutter_map", "latlong2", "geolocator", "flutter_map_cancellable_tile_provider"];

function satisfiesDart(constraint) {
  // crude check: constraint like ">=3.3.0 <4.0.0" or "^3.4.0"
  if (!constraint) return true;
  const [maj, min, pat] = DART.split(".").map(Number);
  const v = maj * 10000 + min * 100 + pat;
  const ge = constraint.match(/>=\s*([0-9]+)\.([0-9]+)\.([0-9]+)/);
  const lt = constraint.match(/<\s*([0-9]+)\.([0-9]+)\.([0-9]+)/);
  const caret = constraint.match(/\^([0-9]+)\.([0-9]+)\.([0-9]+)/);
  let ok = true;
  if (caret) {
    const lo = (+caret[1]) * 10000 + (+caret[2]) * 100 + (+caret[3]);
    const hi = (+caret[1] + 1) * 10000;
    ok = v >= lo && v < hi;
  } else {
    if (ge) ok = ok && v >= (+ge[1]) * 10000 + (+ge[2]) * 100 + (+ge[3]);
    if (lt) ok = ok && v < (+lt[1]) * 10000 + (+lt[2]) * 100 + (+lt[3]);
  }
  return ok;
}

for (const pkg of pkgs) {
  try {
    const res = await fetch(`https://pub.dev/api/packages/${pkg}`);
    const j = await res.json();
    const versions = j.versions.slice().reverse(); // newest first
    console.log(`\n### ${pkg}  (latest = ${j.latest.version})`);
    let shown = 0;
    for (const v of versions) {
      const sdk = v.pubspec.environment?.sdk;
      const flutter = v.pubspec.environment?.flutter;
      const compat = satisfiesDart(sdk);
      if (shown < 6) {
        console.log(`  ${v.version.padEnd(12)} dart="${sdk ?? "?"}" flutter="${flutter ?? "?"}" ${compat ? "<= dart3.5.4 OK" : "x"}`);
        shown++;
      }
    }
    const firstCompat = versions.find((v) => satisfiesDart(v.pubspec.environment?.sdk));
    console.log(`  -> newest compatible with Dart ${DART}: ${firstCompat ? firstCompat.version : "NONE FOUND"}`);
  } catch (e) {
    console.log(`### ${pkg}: ERROR ${e}`);
  }
}
