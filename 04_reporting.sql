-- 04_reporting.sql: flat tables for the dashboard, each built from one fact and its dims.

-- declare before set
declare reference_date date;

set @@dataset_id = '{{DATASET}}';

set reference_date = (select max(as_at_date) from fct_risk);

-- one row per risk with labels, sort keys and 0/1 counters
create or replace table rpt_risk as
select
    f.as_at_date,
    f.risk_id,
    dr.risk_title,
    dr.risk_category,
    dr.control_reference,
    dr.status,
    dr.treatment_strategy,
    dr.severity_code,
    dr.risk_owner_id,
    dr.org_unit,
    dr.risk_reviewer_id,
    dr.owning_legal_entity,
    dr.primary_application_id,
    dr.primary_application_name,
    f.created_date,
    f.last_updated_date,
    f.target_mitigation_date,
    extract(year from f.created_date) as created_year,
    coalesce(format_date('%Y-Q%Q', f.target_mitigation_date), 'No target date') as target_year_quarter,

    f.inherent_impact,
    f.inherent_likelihood,
    f.inherent_score,
    f.residual_impact,
    f.residual_likelihood,
    f.residual_score,
    f.score_reduction,
    f.progress_percent,
    f.application_count,
    dr.highest_application_criticality,
    f.is_cif_supporting,
    f.touches_non_active_application,
    f.affected_legal_entity_count,
    f.is_accepted,
    f.has_acceptance_justification,
    f.has_owner,
    f.source_row_count,
    f.age_days,
    f.days_since_update,
    f.days_past_target,
    f.dq_issue_count,
    f.is_high_sig,
    f.is_overdue,
    f.is_acceptance_expired,
    f.is_stale,
    f.is_complete_not_closed,
    f.overdue_bucket,
    f.age_bucket,

    dr.severity_label,
    dr.severity_rank,
    dr.status_group,
    dr.status_sort,
    f.overdue_bucket_sort,
    f.age_bucket_sort,
    if(f.is_cif_supporting, 'CIF', 'Non-CIF') as cif_label,
    if(f.is_overdue, 'Overdue', 'Not overdue') as overdue_label,
    cast(f.is_overdue as int64) as overdue_cnt,
    cast(f.is_high_sig as int64) as high_sig_cnt,
    cast(not f.is_accepted as int64) as non_accepted_cnt,
    cast(f.is_cif_supporting as int64) as cif_cnt,
    cast(f.is_stale as int64) as stale_cnt
from fct_risk as f
left join dim_risk as dr on dr.risk_id = f.risk_id;

-- one row per risk-app link; count risks with count(distinct risk_id)
create or replace table rpt_risk_application as
select
    b.risk_id,
    b.application_id,
    b.relationship_type,
    b.allocation_weight,
    a.application_name,
    a.application_type,
    a.application_criticality,
    a.is_cif_supporting as app_is_cif_supporting,
    a.owning_legal_entity as app_legal_entity,
    a.hosting_model,
    a.primary_region,
    a.lifecycle_status,
    dr.severity_code,
    dr.severity_label,
    dr.severity_rank,
    dr.status,
    dr.org_unit,
    b.is_high_sig,
    b.is_overdue,
    b.is_accepted,
    b.overdue_bucket,
    b.residual_score,
    if(dr.severity_code = 'R4', b.risk_id, null) as r4_risk_id,
    if(b.is_high_sig, b.risk_id, null) as high_sig_risk_id,
    if(b.is_overdue, b.risk_id, null) as overdue_risk_id,
    b.as_at_date
from fct_risk_application as b
left join dim_application as a on a.application_id = b.application_id
left join dim_risk as dr on dr.risk_id = b.risk_id;

-- headline numbers; overdue rate uses non-accepted risks as base
create or replace table rpt_kpis as
select
    reference_date as as_at_date,
    count(*) as active_risks,
    countif(f.is_high_sig) as high_sig_risks,
    countif(dr.severity_code = 'R4') as r4_risks,
    countif(not f.is_accepted) as non_accepted_risks,
    countif(f.is_overdue) as overdue_risks,
    round(safe_divide(countif(f.is_overdue), countif(not f.is_accepted)), 3) as overdue_rate,
    countif(f.is_overdue and f.is_high_sig) as overdue_high_sig_risks,
    countif(f.is_overdue and f.days_past_target > 365) as overdue_over_1y,
    countif(f.is_cif_supporting) as cif_risks,
    countif(f.cif_per_source_flag) as cif_risks_per_source_flag,
    countif(f.is_cif_supporting and f.is_high_sig) as cif_high_sig_risks,
    countif(f.is_accepted) as accepted_risks,
    countif(f.is_accepted and not f.has_acceptance_justification) as accepted_no_justification,
    countif(f.is_acceptance_expired) as acceptance_expired,
    countif(not f.has_owner) as unowned_risks,
    countif(f.is_stale) as stale_risks,
    countif(f.is_complete_not_closed) as complete_not_closed,
    countif(f.overdue_bucket = 'No target date') as no_target_date,
    (select any_value(m) from (select percentile_cont(age_days, 0.5) over () as m from fct_risk)) as median_age_days,
    sum(f.source_row_count) as source_rows,
    sum(f.source_row_count) - count(*) as duplicate_rows_removed
from fct_risk as f
left join dim_risk as dr on dr.risk_id = f.risk_id;

-- one row per DQ rule with rows and risks affected
create or replace table rpt_dq_summary as
select
    q.rule_id,
    q.rule_name,
    q.dq_dimension,
    q.description,
    q.treatment,
    q.treatment_detail,
    coalesce(sum(c.is_failed), 0) as affected_rows,
    count(distinct if(c.is_failed = 1, c.risk_id, null)) as affected_risks,
    q.designed_count,
    round(avg(c.is_failed), 4) as pct_of_rows,
    reference_date as as_at_date
from dim_dq_rule as q
left join fct_dq_check as c on c.rule_id = q.rule_id
group by all;

-- checks: report tables keep the grain of their facts
assert (select count(*) from rpt_risk) = (select count(*) from fct_risk)
    as '4e: rpt_risk row count does not match fct_risk';

assert (select count(*) from rpt_risk_application) = (select count(*) from fct_risk_application)
    as '4e: rpt_risk_application row count does not match fct_risk_application';

assert (select active_risks from rpt_kpis) = (select count(*) from fct_risk)
    as '4e: rpt_kpis.active_risks does not match fct_risk';

assert (select count(*) from rpt_kpis) = 1
    as '4e: rpt_kpis should be exactly one row';

assert (select count(*) from rpt_dq_summary) = (select count(*) from dim_dq_rule)
    as '4e: rpt_dq_summary is not one row per DQ rule';

assert (select sum(affected_rows) from rpt_dq_summary) = (select sum(is_failed) from fct_dq_check)
    as '4e: rpt_dq_summary affected_rows do not add up to fct_dq_check failures';
