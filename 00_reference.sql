-- 00_reference.sql: lookup tables and report settings that do not come from the source file.

set @@dataset_id = '{{DATASET}}';

-- report date (31 Aug 2026) and stale limit, used instead of current_date
create or replace table ref_params (
    reference_date date,
    stale_after_days int64
);
insert into ref_params values (date '2026-08-31', 365);

-- code is trusted, label is rebuilt from it
create or replace table ref_severity (
    severity_code string, severity_label string, severity_name string, severity_rank int64
);
insert into ref_severity values
    ('R1', 'R1 - Low', 'Low', 1),
    ('R2', 'R2 - Moderate', 'Moderate', 2),
    ('R3', 'R3 - Significant', 'Significant', 3),
    ('R4', 'R4 - High', 'High', 4);

-- 5 statuses in lifecycle order, with groups for charts
create or replace table ref_status (
    status string, status_group string, status_sort int64, is_accepted bool
);
insert into ref_status values
    ('Open', 'Not yet treated', 1, false),
    ('Under Review', 'Not yet treated', 2, false),
    ('In Remediation', 'Treatment in progress', 3, false),
    ('Pending Acceptance', 'Acceptance in progress', 4, false),
    ('Risk Accepted', 'Accepted', 5, true);

-- one row per data quality rule and how it is treated
create or replace table ref_dq_rules (
    rule_id string,
    rule_name string,
    dq_dimension string,
    description string,
    treatment string,
    treatment_detail string,
    designed_count int64
);

insert into ref_dq_rules values
    ('DQ01', 'duplicate_risk_id',        'Uniqueness',   'Risk_ID repeated in source',                              'Exclude', 'Keep latest Last_Updated_Date, drop the rest', 8),
    ('DQ02', 'missing_owner',            'Completeness', 'Risk_Owner_ID is null',                                   'Flag',    'Show as Unassigned', 18),
    ('DQ03', 'missing_cif_flag',         'Completeness', 'CIF_Supporting is null',                                  'Derive',  'Take from application catalog', 34),
    ('DQ04', 'cif_flag_mismatch',        'Consistency',  'CIF_Supporting differs from application catalog',         'Derive',  'Use catalog value', 12),
    ('DQ05', 'status_format',            'Validity',     'Status has wrong case or extra spaces',                   'Correct', 'Map to standard status', 28),
    ('DQ06', 'app_list_delimiter',       'Validity',     'Related_Application_IDs not separated by ;',              'Bypass',  'Use Risk_Application_Map instead', 31),
    ('DQ07', 'stale_update',             'Timeliness',   'Last_Updated_Date older than 365 days at reference date', 'Flag',    'Keep, report as stale', 45),
    ('DQ08', 'missing_target_date',      'Completeness', 'Target_Mitigation_Date is null',                          'Flag',    'Report as no target date', 11),
    ('DQ09', 'accepted_no_justification','Completeness', 'Treatment_Strategy = Accept and no justification',        'Flag',    'Keep, report for follow-up', 22),
    ('DQ10', 'severity_label',           'Validity',     'Risk_Severity_Label does not match Risk_Severity',        'Correct', 'Rebuild label from code', 14),
    ('DQ11', 'updated_before_created',   'Validity',     'Last_Updated_Date before Created_Date',                   'Flag',    'Keep dates as is', null),
    ('DQ12', 'target_before_created',    'Validity',     'Target_Mitigation_Date before Created_Date',              'Flag',    'Keep dates as is', null),
    ('DQ13', 'status_strategy_mismatch', 'Consistency',  'Accept strategy does not match status, or the reverse',   'Flag',    'Keep both as is', null);
