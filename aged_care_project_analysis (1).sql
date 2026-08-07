/*
===============================================================================
AGED CARE QUALITY & REGULATORY PERFORMANCE ANALYTICS
PostgreSQL analysis and data-quality queries
===============================================================================

Project type : Independent portfolio project using publicly available data
Database     : PostgreSQL
Schema       : analytics
Prepared by  : Sekai Kanyoke
Year         : 2026

Purpose
-------
This script contains the SQL analysis and validation workflow prepared for
three aged-care reporting datasets:

1. Complaints
2. Serious Incident Response Scheme (SIRS) incidents
3. Worker-regulation activity

Prerequisites
-------------
The following cleaned tables must already exist:

    analytics.complaints_clean
    analytics.sirs_incidents_clean
    analytics.worker_regulation_clean

Important methodology note
--------------------------
Public reporting definitions and classifications changed around the
1 November 2025 aged-care transition. Legacy and post-change figures should
not be treated as directly comparable unless the definitions, coverage and
reporting periods have been checked. The queries below keep the datasets
separate and do not combine their volumes into a single performance measure.

This is a read-only analysis script. It does not create, update or delete data.
===============================================================================
*/


-- =============================================================================
-- 1. STRUCTURE AND DATA-QUALITY CHECKS
-- =============================================================================

-- 1.1 Confirm the columns and data types available in the cleaned tables.
SELECT
    table_name,
    ordinal_position,
    column_name,
    data_type
FROM information_schema.columns
WHERE table_schema = 'analytics'
  AND table_name IN (
      'complaints_clean',
      'sirs_incidents_clean',
      'worker_regulation_clean'
  )
ORDER BY table_name, ordinal_position;


-- 1.2 Count records in each cleaned dataset.
SELECT 'Complaints' AS dataset, COUNT(*) AS total_records
FROM analytics.complaints_clean

UNION ALL

SELECT 'SIRS' AS dataset, COUNT(*) AS total_records
FROM analytics.sirs_incidents_clean

UNION ALL

SELECT 'Worker Regulation' AS dataset, COUNT(*) AS total_records
FROM analytics.worker_regulation_clean
ORDER BY dataset;


-- 1.3 Check for missing period identifiers or dates.
SELECT
    'Complaints' AS dataset,
    COUNT(*) FILTER (WHERE period_key IS NULL) AS missing_period_key,
    COUNT(*) FILTER (WHERE period_start IS NULL) AS missing_period_start
FROM analytics.complaints_clean

UNION ALL

SELECT
    'SIRS' AS dataset,
    COUNT(*) FILTER (WHERE period_key IS NULL) AS missing_period_key,
    COUNT(*) FILTER (WHERE period_start IS NULL) AS missing_period_start
FROM analytics.sirs_incidents_clean

UNION ALL

SELECT
    'Worker Regulation' AS dataset,
    COUNT(*) FILTER (WHERE period_key IS NULL) AS missing_period_key,
    COUNT(*) FILTER (WHERE period_start IS NULL) AS missing_period_start
FROM analytics.worker_regulation_clean;


-- 1.4 Check complaints for possible duplicate analytical rows.
-- Review returned records before deciding whether they are true duplicates.
SELECT
    period_key,
    measure_name,
    breakdown_value,
    count_value,
    COUNT(*) AS row_count
FROM analytics.complaints_clean
GROUP BY period_key, measure_name, breakdown_value, count_value
HAVING COUNT(*) > 1
ORDER BY row_count DESC, period_key, measure_name;


-- 1.5 Check SIRS for possible duplicate analytical rows.
SELECT
    period_key,
    incident_type,
    service_setting,
    total_count,
    COUNT(*) AS row_count
FROM analytics.sirs_incidents_clean
GROUP BY period_key, incident_type, service_setting, total_count
HAVING COUNT(*) > 1
ORDER BY row_count DESC, period_key, incident_type;


-- 1.6 Check worker regulation for possible duplicate analytical rows.
SELECT
    period_key,
    activity_category,
    case_count,
    COUNT(*) AS row_count
FROM analytics.worker_regulation_clean
GROUP BY period_key, activity_category, case_count
HAVING COUNT(*) > 1
ORDER BY row_count DESC, period_key, activity_category;


-- =============================================================================
-- 2. COMPLAINTS ANALYSIS
-- =============================================================================

-- 2.1 Inspect the available complaint measure groups.
SELECT DISTINCT measure_group
FROM analytics.complaints_clean
WHERE measure_group IS NOT NULL
ORDER BY measure_group;


-- 2.2 Inspect the available complaint measure names.
-- Run this before the trend query to confirm the exact total-volume label.
SELECT DISTINCT measure_name
FROM analytics.complaints_clean
WHERE measure_name IS NOT NULL
ORDER BY measure_name;


-- 2.3 Complaint volume over time.
-- Filtering to "Complaints received" prevents complaint totals and issue
-- breakdowns from being added together. Confirm this label in query 2.2.
SELECT
    period_key,
    reporting_period,
    MIN(period_start) AS period_start,
    SUM(count_value) AS complaints_received
FROM analytics.complaints_clean
WHERE LOWER(measure_name) = 'complaints received'
GROUP BY period_key, reporting_period
ORDER BY period_start;


-- 2.4 Complaints by issue category.
-- The issue labels are stored in breakdown_value rather than issue_category.
SELECT
    breakdown_value AS issue_category,
    SUM(count_value) AS complaints
FROM analytics.complaints_clean
WHERE LOWER(measure_name) = 'complaint issue'
  AND breakdown_value IS NOT NULL
GROUP BY breakdown_value
ORDER BY complaints DESC, issue_category;


-- 2.5 Percentage change in complaints between reporting periods.
WITH complaint_totals AS (
    SELECT
        period_key,
        MIN(period_start) AS period_start,
        SUM(count_value) AS complaints_received
    FROM analytics.complaints_clean
    WHERE LOWER(measure_name) = 'complaints received'
    GROUP BY period_key
),
complaint_change AS (
    SELECT
        period_key,
        period_start,
        complaints_received,
        LAG(complaints_received) OVER (ORDER BY period_start) AS prior_period
    FROM complaint_totals
)
SELECT
    period_key,
    complaints_received,
    prior_period,
    ROUND(
        100.0 * (complaints_received - prior_period)
        / NULLIF(prior_period, 0),
        2
    ) AS percentage_change
FROM complaint_change
ORDER BY period_start;


-- 2.6 Reporting period with the highest complaint volume.
SELECT
    reporting_period,
    SUM(count_value) AS complaints_received
FROM analytics.complaints_clean
WHERE LOWER(measure_name) = 'complaints received'
GROUP BY reporting_period
ORDER BY complaints_received DESC
LIMIT 1;


-- =============================================================================
-- 3. SIRS ANALYSIS
-- =============================================================================

-- 3.1 SIRS incidents over time.
SELECT
    period_key,
    reporting_period,
    MIN(period_start) AS period_start,
    SUM(total_count) AS sirs_incidents
FROM analytics.sirs_incidents_clean
GROUP BY period_key, reporting_period
ORDER BY period_start;


-- 3.2 SIRS incidents by incident type.
SELECT
    incident_type,
    SUM(total_count) AS sirs_incidents
FROM analytics.sirs_incidents_clean
WHERE incident_type IS NOT NULL
GROUP BY incident_type
ORDER BY sirs_incidents DESC, incident_type;


-- 3.3 SIRS incidents by service setting.
SELECT
    service_setting,
    SUM(total_count) AS sirs_incidents
FROM analytics.sirs_incidents_clean
WHERE service_setting IS NOT NULL
GROUP BY service_setting
ORDER BY sirs_incidents DESC, service_setting;


-- 3.4 Reporting period with the highest SIRS volume.
SELECT
    reporting_period,
    SUM(total_count) AS sirs_incidents
FROM analytics.sirs_incidents_clean
GROUP BY reporting_period
ORDER BY sirs_incidents DESC
LIMIT 1;


-- =============================================================================
-- 4. WORKER-REGULATION ANALYSIS
-- =============================================================================

-- 4.1 Worker-regulation activity over time.
SELECT
    period_key,
    reporting_period,
    MIN(period_start) AS period_start,
    SUM(case_count) AS regulatory_actions
FROM analytics.worker_regulation_clean
GROUP BY period_key, reporting_period
ORDER BY period_start;


-- 4.2 Worker-regulation activity by category.
SELECT
    activity_category,
    SUM(case_count) AS regulatory_actions
FROM analytics.worker_regulation_clean
WHERE activity_category IS NOT NULL
GROUP BY activity_category
ORDER BY regulatory_actions DESC, activity_category;


-- 4.3 Reporting period with the highest worker-regulation activity.
SELECT
    reporting_period,
    SUM(case_count) AS regulatory_actions
FROM analytics.worker_regulation_clean
GROUP BY reporting_period
ORDER BY regulatory_actions DESC
LIMIT 1;


-- =============================================================================
-- 5. SIDE-BY-SIDE REPORTING VIEW
-- =============================================================================

-- This query aligns the three datasets by period for review and dashboarding.
-- The values represent different activities and should not be added together.
WITH reporting_periods AS (
    SELECT period_key, MIN(period_start) AS period_start
    FROM (
        SELECT period_key, period_start
        FROM analytics.complaints_clean

        UNION ALL

        SELECT period_key, period_start
        FROM analytics.sirs_incidents_clean

        UNION ALL

        SELECT period_key, period_start
        FROM analytics.worker_regulation_clean
    ) AS all_periods
    GROUP BY period_key
),
complaints AS (
    SELECT
        period_key,
        SUM(count_value) AS complaints_received
    FROM analytics.complaints_clean
    WHERE LOWER(measure_name) = 'complaints received'
    GROUP BY period_key
),
sirs AS (
    SELECT
        period_key,
        SUM(total_count) AS sirs_incidents
    FROM analytics.sirs_incidents_clean
    GROUP BY period_key
),
worker AS (
    SELECT
        period_key,
        SUM(case_count) AS worker_regulation_actions
    FROM analytics.worker_regulation_clean
    GROUP BY period_key
)
SELECT
    rp.period_key,
    rp.period_start,
    COALESCE(c.complaints_received, 0) AS complaints_received,
    COALESCE(s.sirs_incidents, 0) AS sirs_incidents,
    COALESCE(w.worker_regulation_actions, 0) AS worker_regulation_actions
FROM reporting_periods AS rp
LEFT JOIN complaints AS c
    ON rp.period_key = c.period_key
LEFT JOIN sirs AS s
    ON rp.period_key = s.period_key
LEFT JOIN worker AS w
    ON rp.period_key = w.period_key
ORDER BY rp.period_start;


-- =============================================================================
-- END OF SCRIPT
-- =============================================================================
