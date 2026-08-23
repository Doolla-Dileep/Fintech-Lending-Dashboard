CREATE DATABASE fintech_loan_analytics;
USE fintech_loan_analytics;
select * from raw_loan_data limit 10;
-- Create a clean production table from your raw import
CREATE TABLE clean_loan_data AS 
SELECT * FROM raw_loan_data;

-- 1. Turn OFF Safe Update Mode so MySQL allows dataset cleaning
SET SQL_SAFE_UPDATES = 0;

-- 2. Create the clean production table from your raw import
CREATE TABLE clean_loan_data AS 
SELECT * FROM raw_loan_data;

-- 3. Remove extreme anomalies (ages over 100 or unrealistic employment years)
DELETE FROM clean_loan_data 
WHERE person_age > 100 OR person_emp_length > 60;

-- 4. Handle missing data points (Fix null values in interest rate with the average rate)
UPDATE clean_loan_data
SET loan_int_rate = (SELECT AVG(loan_int_rate) FROM raw_loan_data WHERE loan_int_rate IS NOT NULL)
WHERE loan_int_rate IS NULL;

-- 5. Turn Safe Update Mode back ON for safety
SET SQL_SAFE_UPDATES = 1;

-- 6. Verify that your clean table is ready
SELECT COUNT(*) AS total_clean_records FROM clean_loan_data;


WITH Customer_Segmentation AS (
    -- Step 1: Categorize borrowers into clear income tiers
    SELECT 
        loan_intent,
        loan_status,
        loan_amnt,
        CASE 
            WHEN person_income < 35000 THEN 'Tier 3: Low Income'
            WHEN person_income BETWEEN 35000 AND 75000 THEN 'Tier 2: Middle Income'
            ELSE 'Tier 1: High Income'
        END AS income_bracket
    FROM clean_loan_data
),
Risk_Metrics AS (
    -- Step 2: Calculate total loans, total defaults, and NPA rate per segment
    SELECT 
        income_bracket,
        loan_intent,
        COUNT(*) AS total_loan_applications,
        SUM(loan_amnt) AS total_funded_amount,
        SUM(CASE WHEN loan_status = 1 THEN 1 ELSE 0 END) AS total_defaults,
        ROUND((SUM(CASE WHEN loan_status = 1 THEN 1 ELSE 0 END) / COUNT(*)) * 100, 2) AS default_rate_percentage
    FROM Customer_Segmentation
    GROUP BY income_bracket, loan_intent
)
-- Step 3: Use a Window Function to rank the riskiest loan purposes within each income tier
SELECT 
    income_bracket,
    loan_intent,
    total_loan_applications,
    total_funded_amount,
    total_defaults,
    default_rate_percentage,
    DENSE_RANK() OVER (PARTITION BY income_bracket ORDER BY default_rate_percentage DESC) AS risk_rank_within_tier
FROM Risk_Metrics
ORDER BY income_bracket, risk_rank_within_tier;

