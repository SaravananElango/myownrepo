-- 05_observability.sql: run log of row counts, DQ results and freshness, appended per report date.

-- declare before set
declare reference_date date;
declare run_ts timestamp default current_timestamp();

set @@dataset_id = '{{DATASET}}';

set reference_date = (select max(as_at_date) from fct_risk);

-- log tables are created once and appended to
create table if not exists obs_pipeline_run (
    as_at_date date,
    run_ts timestamp,
    layer_order int64,
    layer string,
    table_name string,
    grain string,
    row_count int64,
    expected_row_count int64,
    status string
);

create table if not exists obs_dq_history (
    as_at_date date,
    run_ts timestamp,
    rule_id string,
    rule_name string,
    dq_dimension string,
    checked_rows int64,
    failed_rows int64,
    failed_risks int64,
    fail_rate float64,
    designed_count int64,
    prev_failed_rows int64,
    change_vs_prev int64
);

create table if not exists obs_freshness (
    as_at_date date,
    run_ts timestamp,
    max_last_updated_date date,
    days_since_latest_update int64,
    stale_risk_count int64
);

-- row count per table vs expected count (OK / CHECK / INFO)
delete from obs_pipeline_run where as_at_date = reference_date;

insert into obs_pipeline_run
with
    counts as (
        select 1 as layer_order, 'raw' as layer, 'raw_risk_data' as table_name, 'source row' as grain, (select count(*) from raw_risk_data) as row_count
        union all select 1, 'raw', 'raw_risk_application_map', 'risk-app link', (select count(*) from raw_risk_application_map)
        union all select 1, 'raw', 'raw_application_catalog', 'application', (select count(*) from raw_application_catalog)
        union all select 2, 'staging', 'stg_risk_register_all', 'source row', (select count(*) from stg_risk_register_all)
        union all select 2, 'staging', 'stg_risk_register', 'risk', (select count(*) from stg_risk_register)
        union all select 2, 'staging', 'stg_risk_application_map', 'risk-app link', (select count(*) from stg_risk_application_map)
        union all select 2, 'staging', 'stg_application_catalog', 'application', (select count(*) from stg_application_catalog)
        union all select 3, 'intermediate', 'int_risk', 'risk', (select count(*) from int_risk)
        union all select 3, 'intermediate', 'int_risk_application_rollup', 'risk', (select count(*) from int_risk_application_rollup)
        union all select 3, 'intermediate', 'int_risk_application_link', 'risk-app link', (select count(*) from int_risk_application_link)
        union all select 3, 'intermediate', 'int_dq_issue', 'failed check', (select count(*) from int_dq_issue)
        union all select 3, 'intermediate', 'int_dq_check', 'source row x rule', (select count(*) from int_dq_check)
        union all select 4, 'marts', 'fct_risk', 'risk', (select count(*) from fct_risk)
        union all select 4, 'marts', 'fct_risk_application', 'risk-app link', (select count(*) from fct_risk_application)
        union all select 4, 'marts', 'fct_dq_check', 'source row x rule', (select count(*) from fct_dq_check)
        union all select 4, 'marts', 'dim_risk', 'risk', (select count(*) from dim_risk)
        union all select 4, 'marts', 'dim_application', 'application', (select count(*) from dim_application)
        union all select 4, 'marts', 'dim_dq_rule', 'DQ rule', (select count(*) from dim_dq_rule)
        union all select 5, 'reporting', 'rpt_risk', 'risk', (select count(*) from rpt_risk)
        union all select 5, 'reporting', 'rpt_risk_application', 'risk-app link', (select count(*) from rpt_risk_application)
        union all select 5, 'reporting', 'rpt_kpis', 'snapshot', (select count(*) from rpt_kpis)
        union all select 5, 'reporting', 'rpt_dq_summary', 'DQ rule', (select count(*) from rpt_dq_summary)
    ),
    expected as (
        select 'stg_risk_register_all' as table_name, (select count(*) from raw_risk_data) as expected_row_count
        union all select 'stg_risk_register', (select count(distinct trim(Risk_ID)) from raw_risk_data)
        union all select t, (select count(*) from stg_risk_register)
            from unnest(['int_risk', 'fct_risk', 'dim_risk', 'rpt_risk']) as t
        union all select t, (select count(*) from stg_risk_application_map)
            from unnest(['int_risk_application_link', 'fct_risk_application', 'rpt_risk_application']) as t
        union all select 'fct_dq_check',
            (select count(*) from stg_risk_register_all) * (select count(*) from ref_dq_rules)
        union all select 'rpt_dq_summary', (select count(*) from dim_dq_rule)
    )
select
    reference_date as as_at_date,
    run_ts,
    c.layer_order,
    c.layer,
    c.table_name,
    c.grain,
    c.row_count,
    e.expected_row_count,
    case
        when e.expected_row_count is null then 'INFO'
        when c.row_count = e.expected_row_count then 'OK'
        else 'CHECK'
    end as status
from counts as c
left join expected as e using (table_name);

-- failures per DQ rule and change since the previous load
delete from obs_dq_history where as_at_date = reference_date;

insert into obs_dq_history
with
    cur as (
        select
            q.rule_id,
            q.rule_name,
            q.dq_dimension,
            q.designed_count,
            count(*) as checked_rows,
            sum(c.is_failed) as failed_rows,
            count(distinct if(c.is_failed = 1, c.risk_id, null)) as failed_risks,
            round(avg(c.is_failed), 4) as fail_rate
        from fct_dq_check as c
        inner join dim_dq_rule as q using (rule_id)
        group by q.rule_id, q.rule_name, q.dq_dimension, q.designed_count
    ),
    prev as (
        select rule_id, failed_rows as prev_failed_rows
        from obs_dq_history
        where as_at_date < reference_date
        qualify row_number() over (partition by rule_id order by as_at_date desc) = 1
    )
select
    reference_date as as_at_date,
    run_ts,
    cur.rule_id,
    cur.rule_name,
    cur.dq_dimension,
    cur.checked_rows,
    cur.failed_rows,
    cur.failed_risks,
    cur.fail_rate,
    cur.designed_count,
    prev.prev_failed_rows,
    cur.failed_rows - prev.prev_failed_rows as change_vs_prev
from cur
left join prev using (rule_id);

-- how recent the data is and how many risks are stale
delete from obs_freshness where as_at_date = reference_date;

insert into obs_freshness
select
    reference_date as as_at_date,
    run_ts,
    max(last_updated_date) as max_last_updated_date,
    date_diff(reference_date, max(last_updated_date), day) as days_since_latest_update,
    countif(is_stale) as stale_risk_count
from fct_risk;
