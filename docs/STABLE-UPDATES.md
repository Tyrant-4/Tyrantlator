# Tyrantlator stable updates

This updater follows Bannerlator's latest **published stable release**, not commits
on its main branch or prereleases. It integrates into Tyrantlator's **profiling**
branch, which contains the current customizations. It does not install APKs.

## Operation

The scheduled workflow must be published on Tyrantlator's default `main` branch.
It checks daily at 05:23 UTC (08:23 Saudi Arabia time); GitHub may delay scheduled
runs. It also supports Actions > Stable Bannerlator updates > Run workflow on main.

1. Test the trusted merge helper in temporary fixture repositories.
2. Read the official latest release, pin its tag to the fetched commit, and fetch
   the current profiling branch. Skip a stable release already in its ancestry.
3. Make a normal two-parent merge in a disposable CI checkout. Preserve the entire
   custom branch history. Never resolve conflicts with an automatic ours/theirs rule.
4. Stop on conflicts, any file deletion, changes under `.github/` or `keystore/`,
   changes to the updater scripts/guide, Tyrantlator-named branding files, or changes
   to flavor package IDs, names, signing selections or the signing configuration.
   Open one issue per blocked stable version; save a report. Other failures fail
   the Actions run. No branch is advanced on either path.
5. For a clean guarded merge, push a uniquely named candidate branch, explicitly
   call the trusted reusable build with its exact commit, build **only PUBG**, and
   require `NetworkAddressTest` to pass. This build receives no inherited secrets
   and no repository write permission. The optional Galaxy SDK is therefore absent.
6. After a successful build, recheck the candidate's two parents and the current
   profiling base, then advance profiling with an ordinary push. A competing edit
   causes failure instead of overwriting it. No force push or branch protection bypass.

The existing build's Rust host tests remain non-blocking as before. These gates
check a merge/build and the existing network address unit tests, not every custom
feature's behavior. Clean Git merges cannot guarantee semantic preservation.
Install the APK manually and check launchers, container switching, fonts, HUD,
network drives and the games you use before treating it as phone-tested.

## Downloads and recovery

Open the successful Actions run and download its `Bannerlator-stable-...-pubg`
artifact within seven days. Report artifacts last 30 days. Candidate branches are
retained for review; this workflow does not automatically delete them. It does not
publish a GitHub release or change the app's existing update feed.

When blocked, review the issue and saved report. Integrate the stable release on
profiling with the custom settings retained, run the build and phone checks, then
publish that reviewed merge. The next scheduled check recognizes the integrated
release. Changes to protected automation require a separate review of the trusted
files on main. A failed build leaves profiling untouched; inspect the candidate
and build logs, make a reviewed fix, and rerun. Repeated checks can retry a failed
build until the stable release is integrated.

## Activation (not yet performed locally)

Publish these files on BOTH profiling and main:

- `.github/workflows/stable-upstream.yml`
- `scripts/stable_upstream.py`
- `scripts/test_stable_upstream.py`
- `docs/STABLE-UPDATES.md`
- the `_build.yml` additions for `source_ref`, PUBG selection, and network tests.

The prepared main version keeps the legacy all-flavor default for existing
release callers; the updater explicitly requests PUBG only. The profiling version
keeps its existing PUBG default. Both disable persisted checkout credentials in
the build job. Do not copy local Android SDK settings or `app/local.properties`.

Repository Actions must be enabled, and branch rules must permit the normal
GITHUB_TOKEN push to profiling/candidate branches. When Issues are enabled, blocked-update reports also open an issue. If Issues are disabled,
the report remains in the Actions summary and downloadable report artifact. No personal access token, public tunnel or model service
is required. Existing repository protections are not disabled by this workflow.
If organization settings or branch rules deny it, the run fails and needs review.

Activate with a manual workflow run on main first. Verify a blocked/current report
or the PUBG artifact plus profiling advancement. Scheduled execution alone is not
proof of a successful build. The public repo's Actions usage remains subject to
GitHub's policies; APK downloads use your bandwidth.

## Initial source assessment, 2026-10-16

profiling: `a5cdea6b1f0fa682c4c344a52dd3fc7055efbc3b` (already published).
Bannerlator stable 3.1.6: `6bd208417f18754d52cade65535f05bdb2894c13`.
Neither the stable tag nor the existing `merge/bannerlator-3.1.6` branch is an
ancestor of profiling. A working-tree-free merge assessment found conflicts in
`.github/workflows/_build.yml` and `app/build.gradle`. The first run is expected
to stop for review. The older merge branch is reference material, not a replacement
for the 36 newer custom commits on profiling.

Offline verification: `python -m unittest discover -s scripts -p test_stable_upstream.py -v`.
Do not run the preparation CLI in your working checkout; it is CI-only.
