# PathSeq T2T — Cirro

Host-subtraction + microbial profiling for WGS BAM/CRAM. Aligns reads against the CHM13 T2T human reference, removes host-matched reads, and classifies what remains with Kraken2.

## How it works in Cirro

1. Upload BAM or CRAM files to a Cirro dataset. CRAM is auto-converted using the GATK GRCh38 reference (downloaded on first run).
2. Launch this pipeline against the dataset. The samplesheet (`sample_id`, `bam`) is generated automatically from the dataset's file manifest.
3. Outputs land under the dataset's data path, one folder per sample.

## Parameters

| Field | Default | Notes |
| --- | --- | --- |
| Host-subtraction aligner | `bwa` | `bwa` (BWA-MEM) or `dragen` (Dragen-OS — only works if the container image includes it). |
| Kraken2 database URL | Standard 8GB DB | Override with a larger pre-built DB from https://benlangmead.github.io/aws-indexes/k2. Downloaded and cached on first run. |

## References auto-downloaded on first run

- CHM13 T2T FASTA + BWA index (UCSC `hs1`)
- PathSeq host index (`pathseq_host.bfi`, `pathseq_host.fa.img`, GATK GCS)
- Kraken2 standard DB (URL above)
- GATK GRCh38 FASTA (only when CRAM input is provided)

All caches live under `${outdir}/_ref_cache/` and persist across reruns via Nextflow `storeDir`.

## Outputs

Per sample, under `${outdir}/${sample_id}/`:

```
classification_stats/
  ${sample_id}.paired.kraken.report.txt
  ${sample_id}.unpaired.kraken.report.txt
results/
  ${sample_id}.summary.tsv        # filtering + classification summary
  ${sample_id}.kraken.txt         # normalized abundance table
```

## Roadmap (not in this version)

- MetaPhlAn 4 and Sylph classifiers (need either pipeline-side auto-download or pre-staged Cirro references).
- Optional metagenomic assembly + binning (`--assembly`) — needs CheckV and GTDB-Tk references.
- `hot.Parquet` post-processing of abundance tables for Cirro visualizations.

See the full upstream docs: https://github.com/peteryzheng/pathseq-t2t/blob/main/nextflow/README.md
