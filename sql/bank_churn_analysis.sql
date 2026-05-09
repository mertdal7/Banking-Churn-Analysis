-- =============================================================================
-- PROJECT:     Bank Churn Analysis
-- AUTHOR:      Mert Dal
-- DESCRIPTION: End-to-end SQL layer for bank customer churn analysis.
--              Covers data quality checks, customer-level enrichment,
--              segment-level aggregation, and retention priority scoring.
--
-- EXECUTION ORDER:
--   1. Sanity checks        — validate raw data before any transformation
--   2. vw_churn_segmented   — customer-level enriched view
--   3. vw_segment_stats     — 15-row segment aggregation
--   4. vw_segment_priority  — quadrant scoring & retention priority ranking
--
-- SOURCE TABLE:
--   churn-project-492519.churn_dataset.Churn_Modelling
--
-- TOOL:        Google BigQuery
-- =============================================================================


-- =============================================================================
-- SECTION 1: SANITY CHECKS
-- Validate raw data quality before building any views.
-- Run these queries manually and review results before proceeding.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1.1 Row count & high-level churn overview
-- Expected: 10,000 rows, ~20% churn rate, no nulls in key columns
-- -----------------------------------------------------------------------------
SELECT
  COUNT(*)                                              AS total_rows,
  COUNT(DISTINCT CustomerId)                            AS unique_customers,
  COUNTIF(Exited = 1)                                   AS churned,
  COUNTIF(Exited = 0)                                   AS retained,
  ROUND(COUNTIF(Exited = 1) / COUNT(*) * 100, 2)       AS churn_rate_pct,
  COUNTIF(Balance = 0)                                  AS zero_balance_customers,
  COUNTIF(
    CreditScore IS NULL
    OR Age IS NULL
    OR Balance IS NULL
  )                                                     AS rows_with_nulls
FROM `churn-project-492519.churn_dataset.Churn_Modelling`;


-- -----------------------------------------------------------------------------
-- 1.2 Check for duplicate CustomerIds
-- Expected: 0 duplicates — each customer should appear exactly once
-- -----------------------------------------------------------------------------
SELECT
  CustomerId,
  COUNT(*)                                              AS occurrences
FROM `churn-project-492519.churn_dataset.Churn_Modelling`
GROUP BY CustomerId
HAVING COUNT(*) > 1
ORDER BY occurrences DESC;


-- -----------------------------------------------------------------------------
-- 1.3 Geography distribution
-- Expected: three countries — France, Germany, Spain
-- Check for unexpected values or typos in geography field
-- -----------------------------------------------------------------------------
SELECT
  Geography,
  COUNT(*)                                              AS total_customers,
  COUNTIF(Exited = 1)                                   AS churned,
  ROUND(COUNTIF(Exited = 1) / COUNT(*) * 100, 2)       AS churn_rate_pct
FROM `churn-project-492519.churn_dataset.Churn_Modelling`
GROUP BY Geography
ORDER BY churn_rate_pct DESC;


-- -----------------------------------------------------------------------------
-- 1.4 Age distribution check
-- Expected: reasonable range (18–92), no extreme outliers
-- -----------------------------------------------------------------------------
SELECT
  MIN(Age)                                              AS min_age,
  MAX(Age)                                              AS max_age,
  ROUND(AVG(Age), 1)                                    AS avg_age,
  COUNTIF(Age < 18)                                     AS under_18,
  COUNTIF(Age > 90)                                     AS over_90
FROM `churn-project-492519.churn_dataset.Churn_Modelling`;


-- -----------------------------------------------------------------------------
-- 1.5 Balance distribution check
-- Large zero-balance cluster is expected in retail banking data.
-- Zero-balance customers will be handled as a separate segment.
-- -----------------------------------------------------------------------------
SELECT
  COUNTIF(Balance = 0)                                  AS zero_balance,
  COUNTIF(Balance > 0 AND Balance < 50000)              AS low_balance,
  COUNTIF(Balance >= 50000 AND Balance < 100000)        AS mid_balance,
  COUNTIF(Balance >= 100000 AND Balance < 150000)       AS high_balance,
  COUNTIF(Balance >= 150000)                            AS very_high_balance,
  ROUND(MIN(Balance), 0)                                AS min_balance,
  ROUND(MAX(Balance), 0)                                AS max_balance,
  ROUND(AVG(Balance), 0)                                AS avg_balance
FROM `churn-project-492519.churn_dataset.Churn_Modelling`;


-- -----------------------------------------------------------------------------
-- 1.6 CreditScore range check
-- Expected: 300–850 (standard FICO range)
-- -----------------------------------------------------------------------------
SELECT
  MIN(CreditScore)                                      AS min_score,
  MAX(CreditScore)                                      AS max_score,
  ROUND(AVG(CreditScore), 0)                            AS avg_score,
  COUNTIF(CreditScore < 300)                            AS below_range,
  COUNTIF(CreditScore > 850)                            AS above_range
FROM `churn-project-492519.churn_dataset.Churn_Modelling`;


-- -----------------------------------------------------------------------------
-- 1.7 Binary flag validation
-- HasCrCard, IsActiveMember, Exited should only contain 0 or 1
-- -----------------------------------------------------------------------------
SELECT
  COUNTIF(HasCrCard NOT IN (0, 1))                      AS invalid_has_cr_card,
  COUNTIF(IsActiveMember NOT IN (0, 1))                 AS invalid_is_active_member,
  COUNTIF(Exited NOT IN (0, 1))                         AS invalid_exited
FROM `churn-project-492519.churn_dataset.Churn_Modelling`;


-- -----------------------------------------------------------------------------
-- 1.8 NumOfProducts distribution
-- Flag: customers with 3-4 products have near-total churn (known finding)
-- -----------------------------------------------------------------------------
SELECT
  NumOfProducts,
  COUNT(*)                                              AS total_customers,
  COUNTIF(Exited = 1)                                   AS churned,
  ROUND(COUNTIF(Exited = 1) / COUNT(*) * 100, 2)       AS churn_rate_pct
FROM `churn-project-492519.churn_dataset.Churn_Modelling`
GROUP BY NumOfProducts
ORDER BY NumOfProducts;


-- =============================================================================
-- SECTION 2: vw_churn_segmented
-- Customer-level enriched view.
-- Adds derived dimensions for age group, credit tier, balance segment,
-- tenure segment, and readable labels for binary flags.
-- This is the single source of truth for all downstream views.
-- =============================================================================

CREATE OR REPLACE VIEW `churn-project-492519.churn_dataset.vw_churn_segmented` AS

SELECT
  -- -------------------------------------------------------------------------
  -- Raw identifiers & demographic fields
  -- -------------------------------------------------------------------------
  CustomerId,
  Surname,
  Geography,
  Gender,
  Age,
  CreditScore,
  Tenure,
  Balance,
  NumOfProducts,
  HasCrCard,
  IsActiveMember,
  EstimatedSalary,
  Exited,

  -- -------------------------------------------------------------------------
  -- Derived: Age group
  -- Binned into 5 standard demographic bands.
  -- Used as segmentation axis in downstream analysis.
  -- -------------------------------------------------------------------------
  CASE
    WHEN Age < 30 THEN '18-29'
    WHEN Age < 40 THEN '30-39'
    WHEN Age < 50 THEN '40-49'
    WHEN Age < 60 THEN '50-59'
    ELSE               '60+'
  END                                                   AS age_group,

  -- -------------------------------------------------------------------------
  -- Derived: Credit score tier
  -- Based on standard FICO score segmentation used in retail banking.
  -- -------------------------------------------------------------------------
  CASE
    WHEN CreditScore >= 800 THEN 'Excellent'
    WHEN CreditScore >= 740 THEN 'Very Good'
    WHEN CreditScore >= 670 THEN 'Good'
    WHEN CreditScore >= 580 THEN 'Fair'
    ELSE                         'Poor'
  END                                                   AS credit_tier,

  -- -------------------------------------------------------------------------
  -- Derived: Balance segment
  -- Fixed thresholds chosen to reflect typical retail banking product tiers.
  -- Zero balance is treated as a distinct behavioral segment — customers
  -- with $0 made an active or passive choice to hold nothing, which is
  -- analytically different from a low positive balance.
  -- Note: The Low (<50K) segment has ~75 customers due to the bimodal
  -- distribution of balances in this dataset (large zero cluster, then
  -- most non-zero balances starting around 50K+). This is a data
  -- characteristic, not a segmentation error.
  -- -------------------------------------------------------------------------
  CASE
    WHEN Balance = 0        THEN 'No Balance'
    WHEN Balance < 50000    THEN 'Low'
    WHEN Balance < 100000   THEN 'Mid'
    WHEN Balance < 150000   THEN 'High'
    ELSE                         'Very High'
  END                                                   AS balance_segment,

  -- -------------------------------------------------------------------------
  -- Derived: Tenure segment
  -- Groups customers by length of relationship with the bank.
  -- -------------------------------------------------------------------------
  CASE
    WHEN Tenure <= 2  THEN 'New (0-2y)'
    WHEN Tenure <= 5  THEN 'Established (3-5y)'
    ELSE                   'Loyal (6y+)'
  END                                                   AS tenure_segment,

  -- -------------------------------------------------------------------------
  -- Derived: Readable labels for binary flags
  -- CASE WHEN used instead of IF() for ANSI SQL portability across
  -- database platforms (Postgres, Snowflake, SQL Server, BigQuery).
  -- -------------------------------------------------------------------------
  CASE WHEN HasCrCard = 1      THEN 'Yes' ELSE 'No' END AS has_credit_card,
  CASE WHEN IsActiveMember = 1 THEN 'Yes' ELSE 'No' END AS is_active_member,
  CASE WHEN Exited = 1         THEN 'Churned' ELSE 'Retained' END AS churn_status

FROM `churn-project-492519.churn_dataset.Churn_Modelling`;


-- =============================================================================
-- SECTION 3: vw_segment_stats
-- Segment-level aggregation view (15 rows: Geography x Age Group).
-- Pre-aggregates all metrics needed for Power BI KPI cards and
-- segment-level visuals. Power BI connects to this view directly.
-- Keeping aggregation in BigQuery follows warehouse-first architecture —
-- all static computation stays in the warehouse, Power BI visualizes only.
-- =============================================================================

CREATE OR REPLACE VIEW `churn-project-492519.churn_dataset.vw_segment_stats` AS

SELECT
  geography,
  age_group,
  COUNT(*)                                              AS total_customers,
  COUNTIF(Exited = 1)                                   AS churned_customers,
  ROUND(COUNTIF(Exited = 1) / COUNT(*) * 100, 1)       AS churn_rate_pct,

  -- Total balance lost: sum of balances of churned customers only
  ROUND(SUM(CASE WHEN Exited = 1
            THEN Balance ELSE 0 END), 0)                 AS lost_balance,

  -- Average balance per churned customer within segment
  ROUND(AVG(CASE WHEN Exited = 1
            THEN Balance ELSE NULL END), 0)               AS avg_lost_balance,

  -- Total balance of all customers in segment (churned + retained)
  -- Used for forward-looking exposure analysis
  ROUND(SUM(Balance), 0)                                AS total_segment_balance,

  -- Average balance across all customers in segment
  ROUND(AVG(Balance), 0)                                AS avg_segment_balance

FROM `churn-project-492519.churn_dataset.vw_churn_segmented`
GROUP BY geography, age_group;


-- =============================================================================
-- SECTION 4: vw_segment_priority
-- Retention priority scoring view.
-- Extends vw_segment_stats with quadrant assignment, action labels,
-- priority ranking, and a composite sort key for Power BI.
--
-- BENCHMARK METHODOLOGY:
--   Churn rate threshold  → median segment churn rate
--                           Median chosen over average because Germany 50-59
--                           at 70% churn is a significant outlier that would
--                           pull the average threshold too high (27.49%),
--                           incorrectly excluding genuinely risky segments
--                           like France 40-49 (25.5%) from the urgent group.
--                           Median gives a more representative threshold of
--                           24.4% across the 15 segments.
--
--   Lost balance threshold → average segment lost balance
--                            Average chosen here because the lost balance
--                            distribution across segments is more balanced
--                            than churn rate. Average represents the expected
--                            financial damage per segment — segments above
--                            this threshold cause above-average financial harm.
--                            Computed at segment level (not customer level)
--                            to stay consistent with the unit of analysis.
--
-- QUADRANT DEFINITIONS:
--   High churn · High balance → Call first  (quadrant_order = 1)
--   High churn · Low balance  → Monitor     (quadrant_order = 2)
--   Low churn  · High balance → Protect     (quadrant_order = 3)
--   Low churn  · Low balance  → Healthy     (quadrant_order = 4)
--
-- PRIORITIZATION LOGIC:
--   Lost balance was used as the primary ranking metric within quadrants
--   rather than a composite index, because lost balance naturally combines
--   both churn likelihood and financial exposure — segments with high churn
--   AND high balances produce the highest lost balance figures organically.
--   A normalized composite index would reconstruct the same information
--   with added complexity and less intuitive explainability.
-- =============================================================================

CREATE OR REPLACE VIEW `churn-project-492519.churn_dataset.vw_segment_priority` AS

-- -----------------------------------------------------------------------------
-- CTE 1: segment_stats
-- Aggregates raw customer data to Geography x Age Group level.
-- Produces the 15 segments that form the basis of all priority scoring.
-- -----------------------------------------------------------------------------
WITH segment_stats AS (
  SELECT
    geography,
    age_group,
    COUNT(*)                                            AS total_customers,
    COUNTIF(Exited = 1)                                 AS churned_customers,
    ROUND(COUNTIF(Exited = 1) / COUNT(*) * 100, 1)     AS churn_rate_pct,

    -- Total balance lost to churn within this segment
    ROUND(SUM(CASE WHEN Exited = 1
              THEN Balance ELSE 0 END), 0)               AS lost_balance,

    -- Average balance per churned customer within this segment
    ROUND(AVG(CASE WHEN Exited = 1
              THEN Balance ELSE NULL END), 0)             AS avg_lost_balance
  FROM `churn-project-492519.churn_dataset.vw_churn_segmented`
  GROUP BY geography, age_group
),

-- -----------------------------------------------------------------------------
-- CTE 2: churn_benchmark
-- Calculates median churn rate across all 15 segments.
-- PERCENTILE_CONT is a window function — it returns one value per input row.
-- LIMIT 1 is required to extract a single scalar value for the CROSS JOIN.
-- Result: ~24.4% (the 8th value when 15 segments are sorted ascending)
-- -----------------------------------------------------------------------------
churn_benchmark AS (
  SELECT
    ROUND(
      PERCENTILE_CONT(churn_rate_pct, 0.5) OVER(), 1
    )                                                    AS median_churn_rate_benchmark
  FROM segment_stats
  LIMIT 1
),

-- -----------------------------------------------------------------------------
-- CTE 3: balance_benchmark
-- Calculates average lost balance across all 15 segments.
-- Standard aggregate — no window function needed, no LIMIT required.
-- Result: ~$12.37M (average of the 15 segment lost balance totals)
-- -----------------------------------------------------------------------------
balance_benchmark AS (
  SELECT
    ROUND(AVG(lost_balance), 0)                          AS avg_lost_balance_benchmark
  FROM segment_stats
),

-- -----------------------------------------------------------------------------
-- CTE 4: quadrants
-- Joins segment stats with both benchmarks via CROSS JOIN.
-- CROSS JOIN is appropriate here because both benchmark CTEs return
-- exactly one row — producing a single benchmark value applied uniformly
-- to all 15 segments.
-- Assigns each segment to a quadrant and numeric sort order.
-- -----------------------------------------------------------------------------
quadrants AS (
  SELECT
    s.*,
    cb.median_churn_rate_benchmark,
    bb.avg_lost_balance_benchmark,

    -- Quadrant label based on position relative to both benchmarks
    CASE
      WHEN s.churn_rate_pct >= cb.median_churn_rate_benchmark
       AND s.lost_balance   >= bb.avg_lost_balance_benchmark
        THEN 'High churn · High balance'
      WHEN s.churn_rate_pct <  cb.median_churn_rate_benchmark
       AND s.lost_balance   >= bb.avg_lost_balance_benchmark
        THEN 'Low churn · High balance'
      WHEN s.churn_rate_pct >= cb.median_churn_rate_benchmark
       AND s.lost_balance   <  bb.avg_lost_balance_benchmark
        THEN 'High churn · Low balance'
      ELSE
        'Low churn · Low balance'
    END                                                  AS quadrant,

    -- Numeric sort order for downstream sorting (1 = most urgent)
    CASE
      WHEN s.churn_rate_pct >= cb.median_churn_rate_benchmark
       AND s.lost_balance   >= bb.avg_lost_balance_benchmark THEN 1
      WHEN s.churn_rate_pct >= cb.median_churn_rate_benchmark
       AND s.lost_balance   <  bb.avg_lost_balance_benchmark THEN 2
      WHEN s.churn_rate_pct <  cb.median_churn_rate_benchmark
       AND s.lost_balance   >= bb.avg_lost_balance_benchmark THEN 3
      ELSE                                                     4
    END                                                  AS quadrant_order

  FROM segment_stats s
  CROSS JOIN churn_benchmark cb
  CROSS JOIN balance_benchmark bb
)

-- -----------------------------------------------------------------------------
-- FINAL SELECT
-- Output consumed by Power BI.
-- Includes all segment metrics, benchmark reference values for scatter
-- plot reference lines, quadrant classification, plain-English action
-- label, priority rank within urgent group, and composite sort key.
-- -----------------------------------------------------------------------------
SELECT
  geography,
  age_group,
  total_customers,
  churned_customers,
  churn_rate_pct,
  lost_balance,
  avg_lost_balance,

  -- Benchmark values passed to Power BI for dynamic reference line positioning
  -- X-axis constant line: median_churn_rate_benchmark
  -- Y-axis constant line: avg_lost_balance_benchmark
  median_churn_rate_benchmark,
  avg_lost_balance_benchmark,

  -- Quadrant classification and numeric sort order
  quadrant,
  quadrant_order,

  -- Priority rank within Call First segments only, ordered by lost balance
  -- descending. NULL for all other quadrants — rank is not meaningful
  -- outside the urgent group.
  CASE
    WHEN quadrant_order = 1
    THEN RANK() OVER (
           PARTITION BY quadrant_order
           ORDER BY lost_balance DESC)
    ELSE NULL
  END                                                    AS priority_rank,

  -- Plain-English action label used for Power BI conditional formatting
  CASE
    WHEN quadrant = 'High churn · High balance'          THEN 'Call first'
    WHEN quadrant = 'High churn · Low balance'           THEN 'Monitor'
    WHEN quadrant = 'Low churn · High balance'           THEN 'Protect'
    ELSE                                                 'Healthy'
  END                                                    AS action,

  -- Composite sort key for Power BI multi-column sorting.
  -- Encodes quadrant priority (hundreds) + lost balance rank (units)
  -- so a single ascending sort on sort_key produces correct ordering
  -- across all 15 segments simultaneously.
  -- Example: segment with quadrant_order=1, rank=2 → sort_key=2
  --          segment with quadrant_order=2, rank=1 → sort_key=101
  CASE
    WHEN quadrant_order = 1
      THEN RANK() OVER (PARTITION BY quadrant_order ORDER BY lost_balance DESC)
    WHEN quadrant_order = 2
      THEN 100 + RANK() OVER (PARTITION BY quadrant_order ORDER BY lost_balance DESC)
    WHEN quadrant_order = 3
      THEN 200 + RANK() OVER (PARTITION BY quadrant_order ORDER BY lost_balance DESC)
    ELSE
      300 + RANK() OVER (PARTITION BY quadrant_order ORDER BY lost_balance DESC)
  END                                                    AS sort_key

FROM quadrants
ORDER BY quadrant_order ASC, lost_balance DESC;
