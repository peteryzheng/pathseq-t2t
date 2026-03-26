#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
pst2t_summarize_assembly.py
Per-sample assembly QC summary + per-bin classification summary.

Outputs (to --results-dir):
  1) <sample>.assembly_summary.tsv  — one-row QC summary of the full assembly pipeline
  2) <sample>.bin_summary.tsv       — one row per bin with checkm2/checkv/gtdbtk detail
"""

import argparse
import glob
import os
import re
import sys
from typing import Optional, Dict

import pandas as pd

# ── Utilities ────────────────────────────────────────────────────────────────

def eprint(*args, **kwargs):
    print(*args, file=sys.stderr, **kwargs)


# ── Parsers for individual QC sources ────────────────────────────────────────

def parse_flagstat_primary(path: str) -> Optional[int]:
    """Return total primary reads from a samtools flagstat TSV."""
    try:
        with open(path, encoding="utf-8") as fh:
            for line in fh:
                parts = line.rstrip("\n").split("\t")
                if len(parts) >= 3 and parts[2].strip() == "primary":
                    v1, v2 = parts[0].strip(), parts[1].strip()
                    if v1.isdigit() and v2.isdigit():
                        return int(v1) + int(v2)
    except Exception as ex:
        eprint(f"WARNING: Could not read flagstat: {path} ({ex})")
    return None


def parse_trim_galore_report(path: str) -> Dict[str, object]:
    """Extract key metrics from a single trim_galore trimming report."""
    metrics: Dict[str, object] = {}
    try:
        with open(path, encoding="utf-8") as fh:
            for line in fh:
                line = line.strip()
                m = re.match(r"Total reads processed:\s+([\d,]+)", line)
                if m:
                    metrics["reads_input"] = int(m.group(1).replace(",", ""))
                m = re.match(r"Reads with adapters:\s+([\d,]+)\s+\(([\d.]+)%\)", line)
                if m:
                    metrics["reads_with_adapters"] = int(m.group(1).replace(",", ""))
                    metrics["pct_adapter"] = float(m.group(2))
                m = re.match(r"Reads written \(passing filters\):\s+([\d,]+)", line)
                if m:
                    metrics["reads_written"] = int(m.group(1).replace(",", ""))
    except Exception as ex:
        eprint(f"WARNING: Could not parse trim_galore report: {path} ({ex})")
    return metrics


def parse_megahit_log(path: str) -> Dict[str, object]:
    """Extract final contig stats from MEGAHIT log."""
    metrics: Dict[str, object] = {}
    try:
        with open(path, encoding="utf-8") as fh:
            for line in fh:
                # e.g. "912531 contigs, total 397966731 bp, min 200 bp, max 805381 bp, avg 436 bp, N50 418 bp"
                m = re.search(
                    r"(\d+)\s+contigs,\s+total\s+(\d+)\s+bp,\s+min\s+(\d+)\s+bp,\s+max\s+(\d+)\s+bp,\s+avg\s+(\d+)\s+bp,\s+N50\s+(\d+)\s+bp",
                    line,
                )
                if m:
                    metrics["total_contigs"] = int(m.group(1))
                    metrics["total_length_bp"] = int(m.group(2))
                    metrics["min_contig_bp"] = int(m.group(3))
                    metrics["max_contig_bp"] = int(m.group(4))
                    metrics["avg_contig_bp"] = int(m.group(5))
                    metrics["n50_bp"] = int(m.group(6))
    except Exception as ex:
        eprint(f"WARNING: Could not parse MEGAHIT log: {path} ({ex})")
    return metrics


def read_summary_tsv(path: str) -> Optional[pd.Series]:
    """Read a 2-row (header + values) TSV and return the values as a Series."""
    if not os.path.isfile(path) or os.path.getsize(path) == 0:
        return None
    try:
        df = pd.read_csv(path, sep="\t", nrows=1)
        if df.shape[0] >= 1:
            return df.iloc[0]
    except Exception as ex:
        eprint(f"WARNING: Could not read summary TSV: {path} ({ex})")
    return None


# ── Assembly summary (one row per sample) ────────────────────────────────────

ASSEMBLY_SUMMARY_COLS = [
    "sample_id",
    "PRIMARY_READS",
    # trim_galore
    "READS_BEFORE_TRIMMING",
    "READS_AFTER_TRIMMING",
    "READS_REMOVED_TRIMMING",
    "PCT_ADAPTER_R1",
    "PCT_ADAPTER_R2",
    # megahit
    "TOTAL_CONTIGS",
    "TOTAL_LENGTH_BP",
    "MIN_CONTIG_BP",
    "MAX_CONTIG_BP",
    "AVG_CONTIG_BP",
    "N50_BP",
    # metabat2
    "NUM_BINS",
    "BINNED_CONTIGS",
    "BINNED_LENGTH_BP",
    # checkm2
    "CHECKM2_HQ",
    "CHECKM2_MQ",
    "CHECKM2_LQ",
    "CHECKM2_FQ",
    # checkv
    "CHECKV_HQ",
    "CHECKV_MQ",
    "CHECKV_LQ",
    "CHECKV_ND",
    "CHECKV_PV",
    "CHECKV_FQ",
    # gtdbtk
    "GTDBTK_CLASSIFIED",
    "GTDBTK_UNCLASSIFIED",
]


def build_assembly_summary(
    sample_id: str,
    assembly_dir: str,
    flagstat_path: Optional[str] = None,
    verbose: bool = False,
) -> pd.Series:
    row: Dict[str, object] = {"sample_id": sample_id}

    # ── PRIMARY_READS from flagstat ──
    if flagstat_path and os.path.isfile(flagstat_path):
        v = parse_flagstat_primary(flagstat_path)
        if v is not None:
            row["PRIMARY_READS"] = v

    # ── trim_galore ──
    tgdir = os.path.join(assembly_dir, "trim_galore")
    r1_report = os.path.join(tgdir, f"{sample_id}.R1.fq.gz_trimming_report.txt")
    r2_report = os.path.join(tgdir, f"{sample_id}.R2.fq.gz_trimming_report.txt")

    r1 = parse_trim_galore_report(r1_report) if os.path.isfile(r1_report) else {}
    r2 = parse_trim_galore_report(r2_report) if os.path.isfile(r2_report) else {}

    if r1.get("reads_input") or r2.get("reads_input"):
        row["READS_BEFORE_TRIMMING"] = r1.get("reads_input", 0) + r2.get("reads_input", 0)
        row["READS_AFTER_TRIMMING"] = r1.get("reads_written", 0) + r2.get("reads_written", 0)
        row["READS_REMOVED_TRIMMING"] = row["READS_BEFORE_TRIMMING"] - row["READS_AFTER_TRIMMING"]
    if "pct_adapter" in r1:
        row["PCT_ADAPTER_R1"] = r1["pct_adapter"]
    if "pct_adapter" in r2:
        row["PCT_ADAPTER_R2"] = r2["pct_adapter"]

    # ── MEGAHIT ──
    mh_log = os.path.join(assembly_dir, "megahit", f"{sample_id}.log")
    mh = parse_megahit_log(mh_log) if os.path.isfile(mh_log) else {}
    for key, col in [
        ("total_contigs", "TOTAL_CONTIGS"),
        ("total_length_bp", "TOTAL_LENGTH_BP"),
        ("min_contig_bp", "MIN_CONTIG_BP"),
        ("max_contig_bp", "MAX_CONTIG_BP"),
        ("avg_contig_bp", "AVG_CONTIG_BP"),
        ("n50_bp", "N50_BP"),
    ]:
        if key in mh:
            row[col] = mh[key]

    # ── MetaBAT2 summary ──
    mb = read_summary_tsv(os.path.join(assembly_dir, "metabat2_bins", "metabat2_summary.tsv"))
    if mb is not None:
        row["NUM_BINS"] = int(mb.get("num_bins", 0))
        row["BINNED_CONTIGS"] = int(mb.get("total_contigs", 0))
        row["BINNED_LENGTH_BP"] = int(mb.get("total_length", 0))

    # ── CheckM2 summary ──
    c2 = read_summary_tsv(os.path.join(assembly_dir, "checkm2", "checkm2_summary.tsv"))
    if c2 is not None:
        for src, dst in [("HQ", "CHECKM2_HQ"), ("MQ", "CHECKM2_MQ"), ("LQ", "CHECKM2_LQ"), ("FQ", "CHECKM2_FQ")]:
            row[dst] = int(c2.get(src, 0))

    # ── CheckV summary ──
    cv = read_summary_tsv(os.path.join(assembly_dir, "checkv", "checkv_summary.tsv"))
    if cv is not None:
        for src, dst in [
            ("HQ", "CHECKV_HQ"), ("MQ", "CHECKV_MQ"), ("LQ", "CHECKV_LQ"),
            ("ND", "CHECKV_ND"), ("PV", "CHECKV_PV"), ("FQ", "CHECKV_FQ"),
        ]:
            row[dst] = int(cv.get(src, 0))

    # ── GTDB-Tk summary ──
    gt = read_summary_tsv(os.path.join(assembly_dir, "gtdbtk_output", "gtdbtk_summary.tsv"))
    if gt is not None:
        row["GTDBTK_CLASSIFIED"] = int(gt.get("C", 0))
        row["GTDBTK_UNCLASSIFIED"] = int(gt.get("NC", 0))

    series = pd.Series(row).reindex(ASSEMBLY_SUMMARY_COLS)
    if verbose:
        eprint(f"[summarize-assembly] assembly_summary: {dict(row)}")
    return series


# ── Bin summary (one row per bin) ────────────────────────────────────────────

def assign_checkm2_quality(completeness: float, contamination: float) -> str:
    if contamination > 10:
        return "FQ"
    elif completeness > 90 and contamination < 5:
        return "HQ"
    elif completeness >= 50 and contamination < 10:
        return "MQ"
    else:
        return "LQ"


def build_bin_summary(
    sample_id: str,
    assembly_dir: str,
    verbose: bool = False,
) -> Optional[pd.DataFrame]:
    """Build per-bin detail table joining checkm2, checkv, and gtdbtk."""

    # ── CheckM2 quality_report.tsv (one row per bin) ──
    checkm2_path = os.path.join(assembly_dir, "checkm2", "quality_report.tsv")
    if not os.path.isfile(checkm2_path):
        if verbose:
            eprint(f"[summarize-assembly] No checkm2 quality_report.tsv found")
        return None

    df_c2 = pd.read_csv(checkm2_path, sep="\t")
    if df_c2.empty:
        return None

    bins = df_c2[["Name", "Completeness", "Contamination", "Completeness_Model_Used",
                   "Genome_Size", "Total_Contigs", "Contig_N50", "GC_Content"]].copy()
    bins = bins.rename(columns={
        "Name": "bin_id",
        "Completeness": "completeness",
        "Contamination": "contamination",
        "Completeness_Model_Used": "completeness_model",
        "Genome_Size": "genome_size",
        "Total_Contigs": "num_contigs",
        "Contig_N50": "contig_n50",
        "GC_Content": "gc_content",
    })
    bins["checkm2_quality"] = bins.apply(
        lambda r: assign_checkm2_quality(r["completeness"], r["contamination"]), axis=1
    )

    # ── CheckV quality_summary.tsv (one row per contig, aggregate to bin) ──
    checkv_path = os.path.join(assembly_dir, "checkv", "quality_summary.tsv")
    if os.path.isfile(checkv_path):
        df_cv = pd.read_csv(checkv_path, sep="\t")
        if not df_cv.empty and "contig_id" in df_cv.columns and "checkv_quality" in df_cv.columns:
            # Map contigs to bins by reading bin FASTA files
            bins_dir = os.path.join(assembly_dir, "metabat2_bins")
            contig_to_bin = {}
            for fa_path in glob.glob(os.path.join(bins_dir, "bin*.fa")):
                bin_name = os.path.splitext(os.path.basename(fa_path))[0]
                with open(fa_path, encoding="utf-8") as fh:
                    for line in fh:
                        if line.startswith(">"):
                            contig_id = line[1:].strip().split()[0]
                            contig_to_bin[contig_id] = bin_name

            df_cv["bin_id"] = df_cv["contig_id"].map(contig_to_bin)
            df_cv_binned = df_cv.dropna(subset=["bin_id"])

            if not df_cv_binned.empty:
                # Best quality per bin (priority: Complete > High > Medium > Low > Not-determined)
                quality_order = {"Complete": 4, "High-quality": 3, "Medium-quality": 2, "Low-quality": 1, "Not-determined": 0}
                df_cv_binned = df_cv_binned.copy()
                df_cv_binned["_qord"] = df_cv_binned["checkv_quality"].map(quality_order).fillna(-1)

                cv_agg = df_cv_binned.groupby("bin_id").agg(
                    checkv_viral_contigs=("contig_id", "count"),
                    checkv_best_quality=("_qord", "max"),
                    checkv_provirus_count=("provirus", lambda x: (x == "Yes").sum()),
                ).reset_index()

                inv_order = {v: k for k, v in quality_order.items()}
                cv_agg["checkv_best_quality"] = cv_agg["checkv_best_quality"].map(inv_order)

                bins = bins.merge(cv_agg, on="bin_id", how="left")

    # ── GTDB-Tk bac120 summary (one row per bin) ──
    gtdbtk_path = os.path.join(assembly_dir, "gtdbtk_output", "gtdbtk.bac120.summary.tsv")
    if os.path.isfile(gtdbtk_path):
        df_gt = pd.read_csv(gtdbtk_path, sep="\t")
        if not df_gt.empty and "user_genome" in df_gt.columns:
            gt_cols = ["user_genome", "classification"]
            for c in ["closest_genome_ani", "closest_genome_af", "classification_method"]:
                if c in df_gt.columns:
                    gt_cols.append(c)
            gt_sub = df_gt[gt_cols].rename(columns={"user_genome": "bin_id"})
            bins = bins.merge(gt_sub, on="bin_id", how="left")

    bins.insert(0, "sample_id", sample_id)

    if verbose:
        eprint(f"[summarize-assembly] bin_summary: {len(bins)} bins")

    return bins


# ── Argument parsing ─────────────────────────────────────────────────────────

def parse_args():
    p = argparse.ArgumentParser(
        description="Per-sample assembly QC summary and per-bin classification summary.",
        formatter_class=argparse.ArgumentDefaultsHelpFormatter,
    )
    p.add_argument("--sample-id", required=True, help="Sample ID (UUID)")
    p.add_argument("--outdir", default="./pst2t_out", help="Root pst2t output directory")
    p.add_argument("--assembly-dir", default=None, help="Assembly directory (overrides outdir inference)")
    p.add_argument("--results-dir", default=None, help="Where to write output TSVs")
    p.add_argument("--input-flagstat", default=None, help="Path to flagstat TSV")
    p.add_argument("-v", "--verbose", action="store_true")

    args = p.parse_args()

    sid = args.sample_id
    outdir = args.outdir

    if args.assembly_dir is None:
        args.assembly_dir = os.path.join(outdir, "assembly", sid)
    if args.results_dir is None:
        args.results_dir = os.path.join(outdir, "results")
    if args.input_flagstat is None:
        args.input_flagstat = os.path.join(outdir, "filter_stats", f"{sid}.flagstat.tsv")

    return args


# ── Main ─────────────────────────────────────────────────────────────────────

def main():
    args = parse_args()
    os.makedirs(args.results_dir, exist_ok=True)
    sample = args.sample_id

    # 1) Assembly summary (one row)
    asm_row = build_assembly_summary(
        sample_id=sample,
        assembly_dir=args.assembly_dir,
        flagstat_path=args.input_flagstat,
        verbose=args.verbose,
    )
    out_asm = os.path.join(args.results_dir, f"{sample}.assembly_summary.tsv")
    asm_row.to_frame().T.to_csv(out_asm, sep="\t", index=False)
    if args.verbose:
        eprint(f"[summarize-assembly] wrote {out_asm}")

    # 2) Bin summary (one row per bin)
    bin_df = build_bin_summary(
        sample_id=sample,
        assembly_dir=args.assembly_dir,
        verbose=args.verbose,
    )
    out_bin = os.path.join(args.results_dir, f"{sample}.bin_summary.tsv")
    if bin_df is not None and not bin_df.empty:
        bin_df.to_csv(out_bin, sep="\t", index=False)
    else:
        # Write header-only file so downstream aggregation doesn't break
        pd.DataFrame(columns=["sample_id", "bin_id"]).to_csv(out_bin, sep="\t", index=False)
    if args.verbose:
        eprint(f"[summarize-assembly] wrote {out_bin}")

    eprint(f"[summarize-assembly] done: {sample}")


if __name__ == "__main__":
    try:
        main()
    except SystemExit:
        raise
    except Exception as ex:
        eprint(f"FATAL: {ex}")
        sys.exit(1)
