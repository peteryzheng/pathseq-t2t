# Changelog

All notable changes to pathseq-t2t are documented here.
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

## [Unreleased]

### Changed
- Meta map refactor: all modules now use `val(meta)` (Groovy map with `id` key) instead of bare `val(sample_id)`, aligning with nf-core conventions
- Extracted filtering chain (PREFILTER → QCFILTER → T2TFILTER) into `subworkflows/local/filter.nf`
- Extracted classification fan-out (KRAKEN / METAPHLAN / SYLPH) into `subworkflows/local/classify.nf`
- Resource allocations moved from `conf/resources.config` to `conf/base.config` with nf-core `check_max()` helper
- Test profile moved from `nextflow.config` to `conf/test.config`

### Added
- `nextflow_schema.json` — JSON Schema parameter validation; enables `--help`, nf-schema type checking, and Seqera Platform UI
- `nf-schema@2.1.1` plugin for `validateParameters()` and `paramsHelp()`
- `params.max_cpus`, `params.max_memory`, `params.max_time` resource caps

## [0.3.0]

### Added
- `report.overwrite = true` to prevent re-run errors when HTML reports already exist

### Fixed
- sylph and sylph-tax moved from pip to conda-forge/bioconda in `envs/main.yml`
- Removed python=3.10 pin from `envs/checkm2.yml` (incompatible with all checkm2 versions)

## [0.2.0]

### Added
- GitHub Actions workflow to build and push Docker image to GHCR on push to `main` and version tags
- SLURM profile using Singularity/Apptainer for HPC execution (modeled on ERISTwo cluster)
- Local profile using Docker
- CRAM auto-conversion module (`CRAM_TO_BAM`) with hg38 auto-download via `DOWNLOAD_HG38`
- Auto-download of reference data on first run: CHM13v2 T2T FASTA + BWA index (`DOWNLOAD_REFERENCE`), PathSeq host index (`DOWNLOAD_HOST_INDEX`), Kraken2 8GB DB (`DOWNLOAD_KRAKEN_DB`)
- `storeDir` caching so downloads run once per `outdir` across reruns
- `--reference`, `--hostdir`, `--kraken_index` are now optional

## [0.1.0]

### Added
- Initial Nextflow DSL2 pipeline with host-subtraction (PREFILTER → QCFILTER → T2TFILTER) and microbial classification (Kraken2, MetaPhlAn, Sylph)
- Optional metagenomic assembly (MEGAHIT + MetaBAT2 + CheckM2/CheckV + GTDB-Tk)
- AWS Batch profile
- Docker image via `Dockerfile` with isolated conda environments per tool
