nextflow.enable.dsl = 2

process GENERATE_SYNTHETIC_METADATA {
    tag 'synthetic-metadata'

    output:
    path 'sample_metadata.csv', emit: metadata

    stub:
    '''
    cat > sample_metadata.csv <<'EOF'
barcode,cDNA_ID,SubjectId,Group,Challenge,Timepoint,Tissue,RCaudalPathScoreLongTerm,Vaccine,CFU_Tissue,TB_Study,species,RIRA_Immune.cellclass,RIRA_TNK_v2.cellclass,RIRA_Myeloid_v3.cellclass,TNK_Type,TandNK_ActivationCore_UCell
bc01,SAMPLE_01,SUBJ_01,BCG,Mtb,Day 7,Lung-R,1.1,BCG (adult),2.2,Synthetic Trial A,human,TNK,CD4+ T Cells,,Alpha/Beta,0.77
bc02,SAMPLE_01,SUBJ_01,BCG,Mtb,Day 7,Lung-R,1.1,BCG (adult),2.2,Synthetic Trial A,human,TNK,CD8+ T Cells,,Alpha/Beta,0.63
bc03,SAMPLE_01,SUBJ_01,BCG,Mtb,Day 7,Lung-R,1.1,BCG (adult),2.2,Synthetic Trial A,human,Myeloid,,MacrophageM1,,0.14
bc04,SAMPLE_02,SUBJ_02,BCG,Mtb,Day 28,Lung-L,0.7,IV-BCG,1.8,Synthetic Trial A,human,Myeloid,,Neutrophils,,0.25
bc05,SAMPLE_02,SUBJ_02,BCG,Mtb,Day 28,Lung-L,0.7,IV-BCG,1.8,Synthetic Trial A,human,TNK,NK,,Gamma/Delta,0.41
EOF
    '''

    script:
    """
    Rscript ${projectDir}/tests/fixtures/simulate_trial_data.R \
        --output-dir . \
        --target metadata \
        --seed 20260414
    """
}

process GENERATE_SYNTHETIC_RDS {
    tag 'synthetic-rds'

    output:
    path 'sample.rds', emit: rds

    stub:
    '''
    printf 'synthetic rds placeholder\n' > sample.rds
    '''

    script:
    """
    Rscript ${projectDir}/tests/fixtures/simulate_trial_data.R \
        --output-dir . \
        --target rds \
        --seed 20260414
    """
}

process GENERATE_SYNTHETIC_COUNTS {
    tag 'synthetic-counts'

    output:
    path 'sample_counts', emit: counts_dir

    stub:
    '''
    mkdir -p sample_counts
    touch sample_counts/matrix.mtx
    touch sample_counts/features.tsv
    touch sample_counts/barcodes.tsv
    touch sample_counts/obs_meta.csv
    '''

    script:
    """
    Rscript ${projectDir}/tests/fixtures/simulate_trial_data.R \
        --output-dir . \
        --target counts \
        --seed 20260414
    """
}

process GENERATE_SYNTHETIC_HARMONIZED {
    tag 'synthetic-harmonized'

    output:
    path 'harmonized_inputs', emit: harmonized

    stub:
    '''
    mkdir -p harmonized_inputs
    touch harmonized_inputs/00_human_harmonized.h5ad
    touch harmonized_inputs/01_macaque_harmonized.h5ad
    touch harmonized_inputs/integration_manifest.csv
    touch harmonized_inputs/shared_genes.csv
    touch harmonized_inputs/ortholog_mapping.csv
    printf '4\n' > harmonized_inputs/n_shared.txt
    '''

    script:
    """
    Rscript ${projectDir}/tests/fixtures/simulate_trial_data.R \
        --output-dir . \
        --target harmonized \
        --seed 20260414
    """
}