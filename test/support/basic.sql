-- No substitution query
-- name: get_hostnames
SELECT hostname
  FROM server;

-- Simple query
-- name: get_server_by_hostname
SELECT *
  FROM server
 WHERE hostname = :hostname;
