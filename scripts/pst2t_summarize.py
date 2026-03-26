#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
pst2t_summarize.py
Combined summarization + normalization step for PathSeq-T2T.

What this script does (single entry point for the new "summarize" step):
1) Reads PathSeq filtering metrics + T2T flagstats from --filter-stats-dir
2) Reads raw classifier outputs from --classification-stats-dir
   - Kraken2:   <sample>.paired.kraken.report.txt and <sample>.unpaired.kraken.report.txt
   - MetaPhlAn: <sample>.metaphlan.report.txt
   - Sylph:     <sample>.paired.taxonomy.txt and <sample>.unpaired.taxonomy.txt
3) Writes exactly two types of outputs into --results-dir (user-defined):
   a) <sample>.summary.tsv  (ONE wide row merging filtering + classification key totals)
   b) Normalized tables (RPM using PRIMARY_READS):
        - <sample>.kraken.txt       (if Kraken2 present)
        - <sample>.metaphlan.txt    (if MetaPhlAn present)
        - <sample>.sylph.txt        (if Sylph present)

Exit codes:
- 0 on success
- nonzero with a helpful message on error
"""


import argparse
import os
import sys
from typing import Optional, Dict, List

import pandas as pd

# ------------------------ Utilities ------------------------

def eprint(*args, **kwargs):
    print(*args, file=sys.stderr, **kwargs)


# def require_dir(path: str, label: str):
#     if not path or not os.path.isdir(path):
#         eprint(f"ERROR: {label} not found or not a directory: {path}")
#         sys.exit(2)


def require_parent(path: str):
    parent = os.path.dirname(path) or '.'
    os.makedirs(parent, exist_ok=True)


# ------------------------ Filtering summary (from pst2t_summarize_filtering.py) ------------------------

def parse_flagstat_primary(path: str) -> Optional[int]:
    """
    Expect 3-column TSV rows, with a row 'primary' in column 3.
    Example line: 5995946    0    primary
    Returns int(primary) or None if not found.
    """
    try:
        with open(path, 'r', encoding='utf-8') as fh:
            for line in fh:
                parts = line.rstrip('\n').split('\t')
                if len(parts) >= 3 and parts[2].strip() == 'primary':
                    val1 = parts[0].strip()
                    val2 = parts[1].strip()
                    if val1.isdigit() and val2.isdigit():
                        return int(val1) + int(val2)
        return None
    except Exception as ex:
        eprint(f'WARNING: Could not read flagstat file: {path} ({ex})')
        return None


def collect_primary_reads(
    input_flagstat: str,
    t2tfilter_flagstat_paired: str,
    t2tfilter_flagstat_unpaired: str,
) -> pd.Series:

    rs: Dict[str, int] = {}

    mapping = {
        'PRIMARY_READS':                  input_flagstat,
        'T2T_UNALIGNED_PAIRED_READS':     t2tfilter_flagstat_paired,
        'T2T_UNALIGNED_UNPAIRED_READS':   t2tfilter_flagstat_unpaired,
    }
    for key, path in mapping.items():
        if path and os.path.isfile(path):
            v = parse_flagstat_primary(path)
            if v is not None:
                rs[key] = int(v)

    return pd.Series(rs, dtype='Int64')



PATHSEQ_COLS = [
    'PRIMARY_READS',
    'READS_AFTER_PREALIGNED_HOST_FILTER',
    'READS_AFTER_QUALITY_AND_COMPLEXITY_FILTER',
    'READS_AFTER_HOST_FILTER',
    'READS_AFTER_DEDUPLICATION',
    'FINAL_PAIRED_READS',
    'FINAL_UNPAIRED_READS',
    'FINAL_TOTAL_READS',
]


def read_pathseq_metrics_table(path: str) -> Optional[pd.Series]:
    if not os.path.isfile(path):
        return None

    try:
        df = pd.read_table(path, comment='#', sep='\t')
        if df.empty or 'PRIMARY_READS' not in df.columns:
            df = pd.read_table(path, sep='\t', skiprows=6)
        if 'PRIMARY_READS' not in df.columns:
            with open(path, 'r', encoding='utf-8') as fh:
                lines = fh.readlines()
            hdr_idx = None
            for i, ln in enumerate(lines):
                if ln.startswith('PRIMARY_READS'):
                    hdr_idx = i
                    break
            if hdr_idx is None:
                return None
            df = pd.read_table(path, sep='\t', skiprows=hdr_idx)

        if df.shape[0] >= 1:
            s = df.iloc[0]
            s = pd.to_numeric(s, errors='coerce').fillna(0)
            s = s.astype('Int64')
            return s
        return None
    except Exception as ex:
        eprint(f'WARNING: Could not parse PathSeq metrics: {path} ({ex})')
        return None


def collect_pathseq_metrics(qcfilter_metrics_unaligned: str, qcfilter_metrics_decoys: str) -> pd.Series:
    rs: Dict[str, int] = {}

    files = {
        'UNALIGNED': qcfilter_metrics_unaligned,
        'DECOYS':  qcfilter_metrics_decoys,
    }

    per_kind: Dict[str, pd.Series] = {}
    for kind, fpath in files.items():
        s = read_pathseq_metrics_table(fpath) if (fpath and os.path.isfile(fpath)) else None
        if s is None:
            s = pd.Series(dtype='Int64')
        per_kind[kind] = s

    for col in PATHSEQ_COLS:
        rs[f'UNALIGNED_{col}'] = int(per_kind['UNALIGNED'].get(col, 0))
        rs[f'DECOYS_{col}']  = int(per_kind['DECOYS'].get(col, 0))
        rs[f'QCFILTER_{col}']  = rs[f'UNALIGNED_{col}'] + rs[f'DECOYS_{col}']

    return pd.Series(rs, dtype='Int64')



FILTER_SUMMARY_ORDER = (
    ['PRIMARY_READS']
    + [f'{kind}_{col}' for kind in ('QCFILTER', 'UNALIGNED', 'DECOYS') for col in PATHSEQ_COLS]
    + ['T2T_UNALIGNED_PAIRED_READS', 'T2T_UNALIGNED_UNPAIRED_READS']
    + ['FINAL_READ_COUNT','FINAL_READ_COUNT_INCLUDING_MATES']
)


def filtering_summary(
    input_flagstat: str,
    t2tfilter_flagstat_paired: str,
    t2tfilter_flagstat_unpaired: str,
    qcfilter_metrics_unaligned: str,
    qcfilter_metrics_decoys: str,
) -> pd.Series:
    rs_flagstat = collect_primary_reads(
        input_flagstat,
        t2tfilter_flagstat_paired,
        t2tfilter_flagstat_unpaired,
    )

    rs_pathseq = collect_pathseq_metrics(
        qcfilter_metrics_unaligned,
        qcfilter_metrics_decoys
    )

    merged = pd.concat([rs_flagstat, rs_pathseq])

    paired_reads = merged.get('T2T_UNALIGNED_PAIRED_READS', 0)
    unpaired_reads = merged.get('T2T_UNALIGNED_UNPAIRED_READS', 0)
    if pd.isna(paired_reads):
        paired_reads = 0
    if pd.isna(unpaired_reads):
        unpaired_reads = 0

    merged['FINAL_READ_COUNT'] = paired_reads + unpaired_reads
    merged['FINAL_READ_COUNT_INCLUDING_MATES'] = paired_reads + 2 * unpaired_reads

    row = merged.reindex(FILTER_SUMMARY_ORDER).fillna(0).astype(int)

    return row


# ------------------------ Kraken2 I/O + merge ------------------------

KRAKEN2_COLS = [
    'pct_reads',
    'reads_clade',
    'reads_taxon',
    'minimizers_count',
    'minimizers_distinct',
    'rank',
    'tax_id',
    'name',
]

# MICROBIAL_TAX_IDS = [2, 4751, 2157, 10239]  # Bacteria, Fungi, Archaea, Viruses

def load_kraken_report(path: str) -> pd.DataFrame:
    if os.path.getsize(path) == 0:
        df = pd.DataFrame(columns=KRAKEN2_COLS)
        for c in ('reads_clade','reads_taxon','pct_reads'):
            df[c] = df[c].astype('float64').fillna(0)
        df['tax_id'] = df.index.astype('Int64')
        return df

    df = pd.read_table(path, header=None, dtype=str)
    if df.shape[1] < 8:
        raise ValueError(f'Malformed Kraken2 report: {path}')
    df = df.iloc[:, :8].copy()
    df.columns = KRAKEN2_COLS
    df['name'] = df['name'].str.strip()
    for c in ['pct_reads','reads_clade','reads_taxon','minimizers_count','minimizers_distinct','tax_id']:
        df[c] = pd.to_numeric(df[c], errors='coerce').fillna(0)
    return df


def merge_kraken_reports(paired_path: str, unpaired_path: str) -> pd.DataFrame:
    present = [os.path.isfile(paired_path), os.path.isfile(unpaired_path)]
    if not any(present):
        raise FileNotFoundError('No Kraken2 reports found.')
    dfs = []
    if present[0]:
        dfp = load_kraken_report(paired_path).copy()
        dfp['reads_clade'] = 2 * dfp['reads_clade']
        dfp['reads_taxon'] = 2 * dfp['reads_taxon']
        dfs.append(dfp)
    if present[1]:
        dfu = load_kraken_report(unpaired_path).copy()
        dfu['reads_clade'] = 2 * dfu['reads_clade']
        dfu['reads_taxon'] = 2 * dfu['reads_taxon']
        dfs.append(dfu)

    df = (
        pd.concat(dfs, ignore_index=True)
        .groupby(['name','tax_id','rank'], as_index=False)[['reads_clade','reads_taxon','minimizers_count','minimizers_distinct']]
        .sum()
    )
    total_reads = df.loc[df['tax_id'].isin([0,1]), 'reads_clade'].sum()
    df['pct_reads'] = (100.0 * df['reads_clade'] / total_reads).round(4) if total_reads > 0 else 0.0
    df = df[['pct_reads','reads_clade','reads_taxon','rank','tax_id','name']]
    return df


# ------------------------ MetaPhlAn I/O ------------------------

MPA_COLUMNS = [
    'clade_name',
    'clade_taxid',
    'relative_abundance',
    'coverage',
    'estimated_number_of_reads_from_the_clade',
]

def load_metaphlan_table(path: str) -> pd.DataFrame:
    df = pd.read_table(path, comment='#', header=None)
    if df.shape[1] < 5:
        raise RuntimeError(f'Unexpected MetaPhlAn format: {path}')
    df.columns = MPA_COLUMNS
    df['clade_name'] = df['clade_name'].astype(str)
    df['clade_taxid'] = pd.to_numeric(df['clade_taxid'], errors='coerce').fillna(-1).astype(int)
    df['relative_abundance'] = pd.to_numeric(df['relative_abundance'], errors='coerce').fillna(0.0)
    df['coverage'] = pd.to_numeric(df['coverage'], errors='coerce').fillna(0.0)
    df['estimated_number_of_reads_from_the_clade'] = pd.to_numeric(
        df['estimated_number_of_reads_from_the_clade'], errors='coerce'
    ).fillna(0.0)
    return df


# ------------------------ Sylph I/O ------------------------

def load_df_syl(path: str) -> pd.DataFrame:
    """
    Expect Sylph taxonomy columns like:
      clade_name | relative_abundance | sequence_abundance | [optional]
    We only use clade_name and sequence_abundance.
    """
    if not path or not os.path.isfile(path) or os.path.getsize(path) == 0:
        return pd.DataFrame(columns=['clade_name', 'sequence_abundance'])

    df = pd.read_table(path, sep='\t', comment='#')
    if 'clade_name' not in df.columns or 'sequence_abundance' not in df.columns:
        raise RuntimeError(
            f"Sylph taxonomy must contain 'clade_name' and 'sequence_abundance' (got {list(df.columns)}) in {path}"
        )
    out = df[['clade_name', 'sequence_abundance']].copy()
    out['clade_name'] = out['clade_name'].astype(str)
    out['sequence_abundance'] = pd.to_numeric(out['sequence_abundance'], errors='coerce').fillna(0.0)
    return out

# ------------------------ Classification summary + normalized tables ------------------------

def summarize_classification(
    kraken_report_paired: str,
    kraken_report_unpaired: str,
    metaphlan_report: str,
    sylph_report_paired: str,
    sylph_report_unpaired: str,
) -> pd.Series:
    summary: Dict[str, int] = {}

    # Kraken2 totals
    try:
        if (kraken_report_paired and os.path.isfile(kraken_report_paired)) or \
           (kraken_report_unpaired and os.path.isfile(kraken_report_unpaired)):
            df_k = merge_kraken_reports(kraken_report_paired or "", kraken_report_unpaired or "")

            summary.update(dict(
                UNCLASSIFIED_READS_K2 = int(df_k.loc[df_k['tax_id'] == 0, 'reads_clade'].sum()),
                CLASSIFIED_READS_K2 = int(df_k.loc[df_k['tax_id'] == 1, 'reads_clade'].sum()),
                HUMAN_READS_K2        = int(df_k.loc[df_k['tax_id'] == 9606, 'reads_clade'].sum()),
                MICROBIAL_READS_K2    = int(df_k.loc[df_k['tax_id'].isin([2,4751,2157,10239]), 'reads_clade'].sum()),
                BACTERIAL_READS_K2    = int(df_k.loc[df_k['tax_id']==2, 'reads_clade'].sum()),
                ARCHAEA_READS_K2    = int(df_k.loc[df_k['tax_id']==2157, 'reads_clade'].sum()),
                EUKARYOTA_READS_K2    = int(df_k.loc[df_k['tax_id']==2759, 'reads_clade'].sum()),
                VIRUS_READS_K2    = int(df_k.loc[df_k['tax_id']==10239, 'reads_clade'].sum()),
                FUNGI_READS_K2    = int(df_k.loc[df_k['tax_id']==4751, 'reads_clade'].sum()),
            ))
    except FileNotFoundError:
        pass

    # MetaPhlAn totals
    mpa_path = metaphlan_report
    if mpa_path and os.path.isfile(mpa_path) and os.path.getsize(mpa_path) != 0:
        classified_reads = pd.NA
        with open(mpa_path, 'r', encoding='utf-8') as fh:
            for line in fh:
                if not line.startswith('#'):
                    break
                if 'reads processed' in line:
                    parts = line.strip('# \n').split()
                    for i,p in enumerate(parts):
                        if p.isdigit() and i+2 < len(parts) and parts[i+1] == 'reads' and parts[i+2].startswith('processed'):
                            total_reads = int(p); break
                if line.startswith('#estimated_reads_mapped_to_known_clades:'):
                    try:
                        classified_reads = int(line.split(':')[1])
                    except Exception:
                        pass

        df_mpa = load_metaphlan_table(mpa_path)

        bacteria_reads  = df_mpa.loc[df_mpa['clade_name']=='k__Bacteria', 'estimated_number_of_reads_from_the_clade'].sum()
        archaea_reads   = df_mpa.loc[df_mpa['clade_name']=='k__Archaea',  'estimated_number_of_reads_from_the_clade'].sum()
        eukaryota_reads  = df_mpa.loc[df_mpa['clade_name']=='k__Eukaryota','estimated_number_of_reads_from_the_clade'].sum()

        summary.update(dict(
            CLASSIFIED_READS_MPA          = classified_reads,
            MICROBIAL_READS_MPA         = int(bacteria_reads + archaea_reads + eukaryota_reads),
            BACTERIA_READS_MPA       = int(bacteria_reads),
            ARCHAEA_READS_MPA        = int(archaea_reads),
            EUKARYOTA_READS_MPA      = int(eukaryota_reads),
        ))

    # Sylph
    have_sylph = (sylph_report_paired and os.path.isfile(sylph_report_paired)) or \
                 (sylph_report_unpaired and os.path.isfile(sylph_report_unpaired))
    if have_sylph:
        df_p = load_df_syl(sylph_report_paired)   if (sylph_report_paired and os.path.isfile(sylph_report_paired)) else pd.DataFrame(columns=['clade_name','sequence_abundance'])
        df_u = load_df_syl(sylph_report_unpaired) if (sylph_report_unpaired and os.path.isfile(sylph_report_unpaired)) else pd.DataFrame(columns=['clade_name','sequence_abundance'])

        df_syl = pd.merge(
            df_p.rename(columns={'sequence_abundance':'seq_p'}),
            df_u.rename(columns={'sequence_abundance':'seq_u'}),
            on='clade_name', how='outer'
        )
        df_syl['seq_p'] = pd.to_numeric(df_syl.get('seq_p', 0.0), errors='coerce').fillna(0.0)
        df_syl['seq_u'] = pd.to_numeric(df_syl.get('seq_u', 0.0), errors='coerce').fillna(0.0)
        df_syl['sequence_abundance'] = 1.0*df_syl['seq_p'] + 2.0*df_syl['seq_u']

        bacteria_reads  = df_syl.loc[df_syl['clade_name']=='d__Bacteria', 'sequence_abundance'].sum()
        archaea_reads   = df_syl.loc[df_syl['clade_name']=='d__Archaea',  'sequence_abundance'].sum()
        eukaryota_reads  = df_syl.loc[df_syl['clade_name']=='k__Eukaryota','sequence_abundance'].sum()

        summary.update(dict(
            CLASSIFIED_READS_SYLPH           = int(bacteria_reads + archaea_reads + eukaryota_reads),
            MICROBIAL_READS_SYLPH           = int(bacteria_reads + archaea_reads + eukaryota_reads),
            BACTERIA_READS_SYLPH    = int(bacteria_reads),
            ARCHAEA_READS_SYLPH     = int(archaea_reads),
            EUKARYOTA_READS_SYLPH    = int(eukaryota_reads)
        ))

    if not summary:
        eprint('WARNING: No classifier outputs found. Summary will only include filtering metrics.')

    return pd.Series(summary, dtype='Int64')




def write_normalized_tables(
    outdir: str,
    sample: str,
    kraken_report_paired: str,
    kraken_report_unpaired: str,
    metaphlan_report: str,
    sylph_report_paired: str,
    sylph_report_unpaired: str,
    primary_reads: int,
    verbose: bool = False
):
    if primary_reads <= 0:
        eprint('WARNING: PRIMARY_READS <= 0; skipping normalization outputs.')
        return

    os.makedirs(outdir, exist_ok=True)

    # ---- Kraken ----
    if (kraken_report_paired and os.path.isfile(kraken_report_paired)) or \
       (kraken_report_unpaired and os.path.isfile(kraken_report_unpaired)):
        try:
            dfk = merge_kraken_reports(kraken_report_paired or "", kraken_report_unpaired or "")
            df_rpm = dfk.copy()
            df_rpm['reads_clade_per_million'] = 1e6 * df_rpm['reads_clade'] / primary_reads
            df_rpm['reads_taxon_per_million'] = 1e6 * df_rpm['reads_taxon'] / primary_reads
            df_rpm = df_rpm[['name','tax_id','rank','reads_clade','reads_taxon',
                             'reads_clade_per_million','reads_taxon_per_million','pct_reads']]
            out_k2 = os.path.join(outdir, f'{sample}.kraken.txt')
            df_rpm.to_csv(out_k2, sep='\t', index=False)
            if verbose: eprint(f'[summarize] wrote {out_k2}')
        except Exception as ex:
            eprint(f'WARNING: Kraken2 normalization failed: {ex}')

    # ---- MetaPhlAn ----
    if metaphlan_report and os.path.isfile(metaphlan_report):
        try:
            dfm = load_metaphlan_table(metaphlan_report)
            dfm_out = dfm.copy()
            dfm_out['estimated_number_of_reads_from_the_clade_per_million'] = (
                1e6 * dfm_out['estimated_number_of_reads_from_the_clade'] / primary_reads
            )
            dfm_out = dfm_out[['clade_name','clade_taxid',
                               'estimated_number_of_reads_from_the_clade',
                               'estimated_number_of_reads_from_the_clade_per_million',
                               'relative_abundance','coverage']]
            out_mpa = os.path.join(outdir, f'{sample}.metaphlan.txt')
            dfm_out.to_csv(out_mpa, sep='\t', index=False)
            if verbose: eprint(f'[summarize] wrote {out_mpa}')
        except Exception as ex:
            eprint(f'WARNING: MetaPhlAn normalization failed: {ex}')

    # ---- Sylph ----
    have_sylph = (sylph_report_paired and os.path.isfile(sylph_report_paired)) or \
                 (sylph_report_unpaired and os.path.isfile(sylph_report_unpaired))
    if have_sylph:
        try:
            df_p = load_df_syl(sylph_report_paired)   if (sylph_report_paired and os.path.isfile(sylph_report_paired)) else pd.DataFrame(columns=['clade_name','sequence_abundance'])
            df_u = load_df_syl(sylph_report_unpaired) if (sylph_report_unpaired and os.path.isfile(sylph_report_unpaired)) else pd.DataFrame(columns=['clade_name','sequence_abundance'])

            merged = pd.merge(
                df_p.rename(columns={'sequence_abundance':'seq_p'}),
                df_u.rename(columns={'sequence_abundance':'seq_u'}),
                on='clade_name', how='outer'
            )
            merged['seq_p'] = pd.to_numeric(merged.get('seq_p', 0.0), errors='coerce').fillna(0.0)
            merged['seq_u'] = pd.to_numeric(merged.get('seq_u', 0.0), errors='coerce').fillna(0.0)

            # Weighted combination: 1×paired + 2×unpaired
            merged['sequence_abundance'] = 1.0*merged['seq_p'] + 2.0*merged['seq_u']
            merged['sequence_abundance_per_million'] = 1e6 * merged['sequence_abundance'] / float(primary_reads)

            total_seq = float(merged['sequence_abundance'].sum())
            merged['relative_abundance'] = (100.0 * merged['sequence_abundance'] / total_seq) if total_seq > 0 else 0.0

            out_cols = ['clade_name', 'sequence_abundance', 'sequence_abundance_per_million', 'relative_abundance']
            out_df = merged[out_cols].sort_values('sequence_abundance', ascending=False, kind='mergesort')

            out_path = os.path.join(outdir, f'{sample}.sylph.txt')
            out_df.to_csv(out_path, sep='\t', index=False)
            if verbose: eprint(f'[summarize] wrote {out_path}')
        except Exception as ex:
            eprint(f'WARNING: Sylph normalization failed: {ex}')



# ------------------------ Argument parsing ------------------------

def parse_args():
    p = argparse.ArgumentParser(
        description="Combine filtering + classification summaries and write normalized classifier tables (RPM).",
        formatter_class=argparse.ArgumentDefaultsHelpFormatter,
    )

    # Core
    p.add_argument("--sample-id", required=True, help="Sample ID used to build default filenames.")
    p.add_argument("--outdir", default="./pst2t_out", help="Root directory for inferring default input/output paths.")
    p.add_argument("--results-dir", dest="results_dir", default=None, help="Directory to write final outputs.")
    p.add_argument("-v", "--verbose", action="store_true", help="Verbose logging to stderr")

    # Explicit file inputs (optional overrides). If omitted, defaults come from --outdir + --sample-id. 
    # Filtering / flagstat / QC metrics
    p.add_argument("--input-flagstat", default=None, help="<ID>.flagstat.tsv")
    p.add_argument("--qcfilter-metrics-unaligned", default=None, help="<ID>.unaligned.filter_metrics.txt")
    p.add_argument("--qcfilter-metrics-decoys", default=None, help="<ID>.decoys.filter_metrics.txt")
    p.add_argument("--t2tfilter-flagstat-paired", default=None, help="<ID>.qcfilt_paired.t2t_unaln.flagstat.tsv")
    p.add_argument("--t2tfilter-flagstat-unpaired", default=None, help="<ID>.qcfilt_unpaired.t2t_unaln.flagstat.tsv")

    # Classification reports
    p.add_argument("--kraken-report-paired", default=None, help="<ID>.paired.kraken.report.txt")
    p.add_argument("--kraken-report-unpaired", default=None, help="<ID>.unpaired.kraken.report.txt")
    p.add_argument("--metaphlan-report", default=None, help="<ID>.metaphlan.report.txt")
    p.add_argument("--sylph-report-paired", default=None, help="<ID>.paired.sylph.report.txt")
    p.add_argument("--sylph-report-unpaired", default=None, help="<ID>.unpaired.sylph.report.txt")

    args = p.parse_args()

    # ----- Defaults from --outdir if any file arg is missing -----
    sid = args.sample_id
    outdir = args.outdir

    filt_dir = os.path.join(outdir, "filter_stats")
    cls_dir  = os.path.join(outdir, "classification_stats")
    if args.results_dir is None:
        args.results_dir = os.path.join(outdir, "results")

    def _dset(attr, default_path):
        if getattr(args, attr) in (None, ""):
            setattr(args, attr, default_path)

    # Filtering defaults
    _dset("input_flagstat",           os.path.join(filt_dir, f"{sid}.flagstat.tsv"))
    _dset("qcfilter_metrics_unaligned",  os.path.join(filt_dir, f"{sid}.prefilter.unaligned.filter_metrics.txt"))
    _dset("qcfilter_metrics_decoys",     os.path.join(filt_dir, f"{sid}.prefilter.decoys.filter_metrics.txt"))
    _dset("t2tfilter_flagstat_paired",        os.path.join(filt_dir, f"{sid}.qcfilt_paired.t2t_unaln.flagstat.tsv"))
    _dset("t2tfilter_flagstat_unpaired",      os.path.join(filt_dir, f"{sid}.qcfilt_unpaired.t2t_unaln.flagstat.tsv"))

    # Classification defaults
    _dset("kraken_report_paired",         os.path.join(cls_dir,  f"{sid}.paired.kraken.report.txt"))
    _dset("kraken_report_unpaired",       os.path.join(cls_dir,  f"{sid}.unpaired.kraken.report.txt"))
    _dset("metaphlan_report",             os.path.join(cls_dir,  f"{sid}.metaphlan.report.txt"))

    # Sylph defaults
    _dset("sylph_report_paired",        os.path.join(cls_dir,  f"{sid}.paired.sylph.report.txt"))
    _dset("sylph_report_unpaired",      os.path.join(cls_dir,  f"{sid}.unpaired.sylph.report.txt"))

    return args



# ------------------------ Main ------------------------

def main():
    args = parse_args()
    os.makedirs(args.results_dir, exist_ok=True)
    sample = args.sample_id

    # Filtering summary
    filt_row = filtering_summary(
        args.input_flagstat,
        args.t2tfilter_flagstat_paired,
        args.t2tfilter_flagstat_unpaired,
        args.qcfilter_metrics_unaligned,
        args.qcfilter_metrics_decoys,
    )
    primary_reads = int(filt_row.get('PRIMARY_READS', 0))

    # Classification summary (Kraken2, MetaPhlAn, Sylph)
    class_row = summarize_classification(
        args.kraken_report_paired,
        args.kraken_report_unpaired,
        args.metaphlan_report,
        args.sylph_report_paired,
        args.sylph_report_unpaired,
    )

    # Merge → one wide row
    combined = pd.concat([filt_row, class_row]) #.astype(int)
    combined.name = sample

    
    for rate, num, denom in [
        ('CLASSIFICATION_RATE_K2',   'CLASSIFIED_READS_K2',   'FINAL_READ_COUNT_INCLUDING_MATES'),
        ('CLASSIFICATION_RATE_MPA',  'CLASSIFIED_READS_MPA',  'FINAL_READ_COUNT'),
        ('CLASSIFICATION_RATE_SYLPH','CLASSIFIED_READS_SYLPH','FINAL_READ_COUNT_INCLUDING_MATES'),
    ]:
        if {num, denom}.issubset(combined.index) and combined[denom]:
            combined[rate] = f"{100 * combined[num] / combined[denom]:.4f}%"

    # (a) combined filtering/classification summary
    out_summary = os.path.join(args.results_dir, f'{sample}.summary.tsv')
    require_parent(out_summary)
    combined.to_frame().to_csv(out_summary, sep='\t', index=True, index_label='sample_id')
    if args.verbose:
        eprint(f'[summarize] wrote {out_summary}')

    # (b) normalized classifier tables (write K2/MPA/Sylph)
    write_normalized_tables(
        args.results_dir,
        sample,
        args.kraken_report_paired,
        args.kraken_report_unpaired,
        args.metaphlan_report,
        args.sylph_report_paired,
        args.sylph_report_unpaired,
        primary_reads,
        verbose=args.verbose
    )


if __name__ == '__main__':
    try:
        main()
    except SystemExit:
        raise
    except Exception as ex:
        eprint(f'FATAL: {ex}')
        sys.exit(1)
