-- 02_intermediate.sql: business rules and data quality checks, defined once and reused by marts and reports.

-- declare before set, filled from ref_params below
declare reference_date date;
declare stale_after_days int64;

set @@dataset_id = '{{DATASET}}';

set reference_date = (select reference_date from ref_params);
set stale_after_days = (select stale_after_days from ref_params);

-- app attributes per risk; CIF = any linked app is CIF in the catalog
create or replace table int_risk_application_rollup as
select
    m.risk_id,
    count(distinct m.application_id) as application_count,
    logical_or(a.is_cif_supporting) as is_cif_supporting,
    case
        when logical_or(a.application_criticality = 'Critical') then 'Critical'
        when logical_or(a.application_criticality = 'Important') then 'Important'
        else 'Standard'
    end as highest_application_criticality,
    logical_or(a.lifecycle_status != 'Active') as touches_non_active_application,
    string_agg(distinct m.application_id, ';' order by m.application_id) as application_ids,
    count(distinct a.owning_legal_entity) as affected_legal_entity_count
from stg_risk_application_map as m
inner join stg_application_catalog as a using (application_id)
group by m.risk_id;

-- one row per source row and DQ rule it fails (runs on all 2,000 rows)
create or replace table int_dq_issue as
with
    r as (select * from stg_risk_register_all),
    apps as (select * from int_risk_application_rollup),
    dup_ids as (select risk_id from r group by risk_id having count(*) > 1),

    checks as (
        select source_row_id, risk_id, 'DQ01' as rule_id
        from r where risk_id in (select risk_id from dup_ids)
        union all
        select source_row_id, risk_id, 'DQ02' from r where risk_owner_id is null
        union all
        select source_row_id, risk_id, 'DQ03' from r where cif_supporting_source is null
        union all
        select r.source_row_id, r.risk_id, 'DQ04'
        from r inner join apps using (risk_id)
        where r.cif_supporting_source is not null
            and (r.cif_supporting_source = 'Yes') != apps.is_cif_supporting
        union all
        select source_row_id, risk_id, 'DQ05' from r where status is null or status_raw != status
        union all
        select source_row_id, risk_id, 'DQ06'
        from r where not regexp_contains(related_application_ids_raw, r'^APP-\d{4}(;APP-\d{4})*$')
        union all
        select source_row_id, risk_id, 'DQ07'
        from r where date_diff(reference_date, last_updated_date, day) > stale_after_days
        union all
        select source_row_id, risk_id, 'DQ08'
        from r where target_mitigation_date is null and treatment_strategy != 'Accept'
        union all
        select source_row_id, risk_id, 'DQ09'
        from r where treatment_strategy = 'Accept' and risk_acceptance_justification is null
        union all
        select r.source_row_id, r.risk_id, 'DQ10'
        from r inner join ref_severity as s using (severity_code)
        where r.severity_label_raw != s.severity_label
        union all
        select source_row_id, risk_id, 'DQ11' from r where last_updated_date < created_date
        union all
        select source_row_id, risk_id, 'DQ12' from r where target_mitigation_date < created_date
        union all
        select source_row_id, risk_id, 'DQ13'
        from r
        where (status in ('Pending Acceptance', 'Risk Accepted') and treatment_strategy != 'Accept')
            or (status != 'Risk Accepted' and treatment_strategy = 'Accept')
    )

select c.source_row_id, c.risk_id, c.rule_id, q.rule_name, q.dq_dimension, q.treatment
from checks as c
inner join ref_dq_rules as q using (rule_id);

-- one row per risk with all measures, flags and buckets
create or replace table int_risk as
with
    r as (select * from stg_risk_register),
    apps as (select * from int_risk_application_rollup),
    dq as (
        select risk_id, count(distinct rule_id) as dq_issue_count
        from int_dq_issue
        where rule_id != 'DQ01'
        group by risk_id
    ),

    base as (
        select
            reference_date as as_at_date,
            r.risk_id,
            r.risk_title,
            r.risk_category,
            r.control_reference,
            r.status,
            r.treatment_strategy,
            r.severity_code,
            sev.severity_label,
            sev.severity_rank,
            st.status_group,
            st.status_sort,
            coalesce(r.risk_owner_id, 'Unassigned') as risk_owner_id,
            r.risk_owner_unit as org_unit,
            r.risk_reviewer_id,
            r.owning_legal_entity,
            r.primary_application_id,
            r.primary_application_name,

            r.created_date,
            r.last_updated_date,
            r.target_mitigation_date,

            r.inherent_impact,
            r.inherent_likelihood,
            r.inherent_impact * r.inherent_likelihood as inherent_score,
            r.residual_impact,
            r.residual_likelihood,
            r.residual_impact * r.residual_likelihood as residual_score,
            r.progress_percent,

            apps.application_count,
            apps.highest_application_criticality,
            apps.is_cif_supporting,
            r.cif_supporting_source,
            coalesce(r.cif_supporting_source = 'Yes', false) as cif_per_source_flag,
            apps.touches_non_active_application,
            apps.affected_legal_entity_count,

            r.treatment_strategy = 'Accept' as is_accepted,
            r.risk_acceptance_justification is not null as has_acceptance_justification,
            r.risk_owner_id is not null as has_owner,
            r.source_row_count,

            date_diff(reference_date, r.created_date, day) as age_days,
            date_diff(reference_date, r.last_updated_date, day) as days_since_update,
            case
                when r.target_mitigation_date is not null
                then greatest(date_diff(reference_date, r.target_mitigation_date, day), 0)
            end as days_past_target,
            r.overdue_flag_source,
            r.days_overdue_source,
            coalesce(dq.dq_issue_count, 0) as dq_issue_count
        from r
        left join apps using (risk_id)
        left join dq using (risk_id)
        left join ref_severity as sev on sev.severity_code = r.severity_code
        left join ref_status as st on st.status = r.status
    ),

    -- overdue = not accepted and past target; no target date counts as not overdue
    flagged as (
        select
            *,
            severity_code in ('R3', 'R4') as is_high_sig,
            inherent_score - residual_score as score_reduction,
            coalesce(not is_accepted and days_past_target > 0, false) as is_overdue,
            coalesce(is_accepted and days_past_target > 0, false) as is_acceptance_expired,
            days_since_update > stale_after_days as is_stale,
            not is_accepted and progress_percent = 100 as is_complete_not_closed,
            case
                when is_accepted then 'Accepted (n/a)'
                when target_mitigation_date is null then 'No target date'
                when days_past_target = 0 then 'Not yet due'
                when days_past_target <= 90 then '1-90 days'
                when days_past_target <= 180 then '91-180 days'
                when days_past_target <= 365 then '181-365 days'
                else '> 1 year'
            end as overdue_bucket,
            case
                when age_days <= 365 then '< 1 year'
                when age_days <= 730 then '1-2 years'
                when age_days <= 1095 then '2-3 years'
                else '> 3 years'
            end as age_bucket
        from base
    )

select
    *,
    case overdue_bucket
        when 'Not yet due' then 1 when '1-90 days' then 2 when '91-180 days' then 3
        when '181-365 days' then 4 when '> 1 year' then 5 when 'No target date' then 6
        when 'Accepted (n/a)' then 7
    end as overdue_bucket_sort,
    case age_bucket
        when '< 1 year' then 1 when '1-2 years' then 2 when '2-3 years' then 3 when '> 3 years' then 4
    end as age_bucket_sort
from flagged;

-- risk-app links; allocation_weight = 1 / apps per risk
create or replace table int_risk_application_link as
select
    risk_id,
    application_id,
    relationship_type,
    sequence,
    1.0 / count(*) over (partition by risk_id) as allocation_weight
from stg_risk_application_map;

-- every source row x every rule, pass or fail (26,000)
create or replace table int_dq_check as
select
    s.source_row_id,
    s.risk_id,
    q.rule_id,
    if(i.source_row_id is null, 0, 1) as is_failed
from stg_risk_register_all as s
cross join ref_dq_rules as q
left join int_dq_issue as i
    on i.source_row_id = s.source_row_id
    and i.rule_id = q.rule_id;

-- checks: my overdue logic matches the source, no duplicate risks, weights add to 1
assert (select countif(overdue_flag_source is not null
                       and (overdue_flag_source = 'Yes') != (is_overdue or is_acceptance_expired))
        from int_risk) = 0
    as '2f: is_overdue does not match source Overdue_Flag (int_risk)';

assert (select countif(days_overdue_source is not null
                       and days_past_target is not null
                       and days_overdue_source != days_past_target)
        from int_risk) = 0
    as '2g: days_past_target does not match source Days_Overdue (int_risk)';

assert (select count(*) - count(distinct risk_id) from int_risk) = 0
    as '2h: duplicate risk_id in int_risk, a join repeated rows';

assert (select count(*) from int_risk_application_link) = (select count(*) from stg_risk_application_map)
    as '2i: int_risk_application_link row count does not match stg_risk_application_map';

assert (select countif(abs(w - 1) > 1e-9)
        from (select sum(allocation_weight) as w from int_risk_application_link group by risk_id)) = 0
    as '2i: allocation_weight does not add up to 1 for some risks';

assert (select count(*) from int_dq_check)
       = (select count(*) from stg_risk_register_all) * (select count(*) from ref_dq_rules)
    as '2j: int_dq_check is not source rows x rules';

assert (select sum(is_failed) from int_dq_check) = (select count(*) from int_dq_issue)
    as '2j: failures in int_dq_check do not match int_dq_issue';
