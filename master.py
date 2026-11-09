"""
master.py — runs the whole sanctions & violence pipeline, Python and R steps alike.

Usage (from the project folder):
    uv run python master.py                     # data pipeline: cleaning + processing
    uv run python master.py --check             # ... then compare with the frozen baseline (archive/baseline)
    uv run python master.py --set-baseline      # ... then freeze the current outputs as the new baseline
    uv run python master.py --stage cleaning    # one stage only
    uv run python master.py --only clean_gsdb   # one step only
    uv run python master.py --skip-r            # skip R steps (reuse existing data/clean/base/base.csv)
    uv run python master.py --stage empirics    # empirics only: sample, descriptives, reaction functions
    uv run python master.py --only reaction_functions   # e.g. re-run Table 1 only
    uv run python master.py --list              # show the steps without running anything

Each step runs in a fresh process with the project folder as working directory.
Its full output goes to one log per run in data/logs/ (empirics: empirics/results/logs/).
The master stops at the first step that fails.
R steps use `Rscript` (override with the environment variable RSCRIPT=/path/to/Rscript).
"""
import argparse
import os
import platform
import subprocess
import sys
import time
from datetime import datetime
from pathlib import Path

ROOT = Path(__file__).resolve().parent
DATA_LOGS = ROOT / "data" / "logs"
EMP_LOGS = ROOT / "empirics" / "results" / "logs"
RSCRIPT = os.environ.get("RSCRIPT", "Rscript")

# ---------------------------------------------------------------------------
# Pipeline definition: (stage, step name, script path relative to ROOT)
# Order matters: steps run top to bottom.
# ---------------------------------------------------------------------------
STEPS = [
    # collection: raw files were downloaded by hand (see data/raw/README.md)
    ("cleaning",   "clean_base",                 "data/scripts/cleaning/clean_base.R"),
    ("cleaning",   "clean_gsdb",                 "data/scripts/cleaning/clean_gsdb.py"),
    ("cleaning",   "clean_ucdp_ov",              "data/scripts/cleaning/clean_ucdp_ov.py"),
    ("cleaning",   "clean_acled",                "data/scripts/cleaning/clean_acled.py"),
    ("cleaning",   "clean_gdelt",                "data/scripts/cleaning/clean_gdelt.py"),
    ("cleaning",   "clean_population",           "data/scripts/cleaning/clean_population.py"),
    ("cleaning",   "clean_gdp",                  "data/scripts/cleaning/clean_gdp.py"),
    ("processing", "process_sanctions_violence", "data/scripts/processing/process_sanctions_violence.py"),
    # empirics (all scripts source 00_setup.R; estimation scripts also source functions.R)
    ("empirics",   "prepare_sample",             "empirics/scripts/01_prepare_sample.R"),       # variables, sample, exclusion log
    ("empirics",   "descriptives",               "empirics/scripts/02_descriptives.R"),         # figures 1-9, flow summary table
    ("empirics",   "data_diagnostics",           "empirics/scripts/03_data_diagnostics.R"),     # unit roots, persistence, balance, lag criteria
    ("empirics",   "reaction_functions",         "empirics/scripts/04_reaction_functions.R"),   # JP Table 1, Granger tests (OLS + jackknife)
    ("empirics",   "robustness",                 "empirics/scripts/09_robustness.R"),          # robustness: R3 logit / PPML, R10 raw / capped deaths incl. IRF bootstrap (~1 min; needs 04)
    ("empirics",   "pvar_gmm",                   "empirics/scripts/10_pvar_gmm.R"),            # GMM panel VAR, robustness R8 (needs 04)
    # 06 runs after 10 on purpose: its stability table also covers the GMM estimates
    ("empirics",   "model_diagnostics",          "empirics/scripts/06_model_diagnostics.R"),   # residual autocorrelation, CD test, stability
    ("empirics",   "empirical_response",         "empirics/scripts/07_empirical_response.R"),  # JP Fig. 2 response functions
    ("empirics",   "irf",                        "empirics/scripts/08_irf.R"),                 # impulse responses, bootstrap (~10 min)
    ("empirics",   "gdelt",                      "empirics/scripts/11_gdelt.R"),               # GDELT robustness R12: all of the above with GDELT (~17 min; needs 04)
    ("empirics",   "lpdid",                      "empirics/scripts/12_lpdid.R"),               # EXTENSION: LP-DiD event study, UCDP + GDELT (needs 01, 11)
    ("empirics",   "local_projections",          "empirics/scripts/13_local_projections.R"),   # plain panel LP (no DiD), all / US / without ICC case 685 (needs 01)
    ("empirics",   "conflict_sample_lp",         "empirics/scripts/14_conflict_sample_lp.R"),  # arms embargoes / conflict-objective sanctions, sample in conflict in t-1 (needs 01)
    ("empirics",   "specification_grid",         "empirics/scripts/15_specification_grid.R"),   # all combinations in empirics/specifications.R, UCDP/ACLED/GDELT (~min)
    ("empirics",   "specification_curve",        "empirics/scripts/16_specification_curve.R"),  # specification curves from the grid (needs 15)
    ("empirics",   "writing_tables",            "Writing/scripts/make_tables.py"),             # LaTeX tables for Writing/main.tex from the CSV results
]
DATA_STAGES = ["collection", "cleaning", "processing"]
CHECK_SCRIPT = "data/scripts/checks/check_replication.py"


def command_for(script: str) -> list[str]:
    script, *extra = script.split(" --")
    extra = ["--" + e for e in extra]
    path = ROOT / script
    if path.suffix == ".py":
        return [sys.executable, str(path)] + extra
    if path.suffix == ".R":
        return [RSCRIPT, str(path)]
    if path.suffix == ".Rmd":
        out_dir = (ROOT / "empirics" / "results").as_posix()
        expr = (f"rmarkdown::render('{path.as_posix()}', output_format = 'html_document', "
                f"output_dir = '{out_dir}', knit_root_dir = '{ROOT.as_posix()}')")
        return [RSCRIPT, "-e", expr]
    raise ValueError(f"don't know how to run {script}")


def run_step(stage: str, name: str, script: str, stamp: str, master_log) -> bool:
    log_dir = EMP_LOGS if stage == "empirics" else DATA_LOGS
    log_dir.mkdir(parents=True, exist_ok=True)
    log_path = log_dir / f"{name}_{stamp}.log"
    cmd = command_for(script)

    def say(msg):
        print(msg, flush=True)
        master_log.write(msg + "\n")
        master_log.flush()

    say(f"[{datetime.now():%H:%M:%S}] {stage:<10} {name:<28} ... ")
    t0 = time.time()
    with open(log_path, "w", encoding="utf-8") as log:
        log.write(f"step     : {name}\nscript   : {script}\ncommand  : {' '.join(cmd)}\n"
                  f"started  : {datetime.now():%Y-%m-%d %H:%M:%S}\nmachine  : {platform.platform()}\n"
                  f"python   : {sys.version.split()[0]}\n{'-' * 70}\n")
        log.flush()
        try:
            rc = subprocess.run(cmd, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT).returncode
        except FileNotFoundError as e:
            log.write(f"\nCould not start: {e}\n")
            rc = 127
        log.write(f"{'-' * 70}\nfinished : {datetime.now():%Y-%m-%d %H:%M:%S}\n"
                  f"duration : {time.time() - t0:.1f}s\nexit code: {rc}\n")
    status = "OK" if rc == 0 else f"FAILED (exit {rc})"
    say(f"{'':>12}-> {status} in {time.time() - t0:.1f}s, log: {log_path.relative_to(ROOT)}")
    if rc != 0:
        if rc == 127:
            say(f"{'':>12}   could not start {cmd[0]!r} — is it installed and on PATH?")
        else:
            say(f"{'':>12}   last lines of the log:")
            for line in log_path.read_text(encoding="utf-8", errors="replace").splitlines()[-15:]:
                say(f"{'':>15}{line}")
    return rc == 0


# Data versions (added 2026-11-09): data files are not in git (public repo, ACLED terms) but versioned with DVC.
# `master.py --dvc` records the current version of these paths and copies it to the DVC storage folder
# (set per machine in .dvc/config.local). Then commit the changed *.dvc pointer files with git.
DVC_TARGETS = ["data/clean", "data/processed", "empirics/results/data", "data/raw/acled", "data/raw/wdi",
               "data/raw/imf_imts",
               *sorted(str(p.relative_to(ROOT)) for p in (ROOT / "archive" / "baseline").glob("*.csv"))]


def snapshot_data() -> int:
    """dvc add + dvc push for DVC_TARGETS; prints which pointer files changed."""
    targets = [t for t in DVC_TARGETS if (ROOT / t).exists()]
    for cmd in (["dvc", "add", *targets], ["dvc", "push"]):
        print("$", " ".join(cmd[:2]), "...")
        rc = subprocess.call(["uv", "run", *cmd], cwd=ROOT)
        if rc != 0:
            print("DVC step failed (exit code", rc, ")")
            return rc
    changed = subprocess.run(["git", "status", "--porcelain", "--", "*.dvc"], cwd=ROOT,
                             capture_output=True, text=True).stdout.strip()
    print("\nData version stored." + (f" Changed pointer files — commit them with git:\n{changed}" if changed
                                      else " No data changed since the last snapshot."))
    return 0


def main():
    ap = argparse.ArgumentParser(description="Run the sanctions & violence pipeline.")
    ap.add_argument("--stage", choices=DATA_STAGES + ["empirics", "data", "all"], default="data",
                    help="data = collection+cleaning+processing (default); all = data + empirics")
    ap.add_argument("--only", metavar="STEP", help="run a single step by name (see --list)")
    ap.add_argument("--skip-r", action="store_true", help="skip R steps")
    ap.add_argument("--check", action="store_true", help="afterwards, compare outputs with the frozen baseline (archive/baseline)")
    ap.add_argument("--set-baseline", action="store_true", help="afterwards, freeze the current outputs as the new baseline")
    ap.add_argument("--list", action="store_true", help="list the steps and exit")
    ap.add_argument("--dvc", action="store_true",
                    help="only record the current data version with DVC (dvc add + dvc push) and exit")
    args = ap.parse_args()

    if args.dvc:
        return snapshot_data()

    if args.list:
        for stage, name, script in STEPS:
            print(f"{stage:<11}{name:<29}{script}")
        return 0

    if args.only:
        steps = [s for s in STEPS if s[1] == args.only]
        if not steps:
            sys.exit(f"unknown step {args.only!r}; use --list")
    else:
        stages = {"data": DATA_STAGES, "all": DATA_STAGES + ["empirics"]}.get(args.stage, [args.stage])
        steps = [s for s in STEPS if s[0] in stages]
    if args.skip_r:
        steps = [s for s in steps if Path(s[2]).suffix not in (".R", ".Rmd")]

    stamp = datetime.now().strftime("%Y%m%d-%H%M%S")
    DATA_LOGS.mkdir(parents=True, exist_ok=True)
    with open(DATA_LOGS / f"master_{stamp}.log", "w", encoding="utf-8") as master_log:
        master_log.write(f"master run {stamp} | args: {' '.join(sys.argv[1:]) or '(none)'}\n")
        for stage, name, script in steps:
            if not run_step(stage, name, script, stamp, master_log):
                print("\nStopped: fix the failing step and re-run (use --only to resume from a single step).")
                return 1
        if args.set_baseline:
            run_step("check", "set_baseline", CHECK_SCRIPT + " --set-baseline", stamp, master_log)
        if args.check:
            if not run_step("check", "check_replication", CHECK_SCRIPT, stamp, master_log):
                print("\nReplication check reported differences — open the check_replication log.")
                return 1
    if any(stage in DATA_STAGES for stage, _, _ in steps):
        print("\nData outputs may have changed: run `uv run python master.py --dvc` to store this data version.")
    print("\nDone.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
