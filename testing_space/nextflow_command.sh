#!/usr/bin/env bash

nextflow run ../main.nf \
  --profile local \
  --workflow ingest_tabulate \
  --input ./samplesheet.csv \
  --labkey_base_url 'https://prime-seq.ohsu.edu' \
  --labkey_folder '/Labs/Bimber' \
  --resume
