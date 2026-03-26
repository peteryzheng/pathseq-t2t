# pathseq-t2t

PathSeq-T2T is a host-subtraction and microbial profiling workflow for low-biomass sequencing data.

## Install

```bash
git clone https://github.com/<your-org>/pathseq-t2t.git
cd pathseq-t2t
chmod +x src/pathseq-t2t
export PATH="$PWD/src:$PATH"
pathseq-t2t --help
```

Conda environment setup is not implemented yet.

## Commands

- `prefilter`
- `qcfilter`
- `t2tfilter`
- `filter`
- `classify`
- `assemble`
- `binqc`
- `binclassify`
- `summarize`
- `summarize-assembly`

Default output root is `./pst2t_out`.

## Naming policy

Each command supports two modes:

- `--sample-id` mode: input/output paths are filled using command defaults.
- Explicit mode (no `--sample-id`): input/output paths must be provided explicitly.


## Core dependencies

- `samtools >= 1.16`
- `gatk >= 4`
- `java 17`
- `picard`
- `bwa >= 0.7.17`
- `kraken2`
- `metaphlan >= 4`
- `sylph >= 0.9.0` and `sylph-tax` (if using Sylph)
- `python3` + `pandas` (for `summarize`)

Additional dependencies for `assemble`:

- `trim_galore >= 0.6.10`
- `megahit >= 1.2.9`
- `bowtie2` and `bowtie2-build`
- `metabat2` and `jgi_summarize_bam_contig_depths`
- `pigz` (optional; gzip fallback is used if absent)

Additional dependencies for `binqc`:

- `checkm2`
- `checkv` (required in default `binqc --model both` mode)

Additional dependencies for `binclassify`:

- `gtdbtk`
- `GTDBTK_DATA_PATH` set to a compatible GTDB-Tk reference data directory

## Reference databases/files

- PathSeq host directory containing:
  - `pathseq_host.bfi`
  - `pathseq_host.fa.img`
- T2T FASTA (`--reference` or `$T2TREF`) for `t2tfilter`
- Kraken2 database for Kraken (`--kraken-index` or `$KRAKEN_INDEX`)
- MetaPhlAn index name and Bowtie2 index dir for MetaPhlAn (`--metaphlan-index` / `--bowtie2-index` or env vars)
- Sylph `.syldb` file(s) and taxonomy tag(s) for Sylph mode

## Typical workflow

```bash
pathseq-t2t prefilter --input-bam sample.bam --aligner bwa --decoys-to-mask non_human_decoys.bed

pathseq-t2t filter --input-bam sample.bam --aligner bwa --decoys-to-mask non_human_decoys.bed \
  --sample-id sample --hostdir /refs/pathseq_host --reference /refs/t2t.fa --outdir ./pst2t_out

pathseq-t2t qcfilter --sample-id sample --hostdir /refs/pathseq_host --outdir ./pst2t_out

pathseq-t2t t2tfilter --sample-id sample --reference /refs/t2t.fa --outdir ./pst2t_out

pathseq-t2t classify --sample-id sample --classifiers kraken,metaphlan,sylph --outdir ./pst2t_out \
  --kraken-index /db/k2_pluspf_20240605 \
  --metaphlan-index mpa_vJun23_CHOCOPhlAnSGB_202403 \
  --bowtie2-index /db/mpa_vJun23_CHOCOPhlAnSGB_202403_bt2.tar \
  --sylph-index /db/gtdb-r226-c200-dbv1.syldb \
  --sylph-taxonomy GTDB_r226

pathseq-t2t assemble --sample-id sample --input-unaligned ./pst2t_out/bams/sample.prefilter.unaligned.bam \
  --input-decoys ./pst2t_out/bams/sample.prefilter.decoys.bam --outdir ./pst2t_out

pathseq-t2t binqc --sample-id sample --outdir ./pst2t_out

pathseq-t2t binclassify --sample-id sample --outdir ./pst2t_out

pathseq-t2t summarize --sample-id sample --outdir ./pst2t_out --results-dir ./pst2t_out/results -v

pathseq-t2t summarize-assembly --sample-id sample --outdir ./pst2t_out \
  --input-flagstat ./pst2t_out/filter_stats/sample.flagstat.tsv
```

## Resource guidance

Approximate memory usage by step (run steps separately on HPC when possible):

- `prefilter`: 50-100 MB
- `qcfilter`: 32-64 GB
- `t2tfilter`: 4-8 GB
- `classify`: ~128 GB (Kraken), 32-64 GB (MetaPhlAn, Sylph)

## Command reference

### 1) `filter`

Run `prefilter`, `qcfilter`, and `t2tfilter` in sequence as a single command.

```bash
pathseq-t2t filter \
  --input-bam <bam> \
  --aligner <dragen|bwa> \
  --decoys-to-mask <bed|None> \
  [--sample-id <id>] \
  [--outdir <dir>] \
  [--hostdir <dir>] \
  [--reference <t2t.fa>] \
  [--threads <int>] \
  [--dont-overwrite] \
  [--keep-intermediate] \
  [--prefilter-args "<args>"] \
  [--qcfilter-args "<args>"] \
  [--t2tfilter-args "<args>"]
```

Required inputs:

- `--input-bam`, `--aligner`, `--decoys-to-mask`
- `--hostdir <dir>` or `$HOSTDIR`
- `--reference <t2t.fa>` or `$T2TREF`

### 2) `prefilter`

Select host-unmapped reads and decoy-overlapping reads from an input BAM.

```bash
pathseq-t2t prefilter \
  --input-bam <bam> \
  --aligner <dragen|bwa> \
  --decoys-to-mask <bed|None> \
  [--sample-id <id>] \
  [--outdir <dir>] \
  [--unaligned-out <bam>] \
  [--decoys-out <bam>] \
  [--flagstat-out <tsv>] \
  [--threads <int>] \
  [--dont-overwrite]
```

Required inputs:

- Always: `--input-bam`, `--aligner`, `--decoys-to-mask`
- With `--sample-id`: outputs default under `<outdir>`
- Without `--sample-id`: provide `--unaligned-out`, `--decoys-out`, and `--flagstat-out`

Default outputs:

- `<outdir>/bams/<ID>.prefilter.unaligned.bam`
- `<outdir>/bams/<ID>.prefilter.decoys.bam`
- `<outdir>/filter_stats/<ID>.flagstat.tsv`

### 3) `qcfilter`

Run PathSeqFilterSpark on prefilter outputs (unaligned + decoys), then merge outputs.

```bash
pathseq-t2t qcfilter \
  [--outdir <dir>] \
  [--sample-id <id>] \
  [--hostdir <dir>] \
  [--input-unaligned <bam>] \
  [--input-decoys <bam>] \
  [--paired-out <bam>] \
  [--unpaired-out <bam>] \
  [--metrics-unaligned <txt>] \
  [--metrics-decoys <txt>] \
  [--threads <int>] \
  [--ram-gb <int>] \
  [--tmpdir <dir>] \
  [--min-clipped-read-length <int>] \
  [--psfilterspark-args "<args>"] \
  [--picard-jar <jar>] \
  [--dont-overwrite] \
  [--keep-intermediate]
```

Required inputs:

- `--hostdir <dir>` or `$HOSTDIR`
- With `--sample-id`: missing inputs/outputs/metrics are filled from defaults
- Without `--sample-id`: provide `--input-unaligned`, `--paired-out`, `--unpaired-out`, and `--metrics-unaligned`
- If `--input-decoys` is provided without `--sample-id`, also provide `--metrics-decoys`

Default outputs:

- `<outdir>/bams/<ID>.qcfilt_paired.bam`
- `<outdir>/bams/<ID>.qcfilt_unpaired.bam`
- `<outdir>/filter_stats/<ID>.prefilter.unaligned.filter_metrics.txt`
- `<outdir>/filter_stats/<ID>.prefilter.decoys.filter_metrics.txt`

### 4) `t2tfilter`

Subtract reads by alignment to T2T reference and emit unmapped paired/unpaired BAMs.

```bash
pathseq-t2t t2tfilter \
  [--outdir <dir>] \
  [--sample-id <id>] \
  [--input-paired <bam>] \
  [--input-unpaired <bam>] \
  [--reference <t2t.fa>] \
  [--decoys-to-mask <bed|None>] \
  [--output-paired <bam>] \
  [--output-unpaired <bam>] \
  [--flagstat-unaln-paired <tsv>] \
  [--flagstat-unaln-unpaired <tsv>] \
  [--threads <int>] \
  [--picard-jar <jar>] \
  [--dont-overwrite] \
  [--keep-intermediate]
```

Required inputs:

- `--reference <t2t.fa>` or `$T2TREF`
- With `--sample-id`: missing inputs/outputs/flagstats are filled from defaults
- Without `--sample-id`: provide `--input-paired`, `--input-unpaired`, `--output-paired`, `--output-unpaired`, `--flagstat-unaln-paired`, and `--flagstat-unaln-unpaired`
- If `--decoys-to-mask <bed>` is provided, aligned reads overlapping those regions are merged back into the final paired/unpaired outputs.

Default outputs:

- `<outdir>/bams/<ID>.t2tfilt_paired.bam`
- `<outdir>/bams/<ID>.t2tfilt_unpaired.bam`
- `<outdir>/filter_stats/<ID>.qcfilt_paired.t2t_unaln.flagstat.tsv`
- `<outdir>/filter_stats/<ID>.qcfilt_unpaired.t2t_unaln.flagstat.tsv`

### 5) `classify`

Classify T2T-filtered reads with one or more classifiers.

```bash
pathseq-t2t classify \
  [--outdir <dir>] \
  [--sample-id <id>] \
  [--input-paired <bam>] \
  [--input-unpaired <bam>] \
  [--classifiers "kraken,metaphlan,sylph"] \
  [--kraken-index <dir>] \
  [--metaphlan-index <name>] \
  [--bowtie2-index <dir>] \
  [--sylph-index <file.syldb>]... \
  [--sylph-taxonomy <name>]... \
  [--kraken-args "<args>"] \
  [--metaphlan-args "<args>"] \
  [--sylph-args "<args>"] \
  [--threads <int>] \
  [--picard-jar <jar>] \
  [--java-mem <mem>] \
  [--dont-overwrite] \
  [--keep-intermediate]
```

Required inputs:

- With `--sample-id`: missing input/output paths are filled from defaults
- Without `--sample-id`: provide explicit `--input-paired` and `--input-unpaired`
- Without `--sample-id`: provide explicit output/report paths for selected classifiers
- If running Kraken (default): `--kraken-index <dir>` or `$KRAKEN_INDEX`
- If running MetaPhlAn: `--metaphlan-index <name>` and `--bowtie2-index <dir>` (or env vars)
- If running Sylph: one or more `--sylph-index` and `--sylph-taxonomy` values

Default reports are written in `<outdir>/classification_stats`.

### 6) `assemble`

Assemble reads from prefilter outputs and perform binning.

```bash
pathseq-t2t assemble \
  --input-unaligned <bam> \
  [--input-decoys <bam>] \
  [--sample-id <id>] \
  [--outdir <dir>] \
  [--assembly-dir <dir>] \
  [--threads <int>] \
  [--min-contig-len <int>] \
  [--trim-galore-args "<args>"] \
  [--dont-overwrite] \
  [--keep-intermediate]
```

Required inputs:

- Always: `--input-unaligned`
- With `--sample-id`: `--assembly-dir` defaults to `<outdir>/assembly/<sample-id>`
- Without `--sample-id`: provide `--assembly-dir`

Pipeline steps:

1. BAM to FASTQ (`samtools collate` + `samtools fastq`)
2. Read trimming (`trim_galore`)
3. Assembly (`megahit`)
4. Contig indexing and mapping (`bowtie2-build`, `bowtie2`)
5. Depth estimation and binning (`jgi_summarize_bam_contig_depths`, `metabat2`)

Default output root:

- `<outdir>/assembly/<sample>/`

### 7) `binqc`

Run CheckM2 on assembled bins.

```bash
pathseq-t2t binqc \
  [--sample-id <id>] \
  [--outdir <dir>] \
  [--assembly-dir <dir>] \
  [--bins-dir <dir>] \
  [--qc-dir <dir>] \
  [--model <both|checkm2|checkv>] \
  [--checkv-db <dir>] \
  [--threads <int>] \
  [--dont-overwrite]
```

Required inputs:

- With `--sample-id`: defaults are inferred under `<outdir>/assembly/<sample-id>/...`
- Without `--sample-id`: provide explicit `--bins-dir`
- `--qc-dir` is only valid in single-model mode (`checkm2` or `checkv`)
- Default `--model` is `both` (runs CheckM2 then CheckV)
- For CheckV mode: provide `--checkv-db <dir>` or set `$CHECKVDB`

Default outputs:

- `--model both`: `<outdir>/assembly/<sample>/checkm2/quality_report.tsv` and `<outdir>/assembly/<sample>/checkv/quality_summary.tsv`
- `--model checkm2`: `<outdir>/assembly/<sample>/checkm2/quality_report.tsv`
- `--model checkv`: `<outdir>/assembly/<sample>/checkv/quality_summary.tsv`

### 8) `binclassify`

Classify assembled bins with GTDB-Tk.

```bash
pathseq-t2t binclassify \
  [--sample-id <id>] \
  [--outdir <dir>] \
  [--assembly-dir <dir>] \
  [--bins-dir <dir>] \
  [--classify-dir <dir>] \
  [--threads <int>] \
  [--extension <ext>] \
  [--gtdbtk-args "<args>"] \
  [--dont-overwrite]
```

Required inputs:

- With `--sample-id`: defaults are inferred under `<outdir>/assembly/<sample-id>/...`
- Without `--sample-id`: provide `--bins-dir`
- If `--sample-id` is omitted and `--classify-dir` is omitted, provide `--assembly-dir`
- `GTDBTK_DATA_PATH` must point to the GTDB-Tk reference data directory

Default outputs:

- `<outdir>/assembly/<sample>/gtdbtk_output/*.summary.tsv`

GTDB-Tk writes bacterial and archaeal classification summaries such as:

- `gtdbtk.bac120.summary.tsv`
- `gtdbtk.ar53.summary.tsv`

### 9) `summarize`

Generate combined filtering/classification summary and normalized classifier tables.

```bash
pathseq-t2t summarize \
  --sample-id <id> \
  [--outdir <dir>] \
  [--results-dir <dir>] \
  [--input-flagstat <tsv>] \
  [--qcfilter-metrics-unaligned <txt>] \
  [--qcfilter-metrics-decoys <txt>] \
  [--t2tfilter-flagstat-paired <tsv>] \
  [--t2tfilter-flagstat-unpaired <tsv>] \
  [--kraken-report-paired <txt>] \
  [--kraken-report-unpaired <txt>] \
  [--metaphlan-report <txt>] \
  [--sylph-report-paired <txt>] \
  [--sylph-report-unpaired <txt>] \
  [-v|--verbose]
```

Default outputs in `<results-dir>`:

- `<sample>.summary.tsv`
- `<sample>.kraken.txt` (if Kraken2 reports exist)
- `<sample>.metaphlan.txt` (if MetaPhlAn report exists)
- `<sample>.sylph.txt` (if Sylph reports exist)

### 10) `summarize-assembly`

Generate per-sample assembly QC and bin classification summaries from `assemble`, `binqc`, and `binclassify` outputs.

```bash
pathseq-t2t summarize-assembly \
  --sample-id <id> \
  [--outdir <dir>] \
  [--assembly-dir <dir>] \
  [--results-dir <dir>] \
  [--input-flagstat <tsv>] \
  [-v|--verbose]
```

Required inputs:

- `--sample-id`
- With `--sample-id`: assembly directory defaults to `<outdir>/assembly/<sample-id>`
- `--input-flagstat`: prefilter flagstat TSV (provides primary read count; inferred from `<outdir>/filter_stats/<sample>.flagstat.tsv` when using `--sample-id` defaults)

Default outputs in `<outdir>/results/`:

- `<sample>.assembly_summary.tsv` — one-row pipeline QC summary (read counts, assembly stats, binning stats, CheckM2/CheckV/GTDB-Tk counts)
- `<sample>.bin_summary.tsv` — one row per bin (completeness, contamination, viral quality, taxonomy)
