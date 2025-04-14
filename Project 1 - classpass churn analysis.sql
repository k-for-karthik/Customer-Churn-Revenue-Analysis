-- Database creation
create database classpass

-- table creation
CREATE TABLE classpass.churn (
    customer_id INT PRIMARY KEY,
    signup_date DATE,
    age_group VARCHAR(10),
    location VARCHAR(50),
    segment VARCHAR(20),
    churn_flag TINYINT(1),
    churn_date DATE NULL,
    plan_type VARCHAR(20),
    plan_price DECIMAL(5,2),
    contract_duration VARCHAR(10),
    discount_applied DECIMAL(5,2),
    last_login_date DATE NULL,
    total_logins INT,
    avg_session_duration DECIMAL(5,2),
    features_used_count INT,
    payment_status VARCHAR(20),
    last_payment_date DATE NULL,
    outstanding_balance DECIMAL(7,2),
    total_spent DECIMAL(10,2),
    random_notes TEXT NULL,
    survey_response VARCHAR(20) NULL,
    timestamp DATETIME
);

-- checking the table is properly imported
select *
from classpass.churn
limit 10

-- to check the count of rows
SELECT COUNT(*) FROM classpass.churn;

-- removing unwanted fields
alter table classpass.churn
drop column random_notes

alter table classpass.churn
drop column timestamp

alter table classpass.churn
drop column survey_response

-- to check the null values in the important fields
SELECT 
    SUM(CASE WHEN customer_id IS NULL THEN 1 ELSE 0 END) AS null_customers,
    SUM(CASE WHEN signup_date IS NULL THEN 1 ELSE 0 END) AS null_signup_date,
    SUM(CASE WHEN plan_type IS NULL THEN 1 ELSE 0 END) AS null_plan_type,
    SUM(CASE WHEN plan_price IS NULL THEN 1 ELSE 0 END) AS null_plan_price,
    SUM(CASE WHEN payment_status IS NULL THEN 1 ELSE 0 END) AS null_payment_status
FROM classpass.churn;

-- Data Cleaning and EDA
select churn_flag , count(*) as count
from classpass.churn
group by churn_flag

select count(*) as null_churn_dates
from classpass.churn
where churn_date is null

update classpass.churn
set churn_date = Null
where churn_date = 0000-00-00

select count(*) as mismatched_rows
from classpass.churn
where churn_flag = 1 and churn_date is null

update classpass.churn
set churn_flag = 0
where churn_flag = 1 and churn_date is null

select churn_flag,count(*)
from classpass.churn
group by churn_flag

select customer_id , count(*)
from classpass.churn
group by customer_id
having count(*) > 1

select distinct plan_type , count(*)
from classpass.churn
group by plan_type
order by count(*) desc

Select distinct plan_price , count(*)
from classpass.churn
group by plan_price
order by plan_price

update classpass.churn
set plan_type = 'Premium'
where plan_type = 'Premiumm'

select min(avg_session_duration) as min_duration,
	   max(avg_session_duration) as max_duration
from classpass.churn

select distinct payment_status,count(*)
from classpass.churn
group by payment_status

select
	date_format(churn_date , '%Y-%m') as churn_month,
    count(*) as churned_customers
from classpass.churn
where churn_flag = 1
group by churn_month
order by churn_month

select
	date_format(signup_date,'%Y-%m') as signup_month,
    count(*) as new_signups
from classpass.churn
group by signup_month
order by signup_month

with customer_base as(
	select
		date_format(churn_date, '%Y-%m') as churn_month,
        count(*) as churned_customers
	from classpass.churn
    where churn_flag = 1
    group by churn_month
),
signup_base as (
	select
		date_format(signup_date , '%Y-%m') as signup_month,
        count(*) as new_signups
	from classpass.churn
    group by signup_month
),
running_totals as (
	select
		sb.signup_month as month,
        sb.new_signups,
        coalesce(cb.churned_customers , 0) as churned_customers,
        sum(sb.new_signups) over (order by sb.signup_month)
        - sum(coalesce(cb.churned_customers , 0)) over (order by sb.signup_month) as total_customers_at_start
	from signup_base as sb
    left join customer_base as cb on sb.signup_month = cb.churn_month
)
select
	month,
    new_signups,
    churned_customers,
    total_customers_at_start,
    round((churned_customers / nullif(total_customers_at_start,0)) * 100,2) as churn_rate
from running_totals

select
	plan_type,
    count(*) as total_customers,
    sum(case when churn_flag = 1 then 1 else 0 end) as churned_customers,
    round((sum(case when churn_flag = 1 then 1 else 0 end) / count(*)) * 100,2) as churn_rate
from classpass.churn
group by plan_type
order by churn_rate desc

select
	plan_type,
    round(sum(plan_price),2) as total_revenue_lost,
    count(*) as churned_customers,
    round(avg(plan_price),2) as avg_revenue_lost_per_user
from classpass.churn
where churn_flag = 1
group by plan_type
order by total_revenue_lost desc

-- customers with declining activities
WITH session_activity AS (
    SELECT 
        customer_id, 
        MIN(last_login_date) AS first_session,  
        MAX(last_login_date) AS recent_session,  
        MIN(avg_session_duration) AS oldest_session_duration,  
        MAX(avg_session_duration) AS latest_session_duration
    FROM classpass.churn
    GROUP BY customer_id
),
activity_change AS (
    SELECT 
        customer_id,
        oldest_session_duration,
        latest_session_duration,
        ROUND(((oldest_session_duration - latest_session_duration) / oldest_session_duration) * 100, 2) AS activity_drop_percentage
    FROM session_activity
)
SELECT 
    customer_id, 
    oldest_session_duration, 
    latest_session_duration, 
    activity_drop_percentage
FROM activity_change
WHERE activity_drop_percentage >= 30
ORDER BY activity_drop_percentage DESC

-- customers with multiple failed payments
select
	customer_id,
    count(*) as failed_payment_count
from classpass.churn
where payment_status = 'Failed'
group by customer_id
having failed_payment_count >= 3
order by failed_payment_count desc

-- identifying inactive customers
select
	customer_id,
    last_login_date,
    datediff(curdate(), last_login_date) as days_since_last_login
from classpass.churn
where datediff(curdate(), last_login_date) >=180
order by days_since_last_login desc

-- SQL Based Dashboard
-- View for monthly_churn_rate
CREATE VIEW classpass.churn_monthly_report AS
SELECT 
    DATE_FORMAT(churn_date, '%Y-%m') AS churn_month,
    COUNT(*) AS churned_customers,
    ROUND((COUNT(*) / (SELECT COUNT(*) FROM classpass.churn WHERE churn_flag = 0) * 100), 2) AS monthly_churn_rate
FROM classpass.churn
WHERE churn_flag = 1
GROUP BY churn_month
ORDER BY churn_month;

-- view for churn_by_plan
CREATE VIEW classpass.churn_by_plan AS
SELECT 
    plan_type,
    COUNT(*) AS total_customers,
    SUM(CASE WHEN churn_flag = 1 THEN 1 ELSE 0 END) AS churned_customers,
    ROUND((SUM(CASE WHEN churn_flag = 1 THEN 1 ELSE 0 END) / COUNT(*)) * 100, 2) AS churn_rate
FROM classpass.churn
GROUP BY plan_type
ORDER BY churn_rate DESC;

-- view for revenue_lost_report
CREATE VIEW classpass.revenue_lost_report AS
SELECT 
    plan_type,
    ROUND(SUM(plan_price), 2) AS total_revenue_lost,
    COUNT(*) AS churned_customers,
    ROUND(AVG(plan_price), 2) AS avg_revenue_lost_per_user
FROM classpass.churn
WHERE churn_flag = 1
GROUP BY plan_type
ORDER BY total_revenue_lost DESC;

-- view for inactive_customers_report
CREATE VIEW classpass.inactive_customers_report AS
SELECT 
    COUNT(*) AS inactive_customers
FROM classpass.churn
WHERE DATEDIFF(CURDATE(), last_login_date) >= 180;

-- view for monthly_revenue_trends
CREATE VIEW classpass.monthly_revenue_trend AS
SELECT 
    DATE_FORMAT(signup_date, '%Y-%m') AS revenue_month,
    SUM(plan_price) AS total_revenue
FROM classpass.churn
WHERE churn_flag = 0 -- Only active users contribute to revenue
GROUP BY revenue_month
ORDER BY revenue_month;

-- Customer Lifetime Value (CLV) Calculation
CREATE VIEW classpass.customer_lifetime_value AS
SELECT 
    plan_type,
    ROUND(AVG(plan_price), 2) AS avg_revenue_per_user,
    ROUND(AVG(DATEDIFF(churn_date, signup_date)) / 30, 2) AS avg_customer_lifespan_months,
    ROUND(AVG(plan_price) * (AVG(DATEDIFF(churn_date, signup_date)) / 30), 2) AS estimated_CLV
FROM classpass.churn
WHERE churn_flag = 1 -- Only churned users are considered for CLV
GROUP BY plan_type
ORDER BY estimated_CLV DESC;

-- Stored procedure for full retention report
DROP PROCEDURE IF EXISTS classpass.retention_dashboard;
DELIMITER $$
CREATE PROCEDURE classpass.retention_dashboard()
BEGIN
    -- Monthly Churn Rate
    SELECT * FROM classpass.churn_monthly_report;

    -- Churn Rate by Plan
    SELECT * FROM classpass.churn_by_plan;

    -- Revenue Lost Due to Churn
    SELECT * FROM classpass.revenue_lost_report;

    -- Inactive Customers
    SELECT * FROM classpass.inactive_customers_report;

    -- Monthly revenue trends
    SELECT * FROM classpass.monthly_revenue_trend;

    -- Customer Lifetime value
    SELECT * FROM classpass.customer_lifetime_value;

END $$
DELIMITER ;

-- Now, to view the full report, simply run
CALL classpass.retention_dashboard();

-- To see the average lifespan of the customers
SELECT 
    plan_type,
    ROUND(AVG(DATEDIFF(churn_date, signup_date)) / 30, 2) AS avg_lifespan_months,
    COUNT(*) AS churned_customers
FROM classpass.churn
WHERE churn_flag = 1  -- Only churned customers
GROUP BY plan_type
ORDER BY avg_lifespan_months DESC;