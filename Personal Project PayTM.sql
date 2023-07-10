/*SELECT * FROM dbo.fact_transaction_2020 WHERE scenario_id IN ('S2_1', 'S1_118')
SELECT * FROM dim_scenario
SELECT * FROM dim_status
SELECT * FROM dim_platform
SELECT * FROM dim_payment_channel;*/

-- Overview
WITH source_table AS (
    SELECT customer_id
        , transaction_id
        , status_description
        , sce.*
    FROM fact_transaction_2020 fact_20
    JOIN dim_scenario sce ON fact_20.scenario_id = sce.scenario_id
    JOIN dim_status sta ON fact_20.status_id = sta.status_id
)
SELECT transaction_type
    , COUNT (CASE WHEN status_description = 'success' THEN transaction_id END) AS number_success_trans
    , COUNT (transaction_id) AS number_trans
    , FORMAT (COUNT (CASE WHEN status_description = 'success' THEN transaction_id END)*1.0/COUNT (transaction_id), 'F') AS success_type_rate
FROM source_table
GROUP BY transaction_type;


-- 1.1
WITH scenario_table AS (
    SELECT customer_id
        , transaction_id
        , status_description
        , sce.*
    FROM fact_transaction_2020 fact_20
    LEFT JOIN dim_scenario sce ON fact_20.scenario_id = sce.scenario_id
    LEFT JOIN dim_status sta ON fact_20.status_id = sta.status_id
    WHERE transaction_type = 'Top-up account'
)
SELECT scenario_id
    , COUNT (CASE WHEN status_description = 'success' THEN transaction_id END) AS number_success_trans
    , COUNT (transaction_id) AS number_volume
    , FORMAT (COUNT (CASE WHEN status_description = 'success' THEN transaction_id END)*1.0/COUNT (transaction_id), 'F') AS difference_scenario_rate
FROM scenario_table
GROUP BY scenario_id
ORDER BY scenario_id

-- 1.2
WITH platform_table AS (
    SELECT customer_id
        , transaction_id
        , status_description
        , payment_platform
        , MONTH (transaction_time) AS [month]
    FROM fact_transaction_2020 fact_20
    LEFT JOIN dim_scenario sce ON fact_20.scenario_id = sce.scenario_id
    LEFT JOIN dim_status sta ON fact_20.status_id = sta.status_id
    LEFT JOIN dim_platform pla ON fact_20.platform_id = pla.platform_id
    WHERE transaction_type = 'Top-up account'
)
, platform_month AS (
    SELECT payment_platform
        , [month]
        , COUNT (CASE WHEN status_description = 'success' THEN transaction_id END) AS number_success_trans
        , COUNT (transaction_id) AS number_platform_volume
    FROM platform_table
    GROUP BY payment_platform
        , [month]
    -- ORDER BY payment_platform, [month]
)
SELECT *
    , SUM (number_platform_volume) OVER (PARTITION BY [month]) AS total_volume
    , FORMAT (number_success_trans*1.0/SUM (number_platform_volume) OVER (PARTITION BY [month]), 'F') AS difference_platform_rate
FROM platform_month
ORDER BY payment_platform, [month];

-- 1.3
WITH channel_table AS (
    SELECT customer_id
        , transaction_id
        , status_description
        , payment_method
        , MONTH (transaction_time) AS [month]
    FROM fact_transaction_2019 fact_20
    LEFT JOIN dim_scenario sce ON fact_20.scenario_id = sce.scenario_id
    LEFT JOIN dim_status sta ON fact_20.status_id = sta.status_id
    LEFT JOIN dim_payment_channel cha ON fact_20.payment_channel_id = cha.payment_channel_id
    WHERE transaction_type = 'Top-up account'
)
, channel_month AS (
    SELECT payment_method
        , [month]
        , COUNT (CASE WHEN status_description = 'success' THEN transaction_id END) AS number_success_trans
        , COUNT (transaction_id) AS number_channel_volume
    FROM channel_table
    GROUP BY payment_method
        , [month]
    -- ORDER BY payment_method, [month]
)
SELECT *
    , SUM (number_channel_volume) OVER (PARTITION BY [month]) AS total_volume
    , FORMAT (number_success_trans*1.0/SUM (number_channel_volume) OVER (PARTITION BY [month]), 'F') AS difference_channel_rate
FROM channel_month
ORDER BY payment_method, [month]

-- 1.4
WITH status_table AS (
    SELECT customer_id
        , transaction_id
        , status_description
        , MONTH (transaction_time) AS [month]
    FROM fact_transaction_2019 fact_20
    LEFT JOIN dim_scenario sce ON fact_20.scenario_id = sce.scenario_id
    LEFT JOIN dim_status sta ON fact_20.status_id = sta.status_id
    WHERE transaction_type = 'Top-up account' and status_description != 'success'
)
, error_month AS (
    SELECT [month]
        , status_description
        , COUNT (transaction_id) AS number_failed_trans
    FROM status_table
    GROUP BY [month]
        , status_description
)
SELECT *
    , SUM (number_failed_trans) OVER (PARTITION BY [month]) AS total_volume
    , FORMAT (number_failed_trans*1.0 / SUM (number_failed_trans) OVER (PARTITION BY [month]), 'F') AS difference_error_rate
FROM error_month
ORDER BY status_description, [month];

-- 2.1
WITH top_up_table AS (
    SELECT customer_id
        , transaction_id
        , transaction_time
        , status_description
        , LAG (status_description, 1) OVER (PARTITION BY customer_id ORDER BY transaction_id ASC) AS previous_status_description
    FROM fact_transaction_2020 fact_20
    LEFT JOIN dim_scenario sce ON fact_20.scenario_id = sce.scenario_id
    LEFT JOIN dim_status sta ON fact_20.status_id = sta.status_id
    WHERE transaction_type = 'Top-up account'
    -- ORDER BY customer_id, transaction_id
)
, failed_trans_table AS (
    SELECT customer_id
        , transaction_id
        , transaction_time
        , RANK () OVER (PARTITION BY customer_id ORDER BY transaction_time ASC) AS failed_trans_time
        , status_description
        , previous_status_description
    FROM top_up_table
    WHERE status_description = 'success' AND previous_status_description != 'success'
)
SELECT
    COUNT (CASE WHEN failed_trans_time = 1 THEN transaction_id END) AS number_first_failed_trans,
    COUNT (transaction_id) AS number_failed_trans,
    FORMAT (COUNT (CASE WHEN failed_trans_time = 1 THEN transaction_id END)*1.0 / COUNT (transaction_id), 'P') AS failed_trans_pct
FROM failed_trans_table;

-- 2.2
WITH failed_top_up_table AS (
    SELECT customer_id
        , transaction_id
        , fact_20.status_id
        , status_description
    FROM fact_transaction_2020 fact_20
    LEFT JOIN dim_scenario sce ON fact_20.scenario_id = sce.scenario_id
    LEFT JOIN dim_status sta ON fact_20.status_id = sta.status_id
    WHERE transaction_type = 'Top-up account' AND status_description != 'success'
)
SELECT COUNT (CASE WHEN status_id NOT IN ('-10', '-11', '-12', '-13', '-14', '-15') THEN transaction_id END) AS error_cus_number
    , COUNT (transaction_id) AS total_error
    , FORMAT (COUNT (CASE WHEN status_id NOT IN ('-10', '-11', '-12', '-13', '-14', '-15') THEN transaction_id END) *1.0 / COUNT (transaction_id), 'P') AS error_cus_pct
FROM failed_top_up_table;

-- 2.3
WITH promo_table AS (
    SELECT customer_id
        , transaction_id
        , promotion_id
        , transaction_type
        , IIF (promotion_id <> '0', 'is_promo', 'non_promo') AS promo_type
        , MONTH (transaction_time) AS [month]
    FROM fact_transaction_2020 fact_20
    LEFT JOIN dim_scenario sce ON fact_20.scenario_id = sce.scenario_id
    WHERE transaction_type = 'Top-up account' AND status_id = 1
)
SELECT [month]
    , COUNT (CASE WHEN promo_type = 'is_promo' THEN transaction_id END) AS number_promo_trans
    , COUNT (transaction_id) AS number_success_trans
    , FORMAT (COUNT (CASE WHEN promo_type = 'is_promo' THEN transaction_id END)*1.0 /COUNT (transaction_id), 'P') AS promo_trans_pct
FROM promo_table
GROUP BY [month]
ORDER BY [month];