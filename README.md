# Bank Churn Analysis
### BigQuery · Power BI · SQL

A end-to-end data analytics portfolio project analyzing customer churn at a retail bank. The project identifies which customer segments are churning, quantifies the financial damage, and produces a prioritized retention target list for the bank's retention team.

---

## Table of Contents

- [Business Context](#business-context)
- [Dataset](#dataset)
- [Questions I Set Out to Answer](#questions-i-set-out-to-answer)
- [Tools & Architecture](#tools--architecture)
- [Data Model](#data-model)
- [Methodology](#methodology)
- [Dashboard](#dashboard)
- [Key Findings](#key-findings)
- [Recommendations](#recommendations)
- [Repository Structure](#repository-structure)
- [How to Run](#how-to-run)

---

## Business Context

Customer churn is one of the most expensive problems a retail bank faces. Acquiring a new customer costs significantly more than retaining an existing one — and when high-balance customers leave, the financial impact compounds beyond the simple loss of a relationship.

This project approaches churn not just as a customer count problem but as a **financial exposure problem**. The central question is not only *"who is leaving?"* but *"how much money is walking out the door, and from which segments?"*

The output is a two-page Power BI dashboard designed to be used by a retention team as an operational tool — telling them exactly which customer segments to prioritize and why.

---

## Dataset

**Source:** [Kaggle — Churn Modelling Dataset](https://www.kaggle.com/shrutimechlearn/churn-modelling)

| Column | Description |
|---|---|
| `CustomerId` | Unique customer identifier |
| `Geography` | Country — France, Germany, Spain |
| `Gender` | Male / Female |
| `Age` | Customer age |
| `CreditScore` | Customer credit score |
| `Tenure` | Years as a bank customer |
| `Balance` | Account balance |
| `NumOfProducts` | Number of bank products held |
| `HasCrCard` | Has a credit card (0/1) |
| `IsActiveMember` | Active member status (0/1) |
| `EstimatedSalary` | Estimated annual salary |
| `Exited` | Churned (1) or retained (0) — target variable |

**Size:** 10,000 customers · 14 columns · No missing values

---

## Questions I Set Out to Answer

Before looking at the data, I defined the analytical questions I wanted the dashboard to answer:

1. What is the overall churn rate and what does it mean in financial terms?
2. Which geographies have a disproportionate churn problem?
3. Which customer demographics — age, gender, activity status — are most at risk?
4. Do higher-balance customers churn more than lower-balance ones?
5. Which specific segments should the retention team prioritize first?
6. Are there segments with low churn today that could become tomorrow's risk?

---

## Tools & Architecture

```
Churn_Modelling.csv
        ↓
Google BigQuery
  ├── vw_churn_enriched       — data enrichment & derived dimensions
  ├── vw_segment_stats        — 15-row segment aggregation
  └── vw_segment_priority     — quadrant scoring & retention priority
        ↓
Power BI (Import mode)
  ├── Page 1 — Executive Overview
  └── Page 2 — Risk Segmentation
```

**Why this architecture:**
All static business logic and aggregations live in BigQuery views, keeping Power BI focused purely on visualization. This follows a warehouse-first approach where the BI tool is a presentation layer, not a computation layer.

---

## Data Model

### `vw_churn_enriched`
Enriched version of the raw dataset with derived dimensions added:

| Derived Column | Logic |
|---|---|
| `age_group` | Binned into 5 groups: 18–29, 30–39, 40–49, 50–59, 60+ |
| `credit_tier` | Poor / Fair / Good / Very Good / Excellent |
| `balance_segment` | No Balance / Low / Mid / High / Very High |
| `tenure_segment` | New (0–2y) / Established (3–5y) / Loyal (6y+) |
| `has_credit_card` | Yes / No label |
| `is_active_member` | Yes / No label |
| `churn_status` | Churned / Retained label |

### `vw_segment_stats`
Pre-aggregated to 15 segments (Geography × Age Group) with churn rate, lost balance, and customer counts. Power BI connects to this view for KPI cards and segment-level visuals.

### `vw_segment_priority`
Extends `vw_segment_stats` with quadrant assignment, action labels, and priority ranking. Used for the scatter plot and priority table on page 2.

---

## Methodology

### Segmentation
Segments are defined as **Geography × Age Group** combinations, producing 15 distinct groups. This level of granularity was chosen because it produces statistically meaningful segment sizes (minimum ~120 customers per segment) while remaining actionable — a regional retention manager can act on "German customers aged 40–49" immediately.

Balance segmentation was intentionally kept as a reporting dimension rather than a segmentation axis to avoid creating thin, unreliable segments.

### Risk Priority Index
Rather than building a composite index, the prioritization framework uses a two-step approach:

**Step 1 — Quadrant assignment** classifies each segment into one of four zones based on two benchmarks:
- Churn rate threshold → median segment churn rate (24.4%)
- Lost balance threshold → average segment lost balance ($12.37M)

Median was chosen for churn rate because Germany 50–59's 70% churn rate is a significant outlier that would distort an average threshold. Average was chosen for lost balance because the distribution across segments is more balanced.

**Step 2 — Priority ranking** within the urgent quadrant (High churn · High balance) ranks segments by total lost balance descending, ensuring the financially most damaging segments are called first.

This approach was preferred over a normalized composite index because lost balance already naturally combines both churn likelihood and financial exposure — segments with high churn AND high balance produce the highest lost balance figures organically.

### Quadrant Definitions

| Quadrant | Churn rate | Lost balance | Action |
|---|---|---|---|
| High churn · High balance | ≥ 24.4% | ≥ $12.37M | Call first |
| High churn · Low balance | ≥ 24.4% | < $12.37M | Monitor |
| Low churn · High balance | < 24.4% | ≥ $12.37M | Protect |
| Low churn · Low balance | < 24.4% | < $12.37M | Healthy |

---

## Dashboard

### Page 1 — Executive Overview
Answers the question: *what is happening and who is churning?*

- KPI cards: Total customers, churn rate, total balance, lost balance, lost balance ratio
- Map: Churn rate by geography
- Bar charts: Churn rate by gender, active vs passive members
- Column chart: Churn rate by age group
- Bar chart: Churn rate by balance segment
- Insight cards: Geography finding, engagement finding

### Page 2 — Risk Segmentation
Answers the question: *where is the money going and who do we call first?*

- KPI cards: Total balance, lost balance, lost balance ratio, avg balance churned vs retained
- Scatter plot: Segment priority map — churn rate vs lost balance, bubble size = customers
- Priority table: All 15 segments ranked with conditional formatting by action
- Insight cards: Priority finding, age & balance risk, retention opportunity

---

## Key Findings

**1. Financial scale of churn**
1 in 5 customers churned, removing $186M in deposits — 24% of the bank's total balance portfolio.

**2. Germany is the primary risk geography**
Germany churns at 32.4% — nearly double France (16.2%) and Spain (16.7%) — despite representing only 25% of total customers. German customers account for 3 of the top 4 priority segments.

**3. Age amplifies financial risk**
The 40–59 age band drives 69% of total lost balance despite representing only 37% of customers. Older customers hold larger balances and leave at higher rates — creating a compounding financial risk.

**4. Passive members are twice as likely to churn**
Passive members churn at 26.9% versus 14.3% for active members. Re-engagement of inactive customers is the highest-leverage retention action available.

**5. Higher-balance customers churn more**
Churned customers hold on average $91.1K — 25% more than retained customers at $72.7K. The bank is disproportionately losing its highest-value relationships.

**6. Female customers churn at significantly higher rates**
Female customers churn at 25.1% versus 16.5% for male customers — a 52% higher rate that may signal product or service fit gaps worth investigating.

---

## Recommendations

| Priority | Segment | Action | Rationale |
|---|---|---|---|
| 1 | Germany 40–49 | Immediate retention outreach | $40.1M lost — highest financial damage |
| 2 | Germany 50–59 | Immediate retention outreach | 70% churn rate — highest likelihood |
| 3 | France 40–49 | Immediate retention outreach | $21.6M lost — significant exposure |
| 4 | France 50–59 | Immediate retention outreach | $13.0M lost — above average on both dimensions |
| 5 | All geographies | Passive member re-engagement campaign | 1.9× churn multiplier — broad impact |
| 6 | France & Germany 30–39 | Proactive engagement | $36.8M combined at low churn today — prevent future risk |

---

## Repository Structure

```
bank-churn-analysis/
│
├── README.md
│
├── sql/
│   ├── vw_churn_enriched.sql
│   ├── vw_segment_stats.sql
│   └── vw_segment_priority.sql
│
├── dashboard/
│   ├── bank_churn_analysis.pbix
│   └── bank_churn_analysis.pdf
│
└── data/
    └── Churn_Modelling.csv
```

---

## How to Run

**BigQuery setup:**

1. Create a GCP project and enable BigQuery
2. Upload `Churn_Modelling.csv` to a new dataset named `churn_dataset`
3. Run the SQL files in order:
   ```
   1. vw_churn_enriched.sql
   2. vw_segment_stats.sql
   3. vw_segment_priority.sql
   ```

**Power BI setup:**

1. Open `bank_churn_analysis.pbix`
2. Go to Transform Data → Data Source Settings
3. Update the BigQuery project and dataset connection to your own
4. Refresh the data

Alternatively, view the static export at `dashboard/bank_churn_analysis.pdf`.

---

*Built as a portfolio project to demonstrate end-to-end data analytics skills across SQL, cloud data warehousing, and business intelligence tooling.*
