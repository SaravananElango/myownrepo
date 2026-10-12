-- 03_marts.sql: fact and dimension tables for reporting, no new business logic.

set @@dataset_id = '{{DATASET}}';

-- descriptions per risk
create or replace table dim_risk as
select
    risk_id,
    risk_title,
    risk_category,
    control_reference,
    treatment_strategy,
    severity_code,
    severity_label,
    severity_rank,
    status,
    status_group,
    status_sort,
    risk_owner_id,
    org_unit,
    risk_reviewer_id,
    owning_legal_entity,
    primary_application_id,
    primary_application_name,
    highest_application_criticality
from int_risk;

-- descriptions per application
create or replace table dim_application as
select
    application_id,
    application_name,
    application_type,
    application_criticality,
    is_cif_supporting,
    owning_legal_entity,
    hosting_model,
    primary_region,
    lifecycle_status
from stg_application_catalog;

-- DQ rule descriptions for the DQ page
create or replace table dim_dq_rule as
select rule_id, rule_name, dq_dimension, description, treatment, treatment_detail, designed_count
from ref_dq_rules;

-- one row per risk: dates, scores and flags
create or replace table fct_risk as
select
    as_at_date,
    risk_id,
    created_date,
    last_updated_date,
    target_mitigation_date,

    inherent_impact,
    inherent_likelihood,
    inherent_score,
    residual_impact,
    residual_likelihood,
    residual_score,
    score_reduction,
    progress_percent,
    age_days,
    days_since_update,
    days_past_target,
    application_count,
    affected_legal_entity_count,
    dq_issue_count,
    source_row_count,

    is_high_sig,
    is_accepted,
    is_overdue,
    is_acceptance_expired,
    is_stale,
    is_complete_not_closed,
    is_cif_supporting,
    cif_per_source_flag,
    touches_non_active_application,
    has_acceptance_justification,
    has_owner,

    overdue_bucket,
    overdue_bucket_sort,
    age_bucket,
    age_bucket_sort
from int_risk;

-- one row per risk-app link, with the risk flags needed for app charts
create or replace table fct_risk_application as
select
    r.as_at_date,
    l.risk_id,
    l.application_id,
    l.relationship_type,
    l.sequence,
    l.allocation_weight,
    r.residual_score,
    r.is_high_sig,
    r.is_overdue,
    r.is_accepted,
    r.overdue_bucket
from int_risk_application_link as l
left join int_risk as r using (risk_id);

-- one row per source row x DQ rule
create or replace table fct_dq_check as
select
    (select max(as_at_date) from int_risk) as as_at_date,
    source_row_id,
    risk_id,
    rule_id,
    is_failed
from int_dq_check;

-- checks: unique keys, row counts, every fact key exists in its dim
assert (select count(*) - count(distinct risk_id) from dim_risk) = 0
    as '3c: duplicate risk_id in dim_risk';

assert (select count(*) - count(distinct application_id) from dim_application) = 0
    as '3c: duplicate application_id in dim_application';

assert (select count(*) - count(distinct rule_id) from dim_dq_rule) = 0
    as '3c: duplicate rule_id in dim_dq_rule';

assert (select count(*) from fct_risk) = (select count(*) from int_risk)
    as '3c: fct_risk row count does not match int_risk';

assert (select count(*) from fct_risk_application) = (select count(*) from int_risk_application_link)
    as '3c: fct_risk_application row count does not match int_risk_application_link';

assert (select count(*) from fct_dq_check) = (select count(*) from int_dq_check)
    as '3c: fct_dq_check row count does not match int_dq_check';

assert (select count(*) from fct_risk as f left join dim_risk as d using (risk_id) where d.risk_id is null) = 0
    as '3c: risk_id in fct_risk missing from dim_risk';

assert (select count(*) from fct_risk_application as f left join dim_risk as d using (risk_id) where d.risk_id is null) = 0
    as '3c: risk_id in fct_risk_application missing from dim_risk';

assert (select count(*) from fct_risk_application as f left join dim_application as d using (application_id) where d.application_id is null) = 0
    as '3c: application_id in fct_risk_application missing from dim_application';

assert (select count(*) from fct_dq_check as f left join dim_risk as d using (risk_id) where d.risk_id is null) = 0
    as '3c: risk_id in fct_dq_check missing from dim_risk';

assert (select count(*) from fct_dq_check as f left join dim_dq_rule as d using (rule_id) where d.rule_id is null) = 0
    as '3c: rule_id in fct_dq_check missing from dim_dq_rule';
