-- No substitution query
-- name: get_servers
SELECT hostname
  FROM server;

-- Simple query
-- name: get_server
SELECT *
  FROM server
 WHERE hostname = :hostname;

-- Tempotal time table
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
