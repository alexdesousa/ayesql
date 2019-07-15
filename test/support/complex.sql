-- No substitution query
-- name: get_hostnames
SELECT hostname
  FROM server;

-- Simple query
-- name: get_server_by_hostname
SELECT *
  FROM server
 WHERE hostname = :hostname;

-- IN query
-- name: get_servers_by_hostnames
SELECT *
  FROM server
 WHERE hostname IN ( :hostnames );

-- Query composition (ignore efficiency).
-- name: get_ram_by_hostnames
SELECT s.hostname, m.ram
  FROM metrics AS m
  JOIN server AS s ON s.id = m.server_id
 WHERE s.hostname IN ( :get_servers_by_hostnames );

-- Temporal time table
-- name: get_interval
-- docs: Gets time intervals
SELECT (datetime::date) AS date,
       (datetime::time) AS time
  -- Generate series comment
  FROM  generate_series(
           :start::timestamp,
           :start::timestamp + :interval::interval - :step::interval,
           :step::interval
        ) AS datetime;

-- Function call and in replacement
-- name: get_avg_ram
-- docs: Gets average RAM usage by servers and location
  WITH computed_dates AS (
    :get_interval
  )
  SELECT dates.date AS date,
         dates.time AS time,
         metrics.hostname AS hostname,
         AVG((metrics.metrics->>'ram')::numeric) AS ram
    FROM computed_dates AS dates
         LEFT JOIN server_metrics AS metrics USING(date, time)
   WHERE metrics.hostname IN (:servers)
         AND metrics.location = :location
GROUP BY dates.date, dates.time, metrics.hostname;
