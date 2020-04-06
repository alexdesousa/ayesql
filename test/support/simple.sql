-- name: get_server_by_hostname
SELECT *
  FROM server
 WHERE hostname = :hostname
