#!/usr/bin/env bash
# Extract Kraken2-classified HSV-1 reads from t2t-filtered BAMs and realign to
# a composite HSV reference. Requires: samtools, bwa (already indexed composite.fa).
set -euo pipefail

# ── config ────────────────────────────────────────────────────────────────────
RESULTS=/data/beroukhim1/youyun/BTC_GBM/data/wxs/results
COMPOSITE=/data/beroukhim1/youyun/BTC_GBM/refs/composite_hsv.fa   # build with efetch (see README)
OUTDIR=/data/beroukhim1/youyun/BTC_GBM/data/wxs/hsv1_reads
TAXID=10298   # HSV-1; add 10310 for HSV-2 with: awk '$3==10298||$3==10310'
THREADS=8
# ─────────────────────────────────────────────────────────────────────────────

SAMPLES=(
    GBM1.DFCI4.S1.CSF
    GBM1.DFCI4.S2.CSF
    GBM1.DFCI4.S3.CSF
    GBM1.DFCI4.S4.CSF
    GBM1.DFCI4.S5.CSF
    GBM1.DFCI4.S6.CSF
)

mkdir -p "$OUTDIR"

for sample in "${SAMPLES[@]}"; do
    echo "=== ${sample} ==="

    src="${RESULTS}/${sample}"
    paired_bam="${src}/bams/${sample}.t2tfilt_paired.bam"
    unpaired_bam="${src}/bams/${sample}.t2tfilt_unpaired.bam"
    kraken_paired="${src}/classification_stats/${sample}.paired.kraken.output.txt"
    kraken_unpaired="${src}/classification_stats/${sample}.unpaired.kraken.output.txt"

    # Skip sample if pipeline outputs are missing (not yet run, or no reads passed filter)
    missing=0
    for f in "$paired_bam" "$unpaired_bam" "$kraken_paired" "$kraken_unpaired"; do
        [[ -f "$f" ]] || { echo "  MISSING: $f"; missing=1; }
    done
    [[ $missing -eq 1 ]] && { echo "  Skipping ${sample}"; continue; }

    work="${OUTDIR}/${sample}"
    mkdir -p "$work"

    # 1. Extract HSV-1 read IDs from Kraken per-read output
    awk -v t="$TAXID" '$1=="C" && $3==t {print $2}' "$kraken_paired"   > "${work}/paired.ids"
    awk -v t="$TAXID" '$1=="C" && $3==t {print $2}' "$kraken_unpaired" > "${work}/unpaired.ids"

    n_paired=$(wc -l < "${work}/paired.ids")
    n_unpaired=$(wc -l < "${work}/unpaired.ids")
    echo "  HSV-1 read IDs: ${n_paired} paired-fragments, ${n_unpaired} unpaired"

    # ── paired ────────────────────────────────────────────────────────────────
    if [[ $n_paired -gt 0 ]]; then
        # 2. Subset BAM by read name, then name-sort (required for samtools fastq pairing)
        samtools view -bh -@ "$THREADS" -N "${work}/paired.ids" "$paired_bam" \
            | samtools sort -n -@ "$THREADS" -o "${work}/paired.nsort.bam" -

        # 3. BAM -> FASTQ
        samtools fastq -@ "$THREADS" \
            -1 "${work}/R1.fq.gz" \
            -2 "${work}/R2.fq.gz" \
            -0 /dev/null -s /dev/null -N \
            "${work}/paired.nsort.bam"

        # 4. Align to composite HSV reference
        bwa mem -t "$THREADS" "$COMPOSITE" "${work}/R1.fq.gz" "${work}/R2.fq.gz" \
            | samtools sort -@ "$THREADS" -o "${OUTDIR}/${sample}.hsv1.paired.bam" -
        samtools index "${OUTDIR}/${sample}.hsv1.paired.bam"

        rm "${work}/paired.nsort.bam" "${work}/R1.fq.gz" "${work}/R2.fq.gz"
        echo "  -> ${OUTDIR}/${sample}.hsv1.paired.bam"
    else
        echo "  No paired HSV-1 reads — skipping paired alignment"
    fi

    # ── unpaired / singleton ──────────────────────────────────────────────────
    if [[ $n_unpaired -gt 0 ]]; then
        samtools view -bh -@ "$THREADS" -N "${work}/unpaired.ids" "$unpaired_bam" \
            > "${work}/unpaired.subset.bam"

        samtools fastq -@ "$THREADS" "${work}/unpaired.subset.bam" \
            | gzip > "${work}/U.fq.gz"

        bwa mem -t "$THREADS" "$COMPOSITE" "${work}/U.fq.gz" \
            | samtools sort -@ "$THREADS" -o "${OUTDIR}/${sample}.hsv1.unpaired.bam" -
        samtools index "${OUTDIR}/${sample}.hsv1.unpaired.bam"

        rm "${work}/unpaired.subset.bam" "${work}/U.fq.gz"
        echo "  -> ${OUTDIR}/${sample}.hsv1.unpaired.bam"
    else
        echo "  No unpaired HSV-1 reads — skipping unpaired alignment"
    fi
done

echo ""
echo "All samples complete. Output BAMs in: ${OUTDIR}/"
echo "Quick read counts:"
for bam in "${OUTDIR}"/*.bam; do
    [[ -f "$bam" ]] || continue
    n=$(samtools view -c "$bam")
    printf "  %-55s  %d reads\n" "$(basename $bam)" "$n"
done
