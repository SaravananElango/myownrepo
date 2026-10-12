-- 01_staging.sql: type and clean the raw tables and remove duplicate risks. Raw tables are not changed.

set @@dataset_id = '{{DATASET}}';

-- raw is all STRING, these helpers cast safely (bad values become NULL)
create temp function to_date(x string) as (safe.parse_date('%Y-%m-%d', substr(trim(x), 1, 10)));
create temp function to_int(x string) as (safe_cast(nullif(trim(x), '') as int64));
create temp function clean_str(x string) as (nullif(trim(x), ''));

-- every source row typed (2,000), duplicates kept for DQ counts; row key = row hash + ordinal
create or replace table stg_risk_register_all as
with keyed as (
    select *, farm_fingerprint(to_json_string(src)) as row_hash
    from raw_risk_data as src
)
select
    concat(cast(row_hash as string), '-', cast(row_number() over (partition by row_hash order by row_hash) as string)) as source_row_id,

    trim(Risk_ID) as risk_id,
    trim(Risk_Title) as risk_title,
    trim(Risk_Category) as risk_category,
    trim(Control_Reference) as control_reference,

    Status as status_raw,
    case lower(trim(Status))
        when 'open' then 'Open'
        when 'under review' then 'Under Review'
        when 'in remediation' then 'In Remediation'
        when 'pending acceptance' then 'Pending Acceptance'
        when 'risk accepted' then 'Risk Accepted'
    end as status,

    trim(Treatment_Strategy) as treatment_strategy,
    clean_str(Risk_Acceptance_Justification) as risk_acceptance_justification,

    to_int(Inherent_Impact) as inherent_impact,
    to_int(Inherent_Likelihood) as inherent_likelihood,
    to_int(Residual_Impact) as residual_impact,
    to_int(Residual_Likelihood) as residual_likelihood,

    trim(Risk_Severity) as severity_code,
    Risk_Severity_Label as severity_label_raw,

    to_date(Created_Date) as created_date,
    to_date(Last_Updated_Date) as last_updated_date,
    to_date(Target_Mitigation_Date) as target_mitigation_date,
    clean_str(Overdue_Flag) as overdue_flag_source,
    to_int(Days_Overdue) as days_overdue_source,

    clean_str(Risk_Owner_ID) as risk_owner_id,
    trim(Risk_Owner_Unit) as risk_owner_unit,
    clean_str(Risk_Reviewer_ID) as risk_reviewer_id,
    trim(Owning_Legal_Entity) as owning_legal_entity,

    trim(Primary_Application_ID) as primary_application_id,
    trim(Primary_Application_Name) as primary_application_name,
    Related_Application_IDs as related_application_ids_raw,
    clean_str(CIF_Supporting) as cif_supporting_source,

    to_int(Progress_Percent) as progress_percent
from keyed;

-- one row per risk, keep the latest update (2,000 -> 1,992)
create or replace table stg_risk_register as
select * except (rn)
from (
    select
        *,
        count(*) over (partition by risk_id) as source_row_count,
        row_number() over (partition by risk_id order by last_updated_date desc, source_row_id) as rn
    from stg_risk_register_all
)
where rn = 1;

-- link table and app catalog, typed and trimmed
create or replace table stg_risk_application_map as
select
    trim(Risk_ID) as risk_id,
    trim(Application_ID) as application_id,
    trim(Relationship_Type) as relationship_type,
    to_int(Sequence) as sequence
from raw_risk_application_map;

create or replace table stg_application_catalog as
select
    trim(Application_ID) as application_id,
    trim(Application_Name) as application_name,
    trim(Application_Type) as application_type,
    trim(Application_Criticality) as application_criticality,
    trim(CIF_Supporting) = 'Yes' as is_cif_supporting,
    trim(Owning_Legal_Entity) as owning_legal_entity,
    trim(Hosting_Model) as hosting_model,
    trim(Primary_Region) as primary_region,
    trim(Lifecycle_Status) as lifecycle_status
from raw_application_catalog;

-- checks: risk_id present and unique, row counts match raw
assert (select countif(risk_id is null) from stg_risk_register) = 0
    as '1d: stg_risk_register has a null risk_id';

assert (select count(*) - count(distinct risk_id) from stg_risk_register) = 0
    as '1d: stg_risk_register has a duplicate risk_id, dedup did not work';

assert (select count(*) from stg_risk_register_all) = (select count(*) from raw_risk_data)
    as '1e: stg_risk_register_all row count does not match raw_risk_data';

assert (select count(*) from stg_risk_register) = (select count(distinct trim(Risk_ID)) from raw_risk_data)
    as '1e: stg_risk_register count does not match distinct Risk_IDs in raw_risk_data';

assert (select count(*) from stg_risk_application_map) = (select count(*) from raw_risk_application_map)
    as '1e: stg_risk_application_map row count does not match raw_risk_application_map';

assert (select count(*) from stg_application_catalog) = (select count(*) from raw_application_catalog)
    as '1e: stg_application_catalog row count does not match raw_application_catalog';
