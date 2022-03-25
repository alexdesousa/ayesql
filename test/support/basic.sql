-- No substitution query
-- name: get_hostnames
SELECT hostname
  FROM server;

-- Simple query
-- name: get_server_by_hostname
-- docs: Simple query
SELECT *
  FROM server
 WHERE hostname = :hostname;
