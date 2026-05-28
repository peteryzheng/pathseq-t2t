# pathseq-t2t Nextflow pipeline

Nextflow DSL2 pipeline for host subtraction and microbial profiling of human sequencing data.

## Quick start

```bash
nextflow run nextflow/main.nf \
  -profile slurm \
  --samplesheet samples.csv \
  --hostdir /refs/pathseq_host \
  --reference /refs/chm13v2.fa
```

## Samplesheet

CSV with `sample_id` and `bam` columns. Both BAM and CRAM inputs are accepted; CRAM files are auto-converted using the GATK GRCh38 reference (downloaded once if `--hg38_ref` is not provided).

```csv
sample_id,bam
sample1,/path/to/sample1.hg38.bam
sample2,/path/to/sample2.hg38.cram
```

A template is at `assets/samplesheet_template.csv`.

## Workflow

```
[BAM / CRAM input]
       │
  CRAM_TO_BAM          (CRAM inputs only — samtools view with GRCh38 reference)
       │
  ┌────▼────────────────────────────────────┐
  │ FILTER subworkflow                       │
  │   PREFILTER   → extract unaligned reads  │
  │   QCFILTER    → PathSeq host filtering   │
  │   T2TFILTER   → T2T CHM13v2 alignment   │
  └────────────────────────┬────────────────┘
                           │
  ┌────────────────────────▼────────────────┐
  │ CLASSIFY subworkflow (any combination)   │
  │   CLASSIFY_KRAKEN                        │
  │   CLASSIFY_METAPHLAN                     │
  │   CLASSIFY_SYLPH                         │
  └────────────────────────┬────────────────┘
                           │
                       SUMMARIZE
                           │
                    results/{id}.summary.tsv
```

Optional assembly branch (enabled with `--assembly`):
```
PREFILTER.unaligned + decoys → ASSEMBLE → BINQC + BINCLASSIFY → SUMMARIZE_ASSEMBLY
```

## Key parameters

| Parameter | Required | Description |
|---|---|---|
| `--samplesheet` | ✓ | Path to CSV samplesheet |
| `--hostdir` | ✓ | PathSeq host index directory (`.bfi` + `.fa.img`) |
| `--reference` | ✓ | CHM13v2 T2T FASTA for host subtraction |
| `--hg38_ref` | | GRCh38 FASTA for CRAM decoding; auto-downloaded if absent |
| `--classifiers` | | Comma-separated: `kraken`, `metaphlan`, `sylph` (default: `kraken`) |
| `--outdir` | | Output directory (default: `./results`) |
| `--assembly` | | Enable metagenomic assembly pipeline (default: `false`) |
| `--aligner` | | Aligner used to generate input BAMs: `bwa` or `dragen` (default: `bwa`) |

Classifier-specific parameters (required only when the classifier is enabled):

| Parameter | Classifier | Description |
|---|---|---|
| `--kraken_index` | kraken | Kraken2 database directory; auto-downloaded (8 GB standard) if absent |
| `--metaphlan_index` | metaphlan | MetaPhlAn database name, e.g. `mpa_vJun23_CHOCOPhlAnSGB_202403` |
| `--bowtie2_index` | metaphlan | Directory with MetaPhlAn Bowtie2 index |
| `--sylph_index` | sylph | Path to `.syldb` file |

Full parameter list and descriptions: `nextflow_schema.json`.

## Profiles

| Profile | Executor | Container |
|---|---|---|
| `local` | Local | Docker |
| `slurm` | SLURM | Singularity |
| `aws` | AWS Batch | — |
| `test` | — | Minimal test config |

SLURM-specific params: `--slurm_queue`, `--slurm_account`, `--slurm_options`.

## Outputs

Only final deliverables are written to `--outdir`; intermediate BAMs are not published.

```
results/
└── {sample_id}/
    ├── classification_stats/
    │   ├── {id}.paired.kraken.report.txt
    │   ├── {id}.unpaired.kraken.report.txt
    │   ├── {id}.metaphlan.report.txt
    │   ├── {id}.paired.taxonomy.txt       (Sylph)
    │   └── {id}.unpaired.taxonomy.txt
    └── results/
        ├── {id}.summary.tsv
        └── {id}.*.txt                     (classifier abundance tables)
```

Pipeline-level reports (DAG, timeline, execution report) are written to `--outdir` root.

## Directory structure

```
nextflow/
├── main.nf                        # Entry point
├── nextflow.config                # Params, profiles, reporting
├── nextflow_schema.json           # nf-schema parameter definitions
├── assets/
│   └── samplesheet_template.csv
├── conf/
│   ├── base.config                # Resource allocations + retry logic
│   ├── slurm.config               # SLURM + Singularity settings
│   ├── aws.config                 # AWS Batch settings
│   └── test.config                # Minimal test overrides
├── modules/
│   ├── cram_to_bam.nf             # CRAM → BAM conversion
│   ├── prefilter.nf               # Extract unaligned + decoy reads
│   ├── qcfilter.nf                # PathSeq host QC filtering
│   ├── t2tfilter.nf               # T2T CHM13v2 alignment filter
│   ├── classify.nf                # Kraken2 / MetaPhlAn / Sylph
│   ├── assemble.nf                # MEGAHIT + MetaBAT2
│   ├── binqc.nf                   # CheckM2 / CheckV bin QC
│   ├── binclassify.nf             # GTDB-Tk bin classification
│   ├── summarize.nf               # Per-sample summary TSV
│   ├── summarize_assembly.nf      # Assembly summary TSV
│   └── download_refs.nf           # Reference auto-download processes
└── subworkflows/local/
    ├── filter.nf                  # PREFILTER → QCFILTER → T2TFILTER
    └── classify.nf                # Classifier fan-out + empty-channel handling
```
