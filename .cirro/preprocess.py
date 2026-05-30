#!/usr/bin/env python3
from cirro.helpers.preprocess_dataset import PreprocessDataset

ds = PreprocessDataset.from_running()
ds.logger.info("Starting params:")
ds.logger.info(ds.params)
ds.logger.info("Files in dataset:")
ds.logger.info(ds.files.to_csv(index=False))

bam_like = ds.files[
    ds.files["file"].str.lower().str.endswith((".bam", ".cram"))
].copy()
assert len(bam_like) > 0, "No BAM or CRAM files found in dataset"

if "sample" in bam_like.columns and bam_like["sample"].notna().any():
    bam_like["sample_id"] = bam_like["sample"]
else:
    bam_like["sample_id"] = bam_like["file"].apply(
        lambda p: p.rsplit("/", 1)[-1].rsplit(".", 1)[0]
    )

samplesheet = (
    bam_like[["sample_id", "file"]]
    .rename(columns={"file": "bam"})
    .drop_duplicates("sample_id")
    .reset_index(drop=True)
)
ds.logger.info("Generated samplesheet:")
ds.logger.info(samplesheet.to_csv(index=False))
samplesheet.to_csv("samplesheet.csv", index=False)
ds.add_param("samplesheet", "samplesheet.csv")

ds.logger.info("Final params:")
ds.logger.info(ds.params)
