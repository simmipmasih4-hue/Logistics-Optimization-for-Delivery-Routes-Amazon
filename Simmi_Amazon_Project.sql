create database amazon;
show databases;
use amazon;
show tables;

-- Task 1:
-- 1.1:Identify and delete duplicate Order_ID records.

select * from orders;
select order_id,count(*) from orders group by order_id having count(*) >1;
select * from orders where order_id in (select order_id from orders group by order_id having count(*)>1);
DELETE FROM orders WHERE order_id NOT IN (SELECT min_order_id FROM (SELECT MIN(order_id) AS min_order_id
FROM orders GROUP BY order_id) AS temp_table);

-- 1.2:Replace null Traffic_Delay_Min with the average delay for that route. 

select * from routes;
create table routeaverage (route_id varchar(10),avg_delay int);
select route_id,avg(traffic_delay_min) over (partition by route_id) as avg_delay from routes;
update routes R join routeaverage ra on R.route_id=ra.route_id SET R.Traffic_Delay_Min = ra.avg_delay
WHERE R.Traffic_Delay_Min IS NULL;

-- 1.3: Convert all date columns into YYYY-MM-DD format using SQL functions.
-- Orders table
SELECT 
DATE_FORMAT(Order_Date, '%Y-%m-%d') AS Order_Date,
DATE_FORMAT(Expected_Delivery_Date, '%Y-%m-%d') AS Expected_Delivery_Date,
DATE_FORMAT(Actual_Delivery_Date, '%Y-%m-%d') AS Actual_Delivery_Date
FROM Orders;

SELECT 
DATE_FORMAT(Checkpoint_Time, '%Y-%m-%d') AS Checkpoint_Date
FROM Shipment_Tracking;

-- All date columns were already stored in YYYY-MM-DD format
-- Therefore, no data transformation was required
-- DATE_FORMAT() was used to ensure consistent output format.

-- Task 1.4:Ensure that no Actual_Delivery_Date is before Order_Date (flag such records).

SELECT Order_ID,Order_Date,Actual_Delivery_Date,
CASE WHEN Actual_Delivery_Date < Order_Date THEN 'Invalid'ELSE 'Valid'END AS Delivery_Status FROM Orders;

-- OR
SELECT  *,CASE WHEN Actual_Delivery_Date >= Order_Date THEN 'Valid' ELSE 'Invalid' 
END AS Delivery_Status FROM Orders;

-- We validated delivery dates by comparing Actual_Delivery_Date with Order_Date.
-- Records where delivery occurred before the order date were flagged as Invalid, as they indicate data inconsistencies.

-- Task 2.1: Calculate delivery delay (in days) for each order 
SELECT Order_ID,
DATEDIFF(Actual_Delivery_Date, Order_Date) AS Total_Delivery_Time,
CASE
WHEN DATEDIFF(Actual_Delivery_Date, Order_Date) < 0 THEN 'Invalid'
WHEN DATEDIFF(Actual_Delivery_Date, Order_Date) = 0 THEN 'On-Time'
ELSE 'Delayed'END AS Delivery_Status
FROM Orders;

--  Task2.2 :Find Top 10 delayed routes based on average delay days. 
select route_id,avg(datediff(actual_delivery_date,order_date)) as avg_delay_days from orders
where actual_delivery_date>=order_date group by route_id order by avg_delay_days desc limit 10;

-- Task 2.3: Use window functions to rank all orders by delay within each warehouse. 
select order_id,Warehouse_ID,datediff(actual_delivery_date,order_date) as delivery_delay_days,
dense_rank() over ( partition by Warehouse_ID order by datediff(actual_delivery_date,order_date) desc) 
as delay_rank from orders where actual_delivery_date>= order_date;

-- Task 3.1 : For each route, calculate: 
-- 1:Average delivery time (in days). 2:Average traffic delay.3:Distance-to-time efficiency ratio: Distance_KM / Average_Travel_Time_Min. 

SELECT r.Route_ID,
ROUND(AVG(DATEDIFF(o.Actual_Delivery_Date, o.Order_Date)),2) AS Avg_Delivery_Time_Days,
ROUND(AVG(r.Traffic_Delay_Min),2) AS Avg_Traffic_Delay_Min,
ROUND(AVG(r.Distance_KM )/AVG( r.Average_Travel_Time_Min),2) AS Efficiency_Ratio
FROM Orders o JOIN Routes r ON o.Route_ID = r.Route_ID
WHERE o.Actual_Delivery_Date >= o.Order_Date GROUP BY r.Route_ID;

-- Task 3.2 :Identify 3 routes with the worst efficiency ratio.
SELECT r.Route_ID,ROUND(MAX(r.Distance_KM) / MAX(r.Average_Travel_Time_Min), 2) AS Efficiency_Ratio
FROM Orders o JOIN Routes r ON o.Route_ID = r.Route_ID GROUP BY r.Route_ID ORDER BY Efficiency_Ratio LIMIT 3;

-- Task 3.3 :Find routes with >20% delayed shipments. 

SELECT Route_ID,COUNT(*) AS Total_Orders,SUM(DATEDIFF(Actual_Delivery_Date, Order_Date) > 0) AS Delayed_Orders,
ROUND(SUM(DATEDIFF(Actual_Delivery_Date, Order_Date) > 0) * 100.0 / COUNT(*),2) AS Delay_Percentage
FROM Orders WHERE Actual_Delivery_Date >= Order_Date GROUP BY Route_ID HAVING Delay_Percentage > 20;

-- Task 4: Warehouse Performance
-- 4.1: Find the top 3 warehouses with the highest average processing time. 
SELECT Warehouse_ID,ROUND(AVG(Processing_Time_Min), 2) AS Avg_Processing_Time_Min
FROM Warehouses GROUP BY Warehouse_ID ORDER BY Avg_Processing_Time_Min DESC LIMIT 3;

-- 4.2 : Calculate total vs. delayed shipments for each warehouse. 

select o.Warehouse_ID,count(*) as total_orders,sum(datediff(o.Actual_Delivery_Date,
o.Order_Date)>0) as delayed_orders from orders o where 
o.actual_delivery_date >= o.order_date group by o.warehouse_id;

-- 4.3:Use CTEs to find bottleneck warehouses where processing time > global average. 
WITH Warehouse_Avg AS (SELECT o.Warehouse_ID,
AVG(DATEDIFF(o.Actual_Delivery_Date, o.Order_Date)) AS Avg_Time FROM Orders o
WHERE o.Actual_Delivery_Date >= o.Order_Date GROUP BY o.Warehouse_ID),
Global_Avg AS (SELECT AVG(Avg_Time) AS Overall_Avg FROM Warehouse_Avg)
SELECT w.Warehouse_ID,ROUND(w.Avg_Time, 2) AS Avg_Time
FROM Warehouse_Avg w, Global_Avg g WHERE w.Avg_Time > g.Overall_Avg;

-- 4.4 Rank warehouses based on on-time delivery percentage. 

SELECT o.Warehouse_ID,ROUND((SUM(DATEDIFF(o.Actual_Delivery_Date, o.Order_Date) = 0)* 100.0)
 / COUNT(*), 2)AS On_Time_Percentage,
DENSE_RANK() OVER (ORDER BY (SUM(DATEDIFF(o.Actual_Delivery_Date, o.Order_Date) = 0) * 1.0)
/ COUNT(*) DESC) AS Rank_Warehouse
FROM Orders o WHERE o.Actual_Delivery_Date >= o.Order_Date GROUP BY o.Warehouse_ID;

-- Task 5: Delivery Agent Performance
-- 5.1: Rank agents (per route) by on-time delivery percentage  
SELECT o.Route_ID,d.Agent_ID,
ROUND((SUM(DATEDIFF(o.Actual_Delivery_Date, o.Order_Date) = 0) * 100.0) / COUNT(*), 2)
AS On_Time_Percentage,
DENSE_RANK() OVER (PARTITION BY o.Route_ID ORDER BY 
(SUM(DATEDIFF(o.Actual_Delivery_Date, o.Order_Date) = 0) * 1.0) / COUNT(*) DESC) 
AS Agent_Rank FROM Orders o JOIN Delivery_Agents d ON o.Route_ID = d.Route_ID
WHERE o.Actual_Delivery_Date >= o.Order_Date GROUP BY o.Route_ID, d.Agent_ID;

-- 5.2:Find agents with on-time % < 80%.
SELECT d.Agent_ID,
ROUND((SUM(DATEDIFF(o.Actual_Delivery_Date, o.Order_Date) = 0) * 100.0) / COUNT(*), 2) AS On_Time_Percentage
FROM Orders o JOIN Delivery_Agents d ON o.Route_ID = d.Route_ID
WHERE o.Actual_Delivery_Date >= o.Order_Date GROUP BY d.Agent_ID HAVING On_Time_Percentage < 80;

-- 5.3: Compare average speed of top 5 vs bottom 5 agents using subqueries.
SELECT 'Top 5 Agents' AS Category,AVG(Avg_Speed) AS Avg_Speed
FROM (SELECT d.Agent_ID,AVG(r.Distance_KM / r.Average_Travel_Time_Min) AS Avg_Speed
FROM Orders o JOIN Delivery_Agents d ON o.Route_ID = d.Route_ID
JOIN Routes r ON o.Route_ID = r.Route_ID GROUP BY d.Agent_ID ORDER BY Avg_Speed DESC LIMIT 5) AS Top_Agents
UNION
SELECT 'Bottom 5 Agents' AS Category,AVG(Avg_Speed) AS Avg_Speed
FROM (SELECT d.Agent_ID,AVG(r.Distance_KM / r.Average_Travel_Time_Min) AS Avg_Speed
FROM Orders o JOIN Delivery_Agents d ON o.Route_ID = d.Route_ID JOIN Routes r ON o.Route_ID = r.Route_ID
GROUP BY d.Agent_ID ORDER BY Avg_Speed LIMIT 5) AS Bottom_Agents;

SELECT d.Agent_ID,AVG(r.Distance_KM / r.Average_Travel_Time_Min) AS Avg_Speed
FROM Orders o JOIN Delivery_Agents d ON o.Route_ID = d.Route_ID
JOIN Routes r ON o.Route_ID = r.Route_ID GROUP BY d.Agent_ID ORDER BY Avg_Speed DESC LIMIT 5;

SELECT d.Agent_ID,AVG(r.Distance_KM / r.Average_Travel_Time_Min) AS Avg_Speed
FROM Orders o JOIN Delivery_Agents d ON o.Route_ID = d.Route_ID
JOIN Routes r ON o.Route_ID = r.Route_ID GROUP BY d.Agent_ID ORDER BY Avg_Speed LIMIT 5;

-- Task 6: Shipment Tracking Analytics 
-- 6.1: For each order, list the last checkpoint and time. 
SELECT Order_ID,MAX(Checkpoint_Time) AS Last_Checkpoint_Time
FROM Shipment_Tracking GROUP BY Order_ID;

-- 6.2:Find the most common delay reasons (excluding None).
SELECT Delay_Reason,COUNT(*) AS Frequency
FROM Shipment_Tracking
WHERE Delay_Reason IS NOT NULL AND Delay_Reason <> 'None'
GROUP BY Delay_Reason ORDER BY Frequency DESC;

-- 6.3:Identify orders with >2 delayed checkpoints
SELECT Order_ID,COUNT(*) AS Delayed_Checkpoints
FROM Shipment_Tracking WHERE Delay_Reason IS NOT NULL 
AND Delay_Reason <> 'None' GROUP BY Order_ID HAVING COUNT(*) > 2;

-- Task 7: Advanced KPI Reporting
-- 7.1:Average Delivery Delay per Region (Start_Location). 
SELECT r.Start_Location,ROUND(AVG(DATEDIFF
(o.Actual_Delivery_Date, o.Order_Date)), 2) AS Avg_Delivery_Delay
FROM Orders o INNER JOIN Routes r ON o.Route_ID = r.Route_ID
WHERE o.Actual_Delivery_Date >= o.Order_Date 
GROUP BY r.Start_Location;

-- 7.2:On-Time Delivery % = (Total On-Time Deliveries / Total Deliveries) * 100. 
SELECT DATEDIFF(Actual_Delivery_Date, Order_Date) AS diff,COUNT(*)
FROM Orders GROUP BY diff;

SELECT ROUND((SUM(Actual_Delivery_Date <= Expected_Delivery_Date) 
* 100.0) / COUNT(*), 2) AS On_Time_Percentage
FROM Orders WHERE Actual_Delivery_Date >= Order_Date;

-- 7.3:Average Traffic Delay per Route.
SELECT Route_ID,Start_Location,End_Location,
ROUND(AVG(Traffic_Delay_Min), 2) AS Avg_Traffic_Delay_Min
FROM Routes GROUP BY Route_ID, Start_Location, End_Location;

SELECT r.Route_ID,r.Start_Location,
-- KPI 1: Avg Delivery Delay
ROUND(AVG(DATEDIFF(o.Actual_Delivery_Date, o.Order_Date)), 2) AS Avg_Delivery_Delay_Days,
-- KPI 2: On-Time Delivery %
ROUND((SUM(o.Actual_Delivery_Date <= o.Expected_Delivery_Date) * 100.0) / COUNT(*), 2)AS On_Time_Delivery_Percentage,
-- KPI 3: Avg Traffic Delay
ROUND(AVG(r.Traffic_Delay_Min), 2) AS Avg_Traffic_Delay_Min FROM Orders o INNER JOIN Routes r ON o.Route_ID =
r.Route_ID WHERE o.Actual_Delivery_Date >= o.Order_Date GROUP BY r.Route_ID, r.Start_Location;




