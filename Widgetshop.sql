create schema UC_DAVIS_SQL;

USE uc_davis_sql;

/*
We will answer some of the business answer to understand about data as well as the business.
Questions are as follows.
*/

-- General Analysis

-- SELECT ALL THE ITEMS IN ONE CATEGORY OF ITEMS -- let's pull widget category item
SELECT DISTINCT category FROM items;
/*
Different category items sell on a ecommerce website are as follow: 
Nozzle
Bracket
Switch
Actuator
Cog
Widget
Bearing
Connector
Gear
End Cap
Plate
Bolt
Valve
Sensor
*/

-- 1) list of product related to Widget category.
SELECT id,category,display_name
FROM items
WHERE category='Widget';

-- 2) Calculate the average price of the items in each category.
SELECT category,AVG(list_price) as avg_price
FROM items
GROUP BY category
ORDER BY avg_price DESC;
/*
insight:
- Actuator as the category with the highest average price ($100.279).
- Widget as the second highest ($89.266).
- Plate as the third ($37.99).
*/

-- Count the number of orders per days
SELECT date(created_timestamp) as order_date,COUNT(id) AS total_order_perday
FROM orders
GROUP BY date(created_timestamp)
ORDER BY date(created_timestamp);


-- Create cost buckets or items prices and apply the logic to every item
SELECT id as item_id,
	   list_price,
       CASE WHEN list_price>=0 AND list_price<=25 THEN '$0-$24.99'
            WHEN list_price>=25 AND list_price<=100 THEN  '$25-$100'
            ELSE '$100<' END AS price_bucket
FROM items;

-- For each user, Calculate average number of items per order 
WITH AVG_ITEMS AS (
	SELECT order_id,COUNT(item_id) as items
    FROM line_items
	GROUP BY order_id
)	
SELECT user_id,AVG(items) as AOV_eachuser
FROM orders o
JOIN AVG_ITEMS ai on o.id=ai.order_id
GROUP BY user_id
ORDER BY AOV_eachuser desc;
-- Highest avg order value for each user is 10 by 4 different user.

-- This query could help to make understand about average order value of each user.


-- 3) What is the most common user locale?
-- Understand about locale column- it contain information about language+location separated by _.
SELECT locale,language,location,COUNT(*) AS COUNT
FROM (SELECT locale,
			 substring_index(locale,'_',1) as language,
			 substring_index(locale,'_',-1) as location
	  FROM users) t
GROUP BY locale,language,location
ORDER BY COUNT desc;

-- The most common user locale is en_US, with a count of 421 users.
--------------------------------------------------------------------------------------------
--------------------------------------------------------------------------------------------
/*
what can we find out about the difference between item viewed and view item events?
*/

SELECT DISTINCT EVENT_NAME
FROM events;

/*

output: 
view_item
add_to_cart
checkout_start
login_start
item_view
login_success
 
Queries all distinct event_name values from event table. Saw two names similar:
- view_item
- item_view
This might be due to inconsistencies or change in tracking design.
let's check how often each event type occur
*/

SELECT EVENT_NAME,COUNT(*) AS rowz
FROM events
GROUP BY EVENT_NAME;

/*
Both item_view and view_item wenew_valuere appearing often, so they weren’t just typos or unused.
Now let's check how many user triggered each event
*/
SELECT EVENT_NAME,COUNT(DISTINCT USER_ID) as users
FROM events
GROUP BY EVENT_NAME;

/*
view_items-- has user IDs.
item_views-- has one user IDs.
So it might possible that there are browsing anonymously. or it may be any other reason.
Hence, it need to be verefied from a owner or who have build a website. As it might be for admin use. So it need to be confirmed from them.
let's explore the individual session
*/
SELECT * FROM events order by SESSION_ID,EVENT_TIME;
/*
-> Sessions that had view_item usually came after login success.
-> Sessions with only item_view typically had no login event — the user was anonymous.That might be a admin who have login to check a stock.
*/
SELECT session_id,
       COUNT(*)                                 AS total_events,
       COUNT(DISTINCT event_name)               AS unique_events,
       MAX(CASE WHEN event_name = 'login_success' THEN 1 ELSE 0 END) AS logged_in,
       MAX(CASE WHEN event_name = 'item_view'   THEN 1 ELSE 0 END) AS saw_item_view,
       MAX(CASE WHEN event_name = 'view_item'   THEN 1 ELSE 0 END) AS saw_view_item
FROM events
GROUP BY session_id
ORDER BY session_id;
/*
Takeaway skills:
How to explore event logs
How to think in terms of user journeys and sessions
How to investigate inconsistent or messy event tracking
How to use SQL to answer real-world business questions

When you're exploring events in an analytics table, don't assume similar names mean the same thing. Always investigate:
Are they logged for different types of users (e.g., logged-in vs anonymous)?
Do they differ in data completeness (like user IDs, session IDs)?
Could they be tracking different parts of the user journey?
*/

-------------------------------------------------------------------------------------------------
-------------------------------------------------------------------------------------------------
/*
Exploring field history table:
It's a log of what changed, when it changed, and who changed it. 
Each row represents a change to a single field (column) for a specific item (or record).

Why this table is useful for?
Auditing: Track who changed what and when (e.g., for legal or business compliance).
Rebuilding the past: If a user placed an order on Jan 1, and the price changed on Jan 2, you can look up the old price.
Keeps the items table clean: Instead of tracking every change in the main table, this keeps historical data in a separate table.

Task to do:
For each order, determine what the availability status was for that item at the time of the order.
*/

WITH OrderItemAvailability AS (
    SELECT
        o.id AS order_id,
        o.created_timestamp AS order_created_at,
        li.item_id,
        li.price AS item_ordered_price, 
        ih.field_name,
        ih.new_value AS availability_status,
        ih.changed_timestamp,
        ROW_NUMBER() OVER(
            PARTITION BY o.id, li.item_id
            ORDER BY ih.changed_timestamp DESC
        ) AS rn
    FROM
        orders o
    JOIN
        line_items li ON o.id = li.order_id
    LEFT JOIN
        item_field_history ih ON li.item_id = ih.record_id
                               AND ih.field_name = 'availability'
                               AND ih.changed_timestamp <= o.created_timestamp
)
SELECT
    order_id,
    order_created_at,
    item_id,
    availability_status
FROM
    OrderItemAvailability
WHERE
    rn = 1
ORDER BY
    order_id, item_id;



--------------------------------------------------------------------------------------------------------
--------------------------------------------------------------------------------------------------------
/* normalise and denormalise table.

Denormalising table that has information with the most important and filter out that doesn't really matter.
we will denormalise line_items for quick reporting
1) add item information like item name, category,availability etc;category
*/
CREATE TEMPORARY TABLE Denorm_line_items AS
SELECT li.*,i.display_name,i.category
FROM line_items li
JOIN items i on li.item_id=i.id;

SELECT * FROM Denorm_line_items;

-- Makes it easier to analyze sales by item name/type without joining the items table every time.

---------------------------------------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------------------------------------
-- USER & ORDER BEHAVIOUR
-- Q 2.1: What percent of users have viewed an item?
SELECT DISTINCT(substring_index(email_address,'@',-1)) FROM users;
-- found hypotheticalwigetshop.com as a mailservice, so it might not be a user.
-- it is a good practice to filter the events table that not include hypotheticalwidgetshop.com domain.

with valid_user as (
SELECT USER_ID,EVENT_NAME
FROM events
JOIN users on events.USER_ID=users.id AND email_address NOT LIKE '%hypotheticalwidgetshop.com%'
)
SELECT ROUND(COUNT(DISTINCT USER_ID)*100/(SELECT COUNT(DISTINCT USER_ID) FROM valid_user),2) as percent_user_view_item 
FROM valid_user
WHERE EVENT_NAME = 'view_item';

-- 96% of users have view an item from a app.

-- 2.2 What percentage of total users have placed at least one order.
WITH total_users AS (
    SELECT COUNT(DISTINCT id) AS total_user_count
    FROM users 
    WHERE email_address NOT LIKE '%hypotheticalwidgetshop.com%'
),
users_placed_order AS (
    SELECT COUNT(DISTINCT user_id) AS ordered_user_count
    FROM orders
    JOIN users on orders.user_id=users.id
    WHERE user_id IS NOT NULL AND email_address NOT LIKE '%hypotheticalwidgetshop.com%' -- Exclude potential guest orders if user_id can be NULL
)
SELECT 
    ROUND(100.0 * upo.ordered_user_count / tu.total_user_count, 2) AS percent_users_placed_order
FROM total_users tu, users_placed_order upo;

-- 49.05% of user have placed at least one order from a website.

-- 2.3 How often do users re-order?
-- based on this, we can identify loyal customer who made order frequently from a website.

-- one way to find out a total order by each user_id and arrange them in descending order of total_count. 
-- so first 10,20 are our loyal customer
SELECT user_id,COUNT(*) as total_order
FROM orders
JOIN users on orders.user_id=users.id
WHERE email_address NOT LIKE '%hypotheticalwidgetshop.com%'
GROUP BY user_id
ORDER BY total_order desc LIMIT 10;

-- 2.4  Are there any items that have never been purchased?
with item_zero_sales as (
SELECT items.id
FROM items 
LEFT JOIN line_items on items.id=line_items.item_id 
WHERE line_items.item_id IS NULL
)
SELECT display_name
FROM items
JOIN item_zero_sales ON items.id=item_zero_sales.id;


-- there is one item that have zero sales- Polymer Plate Entire Assembly. 

-- 2.5 What is the most popular category of item, based on the number of purchases?
SELECT category,count(line_items.id) as total_purchase,ROUND(SUM(price),2) as total_amount
FROM line_items
JOIN items on line_items.item_id=items.id
GROUP BY category
ORDER BY total_purchase desc,total_amount desc;

-- popular category which is purchase for more time are: 
-- Actuator	1205	123637.04
-- Cog	    1183	21898.93
-- Sensor	1179	46569.58
-- Switch	1152	31240.5

------------------------------------------------------------------------------------------------------------------
/*
Sometimes metrics can be misleading or gamed if we are not careful beacause:
- it may contain bot user, test user, admin user etc.
- it must ensure that metric reflect the true goal and intent.
*/

-- Design a metric to know total new user signup.(input metric)
SELECT DISTINCT(substring_index(email_address,'@',-1)) FROM users;

-- design a metric that calculate number of item purchased
WITH item_purchased as (
SELECT item_id,display_name,number_items_purchased
FROM (SELECT item_id,count(id) as number_items_purchased
	  FROM line_items
      GROUP BY item_id) t
JOIN items on t.item_id=items.id
ORDER BY number_items_purchased desc
),
-- organic Valve Subassembly viewed maximum time. Value is 58. It is purchased 58 times. 

-- Design a metric to know total number of item view by user.
view_items as (
SELECT *
FROM events
WHERE EVENT_NAME='view_item'
),
item_viewed as (
SELECT record_id,COUNT(*) AS number_items_viewed
FROM view_items
JOIN users on view_items.user_id=users.id 
JOIN item_field_history on users.id=item_field_history.changed_by_user_id
GROUP BY record_id
)
SELECT
  item_purchased.item_id,
  item_purchased.display_name,
  item_viewed.number_items_viewed,
  item_purchased.number_items_purchased,
  ROUND(1.0 * item_purchased.number_items_purchased / item_viewed.number_items_viewed, 2) AS conversion_rate
FROM item_purchased
JOIN item_viewed on item_purchased.item_id=item_viewed.record_id;

-- “Steel Bolt Replacement Part has a high conversion rate of ~80%, indicating strong buyer intent once viewed.”
-- User who view this product are likely to buy it. 

-- time-based grouping
WITH real_users AS (
  SELECT id AS user_id
  FROM users
  WHERE email_address NOT LIKE '%@hypotheticalwidgetshop.com'
),
view_events AS (
  SELECT 
    e.id AS event_id,
    e.USER_ID,
    DATE(EVENT_TIME) AS event_date
  FROM events e
  JOIN real_users r ON e.user_id = r.user_id
  WHERE e.EVENT_NAME = 'view_item'
),
daily_item_views AS (
  SELECT 
    event_date,
    COUNT(event_id) AS item_viewed
  FROM view_events
  GROUP BY event_date
)
SELECT * FROM daily_item_views;

------------------------------------------------------------------------------------------------------
------------------------------------------------------------------------------------------------------
-- Reporting: transforming raw data into structured summaries,metrics,visual.
-- 1. Count the number of distinct user who view an item. 
-- 2. Report on it daily using weekly and montly windows.
-- 3. Discuss how and if we can segment metric.

SELECT COUNT(DISTINCT USER_ID) AS user_view_item
FROM events
WHERE EVENT_NAME='view_item';
-- 548 User view an items from a website.

WITH user_view_item as (
SELECT *
FROM events
WHERE EVENT_NAME='view_item'
)
SELECT dates.ds,COUNT(DISTINCT USER_ID) AS total_user_view_item
FROM user_view_item
JOIN dates ON DATE(user_view_item.EVENT_TIME) <= dates.ds AND DATE(user_view_item.EVENT_TIME) > dates.day_ago_7
GROUP BY dates.ds
ORDER BY dates.ds;

-- with the technique called rolling window, a distinct user who view an items is being found in the span of period of 7 days. 

--------------------------------------------------------------------------------------------------------------------------
-- Funnel & Activation analysis
--------------------------------------------------------------------------------------------------------------------------
-- funnel : It is to calculate the group who have successfully completed the task. Who have succedded in it.
-- Q) 3.1 What percentage of login attempts are successful within a 5-minute window from the login_start event
-- login_start
-- login_success
WITH start_event AS (
    SELECT SESSION_ID, EVENT_TIME
    FROM events
    WHERE EVENT_NAME = 'login_start'
),
outcome_event AS (
    SELECT SESSION_ID, EVENT_TIME
    FROM events
    WHERE EVENT_NAME = 'login_success'
),
session_login_times AS (
    SELECT
        se.SESSION_ID,
        MIN(se.EVENT_TIME) AS first_login_attempt_time,
        MIN(oe.EVENT_TIME) AS first_login_success_time
    FROM
        start_event se
    LEFT JOIN
        outcome_event oe ON se.SESSION_ID = oe.SESSION_ID
                           AND oe.EVENT_TIME >= se.EVENT_TIME
                           AND oe.EVENT_TIME <= DATE_ADD(se.EVENT_TIME, INTERVAL 5 MINUTE)
    GROUP BY
        se.SESSION_ID
)
SELECT
    COUNT(SESSION_ID) AS total_login_attempts,
    COUNT(first_login_success_time) AS total_successful_logins_within_5_min,
    ROUND(100 * COUNT(first_login_success_time) / COUNT(SESSION_ID), 2) AS overall_login_success_percent_within_5_min
FROM
    session_login_times;
    
-- 43.56% of user could able to successfully login into website withnin 5 min. Developer seriously have to look into this situation.
-- As this create bad impression on a website.


-- Q) 3.2 What percentage of login attempts are successful over time (e.g., daily or weekly success rates)?
WITH start_event AS (
    SELECT SESSION_ID, EVENT_TIME
    FROM events
    WHERE EVENT_NAME = 'login_start'
),
outcome_event AS (
    SELECT SESSION_ID, EVENT_TIME
    FROM events
    WHERE EVENT_NAME = 'login_success'
),
session_login_times AS (
    SELECT
        se.SESSION_ID,
        MIN(se.EVENT_TIME) AS first_login_attempt_time,
        MIN(oe.EVENT_TIME) AS first_login_success_time
    FROM
        start_event se
    LEFT JOIN
        outcome_event oe ON se.SESSION_ID = oe.SESSION_ID
                           AND oe.EVENT_TIME >= se.EVENT_TIME
                           AND oe.EVENT_TIME <= DATE_ADD(se.EVENT_TIME, INTERVAL 5 MINUTE)
    GROUP BY
        se.SESSION_ID
)
SELECT
    DATE_FORMAT(first_login_attempt_time, '%Y-%U') AS login_week, -- '%U' for Sunday as first day of week, '%V' for Monday
    MIN(DATE(first_login_attempt_time)) AS week_start_date, 
    COUNT(SESSION_ID) AS total_login_attempts,
    COUNT(first_login_success_time) AS total_successful_logins,
    ROUND(100.0 * COUNT(first_login_success_time) / COUNT(SESSION_ID), 2) AS login_success_percent
FROM
    session_login_times
GROUP BY
    login_week
ORDER BY
    login_week;

-- This insight indicate about the system stability. Like a app is still not efficience because successfull login is below 50 for majority of the week.


-- What % of sessions that view a product end up adding something to the cart?
-- Start Event: view_item
-- Success Event: add_to_cart
-- Entity: session_id or user_id

SELECT DISTINCT EVENT_NAME FROM events;
SELECT MIN(EVENT_TIME),MAX(EVENT_TIME) FROM events; -- min_date 2024-03-02 07:24:26   max_date 2025-03-19 21:40:28

WITH start_event as (
SELECT SESSION_ID,DATE(EVENT_TIME) AS view_date 
FROM events
WHERE EVENT_NAME='view_item'
GROUP BY SESSION_ID,DATE(EVENT_TIME)
),
success_event as (
SELECT SESSION_ID,DATE(EVENT_TIME) AS cart_date
FROM events
WHERE EVENT_NAME='add_to_cart'
GROUP BY SESSION_ID,DATE(EVENT_TIME)
),
session_added_cart as (
SELECT start_event.view_date,
	   COUNT(DISTINCT start_event.SESSION_ID) as session_with_view,
       COUNT(DISTINCT success_event.SESSION_ID) as session_with_cart
FROM start_event
LEFT JOIN success_event on start_event.SESSION_ID=success_event.SESSION_ID
GROUP BY start_event.view_date
),
final_table as (
SELECT 
  view_date,
  session_with_view,
  session_with_cart,
  ROUND(1.0 * session_with_cart / session_with_view, 2) AS view_to_cart_pct
FROM session_added_cart
ORDER BY view_date
)
SELECT AVG(view_to_cart_pct) FROM final_table;

-- 85% of users who view an item added an item to the cart.



-- calculate the rolling average for 7 days
/*rolling_avg AS (
SELECT dates.ds AS report_date,
       AVG(final_table.view_to_cart_pct) AS rolling_average_7days
FROM dates 
JOIN final_table on final_table.view_date<=dates.ds AND final_table.view_date>dates.day_ago_7 -- last 7 days, excluding the 8th day
GROUP BY dates.ds
)
SELECT * FROM rolling_avg
ORDER BY report_date;
*/


------------------------------------------------------------------------------------------------------
------------------------------------------------------------------------------------------------------
-- Retention: It is a way to track a user who have engage yesterday, how likely it is to engage today/monthly/yearly. 
-- cohort based retention: create a group of user who have started on same day/month/year and track how they behave over a time. 

-- Q) tracking day over day item viewing retention of user. 
-- starting_event: viewing an item on given day
-- outcome_event:  viewing an item on following day
-- tracking:       logged in users

WITH starting_event as (
SELECT USER_ID,DATE(EVENT_TIME) as view_date
FROM events
WHERE EVENT_NAME='view_item'
GROUP BY USER_ID,DATE(EVENT_TIME)
),
retained_users as (
SELECT s1.USER_ID,s1.view_date as curr_date,s2.view_date as following_date
FROM starting_event s1
JOIN starting_event s2 on s1.USER_ID=s2.USER_ID AND s2.view_date = DATE_ADD(s1.view_date, INTERVAL 1 DAY)
)
SELECT curr_date,
       COUNT(DISTINCT USER_ID) AS retained_users
FROM retained_users
GROUP BY curr_date
ORDER BY curr_date;


-- Day level cohort based retention
WITH user_first_view AS (
  SELECT
    USER_ID,
    MIN(DATE(EVENT_TIME)) AS cohort_date
  FROM events
  WHERE EVENT_NAME = 'view_item'
    AND USER_ID IS NOT NULL
  GROUP BY USER_ID
),

user_activity AS (
  SELECT
    USER_ID,
    DATE(EVENT_TIME) AS activity_date
  FROM events
  WHERE EVENT_NAME = 'view_item'
    AND USER_ID IS NOT NULL
),

cohort_activity AS (
  SELECT
    uav.USER_ID,
    ufv.cohort_date,
    uav.activity_date,
    DATEDIFF(uav.activity_date, ufv.cohort_date) AS days_since_signup
  FROM user_activity uav
  JOIN user_first_view ufv
    ON uav.USER_ID = ufv.USER_ID
  WHERE DATEDIFF(uav.activity_date, ufv.cohort_date) >= 0
),

cohort_counts AS (
  SELECT
    cohort_date,
    days_since_signup,
    COUNT(DISTINCT USER_ID) AS active_users
  FROM cohort_activity
  GROUP BY cohort_date, days_since_signup
),

cohort_sizes AS (
  SELECT
    cohort_date,
    COUNT(DISTINCT USER_ID) AS cohort_size
  FROM user_first_view
  GROUP BY cohort_date
)

SELECT
  cc.cohort_date,
  cc.days_since_signup,
  cc.active_users,
  cs.cohort_size,
  ROUND(1.0 * cc.active_users / cs.cohort_size, 2) AS retention_rate
FROM cohort_counts cc
JOIN cohort_sizes cs
  ON cc.cohort_date = cs.cohort_date
ORDER BY cc.cohort_date, cc.days_since_signup;








